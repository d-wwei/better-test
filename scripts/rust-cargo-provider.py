#!/usr/bin/env python3
"""Generic, project-neutral Rust/Cargo source provider for Better Test."""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
from collections import defaultdict, deque
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from hybrid_core import CONTRACT_VERSION, dump_json, load_json, sha256_file, sha256_json


PROVIDER_ID = "better-test.rust-cargo"
PROVIDER_VERSION = "1.0.0"


def run(root: Path, *command: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, cwd=root, text=True, capture_output=True, check=check)


def relpath(path: Path, root: Path) -> str:
    relative = path.resolve().relative_to(root.resolve())
    return "." if str(relative) == "." else relative.as_posix()


def git_identity(root: Path) -> tuple[dict[str, Any], str]:
    inside = run(root, "git", "rev-parse", "--is-inside-work-tree", check=False)
    if inside.returncode != 0 or inside.stdout.strip() != "true":
        digest = hashlib.sha256()
        for path in sorted(root.rglob("*")):
            if path.is_file() and ".git" not in path.parts:
                digest.update(relpath(path, root).encode())
                digest.update(sha256_file(path).encode())
        return {
            "vcs": "none",
            "commit": "unversioned",
            "dirty": True,
            "worktree_fingerprint": digest.hexdigest(),
            "dirty_scope": ["untracked"],
        }, "1970-01-01T00:00:00+00:00"

    commit = run(root, "git", "rev-parse", "HEAD").stdout.strip()
    staged = run(root, "git", "diff", "--cached", "--binary").stdout
    unstaged = run(root, "git", "diff", "--binary").stdout
    untracked_rows = run(root, "git", "ls-files", "--others", "--exclude-standard", "-z").stdout.split("\0")
    untracked = sorted(row for row in untracked_rows if row)
    scopes = []
    if staged:
        scopes.append("staged")
    if unstaged:
        scopes.append("unstaged")
    if untracked:
        scopes.append("untracked")
    identity: dict[str, Any] = {"vcs": "git", "commit": commit, "dirty": bool(scopes)}
    if scopes:
        digest = hashlib.sha256()
        digest.update(staged.encode())
        digest.update(unstaged.encode())
        for row in untracked:
            path = root / row
            digest.update(row.encode())
            if path.is_file():
                digest.update(sha256_file(path).encode())
        identity.update(worktree_fingerprint=digest.hexdigest(), dirty_scope=scopes)
    generated = run(root, "git", "show", "-s", "--format=%cI", "HEAD").stdout.strip()
    return identity, generated


def cargo_metadata(root: Path) -> dict[str, Any]:
    completed = run(root, "cargo", "metadata", "--format-version", "1", "--no-deps")
    return json.loads(completed.stdout)


def cargo_metadata_fingerprint(root: Path, packages: list[dict[str, Any]]) -> str:
    """Hash graph semantics without checkout/target-directory absolute paths."""
    canonical = []
    for package in packages:
        canonical.append(
            {
                "name": package["name"],
                "version": package.get("version"),
                "manifest_path": relpath(Path(package["manifest_path"]), root),
                "features": {
                    name: sorted(values)
                    for name, values in sorted(package.get("features", {}).items())
                },
                "targets": [
                    {
                        "name": target["name"],
                        "kind": sorted(target.get("kind", [])),
                        "crate_types": sorted(target.get("crate_types", [])),
                        "src_path": relpath(Path(target["src_path"]), root),
                    }
                    for target in sorted(
                        package.get("targets", []), key=lambda row: (row["name"], row["kind"])
                    )
                ],
                "dependencies": [
                    {
                        "name": dependency["name"],
                        "kind": dependency.get("kind"),
                        "optional": dependency.get("optional", False),
                        "uses_default_features": dependency.get("uses_default_features", True),
                        "features": sorted(dependency.get("features", [])),
                    }
                    for dependency in sorted(
                        package.get("dependencies", []),
                        key=lambda row: (row["name"], str(row.get("kind"))),
                    )
                ],
            }
        )
    return sha256_json(canonical)


def inventory(root: Path) -> dict[str, Any]:
    metadata = cargo_metadata(root)
    identity, generated_at = git_identity(root)
    packages = sorted(metadata["packages"], key=lambda row: row["name"])
    package_by_raw = {row["id"]: f"cargo-package:{row['name']}" for row in packages}
    units: list[dict[str, Any]] = []
    risks: list[dict[str, Any]] = []
    edges: list[dict[str, str]] = []
    for package in packages:
        package_id = package_by_raw[package["id"]]
        package_path = Path(package["manifest_path"]).parent
        relative = relpath(package_path, root)
        units.append(
            {
                "id": package_id,
                "kind": "cargo-package",
                "path": relative,
                "provider_metadata": {
                    "name": package["name"],
                    "manifest_path": relpath(Path(package["manifest_path"]), root),
                    "features": sorted(package.get("features", {})),
                },
            }
        )
        risk_id = f"risk:package:{package['name']}"
        risks.append({"id": risk_id, "kind": "package-risk", "path": relative})
        edges.append({"from": package_id, "to": risk_id, "kind": "carries_risk"})
        for target in sorted(package.get("targets", []), key=lambda row: (row["name"], row["kind"])):
            target_id = f"cargo-target:{package['name']}:{target['name']}:{'+'.join(target['kind'])}"
            units.append(
                {
                    "id": target_id,
                    "kind": "cargo-target",
                    "path": relpath(Path(target["src_path"]), root),
                    "owner": package_id,
                    "provider_metadata": {"target_kinds": target["kind"], "crate_types": target["crate_types"]},
                }
            )
            edges.append({"from": target_id, "to": package_id, "kind": "belongs_to"})
        dependency_names = {row["name"] for row in package.get("dependencies", [])}
        for dependency in sorted(packages, key=lambda row: row["name"]):
            if dependency["name"] in dependency_names:
                edges.append({"from": package_id, "to": package_by_raw[dependency["id"]], "kind": "depends_on"})
    checks = [
        {
            "id": "cargo-fmt:workspace",
            "kind": "format",
            "command": ["cargo", "fmt", "--all", "--", "--check"],
            "subject_type": "source",
        },
        {
            "id": "cargo-check:workspace",
            "kind": "compile",
            "command": ["cargo", "check", "--workspace", "--all-targets"],
            "subject_type": "source",
        },
        {
            "id": "cargo-clippy:workspace",
            "kind": "lint",
            "command": ["cargo", "clippy", "--workspace", "--all-targets", "--", "-D", "warnings"],
            "subject_type": "source",
        },
        {
            "id": "cargo-test:workspace",
            "kind": "unit-integration",
            "command": ["cargo", "test", "--workspace", "--all-targets"],
            "subject_type": "build",
        },
        {
            "id": "cargo-llvm-cov:workspace",
            "kind": "coverage-optional",
            "command": ["cargo", "llvm-cov", "--workspace", "--all-targets"],
            "subject_type": "build",
            "optional": True,
        },
    ]
    for package in packages:
        package_id = package_by_raw[package["id"]]
        for check in checks:
            edges.append({"from": package_id, "to": check["id"], "kind": "verified_by"})
    assets = []
    candidates = [root / "Cargo.toml", root / "Cargo.lock"] + [Path(row["manifest_path"]) for row in packages]
    for path in sorted({candidate.resolve() for candidate in candidates if candidate.is_file()}):
        assets.append({"path": relpath(path, root), "sha256": sha256_file(path)})
    source_subject_id = f"source:{identity['commit']}"
    if identity.get("dirty"):
        source_subject_id = f"{source_subject_id}:{identity['worktree_fingerprint'][:16]}"
    return {
        "schema_version": 1,
        "contract_version": CONTRACT_VERSION,
        "generated_at": generated_at,
        "provider": {"id": PROVIDER_ID, "version": PROVIDER_VERSION},
        "source": {"subject_id": source_subject_id, "type": "source", "identity": identity},
        "native_assets": assets,
        "units": units,
        "risk_units": risks,
        "checks": checks,
        "edges": sorted(edges, key=lambda row: (row["from"], row["to"], row["kind"])),
        "provider_metadata": {
            "cargo_metadata_sha256": cargo_metadata_fingerprint(root, packages),
            "workspace_members": len(metadata["workspace_members"]),
            "generation_binding": {
                "provider_implementation_sha256": sha256_file(Path(__file__).resolve()),
                "hybrid_core_sha256": sha256_file(
                    Path(__file__).resolve().with_name("hybrid_core.py")
                ),
            },
        },
    }


def changed_paths(root: Path, base: str, head: str) -> list[tuple[str, str]]:
    completed = run(root, "git", "diff", "--name-status", "--find-renames", base, head)
    rows: list[tuple[str, str]] = []
    for line in completed.stdout.splitlines():
        parts = line.split("\t")
        code = parts[0]
        path = parts[-1]
        change = {"A": "added", "M": "modified", "D": "deleted"}.get(code[:1], "renamed" if code.startswith("R") else "unknown")
        rows.append((path, change))
    return rows


def working_tree_changed_paths(root: Path) -> list[tuple[str, str]]:
    rows: list[tuple[str, str]] = []
    for command in (("git", "diff", "--cached", "--name-status"), ("git", "diff", "--name-status")):
        completed = run(root, *command)
        for line in completed.stdout.splitlines():
            parts = line.split("\t")
            code = parts[0]
            path = parts[-1]
            change = {"A": "added", "M": "modified", "D": "deleted"}.get(
                code[:1], "renamed" if code.startswith("R") else "unknown"
            )
            rows.append((path, change))
    untracked = run(root, "git", "ls-files", "--others", "--exclude-standard", "-z").stdout
    rows.extend((path, "added") for path in untracked.split("\0") if path)
    return rows


def impact(root: Path, source_map_path: Path, base: str, head: str, explicit: list[str]) -> dict[str, Any]:
    source_map = load_json(source_map_path)
    source_identity = source_map.get("source", {}).get("identity", {})
    if source_identity.get("vcs") == "git":
        resolved_head = run(root, "git", "rev-parse", head).stdout.strip()
        if source_identity.get("commit") != resolved_head:
            raise ValueError(
                "source map commit does not match impact head: "
                f"map={source_identity.get('commit')} head={resolved_head}"
            )
        current_identity, _ = git_identity(root)
        for field in ("commit", "dirty", "worktree_fingerprint", "dirty_scope"):
            if source_identity.get(field) != current_identity.get(field):
                raise ValueError(f"source map {field} does not match current worktree")
        changes = changed_paths(root, base, head)
        changes.extend(working_tree_changed_paths(root))
    else:
        changes = []
        if source_identity.get("dirty") is True and not explicit:
            changes.append(("<dirty-unversioned-worktree>", "unknown"))
    changes.extend((path, "unknown") for path in explicit)
    changes = sorted({path: change for path, change in changes}.items())
    package_units = [row for row in source_map["units"] if row.get("kind") == "cargo-package"]
    known_package_ids = {row["id"] for row in package_units}
    reverse: dict[str, set[str]] = defaultdict(set)
    risk_by_package: dict[str, set[str]] = defaultdict(set)
    for edge in source_map["edges"]:
        if edge["kind"] == "depends_on" and edge["from"] in known_package_ids and edge["to"] in known_package_ids:
            reverse[edge["to"]].add(edge["from"])
        if edge["kind"] == "carries_risk":
            risk_by_package[edge["from"]].add(edge["to"])
    changed_units: list[dict[str, str]] = []
    directly_changed: set[str] = set()
    unknown: list[str] = []
    for path, change_type in changes:
        change_id = f"change:{hashlib.sha256(path.encode()).hexdigest()[:16]}"
        matches = []
        for row in package_units:
            prefix = row["path"]
            if prefix == "." or path == prefix or path.startswith(prefix + "/"):
                matches.append(row)
        if matches:
            match = max(matches, key=lambda row: len(row["path"]))
            directly_changed.add(match["id"])
            changed_units.append({"id": change_id, "path": path, "change_type": change_type})
        else:
            unknown.append(path)
            changed_units.append({"id": change_id, "path": path, "change_type": change_type})
    impacted = set(directly_changed)
    queue = deque(sorted(directly_changed))
    while queue:
        current = queue.popleft()
        for dependent in sorted(reverse[current]):
            if dependent not in impacted:
                impacted.add(dependent)
                queue.append(dependent)
    if unknown:
        impacted = known_package_ids
    impacted_risks = sorted({risk for package in impacted for risk in risk_by_package[package]})
    required = [
        {
            "id": "cargo-fmt:workspace",
            "kind": "format",
            "reason": "reject source formatting drift before broader checks",
            "unit_ids": sorted(impacted),
            "risk_ids": impacted_risks,
        },
        {
            "id": "cargo-check:workspace",
            "kind": "compile",
            "reason": "compile impacted Rust workspace; safe default when mapping is incomplete",
            "unit_ids": sorted(impacted),
            "risk_ids": impacted_risks,
        },
        {
            "id": "cargo-clippy:workspace",
            "kind": "lint",
            "reason": "lint impacted Rust workspace with warnings denied",
            "unit_ids": sorted(impacted),
            "risk_ids": impacted_risks,
        },
        {
            "id": "cargo-test:workspace",
            "kind": "unit-integration",
            "reason": "exercise impacted packages and reverse dependents",
            "unit_ids": sorted(impacted),
            "risk_ids": impacted_risks,
        },
    ]
    mutation_triggers = (
        ["high-risk-source-change"]
        if any(row["path"].endswith(".rs") for row in changed_units)
        else []
    )
    if mutation_triggers:
        required.append(
            {
                "id": "mutation:workspace",
                "kind": "mutation",
                "reason": "profile policy requires mutation adequacy for a Rust source change",
                "unit_ids": sorted(impacted),
                "risk_ids": impacted_risks,
            }
        )
    level = "low" if unknown else ("high" if changes else "medium")
    score = {"low": 0.25, "medium": 0.7, "high": 0.95}[level]
    return {
        "schema_version": 1,
        "contract_version": CONTRACT_VERSION,
        "source_map_sha256": sha256_file(source_map_path),
        "base": base,
        "head": head,
        "changed_units": changed_units,
        "impacted_risk_units": impacted_risks,
        "selections": {
            "required": required,
            "recommended": [
                {
                    "id": "cargo-llvm-cov:workspace",
                    "kind": "coverage-optional",
                    "reason": "measure coverage when cargo-llvm-cov is installed and the risk warrants it",
                    "unit_ids": sorted(impacted),
                    "risk_ids": impacted_risks,
                }
            ],
            "excluded": [],
        },
        "required_lanes": ["diff", "risk", "selection", "invariant"],
        "required_gates": ["source-closure"],
        "mutation_triggers": mutation_triggers,
        "confidence": {"score": score, "level": level, "reasons": ["path ownership and reverse Cargo dependencies"]},
        "unknown_changes": unknown,
        "fallback_policy": "expand-safe-default" if unknown else "none",
        "provider_metadata": {"provider": {"id": PROVIDER_ID, "version": PROVIDER_VERSION}},
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", action="version", version=PROVIDER_VERSION)
    subparsers = parser.add_subparsers(dest="operation", required=True)
    for name in ("probe", "inventory"):
        sub = subparsers.add_parser(name)
        sub.add_argument("--project-root", type=Path, required=True)
    impact_parser = subparsers.add_parser("impact")
    impact_parser.add_argument("--project-root", type=Path, required=True)
    impact_parser.add_argument("--source-map", type=Path, required=True)
    impact_parser.add_argument("--base", default="HEAD~1")
    impact_parser.add_argument("--head", default="HEAD")
    impact_parser.add_argument("--changed-file", action="append", default=[])
    check_parser = subparsers.add_parser("check")
    check_parser.add_argument("--project-root", type=Path, required=True)
    check_parser.add_argument(
        "--check-id",
        choices=(
            "cargo-fmt:workspace",
            "cargo-check:workspace",
            "cargo-clippy:workspace",
            "cargo-test:workspace",
            "cargo-llvm-cov:workspace",
        ),
        required=True,
    )
    args = parser.parse_args()
    root = args.project_root.resolve()
    try:
        if args.operation == "probe":
            cargo = run(root, "cargo", "--version", check=False)
            git = run(root, "git", "--version", check=False)
            rustfmt = run(root, "cargo", "fmt", "--version", check=False)
            clippy = run(root, "cargo", "clippy", "--version", check=False)
            llvm_cov = run(root, "cargo", "llvm-cov", "--version", check=False)
            document = {
                "provider": {
                    "id": PROVIDER_ID,
                    "version": PROVIDER_VERSION,
                    "implementation_sha256": sha256_file(Path(__file__).resolve()),
                },
                "capabilities": [
                    {"name": "source-map", "status": "available" if cargo.returncode == 0 else "unavailable", "evidence": cargo.stdout.strip() or cargo.stderr.strip()},
                    {"name": "source-impact", "status": "available" if cargo.returncode == 0 and git.returncode == 0 else "unavailable", "evidence": f"{cargo.stdout.strip()}; {git.stdout.strip()}"},
                    {"name": "typed-subject-identity", "status": "available", "evidence": "results v4 typed subject contract"},
                    {"name": "runtime-probe", "status": "unavailable", "evidence": "source provider does not execute a runtime candidate"},
                    {"name": "artifact-identity", "status": "unconfigured", "evidence": "artifact is supplied per test run"},
                    {"name": "process-identity", "status": "unconfigured", "evidence": "candidate process is supplied per test run"},
                    {"name": "session-readiness", "status": "unavailable", "evidence": "source provider does not establish sessions"},
                    {"name": "cargo-fmt", "status": "available" if rustfmt.returncode == 0 else "unavailable", "evidence": rustfmt.stdout.strip() or rustfmt.stderr.strip()},
                    {"name": "cargo-clippy", "status": "available" if clippy.returncode == 0 else "unavailable", "evidence": clippy.stdout.strip() or clippy.stderr.strip()},
                    {"name": "cargo-llvm-cov", "status": "available" if llvm_cov.returncode == 0 else "unavailable", "evidence": llvm_cov.stdout.strip() or llvm_cov.stderr.strip()},
                ],
            }
        elif args.operation == "inventory":
            document = inventory(root)
        elif args.operation == "impact":
            document = impact(root, args.source_map.resolve(), args.base, args.head, args.changed_file)
        else:
            commands = {
                "cargo-fmt:workspace": ["cargo", "fmt", "--all", "--", "--check"],
                "cargo-check:workspace": ["cargo", "check", "--workspace", "--all-targets"],
                "cargo-clippy:workspace": ["cargo", "clippy", "--workspace", "--all-targets", "--", "-D", "warnings"],
                "cargo-test:workspace": ["cargo", "test", "--workspace", "--all-targets"],
                "cargo-llvm-cov:workspace": ["cargo", "llvm-cov", "--workspace", "--all-targets"],
            }
            command = commands[args.check_id]
            completed = run(root, *command, check=False)
            document = {"provider": {"id": PROVIDER_ID, "version": PROVIDER_VERSION}, "check_id": args.check_id, "exit_code": completed.returncode, "stdout": completed.stdout, "stderr": completed.stderr}
    except (OSError, subprocess.CalledProcessError, json.JSONDecodeError, ValueError) as exc:
        print(f"rust-cargo provider failed: {exc}", file=sys.stderr)
        return 2
    print(dump_json(document), end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

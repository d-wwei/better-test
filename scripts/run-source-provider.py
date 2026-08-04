#!/usr/bin/env python3
"""Run a declared provider with identity checks and a minimized environment.

This runner enforces declaration, implementation hash/version, path scope, and
explicit authorization flags. It does not pretend to be an OS network sandbox;
projects that require hard isolation must wrap the declared command in their
platform sandbox and declare that wrapper as the hashed provider.
"""

from __future__ import annotations

import argparse
from contextlib import nullcontext
import hashlib
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any

from hybrid_core import dump_json, load_json, loads_json, sha256_file, validate, write_atomic


def source_snapshot(root: Path) -> str:
    """Fingerprint tracked, staged, unstaged, and untracked bytes without mutation."""
    digest = hashlib.sha256()
    git = subprocess.run(
        ["git", "rev-parse", "--is-inside-work-tree"],
        cwd=root,
        text=True,
        capture_output=True,
        check=False,
    )
    if git.returncode == 0 and git.stdout.strip() == "true":
        for command in (
            ["git", "rev-parse", "HEAD"],
            ["git", "diff", "--binary", "HEAD"],
            ["git", "diff", "--cached", "--binary"],
        ):
            completed = subprocess.run(
                command, cwd=root, text=False, capture_output=True, check=False
            )
            digest.update(completed.stdout)
            digest.update(completed.stderr)
        untracked: set[bytes] = set()
        for command in (
            ["git", "ls-files", "--others", "--exclude-standard", "-z"],
            ["git", "ls-files", "--others", "--ignored", "--exclude-standard", "-z"],
        ):
            untracked.update(
                path
                for path in subprocess.run(
                    command,
                    cwd=root,
                    text=False,
                    capture_output=True,
                    check=False,
                ).stdout.split(b"\0")
                if path
            )
        for raw in sorted(untracked):
            digest.update(raw)
            candidate = root / raw.decode("utf-8", errors="surrogateescape")
            if candidate.is_file():
                digest.update(sha256_file(candidate).encode())
        return digest.hexdigest()
    for path in sorted(candidate for candidate in root.rglob("*") if candidate.is_file()):
        if ".git" in path.parts:
            continue
        digest.update(path.relative_to(root).as_posix().encode())
        digest.update(sha256_file(path).encode())
    return digest.hexdigest()


def expand(value: str, project_root: Path, better_test_root: Path, source_root: Path) -> str:
    return value.replace("{project_root}", str(project_root)).replace(
        "{better_test_root}", str(better_test_root)
    ).replace("{source_root}", str(source_root))


def implementation_file(command: list[str]) -> Path | None:
    for part in command:
        candidate = Path(part)
        if candidate.is_absolute() and candidate.is_file() and candidate.suffix in {".py", ".sh", ".rb", ".pl"}:
            return candidate.resolve()
    return None


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--profile", type=Path, required=True)
    parser.add_argument("--provider", required=True)
    parser.add_argument("--operation", choices=("probe", "inventory", "impact", "check"), required=True)
    parser.add_argument("--project-root", type=Path, required=True)
    parser.add_argument("--source-root", type=Path)
    parser.add_argument("--better-test-root", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--metrics-output", type=Path)
    parser.add_argument("--timeout", type=int, default=120)
    parser.add_argument("--allow-network", action="store_true")
    parser.add_argument("--allow-external-writes", action="store_true")
    parser.add_argument("--scratch-dir", type=Path)
    parser.add_argument("provider_args", nargs=argparse.REMAINDER)
    args = parser.parse_args()

    better_test_root = (args.better_test_root or Path(__file__).resolve().parent.parent).resolve()
    project_root = args.project_root.resolve()
    try:
        profile = load_json(args.profile)
        profile_errors = validate("project-profile", profile)
        if profile_errors:
            raise ValueError("; ".join(profile_errors))
        provider = next(row for row in profile["providers"] if row["id"] == args.provider)
    except StopIteration:
        print(f"provider runner refused undeclared provider: {args.provider}", file=sys.stderr)
        return 2
    except (OSError, ValueError, KeyError) as exc:
        print(f"provider runner profile error: {exc}", file=sys.stderr)
        return 2

    configured_source = profile.get("extensions", {}).get("source_root", ".")
    source_root = (args.source_root or (project_root / configured_source)).resolve()
    protected_output_trees = {source_root, better_test_root}
    for label, destination in (("output", args.output), ("metrics-output", args.metrics_output)):
        if destination is None:
            continue
        resolved_destination = destination.resolve()
        if resolved_destination in {Path("/"), Path.home().resolve()} or any(
            resolved_destination == root or root in resolved_destination.parents
            for root in protected_output_trees
        ):
            print(f"provider runner {label} path is protected", file=sys.stderr)
            return 4
    trust: dict[str, Any] = provider["trust"]
    if trust["network"] == "explicit" and not args.allow_network:
        print("provider runner requires --allow-network for this declaration", file=sys.stderr)
        return 3
    if trust["network"] == "deny" and args.allow_network:
        print("provider runner refuses network authorization not allowed by profile", file=sys.stderr)
        return 3
    if trust["external_writes"] == "explicit" and not args.allow_external_writes:
        print("provider runner requires --allow-external-writes for this declaration", file=sys.stderr)
        return 3
    if trust["external_writes"] == "deny" and args.allow_external_writes:
        print("provider runner refuses external-write authorization not allowed by profile", file=sys.stderr)
        return 3
    if args.scratch_dir is not None and not args.allow_external_writes:
        print("provider runner requires --allow-external-writes with --scratch-dir", file=sys.stderr)
        return 3

    command = [expand(part, project_root, better_test_root, source_root) for part in provider["command"]]
    implementation = implementation_file(command)
    if trust.get("sha256"):
        if implementation is None or sha256_file(implementation) != trust["sha256"]:
            print("provider runner implementation hash mismatch", file=sys.stderr)
            return 4
    for dependency in trust.get("dependencies", []):
        dependency_path = Path(
            expand(dependency["path"], project_root, better_test_root, source_root)
        )
        if not dependency_path.is_absolute():
            dependency_path = project_root / dependency_path
        dependency_path = dependency_path.resolve()
        if not dependency_path.is_file() or sha256_file(dependency_path) != dependency["sha256"]:
            print(f"provider runner dependency hash mismatch: {dependency['path']}", file=sys.stderr)
            return 4
    for scope in trust["path_scope"]:
        scoped = Path(expand(scope, project_root, better_test_root, source_root))
        if not scoped.is_absolute():
            scoped = project_root / scoped
        scoped = scoped.resolve()
        if scoped in {Path("/"), Path.home().resolve()} or not scoped.exists():
            print(f"provider runner path scope is missing or dangerously broad: {scope}", file=sys.stderr)
            return 4

    command.extend([args.operation, "--project-root", str(project_root)])
    if args.provider_args and args.provider_args[0] == "--":
        command.extend(args.provider_args[1:])
    else:
        command.extend(args.provider_args)
    scratch_root: Path | None = None
    if args.scratch_dir is not None:
        scratch_root = args.scratch_dir.resolve()
        broad_roots = {Path("/"), Path.home().resolve()}
        protected_trees = {project_root, source_root, better_test_root}
        if scratch_root in broad_roots or any(
            scratch_root == root or root in scratch_root.parents for root in protected_trees
        ):
            print("provider runner scratch directory is dangerously broad", file=sys.stderr)
            return 4
        scratch_root.mkdir(parents=True, exist_ok=True)
    context = nullcontext(str(scratch_root)) if scratch_root is not None else tempfile.TemporaryDirectory(prefix="better-test-provider-")
    with context as temporary:
        temporary_root = Path(temporary)
        runner_home = temporary_root / "home"
        runner_tmp = temporary_root / "tmp"
        runner_home.mkdir(parents=True, exist_ok=True)
        runner_tmp.mkdir(parents=True, exist_ok=True)
        host_home = Path.home()
        env = {
            "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
            "LANG": os.environ.get("LANG", "C.UTF-8"),
            "LC_ALL": os.environ.get("LC_ALL", "C.UTF-8"),
            "HOME": str(runner_home),
            "TMPDIR": str(runner_tmp),
            "BT_NETWORK_ACCESS": "allowed" if args.allow_network else "denied",
            "BT_EXTERNAL_WRITES": "allowed" if args.allow_external_writes else "denied",
            "PYTHONDONTWRITEBYTECODE": "1",
            "CARGO_TARGET_DIR": str(temporary_root / "cargo-target"),
            "CARGO_NET_OFFLINE": "false" if args.allow_network else "true",
        }
        # Rustup's cargo shim needs its toolchain roots even for offline metadata.
        # These are paths, not credential values; the provider still receives no
        # inherited token/password environment variables.
        rustup_home = Path(os.environ.get("RUSTUP_HOME", host_home / ".rustup"))
        cargo_home = Path(os.environ.get("CARGO_HOME", host_home / ".cargo"))
        if rustup_home.is_dir():
            env["RUSTUP_HOME"] = str(rustup_home)
        if args.allow_network:
            # Network-authorized builds get an ephemeral registry/cache so the
            # provider cannot mutate the caller's Cargo home.
            ephemeral_cargo_home = temporary_root / "cargo-home"
            ephemeral_cargo_home.mkdir(parents=True, exist_ok=True)
            env["CARGO_HOME"] = str(ephemeral_cargo_home)
        elif cargo_home.is_dir():
            env["CARGO_HOME"] = str(cargo_home)
        before_source_snapshot = source_snapshot(source_root)
        execution_error: OSError | subprocess.TimeoutExpired | None = None
        try:
            started = time.monotonic()
            completed = subprocess.run(
                command,
                cwd=project_root,
                env=env,
                text=True,
                capture_output=True,
                timeout=args.timeout,
                check=False,
            )
            duration_seconds = round(time.monotonic() - started, 6)
        except (OSError, subprocess.TimeoutExpired) as exc:
            execution_error = exc
        after_source_snapshot = source_snapshot(source_root)
        if before_source_snapshot != after_source_snapshot:
            print("provider runner detected a source checkout mutation", file=sys.stderr)
            return 8
        if execution_error is not None:
            print(f"provider runner execution error: {execution_error}", file=sys.stderr)
            return 5
    if completed.returncode != 0:
        print(completed.stderr.rstrip(), file=sys.stderr)
        print(f"provider runner command failed with exit {completed.returncode}", file=sys.stderr)
        return 5
    try:
        document = loads_json(completed.stdout)
        kind = {"probe": "capabilities", "inventory": "source-map", "impact": "source-impact"}.get(args.operation)
        if kind:
            errors = validate(kind, document)
            if errors:
                raise ValueError("; ".join(errors))
        output_provider = document.get("provider") if isinstance(document, dict) else None
        if output_provider is None and isinstance(document, dict):
            output_provider = document.get("provider_metadata", {}).get("provider")
        if not isinstance(output_provider, dict):
            raise ValueError("provider output omits provider identity")
        if output_provider.get("id") != provider["id"]:
            raise ValueError("provider output id differs from declaration")
        if trust.get("version") and output_provider.get("version") != trust["version"]:
            raise ValueError("provider output version differs from declaration")
        cache_hit = False
        if args.operation == "check" and isinstance(document, dict):
            marker = scratch_root / ".better-test-cache-ready" if scratch_root is not None else None
            cache_hit = bool(marker is not None and marker.is_file())
            document["runner_metadata"] = {
                "duration_seconds": duration_seconds,
                "persistent_scratch": scratch_root is not None,
                "cache_hit": cache_hit,
            }
            if marker is not None:
                marker.write_text("ready\n", encoding="utf-8")
    except (ValueError, TypeError) as exc:
        print(f"provider runner rejected output: {exc}", file=sys.stderr)
        return 6
    write_atomic(args.output, dump_json(document))
    summary = document.get("summary") if isinstance(document, dict) else None
    failed = summary.get("failed", 0) if isinstance(summary, dict) else 0
    if args.metrics_output is not None:
        write_atomic(
            args.metrics_output,
            dump_json(
                {
                    "schema_version": 1,
                    "provider_id": provider["id"],
                    "provider_version": output_provider.get("version"),
                    "operation": args.operation,
                    "execution_status": "accepted",
                    "duration_seconds": duration_seconds,
                    "persistent_scratch": scratch_root is not None,
                    "cache_hit": cache_hit,
                    "check_failure_count": failed if args.operation == "check" else 0,
                    "policy_enforcement": {
                        "source_access": "content-snapshot-before-and-after",
                        "network": "declaration-plus-sanitized-environment-not-os-sandbox",
                        "external_writes": "authorization-and-path-guard-not-os-sandbox",
                    },
                }
            ),
        )
    print(args.output)
    if args.operation == "check" and isinstance(document, dict):
        if document.get("exit_code", 0) != 0 or failed:
            print(f"provider runner recorded {failed or 1} failed check(s)", file=sys.stderr)
            return 7
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

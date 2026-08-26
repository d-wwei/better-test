#!/usr/bin/env python3
"""Validate cross-run environment/config/gate coverage for a release set."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any


def load(path: Path) -> Any:
    def reject_constant(value: str) -> None:
        raise ValueError(f"non-standard JSON constant: {value}")

    def reject_duplicate_keys(
        pairs: list[tuple[str, Any]],
    ) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in pairs:
            if key in result:
                raise ValueError(f"duplicate JSON key: {key}")
            result[key] = value
        return result

    with path.open(encoding="utf-8") as handle:
        return json.load(
            handle,
            parse_constant=reject_constant,
            object_pairs_hook=reject_duplicate_keys,
        )


def nonempty(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def validate_source_result(
    path: Path,
    run: dict[str, Any],
    trusted_profiles: list[Path],
) -> str | None:
    schema_version = run.get("schema_version")
    if schema_version == 3:
        command = [str(Path(__file__).with_name("validate-results.sh")), str(path)]
    elif schema_version == 4:
        profile_sha = (
            run.get("input_refs", {}).get("project_profile", {}).get("sha256")
            if isinstance(run.get("input_refs"), dict)
            else None
        )
        matched_profile = next(
            (
                profile
                for profile in trusted_profiles
                if profile.is_file() and sha256_file(profile) == profile_sha
            ),
            None,
        )
        if matched_profile is None:
            return (
                "schema v4 result requires an external canonical --profile "
                f"matching input_refs.project_profile.sha256={profile_sha!r}"
            )
        command = [
            sys.executable,
            str(Path(__file__).with_name("validate-results-v4.py")),
            str(path),
            "--profile",
            str(matched_profile),
        ]
    else:
        return f"unsupported results schema_version: {schema_version!r}"
    completed = subprocess.run(
        command,
        check=False,
        capture_output=True,
        text=True,
    )
    if completed.returncode == 0:
        return None
    detail = (completed.stdout or completed.stderr).strip()
    return detail or f"validator exited {completed.returncode}"


def release_set_metadata(run: dict[str, Any]) -> dict[str, Any]:
    if run.get("schema_version") == 3:
        environment = run.get("environment")
        return {
            "environment": environment if isinstance(environment, dict) else {},
            "package_type": run.get("package_type"),
            "gates": run.get("gate_items", []),
        }
    provider_metadata = run.get("provider_metadata")
    release_set = (
        provider_metadata.get("release_set")
        if isinstance(provider_metadata, dict)
        else None
    )
    return {
        "environment": release_set if isinstance(release_set, dict) else {},
        "package_type": (
            release_set.get("package_type")
            if isinstance(release_set, dict)
            else None
        ),
        "gates": run.get("gates", []),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--policy", required=True, type=Path)
    parser.add_argument(
        "--profile",
        type=Path,
        action="append",
        default=[],
        help="external canonical project profile; repeat when source runs use different profile revisions",
    )
    parser.add_argument("results", nargs="+", type=Path)
    args = parser.parse_args()
    errors: list[str] = []
    try:
        policy = load(args.policy)
        runs = [load(path) for path in args.results]
    except (OSError, json.JSONDecodeError, ValueError) as exc:
        print(f"INVALID: {exc}", file=sys.stderr)
        return 2

    trusted_profiles = [path.resolve() for path in args.profile]
    if not trusted_profiles and os.environ.get("BETTER_TEST_TRUSTED_PROFILE"):
        trusted_profiles.append(
            Path(os.environ["BETTER_TEST_TRUSTED_PROFILE"]).resolve()
        )
    for profile in trusted_profiles:
        if not profile.is_file():
            errors.append(f"trusted profile does not exist: {profile}")

    if not isinstance(policy, dict):
        errors.append("policy must be an object")
        policy = {}
    if type(policy.get("schema_version")) is not int or policy.get(
        "schema_version"
    ) != 1:
        errors.append("policy schema_version must be integer 1")
    run_ids: set[str] = set()
    versions: set[str] = set()
    for index, (path, run) in enumerate(zip(args.results, runs)):
        if not isinstance(run, dict) or run.get("schema_version") not in {3, 4}:
            errors.append(f"results[{index}] must use schema v3 or v4")
            continue
        validation_error = validate_source_result(path, run, trusted_profiles)
        if validation_error:
            errors.append(
                f"results[{index}] failed strict results validation: "
                f"{validation_error}"
            )
        run_id = run.get("run_id")
        if not nonempty(run_id):
            errors.append(f"results[{index}].run_id must be non-empty")
        elif run_id in run_ids:
            errors.append(f"duplicate run_id: {run_id}")
        else:
            run_ids.add(run_id)
        version = run.get("version")
        if not nonempty(version):
            errors.append(f"results[{index}].version must be non-empty")
        else:
            versions.add(version.strip())

    metadata = [
        release_set_metadata(run) if isinstance(run, dict) else {}
        for run in runs
    ]
    environments = {
        row.get("environment", {}).get("environment_id").strip()
        for row in metadata
        if isinstance(row.get("environment"), dict)
        and nonempty(row["environment"].get("environment_id"))
    }
    machines = {
        row.get("environment", {}).get("machine_id").strip()
        for row in metadata
        if isinstance(row.get("environment"), dict)
        and nonempty(row["environment"].get("machine_id"))
    }
    profiles = {
        row.get("environment", {}).get("config_profile").strip()
        for row in metadata
        if isinstance(row.get("environment"), dict)
        and nonempty(row["environment"].get("config_profile"))
    }
    for index, row in enumerate(metadata):
        environment = row.get("environment")
        if not isinstance(environment, dict) or any(
            not nonempty(environment.get(field))
            for field in ("environment_id", "machine_id", "config_profile")
        ):
            schema_version = (
                runs[index].get("schema_version")
                if isinstance(runs[index], dict)
                else None
            )
            location = (
                "environment"
                if schema_version == 3
                else "provider_metadata.release_set"
            )
            errors.append(
                f"results[{index}].{location} must declare environment_id, "
                "machine_id, and config_profile"
            )

    for field, actual in (
        ("min_distinct_environments", len(environments)),
        ("min_distinct_machines", len(machines)),
    ):
        required = policy.get(field, 1)
        if type(required) is not int or required < 1:
            errors.append(f"policy {field} must be a positive integer")
        elif actual < required:
            errors.append(f"{field} requires {required}, observed {actual}")

    required_profiles = policy.get("required_config_profiles", [])
    if not isinstance(required_profiles, list) or not all(
        nonempty(value) for value in required_profiles
    ):
        errors.append("required_config_profiles must be a string array")
        required_profiles = []
    else:
        required_profiles = [value.strip() for value in required_profiles]
        if len(set(required_profiles)) != len(required_profiles):
            errors.append("required_config_profiles must not contain duplicates")
        missing_profiles = sorted(set(required_profiles) - profiles)
        if missing_profiles:
            errors.append(f"missing config profiles: {', '.join(missing_profiles)}")

    gate_verdicts: dict[str, list[str]] = {}
    profile_gate_verdicts: dict[str, dict[str, list[str]]] = {}
    for run, row in zip(runs, metadata):
        if not isinstance(run, dict) or not isinstance(row, dict):
            continue
        environment = row.get("environment")
        profile = (
            environment.get("config_profile", "").strip()
            if isinstance(environment, dict)
            and isinstance(environment.get("config_profile"), str)
            else ""
        )
        gates = row.get("gates", [])
        if not isinstance(gates, list):
            continue
        for gate in gates:
            if not isinstance(gate, dict):
                continue
            gate_id = str(
                gate.get("gate_id")
                if run.get("schema_version") == 3
                else gate.get("id", "")
            )
            verdict = str(gate.get("verdict", ""))
            gate_verdicts.setdefault(gate_id, []).append(verdict)
            profile_gate_verdicts.setdefault(profile, {}).setdefault(
                gate_id, []
            ).append(verdict)
    required_gates = policy.get("required_gate_ids", [])
    if not isinstance(required_gates, list) or not all(
        nonempty(value) for value in required_gates
    ):
        errors.append("required_gate_ids must be a string array")
        required_gates = []
    else:
        required_gates = [value.strip() for value in required_gates]
        if len(set(required_gates)) != len(required_gates):
            errors.append("required_gate_ids must not contain duplicates")
        for gate_id in required_gates:
            verdicts = gate_verdicts.get(gate_id, [])
            if "pass" not in verdicts:
                errors.append(f"required gate lacks pass evidence: {gate_id}")
            if any(value in {"fail", "blocked"} for value in verdicts):
                errors.append(f"required gate has fail/blocked evidence: {gate_id}")
            for profile in required_profiles:
                profile_verdicts = profile_gate_verdicts.get(profile, {}).get(
                    gate_id, []
                )
                if "pass" not in profile_verdicts:
                    errors.append(
                        "required gate lacks pass evidence for config profile "
                        f"{profile}: {gate_id}"
                    )
                if any(
                    value in {"fail", "blocked"}
                    for value in profile_verdicts
                ):
                    errors.append(
                        "required gate has fail/blocked evidence for config "
                        f"profile {profile}: {gate_id}"
                    )

    package_types = {
        row.get("package_type").strip()
        for row in metadata
        if isinstance(row, dict) and nonempty(row.get("package_type"))
    }
    if len(package_types) != 1:
        errors.append(f"release set must have one package_type, observed {sorted(package_types)}")
    if len(versions) != 1:
        errors.append(
            f"release set must have one version, observed {sorted(versions)}"
        )

    if errors:
        for error in errors:
            print(f"INVALID: {error}", file=sys.stderr)
        return 1
    print(
        "valid release set: "
        f"runs={len(runs)} environments={len(environments)} "
        f"machines={len(machines)} profiles={len(profiles)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

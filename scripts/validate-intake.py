#!/usr/bin/env python3
"""Validate a run-local Better Test intake and its results binding."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path, PurePosixPath
from typing import Any

from hybrid_core import (
    is_timestamp,
    load_json,
    sha256_file,
    validate_json_schema,
)


RELATION_TYPES = {
    "built_from": ({"build"}, {"source"}),
    "produced_by": ({"artifact"}, {"build"}),
    "installed_from": ({"installation"}, {"artifact"}),
    "launched_from": ({"process"}, {"installation", "artifact", "build"}),
    "connected_to": ({"session"}, {"process", "external_service"}),
}


def nonempty(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def resolve_artifact(
    intake_path: Path,
    identity: dict[str, Any],
    project_root: Path | None,
) -> tuple[Path | None, str | None]:
    path_value = identity.get("path")
    path_base = identity.get("path_base")
    if path_value is None and path_base is None:
        return None, None
    if not nonempty(path_value) or path_base not in {"project_root", "run_dir"}:
        return None, "artifact path and path_base must appear together"
    pure = PurePosixPath(path_value)
    if pure.is_absolute() or ".." in pure.parts:
        return None, "artifact path must be a safe relative path"
    if path_base == "project_root":
        if project_root is None:
            return None, "artifact path requires --project-root"
        base = project_root.resolve()
    else:
        base = intake_path.parent.resolve()
    target = (base / path_value).resolve()
    try:
        target.relative_to(base)
    except ValueError:
        return None, "artifact path escapes its declared base"
    return target, None


def validate_intake(
    document: Any,
    intake_path: Path,
    results_path: Path | None = None,
    project_root: Path | None = None,
    require_binding: bool = False,
) -> tuple[list[str], list[str], str]:
    schema_path = Path(__file__).resolve().parent.parent / "schemas" / "intake.schema.json"
    errors = validate_json_schema(document, load_json(schema_path))
    advisories: list[str] = []
    if not isinstance(document, dict):
        return errors or ["intake must be an object"], advisories, "invalid"
    if not is_timestamp(document.get("attested_at")):
        errors.append("attested_at must be an ISO 8601 timestamp with timezone")

    subjects = document.get("subjects", [])
    subject_ids: set[str] = set()
    subject_types: dict[str, str] = {}
    concrete_subjects = 0
    artifact_states: list[str] = []
    if isinstance(subjects, list):
        for index, subject in enumerate(subjects):
            if not isinstance(subject, dict):
                continue
            subject_id = subject.get("id")
            if subject_id in subject_ids:
                errors.append(f"duplicate subject id: {subject_id}")
            if nonempty(subject_id):
                subject_ids.add(subject_id)
                subject_types[subject_id] = subject.get("type")
            if subject.get("type") != "unknown":
                concrete_subjects += 1
            identity = subject.get("identity", {})
            if subject.get("type") == "source" and identity.get("dirty") is True:
                fingerprint = identity.get("worktree_fingerprint")
                if not isinstance(fingerprint, str) or len(fingerprint) != 64:
                    errors.append(
                        f"subjects[{index}] dirty source requires worktree_fingerprint"
                    )
            if subject.get("type") != "artifact" or not isinstance(identity, dict):
                continue
            target, path_error = resolve_artifact(intake_path, identity, project_root)
            if path_error == "artifact path requires --project-root":
                advisories.append(f"subjects[{index}] {path_error}")
                artifact_states.append("declared_only")
            elif path_error:
                errors.append(f"subjects[{index}] {path_error}")
                artifact_states.append("invalid")
            elif target is None:
                artifact_states.append("declared_only")
            elif not target.is_file():
                advisories.append(f"subjects[{index}] artifact is unavailable: {target}")
                artifact_states.append("declared_only")
            elif sha256_file(target) != identity.get("sha256"):
                errors.append(f"subjects[{index}] artifact sha256 does not match: {target}")
                artifact_states.append("invalid")
            else:
                artifact_states.append("verified")
    if concrete_subjects == 0:
        errors.append("intake requires at least one non-unknown subject")

    relations = document.get("relations", [])
    if isinstance(relations, list):
        for index, relation in enumerate(relations):
            if not isinstance(relation, dict):
                continue
            source_id = relation.get("from")
            target_id = relation.get("to")
            if source_id not in subject_ids:
                errors.append(f"relations[{index}].from references unknown subject")
            if target_id not in subject_ids:
                errors.append(f"relations[{index}].to references unknown subject")
            expected = RELATION_TYPES.get(relation.get("type"))
            if expected and (
                subject_types.get(source_id) not in expected[0]
                or subject_types.get(target_id) not in expected[1]
            ):
                errors.append(
                    f"relations[{index}] has invalid subject types for "
                    f"{relation.get('type')}"
                )

    if results_path is not None:
        results = load_json(results_path)
        intake_ref = results.get("intake_ref") if isinstance(results, dict) else None
        if not isinstance(intake_ref, dict):
            message = "results.json is missing intake_ref"
            (errors if require_binding else advisories).append(message)
        else:
            if intake_ref.get("intake_id") != document.get("intake_id"):
                errors.append("results intake_ref.intake_id does not match intake_id")
            if intake_ref.get("sha256") != sha256_file(intake_path):
                errors.append("results intake_ref.sha256 does not match intake.json")

    if errors or "invalid" in artifact_states:
        identity_status = "invalid"
    elif artifact_states and all(state == "verified" for state in artifact_states):
        identity_status = "verified"
    else:
        identity_status = "declared_only"
    return errors, advisories, identity_status


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("intake", type=Path)
    parser.add_argument("--results", type=Path)
    parser.add_argument("--project-root", type=Path)
    parser.add_argument("--require-binding", action="store_true")
    args = parser.parse_args()
    try:
        intake_path = args.intake.resolve(strict=True)
        results_path = args.results.resolve(strict=True) if args.results else None
        project_root = args.project_root.resolve(strict=True) if args.project_root else None
        errors, advisories, identity_status = validate_intake(
            load_json(intake_path),
            intake_path,
            results_path,
            project_root,
            args.require_binding,
        )
    except (OSError, ValueError) as exc:
        print(f"intake validation error: {exc}", file=sys.stderr)
        return 2
    for advisory in advisories:
        print(f"ADVISORY: {advisory}")
    if errors:
        for error in errors:
            print(f"INVALID: {error}", file=sys.stderr)
        return 1
    print(f"valid intake: {intake_path} identity={identity_status}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

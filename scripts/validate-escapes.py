#!/usr/bin/env python3
"""Validate better-test's project-level post-ship escape ledger."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any


def nonempty(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


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


def validate_reference(ref: str, base_dir: Path) -> bool:
    path_text = ref.split("#", 1)[0].strip()
    if not path_text:
        return False
    path = Path(path_text)
    if not path.is_absolute():
        path = base_dir / path
    return path.is_file()


def validate(document: Any, base_dir: Path) -> list[str]:
    errors: list[str] = []
    if not isinstance(document, dict):
        return ["root must be an object"]
    if type(document.get("schema_version")) is not int or document.get(
        "schema_version"
    ) != 1:
        errors.append("schema_version must be integer 1")
    escapes = document.get("escapes")
    if not isinstance(escapes, list):
        return errors + ["escapes must be an array"]

    seen_escape_ids: set[str] = set()
    for index, escape in enumerate(escapes):
        where = f"escapes[{index}]"
        if not isinstance(escape, dict):
            errors.append(f"{where} must be an object")
            continue

        escape_id = escape.get("id")
        if not nonempty(escape_id) or not re.fullmatch(r"ESC-[0-9]{3,}", escape_id):
            errors.append(f"{where}.id must match ESC-NNN")
        elif escape_id in seen_escape_ids:
            errors.append(f"{where}.id is duplicated: {escape_id}")
        else:
            seen_escape_ids.add(escape_id)

        for field in ("bug_id", "reported_by"):
            if not nonempty(escape.get(field)):
                errors.append(f"{where}.{field} must be non-empty")

        gate = escape.get("gate")
        if not isinstance(gate, dict):
            errors.append(f"{where}.gate must be an object")
        else:
            if not nonempty(gate.get("gate_id")):
                errors.append(f"{where}.gate.gate_id must be non-empty or 'none'")
            if gate.get("execution_status") not in {
                "executed-missed",
                "not-executed",
                "no-gate",
            }:
                errors.append(f"{where}.gate.execution_status is invalid")
            elif (
                gate.get("execution_status") == "no-gate"
                and gate.get("gate_id") != "none"
            ):
                errors.append(
                    f"{where}.gate no-gate status requires gate_id='none'"
                )
            elif (
                gate.get("execution_status")
                in {"executed-missed", "not-executed"}
                and gate.get("gate_id") == "none"
            ):
                errors.append(
                    f"{where}.gate {gate.get('execution_status')} "
                    "requires a real gate_id"
                )
            refs = gate.get("evidence_refs")
            if not isinstance(refs, list) or not refs or not all(nonempty(v) for v in refs):
                errors.append(f"{where}.gate.evidence_refs must be a non-empty string array")
            else:
                for ref in refs:
                    if not validate_reference(ref, base_dir):
                        errors.append(
                            f"{where}.gate.evidence_refs file does not exist: {ref}"
                        )

        root_causes = escape.get("root_causes")
        if (
            not isinstance(root_causes, list)
            or not root_causes
            or not all(nonempty(v) for v in root_causes)
        ):
            errors.append(f"{where}.root_causes must be a non-empty string array")

        actions = escape.get("corrective_actions")
        action_ids: set[str] = set()
        if not isinstance(actions, list) or not actions:
            errors.append(f"{where}.corrective_actions must be a non-empty array")
            actions = []
        for action_index, action in enumerate(actions):
            action_where = f"{where}.corrective_actions[{action_index}]"
            if not isinstance(action, dict):
                errors.append(f"{action_where} must be an object")
                continue
            action_id = action.get("id")
            if not nonempty(action_id):
                errors.append(f"{action_where}.id must be non-empty")
            elif action_id in action_ids:
                errors.append(f"{action_where}.id is duplicated: {action_id}")
            else:
                action_ids.add(action_id)
            if not nonempty(action.get("description")):
                errors.append(f"{action_where}.description must be non-empty")
            action_status = action.get("status")
            if action_status not in {"planned", "landed", "verified"}:
                errors.append(f"{action_where}.status is invalid")
            refs = action.get("evidence_refs")
            if not isinstance(refs, list) or not all(nonempty(v) for v in refs):
                errors.append(f"{action_where}.evidence_refs must be a string array")
            elif action_status in {"landed", "verified"} and not refs:
                errors.append(f"{action_where} status={action_status} requires evidence_refs")
            else:
                for ref in refs:
                    if not validate_reference(ref, base_dir):
                        errors.append(
                            f"{action_where}.evidence_refs file does not exist: {ref}"
                        )

        status = escape.get("status")
        if status not in {"open", "closed"}:
            errors.append(f"{where}.status is invalid")
        closure = escape.get("closure_evidence")
        if not isinstance(closure, list) or not all(nonempty(v) for v in closure):
            errors.append(f"{where}.closure_evidence must be a string array")
            closure = []
        if status == "closed":
            if not actions or any(
                not isinstance(action, dict) or action.get("status") != "verified"
                for action in actions
            ):
                errors.append(f"{where} cannot close before every action is verified")
            if not closure:
                errors.append(f"{where} status=closed requires closure_evidence")
            else:
                for ref in closure:
                    if not validate_reference(ref, base_dir):
                        errors.append(
                            f"{where}.closure_evidence file does not exist: {ref}"
                        )

    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("ledger", type=Path)
    args = parser.parse_args()
    try:
        document = json.loads(
            args.ledger.read_text(encoding="utf-8"),
            parse_constant=reject_constant,
            object_pairs_hook=reject_duplicate_keys,
        )
    except (OSError, json.JSONDecodeError, ValueError) as exc:
        print(f"INVALID: {exc}", file=sys.stderr)
        return 2
    errors = validate(document, args.ledger.parent)
    if errors:
        for error in errors:
            print(f"INVALID: {error}", file=sys.stderr)
        return 1
    print(f"valid escape ledger: {args.ledger}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Validate an external reference-suite case map without third-party packages."""

from __future__ import annotations

import argparse
from collections import Counter
from datetime import datetime
import json
from pathlib import Path, PurePosixPath
import re
import sys
from typing import Any


SHA40_RE = re.compile(r"^[0-9a-f]{40}$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
SIDE_EFFECTS = {"none", "read", "write", "destructive"}
EXECUTION_LEVELS = {"L0", "L1", "L2", "L3", "L4"}
ADOPTION_STATUSES = {
    "direct",
    "adapted",
    "oracle-only",
    "duplicate",
    "blocked",
    "not-applicable",
    "rejected",
}
ORACLE_TYPES = {
    "reference_implementation",
    "cross_api_invariant",
    "schema_contract",
    "behavioral_baseline",
    "none",
}
SKIP_CATEGORIES = {
    "missing_capability",
    "missing_entitlement",
    "missing_account",
    "market_closed",
    "data_unavailable",
    "rate_limited",
    "upstream_not_implemented",
    "unsafe_without_approval",
    "fixture_failure",
    "product_behavior",
    "unclassified",
}


def reject_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def non_empty_string(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def safe_relative_path(value: Any) -> bool:
    if not non_empty_string(value):
        return False
    path = PurePosixPath(value)
    return not path.is_absolute() and ".." not in path.parts


def validate_string_array(
    value: Any,
    path: str,
    errors: list[str],
    *,
    allowed: set[str] | None = None,
    require_non_empty: bool = False,
) -> list[str]:
    if not isinstance(value, list):
        errors.append(f"{path}: expected an array")
        return []
    if require_non_empty and not value:
        errors.append(f"{path}: expected at least one item")
    normalized: list[str] = []
    for index, item in enumerate(value):
        if not non_empty_string(item):
            errors.append(f"{path}[{index}]: expected a non-empty string")
            continue
        item = item.strip()
        normalized.append(item)
        if allowed is not None and item not in allowed:
            errors.append(f"{path}[{index}]: unsupported value {item!r}")
    duplicates = sorted(item for item, count in Counter(normalized).items() if count > 1)
    if duplicates:
        errors.append(f"{path}: duplicate value(s): {', '.join(repr(x) for x in duplicates)}")
    return normalized


def validate_counts(
    value: Any,
    path: str,
    errors: list[str],
) -> dict[str, int]:
    if not isinstance(value, dict):
        errors.append(f"{path}: expected an object")
        return {}
    normalized: dict[str, int] = {}
    for key, count in value.items():
        if not non_empty_string(key):
            errors.append(f"{path}: expected non-empty string keys")
            continue
        if not isinstance(count, int) or isinstance(count, bool) or count < 0:
            errors.append(f"{path}.{key}: expected a non-negative integer")
            continue
        normalized[key] = count
    return normalized


def validate_document(document: Any) -> list[str]:
    if not isinstance(document, dict):
        return ["document: expected a JSON object"]

    errors: list[str] = []
    required_top = {
        "schema_version",
        "generated_at",
        "suite",
        "summary",
        "danger_scan",
        "cases",
    }
    missing_top = sorted(required_top - set(document))
    if missing_top:
        errors.append(f"document: missing field(s): {', '.join(missing_top)}")
        return errors
    unknown_top = sorted(set(document) - required_top)
    if unknown_top:
        errors.append(f"document: unknown field(s): {', '.join(unknown_top)}")

    if document.get("schema_version") != 1:
        errors.append("schema_version: expected 1")
    generated_at = document.get("generated_at")
    if not non_empty_string(generated_at):
        errors.append("generated_at: expected an ISO 8601 timestamp")
    else:
        try:
            datetime.fromisoformat(generated_at.replace("Z", "+00:00"))
        except ValueError:
            errors.append("generated_at: expected an ISO 8601 timestamp")

    suite = document.get("suite")
    if not isinstance(suite, dict):
        errors.append("suite: expected an object")
        suite = {}
    suite_required = {"id", "repo_url", "branch", "commit", "dirty"}
    missing_suite = sorted(suite_required - set(suite))
    if missing_suite:
        errors.append(f"suite: missing field(s): {', '.join(missing_suite)}")
    unknown_suite = sorted(set(suite) - suite_required)
    if unknown_suite:
        errors.append(f"suite: unknown field(s): {', '.join(unknown_suite)}")
    for field in ("id", "repo_url", "branch"):
        if not non_empty_string(suite.get(field)):
            errors.append(f"suite.{field}: expected a non-empty string")
    if not isinstance(suite.get("commit"), str) or not SHA40_RE.fullmatch(
        suite.get("commit", "")
    ):
        errors.append("suite.commit: expected a 40-character lowercase git SHA")
    if not isinstance(suite.get("dirty"), bool):
        errors.append("suite.dirty: expected a boolean")

    danger_scan = document.get("danger_scan")
    if not isinstance(danger_scan, dict):
        errors.append("danger_scan: expected an object")
        danger_scan = {}
    if danger_scan.get("completed") is not True:
        errors.append("danger_scan.completed: must be true before activation")
    findings = danger_scan.get("findings")
    if not isinstance(findings, list):
        errors.append("danger_scan.findings: expected an array")
        findings = []
    finding_ids: list[str] = []
    for index, finding in enumerate(findings):
        path = f"danger_scan.findings[{index}]"
        if not isinstance(finding, dict):
            errors.append(f"{path}: expected an object")
            continue
        required = {"id", "kind", "severity", "path", "line", "message"}
        missing = sorted(required - set(finding))
        if missing:
            errors.append(f"{path}: missing field(s): {', '.join(missing)}")
            continue
        finding_id = finding.get("id")
        if not non_empty_string(finding_id):
            errors.append(f"{path}.id: expected a non-empty string")
        else:
            finding_ids.append(finding_id.strip())
        if not non_empty_string(finding.get("kind")):
            errors.append(f"{path}.kind: expected a non-empty string")
        if finding.get("severity") not in {"info", "warning", "high"}:
            errors.append(f"{path}.severity: unsupported value")
        if not safe_relative_path(finding.get("path")):
            errors.append(f"{path}.path: expected a safe relative path")
        if (
            not isinstance(finding.get("line"), int)
            or isinstance(finding.get("line"), bool)
            or finding.get("line", 0) < 1
        ):
            errors.append(f"{path}.line: expected an integer >= 1")
        if not non_empty_string(finding.get("message")):
            errors.append(f"{path}.message: expected a non-empty string")
    duplicate_findings = sorted(
        item for item, count in Counter(finding_ids).items() if count > 1
    )
    if duplicate_findings:
        errors.append(
            "danger_scan.findings: duplicate id(s): "
            + ", ".join(repr(item) for item in duplicate_findings)
        )

    cases = document.get("cases")
    if not isinstance(cases, list):
        errors.append("cases: expected an array")
        cases = []
    case_ids: list[str] = []
    case_files: set[str] = set()
    side_effect_counter: Counter[str] = Counter()
    adoption_counter: Counter[str] = Counter()
    for index, case in enumerate(cases):
        path = f"cases[{index}]"
        if not isinstance(case, dict):
            errors.append(f"{path}: expected an object")
            continue
        required = {
            "id",
            "file",
            "class",
            "function",
            "markers",
            "fixtures",
            "call_names",
            "side_effect",
            "execution_level",
            "adoption_status",
            "target_test_ids",
            "oracle_type",
            "environment",
            "skip_categories",
            "evidence_boundary",
            "source_hash",
        }
        missing = sorted(required - set(case))
        if missing:
            errors.append(f"{path}: missing field(s): {', '.join(missing)}")
            continue
        unknown = sorted(set(case) - required)
        if unknown:
            errors.append(f"{path}: unknown field(s): {', '.join(unknown)}")

        case_id = case.get("id")
        if not non_empty_string(case_id):
            errors.append(f"{path}.id: expected a non-empty string")
        else:
            case_ids.append(case_id.strip())
        file_path = case.get("file")
        if not safe_relative_path(file_path):
            errors.append(f"{path}.file: expected a safe relative path")
        else:
            case_files.add(file_path)
        class_name = case.get("class")
        if not isinstance(class_name, str):
            errors.append(f"{path}.class: expected a string")
        function = case.get("function")
        if not non_empty_string(function) or not function.startswith("test_"):
            errors.append(f"{path}.function: expected a test_ function name")

        validate_string_array(case.get("markers"), f"{path}.markers", errors)
        validate_string_array(case.get("fixtures"), f"{path}.fixtures", errors)
        validate_string_array(case.get("call_names"), f"{path}.call_names", errors)
        validate_string_array(
            case.get("target_test_ids"),
            f"{path}.target_test_ids",
            errors,
            require_non_empty=True,
        )
        validate_string_array(case.get("environment"), f"{path}.environment", errors)
        validate_string_array(
            case.get("skip_categories"),
            f"{path}.skip_categories",
            errors,
            allowed=SKIP_CATEGORIES,
        )

        side_effect = case.get("side_effect")
        if side_effect not in SIDE_EFFECTS:
            errors.append(f"{path}.side_effect: unsupported value {side_effect!r}")
        else:
            side_effect_counter[side_effect] += 1
        execution_level = case.get("execution_level")
        if execution_level not in EXECUTION_LEVELS:
            errors.append(
                f"{path}.execution_level: unsupported value {execution_level!r}"
            )
        adoption_status = case.get("adoption_status")
        if adoption_status not in ADOPTION_STATUSES:
            errors.append(
                f"{path}.adoption_status: unsupported value {adoption_status!r}"
            )
        else:
            adoption_counter[adoption_status] += 1
        oracle_type = case.get("oracle_type")
        if oracle_type not in ORACLE_TYPES:
            errors.append(f"{path}.oracle_type: unsupported value {oracle_type!r}")
        if not non_empty_string(case.get("evidence_boundary")):
            errors.append(f"{path}.evidence_boundary: expected a non-empty string")
        source_hash = case.get("source_hash")
        if not isinstance(source_hash, str) or not SHA256_RE.fullmatch(source_hash):
            errors.append(f"{path}.source_hash: expected a lowercase SHA-256")

    duplicate_cases = sorted(
        item for item, count in Counter(case_ids).items() if count > 1
    )
    if duplicate_cases:
        errors.append(
            "cases: duplicate id(s): "
            + ", ".join(repr(item) for item in duplicate_cases)
        )

    summary = document.get("summary")
    if not isinstance(summary, dict):
        errors.append("summary: expected an object")
        summary = {}
    summary_required = {
        "files",
        "static_tests",
        "cases",
        "side_effects",
        "adoption_statuses",
    }
    missing_summary = sorted(summary_required - set(summary))
    if missing_summary:
        errors.append(f"summary: missing field(s): {', '.join(missing_summary)}")
    unknown_summary = sorted(set(summary) - summary_required)
    if unknown_summary:
        errors.append(f"summary: unknown field(s): {', '.join(unknown_summary)}")

    expected_counts = {
        "files": len(case_files),
        "static_tests": len(cases),
        "cases": len(cases),
    }
    for field, expected in expected_counts.items():
        actual = summary.get(field)
        if actual != expected:
            errors.append(f"summary.{field}: expected {expected}, got {actual!r}")
    declared_side_effects = validate_counts(
        summary.get("side_effects"), "summary.side_effects", errors
    )
    if declared_side_effects != dict(sorted(side_effect_counter.items())):
        errors.append(
            "summary.side_effects: does not match cases "
            f"(expected {dict(sorted(side_effect_counter.items()))!r})"
        )
    declared_statuses = validate_counts(
        summary.get("adoption_statuses"), "summary.adoption_statuses", errors
    )
    if declared_statuses != dict(sorted(adoption_counter.items())):
        errors.append(
            "summary.adoption_statuses: does not match cases "
            f"(expected {dict(sorted(adoption_counter.items()))!r})"
        )

    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("map_file", type=Path)
    args = parser.parse_args()
    try:
        document = json.loads(
            args.map_file.read_text(encoding="utf-8"),
            object_pairs_hook=reject_duplicate_keys,
        )
    except (OSError, json.JSONDecodeError, ValueError) as exc:
        print(f"reference suite map parse failed: {exc}", file=sys.stderr)
        return 1
    errors = validate_document(document)
    if errors:
        for error in errors:
            print(error, file=sys.stderr)
        return 1
    print(
        "reference suite map validation passed: "
        f"{len(document['cases'])} cases from {document['summary']['files']} files"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

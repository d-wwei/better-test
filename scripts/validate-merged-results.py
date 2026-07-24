#!/usr/bin/env python3
"""Validate merged results against their immutable source results."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from typing import Any


ALLOWED_RESULTS = {"pass", "fail", "skip", "conflict"}
ALLOWED_GATE_VERDICTS = {"pass", "fail", "blocked", "skip"}
ALLOWED_DOD_VERDICTS = {"pass", "fail", "blocked", "not_applicable"}
ALLOWED_RELEASE_VERDICTS = {"go", "no-go", "blocked", "not_applicable"}
ALLOWED_DISPOSITIONS = {"accepted", "rejected", "unresolved"}
SUMMARY_FIELDS = {
    "total": None,
    "passed": "pass",
    "failed": "fail",
    "skipped": "skip",
    "conflicts": "conflict",
}
SHA256_PATTERN = re.compile(r"^[0-9a-f]{64}$")


def nonempty(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def trimmed_nonempty(value: Any) -> bool:
    return nonempty(value) and value == value.strip()


def parse_timestamp(
    value: Any,
    field: str,
    errors: list[str],
) -> datetime | None:
    if not trimmed_nonempty(value):
        errors.append(f"{field} must be a trimmed ISO 8601 timestamp")
        return None
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        errors.append(f"{field} must be a valid ISO 8601 timestamp")
        return None
    if parsed.tzinfo is None or parsed.utcoffset() is None:
        errors.append(f"{field} must include a timezone")
        return None
    return parsed


def normalized(value: Any) -> str:
    return value.strip().lower() if isinstance(value, str) else ""


def duplicates(values: list[str]) -> list[str]:
    seen: set[str] = set()
    repeated: list[str] = []
    for value in values:
        if value in seen and value not in repeated:
            repeated.append(value)
        seen.add(value)
    return repeated


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_json(path: Path) -> Any:
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


def source_status_category(status: Any) -> str:
    value = normalized(status)
    if value.startswith("pass"):
        return "pass"
    if value in {"fail", "partial_fail", "partial-fail"}:
        return "fail"
    if value in {"skip", "excluded"}:
        return "skip"
    return "conflict"


def merged_result_for(categories: list[str]) -> str:
    if "fail" in categories:
        return "fail"
    unique = set(categories)
    if len(unique) == 1:
        return next(iter(unique))
    return "conflict"


def merged_gate_verdict(verdicts: list[str]) -> str:
    priority = {"pass": 0, "skip": 1, "blocked": 2, "fail": 3}
    return max(verdicts, key=lambda verdict: priority.get(verdict, 4))


def merged_dod_verdict(verdicts: list[str]) -> str:
    priority = {"pass": 0, "not_applicable": 1, "blocked": 2, "fail": 3}
    return max(verdicts, key=lambda verdict: priority.get(verdict, 4))


def validate_source_run(
    entry: Any,
    index: int,
    merged_path: Path,
    source_validator: Path,
    errors: list[str],
) -> tuple[str | None, dict[str, Any] | None, Path | None]:
    where = f"source_runs[{index}]"
    if not isinstance(entry, dict):
        errors.append(f"{where} must be an object")
        return None, None, None

    run_id = entry.get("run_id")
    results_path_value = entry.get("results_path")
    expected_sha = entry.get("sha256")
    if not nonempty(run_id):
        errors.append(f"{where}.run_id must be non-empty")
        run_id = None
    else:
        run_id = run_id.strip()
    if not nonempty(results_path_value):
        errors.append(f"{where}.results_path must be non-empty")
        return run_id, None, None
    if not nonempty(expected_sha) or not SHA256_PATTERN.fullmatch(expected_sha):
        errors.append(f"{where}.sha256 must be a lowercase SHA-256 digest")

    declared_path = Path(results_path_value)
    if declared_path.name != "results.json":
        errors.append(f"{where}.results_path must reference a file named results.json")
    source_path = (
        declared_path
        if declared_path.is_absolute()
        else merged_path.parent / declared_path
    )
    try:
        source_path = source_path.resolve(strict=True)
    except OSError as error:
        errors.append(f"{where}.results_path cannot be resolved: {error}")
        return run_id, None, None
    if not source_path.is_file():
        errors.append(f"{where}.results_path is not a regular file")
        return run_id, None, source_path

    actual_sha = sha256_file(source_path)
    if expected_sha != actual_sha:
        errors.append(
            f"{where}.sha256 does not match results.json "
            f"(expected {expected_sha!r}, actual {actual_sha})"
        )

    try:
        source_document = load_json(source_path)
    except (OSError, json.JSONDecodeError, ValueError) as error:
        errors.append(f"{where}.results_path is not valid JSON: {error}")
        return run_id, None, source_path
    if not isinstance(source_document, dict):
        errors.append(f"{where}.results_path root must be an object")
        return run_id, None, source_path

    source_is_strict = True
    try:
        validation = subprocess.run(
            [str(source_validator), str(source_path)],
            cwd=str(source_validator.parent.parent),
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError as error:
        errors.append(f"{where} could not run validate-results.sh: {error}")
        source_is_strict = False
    else:
        if validation.returncode != 0:
            errors.append(
                f"{where}.results_path failed validate-results.sh "
                f"(exit {validation.returncode})"
            )
            source_is_strict = False

    if not source_is_strict:
        return run_id, None, source_path

    for field in ("run_id", "schema_version", "version", "package_type"):
        if entry.get(field) != source_document.get(field):
            errors.append(
                f"{where}.{field} does not match referenced results.json"
            )
    if type(entry.get("schema_version")) is not int or entry.get(
        "schema_version"
    ) != 3:
        errors.append(f"{where}.schema_version must be integer 3")

    declared_environment = entry.get("environment")
    source_environment = source_document.get("environment")
    if not isinstance(declared_environment, dict):
        errors.append(f"{where}.environment must be an object")
    elif declared_environment != source_environment:
        errors.append(
            f"{where}.environment does not match referenced results.json"
        )
    else:
        for field in ("environment_id", "machine_id", "config_profile"):
            if not nonempty(declared_environment.get(field)):
                errors.append(f"{where}.environment.{field} must be non-empty")

    return run_id, source_document, source_path


def validate(
    document: Any,
    merged_path: Path,
    source_validator: Path,
) -> list[str]:
    errors: list[str] = []
    if not isinstance(document, dict):
        return ["root must be an object"]
    if type(document.get("schema_version")) is not int or document.get(
        "schema_version"
    ) != 2:
        errors.append("schema_version must be integer 2")
    for field in ("version", "merge_id", "coordinator_id"):
        if not trimmed_nonempty(document.get(field)):
            errors.append(f"{field} must be a trimmed non-empty string")
    merged_at = parse_timestamp(document.get("merged_at"), "merged_at", errors)

    source_runs = document.get("source_runs")
    if not isinstance(source_runs, list) or not source_runs:
        return errors + ["source_runs must be a non-empty array"]
    if not source_validator.is_file():
        errors.append(f"source validator does not exist: {source_validator}")

    source_documents: dict[str, dict[str, Any]] = {}
    source_paths: list[str] = []
    declared_run_ids: list[str] = []
    for index, entry in enumerate(source_runs):
        run_id, source_document, source_path = validate_source_run(
            entry,
            index,
            merged_path,
            source_validator,
            errors,
        )
        if run_id is not None:
            declared_run_ids.append(run_id)
        if source_path is not None:
            source_paths.append(str(source_path))
        if run_id is not None and source_document is not None:
            source_documents.setdefault(run_id, source_document)

    for run_id in duplicates(declared_run_ids):
        errors.append(f"source_runs run_id is duplicated: {run_id}")
    for source_path in duplicates(source_paths):
        errors.append(f"source_runs results_path is duplicated: {source_path}")

    merged_version = document.get("version")
    for run_id, source in source_documents.items():
        if source.get("version") != merged_version:
            errors.append(
                f"source run {run_id} version does not match merged version"
            )
        source_finished = parse_timestamp(
            source.get("finished_at"),
            f"source run {run_id} finished_at",
            errors,
        )
        if (
            merged_at is not None
            and source_finished is not None
            and source_finished > merged_at
        ):
            errors.append(
                f"source run {run_id} finished_at cannot be after merged_at"
            )

    environments = {
        source.get("environment", {}).get("environment_id")
        for source in source_documents.values()
        if nonempty(source.get("environment", {}).get("environment_id"))
    }
    machines = {
        source.get("environment", {}).get("machine_id")
        for source in source_documents.values()
        if nonempty(source.get("environment", {}).get("machine_id"))
    }
    profiles = {
        source.get("environment", {}).get("config_profile")
        for source in source_documents.values()
        if nonempty(source.get("environment", {}).get("config_profile"))
    }
    coverage = document.get("environment_coverage")
    if not isinstance(coverage, dict):
        errors.append("environment_coverage must be an object")
    else:
        if type(coverage.get("distinct_environments")) is not int:
            errors.append("distinct_environments must be an integer")
        elif coverage.get("distinct_environments") != len(environments):
            errors.append("distinct_environments does not match source_runs")
        if type(coverage.get("distinct_machines")) is not int:
            errors.append("distinct_machines must be an integer")
        elif coverage.get("distinct_machines") != len(machines):
            errors.append("distinct_machines does not match source_runs")
        config_profiles = coverage.get("config_profiles")
        if (
            not isinstance(config_profiles, list)
            or any(not nonempty(profile) for profile in config_profiles)
        ):
            errors.append("config_profiles do not match source_runs")
        else:
            normalized_profiles = [profile.strip() for profile in config_profiles]
            if (
                duplicates(normalized_profiles)
                or sorted(normalized_profiles) != sorted(profiles)
            ):
                errors.append("config_profiles do not match source_runs")

    source_items: dict[tuple[str, str], dict[str, Any]] = {}
    expected_item_runs: dict[str, set[str]] = {}
    expected_item_definitions: dict[str, tuple[Any, Any, Any, Any]] = {}
    source_evidence: dict[tuple[str, str], str] = {}
    source_gates: dict[tuple[str, str], dict[str, Any]] = {}
    expected_gate_runs: dict[str, set[str]] = {}
    expected_gate_scopes: dict[str, frozenset[str]] = {}
    expected_dod_checks: set[tuple[str, str]] = set()
    for run_id, source in source_documents.items():
        for item in source.get("items", []):
            if not isinstance(item, dict) or not nonempty(item.get("id")):
                continue
            item_id = item["id"]
            source_items[(run_id, item_id)] = item
            expected_item_runs.setdefault(item_id, set()).add(run_id)
            definition = tuple(
                item.get(field)
                for field in ("name", "group", "type", "assertion_field")
            )
            previous_definition = expected_item_definitions.setdefault(
                item_id, definition
            )
            if definition != previous_definition:
                errors.append(
                    f"source item {item_id} definition drift across runs "
                    "(name/group/type/assertion_field)"
                )
            for evidence in item.get("evidence_sources", []):
                if isinstance(evidence, dict) and nonempty(
                    evidence.get("source_id")
                ):
                    source_evidence[(run_id, evidence["source_id"])] = item_id
        for gate in source.get("gate_items", []):
            if not isinstance(gate, dict) or not nonempty(gate.get("gate_id")):
                continue
            gate_id = gate["gate_id"]
            source_gates[(run_id, gate_id)] = gate
            expected_gate_runs.setdefault(gate_id, set()).add(run_id)
            gate_scope = frozenset(
                item_id
                for item_id in gate.get("item_ids", [])
                if nonempty(item_id)
            )
            previous_scope = expected_gate_scopes.setdefault(gate_id, gate_scope)
            if gate_scope != previous_scope:
                errors.append(
                    f"source gate {gate_id} item scope drift across runs"
                )
        dod = source.get("dod")
        if isinstance(dod, dict):
            for check in dod.get("check_results", []):
                if isinstance(check, dict) and nonempty(check.get("check_id")):
                    expected_dod_checks.add((run_id, check["check_id"]))

    items = document.get("items")
    if not isinstance(items, list):
        errors.append("items must be an array")
        items = []
    merged_item_ids: list[str] = []
    merged_item_results: list[str] = []
    for index, item in enumerate(items):
        where = f"items[{index}]"
        if not isinstance(item, dict):
            errors.append(f"{where} must be an object")
            continue
        item_id = item.get("id")
        result = normalized(item.get("result"))
        if not nonempty(item_id):
            errors.append(f"{where}.id must be non-empty")
            continue
        item_id = item_id.strip()
        merged_item_ids.append(item_id)
        if result not in ALLOWED_RESULTS:
            errors.append(f"{where}.result is invalid")
        else:
            merged_item_results.append(result)
        item_source_runs = item.get("source_runs")
        if not isinstance(item_source_runs, list) or not item_source_runs:
            errors.append(f"{where}.source_runs must be a non-empty array")
            continue
        valid_item_source_runs = [
            run_id.strip()
            for run_id in item_source_runs
            if nonempty(run_id)
        ]
        if len(valid_item_source_runs) != len(item_source_runs):
            errors.append(f"{where}.source_runs entries must be non-empty")
        if duplicates(valid_item_source_runs):
            errors.append(f"{where}.source_runs contains duplicates")
        expected_item_source_runs = expected_item_runs.get(item_id, set())
        if set(valid_item_source_runs) != expected_item_source_runs:
            errors.append(
                f"{where}.source_runs do not cover every source item occurrence"
            )
        categories: list[str] = []
        for run_id in valid_item_source_runs:
            if run_id not in source_documents:
                errors.append(f"{where} references unknown source run {run_id}")
                continue
            source_item = source_items.get((run_id, item_id))
            if source_item is None:
                errors.append(
                    f"{where} is absent from source run {run_id} results.json"
                )
                continue
            categories.append(source_status_category(source_item.get("status")))
        if categories and result in ALLOWED_RESULTS:
            expected_result = merged_result_for(categories)
            if result != expected_result:
                errors.append(
                    f"{where}.result={result} does not match source results "
                    f"(expected {expected_result})"
                )
        if result == "conflict" and not nonempty(item.get("conflict_details")):
            errors.append(f"{where}.conflict_details is required for conflict")

    for item_id in duplicates(merged_item_ids):
        errors.append(f"merged item id is duplicated: {item_id}")
    if set(merged_item_ids) != set(expected_item_runs):
        errors.append("merged items do not cover every source item")
    merged_item_id_set = set(merged_item_ids)

    summary = document.get("summary")
    summary_is_nonempty = isinstance(summary, dict) and bool(summary)
    if not isinstance(summary, dict):
        errors.append("summary must be an object")
        summary = {}
    for field, result in SUMMARY_FIELDS.items():
        value = summary.get(field)
        if not isinstance(value, int) or isinstance(value, bool) or value < 0:
            errors.append(f"summary.{field} must be a non-negative integer")
            continue
        expected = (
            len(items)
            if result is None
            else sum(item_result == result for item_result in merged_item_results)
        )
        if value != expected:
            errors.append(
                f"summary.{field}={value} does not match items ({expected})"
            )

    gates = document.get("gate_items")
    if not isinstance(gates, list):
        errors.append("gate_items must be an array")
        gates = []
    merged_gate_ids: list[str] = []
    for index, gate in enumerate(gates):
        where = f"gate_items[{index}]"
        if not isinstance(gate, dict):
            errors.append(f"{where} must be an object")
            continue
        gate_id = gate.get("gate_id")
        verdict = normalized(gate.get("verdict"))
        if not nonempty(gate_id):
            errors.append(f"{where}.gate_id must be non-empty")
            continue
        gate_id = gate_id.strip()
        merged_gate_ids.append(gate_id)
        if verdict not in ALLOWED_GATE_VERDICTS:
            errors.append(f"{where}.verdict is invalid")
        if not nonempty(gate.get("reason")):
            errors.append(f"{where}.reason must be non-empty")

        gate_source_runs = gate.get("source_runs")
        if not isinstance(gate_source_runs, list) or not gate_source_runs:
            errors.append(f"{where}.source_runs must be a non-empty array")
            gate_source_runs = []
        valid_gate_source_runs = [
            run_id.strip()
            for run_id in gate_source_runs
            if nonempty(run_id)
        ]
        if (
            len(valid_gate_source_runs) != len(gate_source_runs)
            or duplicates(valid_gate_source_runs)
        ):
            errors.append(f"{where}.source_runs must contain unique non-empty run IDs")
        expected_runs = expected_gate_runs.get(gate_id, set())
        if set(valid_gate_source_runs) != expected_runs:
            errors.append(
                f"{where}.source_runs do not match source gate occurrences"
            )

        item_ids = gate.get("item_ids")
        if not isinstance(item_ids, list) or not item_ids:
            errors.append(f"{where}.item_ids must be a non-empty array")
            item_ids = []
        valid_item_ids = [
            item_id.strip() for item_id in item_ids if nonempty(item_id)
        ]
        if (
            len(valid_item_ids) != len(item_ids)
            or duplicates(valid_item_ids)
        ):
            errors.append(f"{where}.item_ids must contain unique non-empty IDs")
        for item_id in valid_item_ids:
            if item_id not in merged_item_id_set:
                errors.append(f"{where} references unknown merged item {item_id}")

        expected_items: set[str] = set()
        expected_evidence: set[tuple[str, str]] = set()
        source_verdicts: list[str] = []
        for run_id in valid_gate_source_runs:
            source_gate = source_gates.get((run_id, gate_id))
            if source_gate is None:
                continue
            source_verdicts.append(normalized(source_gate.get("verdict")))
            expected_items.update(source_gate.get("item_ids", []))
            expected_evidence.update(
                (run_id, source_id)
                for source_id in source_gate.get("evidence_refs", [])
            )
        if set(valid_item_ids) != expected_items:
            errors.append(f"{where}.item_ids do not match source gates")
        if source_verdicts and verdict in ALLOWED_GATE_VERDICTS:
            expected_verdict = merged_gate_verdict(source_verdicts)
            if verdict != expected_verdict:
                errors.append(
                    f"{where}.verdict={verdict} does not match source gates "
                    f"(expected {expected_verdict})"
                )

        evidence_refs = gate.get("evidence_refs")
        actual_evidence: set[tuple[str, str]] = set()
        if not isinstance(evidence_refs, list) or not evidence_refs:
            errors.append(f"{where}.evidence_refs must be a non-empty array")
            evidence_refs = []
        for ref_index, evidence_ref in enumerate(evidence_refs):
            ref_where = f"{where}.evidence_refs[{ref_index}]"
            if not isinstance(evidence_ref, dict):
                errors.append(f"{ref_where} must be an object")
                continue
            run_id = evidence_ref.get("source_run")
            source_id = evidence_ref.get("source_id")
            if not nonempty(run_id) or not nonempty(source_id):
                errors.append(
                    f"{ref_where} requires non-empty source_run and source_id"
                )
                continue
            ref = (run_id, source_id)
            if ref in actual_evidence:
                errors.append(f"{ref_where} duplicates an evidence reference")
            actual_evidence.add(ref)
            if run_id not in valid_gate_source_runs:
                errors.append(
                    f"{ref_where}.source_run is not listed by the merged gate"
                )
            owner_item = source_evidence.get(ref)
            if owner_item is None:
                errors.append(f"{ref_where} does not reference real evidence")
            elif owner_item not in valid_item_ids:
                errors.append(
                    f"{ref_where} evidence belongs to unreferenced item "
                    f"{owner_item}"
                )
        if actual_evidence != expected_evidence:
            errors.append(f"{where}.evidence_refs do not match source gates")

    for gate_id in duplicates(merged_gate_ids):
        errors.append(f"merged gate_id is duplicated: {gate_id}")
    if set(merged_gate_ids) != set(expected_gate_runs):
        errors.append("merged gate_items do not cover every source gate")

    dod = document.get("dod")
    dod_is_nonempty = isinstance(dod, dict) and bool(dod)
    if not isinstance(dod, dict):
        errors.append("dod must be an object")
        dod = {}
    package_types = {
        source.get("package_type")
        for source in source_documents.values()
        if nonempty(source.get("package_type"))
    }
    if len(package_types) != 1:
        errors.append("source runs must have exactly one package_type")
    if dod.get("package_type") not in package_types:
        errors.append("dod.package_type does not match source runs")
    dod_verdict = normalized(dod.get("verdict"))
    if dod_verdict not in ALLOWED_DOD_VERDICTS:
        errors.append("dod.verdict is invalid")
    source_dod_verdicts = [
        normalized(source.get("dod", {}).get("verdict"))
        for source in source_documents.values()
    ]
    if source_dod_verdicts and dod_verdict in ALLOWED_DOD_VERDICTS:
        expected_dod_verdict = merged_dod_verdict(source_dod_verdicts)
        if dod_verdict != expected_dod_verdict:
            errors.append(
                "dod.verdict does not match source runs "
                f"(expected {expected_dod_verdict})"
            )
    dod_source_runs = dod.get("source_runs")
    valid_dod_source_runs = (
        [
            run_id.strip()
            for run_id in dod_source_runs
            if nonempty(run_id)
        ]
        if isinstance(dod_source_runs, list)
        else []
    )
    if (
        not isinstance(dod_source_runs, list)
        or len(valid_dod_source_runs) != len(dod_source_runs)
        or duplicates(valid_dod_source_runs)
        or set(valid_dod_source_runs) != set(source_documents)
    ):
        errors.append("dod.source_runs must list every source run exactly once")

    check_refs = dod.get("check_refs")
    actual_check_refs: set[tuple[str, str]] = set()
    if not isinstance(check_refs, list):
        errors.append("dod.check_refs must be an array")
        check_refs = []
    for index, check_ref in enumerate(check_refs):
        where = f"dod.check_refs[{index}]"
        if not isinstance(check_ref, dict):
            errors.append(f"{where} must be an object")
            continue
        run_id = check_ref.get("source_run")
        check_id = check_ref.get("check_id")
        if not nonempty(run_id) or not nonempty(check_id):
            errors.append(
                f"{where} requires non-empty source_run and check_id"
            )
            continue
        ref = (run_id, check_id)
        if ref in actual_check_refs:
            errors.append(f"{where} duplicates a DoD check reference")
        actual_check_refs.add(ref)
        if ref not in expected_dod_checks:
            errors.append(f"{where} does not reference a real source DoD check")
    if actual_check_refs != expected_dod_checks:
        errors.append("dod.check_refs do not match source DoD checks")

    readiness = document.get("release_readiness")
    if not isinstance(readiness, dict):
        errors.append("release_readiness must be an object")
        readiness = {}
    verdict = normalized(readiness.get("verdict"))
    if verdict not in ALLOWED_RELEASE_VERDICTS:
        errors.append("release_readiness.verdict is invalid")
    if not nonempty(readiness.get("reason")):
        errors.append("release_readiness.reason must be non-empty")

    challenge = document.get("verdict_challenge")
    if not isinstance(challenge, dict):
        errors.append("verdict_challenge must be an object")
        challenge = {}
    drafted_by = challenge.get("drafted_by")
    challenger = challenge.get("challenger")
    if not nonempty(drafted_by) or not nonempty(challenger):
        errors.append("verdict_challenge requires drafted_by and challenger")
        drafted_by_value = ""
        challenger_value = ""
    else:
        drafted_by_value = drafted_by.strip()
        challenger_value = challenger.strip()
        if not trimmed_nonempty(drafted_by) or not trimmed_nonempty(challenger):
            errors.append(
                "verdict_challenge drafted_by and challenger must not have "
                "leading/trailing whitespace"
            )
        if drafted_by_value == challenger_value:
            errors.append("verdict challenger must differ from coordinator/drafter")
    coordinator_value = (
        document["coordinator_id"].strip()
        if nonempty(document.get("coordinator_id"))
        else ""
    )
    if drafted_by_value and drafted_by_value != coordinator_value:
        errors.append("verdict_challenge.drafted_by must equal coordinator_id")
    source_tester_ids = {
        source.get("tester_id").strip()
        for source in source_documents.values()
        if nonempty(source.get("tester_id"))
    }
    if challenger_value and challenger_value not in source_tester_ids:
        external_reviewer = challenge.get("external_reviewer")
        external_reviewer_valid = not (
            not isinstance(external_reviewer, dict)
            or not trimmed_nonempty(external_reviewer.get("reviewer_id"))
            or external_reviewer["reviewer_id"].strip() != challenger_value
            or not trimmed_nonempty(external_reviewer.get("identity"))
            or not trimmed_nonempty(external_reviewer.get("evidence_ref"))
        )
        if not external_reviewer_valid:
            errors.append(
                "external verdict challenger requires matching reviewer_id, "
                "identity and evidence_ref"
            )
        else:
            evidence_text = external_reviewer["evidence_ref"].split("#", 1)[0]
            evidence_path = Path(evidence_text)
            if not evidence_path.is_absolute():
                evidence_path = merged_path.parent / evidence_path
            try:
                evidence_path = evidence_path.resolve(strict=True)
                evidence_path.relative_to(merged_path.parent.resolve())
            except (OSError, ValueError):
                errors.append(
                    "external reviewer evidence_ref must resolve to a file "
                    "inside the merge directory"
                )
            else:
                if not evidence_path.is_file():
                    errors.append(
                        "external reviewer evidence_ref must reference a file"
                    )
    if not trimmed_nonempty(challenge.get("reason")):
        errors.append("verdict_challenge.reason must be trimmed and non-empty")
    reviewed_at = parse_timestamp(
        challenge.get("reviewed_at"),
        "verdict_challenge.reviewed_at",
        errors,
    )
    if (
        reviewed_at is not None
        and merged_at is not None
        and reviewed_at < merged_at
    ):
        errors.append("verdict_challenge.reviewed_at cannot be before merged_at")

    dispositions = challenge.get("dispositions")
    if not isinstance(dispositions, list):
        errors.append("verdict_challenge.dispositions must be an array")
        dispositions = []
    disposition_ids: list[str] = []
    unresolved_actual = 0
    for index, disposition in enumerate(dispositions):
        where = f"verdict_challenge.dispositions[{index}]"
        if not isinstance(disposition, dict):
            errors.append(f"{where} must be an object")
            continue
        challenge_id = disposition.get("challenge_id")
        disposition_value = normalized(disposition.get("disposition"))
        if not nonempty(challenge_id):
            errors.append(f"{where}.challenge_id must be non-empty")
        else:
            disposition_ids.append(challenge_id.strip())
        if disposition_value not in ALLOWED_DISPOSITIONS:
            errors.append(f"{where}.disposition is invalid")
        elif disposition_value == "unresolved":
            unresolved_actual += 1
        if not nonempty(disposition.get("reason")):
            errors.append(f"{where}.reason must be non-empty")
    for challenge_id in duplicates(disposition_ids):
        errors.append(f"verdict challenge id is duplicated: {challenge_id}")

    unresolved = challenge.get("unresolved_count")
    if (
        not isinstance(unresolved, int)
        or isinstance(unresolved, bool)
        or unresolved < 0
    ):
        errors.append(
            "verdict_challenge.unresolved_count must be a non-negative integer"
        )
    elif unresolved != unresolved_actual:
        errors.append(
            "verdict_challenge.unresolved_count does not match dispositions "
            f"({unresolved_actual})"
        )

    if verdict == "go":
        if not items:
            errors.append("GO requires non-empty items")
        if not summary_is_nonempty or summary.get("total") == 0:
            errors.append("GO requires a non-empty summary")
        if not dod_is_nonempty:
            errors.append("GO requires non-empty DoD")
        if not check_refs:
            errors.append("GO requires non-empty DoD check_refs")
        if dod_verdict != "pass":
            errors.append("GO requires merged DoD pass")
        if any(
            isinstance(gate, dict)
            and normalized(gate.get("verdict")) in {"fail", "blocked"}
            for gate in gates
        ):
            errors.append("GO cannot contain fail/blocked gate")
        if summary.get("failed", 0) != 0 or summary.get("conflicts", 0) != 0:
            errors.append("GO cannot contain failed/conflict items")
        source_go_count = 0
        for run_id, source in source_documents.items():
            source_readiness = normalized(
                source.get("release_readiness", {}).get("verdict")
            )
            if source_readiness not in {"go", "not_applicable"}:
                errors.append(
                    f"GO rejects source run {run_id} "
                    f"release_readiness={source_readiness or '<missing>'}"
                )
            elif source_readiness == "go":
                source_go_count += 1
        if source_go_count == 0:
            errors.append(
                "GO requires at least one release-scoped source run with "
                "release_readiness=go; targeted not_applicable runs cannot "
                "create release approval"
            )
        if unresolved != 0:
            errors.append("GO requires zero unresolved verdict challenges")

    return errors


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Validate merged results and bind them to immutable source "
            "results.json files."
        )
    )
    parser.add_argument("merged_results", type=Path)
    arguments = parser.parse_args()
    merged_path = arguments.merged_results.resolve()
    source_validator = Path(__file__).resolve().with_name("validate-results.sh")
    try:
        document = load_json(merged_path)
    except (OSError, json.JSONDecodeError, ValueError) as error:
        print(f"INVALID: {error}", file=sys.stderr)
        return 2
    errors = validate(document, merged_path, source_validator)
    if errors:
        for error in errors:
            print(f"INVALID: {error}", file=sys.stderr)
        return 1
    print(f"valid merged results: {merged_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

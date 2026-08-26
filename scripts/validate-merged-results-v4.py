#!/usr/bin/env python3
"""Validate a v4 merge without collapsing typed subjects or evidence semantics."""

from __future__ import annotations

import argparse
import json
import os
import sys
from collections import Counter
from datetime import datetime
from pathlib import Path
from typing import Any

from hybrid_core import (
    CLAIM_RANK,
    CONTRACT_VERSION,
    is_timestamp,
    load_json,
    sha256_file,
    validate_json_schema,
    validate_results_v4,
)


CAVEATED = {"pass_with_caveat", "pass_known_legacy_behavior"}
PASS_RESULTS = {"pass", *CAVEATED}


def _encoded(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def _counter(rows: list[Any]) -> Counter[str]:
    return Counter(_encoded(row) for row in rows)


def _merge_status(statuses: list[str]) -> str:
    normalized = ["partial" if value in {"partial", "partial_fail", "pending"} else value for value in statuses]
    if any(value == "fail" for value in normalized):
        return "fail"
    if any(value == "blocked" for value in normalized):
        return "blocked"
    if any(value == "partial" for value in normalized):
        return "partial"
    observed = set(normalized)
    if observed <= PASS_RESULTS:
        if "pass_with_caveat" in observed:
            return "pass_with_caveat"
        if "pass_known_legacy_behavior" in observed:
            return "pass_known_legacy_behavior"
        return "pass"
    if len(observed) == 1 and next(iter(observed), None) in {"skip", "excluded"}:
        return next(iter(observed))
    return "conflict"


def _merge_gate(verdicts: list[str]) -> str:
    priority = {"pass": 0, "not_applicable": 1, "skip": 2, "blocked": 3, "fail": 4}
    if not verdicts:
        return "conflict"
    if any(value not in priority for value in verdicts):
        return "conflict"
    return max(verdicts, key=lambda value: priority[value])


def _merge_release(verdicts: list[str]) -> str:
    if "no-go" in verdicts:
        return "no-go"
    if "blocked" in verdicts:
        return "blocked"
    if verdicts and all(value == "not_applicable" for value in verdicts):
        return "not_applicable"
    if verdicts and all(value == "go" for value in verdicts):
        return "go"
    return "blocked"


def _summary(results: list[str]) -> dict[str, int]:
    return {
        "total": len(results),
        "passed": sum(value in PASS_RESULTS for value in results),
        "passed_unconditional": results.count("pass"),
        "passed_with_caveat": results.count("pass_with_caveat"),
        "passed_known_legacy_behavior": results.count("pass_known_legacy_behavior"),
        "failed": results.count("fail"),
        "blocked": results.count("blocked"),
        "partial": results.count("partial"),
        "skipped": results.count("skip"),
        "excluded": results.count("excluded"),
        "conflicts": results.count("conflict"),
    }


def _resolve_source(
    merged_path: Path,
    entry: dict[str, Any],
    index: int,
    errors: list[str],
    trusted_profiles: list[Path],
) -> tuple[str | None, dict[str, Any] | None, Path | None]:
    where = f"source_runs[{index}]"
    run_id = entry.get("run_id")
    path_value = entry.get("results_path")
    if not isinstance(run_id, str) or not run_id.strip():
        errors.append(f"{where}.run_id must be non-empty")
        return None, None, None
    if not isinstance(path_value, str) or not path_value.strip():
        errors.append(f"{where}.results_path must be non-empty")
        return run_id, None, None
    declared = Path(path_value)
    if declared.name != "results.json":
        errors.append(f"{where}.results_path must reference results.json")
    candidate = declared if declared.is_absolute() else merged_path.parent / declared
    try:
        source_path = candidate.resolve(strict=True)
    except OSError as exc:
        errors.append(f"{where}.results_path cannot be resolved: {exc}")
        return run_id, None, None
    if not source_path.is_file():
        errors.append(f"{where}.results_path is not a regular file")
        return run_id, None, source_path
    actual_sha = sha256_file(source_path)
    if entry.get("sha256") != actual_sha:
        errors.append(f"{where}.sha256 does not match results.json")
    try:
        source = load_json(source_path)
    except (OSError, ValueError) as exc:
        errors.append(f"{where}.results_path is invalid JSON: {exc}")
        return run_id, None, source_path
    input_profile_sha = (
        source.get("input_refs", {}).get("project_profile", {}).get("sha256")
        if isinstance(source.get("input_refs"), dict)
        else None
    )
    matched_profile = next(
        (
            profile
            for profile in trusted_profiles
            if profile.is_file() and sha256_file(profile) == input_profile_sha
        ),
        None,
    )
    source_errors = validate_results_v4(source, source_path, matched_profile)
    errors.extend(f"{where}.results_path: {error}" for error in source_errors)
    if source_errors:
        return run_id, None, source_path
    for field in ("run_id", "schema_version", "version"):
        if entry.get(field) != source.get(field):
            errors.append(f"{where}.{field} does not match referenced results.json")
    return run_id, source, source_path


def validate(
    document: Any, merged_path: Path, trusted_profiles: list[Path] | None = None
) -> list[str]:
    errors: list[str] = []
    schema_path = Path(__file__).resolve().parent.parent / "schemas" / "merged-results-v4.schema.json"
    try:
        schema = load_json(schema_path)
    except (OSError, ValueError) as exc:
        return [f"merged v4 schema could not be loaded: {exc}"]
    errors.extend(validate_json_schema(document, schema))
    if not isinstance(document, dict):
        return errors or ["merged v4 root must be an object"]
    if document.get("contract_version") != CONTRACT_VERSION:
        errors.append(f"contract_version must be {CONTRACT_VERSION}")
    if not is_timestamp(document.get("merged_at")):
        errors.append("merged_at must be an ISO 8601 timestamp with timezone")

    trusted_profiles = list(trusted_profiles or [])
    if not trusted_profiles and os.environ.get("BETTER_TEST_TRUSTED_PROFILE"):
        trusted_profiles.append(Path(os.environ["BETTER_TEST_TRUSTED_PROFILE"]).resolve())
    sources: dict[str, dict[str, Any]] = {}
    source_paths: set[Path] = set()
    for index, entry in enumerate(document.get("source_runs", [])):
        if not isinstance(entry, dict):
            continue
        run_id, source, source_path = _resolve_source(
            merged_path, entry, index, errors, trusted_profiles
        )
        if run_id in sources:
            errors.append(f"duplicate source run: {run_id}")
        if source_path in source_paths:
            errors.append(f"duplicate source results path: {source_path}")
        if source_path is not None:
            source_paths.add(source_path)
        if run_id is not None and source is not None:
            sources[run_id] = source
    if set(sources) != {entry.get("run_id") for entry in document.get("source_runs", []) if isinstance(entry, dict)}:
        errors.append("not every declared source run is valid")
    for run_id, source in sources.items():
        if source.get("version") != document.get("version"):
            errors.append(f"source run {run_id} version differs from merged version")
        if is_timestamp(source.get("finished_at")) and is_timestamp(document.get("merged_at")):
            source_time = datetime.fromisoformat(source["finished_at"].replace("Z", "+00:00"))
            merge_time = datetime.fromisoformat(document["merged_at"].replace("Z", "+00:00"))
            if source_time > merge_time:
                errors.append(f"source run {run_id} finished after merged_at")

    expected_subjects = [
        {"source_run": run_id, "subject": subject}
        for run_id, source in sources.items()
        for subject in source.get("subjects", [])
    ]
    if _counter(document.get("subjects", [])) != _counter(expected_subjects):
        errors.append("subjects must exactly preserve every typed source subject occurrence")
    expected_relations = [
        {"source_run": run_id, "relation": relation}
        for run_id, source in sources.items()
        for relation in source.get("relations", [])
    ]
    if _counter(document.get("relations", [])) != _counter(expected_relations):
        errors.append("relations must exactly preserve every source relation occurrence")

    expected_items: dict[str, list[dict[str, Any]]] = {}
    for run_id, source in sources.items():
        for item in source.get("items", []):
            expected_items.setdefault(item["id"], []).append({"source_run": run_id, "item": item})
    superseded_pairs: set[tuple[str, str]] = set()
    supersession_keys: set[tuple[str, str]] = set()
    for index, row in enumerate(document.get("supersessions", [])):
        if not isinstance(row, dict):
            continue
        where = f"supersessions[{index}]"
        item_id = row.get("item_id")
        old_run = row.get("superseded_source_run")
        new_run = row.get("authoritative_source_run")
        key = (item_id, old_run)
        if key in supersession_keys:
            errors.append(f"{where} duplicates supersession for {item_id}/{old_run}")
            continue
        supersession_keys.add(key)
        if old_run == new_run:
            errors.append(f"{where} source runs must differ")
            continue
        occurrences = expected_items.get(item_id, [])
        old_item = next(
            (
                occurrence["item"]
                for occurrence in occurrences
                if occurrence["source_run"] == old_run
            ),
            None,
        )
        new_item = next(
            (
                occurrence["item"]
                for occurrence in occurrences
                if occurrence["source_run"] == new_run
            ),
            None,
        )
        if old_item is None or new_item is None:
            errors.append(
                f"{where} must reference two source runs containing item {item_id}"
            )
            continue
        old_status = old_item.get("status")
        new_status = new_item.get("status")
        if old_status not in {"blocked", "partial", "partial_fail", "pending", "skip"}:
            errors.append(
                f"{where} can only supersede blocked/partial/pending/skip, observed {old_status}"
            )
        if new_status not in PASS_RESULTS | {"fail"}:
            errors.append(
                f"{where} authoritative occurrence must be pass/caveated/fail, observed {new_status}"
            )
        old_finished = sources.get(old_run, {}).get("finished_at")
        new_finished = sources.get(new_run, {}).get("finished_at")
        if is_timestamp(old_finished) and is_timestamp(new_finished):
            old_time = datetime.fromisoformat(old_finished.replace("Z", "+00:00"))
            new_time = datetime.fromisoformat(new_finished.replace("Z", "+00:00"))
            if new_time <= old_time:
                errors.append(
                    f"{where} authoritative source must finish after superseded source"
                )
            approved_at = row.get("approved_at")
            if is_timestamp(approved_at):
                approval_time = datetime.fromisoformat(
                    approved_at.replace("Z", "+00:00")
                )
                if approval_time < new_time:
                    errors.append(
                        f"{where} approved_at cannot precede authoritative source finish"
                    )
        superseded_pairs.add((item_id, old_run))
    seen_item_ids: set[str] = set()
    aggregate_results: list[str] = []
    for index, merged_item in enumerate(document.get("items", [])):
        if not isinstance(merged_item, dict):
            continue
        item_id = merged_item.get("id")
        where = f"items[{index}]"
        if item_id in seen_item_ids:
            errors.append(f"duplicate merged item id: {item_id}")
        seen_item_ids.add(item_id)
        expected_occurrences = expected_items.get(item_id, [])
        if _counter(merged_item.get("occurrences", [])) != _counter(expected_occurrences):
            errors.append(f"{where}.occurrences must exactly preserve typed source items and evidence")
        active_occurrences = [
            occurrence
            for occurrence in expected_occurrences
            if (item_id, occurrence["source_run"]) not in superseded_pairs
        ]
        if not active_occurrences:
            errors.append(f"{where} supersessions removed every occurrence")
            active_occurrences = expected_occurrences
        semantic_rows = []
        for occurrence in active_occurrences:
            source = sources.get(occurrence["source_run"], {})
            types_by_id = {
                subject.get("id"): subject.get("type")
                for subject in source.get("subjects", [])
                if isinstance(subject, dict)
            }
            item = occurrence["item"]
            semantic_rows.append(
                {
                    "name": item.get("name"),
                    "test_kind": item.get("test_kind"),
                    "claim_scope": item.get("claim_scope"),
                    "assertion": item.get("assertion"),
                    "bug_ids": sorted(item.get("bug_ids", [])),
                    "subject_types": sorted(
                        types_by_id.get(ref) for ref in item.get("subject_refs", [])
                    ),
                }
            )
        semantics_conflict = len(_counter(semantic_rows)) > 1
        expected_result = (
            "conflict"
            if semantics_conflict
            else _merge_status([row["item"].get("status") for row in active_occurrences])
        )
        if merged_item.get("result") != expected_result:
            errors.append(f"{where}.result must be conservative value {expected_result}")
        if merged_item.get("result") == "conflict" and not merged_item.get("conflict_details"):
            errors.append(f"{where}.conflict_details is required")
        aggregate_results.append(merged_item.get("result"))
    if seen_item_ids != set(expected_items):
        errors.append("merged items must cover every source item exactly once")
    expected_summary = _summary(aggregate_results)
    if document.get("summary") != expected_summary:
        errors.append("summary does not match conservative merged item results")

    expected_gates: dict[str, list[dict[str, Any]]] = {}
    for run_id, source in sources.items():
        for gate in source.get("gates", []):
            expected_gates.setdefault(gate["id"], []).append({"source_run": run_id, "gate": gate})
    superseded_gate_pairs: set[tuple[str, str]] = set()
    gate_supersession_keys: set[tuple[str, str]] = set()
    for index, row in enumerate(document.get("gate_supersessions", [])):
        if not isinstance(row, dict):
            continue
        where = f"gate_supersessions[{index}]"
        gate_id = row.get("gate_id")
        old_run = row.get("superseded_source_run")
        new_run = row.get("authoritative_source_run")
        key = (gate_id, old_run)
        if key in gate_supersession_keys:
            errors.append(
                f"{where} duplicates supersession for {gate_id}/{old_run}"
            )
            continue
        gate_supersession_keys.add(key)
        if old_run == new_run:
            errors.append(f"{where} source runs must differ")
            continue
        occurrences = expected_gates.get(gate_id, [])
        old_gate = next(
            (
                occurrence["gate"]
                for occurrence in occurrences
                if occurrence["source_run"] == old_run
            ),
            None,
        )
        new_gate = next(
            (
                occurrence["gate"]
                for occurrence in occurrences
                if occurrence["source_run"] == new_run
            ),
            None,
        )
        if old_gate is None or new_gate is None:
            errors.append(
                f"{where} must reference two source runs containing gate {gate_id}"
            )
            continue
        old_verdict = old_gate.get("verdict")
        new_verdict = new_gate.get("verdict")
        if old_verdict not in {"blocked", "skip", "not_applicable"}:
            errors.append(
                f"{where} can only supersede blocked/skip/not_applicable, observed {old_verdict}"
            )
        if new_verdict not in {"pass", "fail"}:
            errors.append(
                f"{where} authoritative gate must be pass/fail, observed {new_verdict}"
            )
        old_finished = sources.get(old_run, {}).get("finished_at")
        new_finished = sources.get(new_run, {}).get("finished_at")
        if is_timestamp(old_finished) and is_timestamp(new_finished):
            old_time = datetime.fromisoformat(old_finished.replace("Z", "+00:00"))
            new_time = datetime.fromisoformat(new_finished.replace("Z", "+00:00"))
            if new_time <= old_time:
                errors.append(
                    f"{where} authoritative source must finish after superseded source"
                )
            approved_at = row.get("approved_at")
            if is_timestamp(approved_at):
                approval_time = datetime.fromisoformat(
                    approved_at.replace("Z", "+00:00")
                )
                if approval_time < new_time:
                    errors.append(
                        f"{where} approved_at cannot precede authoritative source finish"
                    )
        superseded_gate_pairs.add((gate_id, old_run))
    seen_gate_ids: set[str] = set()
    for index, merged_gate in enumerate(document.get("gates", [])):
        if not isinstance(merged_gate, dict):
            continue
        gate_id = merged_gate.get("id")
        where = f"gates[{index}]"
        if gate_id in seen_gate_ids:
            errors.append(f"duplicate merged gate id: {gate_id}")
        seen_gate_ids.add(gate_id)
        expected_occurrences = expected_gates.get(gate_id, [])
        if _counter(merged_gate.get("occurrences", [])) != _counter(expected_occurrences):
            errors.append(f"{where}.occurrences must exactly preserve source gates")
        active_occurrences = [
            occurrence
            for occurrence in expected_occurrences
            if (gate_id, occurrence["source_run"])
            not in superseded_gate_pairs
        ]
        if not active_occurrences:
            errors.append(f"{where} gate supersessions removed every occurrence")
            active_occurrences = expected_occurrences
        expected_verdict = _merge_gate(
            [row["gate"].get("verdict") for row in active_occurrences]
        )
        if merged_gate.get("verdict") != expected_verdict:
            errors.append(f"{where}.verdict must be conservative value {expected_verdict}")
    if seen_gate_ids != set(expected_gates):
        errors.append("merged gates must cover every source gate exactly once")

    claims = [source.get("max_claim_scope") for source in sources.values()]
    unknown_claims = [claim for claim in claims if claim not in CLAIM_RANK]
    if unknown_claims:
        errors.append(f"source max_claim_scope is unsupported: {unknown_claims}")
    elif claims:
        expected_claim = min(claims, key=lambda claim: CLAIM_RANK[claim])
        if document.get("max_claim_scope") != expected_claim:
            errors.append(f"max_claim_scope must not exceed weakest source claim {expected_claim}")

    expected_caveats = {
        (run_id, item["id"])
        for run_id, source in sources.items()
        for item in source.get("items", [])
        if item.get("status") in CAVEATED
    }
    override_pairs: list[tuple[Any, Any]] = []
    for override in document.get("caveat_overrides", []):
        if isinstance(override, dict):
            override_pairs.append((override.get("source_run"), override.get("item_id")))
    if len(override_pairs) != len(set(override_pairs)):
        errors.append("caveat_overrides contains duplicates")
    if set(override_pairs) != expected_caveats:
        errors.append("caveat_overrides must explicitly disposition every caveated source occurrence")

    expected_source_verdicts = [
        {"source_run": run_id, **source.get("release_readiness", {})}
        for run_id, source in sources.items()
    ]
    readiness = document.get("release_readiness", {})
    if isinstance(readiness, dict):
        if _counter(readiness.get("source_verdicts", [])) != _counter(expected_source_verdicts):
            errors.append("release_readiness.source_verdicts must exactly preserve source verdicts")
        expected_release = _merge_release([row.get("verdict") for row in expected_source_verdicts])
        if readiness.get("verdict") != expected_release:
            errors.append(f"release_readiness.verdict must be conservative value {expected_release}")

    challenge = document.get("verdict_challenge", {})
    if isinstance(challenge, dict):
        if challenge.get("drafted_by") != document.get("coordinator_id"):
            errors.append("verdict_challenge.drafted_by must equal coordinator_id")
        if challenge.get("challenger") == challenge.get("drafted_by"):
            errors.append("verdict challenger must differ from coordinator")
        if challenge.get("unresolved_count") != 0 and readiness.get("verdict") == "go":
            errors.append("release GO requires zero unresolved verdict challenges")
    if readiness.get("verdict") == "go":
        if any(result not in PASS_RESULTS for result in aggregate_results):
            errors.append("release GO cannot contain incomplete or non-pass items")
        if any(
            gate.get("verdict") != "pass"
            for gate in document.get("gates", [])
            if isinstance(gate, dict)
        ):
            errors.append("release GO requires every merged gate to pass")
        if document.get("max_claim_scope") != "release_gate":
            errors.append("release GO requires max_claim_scope release_gate")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate Better Test merged results v4")
    parser.add_argument("merged_results", type=Path)
    parser.add_argument(
        "--profile",
        type=Path,
        action="append",
        default=[],
        help="external trusted profile; repeat for cross-project merges",
    )
    args = parser.parse_args()
    merged_path = args.merged_results.resolve()
    try:
        document = load_json(merged_path)
    except (OSError, ValueError) as exc:
        print(f"INVALID: {exc}", file=sys.stderr)
        return 2
    errors = validate(document, merged_path, [path.resolve() for path in args.profile])
    if errors:
        for error in errors:
            print(f"INVALID: {error}", file=sys.stderr)
        return 1
    print(f"valid merged v4 results: {merged_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

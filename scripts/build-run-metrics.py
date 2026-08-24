#!/usr/bin/env python3
"""Build a non-authoritative run-local metrics.json."""

from __future__ import annotations

import argparse
import sys
from datetime import datetime
from pathlib import Path
from typing import Any

from hybrid_core import (
    is_timestamp,
    load_json,
    sha256_file,
    validate_json_schema,
    write_atomic,
)


def duration_minutes(started: Any, finished: Any) -> float | None:
    if not is_timestamp(started) or not is_timestamp(finished):
        return None
    start = datetime.fromisoformat(str(started).replace("Z", "+00:00"))
    end = datetime.fromisoformat(str(finished).replace("Z", "+00:00"))
    if end < start:
        return None
    return round((end - start).total_seconds() / 60, 3)


def intake_binding(run_dir: Path, results: dict[str, Any]) -> tuple[bool, str]:
    intake = run_dir / "intake.json"
    if not intake.is_file():
        return False, "missing"
    ref = results.get("intake_ref")
    if not isinstance(ref, dict):
        return True, "invalid"
    try:
        document = load_json(intake)
    except (OSError, ValueError):
        return True, "invalid"
    if (
        ref.get("intake_id") != document.get("intake_id")
        or ref.get("sha256") != sha256_file(intake)
    ):
        return True, "invalid"
    return True, "valid"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-dir", required=True, type=Path)
    parser.add_argument("--unattended-minutes", type=float)
    parser.add_argument("--resume-count", type=int)
    parser.add_argument("--resume-failed", choices=["true", "false"])
    parser.add_argument("--validator-blocks", type=int)
    parser.add_argument("--verdict-overridden", choices=["true", "false"])
    parser.add_argument("--resource-conflicts", type=int)
    args = parser.parse_args()

    try:
        run_dir = args.run_dir.resolve(strict=True)
        results = load_json(run_dir / "results.json")
    except (OSError, ValueError) as exc:
        print(f"metrics build error: {exc}", file=sys.stderr)
        return 2
    if not isinstance(results, dict):
        print("metrics build error: results must be an object", file=sys.stderr)
        return 2

    present, binding = intake_binding(run_dir, results)
    source_runs = results.get("source_runs")
    tester_count = (
        len({row.get("run_id") for row in source_runs if isinstance(row, dict)})
        if isinstance(source_runs, list)
        else (1 if results.get("tester_id") else 0)
    )
    readiness = results.get("release_readiness")
    verdict = readiness.get("verdict") if isinstance(readiness, dict) else None
    metrics = {
        "schema_version": 1,
        "run_id": str(results.get("run_id") or results.get("merge_id") or run_dir.name),
        "recorded_at": datetime.now().astimezone().isoformat(timespec="seconds"),
        "results_schema_version": results.get("schema_version"),
        "mode": results.get("mode"),
        "tester_count": tester_count,
        "wall_clock_minutes": duration_minutes(
            results.get("started_at"), results.get("finished_at")
        ),
        "unattended_minutes": args.unattended_minutes,
        "resume_count": args.resume_count,
        "resume_failed": (
            args.resume_failed == "true" if args.resume_failed is not None else None
        ),
        "validator_blocks": args.validator_blocks,
        "verdict": verdict.upper().replace("-", "_") if isinstance(verdict, str) else None,
        "verdict_overridden": (
            args.verdict_overridden == "true"
            if args.verdict_overridden is not None
            else None
        ),
        "resource_conflicts_detected": args.resource_conflicts,
        "intake_present": present,
        "intake_binding": binding,
    }
    schema = load_json(
        Path(__file__).resolve().parent.parent / "schemas" / "run-metrics.schema.json"
    )
    errors = validate_json_schema(metrics, schema)
    if errors:
        for error in errors:
            print(f"INVALID: {error}", file=sys.stderr)
        return 1
    output = run_dir / "metrics.json"
    write_atomic(output, __import__("json").dumps(metrics, indent=2, ensure_ascii=False) + "\n")
    print(f"run metrics written: {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

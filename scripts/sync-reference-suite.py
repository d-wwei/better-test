#!/usr/bin/env python3
"""Diff two validated reference-suite maps without advancing the pinned source."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import subprocess
import sys
from typing import Any


TRACKED_CASE_FIELDS = (
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
)


def validate(path: Path) -> None:
    subprocess.run(
        [
            sys.executable,
            str(Path(__file__).with_name("validate-reference-suite-map.py")),
            str(path),
        ],
        check=True,
        stdout=subprocess.DEVNULL,
    )


def load(path: Path) -> dict[str, Any]:
    validate(path)
    return json.loads(path.read_text(encoding="utf-8"))


def finding_key(finding: dict[str, Any]) -> tuple[str, str, int]:
    return (finding["kind"], finding["path"], finding["line"])


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("old_map", type=Path)
    parser.add_argument("new_map", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--fail-on-drift", action="store_true")
    args = parser.parse_args()

    old = load(args.old_map)
    new = load(args.new_map)
    old_cases = {case["id"]: case for case in old["cases"]}
    new_cases = {case["id"]: case for case in new["cases"]}
    added_ids = sorted(set(new_cases) - set(old_cases))
    removed_ids = sorted(set(old_cases) - set(new_cases))
    changed = []
    for case_id in sorted(set(old_cases) & set(new_cases)):
        fields = [
            field
            for field in TRACKED_CASE_FIELDS
            if old_cases[case_id].get(field) != new_cases[case_id].get(field)
        ]
        if fields:
            changed.append({"id": case_id, "fields": fields})

    old_findings = {
        finding_key(finding): finding for finding in old["danger_scan"]["findings"]
    }
    new_findings = {
        finding_key(finding): finding for finding in new["danger_scan"]["findings"]
    }
    danger_added = [
        new_findings[key] for key in sorted(set(new_findings) - set(old_findings))
    ]
    danger_removed = [
        old_findings[key] for key in sorted(set(old_findings) - set(new_findings))
    ]
    result = {
        "schema_version": 1,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "suite_id": new["suite"]["id"],
        "old": {
            "branch": old["suite"]["branch"],
            "commit": old["suite"]["commit"],
            "files": old["summary"]["files"],
            "static_tests": old["summary"]["static_tests"],
        },
        "new": {
            "branch": new["suite"]["branch"],
            "commit": new["suite"]["commit"],
            "files": new["summary"]["files"],
            "static_tests": new["summary"]["static_tests"],
        },
        "summary": {
            "added": len(added_ids),
            "removed": len(removed_ids),
            "changed": len(changed),
            "danger_added": len(danger_added),
            "danger_removed": len(danger_removed),
        },
        "added": added_ids,
        "removed": removed_ids,
        "changed": changed,
        "danger_added": danger_added,
        "danger_removed": danger_removed,
    }
    rendered = json.dumps(result, ensure_ascii=False, indent=2) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(rendered, encoding="utf-8")
    else:
        print(rendered, end="")
    has_drift = any(result["summary"].values())
    return 1 if args.fail_on_drift and has_drift else 0


if __name__ == "__main__":
    raise SystemExit(main())

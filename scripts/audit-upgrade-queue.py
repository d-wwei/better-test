#!/usr/bin/env python3
"""Audit the Markdown skill-upgrade queue without counting its fenced example."""

from __future__ import annotations

import argparse
import datetime as dt
import re
import sys
from pathlib import Path


ALLOWED = {
    "pending",
    "rejected",
    "promoted",
    "promoted-modified",
    "promoted-merged",
    "already-present",
    "pilot",
}
FINAL = {"rejected", "promoted", "promoted-modified", "promoted-merged", "already-present"}


def unfenced(text: str) -> str:
    output: list[str] = []
    in_fence = False
    for line in text.splitlines():
        if line.lstrip().startswith("```"):
            in_fence = not in_fence
            continue
        if not in_fence:
            output.append(line)
    return "\n".join(output)


def audit(text: str, today: dt.date) -> tuple[list[str], list[str], dict[str, int]]:
    errors: list[str] = []
    warnings: list[str] = []
    body = unfenced(text)
    queue = body.split("## 当前队列", 1)
    if len(queue) != 2:
        return ["missing ## 当前队列 section"], warnings, {}
    queue_body = queue[1]
    matches = list(
        re.finditer(
            r"^### \[([^\]]+)\] (.+?)\n(.*?)(?=^### \[|\Z)",
            queue_body,
            flags=re.MULTILINE | re.DOTALL,
        )
    )
    if not matches:
        return ["no queue records found"], warnings, {}
    status_line_count = len(
        re.findall(r"^- \*\*状态\*\*:", queue_body, flags=re.MULTILINE)
    )
    if status_line_count != len(matches):
        errors.append(
            "queue record/status mismatch: every status line must belong to "
            "one canonical '### [YYYY-MM-DD]' record"
        )

    counts: dict[str, int] = {}
    seen_keys: set[str] = set()
    for match in matches:
        date_text, title, record = match.groups()
        key = f"{date_text}:{title.strip()}"
        try:
            record_date = dt.date.fromisoformat(date_text)
        except ValueError:
            errors.append(f"{key}: invalid heading date")
            record_date = None
        if key in seen_keys:
            errors.append(f"duplicate queue key: {key}")
        seen_keys.add(key)
        status_match = re.search(r"^- \*\*状态\*\*:\s*([a-z-]+)(.*)$", record, re.MULTILINE)
        if not status_match:
            errors.append(f"{key}: missing status")
            continue
        status, detail = status_match.groups()
        counts[status] = counts.get(status, 0) + 1
        if status not in ALLOWED:
            errors.append(f"{key}: unknown status {status}")
        if status in FINAL:
            final_match = re.fullmatch(
                r"\s+(\d{4}-\d{2}-\d{2})(.+)",
                detail,
            )
            if not final_match:
                errors.append(
                    f"{key}: final status requires an ISO date and landing detail"
                )
            else:
                try:
                    dt.date.fromisoformat(final_match.group(1))
                except ValueError:
                    errors.append(f"{key}: final status has invalid date")
                if not final_match.group(2).strip():
                    errors.append(f"{key}: final status lacks landing detail")
        if status == "pilot":
            deadline_match = re.search(
                r"复核期限\s*[:：]\s*(\d{4}-\d{2}-\d{2})",
                record,
            )
            if not deadline_match:
                errors.append(f"{key}: pilot lacks a non-empty 复核期限")
            else:
                try:
                    deadline = dt.date.fromisoformat(deadline_match.group(1))
                except ValueError:
                    errors.append(f"{key}: pilot has invalid 复核期限")
                else:
                    if deadline < today:
                        errors.append(
                            f"{key}: pilot review deadline expired on {deadline}"
                        )
        if status == "pending" and record_date is not None:
            age = (today - record_date).days
            if age >= 0:
                if age > 30:
                    warnings.append(f"{key}: pending for {age} days")

    pending = counts.get("pending", 0)
    if pending >= 5:
        errors.append(f"pending waterline exceeded: {pending} >= 5")
    if re.search(r"\|\s*(pending|pilot)\b", body):
        warnings.append("batch ledger contains pending/pilot text; review manually")
    return errors, warnings, counts


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("queue", type=Path)
    parser.add_argument("--today", type=dt.date.fromisoformat, default=dt.date.today())
    args = parser.parse_args()
    text = args.queue.read_text(encoding="utf-8")
    errors, warnings, counts = audit(text, args.today)
    for warning in warnings:
        print(f"WARN: {warning}", file=sys.stderr)
    for error in errors:
        print(f"INVALID: {error}", file=sys.stderr)
    count_text = ", ".join(f"{key}={counts[key]}" for key in sorted(counts))
    print(f"upgrade queue: {count_text}")
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())

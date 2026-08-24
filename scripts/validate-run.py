#!/usr/bin/env python3
"""Validate one Better Test run through its portable completion gates."""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path


def run_command(command: list[str]) -> tuple[int, str]:
    completed = subprocess.run(command, check=False, capture_output=True, text=True)
    output = "\n".join(
        part.strip() for part in (completed.stdout, completed.stderr) if part.strip()
    )
    return completed.returncode, output


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-dir", required=True, type=Path)
    parser.add_argument(
        "--intake-policy",
        choices=["required", "advisory", "off"],
        default="required",
    )
    parser.add_argument("--project-root", type=Path)
    parser.add_argument("--profile", type=Path)
    parser.add_argument("--validate-report", action="store_true")
    args = parser.parse_args()

    root = Path(__file__).resolve().parent.parent
    try:
        run_dir = args.run_dir.resolve(strict=True)
    except OSError as exc:
        print(f"run validation error: {exc}", file=sys.stderr)
        return 2
    if not run_dir.is_dir():
        print(f"run validation error: not a directory: {run_dir}", file=sys.stderr)
        return 2

    results = run_dir / "results.json"
    if not results.is_file():
        print(f"INVALID: missing results.json: {results}", file=sys.stderr)
        return 1

    result_command = [str(root / "scripts" / "validate-results.sh"), str(results)]
    if args.profile:
        result_command.extend(["--profile", str(args.profile)])
    rc, output = run_command(result_command)
    if output:
        print(output, file=sys.stderr if rc else sys.stdout)
    if rc:
        return 2 if rc in {64, 66} else 1

    intake = run_dir / "intake.json"
    if args.intake_policy != "off":
        if not intake.is_file():
            if args.intake_policy == "required":
                print(f"INVALID: missing intake.json: {intake}", file=sys.stderr)
                return 1
            print(f"ADVISORY: historical run has no intake.json: {run_dir}")
        else:
            intake_command = [
                sys.executable,
                str(root / "scripts" / "validate-intake.py"),
                str(intake),
                "--results",
                str(results),
            ]
            if args.project_root:
                intake_command.extend(["--project-root", str(args.project_root)])
            if args.intake_policy == "required":
                intake_command.append("--require-binding")
            rc, output = run_command(intake_command)
            if output:
                print(output, file=sys.stderr if rc else sys.stdout)
            if rc:
                return 2 if rc == 2 else 1

    if args.validate_report:
        report = run_dir / "FULL-TEST-REPORT.md"
        report_command = [
            sys.executable,
            str(root / "scripts" / "build-full-report.py"),
            "--run-dir",
            str(run_dir),
            "--output",
            str(report),
            "--validate-only",
        ]
        rc, output = run_command(report_command)
        if output:
            print(output, file=sys.stderr if rc else sys.stdout)
        if rc:
            return 2 if rc == 2 else 1

    print(f"valid run: {run_dir} intake_policy={args.intake_policy}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Validate a Better Test results v4 file, including local evidence closure."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from hybrid_core import load_json, validate_results_v4


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("path", type=Path)
    parser.add_argument(
        "--profile",
        type=Path,
        help="external canonical project profile trust anchor (or BETTER_TEST_TRUSTED_PROFILE)",
    )
    args = parser.parse_args()
    try:
        path = args.path.resolve(strict=True)
        errors = validate_results_v4(load_json(path), path, args.profile)
    except (OSError, ValueError) as exc:
        print(f"results v4 validation failed: {exc}", file=sys.stderr)
        return 2
    if errors:
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1
    print(f"results v4 validation passed: {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Validate one Better Test provider contract document."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from hybrid_core import load_json, validate


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "kind", choices=("project-profile", "capabilities", "source-map", "source-impact")
    )
    parser.add_argument("path", type=Path)
    args = parser.parse_args()
    try:
        document = load_json(args.path)
        errors = validate(args.kind, document, args.path.resolve())
    except (OSError, ValueError) as exc:
        print(f"provider validation failed: {exc}", file=sys.stderr)
        return 2
    if errors:
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1
    print(f"provider validation passed: {args.kind} {args.path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

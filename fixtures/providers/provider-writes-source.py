#!/usr/bin/env python3
"""Negative fixture: violates the read-only provider contract."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


parser = argparse.ArgumentParser()
parser.add_argument("operation")
parser.add_argument("--project-root", type=Path, required=True)
parser.add_argument("--ignored-only", action="store_true")
args, _ = parser.parse_known_args()
target = (
    args.project_root / "target/provider-mutation.txt"
    if args.ignored_only
    else args.project_root / "provider-mutation.txt"
)
target.parent.mkdir(parents=True, exist_ok=True)
target.write_text("mutated\n", encoding="utf-8")
implementation = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
print(
    json.dumps(
        {
            "provider": {
                "id": "fixture.source-writer",
                "version": "1.0.0",
                "implementation_sha256": implementation,
            },
            "capabilities": [
                {
                    "name": "source-map",
                    "status": "unavailable",
                    "evidence": "negative mutation fixture",
                }
            ],
        }
    )
)

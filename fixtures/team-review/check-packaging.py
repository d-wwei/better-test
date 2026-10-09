#!/usr/bin/env python3
"""Check fixture input packaging only, never reviewer correctness or resources."""
from pathlib import Path
import re
import sys

root = Path(__file__).resolve().parent
scenarios = ("shortcut-gap", "shared-golden", "minority-counterexample", "shared-desktop", "isolated-api", "zero-findings")
errors = []
for scenario in scenarios:
    folder = root / scenario
    for name in ("source.md", "phase-a.md", "phase-b.md"):
        path = folder / name
        if not path.is_file():
            errors.append(f"missing {scenario}/{name}")
            continue
        content = path.read_text(encoding="utf-8")
        links = re.findall(r"\[[^\]]*\]\(([^)]+)\)", content)
        if name == "phase-a.md" and links != ["source.md"]:
            errors.append(f"{scenario}: phase A must expose exactly its source.md")
        for link in links:
            target = (folder / link).resolve()
            if not target.is_relative_to(root) or not target.is_file():
                errors.append(f"{scenario}/{name}: unavailable local input {link}")
        if name == "phase-b.md" and not content.startswith("# Phase B\n"):
            errors.append(f"{scenario}: missing phase B boundary")
for name in ("README.md", "assessor-only.md"):
    if not (root / name).is_file():
        errors.append(f"missing {name}")
if errors:
    print("\n".join(f"FAIL: {error}" for error in errors))
    sys.exit(1)
print(f"fixture packaging passed ({len(scenarios)} A/B source slices; static only; semantic rehearsal NOT_RUN)")

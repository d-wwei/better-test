#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Canonical skill-root paths, including paths in tables/code spans, define the
# static loading graph. This checks discoverability, not Agent compliance.
python3 - "$ROOT_DIR" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])

def fail(message):
    print(f"FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)

if (root / "procedures").is_dir():
    fail(f"split Tier-2 root returned: {root / 'procedures'}")

entries = {"SKILL.md", "README.md", "README.zh-CN.md"}
for entry in sorted(entries):
    if not (root / entry).is_file():
        fail(f"entry document does not exist: {entry}")

documents = entries | {
    path.relative_to(root).as_posix()
    for path in (root / "references").rglob("*.md")
    if path.is_file()
}
reference_pattern = re.compile(r"(?<![A-Za-z0-9_./-])references/[A-Za-z0-9._/-]+\.md\b")
graph = {}
try:
    for document in sorted(documents):
        graph[document] = set(reference_pattern.findall((root / document).read_text(encoding="utf-8")))
except (OSError, UnicodeError) as exc:
    fail(f"cannot read resource document: {exc}")

referenced = set().union(*graph.values())
for target in sorted(referenced):
    if not (root / target).is_file():
        fail(f"referenced resource does not exist: {target}")
    # Every edge must have a canonical node; aliases with '..' cannot bypass
    # the procedure-set comparison or produce an unscanned loading node.
    if target not in documents:
        fail(f"referenced resource is not a canonical reference path: {target}")

procedure_prefix = "references/procedures/"
referenced_procedures = {target for target in referenced if target.startswith(procedure_prefix)}
actual_procedures = {document for document in documents if document.startswith(procedure_prefix)}
if not referenced_procedures:
    fail("no Tier-2 procedure references found")

unreferenced = actual_procedures - referenced_procedures
if unreferenced:
    fail("unreferenced Tier-2 procedure: " + ", ".join(sorted(unreferenced)))
# The other set direction is checked above: every referenced target exists and
# is in documents, including nested procedure paths.
reachable = set()
pending = list(entries)
while pending:
    document = pending.pop()
    if document in reachable:
        continue
    reachable.add(document)
    pending.extend(graph[document] - reachable)

unreachable = actual_procedures - reachable
if unreachable:
    fail("Tier-2 procedure not reachable from entry documents: " + ", ".join(sorted(unreachable)))

print(f"resource link integrity passed ({len(actual_procedures)} Tier-2 procedures; static loading reachability only)")
PY

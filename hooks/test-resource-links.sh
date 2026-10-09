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
# Mask complete external regions BEFORE extracting local paths. Punctuation
# inside a URI is never a token boundary that can expose a local-looking suffix.
external_prefix = r"(?:[A-Za-z][A-Za-z0-9+.-]*:|~/|/|\.{1,2}/|(?!(?:references/))[A-Za-z0-9._-]+/)"
external_start = re.compile(external_prefix)
external_locator = re.compile(r"(?<![A-Za-z0-9_./-])" + external_prefix + r"[^\s`<>\"]+")
local_suffix = re.compile(r"(references/[A-Za-z0-9._/-]+\.md)[?#][^\s`<>\"']+")
markdown_destination = re.compile(r"\]\(\s*")


def local_reference_text(text):
    masked = list(text)
    for match in markdown_destination.finditer(text):
        destination = text[match.end():].lstrip("<")
        is_external = external_start.match(destination)
        local_target = reference_pattern.match(destination)
        if not is_external and not local_target:
            continue
        # Find the complete balanced destination, retaining URI-internal []/().
        cursor, depth = match.start() + 2, 1
        while cursor < len(text) and depth:
            if text[cursor] == "\\":
                cursor += 2
                continue
            if text[cursor] == "(":
                depth += 1
            elif text[cursor] == ")":
                depth -= 1
            cursor += 1
        if depth:
            continue
        if not is_external:
            # Keep the actual local target, excluding only the rest of this
            # destination. Never consume a subsequent adjacent local link.
            target_start = match.end() + len(text[match.end():]) - len(destination)
            suffix_start = target_start + local_target.end()
            masked[suffix_start:cursor - 1] = " " * (cursor - 1 - suffix_start)
            continue
        # Its display label is not a local load edge either. Find its opening
        # bracket without swallowing an adjacent, legitimate local link.
        label_start, bracket_depth = match.start() - 1, 1
        while label_start >= 0:
            if text[label_start] == "]":
                bracket_depth += 1
            elif text[label_start] == "[":
                bracket_depth -= 1
                if not bracket_depth:
                    break
            label_start -= 1
        if label_start < 0:
            label_start = match.start()
        masked[label_start:cursor] = " " * (cursor - label_start)
    # Bare URI regions end at whitespace/markup wrappers; URI punctuation
    # (including apostrophes) stays inside. Local suffixes are not load edges.
    local_text = external_locator.sub(" ", "".join(masked))
    return local_suffix.sub(r"\1", local_text)


graph = {}
try:
    for document in sorted(documents):
        content = (root / document).read_text(encoding="utf-8")
        graph[document] = set(reference_pattern.findall(local_reference_text(content)))
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

#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/better-test-resource-validation.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT
passed=0
failed=0

# All mutations are in this disposable repository, never in the source checkout.
new_fixture() {
  FIXTURE="$TMP_DIR/$1"
  mkdir -p "$FIXTURE/hooks" "$FIXTURE/references/procedures"
  cp "$ROOT_DIR/hooks/test-resource-links.sh" "$FIXTURE/hooks/"
  printf '%s\n' 'references/workflow.md' > "$FIXTURE/SKILL.md"
  : > "$FIXTURE/README.md"
  : > "$FIXTURE/README.zh-CN.md"
  printf '%s\n' 'references/procedures/base.md' > "$FIXTURE/references/workflow.md"
  printf '%s\n' '# Base procedure' > "$FIXTURE/references/procedures/base.md"
}

check() {
  local label="$1" expected="$2" reason="${3:-}" actual=0
  bash "$FIXTURE/hooks/test-resource-links.sh" > "$TMP_DIR/output" 2>&1 || actual=$?
  if [[ "$actual" != "$expected" ]] || { [[ -n "$reason" ]] && ! grep -F "$reason" "$TMP_DIR/output" >/dev/null; }; then
    printf 'FAIL: %s (expected exit %s, got %s)\n' "$label" "$expected" "$actual" >&2
    cat "$TMP_DIR/output" >&2
    failed=$((failed + 1))
  else
    printf 'PASS: %s\n' "$label"
    passed=$((passed + 1))
  fi
}

new_fixture current
rm "$FIXTURE/references/workflow.md" "$FIXTURE/references/procedures/base.md"
cp "$ROOT_DIR/SKILL.md" "$ROOT_DIR/README.md" "$ROOT_DIR/README.zh-CN.md" "$FIXTURE/"
cp -R "$ROOT_DIR/references/." "$FIXTURE/references/"
check 'existing repository structure' 0

new_fixture minimal
check 'minimal load chain without fixed procedure count' 0

new_fixture connected
printf '%s\n' 'references/procedures/new.md' >> "$FIXTURE/references/workflow.md"
printf '%s\n' '# Connected addition' > "$FIXTURE/references/procedures/new.md"
check 'new procedure connected through existing workflow' 0

new_fixture nested
mkdir -p "$FIXTURE/references/procedures/nested"
printf '%s\n' 'references/procedures/nested/child.md' >> "$FIXTURE/references/procedures/base.md"
printf '%s\n' '# Nested addition' > "$FIXTURE/references/procedures/nested/child.md"
check 'nested procedure reachable through procedure' 0

new_fixture external
printf '%s\n' '~/.claude/skills/better-work/references/gitignore-template.md' >> "$FIXTURE/references/workflow.md"
check 'external skill reference is outside this graph' 0

new_fixture url_query_missing
printf '%s\n' 'https://example.invalid/docs?next=references/procedures/external.md' >> "$FIXTURE/references/workflow.md"
check 'external URL query is not a missing local resource' 0

new_fixture url_fragment_missing
printf '%s\n' '[external](https://example.invalid/docs#references/procedures/external.md)' >> "$FIXTURE/references/workflow.md"
check 'external URL fragment is not a missing local resource' 0

new_fixture url_parenthesized_query
printf '%s\n' '[external](https://example.invalid/docs?next=(references/procedures/external.md))' >> "$FIXTURE/references/workflow.md"
check 'parenthesized URL query remains one external locator' 0

for suffix in query fragment; do
  if [[ "$suffix" == query ]]; then
    url_prefix='https://example.invalid/docs?next='
  else
    url_prefix='https://example.invalid/docs#'
  fi
  new_fixture "square_${suffix}_missing"
  printf '[external](%s[references/procedures/missing.md])\n' "$url_prefix" >> "$FIXTURE/SKILL.md"
  check "square-bracket URL $suffix is not a missing local resource" 0

  new_fixture "square_${suffix}_orphan"
  printf '%s\n' '# Orphan' > "$FIXTURE/references/procedures/orphan.md"
  printf '[external](%s[references/procedures/orphan.md])\n' "$url_prefix" >> "$FIXTURE/SKILL.md"
  check "square-bracket URL $suffix cannot connect a local orphan" 1 'unreferenced Tier-2 procedure'
done

new_fixture bare_uri_punctuation
printf '%s\n' "https://example.invalid/docs?next=[('references/procedures/missing.md')]" >> "$FIXTURE/SKILL.md"
check 'bare URI punctuation remains inside the external region' 0

new_fixture bare_uri_orphan
printf '%s\n' '# Orphan' > "$FIXTURE/references/procedures/orphan.md"
printf '%s\n' "https://example.invalid/docs#[('references/procedures/orphan.md')]" >> "$FIXTURE/SKILL.md"
check 'bare URI punctuation cannot connect a local orphan' 1 'unreferenced Tier-2 procedure'

new_fixture compact_table_connected
printf '%s\n' '|https://example.invalid/docs|references/procedures/table-only.md|' >> "$FIXTURE/SKILL.md"
printf '%s\n' '# Table-only procedure' > "$FIXTURE/references/procedures/table-only.md"
check 'compact table retains local cell after bare URI' 0

new_fixture compact_table_missing
printf '%s\n' '|https://example.invalid/docs|references/procedures/missing.md|' >> "$FIXTURE/SKILL.md"
check 'compact table local target must exist' 1 'referenced resource does not exist'

new_fixture adjacent_markdown
printf '%s\n' '[external](https://example.invalid/docs?next=[references/procedures/external.md]),[local](references/procedures/adjacent.md)' >> "$FIXTURE/SKILL.md"
printf '%s\n' '# Adjacent local procedure' > "$FIXTURE/references/procedures/adjacent.md"
check 'excluding external destination preserves adjacent local link' 0

new_fixture adjacent_local_anchors
printf '%s\n' '[first](references/procedures/first.md#purpose),[second](references/procedures/second.md?view=source)' >> "$FIXTURE/SKILL.md"
printf '%s\n' '# First procedure' > "$FIXTURE/references/procedures/first.md"
printf '%s\n' '# Second procedure' > "$FIXTURE/references/procedures/second.md"
check 'local suffix exclusion preserves adjacent local targets' 0

new_fixture external_label
printf '%s\n' '# Orphan' > "$FIXTURE/references/procedures/orphan.md"
printf '%s\n' '[references/procedures/orphan.md](https://example.invalid/docs)' >> "$FIXTURE/SKILL.md"
check 'external Markdown label cannot connect a local orphan' 1 'unreferenced Tier-2 procedure'

new_fixture url_query_orphan
printf '%s\n' '# Orphan' > "$FIXTURE/references/procedures/orphan.md"
printf '%s\n' '[external](https://example.invalid/docs?next=references/procedures/orphan.md)' >> "$FIXTURE/SKILL.md"
check 'external URL query cannot connect a local orphan' 1 'unreferenced Tier-2 procedure'

new_fixture url_fragment_orphan
printf '%s\n' '# Orphan' > "$FIXTURE/references/procedures/orphan.md"
printf '%s\n' '[external](https://example.invalid/docs#references/procedures/orphan.md)' >> "$FIXTURE/SKILL.md"
check 'external URL fragment cannot connect a local orphan' 1 'unreferenced Tier-2 procedure'

new_fixture url_path
printf '%s\n' 'https://example.invalid/references/procedures/external.md' >> "$FIXTURE/references/workflow.md"
check 'external URL path is outside the local graph' 0

new_fixture qualified_path
printf '%s\n' '~/.claude/skills/better-work/README.md#references/procedures/external.md' >> "$FIXTURE/references/workflow.md"
check 'external qualified path fragment is outside the local graph' 0

new_fixture local_markdown
printf '%s\n' '[local](references/procedures/link.md#purpose)' '| guide | `references/procedures/table.md` |' >> "$FIXTURE/references/workflow.md"
printf '%s\n' '# Linked procedure' > "$FIXTURE/references/procedures/link.md"
printf '%s\n' '# Table procedure' > "$FIXTURE/references/procedures/table.md"
check 'local Markdown and table code-span targets remain load edges' 0

new_fixture local_fragment_missing
printf '%s\n' '[local](references/procedures/missing.md#purpose)' >> "$FIXTURE/references/workflow.md"
check 'local fragment target must exist' 1 'referenced resource does not exist'

new_fixture local_query_missing
printf '%s\n' '`references/procedures/missing.md?view=source`' >> "$FIXTURE/references/workflow.md"
check 'local query target must exist' 1 'referenced resource does not exist'

new_fixture missing
rm "$FIXTURE/references/procedures/base.md"
check 'missing referenced procedure' 1 'referenced resource does not exist'

new_fixture missing_workflow
rm "$FIXTURE/references/workflow.md"
check 'missing intermediate load document' 1 'referenced resource does not exist'

new_fixture orphan
printf '%s\n' '# Orphan' > "$FIXTURE/references/procedures/orphan.md"
check 'unreferenced procedure' 1 'unreferenced Tier-2 procedure'

new_fixture self_link
printf '%s\n' 'references/procedures/self.md' > "$FIXTURE/references/procedures/self.md"
check 'isolated self reference' 1 'not reachable from entry documents'

new_fixture mutual_links
printf '%s\n' 'references/procedures/b.md' > "$FIXTURE/references/procedures/a.md"
printf '%s\n' 'references/procedures/a.md' > "$FIXTURE/references/procedures/b.md"
check 'isolated mutual references' 1 'not reachable from entry documents'

new_fixture dead_workflow
printf '%s\n' 'references/procedures/dead.md' > "$FIXTURE/references/dead-workflow.md"
printf '%s\n' '# Dead procedure' > "$FIXTURE/references/procedures/dead.md"
check 'reference from unreachable workflow' 1 'not reachable from entry documents'

new_fixture split_root
mkdir "$FIXTURE/procedures"
check 'split Tier-2 root' 1 'split Tier-2 root returned'

new_fixture empty
: > "$FIXTURE/references/workflow.md"
rm "$FIXTURE/references/procedures/base.md"
check 'no procedures or references' 1 'no Tier-2 procedure references found'

if [[ "$failed" -ne 0 ]]; then
  printf 'FAIL: %s/%s resource link validation cases failed\n' "$failed" "$((passed + failed))" >&2
  exit 1
fi
printf 'resource link validation passed (%s cases)\n' "$passed"

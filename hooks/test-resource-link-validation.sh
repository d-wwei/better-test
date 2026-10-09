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

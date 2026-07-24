#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_FILE="$(mktemp "${TMPDIR:-/tmp}/better-test-resource-links.XXXXXX")"
trap 'rm -f "$TMP_FILE"' EXIT

rg --no-filename -o 'references/procedures/[A-Za-z0-9._/-]+\.md' \
  "$ROOT_DIR/SKILL.md" "$ROOT_DIR/references" "$ROOT_DIR/README.md" \
  "$ROOT_DIR/README.zh-CN.md" | sort -u >"$TMP_FILE"

if [[ ! -s "$TMP_FILE" ]]; then
  echo "FAIL: no Tier-2 procedure references found" >&2
  exit 1
fi

while IFS= read -r resource_path; do
  if [[ ! -f "$ROOT_DIR/$resource_path" ]]; then
    echo "FAIL: referenced resource does not exist: $resource_path" >&2
    exit 1
  fi
done <"$TMP_FILE"

if [[ -d "$ROOT_DIR/procedures" ]]; then
  echo "FAIL: split Tier-2 root returned: $ROOT_DIR/procedures" >&2
  exit 1
fi

expected_count=10
actual_count="$(find "$ROOT_DIR/references/procedures" -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ')"
if [[ "$actual_count" != "$expected_count" ]]; then
  echo "FAIL: expected $expected_count Tier-2 procedures, found $actual_count" >&2
  exit 1
fi

echo "resource link integrity passed ($actual_count Tier-2 procedures)"

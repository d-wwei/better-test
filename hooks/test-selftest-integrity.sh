#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

if grep -n -E '(^|[[:space:]])rg([[:space:]]|$)' \
  "$ROOT_DIR/hooks/test-hybrid-testing.sh" \
  "$ROOT_DIR/hooks/test-test-root-resolution.sh" >/dev/null; then
  echo "FAIL: guarded tests still depend on rg" >&2
  exit 1
fi

printf 'clean\nmoomoo\n' >"$TMP_DIR/positive.txt"
if ! grep -i -E '(^|[^[:alnum:]_])(futu|opend|moomoo)([^[:alnum:]_]|$)' \
  "$TMP_DIR/positive.txt" >/dev/null; then
  echo "FAIL: product-specific positive control was not detected" >&2
  exit 1
fi

set +e
grep -E 'anything' "$TMP_DIR/missing.txt" >/dev/null 2>&1
guard_rc=$?
set -e
if [[ "$guard_rc" -lt 2 ]]; then
  echo "FAIL: missing input did not produce a grep tool error" >&2
  exit 1
fi

set +e
BETTER_TEST_EXTRA_REQUIRED_COMMANDS=better-test-command-that-does-not-exist \
  bash "$ROOT_DIR/scripts/test-all.sh" >"$TMP_DIR/preflight.log" 2>&1
preflight_rc=$?
set -e
if [[ "$preflight_rc" -eq 0 ]]; then
  echo "FAIL: dependency preflight accepted a missing command" >&2
  exit 1
fi
if grep -q '^PASS:' "$TMP_DIR/preflight.log"; then
  echo "FAIL: dependency preflight printed PASS after failure" >&2
  exit 1
fi

echo "self-test integrity checks passed"

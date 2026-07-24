#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
VALIDATOR="$REPO_ROOT/scripts/validate-pairwise.py"
VALID_FIXTURE="$SCRIPT_DIR/fixtures/pairwise-valid.json"
MISSING_PAIR_FIXTURE="$SCRIPT_DIR/fixtures/pairwise-missing-pair.json"
MISSING_CLASS_FIXTURE="$SCRIPT_DIR/fixtures/pairwise-missing-class.json"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

expect_failure() {
  local label="$1"
  local expected="$2"
  local fixture="$3"
  if python3 "$VALIDATOR" "$fixture" \
    >"$TMP_DIR/$label.out" 2>"$TMP_DIR/$label.err"
  then
    echo "$label fixture unexpectedly passed" >&2
    exit 1
  fi
  grep -F "$expected" "$TMP_DIR/$label.err" >/dev/null
}

python3 "$VALIDATOR" "$VALID_FIXTURE" >"$TMP_DIR/valid.out"
grep -F "pairwise validation passed" "$TMP_DIR/valid.out" >/dev/null

expect_failure "missing-pair" "pairwise: missing pair" "$MISSING_PAIR_FIXTURE"
expect_failure \
  "missing-class" \
  "unreferenced class(es): 'auth-canary'" \
  "$MISSING_CLASS_FIXTURE"

jq '.factors[1].name = "transport"' \
  "$VALID_FIXTURE" >"$TMP_DIR/duplicate-factor.json"
expect_failure \
  "duplicate-factor" \
  "duplicate factor name(s): 'transport'" \
  "$TMP_DIR/duplicate-factor.json"

jq '.factors[0].levels += ["http"]' \
  "$VALID_FIXTURE" >"$TMP_DIR/duplicate-level.json"
expect_failure \
  "duplicate-level" \
  "duplicate level(s): 'http'" \
  "$TMP_DIR/duplicate-level.json"

jq 'del(.cases[0].values.payload)' \
  "$VALID_FIXTURE" >"$TMP_DIR/missing-factor.json"
expect_failure \
  "missing-factor" \
  "missing factor(s): 'payload'" \
  "$TMP_DIR/missing-factor.json"

jq '.cases[0].values.auth = "certificate"' \
  "$VALID_FIXTURE" >"$TMP_DIR/illegal-level.json"
expect_failure \
  "illegal-level" \
  "illegal level 'certificate'" \
  "$TMP_DIR/illegal-level.json"

jq '.high_risk_canaries[0].case_id = "C999"' \
  "$VALID_FIXTURE" >"$TMP_DIR/dangling-canary.json"
expect_failure \
  "dangling-canary" \
  "unknown case 'C999'" \
  "$TMP_DIR/dangling-canary.json"

jq '.required_equivalence_classes = [] | .cases[].classes = []' \
  "$VALID_FIXTURE" >"$TMP_DIR/no-equivalence-classes.json"
expect_failure \
  "no-equivalence-classes" \
  "expected at least one explicit class" \
  "$TMP_DIR/no-equivalence-classes.json"

python3 - "$VALID_FIXTURE" "$TMP_DIR/duplicate-key.json" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")
text = text.replace(
    '  "factors": [',
    '  "factors": [],\n  "factors": [',
    1,
)
Path(sys.argv[2]).write_text(text, encoding="utf-8")
PY
expect_failure \
  "duplicate-key" \
  "duplicate JSON key: factors" \
  "$TMP_DIR/duplicate-key.json"

echo "pairwise validation tests passed"

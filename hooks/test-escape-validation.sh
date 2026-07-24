#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VALIDATOR="$ROOT_DIR/scripts/validate-escapes.py"
FIXTURES="$ROOT_DIR/hooks/fixtures"
TMP_FILE="$(mktemp "$FIXTURES/.better-test-escape.XXXXXX")"
trap 'rm -f "$TMP_FILE"' EXIT

python3 "$VALIDATOR" "$FIXTURES/escapes-valid.json" >/dev/null

if python3 "$VALIDATOR" "$FIXTURES/escapes-invalid-closed.json" >/dev/null 2>&1; then
  echo "FAIL: closed escape with planned action was accepted" >&2
  exit 1
fi

jq '.schema_version = true' "$FIXTURES/escapes-valid.json" >"$TMP_FILE"
if python3 "$VALIDATOR" "$TMP_FILE" >/dev/null 2>&1; then
  echo "FAIL: boolean schema_version was accepted as integer 1" >&2
  exit 1
fi

jq '.escapes[0].gate.gate_id = "none"
    | .escapes[0].gate.execution_status = "executed-missed"' \
  "$FIXTURES/escapes-valid.json" >"$TMP_FILE"
if python3 "$VALIDATOR" "$TMP_FILE" >/dev/null 2>&1; then
  echo "FAIL: executed-missed escape without a real gate was accepted" >&2
  exit 1
fi

jq '.escapes[0].closure_evidence = ["missing-evidence.json"]' \
  "$FIXTURES/escapes-valid.json" >"$TMP_FILE"
if python3 "$VALIDATOR" "$TMP_FILE" >/dev/null 2>&1; then
  echo "FAIL: closed escape with missing evidence artifact was accepted" >&2
  exit 1
fi

python3 - "$FIXTURES/escapes-valid.json" "$TMP_FILE" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")
text = text.replace(
    '  "escapes": [',
    '  "escapes": [],\n  "escapes": [',
    1,
)
Path(sys.argv[2]).write_text(text, encoding="utf-8")
PY
if python3 "$VALIDATOR" "$TMP_FILE" >/dev/null 2>&1; then
  echo "FAIL: duplicate escape ledger key was accepted" >&2
  exit 1
fi

echo "escape ledger validation passed"

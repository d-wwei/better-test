#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VALIDATOR="$ROOT_DIR/scripts/validate-release-set.py"
BASE="$ROOT_DIR/hooks/fixtures/results-v3-valid.json"
POLICY="$ROOT_DIR/hooks/fixtures/release-set-policy-valid.json"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/better-test-release-set.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

copy_artifacts() {
  local destination="$1"
  mkdir -p "$destination/artifacts"
  cp "$ROOT_DIR"/hooks/fixtures/artifacts/* "$destination/artifacts/"
}

mkdir -p "$TMP_DIR/legacy" "$TMP_DIR/auth"
copy_artifacts "$TMP_DIR/legacy"
copy_artifacts "$TMP_DIR/auth"
jq '.environment.environment_id = "env-legacy"
    | .environment.machine_id = "machine-a"
    | .environment.config_profile = "legacy"' \
  "$BASE" >"$TMP_DIR/legacy/results.json"
jq '.run_id = "run-codex-a3f2-003-20260724T130000+0800"
    | .environment.environment_id = "env-auth"
    | .environment.machine_id = "machine-b"
    | .environment.config_profile = "auth"' \
  "$BASE" >"$TMP_DIR/auth/results.json"

python3 "$VALIDATOR" --policy "$POLICY" \
  "$TMP_DIR/legacy/results.json" "$TMP_DIR/auth/results.json" >/dev/null

if python3 "$VALIDATOR" --policy "$POLICY" \
  "$TMP_DIR/legacy/results.json" "$TMP_DIR/legacy/results.json" \
  >/dev/null 2>&1; then
  echo "FAIL: duplicated environment/config was accepted as a two-profile set" >&2
  exit 1
fi

mkdir -p "$TMP_DIR/duplicate-run" "$TMP_DIR/version-drift" "$TMP_DIR/missing-gate"
copy_artifacts "$TMP_DIR/duplicate-run"
copy_artifacts "$TMP_DIR/version-drift"
copy_artifacts "$TMP_DIR/missing-gate"
jq '.run_id = "run-codex-a3f2-002-20260724T120000+0800"
    | .environment.environment_id = "env-auth"
    | .environment.machine_id = "machine-b"
    | .environment.config_profile = "auth"' \
  "$BASE" >"$TMP_DIR/duplicate-run/results.json"
if python3 "$VALIDATOR" --policy "$POLICY" \
  "$TMP_DIR/legacy/results.json" "$TMP_DIR/duplicate-run/results.json" \
  >/dev/null 2>&1; then
  echo "FAIL: duplicate run_id was accepted as independent release evidence" >&2
  exit 1
fi

jq '.run_id = "run-codex-a3f2-004-20260724T140000+0800"
    | .version = "9.9.9"
    | .environment.environment_id = "env-auth"
    | .environment.machine_id = "machine-b"
    | .environment.config_profile = "auth"' \
  "$BASE" >"$TMP_DIR/version-drift/results.json"
if python3 "$VALIDATOR" --policy "$POLICY" \
  "$TMP_DIR/legacy/results.json" "$TMP_DIR/version-drift/results.json" \
  >/dev/null 2>&1; then
  echo "FAIL: mixed target versions were accepted in one release set" >&2
  exit 1
fi

jq '.run_id = "run-codex-a3f2-005-20260724T150000+0800"
    | .environment.environment_id = "env-auth"
    | .environment.machine_id = "machine-b"
    | .environment.config_profile = "auth"
    | .gate_items = []
    | .dod.check_results[].gate_ids = []' \
  "$BASE" >"$TMP_DIR/missing-gate/results.json"
if python3 "$VALIDATOR" --policy "$POLICY" \
  "$TMP_DIR/legacy/results.json" "$TMP_DIR/missing-gate/results.json" \
  >/dev/null 2>&1; then
  echo "FAIL: required gate was absent from a required config profile" >&2
  exit 1
fi

jq '.schema_version = true
    | .min_distinct_environments = true
    | .min_distinct_machines = true' \
  "$POLICY" >"$TMP_DIR/policy-bool.json"
if python3 "$VALIDATOR" --policy "$TMP_DIR/policy-bool.json" \
  "$TMP_DIR/legacy/results.json" "$TMP_DIR/auth/results.json" \
  >/dev/null 2>&1; then
  echo "FAIL: boolean release policy fields were accepted as integers" >&2
  exit 1
fi

python3 - "$POLICY" "$TMP_DIR/policy-duplicate-key.json" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")
text = text.replace(
    '  "schema_version": 1,',
    '  "schema_version": 999,\n  "schema_version": 1,',
    1,
)
Path(sys.argv[2]).write_text(text, encoding="utf-8")
PY
if python3 "$VALIDATOR" --policy "$TMP_DIR/policy-duplicate-key.json" \
  "$TMP_DIR/legacy/results.json" "$TMP_DIR/auth/results.json" \
  >/dev/null 2>&1; then
  echo "FAIL: duplicate release policy key was accepted" >&2
  exit 1
fi

echo "release-set environment/config validation passed"

#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VALIDATOR="$ROOT_DIR/scripts/validate-run.py"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

RUN_DIR="$TMP_DIR/run"
mkdir -p "$RUN_DIR"
cp "$ROOT_DIR/hooks/fixtures/results-v3-valid.json" "$RUN_DIR/results.json"
cp -R "$ROOT_DIR/hooks/fixtures/artifacts" "$RUN_DIR/artifacts"

expect_fail() {
  local expected="$1"
  shift
  local output=""
  local rc=0
  output=$("$@" 2>&1) || rc=$?
  if [[ "$rc" -eq 0 || "$output" != *"$expected"* ]]; then
    echo "expected failure containing: $expected" >&2
    printf '%s\n' "$output" >&2
    exit 1
  fi
}

python3 "$VALIDATOR" --run-dir "$RUN_DIR" --intake-policy advisory >/dev/null
expect_fail "missing intake.json" \
  python3 "$VALIDATOR" --run-dir "$RUN_DIR" --intake-policy required

jq -n '{
  schema_version:1,
  intake_id:"intake-run-validation",
  produced_by:"fixture",
  attested_at:"2026-08-24T14:30:00+08:00",
  subjects:[{id:"source",type:"source",identity:{commit:"fixture",dirty:false}}],
  relations:[]
}' >"$RUN_DIR/intake.json"
INTAKE_SHA="$(shasum -a 256 "$RUN_DIR/intake.json" | awk '{print $1}')"
jq --arg sha "$INTAKE_SHA" \
  '.intake_ref={intake_id:"intake-run-validation",sha256:$sha}' \
  "$RUN_DIR/results.json" >"$RUN_DIR/results.next"
mv "$RUN_DIR/results.next" "$RUN_DIR/results.json"

python3 "$VALIDATOR" --run-dir "$RUN_DIR" --intake-policy required >/dev/null

python3 "$ROOT_DIR/scripts/build-run-metrics.py" \
  --run-dir "$RUN_DIR" \
  --resume-count 1 \
  --resume-failed false \
  --validator-blocks 2 \
  --resource-conflicts 0 >/dev/null
jq -e '
  .run_id == "run-codex-a3f2-002-20260724T120000+0800" and
  .results_schema_version == 3 and
  .tester_count == 1 and
  .wall_clock_minutes == 5 and
  .resume_count == 1 and
  .validator_blocks == 2 and
  .verdict == "GO" and
  .intake_present == true and
  .intake_binding == "valid"
' "$RUN_DIR/metrics.json" >/dev/null

jq '.intake_id = "mutated"' "$RUN_DIR/intake.json" >"$RUN_DIR/intake.next"
mv "$RUN_DIR/intake.next" "$RUN_DIR/intake.json"
expect_fail "intake_ref.intake_id does not match" \
  python3 "$VALIDATOR" --run-dir "$RUN_DIR" --intake-policy required

echo "run validation tests passed"

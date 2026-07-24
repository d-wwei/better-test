#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VALIDATOR="$ROOT_DIR/scripts/validate-merged-results.py"
FIXTURE_DIR="$ROOT_DIR/hooks/fixtures"
BASE="$FIXTURE_DIR/merged-results-v2-valid.json"
SOURCE_A="$FIXTURE_DIR/merged-runs/run-codex-a3f2-001/results.json"
SOURCE_B="$FIXTURE_DIR/merged-runs/run-claude-b4e3-001/results.json"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/better-test-merged-results.XXXXXX")"
ABS_BASE="$TMP_DIR/merged-results-absolute.json"
TMP_FILE="$TMP_DIR/merged-results-mutated.json"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT
cp "$FIXTURE_DIR/verdict-challenge.md" "$TMP_DIR/verdict-challenge.md"

copy_source_artifacts() {
  local source_results="$1"
  local destination="$2"
  mkdir -p "$destination/artifacts"
  cp "$(dirname "$source_results")"/artifacts/* "$destination/artifacts/"
}

expect_invalid() {
  local label="$1"
  local expected="$2"
  local candidate="$3"
  if python3 "$VALIDATOR" "$candidate" \
    >"$TMP_DIR/$label.out" 2>"$TMP_DIR/$label.err"
  then
    echo "FAIL: $label unexpectedly passed" >&2
    exit 1
  fi
  if ! grep -F "$expected" "$TMP_DIR/$label.err" >/dev/null; then
    echo "FAIL: $label did not report expected error: $expected" >&2
    cat "$TMP_DIR/$label.err" >&2
    exit 1
  fi
}

mutate_and_reject() {
  local label="$1"
  local expected="$2"
  local filter="$3"
  jq "$filter" "$ABS_BASE" >"$TMP_FILE"
  expect_invalid "$label" "$expected" "$TMP_FILE"
}

python3 "$VALIDATOR" "$BASE" >/dev/null

# Use absolute source references so mutated merged files remain valid in TMP_DIR.
jq --arg root "$FIXTURE_DIR" '
  .source_runs |= map(.results_path = ($root + "/" + .results_path))
' "$BASE" >"$ABS_BASE"
python3 "$VALIDATOR" "$ABS_BASE" >/dev/null

mutate_and_reject \
  "self-challenge" \
  "verdict challenger must differ" \
  '.verdict_challenge.challenger = ("  " + .verdict_challenge.drafted_by + "  ")'

mutate_and_reject \
  "challenge-reason" \
  "verdict_challenge.reason must be trimmed and non-empty" \
  '.verdict_challenge.reason = ""'

mutate_and_reject \
  "challenge-reviewed-at" \
  "verdict_challenge.reviewed_at must be a trimmed ISO 8601 timestamp" \
  '.verdict_challenge.reviewed_at = ""'

mutate_and_reject \
  "challenge-count" \
  "unresolved_count does not match dispositions (1)" \
  '.verdict_challenge.dispositions[0].disposition = "unresolved"'

mutate_and_reject \
  "unbound-external-reviewer" \
  "external verdict challenger requires matching reviewer_id" \
  '.verdict_challenge.challenger = "external-l2"'

jq '
  .verdict_challenge.challenger = "external-l2"
  | .verdict_challenge.external_reviewer = {
      "reviewer_id": "external-l2",
      "identity": "independent l2-skeptic session",
      "evidence_ref": "verdict-challenge.md#independent-review"
    }
' "$ABS_BASE" >"$TMP_FILE"
python3 "$VALIDATOR" "$TMP_FILE" >/dev/null

mutate_and_reject \
  "external-reviewer-missing-evidence" \
  "external reviewer evidence_ref must resolve to a file" \
  '.verdict_challenge.challenger = "external-l2"
   | .verdict_challenge.external_reviewer = {
       reviewer_id: "external-l2",
       identity: "independent l2-skeptic session",
       evidence_ref: "missing-challenge.md"
     }'

mutate_and_reject \
  "invalid-merged-time" \
  "merged_at must be a valid ISO 8601 timestamp" \
  '.merged_at = "not-a-date"'

mutate_and_reject \
  "challenge-before-merge" \
  "verdict_challenge.reviewed_at cannot be before merged_at" \
  '.verdict_challenge.reviewed_at = "2026-07-24T13:59:59+08:00"'

mutate_and_reject \
  "wrong-sha" \
  "sha256 does not match results.json" \
  '.source_runs[0].sha256 = ("0" * 64)'

mutate_and_reject \
  "run-id-binding" \
  "run_id does not match referenced results.json" \
  '.source_runs[0].run_id = "run-forged"'

mutate_and_reject \
  "schema-binding" \
  "schema_version does not match referenced results.json" \
  '.source_runs[0].schema_version = 2'

mutate_and_reject \
  "version-binding" \
  "version does not match referenced results.json" \
  '.source_runs[0].version = "9.9.9"'

mutate_and_reject \
  "package-binding" \
  "package_type does not match referenced results.json" \
  '.source_runs[0].package_type = "rc"'

mutate_and_reject \
  "environment-binding" \
  "environment does not match referenced results.json" \
  '.source_runs[0].environment.environment_id = "forged-env"'

mkdir -p "$TMP_DIR/invalid-source"
copy_source_artifacts "$SOURCE_A" "$TMP_DIR/invalid-source"
jq 'del(.tester_id)' "$SOURCE_A" >"$TMP_DIR/invalid-source/results.json"
INVALID_SOURCE_SHA="$(
  shasum -a 256 "$TMP_DIR/invalid-source/results.json" | awk '{print $1}'
)"
jq \
  --arg path "$TMP_DIR/invalid-source/results.json" \
  --arg sha "$INVALID_SOURCE_SHA" \
  '.source_runs[0].results_path = $path | .source_runs[0].sha256 = $sha' \
  "$ABS_BASE" >"$TMP_FILE"
expect_invalid \
  "strict-source-validation" \
  "failed validate-results.sh" \
  "$TMP_FILE"

mutate_and_reject \
  "empty-items" \
  "GO requires non-empty items" \
  '.items = [] | .summary = {
    "total": 0,
    "passed": 0,
    "failed": 0,
    "skipped": 0,
    "conflicts": 0
  }'

mutate_and_reject \
  "empty-gates" \
  "merged gate_items do not cover every source gate" \
  '.gate_items = []'

mutate_and_reject \
  "empty-summary" \
  "GO requires a non-empty summary" \
  '.summary = {}'

mutate_and_reject \
  "empty-dod" \
  "GO requires non-empty DoD" \
  '.dod = {}'

mutate_and_reject \
  "summary-drift" \
  "summary.passed=0 does not match items (1)" \
  '.summary.passed = 0'

mutate_and_reject \
  "omitted-source-occurrence" \
  "source_runs do not cover every source item occurrence" \
  '.items[0].source_runs = ["run-codex-a3f2-001"]'

mutate_and_reject \
  "unknown-gate-item" \
  "references unknown merged item FORGED-ITEM" \
  '.gate_items[0].item_ids = ["FORGED-ITEM"]'

mutate_and_reject \
  "unknown-gate-evidence" \
  "does not reference real evidence" \
  '.gate_items[0].evidence_refs[0].source_id = "FORGED-EVIDENCE"'

mutate_and_reject \
  "omitted-source-gate" \
  "source_runs do not match source gate occurrences" \
  '.gate_items[0].source_runs = ["run-codex-a3f2-001"]'

mutate_and_reject \
  "dod-check-binding" \
  "does not reference a real source DoD check" \
  '.dod.check_refs[0].check_id = "forged-check"'

mkdir -p "$TMP_DIR/no-go-source"
copy_source_artifacts "$SOURCE_A" "$TMP_DIR/no-go-source"
jq '.release_readiness.verdict = "no-go"' \
  "$SOURCE_A" >"$TMP_DIR/no-go-source/results.json"
NO_GO_SHA="$(
  shasum -a 256 "$TMP_DIR/no-go-source/results.json" | awk '{print $1}'
)"
jq \
  --arg path "$TMP_DIR/no-go-source/results.json" \
  --arg sha "$NO_GO_SHA" \
  '.source_runs[0].results_path = $path | .source_runs[0].sha256 = $sha' \
  "$ABS_BASE" >"$TMP_FILE"
expect_invalid \
  "source-readiness" \
  "GO rejects source run run-codex-a3f2-001 release_readiness=no-go" \
  "$TMP_FILE"

mkdir -p "$TMP_DIR/targeted-source"
copy_source_artifacts "$SOURCE_A" "$TMP_DIR/targeted-source"
jq '.release_readiness.verdict = "not_applicable"' \
  "$SOURCE_A" >"$TMP_DIR/targeted-source/results.json"
TARGETED_SHA="$(
  shasum -a 256 "$TMP_DIR/targeted-source/results.json" | awk '{print $1}'
)"
jq \
  --arg path "$TMP_DIR/targeted-source/results.json" \
  --arg sha "$TARGETED_SHA" \
  '.source_runs[0].results_path = $path | .source_runs[0].sha256 = $sha' \
  "$ABS_BASE" >"$TMP_FILE"
python3 "$VALIDATOR" "$TMP_FILE" >/dev/null

mkdir -p "$TMP_DIR/targeted-source-b"
copy_source_artifacts "$SOURCE_B" "$TMP_DIR/targeted-source-b"
jq '.release_readiness.verdict = "not_applicable"' \
  "$SOURCE_B" >"$TMP_DIR/targeted-source-b/results.json"
TARGETED_B_SHA="$(
  shasum -a 256 "$TMP_DIR/targeted-source-b/results.json" | awk '{print $1}'
)"
jq \
  --arg path_a "$TMP_DIR/targeted-source/results.json" \
  --arg sha_a "$TARGETED_SHA" \
  --arg path_b "$TMP_DIR/targeted-source-b/results.json" \
  --arg sha_b "$TARGETED_B_SHA" '
    .source_runs[0].results_path = $path_a
    | .source_runs[0].sha256 = $sha_a
    | .source_runs[1].results_path = $path_b
    | .source_runs[1].sha256 = $sha_b
  ' "$ABS_BASE" >"$TMP_FILE"
expect_invalid \
  "all-targeted-sources" \
  "targeted not_applicable runs cannot create release approval" \
  "$TMP_FILE"

mkdir -p "$TMP_DIR/hidden-fail-source"
copy_source_artifacts "$SOURCE_B" "$TMP_DIR/hidden-fail-source"
cp "$TMP_DIR/hidden-fail-source/artifacts/client.json" \
  "$TMP_DIR/hidden-fail-source/artifacts/failure.json"
jq '
  .summary.total = 2
  | .summary.failed = 1
  | .coverage.manifest_total = 2
  | .coverage.reachable = 2
  | .coverage.tested = 2
  | .items += [{
      "id": "AUTH-FAIL-02",
      "name": "hidden source failure",
      "group": "AUTH-READY",
      "type": "functional",
      "status": "fail",
      "assertion_field": "session_state",
      "assertion_value": "error",
      "evidence_level": "direct",
      "evidence_sources": [{
        "source_id": "SRC-B-FAIL",
        "independence_key": "client-json-failure",
        "artifact_ref": "artifacts/failure.json"
      }],
      "error_code": "AUTH_NOT_READY",
      "error_detail": "The authenticated session did not become ready.",
      "pre_existing": false
    }]
  | .release_readiness.verdict = "no-go"
' "$SOURCE_B" >"$TMP_DIR/hidden-fail-source/results.json"
HIDDEN_FAIL_SHA="$(
  shasum -a 256 "$TMP_DIR/hidden-fail-source/results.json" | awk '{print $1}'
)"
jq \
  --arg path "$TMP_DIR/hidden-fail-source/results.json" \
  --arg sha "$HIDDEN_FAIL_SHA" \
  '.source_runs[1].results_path = $path | .source_runs[1].sha256 = $sha' \
  "$ABS_BASE" >"$TMP_FILE"
expect_invalid \
  "hidden-source-fail" \
  "merged items do not cover every source item" \
  "$TMP_FILE"

mkdir -p "$TMP_DIR/item-definition-drift"
copy_source_artifacts "$SOURCE_B" "$TMP_DIR/item-definition-drift"
jq '.items[0].name = "different semantic claim under the same item ID"' \
  "$SOURCE_B" >"$TMP_DIR/item-definition-drift/results.json"
ITEM_DRIFT_SHA="$(
  shasum -a 256 "$TMP_DIR/item-definition-drift/results.json" | awk '{print $1}'
)"
jq \
  --arg path "$TMP_DIR/item-definition-drift/results.json" \
  --arg sha "$ITEM_DRIFT_SHA" \
  '.source_runs[1].results_path = $path | .source_runs[1].sha256 = $sha' \
  "$ABS_BASE" >"$TMP_FILE"
expect_invalid \
  "item-definition-drift" \
  "source item AUTH-READY-01 definition drift across runs" \
  "$TMP_FILE"

mkdir -p "$TMP_DIR/gate-scope-drift"
copy_source_artifacts "$SOURCE_B" "$TMP_DIR/gate-scope-drift"
cp "$TMP_DIR/gate-scope-drift/artifacts/client.json" \
  "$TMP_DIR/gate-scope-drift/artifacts/scope-client.json"
jq '
  .summary.total = 2
  | .summary.passed = 2
  | .coverage.manifest_total = 2
  | .coverage.reachable = 2
  | .coverage.tested = 2
  | .items += [{
      "id": "AUTH-SCOPE-02",
      "name": "different gate semantic scope",
      "group": "AUTH-SCOPE",
      "type": "functional",
      "status": "pass",
      "assertion_field": "scope_state",
      "assertion_value": "ready",
      "evidence_level": "direct",
      "evidence_sources": [{
        "source_id": "SRC-B-SCOPE",
        "independence_key": "scope-client-json",
        "artifact_ref": "artifacts/scope-client.json"
      }],
      "pre_existing": false
    }]
  | .gate_items[0].item_ids = ["AUTH-SCOPE-02"]
  | .gate_items[0].evidence_refs = ["SRC-B-SCOPE"]
' "$SOURCE_B" >"$TMP_DIR/gate-scope-drift/results.json"
GATE_DRIFT_SHA="$(
  shasum -a 256 "$TMP_DIR/gate-scope-drift/results.json" | awk '{print $1}'
)"
jq \
  --arg path "$TMP_DIR/gate-scope-drift/results.json" \
  --arg sha "$GATE_DRIFT_SHA" \
  '.source_runs[1].results_path = $path | .source_runs[1].sha256 = $sha' \
  "$ABS_BASE" >"$TMP_FILE"
expect_invalid \
  "gate-scope-drift" \
  "source gate GATE-AUTH-READY item scope drift across runs" \
  "$TMP_FILE"

# A project with no applicable source gates may publish an empty merged gate
# ledger; the empty array is then the exact source aggregation, not fail-open.
mkdir -p "$TMP_DIR/no-gate-a" "$TMP_DIR/no-gate-b"
copy_source_artifacts "$SOURCE_A" "$TMP_DIR/no-gate-a"
copy_source_artifacts "$SOURCE_B" "$TMP_DIR/no-gate-b"
jq '
  .gate_items = []
  | .gate_applicability = "none"
  | .gate_applicability_reason = "This fixture declares no applicable project gates."
  | .dod.check_results |= map(.gate_ids = [])
' "$SOURCE_A" >"$TMP_DIR/no-gate-a/results.json"
jq '
  .gate_items = []
  | .gate_applicability = "none"
  | .gate_applicability_reason = "This fixture declares no applicable project gates."
  | .dod.check_results |= map(.gate_ids = [])
' "$SOURCE_B" >"$TMP_DIR/no-gate-b/results.json"
NO_GATE_A_SHA="$(
  shasum -a 256 "$TMP_DIR/no-gate-a/results.json" | awk '{print $1}'
)"
NO_GATE_B_SHA="$(
  shasum -a 256 "$TMP_DIR/no-gate-b/results.json" | awk '{print $1}'
)"
jq \
  --arg path_a "$TMP_DIR/no-gate-a/results.json" \
  --arg sha_a "$NO_GATE_A_SHA" \
  --arg path_b "$TMP_DIR/no-gate-b/results.json" \
  --arg sha_b "$NO_GATE_B_SHA" '
    .source_runs[0].results_path = $path_a
    | .source_runs[0].sha256 = $sha_a
    | .source_runs[1].results_path = $path_b
    | .source_runs[1].sha256 = $sha_b
    | .gate_items = []
  ' "$ABS_BASE" >"$TMP_FILE"
python3 "$VALIDATOR" "$TMP_FILE" >/dev/null

python3 - "$ABS_BASE" "$TMP_FILE" <<'PY'
import json
from pathlib import Path
import sys

document = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
document["nonstandard_number"] = float("nan")
Path(sys.argv[2]).write_text(
    json.dumps(document, ensure_ascii=False),
    encoding="utf-8",
)
PY
expect_invalid \
  "nonstandard-json-number" \
  "non-standard JSON constant" \
  "$TMP_FILE"

python3 - "$ABS_BASE" "$TMP_FILE" <<'PY'
import json
from pathlib import Path
import sys

document = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
document["schema_version"] = 2.0
document["environment_coverage"]["distinct_environments"] = 2.0
document["environment_coverage"]["distinct_machines"] = 2.0
Path(sys.argv[2]).write_text(
    json.dumps(document, ensure_ascii=False),
    encoding="utf-8",
)
PY
expect_invalid \
  "float-integer-fields" \
  "schema_version must be integer 2" \
  "$TMP_FILE"

echo "merged-results source binding and closure validation passed"

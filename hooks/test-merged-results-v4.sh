#!/usr/bin/env bash
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export BETTER_TEST_TRUSTED_PROFILE="$ROOT_DIR/fixtures/providers/project-profile-valid.json"
VALIDATOR="$ROOT_DIR/scripts/validate-merged-results-v4.py"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/better-test-merged-v4.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/merge/run-a" "$TMP_DIR/merge/run-b"
cp "$ROOT_DIR/fixtures/results-v4/artifact.txt" "$TMP_DIR/merge/run-a/artifact.txt"
cp "$ROOT_DIR/fixtures/results-v4/artifact.txt" "$TMP_DIR/merge/run-b/artifact.txt"
for input in project-profile.json capabilities.json strategy.json source-map.json source-impact.json; do
  cp "$ROOT_DIR/fixtures/results-v4/$input" "$TMP_DIR/merge/run-a/$input"
  cp "$ROOT_DIR/fixtures/results-v4/$input" "$TMP_DIR/merge/run-b/$input"
done
jq '
  .tester_id = "tester-a" |
  .run_id = "run-a" |
  .items[0].status = "pass_with_caveat" |
  .items[0].reason = "accepted compatibility limitation"
' "$ROOT_DIR/fixtures/results-v4/results.json" >"$TMP_DIR/merge/run-a/results.json"
jq '
  .tester_id = "tester-b" |
  .run_id = "run-b"
' "$ROOT_DIR/fixtures/results-v4/results.json" >"$TMP_DIR/merge/run-b/results.json"

SHA_A="$(shasum -a 256 "$TMP_DIR/merge/run-a/results.json" | awk '{print $1}')"
SHA_B="$(shasum -a 256 "$TMP_DIR/merge/run-b/results.json" | awk '{print $1}')"
jq -n \
  --slurpfile a "$TMP_DIR/merge/run-a/results.json" \
  --slurpfile b "$TMP_DIR/merge/run-b/results.json" \
  --arg sha_a "$SHA_A" --arg sha_b "$SHA_B" '
  {
    schema_version: 4,
    document_type: "better-test-merged-results",
    contract_version: "1.0.0",
    version: "1.0.0",
    merge_id: "merge-fixture-001",
    coordinator_id: "coordinator-fixture",
    merged_at: "2026-08-01T10:05:00+08:00",
    source_runs: [
      {run_id:"run-a",schema_version:4,version:"1.0.0",results_path:"run-a/results.json",sha256:$sha_a},
      {run_id:"run-b",schema_version:4,version:"1.0.0",results_path:"run-b/results.json",sha256:$sha_b}
    ],
    subjects:
      ([$a[0].subjects[] | {source_run:"run-a",subject:.}] +
       [$b[0].subjects[] | {source_run:"run-b",subject:.}]),
    relations:
      ([$a[0].relations[] | {source_run:"run-a",relation:.}] +
       [$b[0].relations[] | {source_run:"run-b",relation:.}]),
    items: [{
      id: "SRC-UNIT.01",
      result: "pass_with_caveat",
      occurrences: [
        {source_run:"run-a",item:$a[0].items[0]},
        {source_run:"run-b",item:$b[0].items[0]}
      ]
    }],
    gates: [{
      id: "source-closure",
      verdict: "pass",
      occurrences: [
        {source_run:"run-a",gate:$a[0].gates[0]},
        {source_run:"run-b",gate:$b[0].gates[0]}
      ]
    }],
    summary: {
      total:1, passed:1, passed_unconditional:0, passed_with_caveat:1,
      passed_known_legacy_behavior:0, failed:0, blocked:0, partial:0,
      skipped:0, excluded:0, conflicts:0
    },
    max_claim_scope: "source_correctness",
    caveat_overrides: [{
      source_run:"run-a",item_id:"SRC-UNIT.01",approved_by:"coordinator-fixture",
      approved_at:"2026-08-01T10:04:00+08:00",reason:"caveat explicitly reviewed"
    }],
    release_readiness: {
      verdict:"not_applicable",
      reason:"both source runs are source-only",
      source_verdicts: [
        {source_run:"run-a",verdict:$a[0].release_readiness.verdict,reason:$a[0].release_readiness.reason},
        {source_run:"run-b",verdict:$b[0].release_readiness.verdict,reason:$b[0].release_readiness.reason}
      ]
    },
    verdict_challenge: {
      drafted_by:"coordinator-fixture",challenger:"independent-l2-fixture",
      reviewed_at:"2026-08-01T10:04:30+08:00",unresolved_count:0,
      reason:"typed occurrences and conservative aggregation reviewed"
    }
  }
' >"$TMP_DIR/merge/merged-results.json"

python3 "$VALIDATOR" "$TMP_DIR/merge/merged-results.json" >/dev/null

expect_invalid() {
  local label="$1"
  local expected="$2"
  local filter="$3"
  jq "$filter" "$TMP_DIR/merge/merged-results.json" >"$TMP_DIR/merge/$label.json"
  if python3 "$VALIDATOR" "$TMP_DIR/merge/$label.json" \
    >"$TMP_DIR/$label.out" 2>"$TMP_DIR/$label.err"; then
    echo "FAIL: $label unexpectedly passed" >&2
    exit 1
  fi
  if ! grep -F "$expected" "$TMP_DIR/$label.err" >/dev/null; then
    echo "FAIL: $label did not report expected error: $expected" >&2
    cat "$TMP_DIR/$label.err" >&2
    exit 1
  fi
}

expect_invalid \
  "typed-occurrence-drift" \
  "occurrences must exactly preserve typed source items and evidence" \
  '.items[0].occurrences[0].item.evidence_strength = "proven"'
expect_invalid \
  "caveat-collapse" \
  "result must be conservative value pass_with_caveat" \
  '.items[0].result = "pass"'
expect_invalid \
  "missing-caveat-disposition" \
  "caveat_overrides must explicitly disposition every caveated source occurrence" \
  '.caveat_overrides = []'
expect_invalid \
  "claim-upgrade" \
  "max_claim_scope must not exceed weakest source claim source_correctness" \
  '.max_claim_scope = "release_gate"'
expect_invalid \
  "subject-identity-drift" \
  "subjects must exactly preserve every typed source subject occurrence" \
  '.subjects[0].subject.identity.commit = "forged"'
expect_invalid \
  "source-sha-drift" \
  "sha256 does not match results.json" \
  '.source_runs[0].sha256 = ("0" * 64)'
expect_invalid \
  "merged-go-with-weak-claim" \
  "release GO requires max_claim_scope release_gate" \
  '.release_readiness.verdict = "go"'
expect_invalid \
  "merged-go-with-skip" \
  "release GO cannot contain incomplete or non-pass items" \
  '.release_readiness.verdict = "go" | .items[0].result = "skip" | .summary = {total:1,passed:0,passed_unconditional:0,passed_with_caveat:0,passed_known_legacy_behavior:0,failed:0,blocked:0,partial:0,skipped:1,excluded:0,conflicts:0}'
expect_invalid \
  "merged-go-with-skipped-gate" \
  "release GO requires every merged gate to pass" \
  '.release_readiness.verdict = "go" | .gates[0].verdict = "skip"'

# A later supplemental run may explicitly close an older incomplete
# occurrence. Both occurrences remain preserved, but only the reviewed newer
# occurrence participates in the aggregate result.
mkdir -p "$TMP_DIR/merge/run-a-superseded"
cp "$TMP_DIR/merge/run-a/"*.json "$TMP_DIR/merge/run-a-superseded/"
cp "$TMP_DIR/merge/run-a/artifact.txt" "$TMP_DIR/merge/run-a-superseded/artifact.txt"
jq '
  .run_id = "run-a-superseded" |
  .finished_at = "2026-08-01T10:00:00+08:00" |
  .items[0].status = "blocked" |
  .items[0].reason = "environment unavailable in original run" |
  .items[0].test_kind = "runtime" |
  .items[0].claim_scope = "observation" |
  .items[0].assertion = {field:"terminal_verdict",value:"blocked"} |
  .max_claim_scope = "observation" |
  .summary = {
    total:1,passed:0,passed_unconditional:0,passed_with_caveat:0,
    passed_known_legacy_behavior:0,failed:0,blocked:1,skipped:0,
    excluded:0,pending:0,partial:0
  } |
  .max_claim_scope = "observation" |
  .gates[0].verdict = "blocked" |
  .gates[0].reason = "source gate was unavailable in original run" |
  .release_readiness = {verdict:"blocked",reason:"original environment was unavailable"}
' "$TMP_DIR/merge/run-a/results.json" >"$TMP_DIR/merge/run-a-superseded/results.json"
SUPERSEDED_SHA=$(shasum -a 256 "$TMP_DIR/merge/run-a-superseded/results.json" | awk '{print $1}')
jq --slurpfile old "$TMP_DIR/merge/run-a-superseded/results.json" \
   --arg old_sha "$SUPERSEDED_SHA" '
  .source_runs[0] = {
    run_id:"run-a-superseded",schema_version:4,version:"1.0.0",
    results_path:"run-a-superseded/results.json",sha256:$old_sha
  } |
  .subjects = (
    [.subjects[] | select(.source_run != "run-a")] +
    [$old[0].subjects[] | {source_run:"run-a-superseded",subject:.}]
  ) |
  .relations = (
    [.relations[] | select(.source_run != "run-a")] +
    [$old[0].relations[] | {source_run:"run-a-superseded",relation:.}]
  ) |
  .items[0].result = "pass" |
  .items[0].occurrences = [
    {source_run:"run-a-superseded",item:$old[0].items[0]},
    .items[0].occurrences[1]
  ] |
  .gates[0].verdict = "pass" |
  .gates[0].occurrences = [
    {source_run:"run-a-superseded",gate:$old[0].gates[0]},
    .gates[0].occurrences[1]
  ] |
  .summary = {
    total:1,passed:1,passed_unconditional:1,passed_with_caveat:0,
    passed_known_legacy_behavior:0,failed:0,blocked:0,partial:0,
    skipped:0,excluded:0,conflicts:0
  } |
  .max_claim_scope = "observation" |
  .caveat_overrides = [] |
  .release_readiness = {
    verdict:"blocked",
    reason:"one source gate remains blocked",
    source_verdicts:[
      {source_run:"run-a-superseded",verdict:"blocked",reason:"original environment was unavailable"},
      .release_readiness.source_verdicts[1]
    ]
  } |
  .supersessions = [{
    item_id:"SRC-UNIT.01",
    superseded_source_run:"run-a-superseded",
    authoritative_source_run:"run-b",
    approved_by:"independent-l2-fixture",
    approved_at:"2026-08-01T10:04:30+08:00",
    reason:"later direct evidence closes the original environment blocker"
  }] |
  .gate_supersessions = [{
    gate_id:"source-closure",
    superseded_source_run:"run-a-superseded",
    authoritative_source_run:"run-b",
    approved_by:"independent-l2-fixture",
    approved_at:"2026-08-01T10:04:30+08:00",
    reason:"later gate execution closes the original environment blocker"
  }]
' "$TMP_DIR/merge/merged-results.json" >"$TMP_DIR/merge/supplemental-supersession.json"
python3 "$VALIDATOR" "$TMP_DIR/merge/supplemental-supersession.json" >/dev/null
jq '
  .supersessions[0].superseded_source_run = "run-b" |
  .supersessions[0].authoritative_source_run = "run-a-superseded"
' "$TMP_DIR/merge/supplemental-supersession.json" \
  >"$TMP_DIR/merge/invalid-supersession-status.json"
if python3 "$VALIDATOR" "$TMP_DIR/merge/invalid-supersession-status.json" \
  >"$TMP_DIR/invalid-supersession-status.out" \
  2>"$TMP_DIR/invalid-supersession-status.err"; then
  echo "FAIL: invalid supersession status unexpectedly passed" >&2
  exit 1
fi
grep -F "can only supersede blocked/partial/pending/skip" \
  "$TMP_DIR/invalid-supersession-status.err" >/dev/null || {
  cat "$TMP_DIR/invalid-supersession-status.err" >&2
  exit 1
}

cp -R "$TMP_DIR/merge/run-b" "$TMP_DIR/merge/run-b-conflict"
jq '.items[0].assertion.value = 99' "$TMP_DIR/merge/run-b/results.json" \
  >"$TMP_DIR/merge/run-b-conflict/results.json"
CONFLICT_SHA=$(shasum -a 256 "$TMP_DIR/merge/run-b-conflict/results.json" | awk '{print $1}')
jq --slurpfile conflict "$TMP_DIR/merge/run-b-conflict/results.json" --arg sha "$CONFLICT_SHA" '
  .source_runs[1].results_path = "run-b-conflict/results.json" |
  .source_runs[1].sha256 = $sha |
  .items[0].occurrences[1].item = $conflict[0]
' "$TMP_DIR/merge/merged-results.json" >"$TMP_DIR/merge/semantic-conflict.json"
if python3 "$VALIDATOR" "$TMP_DIR/merge/semantic-conflict.json" \
  >"$TMP_DIR/semantic-conflict.out" 2>"$TMP_DIR/semantic-conflict.err"; then
  echo "FAIL: same item id with a different assertion unexpectedly passed" >&2
  exit 1
fi
grep -F "result must be conservative value conflict" "$TMP_DIR/semantic-conflict.err" >/dev/null || {
  cat "$TMP_DIR/semantic-conflict.err" >&2
  exit 1
}

echo "PASS: merged results v4 preserves typed evidence and conservative verdicts"

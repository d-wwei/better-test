#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VALIDATOR="$REPO_DIR/scripts/validate-results.sh"
TMP_DIR="$(mktemp -d)"
RESULTS_FILE="$TMP_DIR/results.json"
mkdir -p "$TMP_DIR/artifacts"
cp "$SCRIPT_DIR"/fixtures/artifacts/* "$TMP_DIR/artifacts/"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

expect_ok() {
  local fixture="$1"
  local output=""
  local rc=0

  cp "$fixture" "$RESULTS_FILE"
  output=$("$VALIDATOR" "$RESULTS_FILE") || rc=$?
  if [[ "$rc" -ne 0 || -n "$output" ]]; then
    echo "expected validation success for $fixture, got rc=$rc" >&2
    printf '%s\n' "$output" >&2
    exit 1
  fi
}

expect_fail_file() {
  local file="$1"
  local expected="$2"
  local output=""
  local rc=0

  output=$("$VALIDATOR" "$file") || rc=$?
  if [[ "$rc" -ne 2 ]]; then
    echo "expected validation rc=2 for $file, got rc=$rc" >&2
    printf '%s\n' "$output" >&2
    exit 1
  fi
  if ! printf '%s\n' "$output" | jq -e --arg expected "$expected" '
    .hookSpecificOutput.additionalContext | contains($expected)
  ' >/dev/null; then
    echo "validation failure for $file did not contain: $expected" >&2
    printf '%s\n' "$output" >&2
    exit 1
  fi
}

expect_fail_fixture() {
  local fixture="$1"
  local expected="$2"
  cp "$fixture" "$RESULTS_FILE"
  expect_fail_file "$RESULTS_FILE" "$expected"
}

expect_mutation_fail() {
  local base="$1"
  local filter="$2"
  local expected="$3"
  jq "$filter" "$base" > "$RESULTS_FILE"
  expect_fail_file "$RESULTS_FILE" "$expected"
}

# v1 remains compatible; v2 and v3 valid fixtures have no advisory output.
expect_ok "$SCRIPT_DIR/fixtures/results-v1-legacy-verdict.json"
expect_ok "$SCRIPT_DIR/fixtures/results-v2-valid.json"
expect_ok "$SCRIPT_DIR/fixtures/results-v3-valid.json"

# Evidence grading closes both weak-enum and false-confirmation paths.
expect_fail_fixture \
  "$SCRIPT_DIR/fixtures/results-v2-invalid-evidence.json" \
  "evidence_level 不支持"
expect_fail_fixture \
  "$SCRIPT_DIR/fixtures/results-v3-confirmed-single-source.json" \
  "至少两个不同 independence_key"
expect_mutation_fail \
  "$SCRIPT_DIR/fixtures/results-v3-valid.json" \
  '.items[0].evidence_level = "indirect"' \
  "pass/fail 时 evidence_level 不得为 indirect"
expect_mutation_fail \
  "$SCRIPT_DIR/fixtures/results-v3-valid.json" \
  '.items[0].evidence_level = "proven" | del(.items[0].proven_basis)' \
  "必须提供 proven_basis"
expect_mutation_fail \
  "$SCRIPT_DIR/fixtures/results-v3-valid.json" \
  '.items[0].evidence_level = "proven"
    | .items[0].evidence_sources[0].evidence_kind = "source"
    | .items[0].proven_basis = {
        kind: "source",
        evidence_refs: ["SRC-DAEMON-LOG-01"]
      }' \
  "必须提供 runtime_evidence_refs"
expect_mutation_fail \
  "$SCRIPT_DIR/fixtures/results-v3-valid.json" \
  '.items[0].evidence_level = "proven"
    | .items[0].evidence_sources[0].evidence_kind = "source"
    | .items[0].evidence_sources[1].evidence_kind = "runtime"
    | .items[0].evidence_sources[1].artifact_ref = "artifacts/daemon.log#runtime"
    | .items[0].proven_basis = {
        kind: "source",
        evidence_refs: ["SRC-DAEMON-LOG-01"],
        runtime_evidence_refs: ["SRC-CLIENT-JSON-01"]
      }' \
  "与 proven basis 文件不同的 runtime artifact"
jq '.items[0].evidence_level = "proven"
    | .items[0].evidence_sources[0].evidence_kind = "source"
    | .items[0].evidence_sources[1].evidence_kind = "runtime"
    | .items[0].proven_basis = {
        kind: "source",
        evidence_refs: ["SRC-DAEMON-LOG-01"],
        runtime_evidence_refs: ["SRC-CLIENT-JSON-01"]
      }' \
  "$SCRIPT_DIR/fixtures/results-v3-valid.json" >"$TMP_DIR/proven-source-valid.json"
expect_ok "$TMP_DIR/proven-source-valid.json"
jq '.items[0].evidence_level = "proven"
    | .items[0].evidence_sources[0].evidence_kind = "binary"
    | .items[0].evidence_sources[0].version = "1.0.0"
    | .items[0].evidence_sources[1].evidence_kind = "binary"
    | .items[0].evidence_sources[1].version = "1.1.0"
    | .items[0].evidence_sources += [{
        source_id: "SRC-RUNTIME-OBS-01",
        independence_key: "runtime-observation",
        artifact_ref: "artifacts/runtime-observation.json",
        evidence_kind: "runtime"
      }]
    | .items[0].proven_basis = {
        kind: "multi-version",
        evidence_refs: ["SRC-DAEMON-LOG-01", "SRC-CLIENT-JSON-01"],
        versions: ["1.0.0", "1.1.0"],
        runtime_evidence_refs: ["SRC-RUNTIME-OBS-01"]
      }' \
  "$SCRIPT_DIR/fixtures/results-v3-valid.json" >"$TMP_DIR/proven-multiversion-valid.json"
expect_ok "$TMP_DIR/proven-multiversion-valid.json"

# Five historically accepted malformed gate-ledger shapes now fail closed.
expect_mutation_fail \
  "$SCRIPT_DIR/fixtures/results-v2-valid.json" \
  '.gate_items = [{}]' \
  "缺少非空 gate_id"
expect_mutation_fail \
  "$SCRIPT_DIR/fixtures/results-v2-valid.json" \
  '.gate_items[0].verdict = "unknown"' \
  "verdict 不支持"
expect_mutation_fail \
  "$SCRIPT_DIR/fixtures/results-v2-valid.json" \
  '.items[0].status = "blocked" | .gate_items[0].verdict = "blocked" | del(.gate_items[0].reason)' \
  "缺少非空 reason"
expect_mutation_fail \
  "$SCRIPT_DIR/fixtures/results-v2-valid.json" \
  '.gate_items[0].item_ids = ["AUTH-MISSING-99"]' \
  "引用了不存在的 item"
expect_mutation_fail \
  "$SCRIPT_DIR/fixtures/results-v2-valid.json" \
  '.gate_items += [.gate_items[0]]' \
  "gate_id 重复"

# Verdict-to-item semantics are enforced for every gate verdict.
expect_mutation_fail \
  "$SCRIPT_DIR/fixtures/results-v2-valid.json" \
  '.items[0].status = "fail"' \
  "verdict=pass 只能引用 pass 类 item"
expect_mutation_fail \
  "$SCRIPT_DIR/fixtures/results-v2-valid.json" \
  '.gate_items[0].verdict = "fail"' \
  "verdict=fail 至少要引用"
expect_mutation_fail \
  "$SCRIPT_DIR/fixtures/results-v2-valid.json" \
  '.gate_items[0].verdict = "blocked"' \
  "verdict=blocked 至少要引用"
expect_mutation_fail \
  "$SCRIPT_DIR/fixtures/results-v2-valid.json" \
  '.gate_items[0].verdict = "skip"' \
  "verdict=skip 只能引用"

# v3 binds gate evidence, package-specific DoD, and the final GO decision.
expect_mutation_fail \
  "$SCRIPT_DIR/fixtures/results-v3-valid.json" \
  '.gate_items[0].evidence_refs = ["SRC-NOT-FOUND"]' \
  "不存在的 evidence source"
expect_mutation_fail \
  "$SCRIPT_DIR/fixtures/results-v3-valid.json" \
  '.dod.check_results |= map(select(.check_id != "smoke"))' \
  "缺少 required check: smoke"
expect_mutation_fail \
  "$SCRIPT_DIR/fixtures/results-v3-valid.json" \
  '.items[0].status = "blocked"
    | .items[0].evidence_level = "direct"
    | .gate_items[0].verdict = "blocked"
    | .gate_items[0].reason = "The environment blocked the assertion."' \
  "release_readiness=go 不允许 gate"
expect_mutation_fail \
  "$SCRIPT_DIR/fixtures/results-v3-valid.json" \
  '.items[0].status = "skip"
    | .items[0].evidence_level = "direct"
    | .items[0].skip_reason = "Explicitly excluded by scope."
    | .gate_items[0].verdict = "skip"
    | .gate_items[0].reason = "Explicitly excluded by scope."
    | del(.release_readiness.override)' \
  "skip/excluded/caveat"

# Empty runs, fake counters and fake coverage cannot form a release decision.
expect_mutation_fail \
  "$SCRIPT_DIR/fixtures/results-v3-valid.json" \
  '.items = []
    | .gate_items = []
    | .summary = {
        total: 0, passed: 0, failed: 0, blocked: 0,
        skipped: 0, excluded: 0, pending: 0, partial: 0
      }
    | .coverage = {
        manifest_total: 0, unreachable: 0, reachable: 0,
        tested: 0, reachable_coverage_pct: 0
      }' \
  "items 不得为空"
expect_mutation_fail \
  "$SCRIPT_DIR/fixtures/results-v3-valid.json" \
  '.coverage = {}' \
  "coverage.manifest_total 必须是非负整数"
expect_mutation_fail \
  "$SCRIPT_DIR/fixtures/results-v3-valid.json" \
  '.coverage.tested = 0 | .coverage.reachable_coverage_pct = 100' \
  "tested/reachable 计算不一致"
expect_mutation_fail \
  "$SCRIPT_DIR/fixtures/results-v3-valid.json" \
  '.coverage.manifest_total = 2
    | .coverage.reachable = 2
    | .coverage.tested = 1
    | .coverage.reachable_coverage_pct = 50
    | del(.release_readiness.override)' \
  "未覆盖 reachable"
jq '.coverage.manifest_total = 2
    | .coverage.reachable = 2
    | .coverage.tested = 1
    | .coverage.reachable_coverage_pct = 50
    | .release_readiness.override = {
        approved_by: "release-owner",
        approved_at: "2026-07-24T12:06:00+08:00",
        reason: "The release owner explicitly accepted the scoped coverage gap."
      }' \
  "$SCRIPT_DIR/fixtures/results-v3-valid.json" >"$TMP_DIR/coverage-override-valid.json"
expect_ok "$TMP_DIR/coverage-override-valid.json"
expect_mutation_fail \
  "$SCRIPT_DIR/fixtures/results-v3-valid.json" \
  '.summary.passed = 999 | .summary.failed = -3' \
  "summary.passed=999 与 items 实际计数"
expect_fail_fixture \
  "$SCRIPT_DIR/fixtures/results-v3-nonfinite.json" \
  "JSON 无法解析或文件为空"

# Identity, timestamps and evidence bindings are normalized before grading.
expect_mutation_fail \
  "$SCRIPT_DIR/fixtures/results-v3-valid.json" \
  '.schema_version = "3"' \
  "schema_version 必须是整数 2 或 3"
expect_mutation_fail \
  "$SCRIPT_DIR/fixtures/results-v3-valid.json" \
  '.environment.machine_id = "   "' \
  "environment.machine_id"
expect_mutation_fail \
  "$SCRIPT_DIR/fixtures/results-v3-valid.json" \
  '.started_at = "yesterday"' \
  "started_at 必须是带时区"
expect_mutation_fail \
  "$SCRIPT_DIR/fixtures/results-v3-valid.json" \
  '.items[0].evidence_sources[0].artifact_ref = "artifacts/missing.log"' \
  "artifact 文件不存在"
expect_mutation_fail \
  "$SCRIPT_DIR/fixtures/results-v3-valid.json" \
  '.items[0].evidence_sources[0].artifact_ref = "artifacts/daemon.log#one"
    | .items[0].evidence_sources[1].artifact_ref = "artifacts/daemon.log#two"' \
  "至少两个不同的本地 artifact 文件"
expect_mutation_fail \
  "$SCRIPT_DIR/fixtures/results-v3-valid.json" \
  '.items[0].evidence_sources[0].artifact_ref = "/etc/hosts"
    | .items[0].evidence_sources[1].artifact_ref = "/etc/passwd"' \
  "artifact 必须位于本 run 目录内"
expect_mutation_fail \
  "$SCRIPT_DIR/fixtures/results-v3-valid.json" \
  '.items[0].evidence_sources[1].independence_key =
      (.items[0].evidence_sources[0].independence_key + " ")
    | .items[0].evidence_sources[1].artifact_ref =
      (.items[0].evidence_sources[0].artifact_ref + " ")' \
  "至少两个不同 independence_key"
expect_mutation_fail \
  "$SCRIPT_DIR/fixtures/results-v3-valid.json" \
  '.items += [
      (.items[0]
        | .id = "AUTH-READY-02"
        | .evidence_level = "direct"
        | .evidence_sources = [{
            source_id: "SRC-SECOND-ITEM-01",
            independence_key: "second-item",
            artifact_ref: "artifacts/second-item.json"
          }])
    ]
    | .summary.total = 2
    | .summary.passed = 2
    | .coverage.manifest_total = 2
    | .coverage.reachable = 2
    | .coverage.tested = 2
    | .gate_items[0].evidence_refs = ["SRC-SECOND-ITEM-01"]' \
  "不属于该 gate 的 item_ids"

python3 - "$SCRIPT_DIR/fixtures/results-v3-valid.json" "$RESULTS_FILE" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")
text = text.replace(
    '  "version": "1.1.0",',
    '  "version": "1.1.0",\n  "version": "duplicate",',
    1,
)
Path(sys.argv[2]).write_text(text, encoding="utf-8")
PY
expect_fail_file "$RESULTS_FILE" "duplicate JSON key: version"

# DoD and GO must close semantics, not just contain the right labels.
expect_mutation_fail \
  "$SCRIPT_DIR/fixtures/results-v3-valid.json" \
  '.dod.check_results += [{
      check_id: "extra-review",
      verdict: "fail",
      reason: "The extra review failed.",
      item_ids: ["AUTH-READY-01"],
      gate_ids: []
    }]' \
  "所有 DoD check 都必须 pass"
expect_mutation_fail \
  "$SCRIPT_DIR/fixtures/results-v3-valid.json" \
  '.dod.check_results[] |= (.item_ids = [] | .gate_ids = [] | .evidence_refs = [])' \
  "必须至少引用一个 item、gate 或 evidence source"
expect_mutation_fail \
  "$SCRIPT_DIR/fixtures/results-v3-valid.json" \
  '.items[0].type = "metadata"
    | .items[0].evidence_level = "binary"' \
  "smoke 必须引用至少一个 direct+ 的 functional pass item"
expect_mutation_fail \
  "$SCRIPT_DIR/fixtures/results-v3-valid.json" \
  '.items[0].status = "skip"
    | .items[0].skip_reason = "No applicable runtime route."
    | .items[0].evidence_level = "direct"
    | .summary.passed = 0
    | .summary.skipped = 1
    | .gate_items = []
    | del(.release_readiness.override)' \
  "至少需要一个 pass 类 item"
expect_mutation_fail \
  "$SCRIPT_DIR/fixtures/results-v3-valid.json" \
  '.items[0].status = "pass_with_caveat"
    | .items[0].caveat_reason = "One non-critical branch remains."
    | del(.release_readiness.override)' \
  "skip/excluded/caveat"
expect_mutation_fail \
  "$SCRIPT_DIR/fixtures/results-v3-valid.json" \
  '.items[0].status = "pass_with_caveat"
    | .items[0].caveat_reason = "One branch remains."
    | .release_readiness.override = {
        approved_by: " fake ",
        approved_at: "2026-99-99T99:99:99+99:99",
        reason: " x "
      }' \
  "override.approved_by 必须是无首尾空白"
expect_mutation_fail \
  "$SCRIPT_DIR/fixtures/results-v3-valid.json" \
  '.items[0].status = "pass_with_caveat"
    | .items[0].caveat_reason = "One branch remains."
    | .release_readiness.override = {
        approved_by: "release-owner",
        approved_at: "2026-99-99T99:99:99+99:99",
        reason: "Approved with a documented residual caveat."
      }' \
  "override.approved_at 不是有效的 ISO 8601"

# Gate applicability is explicit: required ledgers close fully; truly gate-less
# projects remain valid when they declare why no gate exists.
expect_mutation_fail \
  "$SCRIPT_DIR/fixtures/results-v3-valid.json" \
  '.gate_items = [] | .dod.check_results[].gate_ids = []' \
  "gate_applicability=required 时 gate_items 不得为空"
expect_mutation_fail \
  "$SCRIPT_DIR/fixtures/results-v3-valid.json" \
  '.items += [
      (.items[0]
        | .id = "AUTH-READY-02"
        | .evidence_level = "direct"
        | .evidence_sources = [{
            source_id: "SRC-SECOND-ITEM-01",
            independence_key: "second-item",
            artifact_ref: "artifacts/second-item.json"
          }])
    ]
    | .summary.total = 2
    | .summary.passed = 2
    | .coverage.manifest_total = 2
    | .coverage.reachable = 2
    | .coverage.tested = 2
    | .gate_items += [{
        gate_id: "GATE-AUTH-SECOND",
        verdict: "pass",
        reason: "The second applicable gate passed.",
        item_ids: ["AUTH-READY-02"],
        evidence_refs: ["SRC-SECOND-ITEM-01"]
      }]' \
  "必须覆盖 gate_items 中全部适用 gate"
jq '.gate_applicability = "none"
    | .gate_applicability_reason = "This project has no release or critical gates."
    | .gate_items = []
    | .dod.check_results[].gate_ids = []' \
  "$SCRIPT_DIR/fixtures/results-v3-valid.json" >"$TMP_DIR/gate-less-valid.json"
expect_ok "$TMP_DIR/gate-less-valid.json"

# Real timestamp parsing rejects chronology and impossible calendar values.
expect_mutation_fail \
  "$SCRIPT_DIR/fixtures/results-v3-valid.json" \
  '.finished_at = "2026-07-24T11:59:59+08:00"' \
  "finished_at 不得早于 started_at"
expect_mutation_fail \
  "$SCRIPT_DIR/fixtures/results-v3-valid.json" \
  '.started_at = "2026-99-99T99:99:99+99:99"' \
  "started_at 不是有效的 ISO 8601"
expect_mutation_fail \
  "$SCRIPT_DIR/fixtures/results-v3-valid.json" \
  '.tester_id = " codex-a3f2 "' \
  "tester_id 必须是无首尾空白"

echo "results schema v1/v2/v3 validation tests passed"

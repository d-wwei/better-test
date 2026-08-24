#!/usr/bin/env bash
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TMP_DIR="$(mktemp -d)"
export BETTER_TEST_TRUSTED_PROFILE="$ROOT_DIR/fixtures/providers/project-profile-valid.json"
trap 'rm -rf "$TMP_DIR"' EXIT

fail() {
  echo "hybrid testing fixture failed: $*" >&2
  exit 1
}

if git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  set +e
  git -C "$ROOT_DIR" ls-files scripts hooks | grep -E '(^|/)__pycache__/|\.pyc$'
  guard_rc=$?
  set -e
  if [[ "$guard_rc" -eq 0 ]]; then
    fail "tracked Python bytecode is present in the distributable tree"
  elif [[ "$guard_rc" -ge 2 ]]; then
    fail "tracked Python bytecode guard failed (exit $guard_rc)"
  fi
elif find "$ROOT_DIR/scripts" "$ROOT_DIR/hooks" -type f -name '*.pyc' -print -quit | grep -q .; then
  fail "generated Python bytecode is present in the distributable snapshot"
fi

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

# Public schemas are strict JSON documents, independent of optional libraries.
python3 -m json.tool "$ROOT_DIR/schemas/project-profile.schema.json" >/dev/null
python3 -m json.tool "$ROOT_DIR/schemas/source-map.schema.json" >/dev/null
python3 -m json.tool "$ROOT_DIR/schemas/source-impact.schema.json" >/dev/null
python3 -m json.tool "$ROOT_DIR/schemas/results-v4.schema.json" >/dev/null
python3 -m json.tool "$ROOT_DIR/schemas/merged-results-v4.schema.json" >/dev/null

# The reusable layer must not absorb product-specific constants or operational
# examples from a project adapter/knowledge repository.
set +e
grep -r -n -i -E 'futu([^[:alnum:]]|$)|opend([^[:alnum:]]|$)|moomoo([^[:alnum:]]|$)|option_chain|窝轮|11111' \
  "$ROOT_DIR/SKILL.md" \
  "$ROOT_DIR/protocol-base.md" \
  "$ROOT_DIR/README.md" \
  "$ROOT_DIR/README.zh-CN.md" \
  "$ROOT_DIR"/references/*-workflow.md \
  "$ROOT_DIR/references/methodologies/design-rationale.md" \
  "$ROOT_DIR/references/templates.md" \
  "$ROOT_DIR/references/procedures" \
  "$ROOT_DIR/scripts/hybrid_core.py" \
  "$ROOT_DIR/scripts/rust-cargo-provider.py" \
  "$ROOT_DIR/scripts/run-source-provider.py" \
  "$ROOT_DIR/scripts/resolve-hybrid-strategy.py" \
  "$ROOT_DIR/schemas" \
  "$ROOT_DIR/fixtures/generic-rust" \
  "$ROOT_DIR/fixtures/providers" \
  "$ROOT_DIR/fixtures/results-v4"
guard_rc=$?
set -e
if [[ "$guard_rc" -eq 0 ]]; then
  fail "generic layer contains project-specific operational knowledge"
elif [[ "$guard_rc" -ge 2 ]]; then
  fail "generic-layer knowledge guard failed (exit $guard_rc)"
fi

python3 "$ROOT_DIR/scripts/validate-provider-output.py" \
  project-profile "$ROOT_DIR/fixtures/providers/project-profile-valid.json" >/dev/null
jq '.unexpected = true' "$ROOT_DIR/fixtures/providers/project-profile-valid.json" \
  >"$TMP_DIR/project-profile-unexpected.json"
expect_fail "additional property unexpected" python3 "$ROOT_DIR/scripts/validate-provider-output.py" \
  project-profile "$TMP_DIR/project-profile-unexpected.json"
python3 "$ROOT_DIR/scripts/validate-provider-output.py" \
  capabilities "$ROOT_DIR/fixtures/providers/capabilities-valid.json" >/dev/null
expect_fail "secret-like" python3 "$ROOT_DIR/scripts/validate-provider-output.py" \
  project-profile "$ROOT_DIR/fixtures/providers/project-profile-invalid-secret.json"

# Results v4 enforces typed identity, claim bounds, and run-local evidence.
python3 "$ROOT_DIR/scripts/validate-results-v4.py" \
  "$ROOT_DIR/fixtures/results-v4/results.json" >/dev/null
"$ROOT_DIR/scripts/validate-results.sh" \
  "$ROOT_DIR/fixtures/results-v4/results.json" >/dev/null
mkdir -p "$TMP_DIR/results"
cp "$ROOT_DIR/fixtures/results-v4/artifact.txt" "$TMP_DIR/results/artifact.txt"
cp "$ROOT_DIR/fixtures/results-v4/project-profile.json" "$TMP_DIR/results/project-profile.json"
cp "$ROOT_DIR/fixtures/results-v4/capabilities.json" "$TMP_DIR/results/capabilities.json"
cp "$ROOT_DIR/fixtures/results-v4/strategy.json" "$TMP_DIR/results/strategy.json"
cp "$ROOT_DIR/fixtures/results-v4/source-map.json" "$TMP_DIR/results/source-map.json"
cp "$ROOT_DIR/fixtures/results-v4/source-impact.json" "$TMP_DIR/results/source-impact.json"
jq '.input_refs = null' "$ROOT_DIR/fixtures/results-v4/results.json" \
  >"$TMP_DIR/results/results.json"
expect_fail "non-legacy results require hash-bound input_refs" \
  python3 "$ROOT_DIR/scripts/validate-results-v4.py" "$TMP_DIR/results/results.json"
jq '.input_refs.project_profile.sha256 = ("0"*64)' \
  "$ROOT_DIR/fixtures/results-v4/results.json" >"$TMP_DIR/results/results.json"
expect_fail "input_refs.project_profile sha256 does not match artifact" \
  python3 "$ROOT_DIR/scripts/validate-results-v4.py" "$TMP_DIR/results/results.json"
jq '.project_id = "self-signed-attacker"' \
  "$ROOT_DIR/fixtures/results-v4/project-profile.json" \
  >"$TMP_DIR/results/attacker-profile.json"
ATTACKER_PROFILE_SHA=$(shasum -a 256 "$TMP_DIR/results/attacker-profile.json" | awk '{print $1}')
jq --arg sha "$ATTACKER_PROFILE_SHA" '
  .input_refs.project_profile = {artifact_ref:"attacker-profile.json",sha256:$sha}
' "$ROOT_DIR/fixtures/results-v4/results.json" >"$TMP_DIR/results/results.json"
expect_fail "input project_profile differs from external trusted profile" \
  python3 "$ROOT_DIR/scripts/validate-results-v4.py" "$TMP_DIR/results/results.json"
jq '.provider.id = "attacker.fake"' "$ROOT_DIR/fixtures/results-v4/capabilities.json" \
  >"$TMP_DIR/results/attacker-capabilities.json"
ATTACKER_CAPABILITIES_SHA=$(shasum -a 256 "$TMP_DIR/results/attacker-capabilities.json" | awk '{print $1}')
jq --arg sha "$ATTACKER_CAPABILITIES_SHA" '
  .input_refs.capabilities = {artifact_ref:"attacker-capabilities.json",sha256:$sha}
' "$ROOT_DIR/fixtures/results-v4/results.json" >"$TMP_DIR/results/results.json"
expect_fail "capabilities provider is not declared by project profile" \
  python3 "$ROOT_DIR/scripts/validate-results-v4.py" "$TMP_DIR/results/results.json"
jq '.mode = "blackbox"' "$ROOT_DIR/fixtures/results-v4/strategy.json" \
  >"$TMP_DIR/results/blackbox-strategy.json"
BLACKBOX_STRATEGY_SHA=$(shasum -a 256 "$TMP_DIR/results/blackbox-strategy.json" | awk '{print $1}')
jq --arg sha "$BLACKBOX_STRATEGY_SHA" '
  .mode = "blackbox" |
  .input_refs.strategy = {artifact_ref:"blackbox-strategy.json",sha256:$sha}
' "$ROOT_DIR/fixtures/results-v4/results.json" >"$TMP_DIR/results/results.json"
expect_fail "strategy mode differs from capability-derived mode" \
  python3 "$ROOT_DIR/scripts/validate-results-v4.py" "$TMP_DIR/results/results.json"
jq '.provider.id = "attacker.fake"' "$ROOT_DIR/fixtures/results-v4/source-map.json" \
  >"$TMP_DIR/results/attacker-source-map.json"
ATTACKER_MAP_SHA=$(shasum -a 256 "$TMP_DIR/results/attacker-source-map.json" | awk '{print $1}')
jq --arg sha "$ATTACKER_MAP_SHA" '
  .input_refs.source_map = {artifact_ref:"attacker-source-map.json",sha256:$sha}
' "$ROOT_DIR/fixtures/results-v4/results.json" >"$TMP_DIR/results/results.json"
expect_fail "source map provider differs from capabilities provider" \
  python3 "$ROOT_DIR/scripts/validate-results-v4.py" "$TMP_DIR/results/results.json"
jq '.schema_version = 99' "$ROOT_DIR/fixtures/results-v4/source-map.json" \
  >"$TMP_DIR/results/malformed-source-map.json"
MALFORMED_MAP_SHA=$(shasum -a 256 "$TMP_DIR/results/malformed-source-map.json" | awk '{print $1}')
jq --arg sha "$MALFORMED_MAP_SHA" '
  .input_refs.source_map = {artifact_ref:"malformed-source-map.json",sha256:$sha}
' "$ROOT_DIR/fixtures/results-v4/results.json" >"$TMP_DIR/results/results.json"
expect_fail "input source_map: source map schema_version must be integer 1" \
  python3 "$ROOT_DIR/scripts/validate-results-v4.py" "$TMP_DIR/results/results.json"
jq '.selections.excluded = [] |
  .selections.required = [{id:"must-run-blackbox",kind:"integration",reason:"adversarial required selection",unit_ids:[],risk_ids:[]}]' \
  "$ROOT_DIR/fixtures/results-v4/source-impact.json" >"$TMP_DIR/results/required-source-impact.json"
REQUIRED_IMPACT_SHA=$(shasum -a 256 "$TMP_DIR/results/required-source-impact.json" | awk '{print $1}')
jq --arg sha "$REQUIRED_IMPACT_SHA" '
  .input_refs.source_impact = {artifact_ref:"required-source-impact.json",sha256:$sha} |
  .source_impact_ref = .input_refs.source_impact
' "$ROOT_DIR/fixtures/results-v4/results.json" >"$TMP_DIR/results/results.json"
expect_fail "required source-impact selections lack closed result items: must-run-blackbox" \
  python3 "$ROOT_DIR/scripts/validate-results-v4.py" "$TMP_DIR/results/results.json"
jq '.coverage_by_lane |= with_entries(.value = {
  numerator:0,denominator:0,pct:0,subject_refs:["source:fixture"],tool:"not run",
  disposition:"not_applicable",item_refs:[],evidence_refs:[],reason:"unsafe empty lane"
})' "$ROOT_DIR/fixtures/results-v4/results.json" >"$TMP_DIR/results/results.json"
expect_fail "strategy required lane is not measured" \
  python3 "$ROOT_DIR/scripts/validate-results-v4.py" "$TMP_DIR/results/results.json"
jq '
  .items += [(.items[0] |
    .id = "SRC-UNIT.02" |
    .evidence_sources[0].id = "EVIDENCE.UNRELATED-02")] |
  .summary.total = 2 | .summary.passed = 2 |
  .coverage_by_lane.surface.evidence_refs = ["EVIDENCE.UNRELATED-02"]
' "$ROOT_DIR/fixtures/results-v4/results.json" >"$TMP_DIR/results/results.json"
expect_fail "coverage lane surface evidence_refs must belong to its item_refs" \
  python3 "$ROOT_DIR/scripts/validate-results-v4.py" "$TMP_DIR/results/results.json"
jq '.unexpected = true' \
  "$ROOT_DIR/fixtures/results-v4/results.json" >"$TMP_DIR/results/results.json"
expect_fail "additional property unexpected" python3 "$ROOT_DIR/scripts/validate-results-v4.py" \
  "$TMP_DIR/results/results.json"
perl -0pe 's/"pct": 100/"pct": NaN/' "$ROOT_DIR/fixtures/results-v4/results.json" \
  >"$TMP_DIR/results/results.json"
expect_fail "non-standard JSON constant: NaN" python3 "$ROOT_DIR/scripts/validate-results-v4.py" \
  "$TMP_DIR/results/results.json"
jq '.relations = [{type:"forged_chain",from:"source:fixture",to:"source:fixture",evidence_refs:["EV-FIXTURE-01"]}]' \
  "$ROOT_DIR/fixtures/results-v4/results.json" >"$TMP_DIR/results/results.json"
expect_fail "value is not in enum" python3 "$ROOT_DIR/scripts/validate-results-v4.py" \
  "$TMP_DIR/results/results.json"
jq '.mode = "banana"' "$ROOT_DIR/fixtures/results-v4/results.json" \
  >"$TMP_DIR/results/results.json"
expect_fail "schema $.mode: value is not in enum" python3 "$ROOT_DIR/scripts/validate-results-v4.py" \
  "$TMP_DIR/results/results.json"
jq '.objective = "self_declared_anything"' "$ROOT_DIR/fixtures/results-v4/results.json" \
  >"$TMP_DIR/results/results.json"
expect_fail "schema $.objective: value is not in enum" python3 "$ROOT_DIR/scripts/validate-results-v4.py" \
  "$TMP_DIR/results/results.json"
jq '.items[0].claim_scope = "production_release_approved"' \
  "$ROOT_DIR/fixtures/results-v4/results.json" >"$TMP_DIR/results/results.json"
expect_fail "unsupported claim_scope" python3 "$ROOT_DIR/scripts/validate-results-v4.py" \
  "$TMP_DIR/results/results.json"
jq '.max_claim_scope = "production_release_approved"' \
  "$ROOT_DIR/fixtures/results-v4/results.json" >"$TMP_DIR/results/results.json"
expect_fail "max_claim_scope is unsupported" python3 "$ROOT_DIR/scripts/validate-results-v4.py" \
  "$TMP_DIR/results/results.json"
jq '.items[0].evidence_strength = "confirmed"' \
  "$ROOT_DIR/fixtures/results-v4/results.json" >"$TMP_DIR/results/results.json"
expect_fail "confirmed evidence requires two independent keys and files" \
  python3 "$ROOT_DIR/scripts/validate-results-v4.py" "$TMP_DIR/results/results.json"
cp "$ROOT_DIR/fixtures/results-v4/artifact.txt" "$TMP_DIR/results/artifact-2.txt"
jq '.items[0].evidence_strength = "proven" |
    .items[0].evidence_sources += [{id:"EV-FIXTURE-02",independence_key:"runtime-oracle",artifact_ref:"artifact-2.txt",kind:"runtime"}]' \
  "$ROOT_DIR/fixtures/results-v4/results.json" >"$TMP_DIR/results/results.json"
expect_fail "missing required property proven_basis" \
  python3 "$ROOT_DIR/scripts/validate-results-v4.py" "$TMP_DIR/results/results.json"
jq '.items[0].evidence_strength = "confirmed" |
    .items[0].evidence_sources += [{id:"EV-FIXTURE-02",independence_key:"runtime-oracle",artifact_ref:"artifact-2.txt",kind:"runtime"}]' \
  "$ROOT_DIR/fixtures/results-v4/results.json" >"$TMP_DIR/results/results.json"
expect_fail "confirmed evidence requires artifact sha256" \
  python3 "$ROOT_DIR/scripts/validate-results-v4.py" "$TMP_DIR/results/results.json"
jq '.items[0].claim_scope = "release_gate"' \
  "$ROOT_DIR/fixtures/results-v4/results.json" >"$TMP_DIR/results/results.json"
expect_fail "source-only test" python3 "$ROOT_DIR/scripts/validate-results-v4.py" \
  "$TMP_DIR/results/results.json"
jq '.subjects[0].identity.dirty = true' \
  "$ROOT_DIR/fixtures/results-v4/results.json" >"$TMP_DIR/results/results.json"
expect_fail "worktree_fingerprint" python3 "$ROOT_DIR/scripts/validate-results-v4.py" \
  "$TMP_DIR/results/results.json"
jq '.release_readiness = {verdict:"go", reason:"unsafe projection"}' \
  "$ROOT_DIR/fixtures/results-v4/results.json" >"$TMP_DIR/results/results.json"
expect_fail "release GO requires" python3 "$ROOT_DIR/scripts/validate-results-v4.py" \
  "$TMP_DIR/results/results.json"
jq '
  .subjects += [{id:"process:unrelated",type:"process",identity:{pid:123,executable_sha256:("c"*64),started_at:"2026-07-24T12:00:00+08:00"}}] |
  .items[0].evidence_strength = "proven" |
  .items[0].evidence_sources[0].sha256 = ("0"*64) |
  .items[0].evidence_sources += [{id:"EV-FIXTURE-02",independence_key:"runtime-oracle",artifact_ref:"artifact-2.txt",kind:"runtime",sha256:("0"*64)}] |
  .items[0].proven_basis = {proof_kind:"independent_runtime_chain",statement:"unrelated runtime",verifier:"fixture",runtime_subject_refs:["process:unrelated"]}
' "$ROOT_DIR/fixtures/results-v4/results.json" >"$TMP_DIR/results/results.json"
expect_fail "runtime subjects must belong to item subject_refs" \
  python3 "$ROOT_DIR/scripts/validate-results-v4.py" "$TMP_DIR/results/results.json"
jq '
  .items[0].status = "pending" |
  .items[0].assertion = {field:null,value:null} |
  .summary.passed = 0 | .summary.pending = 1 |
  .gates[0].verdict = "skip" |
  .release_readiness = {verdict:"go",reason:"unsafe incomplete release"}
' "$ROOT_DIR/fixtures/results-v4/results.json" >"$TMP_DIR/results/results.json"
expect_fail "release GO cannot contain skipped, excluded, pending, or partial items" \
  python3 "$ROOT_DIR/scripts/validate-results-v4.py" "$TMP_DIR/results/results.json"
jq '
  .subjects += [{id:"process:unrelated",type:"process",identity:{pid:123,executable_sha256:("c"*64),started_at:"2026-07-24T12:00:00+08:00"}}] |
  .max_claim_scope = "release_gate" |
  .release_readiness = {verdict:"go",reason:"unsafe unrelated process"}
' "$ROOT_DIR/fixtures/results-v4/results.json" >"$TMP_DIR/results/results.json"
expect_fail "passed runtime-claim item bound to a passed gate" \
  python3 "$ROOT_DIR/scripts/validate-results-v4.py" "$TMP_DIR/results/results.json"
jq '.subjects += [{id:"process:unrelated",type:"process",identity:{pid:123,executable_sha256:("c"*64),started_at:"2026-08-01T10:00:00+08:00"}}] |
    .max_claim_scope = "release_gate"' \
  "$ROOT_DIR/fixtures/results-v4/results.json" >"$TMP_DIR/results/results.json"
expect_fail "exceeds passed evidence claim ceiling" \
  python3 "$ROOT_DIR/scripts/validate-results-v4.py" "$TMP_DIR/results/results.json"
jq '.gates[0].item_ids = [] | .gates[0].evidence_refs = [] | del(.gates[0].required_subject_types)' \
  "$ROOT_DIR/fixtures/results-v4/results.json" >"$TMP_DIR/results/results.json"
expect_fail "missing required property required_subject_types" \
  python3 "$ROOT_DIR/scripts/validate-results-v4.py" "$TMP_DIR/results/results.json"
jq '.items[0].status = "fail" | .summary.passed = 0 | .summary.failed = 1' \
  "$ROOT_DIR/fixtures/results-v4/results.json" >"$TMP_DIR/results/results.json"
expect_fail "cannot reference non-pass items" \
  python3 "$ROOT_DIR/scripts/validate-results-v4.py" "$TMP_DIR/results/results.json"

# Release GO needs a mode-appropriate, hash-anchored candidate identity chain.
printf 'candidate executable\n' >"$TMP_DIR/results/candidate.bin"
printf '{"pid":123,"ready":true,"probe":"health"}\n' >"$TMP_DIR/results/runtime-transcript.json"
cat >"$TMP_DIR/results/release-capabilities.json" <<'JSON'
{
  "provider": {"id": "fixture.release", "version": "1.0.0", "implementation_sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},
  "capabilities": [
    {"name":"source-map","status":"unavailable","evidence":"black-box release provider"},
    {"name":"source-impact","status":"unavailable","evidence":"black-box release provider"},
    {"name":"artifact-identity","status":"available","evidence":"candidate hash"},
    {"name":"process-identity","status":"available","evidence":"executable hash"},
    {"name":"runtime-probe","status":"available","evidence":"runtime transcript"},
    {"name":"session-readiness","status":"available","evidence":"not required by process-only fixture"},
    {"name":"typed-subject-identity","status":"available","evidence":"typed v4 subjects"}
  ]
}
JSON
cat >"$TMP_DIR/results/release-project-profile.json" <<'JSON'
{
  "schema_version":1,
  "contract_version":"1.0.0",
  "project_id":"release-fixture",
  "result_versions":[4],
  "providers":[{
    "id":"fixture.release",
    "kind":"runtime",
    "command":["fixture-release-provider"],
    "capabilities":["artifact-identity","process-identity","runtime-probe","session-readiness","typed-subject-identity"],
    "trust":{
      "path_scope":["."],
      "version":"1.0.0",
      "sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      "dependencies":[],
      "source_access":"read-only",
      "network":"deny",
      "external_writes":"deny"
    }
  }],
  "evidence_policy":{
    "unknown_impact":"expand-safe-default",
    "safe_default_lanes":["surface","inventory","risk","invariant","selection"],
    "release_required_claim_scopes":["runtime_readiness","release_gate"],
    "mutation":{"required_for":[],"survivor_disposition_required":true}
  },
  "features":{"hybrid_testing":true,"results_v4":"default","dual_write":false}
}
JSON
cp "$TMP_DIR/results/release-project-profile.json" "$TMP_DIR/release-trusted-profile.json"
export BETTER_TEST_TRUSTED_PROFILE="$TMP_DIR/release-trusted-profile.json"
cat >"$TMP_DIR/results/release-strategy.json" <<'JSON'
{
  "schema_version":1,
  "objective":"release_decision",
  "normalized_objective":"release_decision",
  "mode":"blackbox",
  "max_claim_scope":"release_gate",
  "missing_capabilities":[],
  "required_lanes":["surface","inventory","code","diff","risk","invariant","selection"],
  "required_gates":["release-candidate"],
  "feature_flags":{"hybrid_testing":true,"results_v4":"default","dual_write":false},
  "mutation_required_for":[],
  "mutation_required":false,
  "mutation_triggers":[]
}
JSON
CANDIDATE_SHA=$(shasum -a 256 "$TMP_DIR/results/candidate.bin" | awk '{print $1}')
RUNTIME_SHA=$(shasum -a 256 "$TMP_DIR/results/runtime-transcript.json" | awk '{print $1}')
RELEASE_PROFILE_SHA=$(shasum -a 256 "$TMP_DIR/results/release-project-profile.json" | awk '{print $1}')
RELEASE_CAPABILITIES_SHA=$(shasum -a 256 "$TMP_DIR/results/release-capabilities.json" | awk '{print $1}')
RELEASE_STRATEGY_SHA=$(shasum -a 256 "$TMP_DIR/results/release-strategy.json" | awk '{print $1}')
jq --arg sha "$CANDIDATE_SHA" --arg runtime_sha "$RUNTIME_SHA" \
   --arg profile_sha "$RELEASE_PROFILE_SHA" --arg capabilities_sha "$RELEASE_CAPABILITIES_SHA" \
   --arg strategy_sha "$RELEASE_STRATEGY_SHA" '
  .mode = "blackbox" | .objective = "release_decision" |
  .subjects = [
    {id:"source:fixture",type:"source",identity:{vcs:"git",commit:"fixture",dirty:false}},
    {id:"build:fixture",type:"build",identity:{source_ref:"source:fixture",toolchain:"fixture",lock_sha256:("a"*64),features:[],profile:"release",output_sha256:$sha}},
    {id:"artifact:fixture",type:"artifact",identity:{sha256:$sha}},
    {id:"process:fixture",type:"process",identity:{pid:123,executable_sha256:$sha,started_at:"2026-08-01T10:00:00+08:00"}}
  ] |
  .items[0].test_kind = "runtime" |
  .items[0].subject_refs = ["source:fixture","build:fixture","artifact:fixture","process:fixture"] |
  .items[0].claim_scope = "release_gate" |
  .items[0].evidence_strength = "confirmed" |
  .items[0].evidence_sources = [
    {id:"EVIDENCE.CANDIDATE-01",independence_key:"candidate-hash",artifact_ref:"candidate.bin",kind:"artifact",sha256:$sha},
    {id:"EVIDENCE.RUNTIME-01",independence_key:"runtime-probe",artifact_ref:"runtime-transcript.json",kind:"runtime",sha256:$runtime_sha}
  ] |
  .coverage_by_lane |= with_entries(
    .value.item_refs = ["RUNTIME.READY"] |
    .value.evidence_refs = ["EVIDENCE.RUNTIME-02"] |
    .value.disposition = "measured"
  ) |
  .items += [{
    id:"RUNTIME.READY",name:"candidate runtime readiness",status:"pass",test_kind:"runtime",
    subject_refs:["source:fixture","build:fixture","artifact:fixture","process:fixture"],
    claim_scope:"runtime_readiness",evidence_strength:"confirmed",
    assertion:{field:"ready",value:true},selection_refs:[],bug_ids:[],
    evidence_sources:[
      {id:"EVIDENCE.CANDIDATE-02",independence_key:"candidate-hash-2",artifact_ref:"candidate.bin",kind:"artifact",sha256:$sha},
      {id:"EVIDENCE.RUNTIME-02",independence_key:"runtime-probe-2",artifact_ref:"runtime-transcript.json",kind:"runtime",sha256:$runtime_sha}
    ]
  }] |
  .summary.total = 2 | .summary.passed = 2 |
  .relations = [
    {type:"built_from",from:"build:fixture",to:"source:fixture",evidence_refs:["EVIDENCE.CANDIDATE-01"]},
    {type:"produced_by",from:"artifact:fixture",to:"build:fixture",evidence_refs:["EVIDENCE.CANDIDATE-01"]},
    {type:"launched_from",from:"process:fixture",to:"artifact:fixture",evidence_refs:["EVIDENCE.CANDIDATE-01"]}
  ] |
  .gates = [{id:"release-candidate",verdict:"pass",reason:"candidate chain closed",item_ids:["SRC-UNIT.01","RUNTIME.READY"],evidence_refs:["EVIDENCE.CANDIDATE-01","EVIDENCE.RUNTIME-01","EVIDENCE.CANDIDATE-02","EVIDENCE.RUNTIME-02"],required_subject_types:["source","build","artifact","process"]}] |
  .max_claim_scope = "release_gate" |
  .missing_capabilities = ["source-map","source-impact"] |
  .input_refs = {
    project_profile:{artifact_ref:"release-project-profile.json",sha256:$profile_sha},
    capabilities:{artifact_ref:"release-capabilities.json",sha256:$capabilities_sha},
    strategy:{artifact_ref:"release-strategy.json",sha256:$strategy_sha}
  } |
  .source_impact_ref = null |
  .release_readiness = {verdict:"go",reason:"candidate identity and runtime gate closed"}
' "$ROOT_DIR/fixtures/results-v4/results.json" >"$TMP_DIR/results/valid-release-go.json"
python3 "$ROOT_DIR/scripts/validate-results-v4.py" "$TMP_DIR/results/valid-release-go.json" >/dev/null
jq 'del(.items[1]) | .summary.total = 1 | .summary.passed = 1 |
  .gates[0].item_ids = ["SRC-UNIT.01"] |
  .gates[0].evidence_refs = ["EVIDENCE.CANDIDATE-01","EVIDENCE.RUNTIME-01"]' \
  "$TMP_DIR/results/valid-release-go.json" >"$TMP_DIR/results/results.json"
expect_fail "release GO lacks policy-required passed claim scopes: runtime_readiness" \
  python3 "$ROOT_DIR/scripts/validate-results-v4.py" "$TMP_DIR/results/results.json"
jq '.required_gates += ["impact-hard"]' "$TMP_DIR/results/release-strategy.json" \
  >"$TMP_DIR/results/release-strategy-hard.json"
RELEASE_STRATEGY_HARD_SHA=$(shasum -a 256 "$TMP_DIR/results/release-strategy-hard.json" | awk '{print $1}')
jq --arg sha "$RELEASE_STRATEGY_HARD_SHA" '
  .input_refs.strategy = {artifact_ref:"release-strategy-hard.json",sha256:$sha} |
  .gates += [{id:"impact-hard",verdict:"not_applicable",reason:"unsafe waiver",item_ids:[],evidence_refs:[],required_subject_types:[]}]
' "$TMP_DIR/results/valid-release-go.json" >"$TMP_DIR/results/results.json"
expect_fail "release GO requires every strategy required gate to pass" \
  python3 "$ROOT_DIR/scripts/validate-results-v4.py" "$TMP_DIR/results/results.json"
printf 'package archive\n' >"$TMP_DIR/results/package.bin"
printf 'different installed executable\n' >"$TMP_DIR/results/installed-other.bin"
PACKAGE_SHA=$(shasum -a 256 "$TMP_DIR/results/package.bin" | awk '{print $1}')
INSTALLED_OTHER_SHA=$(shasum -a 256 "$TMP_DIR/results/installed-other.bin" | awk '{print $1}')
jq --arg executable_sha "$CANDIDATE_SHA" --arg package_sha "$PACKAGE_SHA" '
  (.subjects[] | select(.type == "build").identity.output_sha256) = $package_sha |
  (.subjects[] | select(.type == "artifact").identity.sha256) = $package_sha |
  .subjects += [{id:"installation:fixture",type:"installation",identity:{install_id:"fixture",installed_executable_sha256:$executable_sha}}] |
  .items[0].subject_refs += ["installation:fixture"] |
  .items[1].subject_refs += ["installation:fixture"] |
  .items[0].evidence_sources += [{id:"EVIDENCE.PACKAGE-01",independence_key:"package-hash-1",artifact_ref:"package.bin",kind:"artifact",sha256:$package_sha}] |
  .items[1].evidence_sources += [{id:"EVIDENCE.PACKAGE-02",independence_key:"package-hash-2",artifact_ref:"package.bin",kind:"artifact",sha256:$package_sha}] |
  .relations = [
    {type:"built_from",from:"build:fixture",to:"source:fixture",evidence_refs:["EVIDENCE.PACKAGE-01"]},
    {type:"produced_by",from:"artifact:fixture",to:"build:fixture",evidence_refs:["EVIDENCE.PACKAGE-01"]},
    {type:"installed_from",from:"installation:fixture",to:"artifact:fixture",evidence_refs:["EVIDENCE.PACKAGE-01"]},
    {type:"launched_from",from:"process:fixture",to:"installation:fixture",evidence_refs:["EVIDENCE.CANDIDATE-01"]}
  ] |
  .gates[0].evidence_refs += ["EVIDENCE.PACKAGE-01","EVIDENCE.PACKAGE-02"] |
  .gates[0].required_subject_types += ["installation"]
' "$TMP_DIR/results/valid-release-go.json" >"$TMP_DIR/results/valid-install-release-go.json"
python3 "$ROOT_DIR/scripts/validate-results-v4.py" "$TMP_DIR/results/valid-install-release-go.json" >/dev/null
jq --arg installed_sha "$INSTALLED_OTHER_SHA" '
  (.subjects[] | select(.type == "installation").identity.installed_executable_sha256) = $installed_sha |
  .items[0].evidence_sources += [{id:"EVIDENCE.INSTALLED-OTHER-01",independence_key:"installed-other-1",artifact_ref:"installed-other.bin",kind:"artifact",sha256:$installed_sha}] |
  .items[1].evidence_sources += [{id:"EVIDENCE.INSTALLED-OTHER-02",independence_key:"installed-other-2",artifact_ref:"installed-other.bin",kind:"artifact",sha256:$installed_sha}] |
  .gates[0].evidence_refs += ["EVIDENCE.INSTALLED-OTHER-01","EVIDENCE.INSTALLED-OTHER-02"]
' "$TMP_DIR/results/valid-install-release-go.json" >"$TMP_DIR/results/results.json"
expect_fail "candidate identity chain from runtime through artifact/build to source" \
  python3 "$ROOT_DIR/scripts/validate-results-v4.py" "$TMP_DIR/results/results.json"
jq '.objective = "source_change"' "$TMP_DIR/results/valid-release-go.json" \
  >"$TMP_DIR/results/results.json"
expect_fail "release GO requires objective release_decision" \
  python3 "$ROOT_DIR/scripts/validate-results-v4.py" "$TMP_DIR/results/results.json"
jq '.missing_capabilities = ["runtime-probe","artifact-identity","process-identity","session-readiness"]' \
  "$TMP_DIR/results/valid-release-go.json" >"$TMP_DIR/results/results.json"
expect_fail "release GO cannot declare missing release capabilities" \
  python3 "$ROOT_DIR/scripts/validate-results-v4.py" "$TMP_DIR/results/results.json"
jq '.subjects[] |= if .type == "artifact" then .identity.sha256 = ("d"*64) else . end' \
  "$TMP_DIR/results/valid-release-go.json" >"$TMP_DIR/results/results.json"
expect_fail "identity sha256 lacks matching evidence" \
  python3 "$ROOT_DIR/scripts/validate-results-v4.py" "$TMP_DIR/results/results.json"
jq '.items[0].test_kind = "integration" | .items[0].evidence_sources[1].kind = "source-test"' \
  "$TMP_DIR/results/valid-release-go.json" >"$TMP_DIR/results/results.json"
expect_fail "requires runtime evidence" \
  python3 "$ROOT_DIR/scripts/validate-results-v4.py" "$TMP_DIR/results/results.json"
cp "$TMP_DIR/results/candidate.bin" "$TMP_DIR/results/candidate-copy.bin"
jq --arg sha "$CANDIDATE_SHA" '
  .items[0].evidence_sources[1].artifact_ref = "candidate-copy.bin" |
  .items[0].evidence_sources[1].sha256 = $sha
' "$TMP_DIR/results/valid-release-go.json" >"$TMP_DIR/results/results.json"
expect_fail "requires independently hashed runtime evidence" \
  python3 "$ROOT_DIR/scripts/validate-results-v4.py" "$TMP_DIR/results/results.json"
export BETTER_TEST_TRUSTED_PROFILE="$ROOT_DIR/fixtures/providers/project-profile-valid.json"
jq '.subjects += [{
      id:"build:fixture", type:"build",
      identity:{source_ref:"source:fixture",toolchain:"fixture",features:[],
                lock_sha256:("a"*64),profile:"test",output_sha256:("b"*64)}
    }] |
    .relations = [{type:"built_from",from:"build:fixture",to:"source:fixture",evidence_refs:[]}]' \
  "$ROOT_DIR/fixtures/results-v4/results.json" >"$TMP_DIR/results/results.json"
expect_fail "identity relation requires evidence_refs" python3 "$ROOT_DIR/scripts/validate-results-v4.py" \
  "$TMP_DIR/results/results.json"
jq '.subjects += [
      {id:"source:other",type:"source",identity:{commit:"other",dirty:false}},
      {id:"build:fixture",type:"build",identity:{source_ref:"source:fixture",toolchain:"fixture",features:[],lock_sha256:("a"*64),profile:"test",output_sha256:("b"*64)}}
    ] |
    .relations = [{type:"built_from",from:"build:fixture",to:"source:other",evidence_refs:["EVIDENCE.SRC-01"]}]' \
  "$ROOT_DIR/fixtures/results-v4/results.json" >"$TMP_DIR/results/results.json"
expect_fail "source_ref must match an exact built_from relation" \
  python3 "$ROOT_DIR/scripts/validate-results-v4.py" "$TMP_DIR/results/results.json"
jq '.subjects += [
      {id:"artifact:fixture",type:"artifact",identity:{sha256:("a"*64)}},
      {id:"installation:fixture",type:"installation",identity:{install_id:"fixture"}}
    ] |
    .relations = [{type:"installed_from",from:"installation:fixture",to:"artifact:fixture",evidence_refs:[]}]' \
  "$ROOT_DIR/fixtures/results-v4/results.json" >"$TMP_DIR/results/results.json"
expect_fail "identity relation requires evidence_refs" \
  python3 "$ROOT_DIR/scripts/validate-results-v4.py" "$TMP_DIR/results/results.json"
jq '.items[0].status = "blocked" | .items[0].reason = "fixture dependency unavailable"' \
  "$ROOT_DIR/fixtures/results-v4/results.json" >"$TMP_DIR/results/results.json"
expect_fail "summary.passed" python3 "$ROOT_DIR/scripts/validate-results-v4.py" \
  "$TMP_DIR/results/results.json"
jq '.items[0].subject_refs = ["source:dangling"]' \
  "$ROOT_DIR/fixtures/results-v4/results.json" >"$TMP_DIR/results/results.json"
expect_fail "references unknown subject" python3 "$ROOT_DIR/scripts/validate-results-v4.py" \
  "$TMP_DIR/results/results.json"
cp "$ROOT_DIR/fixtures/results-v4/results.json" "$TMP_DIR/results/results.json"
rm "$TMP_DIR/results/artifact.txt"
expect_fail "artifact is missing" python3 "$ROOT_DIR/scripts/validate-results-v4.py" \
  "$TMP_DIR/results/results.json"

# The generic adapter is tested against a neutral two-crate workspace.
cp -R "$ROOT_DIR/fixtures/generic-rust" "$TMP_DIR/rust-project"
git -C "$TMP_DIR/rust-project" init -q
git -C "$TMP_DIR/rust-project" config user.email fixture@example.invalid
git -C "$TMP_DIR/rust-project" config user.name fixture
cargo generate-lockfile --manifest-path "$TMP_DIR/rust-project/Cargo.toml" >/dev/null
git -C "$TMP_DIR/rust-project" add .
git -C "$TMP_DIR/rust-project" commit -qm initial
git -C "$TMP_DIR/rust-project" commit --allow-empty -qm second
python3 "$ROOT_DIR/scripts/rust-cargo-provider.py" inventory \
  --project-root "$TMP_DIR/rust-project" >"$TMP_DIR/source-map-1.json"
python3 "$ROOT_DIR/scripts/rust-cargo-provider.py" inventory \
  --project-root "$TMP_DIR/rust-project" >"$TMP_DIR/source-map-2.json"
cmp "$TMP_DIR/source-map-1.json" "$TMP_DIR/source-map-2.json" >/dev/null || \
  fail "source inventory is not deterministic"
python3 "$ROOT_DIR/scripts/validate-provider-output.py" \
  source-map "$TMP_DIR/source-map-1.json" >/dev/null
jq '.unexpected = true' "$TMP_DIR/source-map-1.json" >"$TMP_DIR/source-map-unexpected.json"
expect_fail "additional property unexpected" python3 "$ROOT_DIR/scripts/validate-provider-output.py" \
  source-map "$TMP_DIR/source-map-unexpected.json"
jq -e '
  ([.checks[].id] | index("cargo-fmt:workspace")) and
  ([.checks[].id] | index("cargo-check:workspace")) and
  ([.checks[].id] | index("cargo-clippy:workspace")) and
  ([.checks[].id] | index("cargo-test:workspace")) and
  ([.checks[].id] | index("cargo-llvm-cov:workspace")) and
  ([.units[] | select(.id == "cargo-package:fixture-core") | .provider_metadata.features[]] | index("alternate-answer"))
' "$TMP_DIR/source-map-1.json" >/dev/null || fail "Rust feature/check capability inventory is incomplete"

# Dirty source identity must bind staged, unstaged, and untracked state without
# reusing the clean identity/cache key.
git clone -q "$TMP_DIR/rust-project" "$TMP_DIR/dirty-rust-project"
printf '\n// staged fixture\n' >>"$TMP_DIR/dirty-rust-project/crates/core/src/lib.rs"
git -C "$TMP_DIR/dirty-rust-project" add crates/core/src/lib.rs
printf '\n// unstaged fixture\n' >>"$TMP_DIR/dirty-rust-project/crates/app/src/main.rs"
printf 'untracked fixture\n' >"$TMP_DIR/dirty-rust-project/untracked.txt"
python3 "$ROOT_DIR/scripts/rust-cargo-provider.py" inventory \
  --project-root "$TMP_DIR/dirty-rust-project" >"$TMP_DIR/dirty-source-map-1.json"
python3 "$ROOT_DIR/scripts/rust-cargo-provider.py" inventory \
  --project-root "$TMP_DIR/dirty-rust-project" >"$TMP_DIR/dirty-source-map-2.json"
jq -e '
  .source.identity.dirty == true and
  .source.identity.dirty_scope == ["staged", "unstaged", "untracked"] and
  (.source.identity.worktree_fingerprint | test("^[0-9a-f]{64}$"))
' "$TMP_DIR/dirty-source-map-1.json" >/dev/null || fail "dirty source scope/fingerprint is incomplete"
cmp "$TMP_DIR/dirty-source-map-1.json" "$TMP_DIR/dirty-source-map-2.json" >/dev/null || \
  fail "dirty source fingerprint is not deterministic"
python3 "$ROOT_DIR/scripts/rust-cargo-provider.py" impact \
  --project-root "$TMP_DIR/dirty-rust-project" \
  --source-map "$TMP_DIR/dirty-source-map-1.json" --base HEAD --head HEAD \
  >"$TMP_DIR/dirty-source-impact.json"
jq -e '
  ([.changed_units[].path] | index("crates/core/src/lib.rs")) and
  ([.changed_units[].path] | index("crates/app/src/main.rs")) and
  ([.changed_units[].path] | index("untracked.txt")) and
  (.confidence.level == "low")
' "$TMP_DIR/dirty-source-impact.json" >/dev/null || \
  fail "dirty impact omitted staged, unstaged, or untracked changes"
printf '\n// changed after map\n' >>"$TMP_DIR/dirty-rust-project/crates/core/src/lib.rs"
expect_fail "source map worktree_fingerprint does not match current worktree" \
  python3 "$ROOT_DIR/scripts/rust-cargo-provider.py" impact \
  --project-root "$TMP_DIR/dirty-rust-project" \
  --source-map "$TMP_DIR/dirty-source-map-1.json" --base HEAD --head HEAD
if [ "$(jq -r '.source.subject_id' "$TMP_DIR/source-map-1.json")" = \
     "$(jq -r '.source.subject_id' "$TMP_DIR/dirty-source-map-1.json")" ]; then
  fail "dirty and clean source identities collided"
fi
python3 "$ROOT_DIR/scripts/rust-cargo-provider.py" probe \
  --project-root "$TMP_DIR/rust-project" >"$TMP_DIR/capabilities.json"
python3 "$ROOT_DIR/scripts/validate-provider-output.py" \
  capabilities "$TMP_DIR/capabilities.json" >/dev/null
python3 "$ROOT_DIR/scripts/resolve-hybrid-strategy.py" \
  --objective bug_investigation \
  --capabilities "$TMP_DIR/capabilities.json" \
  --profile "$ROOT_DIR/fixtures/providers/project-profile-valid.json" \
  --output "$TMP_DIR/bug-investigation-strategy.json" >/dev/null
jq -e '
  .normalized_objective == "bug_investigation" and
  (.missing_capabilities | index("runtime-probe")) and
  .required_phases == ["reproduce", "localize", "rebuild", "reverify"] and
  .blocked_phases == ["reproduce", "reverify"] and
  .max_claim_scope == "source_correctness"
' "$TMP_DIR/bug-investigation-strategy.json" >/dev/null || fail "bug investigation silently lost reproduce/reverify"

# v3.1 stays schema_version=3 and binds every hybrid artifact by local hash.
mkdir -p "$TMP_DIR/v31/artifacts" "$TMP_DIR/v31/hybrid"
cp "$ROOT_DIR/hooks/fixtures/artifacts/"* "$TMP_DIR/v31/artifacts/"
cp "$TMP_DIR/source-map-1.json" "$TMP_DIR/v31/hybrid/source-map.json"
SOURCE_MAP_SHA=$(shasum -a 256 "$TMP_DIR/v31/hybrid/source-map.json" | awk '{print $1}')
jq --arg sha "$SOURCE_MAP_SHA" '.hybrid = {
  contract_version: "1.0.0",
  mode: "whitebox",
  objective: "source_change",
  max_claim_scope: "source_correctness",
  missing_capabilities: ["runtime-probe"],
  semantic_diff: "not_run",
  artifacts: {source_map: {artifact_ref: "hybrid/source-map.json", sha256: $sha}}
}' "$ROOT_DIR/hooks/fixtures/results-v3-valid.json" >"$TMP_DIR/v31/results.json"
"$ROOT_DIR/scripts/validate-results.sh" "$TMP_DIR/v31/results.json" >/dev/null
jq '.hybrid.artifacts.source_map.artifact_ref = "https://example.invalid/source-map.json"' \
  "$TMP_DIR/v31/results.json" >"$TMP_DIR/v31/invalid.json"
mv "$TMP_DIR/v31/invalid.json" "$TMP_DIR/v31/results.json"
expect_fail "本地 artifact" "$ROOT_DIR/scripts/validate-results.sh" "$TMP_DIR/v31/results.json"

python3 "$ROOT_DIR/scripts/rust-cargo-provider.py" impact \
  --project-root "$TMP_DIR/rust-project" \
  --source-map "$TMP_DIR/source-map-1.json" \
  --base HEAD --head HEAD \
  --changed-file crates/core/src/lib.rs >"$TMP_DIR/source-impact.json"
python3 "$ROOT_DIR/scripts/validate-provider-output.py" \
  source-impact "$TMP_DIR/source-impact.json" >/dev/null
jq 'del(.required_gates) | .unexpected = true' "$TMP_DIR/source-impact.json" \
  >"$TMP_DIR/source-impact-schema-invalid.json"
expect_fail "missing required property required_gates" \
  python3 "$ROOT_DIR/scripts/validate-provider-output.py" \
  source-impact "$TMP_DIR/source-impact-schema-invalid.json"
jq -e '.selections.required[].unit_ids | index("cargo-package:fixture-app")' \
  "$TMP_DIR/source-impact.json" >/dev/null || fail "reverse dependency was not selected"
jq '.selections = {required:[], recommended:[], excluded:[]}' \
  "$TMP_DIR/source-impact.json" >"$TMP_DIR/source-impact-empty.json"
expect_fail "at least one" python3 "$ROOT_DIR/scripts/validate-provider-output.py" \
  source-impact "$TMP_DIR/source-impact-empty.json"
jq '.selections.excluded = [.selections.required[0]]' \
  "$TMP_DIR/source-impact.json" >"$TMP_DIR/source-impact-duplicate-selection.json"
expect_fail "appears in both required and excluded" \
  python3 "$ROOT_DIR/scripts/validate-provider-output.py" \
  source-impact "$TMP_DIR/source-impact-duplicate-selection.json"
expect_fail "source map commit does not match impact head" \
  python3 "$ROOT_DIR/scripts/rust-cargo-provider.py" impact \
  --project-root "$TMP_DIR/rust-project" --source-map "$TMP_DIR/source-map-1.json" \
  --base HEAD~1 --head HEAD~1

python3 "$ROOT_DIR/scripts/rust-cargo-provider.py" impact \
  --project-root "$TMP_DIR/rust-project" \
  --source-map "$TMP_DIR/source-map-1.json" \
  --base HEAD --head HEAD --changed-file docs/unknown.md >"$TMP_DIR/source-impact-unknown.json"
jq -e '.confidence.level == "low" and .fallback_policy == "expand-safe-default" and (.selections.required | length > 0)' \
  "$TMP_DIR/source-impact-unknown.json" >/dev/null || fail "unknown change did not expand safely"

# The declaration-aware runner preserves the same validated provider output.
python3 "$ROOT_DIR/scripts/run-source-provider.py" \
  --profile "$ROOT_DIR/fixtures/providers/project-profile-valid.json" \
  --provider better-test.rust-cargo --operation inventory \
  --project-root "$TMP_DIR/rust-project" --better-test-root "$ROOT_DIR" \
  --output "$TMP_DIR/runner-source-map.json" \
  --metrics-output "$TMP_DIR/runner-inventory-metrics.json" >/dev/null
cmp "$TMP_DIR/source-map-1.json" "$TMP_DIR/runner-source-map.json" >/dev/null || \
  fail "runner changed deterministic provider output"
jq -e '
  .provider_id == "better-test.rust-cargo" and
  .operation == "inventory" and
  .execution_status == "accepted" and
  .duration_seconds >= 0 and
  .persistent_scratch == false and
  .cache_hit == false and
  .check_failure_count == 0
' "$TMP_DIR/runner-inventory-metrics.json" >/dev/null || fail "runner metrics sidecar invalid"
CARGO_MANIFEST_SHA=$(shasum -a 256 "$TMP_DIR/rust-project/Cargo.toml" | awk '{print $1}')
jq --arg sha "$CARGO_MANIFEST_SHA" '
  .providers[0].trust.dependencies += [{path:"Cargo.toml",sha256:$sha}]
' "$ROOT_DIR/fixtures/providers/project-profile-valid.json" >"$TMP_DIR/relative-dependency-profile.json"
(
  cd "$TMP_DIR"
  python3 "$ROOT_DIR/scripts/run-source-provider.py" \
    --profile "$TMP_DIR/relative-dependency-profile.json" \
    --provider better-test.rust-cargo --operation probe \
    --project-root "$TMP_DIR/rust-project" --better-test-root "$ROOT_DIR" \
    --output "$TMP_DIR/relative-dependency-probe.json" >/dev/null
) || fail "relative provider dependency was not resolved from project_root"
jq '.providers[0].trust.sha256 = ("0" * 64)' \
  "$ROOT_DIR/fixtures/providers/project-profile-valid.json" >"$TMP_DIR/hash-mismatch-profile.json"
expect_fail "hash mismatch" python3 "$ROOT_DIR/scripts/run-source-provider.py" \
  --profile "$TMP_DIR/hash-mismatch-profile.json" \
  --provider better-test.rust-cargo --operation inventory \
  --project-root "$TMP_DIR/rust-project" --better-test-root "$ROOT_DIR" \
  --output "$TMP_DIR/rejected.json"
cp -R "$TMP_DIR/rust-project" "$TMP_DIR/writer-project"
WRITER_SHA=$(shasum -a 256 "$ROOT_DIR/fixtures/providers/provider-writes-source.py" | awk '{print $1}')
jq --arg sha "$WRITER_SHA" '
  .project_id = "source-writer-fixture" |
  .providers[0].id = "fixture.source-writer" |
  .providers[0].command = ["python3", "{better_test_root}/fixtures/providers/provider-writes-source.py"] |
  .providers[0].capabilities = ["source-map"] |
  .providers[0].trust.sha256 = $sha |
  .providers[0].trust.dependencies = []
' "$ROOT_DIR/fixtures/providers/project-profile-valid.json" >"$TMP_DIR/writer-profile.json"
expect_fail "detected a source checkout mutation" \
  python3 "$ROOT_DIR/scripts/run-source-provider.py" \
  --profile "$TMP_DIR/writer-profile.json" --provider fixture.source-writer \
  --operation probe --project-root "$TMP_DIR/writer-project" \
  --better-test-root "$ROOT_DIR" --output "$TMP_DIR/rejected.json"
cp -R "$TMP_DIR/rust-project" "$TMP_DIR/ignored-writer-project"
expect_fail "detected a source checkout mutation" \
  python3 "$ROOT_DIR/scripts/run-source-provider.py" \
  --profile "$TMP_DIR/writer-profile.json" --provider fixture.source-writer \
  --operation probe --project-root "$TMP_DIR/ignored-writer-project" \
  --better-test-root "$ROOT_DIR" --output "$TMP_DIR/rejected.json" -- --ignored-only

# Failure and authorization paths must fail closed instead of emitting empty evidence.
SLOW_SHA=$(shasum -a 256 "$ROOT_DIR/fixtures/providers/provider-slow.py" | awk '{print $1}')
BAD_JSON_SHA=$(shasum -a 256 "$ROOT_DIR/fixtures/providers/provider-bad-json.py" | awk '{print $1}')
jq --arg sha "$SLOW_SHA" '
  .project_id = "runner-slow-fixture" |
  .providers[0].id = "fixture.slow" |
  .providers[0].command = ["python3", "{better_test_root}/fixtures/providers/provider-slow.py"] |
  .providers[0].capabilities = ["source-map"] |
  .providers[0].trust.sha256 = $sha |
  del(.providers[0].trust.dependencies)
' "$ROOT_DIR/fixtures/providers/project-profile-valid.json" >"$TMP_DIR/slow-profile.json"
expect_fail "execution error" python3 "$ROOT_DIR/scripts/run-source-provider.py" \
  --profile "$TMP_DIR/slow-profile.json" --provider fixture.slow --operation inventory \
  --project-root "$TMP_DIR/rust-project" --better-test-root "$ROOT_DIR" \
  --timeout 1 --output "$TMP_DIR/rejected.json"
jq --arg sha "$BAD_JSON_SHA" '
  .project_id = "runner-bad-json-fixture" |
  .providers[0].id = "fixture.bad-json" |
  .providers[0].command = ["python3", "{better_test_root}/fixtures/providers/provider-bad-json.py"] |
  .providers[0].capabilities = ["source-map"] |
  .providers[0].trust.sha256 = $sha |
  del(.providers[0].trust.dependencies)
' "$ROOT_DIR/fixtures/providers/project-profile-valid.json" >"$TMP_DIR/bad-json-profile.json"
expect_fail "duplicate JSON key" python3 "$ROOT_DIR/scripts/run-source-provider.py" \
  --profile "$TMP_DIR/bad-json-profile.json" --provider fixture.bad-json --operation inventory \
  --project-root "$TMP_DIR/rust-project" --better-test-root "$ROOT_DIR" \
  --output "$TMP_DIR/rejected.json"
jq '.providers[0].trust.network = "explicit"' \
  "$ROOT_DIR/fixtures/providers/project-profile-valid.json" >"$TMP_DIR/network-explicit.json"
expect_fail "requires --allow-network" python3 "$ROOT_DIR/scripts/run-source-provider.py" \
  --profile "$TMP_DIR/network-explicit.json" --provider better-test.rust-cargo --operation inventory \
  --project-root "$TMP_DIR/rust-project" --better-test-root "$ROOT_DIR" --output "$TMP_DIR/rejected.json"
expect_fail "refuses network authorization" python3 "$ROOT_DIR/scripts/run-source-provider.py" \
  --profile "$ROOT_DIR/fixtures/providers/project-profile-valid.json" --provider better-test.rust-cargo --operation inventory \
  --project-root "$TMP_DIR/rust-project" --better-test-root "$ROOT_DIR" --allow-network --output "$TMP_DIR/rejected.json"
jq '.providers[0].trust.external_writes = "explicit"' \
  "$ROOT_DIR/fixtures/providers/project-profile-valid.json" >"$TMP_DIR/writes-explicit.json"
expect_fail "requires --allow-external-writes" python3 "$ROOT_DIR/scripts/run-source-provider.py" \
  --profile "$TMP_DIR/writes-explicit.json" --provider better-test.rust-cargo --operation inventory \
  --project-root "$TMP_DIR/rust-project" --better-test-root "$ROOT_DIR" --output "$TMP_DIR/rejected.json"
expect_fail "scratch directory is dangerously broad" python3 "$ROOT_DIR/scripts/run-source-provider.py" \
  --profile "$TMP_DIR/writes-explicit.json" --provider better-test.rust-cargo --operation inventory \
  --project-root "$TMP_DIR/rust-project" --better-test-root "$ROOT_DIR" \
  --allow-external-writes --scratch-dir "$TMP_DIR/rust-project/.better-test-cache" \
  --output "$TMP_DIR/rejected.json"
expect_fail "output path is protected" python3 "$ROOT_DIR/scripts/run-source-provider.py" \
  --profile "$ROOT_DIR/fixtures/providers/project-profile-valid.json" \
  --provider better-test.rust-cargo --operation inventory \
  --project-root "$TMP_DIR/rust-project" --better-test-root "$ROOT_DIR" \
  --output "$TMP_DIR/rust-project/provider-output.json"
expect_fail "metrics-output path is protected" python3 "$ROOT_DIR/scripts/run-source-provider.py" \
  --profile "$ROOT_DIR/fixtures/providers/project-profile-valid.json" \
  --provider better-test.rust-cargo --operation inventory \
  --project-root "$TMP_DIR/rust-project" --better-test-root "$ROOT_DIR" \
  --output "$TMP_DIR/allowed-output.json" \
  --metrics-output "$ROOT_DIR/provider-metrics.json"
expect_fail "refuses external-write authorization" python3 "$ROOT_DIR/scripts/run-source-provider.py" \
  --profile "$ROOT_DIR/fixtures/providers/project-profile-valid.json" --provider better-test.rust-cargo --operation inventory \
  --project-root "$TMP_DIR/rust-project" --better-test-root "$ROOT_DIR" --allow-external-writes --output "$TMP_DIR/rejected.json"
printf '\npub fn intentionally_unformatted( )->u32{1}\n' >>"$TMP_DIR/rust-project/crates/core/src/lib.rs"
expect_fail "recorded 1 failed check" python3 "$ROOT_DIR/scripts/run-source-provider.py" \
  --profile "$ROOT_DIR/fixtures/providers/project-profile-valid.json" --provider better-test.rust-cargo --operation check \
  --project-root "$TMP_DIR/rust-project" --better-test-root "$ROOT_DIR" \
  --output "$TMP_DIR/failed-check.json" -- --check-id cargo-fmt:workspace
[[ -s "$TMP_DIR/failed-check.json" ]] || fail "failed check output was not preserved"

# Strategy replay is deterministic and low-confidence impact cannot reduce scope.
python3 "$ROOT_DIR/scripts/resolve-hybrid-strategy.py" \
  --objective source_change \
  --capabilities "$ROOT_DIR/fixtures/providers/capabilities-valid.json" \
  --profile "$ROOT_DIR/fixtures/providers/project-profile-valid.json" \
  --impact "$TMP_DIR/source-impact-unknown.json" \
  --output "$TMP_DIR/strategy-1.json" >/dev/null
python3 "$ROOT_DIR/scripts/resolve-hybrid-strategy.py" \
  --objective source_change \
  --capabilities "$ROOT_DIR/fixtures/providers/capabilities-valid.json" \
  --profile "$ROOT_DIR/fixtures/providers/project-profile-valid.json" \
  --impact "$TMP_DIR/source-impact-unknown.json" \
  --output "$TMP_DIR/strategy-2.json" >/dev/null
cmp "$TMP_DIR/strategy-1.json" "$TMP_DIR/strategy-2.json" >/dev/null || \
  fail "strategy resolution is not deterministic"
jq -e '.mode == "whitebox" and (.required_lanes | index("invariant"))' \
  "$TMP_DIR/strategy-1.json" >/dev/null || fail "strategy did not preserve safe lanes"
python3 "$ROOT_DIR/scripts/resolve-hybrid-strategy.py" \
  --objective artifact_acceptance \
  --capabilities "$ROOT_DIR/fixtures/providers/capabilities-valid.json" \
  --profile "$ROOT_DIR/fixtures/providers/project-profile-valid.json" \
  --output "$TMP_DIR/strategy-alias.json" >/dev/null
jq -e '.objective == "artifact_acceptance" and .normalized_objective == "package_validation"' \
  "$TMP_DIR/strategy-alias.json" >/dev/null || fail "objective alias was not normalized"

# Capability ceilings are table-driven and cannot be raised by an untrusted probe.
jq '.providers[0].capabilities = [
  "source-map","source-impact","runtime-probe","artifact-identity",
  "process-identity","session-readiness","typed-subject-identity"
]' "$ROOT_DIR/fixtures/providers/project-profile-valid.json" >"$TMP_DIR/matrix-profile.json"
jq '.capabilities = [
  {name:"source-map",status:"unavailable",evidence:"matrix"},
  {name:"source-impact",status:"unavailable",evidence:"matrix"},
  {name:"runtime-probe",status:"unavailable",evidence:"matrix"},
  {name:"artifact-identity",status:"unavailable",evidence:"matrix"},
  {name:"process-identity",status:"unavailable",evidence:"matrix"},
  {name:"session-readiness",status:"unavailable",evidence:"matrix"},
  {name:"typed-subject-identity",status:"unavailable",evidence:"matrix"}
]' "$ROOT_DIR/fixtures/providers/capabilities-valid.json" >"$TMP_DIR/caps-none.json"
python3 "$ROOT_DIR/scripts/resolve-hybrid-strategy.py" --objective package_validation \
  --capabilities "$TMP_DIR/caps-none.json" --profile "$TMP_DIR/matrix-profile.json" \
  --output "$TMP_DIR/strategy-none.json" >/dev/null
jq -e '.mode == "blackbox" and .max_claim_scope == "behavior"' \
  "$TMP_DIR/strategy-none.json" >/dev/null || fail "no-capability ceiling drift"
jq '(.capabilities[] | select(.name == "artifact-identity")).status = "available"' \
  "$TMP_DIR/caps-none.json" >"$TMP_DIR/caps-artifact.json"
python3 "$ROOT_DIR/scripts/resolve-hybrid-strategy.py" --objective package_validation \
  --capabilities "$TMP_DIR/caps-artifact.json" --profile "$TMP_DIR/matrix-profile.json" \
  --output "$TMP_DIR/strategy-artifact.json" >/dev/null
jq -e '.max_claim_scope == "artifact_identity"' "$TMP_DIR/strategy-artifact.json" >/dev/null || \
  fail "artifact-only ceiling drift"
jq '(.capabilities[] | select(.name == "source-map" or .name == "source-impact" or .name == "runtime-probe" or .name == "typed-subject-identity")).status = "available"' \
  "$TMP_DIR/caps-none.json" >"$TMP_DIR/caps-hybrid-partial.json"
python3 "$ROOT_DIR/scripts/resolve-hybrid-strategy.py" --objective release_decision \
  --capabilities "$TMP_DIR/caps-hybrid-partial.json" --profile "$TMP_DIR/matrix-profile.json" \
  --output "$TMP_DIR/strategy-hybrid-partial.json" >/dev/null
jq -e '.mode == "hybrid" and .max_claim_scope == "observed_behavior"' \
  "$TMP_DIR/strategy-hybrid-partial.json" >/dev/null || fail "partial hybrid ceiling drift"
jq '(.capabilities[] | select(.name == "artifact-identity" or .name == "process-identity" or .name == "runtime-probe" or .name == "typed-subject-identity")).status = "available"' \
  "$TMP_DIR/caps-none.json" >"$TMP_DIR/caps-runtime-ready.json"
python3 "$ROOT_DIR/scripts/resolve-hybrid-strategy.py" --objective release_decision \
  --capabilities "$TMP_DIR/caps-runtime-ready.json" --profile "$TMP_DIR/matrix-profile.json" \
  --output "$TMP_DIR/strategy-runtime-ready.json" >/dev/null
jq -e '.max_claim_scope == "runtime_readiness"' "$TMP_DIR/strategy-runtime-ready.json" >/dev/null || \
  fail "runtime-ready ceiling drift"
jq '(.capabilities[] | select(.name == "session-readiness")).status = "available"' \
  "$TMP_DIR/caps-runtime-ready.json" >"$TMP_DIR/caps-release.json"
python3 "$ROOT_DIR/scripts/resolve-hybrid-strategy.py" --objective release_decision \
  --capabilities "$TMP_DIR/caps-release.json" --profile "$TMP_DIR/matrix-profile.json" \
  --output "$TMP_DIR/strategy-release.json" >/dev/null
jq -e '.max_claim_scope == "release_gate"' "$TMP_DIR/strategy-release.json" >/dev/null || \
  fail "release capability ceiling drift"
jq '.provider.id = "attacker.fake"' "$TMP_DIR/caps-release.json" >"$TMP_DIR/caps-fake.json"
expect_fail "capabilities provider is not declared by project profile" \
  python3 "$ROOT_DIR/scripts/resolve-hybrid-strategy.py" --objective release_decision \
  --capabilities "$TMP_DIR/caps-fake.json" --profile "$TMP_DIR/matrix-profile.json" \
  --output "$TMP_DIR/strategy-rejected.json"
jq 'del(.capabilities[] | select(.name == "typed-subject-identity"))' \
  "$TMP_DIR/caps-release.json" >"$TMP_DIR/caps-omitted.json"
expect_fail "omits standard rows: typed-subject-identity" \
  python3 "$ROOT_DIR/scripts/resolve-hybrid-strategy.py" --objective release_decision \
  --capabilities "$TMP_DIR/caps-omitted.json" --profile "$TMP_DIR/matrix-profile.json" \
  --output "$TMP_DIR/strategy-rejected.json"
jq '.features.hybrid_testing = false' \
  "$ROOT_DIR/fixtures/providers/project-profile-valid.json" >"$TMP_DIR/profile-hybrid-off.json"
python3 "$ROOT_DIR/scripts/resolve-hybrid-strategy.py" --objective source_change \
  --capabilities "$ROOT_DIR/fixtures/providers/capabilities-valid.json" \
  --profile "$TMP_DIR/profile-hybrid-off.json" --output "$TMP_DIR/strategy-hybrid-off.json" >/dev/null
jq -e '.mode == "blackbox" and .max_claim_scope == "behavior" and
  (.missing_capabilities | index("source-map")) and
  (.missing_capabilities | index("source-impact"))' \
  "$TMP_DIR/strategy-hybrid-off.json" >/dev/null || fail "hybrid-off policy leaked source claims"
jq '.features.results_v4 = "off"' \
  "$ROOT_DIR/fixtures/providers/project-profile-valid.json" >"$TMP_DIR/profile-v4-off.json"
expect_fail "project profile disables results v4" \
  python3 "$ROOT_DIR/scripts/resolve-hybrid-strategy.py" --objective source_change \
  --capabilities "$ROOT_DIR/fixtures/providers/capabilities-valid.json" \
  --profile "$TMP_DIR/profile-v4-off.json" --output "$TMP_DIR/strategy-rejected.json"

# Legacy GO is deliberately capped until typed runtime identity exists.
mkdir -p "$TMP_DIR/projected/artifacts"
cp "$ROOT_DIR/hooks/fixtures/artifacts/"* "$TMP_DIR/projected/artifacts/"
python3 "$ROOT_DIR/scripts/hybrid-results.py" project-v3-to-v4 \
  "$ROOT_DIR/hooks/fixtures/results-v3-valid.json" "$TMP_DIR/projected/results.json" >/dev/null
python3 "$ROOT_DIR/scripts/validate-results-v4.py" "$TMP_DIR/projected/results.json" >/dev/null
jq -e '.release_readiness.verdict == "blocked"' "$TMP_DIR/projected/results.json" >/dev/null || \
  fail "legacy GO was not capped"
python3 "$ROOT_DIR/scripts/hybrid-results.py" semantic-diff \
  "$TMP_DIR/projected/results.json" "$TMP_DIR/projected/results.json" >/dev/null
jq '.items[0].evidence_strength = "direct"' \
  "$TMP_DIR/projected/results.json" >"$TMP_DIR/projected/evidence-drift.json"
expect_fail "canonical field differs: items" python3 "$ROOT_DIR/scripts/hybrid-results.py" semantic-diff \
  "$TMP_DIR/projected/results.json" "$TMP_DIR/projected/evidence-drift.json"
expect_fail "release_readiness" python3 "$ROOT_DIR/scripts/hybrid-results.py" semantic-diff \
  "$ROOT_DIR/hooks/fixtures/results-v3-valid.json" "$TMP_DIR/projected/results.json"

# A compatible shadow pair materializes independent canonical v3/v4 run trees.
mkdir -p "$TMP_DIR/dual-input/artifacts" "$TMP_DIR/dual-input/hybrid"
cp "$ROOT_DIR/hooks/fixtures/artifacts/"* "$TMP_DIR/dual-input/artifacts/"
cp "$TMP_DIR/source-map-1.json" "$TMP_DIR/dual-input/hybrid/source-map.json"
DUAL_MAP_SHA=$(shasum -a 256 "$TMP_DIR/dual-input/hybrid/source-map.json" | awk '{print $1}')
jq --arg sha "$DUAL_MAP_SHA" '
  .release_readiness = {verdict:"blocked", reason:"generic dual-write fixture is non-release"} |
  .hybrid = {
    contract_version:"1.0.0", mode:"whitebox", objective:"legacy_compatibility",
    max_claim_scope:"behavior", missing_capabilities:["typed-subject-identity"],
    semantic_diff:"pass",
    artifacts:{source_map:{artifact_ref:"hybrid/source-map.json", sha256:$sha}}
  }
' "$ROOT_DIR/hooks/fixtures/results-v3-valid.json" >"$TMP_DIR/dual-input/results.json"
"$ROOT_DIR/scripts/validate-results.sh" "$TMP_DIR/dual-input/results.json" >/dev/null
python3 "$ROOT_DIR/scripts/hybrid-results.py" project-v3-to-v4 \
  "$TMP_DIR/dual-input/results.json" "$TMP_DIR/dual-input/results-v4.json" >/dev/null
jq '.subjects[0].identity.commit = "forged-commit"' \
  "$TMP_DIR/dual-input/results-v4.json" >"$TMP_DIR/dual-input/identity-drift.json"
expect_fail "canonical field differs: subjects" python3 "$ROOT_DIR/scripts/hybrid-results.py" \
  semantic-diff "$TMP_DIR/dual-input/results.json" "$TMP_DIR/dual-input/identity-drift.json"
jq '.coverage_by_lane.surface = {numerator:0,denominator:0,pct:0,subject_refs:["legacy:run"],tool:"forged",conditions:"forged"}' \
  "$TMP_DIR/dual-input/results-v4.json" >"$TMP_DIR/dual-input/coverage-drift.json"
expect_fail "canonical field differs: coverage_by_lane" python3 "$ROOT_DIR/scripts/hybrid-results.py" \
  semantic-diff "$TMP_DIR/dual-input/results.json" "$TMP_DIR/dual-input/coverage-drift.json"
jq --slurpfile projected "$TMP_DIR/dual-input/results-v4.json" '
  .hybrid.coverage_by_lane = $projected[0].coverage_by_lane |
  .hybrid.coverage_by_lane.inventory = {
    numerator:1,denominator:1,pct:100,subject_refs:["legacy:run"],
    tool:"typed-v3-extension",conditions:"preserved during projection"
  }
' "$TMP_DIR/dual-input/results.json" >"$TMP_DIR/dual-input/typed-coverage-results.json"
python3 "$ROOT_DIR/scripts/hybrid-results.py" project-v3-to-v4 \
  "$TMP_DIR/dual-input/typed-coverage-results.json" \
  "$TMP_DIR/dual-input/typed-coverage-results-v4.json" >/dev/null
python3 "$ROOT_DIR/scripts/hybrid-results.py" semantic-diff \
  "$TMP_DIR/dual-input/typed-coverage-results.json" \
  "$TMP_DIR/dual-input/typed-coverage-results-v4.json" >/dev/null
jq -e '.coverage_by_lane.inventory.pct == 100 and .coverage_by_lane.inventory.tool == "typed-v3-extension"' \
  "$TMP_DIR/dual-input/typed-coverage-results-v4.json" >/dev/null || \
  fail "v3.1 typed coverage lanes were lost during projection"
jq '.missing_capabilities += ["forged-capability"]' \
  "$TMP_DIR/dual-input/results-v4.json" >"$TMP_DIR/dual-input/capability-drift.json"
expect_fail "canonical field differs: missing_capabilities" python3 "$ROOT_DIR/scripts/hybrid-results.py" \
  semantic-diff "$TMP_DIR/dual-input/results.json" "$TMP_DIR/dual-input/capability-drift.json"
jq '.release_readiness.reason = "forged reason"' \
  "$TMP_DIR/dual-input/results-v4.json" >"$TMP_DIR/dual-input/readiness-drift.json"
expect_fail "canonical field differs: release_readiness" python3 "$ROOT_DIR/scripts/hybrid-results.py" \
  semantic-diff "$TMP_DIR/dual-input/results.json" "$TMP_DIR/dual-input/readiness-drift.json"
mkdir -p "$TMP_DIR/dual-invalid/artifacts" "$TMP_DIR/dual-invalid/hybrid"
cp "$ROOT_DIR/hooks/fixtures/artifacts/"* "$TMP_DIR/dual-invalid/artifacts/"
cp "$TMP_DIR/dual-input/hybrid/source-map.json" "$TMP_DIR/dual-invalid/hybrid/source-map.json"
jq '.summary.total = 2' "$TMP_DIR/dual-input/results.json" >"$TMP_DIR/dual-invalid/results.json"
expect_fail "dual-write v3 validation failed" python3 "$ROOT_DIR/scripts/hybrid-results.py" dual-write \
  "$TMP_DIR/dual-invalid/results.json" "$TMP_DIR/dual-input/results-v4.json" \
  "$TMP_DIR/dual-invalid-output"
jq '.compatibility.v3_sha256 = ("0"*64)' "$TMP_DIR/dual-input/results-v4.json" \
  >"$TMP_DIR/dual-input/forged-compatibility.json"
expect_fail "compatibility does not bind the exact v3 input" \
  python3 "$ROOT_DIR/scripts/hybrid-results.py" dual-write \
  "$TMP_DIR/dual-input/results.json" "$TMP_DIR/dual-input/forged-compatibility.json" \
  "$TMP_DIR/dual-forged-output"
if [ -e "$TMP_DIR/dual-forged-output" ]; then
  fail "failed dual-write left a partial output tree"
fi
mkdir -p "$TMP_DIR/dual-existing-output"
printf 'preserve me\n' >"$TMP_DIR/dual-existing-output/sentinel.txt"
expect_fail "output_dir must not exist" python3 "$ROOT_DIR/scripts/hybrid-results.py" dual-write \
  "$TMP_DIR/dual-input/results.json" "$TMP_DIR/dual-input/results-v4.json" \
  "$TMP_DIR/dual-existing-output"
grep -Fx 'preserve me' "$TMP_DIR/dual-existing-output/sentinel.txt" >/dev/null || \
  fail "dual-write changed an existing output tree"
python3 "$ROOT_DIR/scripts/hybrid-results.py" dual-write \
  "$TMP_DIR/dual-input/results.json" "$TMP_DIR/dual-input/results-v4.json" \
  "$TMP_DIR/dual-output" >/dev/null
"$ROOT_DIR/scripts/validate-results.sh" "$TMP_DIR/dual-output/v3/results.json" >/dev/null
"$ROOT_DIR/scripts/validate-results.sh" "$TMP_DIR/dual-output/v4/results.json" >/dev/null
python3 "$ROOT_DIR/scripts/hybrid-results.py" semantic-diff \
  "$TMP_DIR/dual-output/v3/results.json" "$TMP_DIR/dual-output/v4/results.json" >/dev/null
jq -e '
  .status == "pass" and (.differences | length == 0) and
  (.v3_sha256 | test("^[0-9a-f]{64}$")) and
  (.v4_sha256 | test("^[0-9a-f]{64}$")) and
  .v3_projection_ref == "v3/results.json" and .v4_result_ref == "v4/results.json"
' \
  "$TMP_DIR/dual-output/semantic-diff.json" >/dev/null || fail "dual-write receipt is incomplete"

# Historical pass-with-caveat must survive v3 -> v4 without becoming plain PASS.
mkdir -p "$TMP_DIR/caveat/artifacts"
cp "$ROOT_DIR/hooks/fixtures/artifacts/"* "$TMP_DIR/caveat/artifacts/"
jq '
  .items[0].status = "pass_with_caveat" |
  .items[0].caveat_reason = "bounded historical fixture caveat" |
  .summary.passed_unconditional = 0 |
  .summary.passed_with_caveat = 1 |
  .release_readiness = {verdict:"blocked", reason:"caveated fixture is not release GO"}
' "$ROOT_DIR/hooks/fixtures/results-v3-valid.json" >"$TMP_DIR/caveat/results.json"
"$ROOT_DIR/scripts/validate-results.sh" "$TMP_DIR/caveat/results.json" >/dev/null
python3 "$ROOT_DIR/scripts/hybrid-results.py" project-v3-to-v4 \
  "$TMP_DIR/caveat/results.json" "$TMP_DIR/caveat/results-v4.json" >/dev/null
python3 "$ROOT_DIR/scripts/validate-results-v4.py" "$TMP_DIR/caveat/results-v4.json" >/dev/null
python3 "$ROOT_DIR/scripts/hybrid-results.py" semantic-diff \
  "$TMP_DIR/caveat/results.json" "$TMP_DIR/caveat/results-v4.json" >/dev/null
jq -e '
  .items[0].status == "pass_with_caveat" and
  .items[0].reason == "bounded historical fixture caveat" and
  .summary.passed == 1 and .summary.passed_unconditional == 0 and .summary.passed_with_caveat == 1
' "$TMP_DIR/caveat/results-v4.json" >/dev/null || fail "v4 lost pass-with-caveat semantics"
jq '
  .release_readiness = {verdict:"go", reason:"unsafe caveat promotion"} |
  .subjects += [{id:"process:fixture",type:"process",identity:{pid:123,executable_sha256:("c"*64),started_at:"2026-07-24T12:00:00+08:00"}}]
' "$TMP_DIR/caveat/results-v4.json" >"$TMP_DIR/caveat/unsafe-go.json"
expect_fail "caveat/legacy pass requires a complete override" \
  python3 "$ROOT_DIR/scripts/validate-results-v4.py" "$TMP_DIR/caveat/unsafe-go.json"

# Generic layer purity: product-specific knowledge belongs in project profiles/providers.
set +e
grep -r -i -E '(^|[^[:alnum:]_])(futu|opend|moomoo)([^[:alnum:]_]|$)' \
  "$ROOT_DIR/schemas" \
  "$ROOT_DIR/scripts/hybrid_core.py" \
  "$ROOT_DIR/scripts/rust-cargo-provider.py" \
  "$ROOT_DIR/scripts/run-source-provider.py" \
  "$ROOT_DIR/scripts/resolve-hybrid-strategy.py" >/dev/null
guard_rc=$?
set -e
if [[ "$guard_rc" -eq 0 ]]; then
  fail "product-specific knowledge leaked into the generic layer"
elif [[ "$guard_rc" -ge 2 ]]; then
  fail "generic-layer purity guard failed (exit $guard_rc)"
fi

echo "PASS: hybrid contracts, provider, strategy, migration, and trust-boundary fixtures"

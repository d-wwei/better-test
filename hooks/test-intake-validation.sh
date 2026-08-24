#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VALIDATOR="$ROOT_DIR/scripts/validate-intake.py"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

PROJECT="$TMP_DIR/project"
RUN_DIR="$PROJECT/test/history/v1/run-codex-test-001"
mkdir -p "$RUN_DIR" "$PROJECT/build"
printf 'candidate artifact\n' >"$PROJECT/build/app.bin"
ARTIFACT_SHA="$(shasum -a 256 "$PROJECT/build/app.bin" | awk '{print $1}')"

write_intake() {
  jq -n --arg sha "$ARTIFACT_SHA" '{
    schema_version: 1,
    intake_id: "intake-001",
    produced_by: "weird-upstream-9000",
    attested_at: "2026-08-24T14:30:00+08:00",
    subjects: [
      {id:"src",type:"source",identity:{commit:"abc123",dirty:false}},
      {id:"build",type:"build",identity:{
        source_ref:"src",toolchain:"fixture",lock_sha256:("a"*64),
        features:[],profile:"release",output_sha256:$sha
      }},
      {id:"artifact",type:"artifact",identity:{
        sha256:$sha,path:"build/app.bin",path_base:"project_root"
      }}
    ],
    relations: [
      {type:"built_from",from:"build",to:"src",evidence_refs:["build.log"]},
      {type:"produced_by",from:"artifact",to:"build",evidence_refs:["build.log"]}
    ]
  }' >"$RUN_DIR/intake.json"
}

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

write_intake
INTAKE_SHA="$(shasum -a 256 "$RUN_DIR/intake.json" | awk '{print $1}')"
jq -n --arg sha "$INTAKE_SHA" '{
  schema_version: 1,
  intake_ref: {intake_id:"intake-001",sha256:$sha}
}' >"$RUN_DIR/results.json"

python3 "$VALIDATOR" "$RUN_DIR/intake.json" \
  --results "$RUN_DIR/results.json" \
  --project-root "$PROJECT" \
  --require-binding >/dev/null

jq '.relations[1].to = "src"' "$RUN_DIR/intake.json" >"$RUN_DIR/invalid-relation.json"
expect_fail "invalid subject types for produced_by" \
  python3 "$VALIDATOR" "$RUN_DIR/invalid-relation.json"

write_intake
printf '\n' >>"$RUN_DIR/intake.json"
expect_fail "intake_ref.sha256 does not match" \
  python3 "$VALIDATOR" "$RUN_DIR/intake.json" \
  --results "$RUN_DIR/results.json" --require-binding

write_intake
jq '.subjects[2].identity.path = "../escape.bin"' "$RUN_DIR/intake.json" \
  >"$RUN_DIR/path-traversal.json"
expect_fail "safe relative path" \
  python3 "$VALIDATOR" "$RUN_DIR/path-traversal.json" --project-root "$PROJECT"

jq 'del(.intake_ref)' "$RUN_DIR/results.json" >"$RUN_DIR/results-unbound.json"
expect_fail "missing intake_ref" \
  python3 "$VALIDATOR" "$RUN_DIR/intake.json" \
  --results "$RUN_DIR/results-unbound.json" --require-binding

python3 - "$ROOT_DIR/schemas/results-v4.schema.json" "$ROOT_DIR/schemas/intake.schema.json" <<'PY'
import json
import sys

results = json.load(open(sys.argv[1], encoding="utf-8"))
intake = json.load(open(sys.argv[2], encoding="utf-8"))
result_subject = results["properties"]["subjects"]["items"]
intake_subject = intake["properties"]["subjects"]["items"]
assert result_subject["properties"]["type"] == intake_subject["properties"]["type"]
assert (
    results["properties"]["relations"]["items"]["properties"]["type"]
    == intake["properties"]["relations"]["items"]["properties"]["type"]
)
for subject_type in ("source", "build", "installation", "process", "session"):
    def required_fields(schema):
        for rule in schema["allOf"]:
            if rule["if"]["properties"]["type"].get("const") == subject_type:
                return rule["then"]["properties"]["identity"]["required"]
        raise AssertionError(subject_type)
    assert required_fields(result_subject) == required_fields(intake_subject)
PY

echo "intake validation tests passed"

#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TMP_DIR="$(mktemp -d)"
PROJECT_DIR="$TMP_DIR/project"
HOME_DIR="$TMP_DIR/home"
RUN_DIR="$PROJECT_DIR/.better-work/test/history/v1/run-codex-a3f2-001-1234"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$RUN_DIR" "$PROJECT_DIR/.codex" "$HOME_DIR/.codex"

run_post_bash() {
  local script="$1"
  local command="$2"
  jq -n --arg cwd "$PROJECT_DIR" --arg command "$command" '{
    tool_name: "Bash",
    cwd: $cwd,
    tool_input: {command: $command}
  }' | "$script"
}

cat > "$RUN_DIR/results.json" <<'EOF'
{"version":"1.0.0","run_id":"run-1","mode":"targeted","summary":"bad","coverage":null,"items":[{"id":"bad-id","status":"pass","assertion_field":"","evidence_level":"indirect"}]}
EOF

CHECKLIST_OUT=$(run_post_bash "$SCRIPT_DIR/codex/post-test-checklist.sh" 'printf "{}" > .better-work/test/history/v1/run-codex-a3f2-001-1234/results.json')
printf '%s\n' "$CHECKLIST_OUT" | jq -e '.hookSpecificOutput.additionalContext | contains("post-completion checklist")' >/dev/null

CHECKLIST_MULTI_OUT=$(run_post_bash "$SCRIPT_DIR/codex/post-test-checklist.sh" 'cp notes.md /tmp/checklist-copy && printf "{}" > .better-work/test/history/v1/run-codex-a3f2-001-1234/results.json')
printf '%s\n' "$CHECKLIST_MULTI_OUT" | jq -e '.hookSpecificOutput.additionalContext | contains("post-completion checklist")' >/dev/null

VALIDATION_OUT=$(run_post_bash "$SCRIPT_DIR/codex/results-validation.sh" 'printf "{}" > .better-work/test/history/v1/run-codex-a3f2-001-1234/results.json')
printf '%s\n' "$VALIDATION_OUT" | jq -e '.hookSpecificOutput.additionalContext | contains("results.json 字段检查")' >/dev/null

VALIDATION_MULTI_OUT=$(run_post_bash "$SCRIPT_DIR/codex/results-validation.sh" 'cp notes.md /tmp/validation-copy && printf "{}" > .better-work/test/history/v1/run-codex-a3f2-001-1234/results.json')
printf '%s\n' "$VALIDATION_MULTI_OUT" | jq -e '.hookSpecificOutput.additionalContext | contains("results.json 字段检查")' >/dev/null

cat > "$RUN_DIR/strategy-plan.md" <<'EOF'
# draft
EOF

REG_OUT=$(run_post_bash "$SCRIPT_DIR/codex/registration-gate.sh" 'printf "draft" > .better-work/test/history/v1/run-codex-a3f2-001-1234/strategy-plan.md')
printf '%s\n' "$REG_OUT" | jq -e '.hookSpecificOutput.additionalContext | contains("Registration gate")' >/dev/null

REG_MULTI_OUT=$(run_post_bash "$SCRIPT_DIR/codex/registration-gate.sh" 'cp notes.md /tmp/registration-copy && printf "draft" > .better-work/test/history/v1/run-codex-a3f2-001-1234/strategy-plan.md')
printf '%s\n' "$REG_MULTI_OUT" | jq -e '.hookSpecificOutput.additionalContext | contains("Registration gate")' >/dev/null

EMPTY_OUT=$(run_post_bash "$SCRIPT_DIR/codex/post-test-checklist.sh" 'cat .better-work/test/history/v1/run-codex-a3f2-001-1234/results.json')
if [[ -n "$EMPTY_OUT" ]]; then
  echo "expected no advisory output for non-write Bash command" >&2
  exit 1
fi

# --- pass-evidence-check: compare mode pass without baseline ---
cp "$SCRIPT_DIR/fixtures/results-pass-no-baseline.json" "$RUN_DIR/results.json"
COMPARE_OUT=$(run_post_bash "$SCRIPT_DIR/codex/results-validation.sh" "printf '%s' '$(cat "$SCRIPT_DIR/fixtures/results-pass-no-baseline.json")' > .better-work/test/history/v1/run-codex-a3f2-001-1234/results.json")
printf '%s\n' "$COMPARE_OUT" | jq -e '.hookSpecificOutput.additionalContext | contains("comparison_baseline")' >/dev/null

# --- pass-evidence-check: pre_existing=true marked pass (non-retest mode → warn) ---
cp "$SCRIPT_DIR/fixtures/results-pre-existing-pass.json" "$RUN_DIR/results.json"
PREEXIST_OUT=$(run_post_bash "$SCRIPT_DIR/codex/results-validation.sh" "printf '%s' '$(cat "$SCRIPT_DIR/fixtures/results-pre-existing-pass.json")' > .better-work/test/history/v1/run-codex-a3f2-001-1234/results.json")
printf '%s\n' "$PREEXIST_OUT" | jq -e '.hookSpecificOutput.additionalContext | contains("pre_existing")' >/dev/null

# --- pass-evidence-check: pre_existing=true in bug-retest mode → NO warn (legitimate fix verification) ---
cp "$SCRIPT_DIR/fixtures/results-pre-existing-pass-bugretest.json" "$RUN_DIR/results.json"
RETEST_OUT=$(run_post_bash "$SCRIPT_DIR/codex/results-validation.sh" "printf '%s' '$(cat "$SCRIPT_DIR/fixtures/results-pre-existing-pass-bugretest.json")' > .better-work/test/history/v1/run-codex-a3f2-001-1234/results.json")
if printf '%s\n' "$RETEST_OUT" | jq -e '.hookSpecificOutput.additionalContext | contains("pre_existing")' >/dev/null 2>&1; then
  echo "FAIL: bug-retest mode should NOT warn on pre_existing pass" >&2
  exit 1
fi

cat > "$HOME_DIR/.codex/config.toml" <<'EOF'
[features]
hooks = true
EOF

HOME="$HOME_DIR" "$SCRIPT_DIR/install-codex-hooks.sh" install --project "$PROJECT_DIR" >/dev/null

jq -e '
  any(.hooks.PostToolUse[]?; .matcher == "Bash" and any(.hooks[]?; (.statusMessage // "") == "better-test: post-test-checklist"))
' "$PROJECT_DIR/.codex/hooks.json" >/dev/null

jq -e '
  any(.hooks.PostToolUse[]?; .matcher == "Bash" and any(.hooks[]?; (.statusMessage // "") == "better-test: results-validation"))
' "$PROJECT_DIR/.codex/hooks.json" >/dev/null

jq -e '
  any(.hooks.PostToolUse[]?; .matcher == "Bash" and any(.hooks[]?; (.statusMessage // "") == "better-test: registration-gate"))
' "$PROJECT_DIR/.codex/hooks.json" >/dev/null

echo "codex post-bash advisory tests passed"

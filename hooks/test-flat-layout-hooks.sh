#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TMP_DIR="$(mktemp -d)"
PROJECT_DIR="$TMP_DIR/project"
HOME_DIR="$TMP_DIR/home"
CODEX_HOME_DIR="$HOME_DIR/.codex"
RUN_DIR="$PROJECT_DIR/test/history/v1/run-codex-a3f2-001-1234"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$PROJECT_DIR"
cp -R "$SCRIPT_DIR/fixtures/flat-layout/." "$PROJECT_DIR/"
mkdir -p \
  "$CODEX_HOME_DIR" \
  "$PROJECT_DIR/.codex" \
  "$PROJECT_DIR/test/.active-sessions" \
  "$PROJECT_DIR/test/reference" \
  "$RUN_DIR" \
  "$PROJECT_DIR/test/history/v1/run-codex-b9c1-001-1234"

cat > "$PROJECT_DIR/test/.active-sessions/$$.json" <<'EOF'
{"tester_id":"codex-a3f2","run_dir":"history/v1/run-codex-a3f2-001-1234"}
EOF
cat > "$PROJECT_DIR/test/.active-sessions/$PPID.json" <<'EOF'
{"tester_id":"codex-a3f2","run_dir":"history/v1/run-codex-a3f2-001-1234"}
EOF

. "$SCRIPT_DIR/lib/common.sh"
. "$SCRIPT_DIR/lib/rules/results-validation.sh"

RESOLVED_FLAT_ROOT=$(bt_resolve_test_dir "$PROJECT_DIR")
EXPECTED_FLAT_ROOT=$(bt_real_dir "$PROJECT_DIR/test")
if [[ "$RESOLVED_FLAT_ROOT" != "$EXPECTED_FLAT_ROOT" ]]; then
  echo ".better-test-root did not resolve test: $RESOLVED_FLAT_ROOT" >&2
  exit 1
fi

cat > "$CODEX_HOME_DIR/config.toml" <<'EOF'
[features]
hooks = true
EOF
INSTALL_HOOKS_OUT=$(HOME="$HOME_DIR" CODEX_HOME="$CODEX_HOME_DIR" "$SCRIPT_DIR/install-codex-hooks.sh" install --project "$PROJECT_DIR")
STATUS_HOOKS_OUT=$(HOME="$HOME_DIR" CODEX_HOME="$CODEX_HOME_DIR" "$SCRIPT_DIR/install-codex-hooks.sh" status --project "$PROJECT_DIR")
printf '%s\n' "$INSTALL_HOOKS_OUT" | grep -F "test root: $EXPECTED_FLAT_ROOT" >/dev/null
printf '%s\n' "$STATUS_HOOKS_OUT" | grep -F "test root: $EXPECTED_FLAT_ROOT" >/dev/null

run_hook() {
  local script="$1"
  local event="$2"
  local command="$3"
  jq -n --arg cwd "$PROJECT_DIR" --arg event "$event" --arg command "$command" '{
    hook_event_name: $event,
    tool_name: "Bash",
    cwd: $cwd,
    tool_input: {command: $command}
  }' | "$script"
}

expect_block() {
  local script="$1"
  local command="$2"
  local rc=0
  run_hook "$script" "PreToolUse" "$command" >/dev/null 2>"$TMP_DIR/stderr" || rc=$?
  if [[ "$rc" -ne 2 ]]; then
    echo "expected flat-layout block from $script, got $rc" >&2
    cat "$TMP_DIR/stderr" >&2 || true
    exit 1
  fi
}

expect_block "$SCRIPT_DIR/codex/credential-scan.sh" 'printf "token=supersecrettoken123456" > test/reference/notes.md'
expect_block "$SCRIPT_DIR/codex/derived-view-guard.sh" 'printf "x" > test/status.md'
expect_block "$SCRIPT_DIR/codex/session-write-guard.sh" 'printf "x" > test/history/v1/run-codex-b9c1-001-1234/results.json'

CLAUDE_RC=0
jq -n --arg cwd "$PROJECT_DIR" --arg path "$PROJECT_DIR/test/reference/notes.md" '{
  tool_name: "Write",
  cwd: $cwd,
  tool_input: {file_path: $path, content: "token=supersecrettoken123456"}
}' | "$SCRIPT_DIR/credential-scan.sh" >/dev/null 2>"$TMP_DIR/claude-stderr" || CLAUDE_RC=$?
if [[ "$CLAUDE_RC" -ne 2 ]]; then
  echo "Claude flat-layout credential hook did not block" >&2
  exit 1
fi

GATE_RC=0
jq -n --arg cwd "$PROJECT_DIR" --arg path "$PROJECT_DIR/test/reference/notes.md" '{
  tool_name: "Write",
  cwd: $cwd,
  tool_input: {file_path: $path, content: "token=supersecrettoken123456"}
}' | "$SCRIPT_DIR/gate.sh" pre-edit-write >/dev/null 2>"$TMP_DIR/gate-stderr" || GATE_RC=$?
if [[ "$GATE_RC" -ne 2 ]]; then
  echo "gate.sh did not auto-detect and block the flat layout" >&2
  exit 1
fi

jq -n --arg cwd "$PROJECT_DIR" '{
  tool_name: "Bash",
  cwd: $cwd,
  tool_input: {command: "printf flat-layout"},
  tool_response: {stdout: "flat-layout", exit_code: 0}
}' | "$SCRIPT_DIR/codex/execution-log.sh"
if [[ ! -f "$RUN_DIR/execution-log.md" ]]; then
  echo "execution log was not written to the flat test root" >&2
  exit 1
fi

CHECKLIST_OUT=$(run_hook "$SCRIPT_DIR/codex/post-test-checklist.sh" "PostToolUse" 'touch test/history/v1/run-codex-a3f2-001-1234/results.json')
printf '%s\n' "$CHECKLIST_OUT" | jq -e '.hookSpecificOutput.additionalContext | contains("post-completion checklist")' >/dev/null

cp "$SCRIPT_DIR/fixtures/results-v2-valid.json" "$RUN_DIR/results.json"
VALID_OUT=$(run_hook "$SCRIPT_DIR/codex/results-validation.sh" "PostToolUse" 'touch test/history/v1/run-codex-a3f2-001-1234/results.json')
if [[ -n "$VALID_OUT" ]]; then
  echo "valid schema v2 unexpectedly produced a validation advisory" >&2
  printf '%s\n' "$VALID_OUT" >&2
  exit 1
fi

cp "$SCRIPT_DIR/fixtures/results-v2-missing-required.json" "$RUN_DIR/results.json"
INVALID_OUT=$(run_hook "$SCRIPT_DIR/codex/results-validation.sh" "PostToolUse" 'touch test/history/v1/run-codex-a3f2-001-1234/results.json')
printf '%s\n' "$INVALID_OUT" | jq -e '
  .hookSpecificOutput.additionalContext
  | contains("schema v2 validation failed")
    and contains("tester_id")
    and contains("finished_at")
    and contains("所有 items 都缺少")
' >/dev/null

CLAUDE_VALIDATION_OUT=$(jq -n \
  --arg cwd "$PROJECT_DIR" \
  --arg path "$RUN_DIR/results.json" \
  --arg content "$(cat "$RUN_DIR/results.json")" '{
    tool_name: "Write",
    cwd: $cwd,
    tool_input: {file_path: $path, content: $content}
  }' | "$SCRIPT_DIR/results-validation.sh")
printf '%s\n' "$CLAUDE_VALIDATION_OUT" | jq -e '.hookSpecificOutput.additionalContext | contains("schema v2 validation failed")' >/dev/null

STRICT_RC=0
STRICT_OUT=$(bt_results_validation_output "$RUN_DIR/results.json" "$(cat "$RUN_DIR/results.json")" "$PROJECT_DIR") || STRICT_RC=$?
if [[ "$STRICT_RC" -ne 2 ]]; then
  echo "schema v2 missing required fields must return validation failure, got $STRICT_RC" >&2
  exit 1
fi
printf '%s\n' "$STRICT_OUT" | jq -e '.hookSpecificOutput.additionalContext | contains("schema v2 validation failed")' >/dev/null

cp "$SCRIPT_DIR/fixtures/results-v1-legacy-verdict.json" "$RUN_DIR/results.json"
LEGACY_OUT=$(run_hook "$SCRIPT_DIR/codex/results-validation.sh" "PostToolUse" 'touch test/history/v1/run-codex-a3f2-001-1234/results.json')
if [[ -n "$LEGACY_OUT" ]]; then
  echo "legacy schema v1 verdict compatibility unexpectedly produced an advisory" >&2
  printf '%s\n' "$LEGACY_OUT" >&2
  exit 1
fi

mkdir -p "$PROJECT_DIR/custom-test-root"
OVERRIDE_RESOLVED=$(BETTER_TEST_DIR="$PROJECT_DIR/custom-test-root" bt_resolve_test_dir "$PROJECT_DIR")
OVERRIDE_EXPECTED=$(bt_real_dir "$PROJECT_DIR/custom-test-root")
if [[ "$OVERRIDE_RESOLVED" != "$OVERRIDE_EXPECTED" ]]; then
  echo "BETTER_TEST_DIR override resolved to unexpected path: $OVERRIDE_RESOLVED" >&2
  exit 1
fi

echo "flat-layout hook and results schema tests passed"

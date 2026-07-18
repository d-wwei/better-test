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

mkdir -p \
  "$PROJECT_DIR/.better-work/test/.active-sessions" \
  "$PROJECT_DIR/.better-work/test/history/v1/run-codex-a3f2-001-1234" \
  "$PROJECT_DIR/.better-work/test/history/v1/run-codex-b9c1-001-1234" \
  "$PROJECT_DIR/.codex" \
  "$HOME_DIR/.codex"

cat > "$PROJECT_DIR/.better-work/test/.active-sessions/$$.json" <<'EOF'
{"tester_id":"codex-a3f2","run_dir":"history/v1/run-codex-a3f2-001-1234"}
EOF

cat > "$PROJECT_DIR/.better-work/test/.active-sessions/$PPID.json" <<'EOF'
{"tester_id":"codex-a3f2","run_dir":"history/v1/run-codex-a3f2-001-1234"}
EOF

run_write_expect_block() {
  local script="$1"
  local patch="$2"
  local stderr_file="$TMP_DIR/stderr.txt"
  local rc=0

  jq -n --arg cwd "$PROJECT_DIR" --arg command "$patch" '{
    hook_event_name: "PreToolUse",
    tool_name: "apply_patch",
    cwd: $cwd,
    tool_input: {command: $command}
  }' | "$script" >/dev/null 2>"$stderr_file" || rc=$?

  if [[ "$rc" -ne 2 ]]; then
    echo "expected block from $script, got exit $rc" >&2
    cat "$stderr_file" >&2 || true
    exit 1
  fi
}

run_write_expect_allow() {
  local script="$1"
  local patch="$2"

  jq -n --arg cwd "$PROJECT_DIR" --arg command "$patch" '{
    hook_event_name: "PreToolUse",
    tool_name: "apply_patch",
    cwd: $cwd,
    tool_input: {command: $command}
  }' | "$script" >/dev/null
}

run_write_advisory() {
  local script="$1"
  local patch="$2"

  jq -n --arg cwd "$PROJECT_DIR" --arg command "$patch" '{
    hook_event_name: "PostToolUse",
    tool_name: "apply_patch",
    cwd: $cwd,
    tool_input: {command: $command}
  }' | "$script"
}

run_write_expect_block "$SCRIPT_DIR/codex/credential-scan.sh" '*** Begin Patch
*** Add File: .better-work/test/reference/notes.md
+token=supersecrettoken123456
*** End Patch'
run_write_expect_allow "$SCRIPT_DIR/codex/credential-scan.sh" '*** Begin Patch
*** Add File: .better-work/test/reference/notes.md
+token=<redacted>
*** End Patch'
run_write_expect_allow "$SCRIPT_DIR/codex/credential-scan.sh" '*** Begin Patch
*** Add File: notes.md
+token=supersecrettoken123456
*** End Patch'

run_write_expect_block "$SCRIPT_DIR/codex/feedback-rules-guard.sh" '*** Begin Patch
*** Add File: .better-work/test/history/feedback-rules.json
+x
*** End Patch'
run_write_expect_allow "$SCRIPT_DIR/codex/feedback-rules-guard.sh" '*** Begin Patch
*** Add File: .better-work/test/history/v1/run-codex-a3f2-001-1234/feedback-rules.json
+x
*** End Patch'

run_write_expect_block "$SCRIPT_DIR/codex/derived-view-guard.sh" '*** Begin Patch
*** Add File: .better-work/test/status.md
+x
*** End Patch'
run_write_expect_allow "$SCRIPT_DIR/codex/derived-view-guard.sh" '*** Begin Patch
*** Add File: .better-work/test/history/v1/run-codex-a3f2-001-1234/status.md
+x
*** End Patch'

run_write_expect_allow "$SCRIPT_DIR/codex/session-write-guard.sh" '*** Begin Patch
*** Add File: .better-work/test/history/v1/run-codex-a3f2-001-1234/results.json
+{}
*** End Patch'
run_write_expect_block "$SCRIPT_DIR/codex/session-write-guard.sh" '*** Begin Patch
*** Add File: .better-work/test/history/v1/run-codex-b9c1-001-1234/results.json
+{}
*** End Patch'

cat > "$RUN_DIR/results.json" <<'EOF'
{}
EOF
CHECKLIST_OUT=$(run_write_advisory "$SCRIPT_DIR/codex/post-test-checklist.sh" '*** Begin Patch
*** Update File: .better-work/test/history/v1/run-codex-a3f2-001-1234/results.json
@@
-{}
+{}
*** End Patch')
printf '%s\n' "$CHECKLIST_OUT" | jq -e '.hookSpecificOutput.additionalContext | contains("post-completion checklist")' >/dev/null

cp "$SCRIPT_DIR/fixtures/results-pass-no-baseline.json" "$RUN_DIR/results.json"
COMPARE_OUT=$(run_write_advisory "$SCRIPT_DIR/codex/results-validation.sh" '*** Begin Patch
*** Update File: .better-work/test/history/v1/run-codex-a3f2-001-1234/results.json
@@
-old
+new
*** End Patch')
printf '%s\n' "$COMPARE_OUT" | jq -e '.hookSpecificOutput.additionalContext | contains("comparison_baseline")' >/dev/null

cp "$SCRIPT_DIR/fixtures/results-pre-existing-pass.json" "$RUN_DIR/results.json"
PREEXIST_OUT=$(run_write_advisory "$SCRIPT_DIR/codex/results-validation.sh" '*** Begin Patch
*** Update File: .better-work/test/history/v1/run-codex-a3f2-001-1234/results.json
@@
-old
+new
*** End Patch')
printf '%s\n' "$PREEXIST_OUT" | jq -e '.hookSpecificOutput.additionalContext | contains("pre_existing")' >/dev/null

cp "$SCRIPT_DIR/fixtures/results-pre-existing-pass-bugretest.json" "$RUN_DIR/results.json"
RETEST_OUT=$(run_write_advisory "$SCRIPT_DIR/codex/results-validation.sh" '*** Begin Patch
*** Update File: .better-work/test/history/v1/run-codex-a3f2-001-1234/results.json
@@
-old
+new
*** End Patch')
if printf '%s\n' "$RETEST_OUT" | jq -e '.hookSpecificOutput.additionalContext | contains("pre_existing")' >/dev/null 2>&1; then
  echo "FAIL: bug-retest mode should NOT warn on pre_existing pass for native Write path" >&2
  exit 1
fi

cat > "$RUN_DIR/strategy-plan.md" <<'EOF'
# draft
EOF
REG_OUT=$(run_write_advisory "$SCRIPT_DIR/codex/registration-gate.sh" '*** Begin Patch
*** Update File: .better-work/test/history/v1/run-codex-a3f2-001-1234/strategy-plan.md
@@
-# old
+# draft
*** End Patch')
printf '%s\n' "$REG_OUT" | jq -e '.hookSpecificOutput.additionalContext | contains("Registration gate")' >/dev/null

cat > "$HOME_DIR/.codex/config.toml" <<'EOF'
[features]
hooks = true
EOF

HOME="$HOME_DIR" "$SCRIPT_DIR/install-codex-hooks.sh" install --project "$PROJECT_DIR" >/dev/null

jq -e '
  any(.hooks.PreToolUse[]?; .matcher == "Write" and any(.hooks[]?; (.statusMessage // "") == "better-test: credential-scan"))
' "$PROJECT_DIR/.codex/hooks.json" >/dev/null

jq -e '
  any(.hooks.PreToolUse[]?; .matcher == "Write" and any(.hooks[]?; (.statusMessage // "") == "better-test: feedback-rules-guard"))
' "$PROJECT_DIR/.codex/hooks.json" >/dev/null

jq -e '
  any(.hooks.PreToolUse[]?; .matcher == "Write" and any(.hooks[]?; (.statusMessage // "") == "better-test: derived-view-guard"))
' "$PROJECT_DIR/.codex/hooks.json" >/dev/null

jq -e '
  any(.hooks.PreToolUse[]?; .matcher == "Write" and any(.hooks[]?; (.statusMessage // "") == "better-test: session-write-guard"))
' "$PROJECT_DIR/.codex/hooks.json" >/dev/null

jq -e '
  any(.hooks.PostToolUse[]?; .matcher == "Write" and any(.hooks[]?; (.statusMessage // "") == "better-test: post-test-checklist"))
' "$PROJECT_DIR/.codex/hooks.json" >/dev/null

jq -e '
  any(.hooks.PostToolUse[]?; .matcher == "Write" and any(.hooks[]?; (.statusMessage // "") == "better-test: results-validation"))
' "$PROJECT_DIR/.codex/hooks.json" >/dev/null

jq -e '
  any(.hooks.PostToolUse[]?; .matcher == "Write" and any(.hooks[]?; (.statusMessage // "") == "better-test: registration-gate"))
' "$PROJECT_DIR/.codex/hooks.json" >/dev/null

echo "codex write hook tests passed"

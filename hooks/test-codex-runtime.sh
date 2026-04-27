#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TMP_DIR="$(mktemp -d)"
INSTALL_HOME="$TMP_DIR/install-home"
INSTALL_CODEX_HOME_DIR="$TMP_DIR/codex-home"
PROJECT_DIR="$TMP_DIR/project"
KEEP_TMP="${BT_KEEP_TMP:-0}"

cleanup() {
  if [[ "$KEEP_TMP" == "1" ]]; then
    echo "kept runtime smoke temp dir: $TMP_DIR" >&2
    return
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

if ! command -v codex >/dev/null 2>&1; then
  echo "codex CLI not found" >&2
  exit 1
fi

print_codex_failure_details() {
  local stderr_file="$1"
  local jsonl_file="$2"
  local auth_hint=false

  if [[ -f "$stderr_file" ]]; then
    cat "$stderr_file" >&2 || true
  fi

  if [[ -f "$jsonl_file" ]]; then
    jq -r '
      select(.type == "error")
      | .message
    ' "$jsonl_file" 2>/dev/null >&2 || cat "$jsonl_file" >&2 || true

    if grep -q '401 Unauthorized' "$jsonl_file" 2>/dev/null; then
      auth_hint=true
    fi
  fi

  if [[ "$auth_hint" == "true" ]]; then
    echo "hint: Codex runtime smoke is currently failing at model/auth startup, before hook behavior can be validated." >&2
  fi

  if [[ "$KEEP_TMP" == "1" ]]; then
    echo "debug: inspect preserved artifacts under $TMP_DIR" >&2
  fi
}

final_agent_message() {
  local jsonl_file="$1"
  jq -r '
    select(.type == "item.completed" and .item.type == "agent_message")
    | .item.text
  ' "$jsonl_file" 2>/dev/null | tail -n 1
}

count_command_executions() {
  local jsonl_file="$1"
  jq -s '
    [ .[] | select(.type == "item.completed" and .item.type == "command_execution") ] | length
  ' "$jsonl_file" 2>/dev/null
}

mkdir -p "$INSTALL_HOME/.codex" "$INSTALL_CODEX_HOME_DIR" "$PROJECT_DIR/.better-work/test"
(
  cd "$PROJECT_DIR"
  git init -q
)
cat > "$INSTALL_CODEX_HOME_DIR/config.toml" <<'EOF'
[features]
codex_hooks = true
EOF

HOME="$INSTALL_HOME" CODEX_HOME="$INSTALL_CODEX_HOME_DIR" "$SCRIPT_DIR/install-codex-hooks.sh" install --project "$PROJECT_DIR" >/dev/null

runtime_rc=0
printf '%s\n' 'Use the Bash tool to run exactly: printf "runtime-smoke". After it finishes, reply with exactly OK.' | codex exec \
  --skip-git-repo-check \
  --enable codex_hooks \
  --ephemeral \
  --sandbox workspace-write \
  --json \
  -C "$PROJECT_DIR" \
  - \
  > "$TMP_DIR/codex-bash.jsonl" \
  2> "$TMP_DIR/codex-bash.stderr" || runtime_rc=$?

if [[ "$runtime_rc" -ne 0 ]]; then
  if grep -q '401 Unauthorized' "$TMP_DIR/codex-bash.jsonl" 2>/dev/null; then
    echo "runtime smoke failed: codex exec exited with $runtime_rc (auth startup failure before hook validation)" >&2
  else
    echo "runtime smoke failed: codex exec exited with $runtime_rc" >&2
  fi
  print_codex_failure_details "$TMP_DIR/codex-bash.stderr" "$TMP_DIR/codex-bash.jsonl"
  exit 1
fi

LOG_FILE="$PROJECT_DIR/.better-work/test/execution-log.md"
if [[ ! -f "$LOG_FILE" ]]; then
  echo "runtime smoke failed: execution-log.md was not created" >&2
  cat "$TMP_DIR/codex-bash.stderr" >&2 || true
  exit 1
fi

grep -q 'CMD: printf "runtime-smoke"' "$LOG_FILE" || {
  echo "runtime smoke failed: command not recorded in execution-log.md" >&2
  cat "$LOG_FILE" >&2
  exit 1
}

grep -q 'runtime-smoke' "$LOG_FILE" || {
  echo "runtime smoke failed: command output not recorded in execution-log.md" >&2
  cat "$LOG_FILE" >&2
  exit 1
}

grep -q 'EXIT: ?' "$LOG_FILE" || {
  echo "runtime smoke failed: expected current Codex runtime to omit exit code and record EXIT: ?" >&2
  cat "$LOG_FILE" >&2
  exit 1
}

if ! jq -s -e '
  any(.[]; .type == "item.completed" and .item.type == "command_execution")
' "$TMP_DIR/codex-bash.jsonl" >/dev/null 2>&1; then
  echo "runtime smoke failed: Codex did not emit a command_execution item" >&2
  cat "$TMP_DIR/codex-bash.jsonl" >&2
  exit 1
fi

BLOCK_PROJ="$TMP_DIR/bash-guard-probe"
mkdir -p "$BLOCK_PROJ/.better-work/test/.active-sessions" "$BLOCK_PROJ/.better-work/test/history"
(
  cd "$BLOCK_PROJ"
  git init -q
)
cat > "$BLOCK_PROJ/.better-work/test/.active-sessions/999.json" <<'EOF'
{"run_dir":"history/v1/run-codex-a3f2-001-1234"}
EOF

HOME="$INSTALL_HOME" CODEX_HOME="$INSTALL_CODEX_HOME_DIR" "$SCRIPT_DIR/install-codex-hooks.sh" install --project "$BLOCK_PROJ" >/dev/null

credential_block_rc=0
printf '%s\n' 'Use the Bash tool exactly once to run exactly: mkdir -p .better-work/test/reference && printf "token=supersecrettoken123456" > .better-work/test/reference/notes.md. Do not run any other command. If it is blocked by a hook, stop immediately and reply with exactly BLOCKED.' | codex exec \
  --skip-git-repo-check \
  --enable codex_hooks \
  --ephemeral \
  --sandbox workspace-write \
  --json \
  -C "$BLOCK_PROJ" \
  - \
  > "$TMP_DIR/codex-block-credential.jsonl" \
  2> "$TMP_DIR/codex-block-credential.stderr" || credential_block_rc=$?

if [[ "$credential_block_rc" -ne 0 ]]; then
  echo "runtime smoke failed: credential block probe codex exec exited with $credential_block_rc" >&2
  cat "$TMP_DIR/codex-block-credential.stderr" >&2 || true
  exit 1
fi

if [[ "$(count_command_executions "$TMP_DIR/codex-block-credential.jsonl")" != "0" ]]; then
  echo "runtime smoke failed: credential block probe executed unexpected Bash commands after a blocked exact-once request" >&2
  cat "$TMP_DIR/codex-block-credential.jsonl" >&2
  exit 1
fi

if [[ -f "$BLOCK_PROJ/.better-work/test/reference/notes.md" ]]; then
  echo "runtime smoke failed: credential-scan probe wrote protected file despite embedded secret" >&2
  cat "$BLOCK_PROJ/.better-work/test/reference/notes.md" >&2
  exit 1
fi

grep -q 'Command blocked by PreToolUse hook' "$TMP_DIR/codex-block-credential.stderr" || {
  echo "runtime smoke failed: missing PreToolUse block evidence for credential-scan" >&2
  cat "$TMP_DIR/codex-block-credential.stderr" >&2
  exit 1
}

if [[ "$(final_agent_message "$TMP_DIR/codex-block-credential.jsonl")" != "BLOCKED" ]]; then
  echo "runtime smoke failed: credential block probe did not terminate with BLOCKED" >&2
  cat "$TMP_DIR/codex-block-credential.jsonl" >&2
  exit 1
fi

feedback_block_rc=0
printf '%s\n' 'Use the Bash tool exactly once to run exactly: printf "x" > .better-work/test/history/feedback-rules.json. Do not run any other command. If it is blocked by a hook, stop immediately and reply with exactly BLOCKED.' | codex exec \
  --skip-git-repo-check \
  --enable codex_hooks \
  --ephemeral \
  --sandbox workspace-write \
  --json \
  -C "$BLOCK_PROJ" \
  - \
  > "$TMP_DIR/codex-block-feedback.jsonl" \
  2> "$TMP_DIR/codex-block-feedback.stderr" || feedback_block_rc=$?

if [[ "$feedback_block_rc" -ne 0 ]]; then
  echo "runtime smoke failed: feedback-rules block probe codex exec exited with $feedback_block_rc" >&2
  cat "$TMP_DIR/codex-block-feedback.stderr" >&2 || true
  exit 1
fi

if [[ "$(count_command_executions "$TMP_DIR/codex-block-feedback.jsonl")" != "0" ]]; then
  echo "runtime smoke failed: feedback-rules block probe executed unexpected Bash commands after a blocked exact-once request" >&2
  cat "$TMP_DIR/codex-block-feedback.jsonl" >&2
  exit 1
fi

grep -q 'Command blocked by PreToolUse hook' "$TMP_DIR/codex-block-feedback.stderr" || {
  echo "runtime smoke failed: missing PreToolUse block evidence for feedback-rules guard" >&2
  cat "$TMP_DIR/codex-block-feedback.stderr" >&2
  exit 1
}

if [[ "$(final_agent_message "$TMP_DIR/codex-block-feedback.jsonl")" != "BLOCKED" ]]; then
  echo "runtime smoke failed: feedback-rules block probe did not terminate with BLOCKED" >&2
  cat "$TMP_DIR/codex-block-feedback.jsonl" >&2
  exit 1
fi

derived_block_rc=0
printf '%s\n' 'Use the Bash tool exactly once to run exactly: printf "x" > .better-work/test/status.md. Do not run any other command. If it is blocked by a hook, stop immediately and reply with exactly BLOCKED.' | codex exec \
  --skip-git-repo-check \
  --enable codex_hooks \
  --ephemeral \
  --sandbox workspace-write \
  --json \
  -C "$BLOCK_PROJ" \
  - \
  > "$TMP_DIR/codex-block-derived.jsonl" \
  2> "$TMP_DIR/codex-block-derived.stderr" || derived_block_rc=$?

if [[ "$derived_block_rc" -ne 0 ]]; then
  echo "runtime smoke failed: derived-view block probe codex exec exited with $derived_block_rc" >&2
  cat "$TMP_DIR/codex-block-derived.stderr" >&2 || true
  exit 1
fi

if [[ "$(count_command_executions "$TMP_DIR/codex-block-derived.jsonl")" != "0" ]]; then
  echo "runtime smoke failed: derived-view block probe executed unexpected Bash commands after a blocked exact-once request" >&2
  cat "$TMP_DIR/codex-block-derived.jsonl" >&2
  exit 1
fi

grep -q 'Command blocked by PreToolUse hook' "$TMP_DIR/codex-block-derived.stderr" || {
  echo "runtime smoke failed: missing PreToolUse block evidence for derived-view guard" >&2
  cat "$TMP_DIR/codex-block-derived.stderr" >&2
  exit 1
}

if [[ "$(final_agent_message "$TMP_DIR/codex-block-derived.jsonl")" != "BLOCKED" ]]; then
  echo "runtime smoke failed: derived-view block probe did not terminate with BLOCKED" >&2
  cat "$TMP_DIR/codex-block-derived.jsonl" >&2
  exit 1
fi

SESSION_PROJ="$TMP_DIR/session-guard-probe"
mkdir -p \
  "$SESSION_PROJ/.better-work/test/.active-sessions" \
  "$SESSION_PROJ/.better-work/test/history/v1/run-codex-a3f2-001-1234" \
  "$SESSION_PROJ/.better-work/test/history/v1/run-codex-b9c1-001-1234"
(
  cd "$SESSION_PROJ"
  git init -q
)

HOME="$INSTALL_HOME" CODEX_HOME="$INSTALL_CODEX_HOME_DIR" "$SCRIPT_DIR/install-codex-hooks.sh" install --project "$SESSION_PROJ" >/dev/null

session_guard_rc=0
cat <<'EOF' | codex exec \
  --skip-git-repo-check \
  --enable codex_hooks \
  --ephemeral \
  --sandbox workspace-write \
  --json \
  -C "$SESSION_PROJ" \
  - \
  > "$TMP_DIR/codex-session-guard.jsonl" \
  2> "$TMP_DIR/codex-session-guard.stderr" || session_guard_rc=$?
Use the Bash tool exactly four times in this order:
1. Run exactly: mkdir -p .better-work/test/.active-sessions .better-work/test/history/v1/run-codex-a3f2-001-1234 .better-work/test/history/v1/run-codex-b9c1-001-1234
2. Run exactly: printf "{\"tester_id\":\"codex-a3f2\",\"run_dir\":\"history/v1/run-codex-a3f2-001-1234\"}" > .better-work/test/.active-sessions/$PPID.json
3. Run exactly: printf "own-ok" > .better-work/test/history/v1/run-codex-a3f2-001-1234/own.txt
4. Run exactly: printf "blocked" > .better-work/test/history/v1/run-codex-b9c1-001-1234/other.txt
Do not run any other commands. If the fourth command is blocked by a hook, stop immediately and reply with exactly BLOCKED.
EOF

if [[ "$session_guard_rc" -ne 0 ]]; then
  echo "runtime smoke failed: session-write-guard probe codex exec exited with $session_guard_rc" >&2
  cat "$TMP_DIR/codex-session-guard.stderr" >&2 || true
  exit 1
fi

if [[ ! -f "$SESSION_PROJ/.better-work/test/history/v1/run-codex-a3f2-001-1234/own.txt" ]]; then
  echo "runtime smoke failed: session-write-guard probe did not allow own run write" >&2
  cat "$TMP_DIR/codex-session-guard.jsonl" >&2 || true
  cat "$TMP_DIR/codex-session-guard.stderr" >&2 || true
  exit 1
fi

if [[ -f "$SESSION_PROJ/.better-work/test/history/v1/run-codex-b9c1-001-1234/other.txt" ]]; then
  echo "runtime smoke failed: session-write-guard probe did not block cross-tester write" >&2
  cat "$TMP_DIR/codex-session-guard.jsonl" >&2 || true
  exit 1
fi

if ! jq -s -e '
  any(
    .[];
    .type == "item.completed"
    and .item.type == "command_execution"
    and ((.item.command // "") | contains("run-codex-a3f2-001-1234/own.txt"))
  )
' "$TMP_DIR/codex-session-guard.jsonl" >/dev/null 2>&1; then
  echo "runtime smoke failed: session-write-guard probe did not record own-run command execution" >&2
  cat "$TMP_DIR/codex-session-guard.jsonl" >&2
  exit 1
fi

if jq -s -e '
  any(
    .[];
    .type == "item.completed"
    and .item.type == "command_execution"
    and ((.item.command // "") | contains("run-codex-b9c1-001-1234/other.txt"))
  )
' "$TMP_DIR/codex-session-guard.jsonl" >/dev/null 2>&1; then
  echo "runtime smoke failed: session-write-guard probe executed the forbidden cross-tester write" >&2
  cat "$TMP_DIR/codex-session-guard.jsonl" >&2
  exit 1
fi

grep -q 'Command blocked by PreToolUse hook' "$TMP_DIR/codex-session-guard.stderr" || {
  echo "runtime smoke failed: missing PreToolUse block evidence for session-write-guard" >&2
  cat "$TMP_DIR/codex-session-guard.stderr" >&2
  exit 1
}

if [[ "$(count_command_executions "$TMP_DIR/codex-session-guard.jsonl")" != "3" ]]; then
  echo "runtime smoke failed: session-write-guard probe did not stop after the blocked fourth command" >&2
  cat "$TMP_DIR/codex-session-guard.jsonl" >&2
  exit 1
fi

if [[ "$(final_agent_message "$TMP_DIR/codex-session-guard.jsonl")" != "BLOCKED" ]]; then
  echo "runtime smoke failed: session-write-guard probe did not terminate with BLOCKED" >&2
  cat "$TMP_DIR/codex-session-guard.jsonl" >&2
  exit 1
fi

ADVISORY_PROJ="$TMP_DIR/post-bash-advisory-probe"
mkdir -p \
  "$ADVISORY_PROJ/.better-work/test/history/v1/run-codex-a3f2-001-1234" \
  "$ADVISORY_PROJ/.codex"
(
  cd "$ADVISORY_PROJ"
  git init -q
)

HOME="$INSTALL_HOME" CODEX_HOME="$INSTALL_CODEX_HOME_DIR" "$SCRIPT_DIR/install-codex-hooks.sh" install --project "$ADVISORY_PROJ" >/dev/null

checklist_advisory_rc=0
printf '%s\n' 'Use the Bash tool exactly once to run exactly: printf "{}" > .better-work/test/history/v1/run-codex-a3f2-001-1234/results.json. After it finishes, if you received any repository-hook advisory, reply with the exact English phrase immediately before "(auto-injected)"; otherwise reply with exactly NONE.' | codex exec \
  --skip-git-repo-check \
  --enable codex_hooks \
  --ephemeral \
  --sandbox workspace-write \
  --json \
  -C "$ADVISORY_PROJ" \
  - \
  > "$TMP_DIR/codex-checklist-advisory.jsonl" \
  2> "$TMP_DIR/codex-checklist-advisory.stderr" || checklist_advisory_rc=$?

if [[ "$checklist_advisory_rc" -ne 0 ]]; then
  echo "runtime smoke failed: post-test-checklist advisory probe codex exec exited with $checklist_advisory_rc" >&2
  cat "$TMP_DIR/codex-checklist-advisory.stderr" >&2 || true
  exit 1
fi

checklist_advisory_msg="$(final_agent_message "$TMP_DIR/codex-checklist-advisory.jsonl")"
if [[ "$checklist_advisory_msg" != *"post-completion checklist"* ]]; then
  echo "runtime smoke failed: post-test-checklist advisory was not model-visible" >&2
  cat "$TMP_DIR/codex-checklist-advisory.jsonl" >&2
  exit 1
fi

results_advisory_rc=0
printf '%s\n' 'Use the Bash tool exactly once to run exactly: printf "%s" "{\"version\":\"1.0.0\",\"run_id\":\"run-1\",\"mode\":\"targeted\",\"summary\":\"bad\",\"coverage\":null,\"items\":[{\"id\":\"bad-id\",\"status\":\"pass\",\"assertion_field\":\"\",\"evidence_level\":\"indirect\"}]}" > .better-work/test/history/v1/run-codex-a3f2-001-1234/results.json. After it finishes, if you received any repository-hook advisory, reply with the exact Chinese phrase immediately before "发现以下问题"; otherwise reply with exactly NONE.' | codex exec \
  --skip-git-repo-check \
  --enable codex_hooks \
  --ephemeral \
  --sandbox workspace-write \
  --json \
  -C "$ADVISORY_PROJ" \
  - \
  > "$TMP_DIR/codex-results-advisory.jsonl" \
  2> "$TMP_DIR/codex-results-advisory.stderr" || results_advisory_rc=$?

if [[ "$results_advisory_rc" -ne 0 ]]; then
  echo "runtime smoke failed: results-validation advisory probe codex exec exited with $results_advisory_rc" >&2
  cat "$TMP_DIR/codex-results-advisory.stderr" >&2 || true
  exit 1
fi

results_advisory_msg="$(final_agent_message "$TMP_DIR/codex-results-advisory.jsonl")"
if [[ "$results_advisory_msg" != *"字段检查"* ]]; then
  echo "runtime smoke failed: results-validation advisory was not model-visible" >&2
  cat "$TMP_DIR/codex-results-advisory.jsonl" >&2
  exit 1
fi

registration_advisory_rc=0
printf '%s\n' 'Use the Bash tool exactly once to run exactly: printf "# draft" > .better-work/test/history/v1/run-codex-a3f2-001-1234/strategy-plan.md. After it finishes, if you received any repository-hook advisory, reply with the exact English label immediately before the first colon; otherwise reply with exactly NONE.' | codex exec \
  --skip-git-repo-check \
  --enable codex_hooks \
  --ephemeral \
  --sandbox workspace-write \
  --json \
  -C "$ADVISORY_PROJ" \
  - \
  > "$TMP_DIR/codex-registration-advisory.jsonl" \
  2> "$TMP_DIR/codex-registration-advisory.stderr" || registration_advisory_rc=$?

if [[ "$registration_advisory_rc" -ne 0 ]]; then
  echo "runtime smoke failed: registration-gate advisory probe codex exec exited with $registration_advisory_rc" >&2
  cat "$TMP_DIR/codex-registration-advisory.stderr" >&2 || true
  exit 1
fi

registration_advisory_msg="$(final_agent_message "$TMP_DIR/codex-registration-advisory.jsonl")"
if [[ "$registration_advisory_msg" != *"Registration"* && "$registration_advisory_msg" != *"gate"* ]]; then
  echo "runtime smoke failed: registration-gate advisory was not model-visible" >&2
  cat "$TMP_DIR/codex-registration-advisory.jsonl" >&2
  exit 1
fi

WRITE_PROJ="$TMP_DIR/write-probe"
mkdir -p \
  "$WRITE_PROJ/.codex" \
  "$WRITE_PROJ/.better-work/test/reference" \
  "$WRITE_PROJ/.better-work/test/history/v1/run-codex-a3f2-001-1234"
(
  cd "$WRITE_PROJ"
  git init -q
)

HOME="$INSTALL_HOME" CODEX_HOME="$INSTALL_CODEX_HOME_DIR" "$SCRIPT_DIR/install-codex-hooks.sh" install --project "$WRITE_PROJ" >/dev/null

write_block_rc=0
printf '%s\n' 'Create the file .better-work/test/reference/notes.md containing exactly token=supersecrettoken123456. You must not execute any shell command or Bash command. Use only the built-in file editing capability. If it is blocked by a hook, stop immediately and reply with exactly BLOCKED.' | codex exec \
  --skip-git-repo-check \
  --enable codex_hooks \
  --ephemeral \
  --sandbox workspace-write \
  --json \
  -C "$WRITE_PROJ" \
  - \
  > "$TMP_DIR/codex-write-block.jsonl" \
  2> "$TMP_DIR/codex-write-block.stderr" || write_block_rc=$?

if [[ "$write_block_rc" -ne 0 ]]; then
  echo "runtime smoke failed: native Write credential block probe codex exec exited with $write_block_rc" >&2
  cat "$TMP_DIR/codex-write-block.stderr" >&2 || true
  exit 1
fi

if [[ -f "$WRITE_PROJ/.better-work/test/reference/notes.md" ]]; then
  echo "runtime smoke failed: native Write credential probe wrote protected file despite embedded secret" >&2
  cat "$WRITE_PROJ/.better-work/test/reference/notes.md" >&2
  exit 1
fi

if jq -s -e '
  any(
    .[];
    .type == "item.completed"
    and .item.type == "file_change"
    and any(.item.changes[]?; (.path // "") | contains("/.better-work/test/reference/notes.md"))
  )
' "$TMP_DIR/codex-write-block.jsonl" >/dev/null 2>&1; then
  echo "runtime smoke failed: native Write credential probe still emitted a file_change for the blocked edit" >&2
  cat "$TMP_DIR/codex-write-block.jsonl" >&2
  exit 1
fi

grep -q 'Command blocked by PreToolUse hook' "$TMP_DIR/codex-write-block.stderr" || {
  echo "runtime smoke failed: missing PreToolUse block evidence for native Write credential-scan" >&2
  cat "$TMP_DIR/codex-write-block.stderr" >&2
  exit 1
}

if [[ "$(final_agent_message "$TMP_DIR/codex-write-block.jsonl")" != "BLOCKED" ]]; then
  echo "runtime smoke failed: native Write credential block probe did not terminate with BLOCKED" >&2
  cat "$TMP_DIR/codex-write-block.jsonl" >&2
  exit 1
fi

write_results_content="$(jq -c . "$SCRIPT_DIR/fixtures/results-pass-no-baseline.json")"
write_advisory_rc=0
cat <<EOF | codex exec \
  --skip-git-repo-check \
  --enable codex_hooks \
  --ephemeral \
  --sandbox workspace-write \
  --json \
  -C "$WRITE_PROJ" \
  - \
  > "$TMP_DIR/codex-write-advisory.jsonl" \
  2> "$TMP_DIR/codex-write-advisory.stderr" || write_advisory_rc=$?
Create the file .better-work/test/history/v1/run-codex-a3f2-001-1234/results.json containing exactly:
$write_results_content
You must not execute any shell command or Bash command. Use only the built-in file editing capability.
After it finishes, if you received any repository-hook advisory containing the substring comparison_baseline, reply with exactly BASELINE; otherwise reply with exactly NONE.
EOF

if [[ "$write_advisory_rc" -ne 0 ]]; then
  echo "runtime smoke failed: native Write results-validation probe codex exec exited with $write_advisory_rc" >&2
  cat "$TMP_DIR/codex-write-advisory.stderr" >&2 || true
  exit 1
fi

if [[ ! -f "$WRITE_PROJ/.better-work/test/history/v1/run-codex-a3f2-001-1234/results.json" ]]; then
  echo "runtime smoke failed: native Write advisory probe did not create results.json" >&2
  cat "$TMP_DIR/codex-write-advisory.jsonl" >&2
  exit 1
fi

if ! jq -s -e '
  any(
    .[];
    .type == "item.completed"
    and .item.type == "file_change"
    and any(.item.changes[]?; (.path // "") | contains("/.better-work/test/history/v1/run-codex-a3f2-001-1234/results.json"))
  )
' "$TMP_DIR/codex-write-advisory.jsonl" >/dev/null 2>&1; then
  echo "runtime smoke failed: native Write advisory probe did not emit a results.json file_change item" >&2
  cat "$TMP_DIR/codex-write-advisory.jsonl" >&2
  exit 1
fi

if [[ "$(final_agent_message "$TMP_DIR/codex-write-advisory.jsonl")" != "BASELINE" ]]; then
  echo "runtime smoke failed: native Write results-validation advisory was not model-visible" >&2
  cat "$TMP_DIR/codex-write-advisory.jsonl" >&2
  exit 1
fi

POST_FAIL_PROJ="$TMP_DIR/post-bash-fail-probe"
mkdir -p "$POST_FAIL_PROJ/.codex" "$POST_FAIL_PROJ/bin"
(
  cd "$POST_FAIL_PROJ"
  git init -q
)

cat > "$POST_FAIL_PROJ/bin/post-fail.sh" <<'EOF'
#!/bin/bash
printf 'post-fail-hook-ran\n' > "$(dirname "$0")/post-fail-ran.log"
echo "post-bash-probe failure" >&2
exit 2
EOF
chmod +x "$POST_FAIL_PROJ/bin/post-fail.sh"

cat > "$POST_FAIL_PROJ/.codex/hooks.json" <<EOF
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "$POST_FAIL_PROJ/bin/post-fail.sh",
            "statusMessage": "probe post-fail"
          }
        ]
      }
    ]
  }
}
EOF

post_fail_rc=0
printf '%s\n' 'Use the Bash tool exactly once to run exactly: printf "post-fail-probe". After it finishes, reply with exactly OK.' | codex exec \
  --skip-git-repo-check \
  --enable codex_hooks \
  --ephemeral \
  --sandbox workspace-write \
  --json \
  -C "$POST_FAIL_PROJ" \
  - \
  > "$TMP_DIR/codex-post-fail.jsonl" \
  2> "$TMP_DIR/codex-post-fail.stderr" || post_fail_rc=$?

if [[ "$post_fail_rc" -ne 0 ]]; then
  echo "runtime smoke failed: PostToolUse/Bash exit 2 probe unexpectedly failed the Codex command path" >&2
  cat "$TMP_DIR/codex-post-fail.stderr" >&2 || true
  exit 1
fi

if [[ ! -f "$POST_FAIL_PROJ/bin/post-fail-ran.log" ]]; then
  echo "runtime smoke failed: PostToolUse/Bash nonzero probe did not execute its hook command" >&2
  cat "$TMP_DIR/codex-post-fail.jsonl" >&2
  exit 1
fi

grep -q 'post-fail-hook-ran' "$POST_FAIL_PROJ/bin/post-fail-ran.log" || {
  echo "runtime smoke failed: PostToolUse/Bash nonzero probe hook marker was not written" >&2
  cat "$POST_FAIL_PROJ/bin/post-fail-ran.log" >&2
  exit 1
}

if [[ "$(final_agent_message "$TMP_DIR/codex-post-fail.jsonl")" != "OK" ]]; then
  echo "runtime smoke failed: PostToolUse/Bash exit 2 probe did not complete the command path successfully" >&2
  cat "$TMP_DIR/codex-post-fail.jsonl" >&2
  exit 1
fi

echo "codex runtime smoke passed"
echo "observed baseline: project hooks.json + PostToolUse/Bash works; PostToolUse/Bash exit 2 still runs the hook command but does not fail the command path, and stderr surfacing is not treated as stable; PostToolUse/Bash additionalContext is model-visible for post-test-checklist/results-validation/registration-gate; PreToolUse/Bash blocks landed for inline credentials, feedback-rules, derived views, and cross-tester run writes; current runtime omits exit code; matcher=Write is runtime-verified on codex-cli 0.125.0 for built-in file_change/apply_patch, including PreToolUse blocking and PostToolUse advisory visibility"

#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TMP_DIR="$(mktemp -d)"
PROJECT_DIR="$TMP_DIR/project"
HOME_DIR="$TMP_DIR/home"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p \
  "$PROJECT_DIR/.better-work/test/.active-sessions" \
  "$PROJECT_DIR/.better-work/test/history" \
  "$PROJECT_DIR/.better-work/test/history/v1/run-codex-a3f2-001-1234" \
  "$PROJECT_DIR/.better-work/test/history/v1/run-codex-b9c1-001-1234" \
  "$PROJECT_DIR/.codex" \
  "$HOME_DIR/.codex"

cat > "$PROJECT_DIR/.better-work/test/.active-sessions/999.json" <<'EOF'
{"run_dir":"history/v1/run-codex-a3f2-001-1234"}
EOF

cat > "$PROJECT_DIR/.better-work/test/.active-sessions/$$.json" <<'EOF'
{"tester_id":"codex-a3f2","run_dir":"history/v1/run-codex-a3f2-001-1234"}
EOF

cat > "$PROJECT_DIR/.better-work/test/.active-sessions/$PPID.json" <<'EOF'
{"tester_id":"codex-a3f2","run_dir":"history/v1/run-codex-a3f2-001-1234"}
EOF

run_expect_block() {
  local script="$1"
  local command="$2"
  local stderr_file="$TMP_DIR/stderr.txt"
  local rc=0

  jq -n --arg cwd "$PROJECT_DIR" --arg command "$command" '{
    tool_name: "Bash",
    cwd: $cwd,
    tool_input: {command: $command}
  }' | "$script" >/dev/null 2>"$stderr_file" || rc=$?

  if [[ "$rc" -ne 2 ]]; then
    echo "expected block from $script, got exit $rc" >&2
    cat "$stderr_file" >&2 || true
    exit 1
  fi
}

run_expect_allow() {
  local script="$1"
  local command="$2"
  jq -n --arg cwd "$PROJECT_DIR" --arg command "$command" '{
    tool_name: "Bash",
    cwd: $cwd,
    tool_input: {command: $command}
  }' | "$script" >/dev/null
}

run_expect_block "$SCRIPT_DIR/codex/credential-scan.sh" 'printf "token=supersecrettoken123456" > .better-work/test/reference/notes.md'
run_expect_allow "$SCRIPT_DIR/codex/credential-scan.sh" 'printf "token=<redacted>" > .better-work/test/reference/notes.md'
run_expect_allow "$SCRIPT_DIR/codex/credential-scan.sh" 'printf "token=supersecrettoken123456" > ./notes.md'

run_expect_block "$SCRIPT_DIR/codex/feedback-rules-guard.sh" 'printf "x" > .better-work/test/history/feedback-rules.json'
run_expect_allow "$SCRIPT_DIR/codex/feedback-rules-guard.sh" 'cat .better-work/test/history/feedback-rules.json'
run_expect_allow "$SCRIPT_DIR/codex/feedback-rules-guard.sh" 'printf "x" > .better-work/test/history/v1/run-codex-a3f2-001-1234/feedback-rules.json'

run_expect_block "$SCRIPT_DIR/codex/derived-view-guard.sh" 'printf "x" > .better-work/test/status.md'
run_expect_allow "$SCRIPT_DIR/codex/derived-view-guard.sh" 'cat .better-work/test/status.md'
run_expect_allow "$SCRIPT_DIR/codex/derived-view-guard.sh" 'printf "x" > .better-work/test/history/v1/run-codex-a3f2-001-1234/status.md'

run_expect_allow "$SCRIPT_DIR/codex/session-write-guard.sh" 'printf "x" > .better-work/test/history/v1/run-codex-a3f2-001-1234/results.json'
run_expect_block "$SCRIPT_DIR/codex/session-write-guard.sh" 'printf "x" > .better-work/test/history/v1/run-codex-b9c1-001-1234/results.json'
run_expect_allow "$SCRIPT_DIR/codex/session-write-guard.sh" 'cat .better-work/test/history/v1/run-codex-b9c1-001-1234/results.json'

cat > "$HOME_DIR/.codex/config.toml" <<'EOF'
[features]
hooks = true
EOF

HOME="$HOME_DIR" "$SCRIPT_DIR/install-codex-hooks.sh" install --project "$PROJECT_DIR" >/dev/null

jq -e '
  any(.hooks.PreToolUse[]?; .matcher == "Bash" and any(.hooks[]?; (.statusMessage // "") == "better-test: credential-scan"))
' "$PROJECT_DIR/.codex/hooks.json" >/dev/null

jq -e '
  any(.hooks.PreToolUse[]?; .matcher == "Bash" and any(.hooks[]?; (.statusMessage // "") == "better-test: feedback-rules-guard"))
' "$PROJECT_DIR/.codex/hooks.json" >/dev/null

jq -e '
  any(.hooks.PreToolUse[]?; .matcher == "Bash" and any(.hooks[]?; (.statusMessage // "") == "better-test: derived-view-guard"))
' "$PROJECT_DIR/.codex/hooks.json" >/dev/null

jq -e '
  any(.hooks.PreToolUse[]?; .matcher == "Bash" and any(.hooks[]?; (.statusMessage // "") == "better-test: session-write-guard"))
' "$PROJECT_DIR/.codex/hooks.json" >/dev/null

echo "codex bash guard tests passed"

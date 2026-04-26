#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_FIXTURE="$SCRIPT_DIR/fixtures/claude/post-bash.json"
CODEX_FIXTURE="$SCRIPT_DIR/fixtures/codex/post-bash.json"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

run_fixture() {
  local label="$1"
  local fixture="$2"
  shift 2
  local project_dir="$TMP_DIR/$label"
  local log_file="$project_dir/.better-work/test/execution-log.md"

  mkdir -p "$project_dir/.better-work/test"

  jq --arg cwd "$project_dir" '.cwd = $cwd' "$fixture" | "$@" >/dev/null

  if [[ ! -f "$log_file" ]]; then
    echo "missing execution log for $label: $log_file" >&2
    exit 1
  fi
}

normalize_log() {
  local log_file="$1"
  sed -E 's/^## \[[^]]+\] Bash$/## [TIMESTAMP] Bash/' "$log_file"
}

run_fixture "claude-direct" "$CLAUDE_FIXTURE" "$SCRIPT_DIR/execution-log.sh"
run_fixture "claude-gate" "$CLAUDE_FIXTURE" "$SCRIPT_DIR/gate.sh" "post-bash"
run_fixture "codex-direct" "$CODEX_FIXTURE" "$SCRIPT_DIR/codex/execution-log.sh"

CLAUDE_DIRECT_LOG="$TMP_DIR/claude-direct/.better-work/test/execution-log.md"
CLAUDE_GATE_LOG="$TMP_DIR/claude-gate/.better-work/test/execution-log.md"
CODEX_DIRECT_LOG="$TMP_DIR/codex-direct/.better-work/test/execution-log.md"

normalize_log "$CLAUDE_DIRECT_LOG" > "$TMP_DIR/claude-direct.norm"
normalize_log "$CLAUDE_GATE_LOG" > "$TMP_DIR/claude-gate.norm"
normalize_log "$CODEX_DIRECT_LOG" > "$TMP_DIR/codex-direct.norm"

cmp -s "$TMP_DIR/claude-direct.norm" "$TMP_DIR/claude-gate.norm" || {
  echo "gate.sh post-bash changed Claude execution-log side effects" >&2
  diff -u "$TMP_DIR/claude-direct.norm" "$TMP_DIR/claude-gate.norm" >&2 || true
  exit 1
}

cmp -s "$TMP_DIR/claude-direct.norm" "$TMP_DIR/codex-direct.norm" || {
  echo "Codex execution-log output diverges from Claude output" >&2
  diff -u "$TMP_DIR/claude-direct.norm" "$TMP_DIR/codex-direct.norm" >&2 || true
  exit 1
}

grep -q 'CMD: printf "hello from codex"' "$CLAUDE_DIRECT_LOG"
grep -q 'EXIT: 0' "$CLAUDE_DIRECT_LOG"
grep -q 'hello from codex' "$CLAUDE_DIRECT_LOG"

echo "execution-log parity tests passed"

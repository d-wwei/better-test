#!/bin/bash
# better-test L1 Hook: Execution Log Auto-Recording
# Records every Bash command + output to .better-work/test/execution-log.md
# PostToolUse on Bash
#
# This creates an unforgeable execution record that L2 sub-agent uses
# to verify if the main agent actually executed what it claims.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Shared rule keeps Claude and Codex append semantics aligned.
. "$SCRIPT_DIR/lib/common.sh"
. "$SCRIPT_DIR/lib/rules/execution-log.sh"

INPUT=$(cat)
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

if [[ "$TOOL_NAME" != "Bash" ]]; then
  exit 0
fi

CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
STDOUT=$(printf '%s' "$INPUT" | jq -r '.tool_response.stdout // .tool_response.output // .tool_response // empty' 2>/dev/null | head -200)
EXIT_CODE=$(printf '%s' "$INPUT" | jq -r '.tool_response.exitCode // "?"' 2>/dev/null)

bt_record_execution_log "$CWD" "$COMMAND" "$STDOUT" "$EXIT_CODE"

exit 0

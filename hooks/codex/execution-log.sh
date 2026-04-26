#!/bin/bash
# better-test L1 Hook: Codex execution-log entrypoint
# PostToolUse on Bash in Codex currently maps to shell command execution.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOKS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$HOOKS_DIR/lib/common.sh"
. "$HOOKS_DIR/lib/rules/execution-log.sh"

INPUT=$(cat)
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // .toolName // empty' 2>/dev/null)

if [[ -n "$TOOL_NAME" && "$TOOL_NAME" != "Bash" ]]; then
  exit 0
fi

CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // .working_directory // .tool_input.cwd // empty' 2>/dev/null)
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // .tool_input.cmd // .command // empty' 2>/dev/null)
STDOUT=$(printf '%s' "$INPUT" | jq -r '
  try (
    if (.tool_response | type) == "string" then
      .tool_response
    elif (.tool_response | type) == "object" then
      .tool_response.stdout // .tool_response.output // empty
    elif (.tool_output | type) == "object" then
      .tool_output.stdout // .tool_output.output // empty
    else
      .aggregated_output // .output // empty
    end
  ) catch empty
' 2>/dev/null | head -200)
EXIT_CODE=$(printf '%s' "$INPUT" | jq -r '
  try (
    if (.tool_response | type) == "object" then
      .tool_response.exit_code // .tool_response.exitCode // "?"
    elif (.tool_output | type) == "object" then
      .tool_output.exit_code // .tool_output.exitCode // "?"
    else
      .exit_code // "?"
    end
  ) catch "?"
' 2>/dev/null)

bt_record_execution_log "$CWD" "$COMMAND" "$STDOUT" "$EXIT_CODE"

exit 0

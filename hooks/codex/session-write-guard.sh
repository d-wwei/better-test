#!/bin/bash
# better-test L1 Hook: Codex session-write-guard
# PreToolUse on Bash for shell write paths that target run directories.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOKS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$HOOKS_DIR/lib/common.sh"
. "$HOOKS_DIR/lib/rules/session-write-guard.sh"

INPUT=$(cat)
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // .toolName // empty' 2>/dev/null)

if [[ -n "$TOOL_NAME" && "$TOOL_NAME" != "Bash" ]]; then
  exit 0
fi

CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // .working_directory // .tool_input.cwd // empty' 2>/dev/null)
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // .tool_input.cmd // .command // empty' 2>/dev/null)

while IFS= read -r target; do
  [[ -n "$target" ]] || continue
  bt_session_write_guard_path "$target" || exit $?
done < <(bt_extract_bash_write_targets "$COMMAND" "$CWD")

exit 0

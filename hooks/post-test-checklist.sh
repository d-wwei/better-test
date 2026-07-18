#!/bin/bash
# better-test L1 Hook: Post-Test Completion Checklist
# Detects when results.json is written and injects a reminder of remaining steps.
# PostToolUse on Write
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib/common.sh"
. "$SCRIPT_DIR/lib/rules/post-test-checklist.sh"

INPUT=$(cat)
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)

if [[ "$TOOL_NAME" != "Write" ]]; then
  exit 0
fi

bt_post_test_checklist_output "$FILE_PATH" "$CWD"
exit 0

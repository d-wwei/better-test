#!/bin/bash
# better-test L1 Hook: results.json Field Validation
# Checks required fields when results.json is written.
# PostToolUse on Write
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib/rules/results-validation.sh"

INPUT=$(cat)
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
CONTENT=$(printf '%s' "$INPUT" | jq -r '.tool_input.content // empty' 2>/dev/null)

if [[ "$TOOL_NAME" != "Write" ]]; then
  exit 0
fi

bt_results_validation_output "$FILE_PATH" "$CONTENT"
exit 0

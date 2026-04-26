#!/bin/bash
# better-test L1 Hook: Credential Scan
# Blocks writes to .better-work/test/ that contain credential patterns.
# PreToolUse on Edit|Write
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib/rules/credential-scan.sh"

INPUT=$(cat)
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

if [[ "$FILE_PATH" != *".better-work/test/"* ]] && [[ "$FILE_PATH" != *".better-work/test\\"* ]]; then
  exit 0
fi

if [[ "$TOOL_NAME" == "Write" ]]; then
  CONTENT=$(printf '%s' "$INPUT" | jq -r '.tool_input.content // empty' 2>/dev/null)
elif [[ "$TOOL_NAME" == "Edit" ]]; then
  CONTENT=$(printf '%s' "$INPUT" | jq -r '.tool_input.new_string // empty' 2>/dev/null)
else
  exit 0
fi

bt_credential_scan_content "$CONTENT" "write to $FILE_PATH"
exit $?

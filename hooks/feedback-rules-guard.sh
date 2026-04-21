#!/bin/bash
# better-test L1 Hook: feedback-rules.json Write Protection
# Blocks direct edits to feedback-rules.json. Must use /better-test feedback command instead.
# PreToolUse on Edit|Write
set -e

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Check if the target file is feedback-rules.json
if echo "$FILE_PATH" | grep -q 'feedback-rules\.json'; then
  echo "better-test L1 Hook: Direct edit to feedback-rules.json is blocked. This file is auto-maintained. Use '/better-test feedback <id> <verdict>' to update rules, or '/better-test feedback <id> revoke' to retract." >&2
  exit 2
fi

exit 0

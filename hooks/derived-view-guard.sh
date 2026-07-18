#!/bin/bash
# better-test L1 Hook: Derived View Write Protection
# Blocks writes to project-level aggregation files unless /better-test merge is in progress.
# These files are derived views — only coordinator writes them during merge.
# PreToolUse on Edit|Write
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib/common.sh"
. "$SCRIPT_DIR/lib/rules/derived-view-guard.sh"

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

bt_derived_view_guard_path "$FILE_PATH" "$CWD"
exit $?

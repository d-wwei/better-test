#!/bin/bash
# better-test L1 Hook: feedback-rules.json Write Protection
# Blocks direct edits to feedback-rules.json unless /better-test merge is in progress.
# This file is a derived view — rebuilt by merge or single-tester completion.
# PreToolUse on Edit|Write
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib/rules/feedback-rules-guard.sh"

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

bt_feedback_rules_guard_path "$FILE_PATH"
exit $?

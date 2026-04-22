#!/bin/bash
# better-test L1 Hook: feedback-rules.json Write Protection
# Blocks direct edits to feedback-rules.json unless /better-test merge is in progress.
# This file is a derived view — rebuilt by merge or single-tester completion.
# PreToolUse on Edit|Write
set -e

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Check if the target file is feedback-rules.json
if echo "$FILE_PATH" | grep -q 'feedback-rules\.json'; then
  # Allow writes inside run-*/ or merge-*/ directories (tester/coordinator workspace)
  if echo "$FILE_PATH" | grep -qE '/(run-|merge-)'; then
    exit 0
  fi

  # Extract .better-work/test base path
  TEST_BASE=$(echo "$FILE_PATH" | sed 's|\(.*\.better-work/test\)/.*|\1|')
  # Also try: path might be .better-work/test/history/feedback-rules.json
  if [[ ! -d "$TEST_BASE" ]]; then
    TEST_BASE=$(echo "$FILE_PATH" | sed 's|\(.*\.better-work\)/.*|\1/test|')
  fi

  # Bypass 1: merge lockfile exists → coordinator is merging, allow
  if [[ -f "$TEST_BASE/.merge-in-progress" ]]; then
    exit 0
  fi

  # Bypass 2: no active sessions → not in parallel testing, allow
  SESSION_DIR="$TEST_BASE/.active-sessions"
  if [[ ! -d "$SESSION_DIR" ]] || [[ -z "$(ls -A "$SESSION_DIR" 2>/dev/null)" ]]; then
    exit 0
  fi

  # Active sessions exist + no merge lockfile → block
  echo "better-test L1 Hook: Direct edit to feedback-rules.json is blocked. Active tester sessions detected — use /better-test merge after all testers complete. During testing, write feedback to run-*/feedback/ instead." >&2
  exit 2
fi

exit 0

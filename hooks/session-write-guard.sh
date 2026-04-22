#!/bin/bash
# better-test L1 Hook: Session-Based Cross-Tester Write Guard (Phase 2)
# Uses PID-keyed session files to identify which tester is writing.
# Blocks writes to other testers' run directories.
#
# Session registration: strategy-workflow Step 0 writes:
#   .better-work/test/.active-sessions/<claude-pid>.json
#   {"tester_id":"claude-a3f2","run_dir":"history/v1.4.28/run-claude-a3f2-002-..."}
#
# PreToolUse on Edit|Write
set -e

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Only check writes to .better-work paths inside run-*/ directories
if [[ "$FILE_PATH" != *".better-work/"* ]]; then
  exit 0
fi

# Only guard run-*/ directories (cross-tester isolation)
if ! echo "$FILE_PATH" | grep -qE '/run-[^/]+-[0-9]+-'; then
  exit 0
fi

# Extract the target run directory name
TARGET_RUN=$(echo "$FILE_PATH" | grep -oE 'run-[^/]+' | head -1)

# Find session file for this Claude Code process
# Try PPID first (direct parent = Claude Code), then grandparent (if intermediate shell)
BETTER_WORK_TEST=$(echo "$FILE_PATH" | sed 's|\(.*\.better-work/test\)/.*|\1|')
SESSION_DIR="$BETTER_WORK_TEST/.active-sessions"
SESSION_FILE=""

if [[ -d "$SESSION_DIR" ]]; then
  for PID in $PPID $(ps -o ppid= -p $PPID 2>/dev/null | tr -d ' '); do
    if [[ -f "$SESSION_DIR/$PID.json" ]]; then
      SESSION_FILE="$SESSION_DIR/$PID.json"
      break
    fi
  done
fi

# No session file found — not registered yet or session detection failed
# Allow write (don't block registration itself)
if [[ -z "$SESSION_FILE" ]]; then
  exit 0
fi

# Read my allowed run directory
MY_RUN_DIR=$(jq -r '.run_dir // empty' < "$SESSION_FILE")
if [[ -z "$MY_RUN_DIR" ]]; then
  exit 0  # No run_dir in session — allow (might be coordinator)
fi

# Extract just the run directory name from the full path
MY_RUN=$(echo "$MY_RUN_DIR" | grep -oE 'run-[^/]+' | head -1)

# Check: is the target run directory mine?
if [[ -n "$MY_RUN" ]] && [[ "$TARGET_RUN" != "$MY_RUN" ]]; then
  MY_TESTER=$(jq -r '.tester_id // "unknown"' < "$SESSION_FILE")
  echo "better-test L1 Hook: Cross-tester write blocked. Tester '$MY_TESTER' attempted to write to '$TARGET_RUN' but is only allowed to write to '$MY_RUN'. Each tester must write exclusively to their own run directory." >&2
  exit 2
fi

exit 0

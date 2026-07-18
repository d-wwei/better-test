#!/bin/bash
# better-test L1 Hook: Session-Based Cross-Tester Write Guard (Phase 2)
# Uses PID-keyed session files to identify which tester is writing.
# Blocks writes to other testers' run directories.
# PreToolUse on Edit|Write
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib/common.sh"
. "$SCRIPT_DIR/lib/rules/session-write-guard.sh"

INPUT=$(cat)
FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)

bt_session_write_guard_path "$FILE_PATH" "$CWD"
exit $?

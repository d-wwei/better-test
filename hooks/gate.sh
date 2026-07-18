#!/bin/bash
# better-test L1 Hook Gate — Universal Entry Point
#
# Single entry point for all better-test hooks. Detects if the current project
# uses better-test, then dispatches to individual hook scripts.
#
# Usage in ~/.claude/settings.json:
#   "command": "~/.claude/skills/better-test/hooks/gate.sh <event>"
#
# Events: pre-edit-write | post-bash | post-write
#
# Non-better-test projects: exits immediately (~10ms overhead).
# Future: when better-work introduces a skill-dispatcher, gate.sh becomes
# one skill's dispatch function within the universal dispatcher.
# NOTE: no `set -e` — we must survive sub-hook exit 2 (block) without dying
EVENT="$1"
if [[ -z "$EVENT" ]]; then
  exit 0
fi

# Read stdin (hook input JSON) — need to pass it to sub-hooks
INPUT=$(cat)

HOOKS_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$HOOKS_DIR/lib/common.sh"

# Extract CWD from hook input
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
if [[ -z "$CWD" ]]; then
  exit 0
fi

if ! bt_resolve_test_dir "$CWD" >/dev/null; then
  exit 0
fi

# Dispatch to individual hooks based on event type
# Collect all outputs — if any hook blocks (exit 2), gate blocks.
# If any hook returns additionalContext, merge them.
BLOCK=false
BLOCK_MSG=""
CONTEXTS=""

dispatch_hook() {
  local script="$1"
  if [[ ! -x "$script" ]]; then
    return
  fi

  local stderr_file="/tmp/gate-hook-stderr-$$-$(basename "$script")"
  local result exit_code

  # Run sub-hook, capture stdout and stderr separately.
  # No set -e, so non-zero exits don't kill gate. Capture exit code explicitly.
  result=$(echo "$INPUT" | "$script" 2>"$stderr_file")
  exit_code=$?

  if [[ $exit_code -eq 2 ]]; then
    # Intentional block by sub-hook
    BLOCK=true
    BLOCK_MSG=$(cat "$stderr_file" 2>/dev/null)
  elif [[ $exit_code -ne 0 ]]; then
    # Unexpected error (syntax error, jq failure, etc.) — fail-closed, not fail-open
    BLOCK=true
    BLOCK_MSG="better-test gate: sub-hook $(basename "$script") exited with unexpected code $exit_code. Blocking as safety precaution. stderr: $(cat "$stderr_file" 2>/dev/null)"
  elif [[ -n "$result" ]]; then
    local ctx
    ctx=$(echo "$result" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)
    if [[ -n "$ctx" ]]; then
      CONTEXTS="${CONTEXTS}${ctx}\n\n"
    fi
  fi

  rm -f "$stderr_file"
}

case "$EVENT" in
  pre-edit-write)
    dispatch_hook "$HOOKS_DIR/credential-scan.sh"
    dispatch_hook "$HOOKS_DIR/feedback-rules-guard.sh"
    dispatch_hook "$HOOKS_DIR/derived-view-guard.sh"
    dispatch_hook "$HOOKS_DIR/session-write-guard.sh"
    ;;
  post-bash)
    dispatch_hook "$HOOKS_DIR/execution-log.sh"
    ;;
  post-write)
    dispatch_hook "$HOOKS_DIR/registration-gate.sh"
    dispatch_hook "$HOOKS_DIR/post-test-checklist.sh"
    dispatch_hook "$HOOKS_DIR/results-validation.sh"
    ;;
  *)
    exit 0
    ;;
esac

# If any hook blocked, block the whole gate
if [[ "$BLOCK" == "true" ]]; then
  echo "$BLOCK_MSG" >&2
  exit 2
fi

# If any hook returned additionalContext, merge and output
if [[ -n "$CONTEXTS" ]]; then
  jq -n --arg ctx "$CONTEXTS" '{
    hookSpecificOutput: {
      hookEventName: "PostToolUse",
      additionalContext: $ctx
    }
  }'
fi

exit 0

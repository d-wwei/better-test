#!/bin/bash
# Better Test Codex Stop hook. Portable validate-run.py remains authoritative.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOKS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$HOOKS_DIR/lib/common.sh"
. "$HOOKS_DIR/lib/rules/stop-gate.sh"

if [[ "${BETTER_TEST_STOP_GATE:-1}" == "0" ]]; then
  exit 0
fi

INPUT=$(cat)
if ! printf '%s' "$INPUT" | jq -e 'type == "object"' >/dev/null 2>&1; then
  bt_stop_gate_log "ERROR" "INVALID_PAYLOAD" "unknown" "unknown" "Stop payload is not valid JSON"
  exit 0
fi

HOOK_EVENT=$(printf '%s' "$INPUT" | jq -r '.hook_event_name // empty' 2>/dev/null)
if [[ -n "$HOOK_EVENT" && "$HOOK_EVENT" != "Stop" ]]; then
  exit 0
fi

CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
TURN_ID=$(printf '%s' "$INPUT" | jq -r '.turn_id // empty' 2>/dev/null)
[[ -n "$CWD" ]] || CWD=$(pwd -P)

if [[ -z "$SESSION_ID" || -z "$TURN_ID" ]]; then
  bt_stop_gate_log "ERROR" "MISSING_IDENTITY" "$SESSION_ID" "$TURN_ID" "$CWD"
  exit 0
fi

REASON=""
GATE_RC=0
REASON=$(bt_stop_gate_evaluate "$CWD" "$SESSION_ID" "$TURN_ID") || GATE_RC=$?
if [[ "$GATE_RC" -eq 10 ]]; then
  jq -n --arg reason "$REASON" '{
    decision: "block",
    reason: $reason,
    suppressOutput: true
  }'
fi

exit 0

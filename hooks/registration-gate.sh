#!/bin/bash
# better-test L1 Hook: Registration Gate
# After strategy-plan.md is written to a run directory, verifies that
# bio.md and registry.md were created. Warns if missing.
# PostToolUse on Write
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib/rules/registration-gate.sh"

INPUT=$(cat)
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

if [[ "$TOOL_NAME" != "Write" ]]; then
  exit 0
fi

bt_registration_gate_output "$FILE_PATH"
exit 0

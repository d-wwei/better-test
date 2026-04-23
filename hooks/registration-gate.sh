#!/bin/bash
# better-test L1 Hook: Registration Gate
# After strategy-plan.md is written to a run directory, verifies that
# bio.md and registry.md were created. Warns if missing.
# PostToolUse on Write
set -e

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Only trigger when strategy-plan.md is written
if [[ "$TOOL_NAME" != "Write" ]] || ! echo "$FILE_PATH" | grep -q 'strategy-plan\.md'; then
  exit 0
fi

# Only for files inside a run-*/ directory
if ! echo "$FILE_PATH" | grep -qE '/run-[^/]+-[0-9]+-'; then
  exit 0
fi

# Extract run directory path
RUN_DIR=$(echo "$FILE_PATH" | sed 's|\(.*run-[^/]*\)/.*|\1|')

# Extract tester-id from run directory name: run-<tester-id>-NNN-<ts>
TESTER_ID=$(echo "$RUN_DIR" | grep -oE 'run-([^-]+-[^-]+)-' | sed 's/^run-//; s/-$//')

# Check 1: bio.md exists in run directory
# Check 2: registry.md exists for this tester
WARNINGS=""

if [[ ! -f "$RUN_DIR/bio.md" ]]; then
  WARNINGS="${WARNINGS}bio.md not found at $RUN_DIR/bio.md. "
fi

TESTERS_DIR=$(echo "$RUN_DIR" | sed 's|\(.*\.better-work/test\)/.*|\1/testers|')
if [[ -n "$TESTER_ID" ]]; then
  REGISTRY="$TESTERS_DIR/$TESTER_ID/registry.md"
  if [[ ! -f "$REGISTRY" ]]; then
    WARNINGS="${WARNINGS}registry.md not found at $REGISTRY (testers/ directory may not exist yet). "
  fi
fi

# PostToolUse cannot block — warn via additionalContext instead
if [[ -n "$WARNINGS" ]]; then
  jq -n --arg w "⚠ Registration gate: ${WARNINGS}Create missing files before proceeding with testing. See strategy-workflow.md Step 0." '{
    hookSpecificOutput: {
      hookEventName: "PostToolUse",
      additionalContext: $w
    }
  }'
fi

exit 0

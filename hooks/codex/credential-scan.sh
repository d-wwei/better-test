#!/bin/bash
# better-test L1 Hook: Codex credential-scan
# PreToolUse on Bash and Write(apply_patch) for credential-like literals
# written into a resolved better-test root.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOKS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$HOOKS_DIR/lib/common.sh"
. "$HOOKS_DIR/lib/rules/credential-scan.sh"

INPUT=$(cat)
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // .toolName // empty' 2>/dev/null)

if [[ -n "$TOOL_NAME" && "$TOOL_NAME" != "Bash" && "$TOOL_NAME" != "apply_patch" ]]; then
  exit 0
fi

CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // .working_directory // .tool_input.cwd // empty' 2>/dev/null)
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // .tool_input.cmd // .command // empty' 2>/dev/null)
PROTECTED_TARGET=""
CONTENT=""

while IFS= read -r target; do
  [[ -n "$target" ]] || continue
  if bt_is_test_path "$target" "$CWD"; then
    PROTECTED_TARGET="$target"
    CONTENT="$(bt_extract_codex_write_added_content "$TOOL_NAME" "$COMMAND" "$CWD" "$target")"
    break
  fi
done < <(bt_extract_codex_write_targets "$TOOL_NAME" "$COMMAND" "$CWD")

if [[ -z "$PROTECTED_TARGET" ]]; then
  exit 0
fi

if [[ "$TOOL_NAME" == "Bash" ]]; then
  bt_credential_scan_content "$CONTENT" "Bash command targeting $PROTECTED_TARGET"
else
  bt_credential_scan_content "$CONTENT" "apply_patch targeting $PROTECTED_TARGET"
fi
exit $?

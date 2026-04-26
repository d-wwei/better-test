#!/bin/bash
# better-test L1 Hook: Codex credential-scan
# PreToolUse on Bash for explicit credential-like literals written into .better-work/test/.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOKS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$HOOKS_DIR/lib/common.sh"
. "$HOOKS_DIR/lib/rules/credential-scan.sh"

INPUT=$(cat)
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // .toolName // empty' 2>/dev/null)

if [[ -n "$TOOL_NAME" && "$TOOL_NAME" != "Bash" ]]; then
  exit 0
fi

CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // .working_directory // .tool_input.cwd // empty' 2>/dev/null)
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // .tool_input.cmd // .command // empty' 2>/dev/null)
PROTECTED_TARGET=""

while IFS= read -r target; do
  [[ -n "$target" ]] || continue
  case "$target" in
    *"/.better-work/test/"* | *".better-work/test/"*)
      PROTECTED_TARGET="$target"
      break
      ;;
  esac
done < <(bt_extract_bash_write_targets "$COMMAND" "$CWD")

if [[ -z "$PROTECTED_TARGET" ]]; then
  exit 0
fi

bt_credential_scan_content "$COMMAND" "Bash command targeting $PROTECTED_TARGET"
exit $?

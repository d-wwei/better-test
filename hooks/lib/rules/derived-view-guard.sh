#!/bin/bash

bt_derived_view_guard_path() {
  local file_path="$1"
  local matched_view=""
  local test_base=""
  local session_dir=""

  if [[ -z "$file_path" ]] || [[ "$file_path" != *".better-work/"* ]]; then
    return 0
  fi

  case "$file_path" in
    *".better-work/test/status.md")
      matched_view="test/status.md"
      ;;
    *".better-work/test/known-issues.md")
      matched_view="test/known-issues.md"
      ;;
    *".better-work/test/history/bugs-index.md")
      matched_view="test/history/bugs-index.md"
      ;;
    *".better-work/test/history/feedback-rules.json")
      matched_view="test/history/feedback-rules.json"
      ;;
    *)
      return 0
      ;;
  esac

  if printf '%s\n' "$file_path" | grep -qE '/(run-|merge-)'; then
    return 0
  fi

  test_base=$(printf '%s\n' "$file_path" | sed 's|\(.*\.better-work/test\)/.*|\1|')
  if [[ -z "$test_base" || ! -d "$test_base" ]]; then
    return 0
  fi

  if [[ -f "$test_base/.merge-in-progress" ]]; then
    return 0
  fi

  session_dir="$test_base/.active-sessions"
  if [[ ! -d "$session_dir" ]] || [[ -z "$(ls -A "$session_dir" 2>/dev/null)" ]]; then
    return 0
  fi

  echo "better-test L1 Hook: Write to derived view '$matched_view' blocked. Active tester sessions detected — use /better-test merge after all testers complete, or clear .active-sessions/ if testing is done." >&2
  return 2
}

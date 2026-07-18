#!/bin/bash

bt_derived_view_guard_path() {
  local file_path="$1"
  local cwd="${2:-}"
  local matched_view=""
  local test_base=""
  local session_dir=""

  file_path=$(bt_normalize_file_path "$file_path" "$cwd") || return 0
  test_base=$(bt_find_test_dir_for_path "$file_path" "$cwd") || return 0

  case "$file_path" in
    "$test_base/status.md")
      matched_view="test/status.md"
      ;;
    "$test_base/known-issues.md")
      matched_view="test/known-issues.md"
      ;;
    "$test_base/history/bugs-index.md")
      matched_view="test/history/bugs-index.md"
      ;;
    "$test_base/history/feedback-rules.json")
      matched_view="test/history/feedback-rules.json"
      ;;
    *)
      return 0
      ;;
  esac

  if printf '%s\n' "$file_path" | grep -qE '/(run-|merge-)'; then
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

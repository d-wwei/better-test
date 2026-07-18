#!/bin/bash

bt_feedback_rules_guard_path() {
  local file_path="$1"
  local cwd="${2:-}"
  local test_base=""
  local session_dir=""

  file_path=$(bt_normalize_file_path "$file_path" "$cwd") || return 0
  test_base=$(bt_find_test_dir_for_path "$file_path" "$cwd") || return 0

  if [[ "$file_path" != "$test_base/history/feedback-rules.json" ]]; then
    return 0
  fi

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

  echo "better-test L1 Hook: Direct edit to feedback-rules.json is blocked. Active tester sessions detected — use /better-test merge after all testers complete. During testing, write feedback to run-*/feedback/ instead." >&2
  return 2
}

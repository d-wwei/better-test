#!/bin/bash

bt_feedback_rules_guard_path() {
  local file_path="$1"
  local test_base=""
  local session_dir=""

  if [[ -z "$file_path" ]]; then
    return 0
  fi

  if ! printf '%s\n' "$file_path" | grep -q 'feedback-rules\.json'; then
    return 0
  fi

  if printf '%s\n' "$file_path" | grep -qE '/(run-|merge-)'; then
    return 0
  fi

  test_base=$(printf '%s\n' "$file_path" | sed 's|\(.*\.better-work/test\)/.*|\1|')
  if [[ ! -d "$test_base" ]]; then
    test_base=$(printf '%s\n' "$file_path" | sed 's|\(.*\.better-work\)/.*|\1|')
    test_base="$test_base/test"
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

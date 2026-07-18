#!/bin/bash

bt_session_write_guard_path() {
  local file_path="$1"
  local cwd="${2:-}"
  local test_base=""
  local session_file=""
  local target_run=""
  local my_run_dir=""
  local my_run=""
  local my_tester=""

  file_path=$(bt_normalize_file_path "$file_path" "$cwd") || return 0
  test_base=$(bt_find_test_dir_for_path "$file_path" "$cwd") || return 0

  if ! printf '%s\n' "$file_path" | grep -qE '/run-[^/]+-[0-9]+-'; then
    return 0
  fi

  target_run=$(printf '%s\n' "$file_path" | grep -oE 'run-[^/]+' | head -1)
  if [[ -z "$target_run" ]]; then
    return 0
  fi

  session_file=$(bt_find_session_file "$test_base") || return 0

  my_run_dir=$(jq -r '.run_dir // empty' < "$session_file" 2>/dev/null)
  if [[ -z "$my_run_dir" ]]; then
    return 0
  fi

  my_run=$(printf '%s\n' "$my_run_dir" | grep -oE 'run-[^/]+' | head -1)
  if [[ -z "$my_run" || "$target_run" == "$my_run" ]]; then
    return 0
  fi

  my_tester=$(jq -r '.tester_id // "unknown"' < "$session_file" 2>/dev/null)
  echo "better-test L1 Hook: Cross-tester write blocked. Tester '$my_tester' attempted to write to '$target_run' but is only allowed to write to '$my_run'. Each tester must write exclusively to their own run directory." >&2
  return 2
}

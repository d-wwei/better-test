#!/bin/bash

BT_STOP_GATE_RULES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BT_STOP_GATE_SKILL_ROOT="$(cd "$BT_STOP_GATE_RULES_DIR/../../.." && pwd)"

bt_stop_gate_log() {
  local level="$1"
  local code="$2"
  local session_id="$3"
  local turn_id="$4"
  local detail="${5:-}"
  local log_file="${BETTER_TEST_STOP_LOG_FILE:-$HOME/.better-test/logs/stop-gate-errors.log}"
  local timestamp=""

  timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || printf '%s' unknown)
  mkdir -p "$(dirname "$log_file")" 2>/dev/null || return 0
  detail=$(printf '%s' "$detail" | tr '\n\r' '  ' | cut -c1-2000)
  printf '%s level=%s code=%s session=%s turn=%s detail=%s\n' \
    "$timestamp" "$level" "$code" "${session_id:-unknown}" "${turn_id:-unknown}" "$detail" \
    >>"$log_file" 2>/dev/null || true
}

bt_stop_gate_log_once() {
  local level="$1"
  local code="$2"
  local session_id="$3"
  local turn_id="$4"
  local detail="${5:-}"
  local state_root="${BETTER_TEST_STOP_STATE_DIR:-${TMPDIR:-/tmp}}"
  local key=""
  local marker=""

  key=$(printf '%s-%s-%s' "$session_id" "$turn_id" "$code" | tr -c 'A-Za-z0-9._-' '_')
  marker="$state_root/better-test-stop-diagnostic-$key"
  mkdir -p "$state_root" 2>/dev/null || true
  if mkdir "$marker" 2>/dev/null; then
    bt_stop_gate_log "$level" "$code" "$session_id" "$turn_id" "$detail"
  fi
}

bt_stop_gate_safe_session() {
  printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_'
}

bt_stop_gate_context_file() {
  local session_id="$1"
  local state_root="${BETTER_TEST_STOP_STATE_DIR:-${TMPDIR:-/tmp}}"
  local safe_session=""

  safe_session=$(bt_stop_gate_safe_session "$session_id")
  printf '%s/better-test-stop-context-%s.json\n' "$state_root" "${safe_session:-unknown}"
}

bt_stop_gate_store_context() {
  local session_id="$1"
  local turn_id="$2"
  local run_dir="$3"
  local session_file="$4"
  local context_file=""
  local temp_file=""

  context_file=$(bt_stop_gate_context_file "$session_id")
  mkdir -p "$(dirname "$context_file")" 2>/dev/null || return 1
  temp_file="$context_file.tmp.$$"
  if ! jq -n \
    --arg turn_id "$turn_id" \
    --arg run_dir "$run_dir" \
    --arg session_file "$session_file" \
    '{turn_id:$turn_id,run_dir:$run_dir,session_file:$session_file}' \
    >"$temp_file" 2>/dev/null; then
    rm -f "$temp_file"
    return 1
  fi
  if ! mv "$temp_file" "$context_file" 2>/dev/null; then
    rm -f "$temp_file"
    return 1
  fi
}

bt_stop_gate_load_context() {
  local session_id="$1"
  local turn_id="$2"
  local context_file=""

  context_file=$(bt_stop_gate_context_file "$session_id")
  [[ -f "$context_file" ]] || return 1
  jq -e --arg turn_id "$turn_id" '
    select(.turn_id == $turn_id)
    | select((.run_dir // "") != "")
  ' "$context_file" 2>/dev/null
}

bt_stop_gate_plan_status() {
  local plan_file="$1"

  [[ -f "$plan_file" ]] || return 1
  awk '
    BEGIN { in_frontmatter=0 }
    NR == 1 && $0 == "---" { in_frontmatter=1; next }
    in_frontmatter && $0 == "---" { exit }
    in_frontmatter && /^[[:space:]]*status[[:space:]]*:/ {
      value=$0
      sub(/^[^:]*:[[:space:]]*/, "", value)
      gsub(/^["'\'']|["'\'']$/, "", value)
      print value
      exit
    }
  ' "$plan_file"
}

bt_stop_gate_is_finalizing() {
  local run_dir="$1"
  local status=""

  [[ -f "$run_dir/FULL-TEST-REPORT.md" ]] && return 0
  status=$(bt_stop_gate_plan_status "$run_dir/strategy-plan.md") || status=""
  [[ "$status" == "completed" ]]
}

bt_stop_gate_validate_run_dir() {
  local test_dir="$1"
  local candidate="$2"
  local test_dir_real=""
  local run_dir_real=""

  test_dir_real=$(bt_real_dir "$test_dir") || return 2
  run_dir_real=$(bt_real_dir "$candidate") || return 2
  case "$run_dir_real" in
    "$test_dir_real/history/"*) printf '%s\n' "$run_dir_real" ;;
    *) return 2 ;;
  esac
}

bt_stop_gate_run_from_session() {
  local test_dir="$1"
  local session_file="$2"
  local run_dir_rel=""

  run_dir_rel=$(jq -r '.run_dir // empty' "$session_file" 2>/dev/null) || return 2
  [[ -n "$run_dir_rel" && "$run_dir_rel" != /* ]] || return 2
  case "/$run_dir_rel/" in
    *"/../"*) return 2 ;;
  esac
  bt_stop_gate_validate_run_dir "$test_dir" "$test_dir/$run_dir_rel"
}

bt_stop_gate_safe_session_file() {
  local test_dir="$1"
  local session_file="$2"
  local normalized=""
  local session_root=""

  [[ -n "$session_file" ]] || return 1
  normalized=$(bt_normalize_file_path "$session_file") || return 1
  session_root=$(bt_normalize_file_path "$test_dir/.active-sessions") || return 1
  case "$normalized" in
    "$session_root/"*.json) return 0 ;;
  esac
  return 1
}

bt_stop_gate_take_slot() {
  local session_id="$1"
  local turn_id="$2"
  local state_root="${BETTER_TEST_STOP_STATE_DIR:-${TMPDIR:-/tmp}}"
  local safe_session=""
  local state_file=""
  local stored_turn=""
  local count=0
  local next_count=0
  local temp_file=""

  safe_session=$(bt_stop_gate_safe_session "$session_id")
  state_file="$state_root/better-test-stop-${safe_session:-unknown}.json"
  mkdir -p "$state_root" 2>/dev/null || return 2

  if [[ -f "$state_file" ]]; then
    stored_turn=$(jq -r '.turn_id // empty' "$state_file" 2>/dev/null) || stored_turn=""
    if [[ "$stored_turn" == "$turn_id" ]]; then
      count=$(jq -r '.count // 0' "$state_file" 2>/dev/null) || count=0
    fi
  fi
  [[ "$count" =~ ^[0-9]+$ ]] || count=0

  if (( count >= 3 )); then
    printf '%s\n' "LIMIT"
    return 0
  fi

  next_count=$((count + 1))
  temp_file="$state_file.tmp.$$"
  if ! jq -n --arg turn_id "$turn_id" --argjson count "$next_count" \
    '{turn_id:$turn_id,count:$count}' >"$temp_file" 2>/dev/null; then
    rm -f "$temp_file"
    return 2
  fi
  if ! mv "$temp_file" "$state_file" 2>/dev/null; then
    rm -f "$temp_file"
    return 2
  fi
  printf '%s\n' "$next_count"
}

bt_stop_gate_evaluate() {
  local cwd="$1"
  local session_id="$2"
  local turn_id="$3"
  local test_dir=""
  local session_file=""
  local context=""
  local run_dir=""
  local run_rc=0
  local project_root=""
  local validator="${BETTER_TEST_VALIDATE_RUN:-$BT_STOP_GATE_SKILL_ROOT/scripts/validate-run.py}"
  local validation_output=""
  local validation_rc=0
  local slot=""

  test_dir=$(bt_resolve_test_dir "$cwd" 2>/dev/null) || return 0

  session_file=$(bt_find_session_file "$test_dir") || session_file=""
  if [[ -n "$session_file" ]]; then
    run_dir=$(bt_stop_gate_run_from_session "$test_dir" "$session_file") || run_rc=$?
  else
    context=$(bt_stop_gate_load_context "$session_id" "$turn_id") || context=""
    if [[ -n "$context" ]]; then
      run_dir=$(printf '%s' "$context" | jq -r '.run_dir')
      session_file=$(printf '%s' "$context" | jq -r '.session_file // empty')
      run_dir=$(bt_stop_gate_validate_run_dir "$test_dir" "$run_dir") || run_rc=$?
    else
      bt_stop_gate_log_once "INFO" "NO_ACTIVE_RUN" "$session_id" "$turn_id" "$test_dir"
      return 0
    fi
  fi
  if [[ "$run_rc" -ne 0 || -z "$run_dir" ]]; then
    bt_stop_gate_log "ERROR" "INVALID_ACTIVE_RUN" "$session_id" "$turn_id" "$test_dir"
    return 0
  fi

  bt_stop_gate_is_finalizing "$run_dir" || return 0
  if ! bt_stop_gate_store_context "$session_id" "$turn_id" "$run_dir" "$session_file"; then
    bt_stop_gate_log "ERROR" "CONTEXT_STATE_ERROR" "$session_id" "$turn_id" "$run_dir"
    return 0
  fi

  project_root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || project_root="$cwd"
  if [[ ! -f "$validator" ]]; then
    bt_stop_gate_log "ERROR" "VALIDATOR_MISSING" "$session_id" "$turn_id" "$validator"
    return 0
  fi

  validation_output=$(python3 "$validator" \
    --run-dir "$run_dir" \
    --intake-policy required \
    --project-root "$project_root" \
    --validate-report 2>&1) || validation_rc=$?

  if [[ "$validation_rc" -eq 0 ]]; then
    if bt_stop_gate_safe_session_file "$test_dir" "$session_file"; then
      rm -f "$session_file" 2>/dev/null || true
    elif [[ -n "$session_file" ]]; then
      bt_stop_gate_log "ERROR" "UNSAFE_SESSION_CLEANUP_PATH" \
        "$session_id" "$turn_id" "$session_file"
    fi
    return 0
  fi
  if [[ "$validation_rc" -ne 1 \
    || -z "$validation_output" \
    || "$validation_output" == *"Traceback (most recent call last):"* \
    || "$validation_output" == *"SyntaxError:"* \
    || "$validation_output" == *"ModuleNotFoundError:"* ]]; then
    bt_stop_gate_log "ERROR" "VALIDATOR_ERROR" "$session_id" "$turn_id" \
      "exit=$validation_rc $validation_output"
    return 0
  fi

  slot=$(bt_stop_gate_take_slot "$session_id" "$turn_id") || {
    bt_stop_gate_log "ERROR" "RATE_STATE_ERROR" "$session_id" "$turn_id" "$run_dir"
    return 0
  }
  if [[ "$slot" == "LIMIT" ]]; then
    bt_stop_gate_log "WARN" "RATE_LIMITED_INVALID_RUN" "$session_id" "$turn_id" \
      "$run_dir $validation_output"
    return 0
  fi

  printf 'Better Test completion gate failed (%s/3) for %s:\n%s\nRun the portable validate-run command again after fixing the evidence.' \
    "$slot" "$run_dir" "$(printf '%s' "$validation_output" | head -c 2000)"
  return 10
}

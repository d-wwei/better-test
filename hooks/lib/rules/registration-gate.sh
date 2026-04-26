#!/bin/bash

bt_registration_gate_output() {
  local file_path="$1"
  local run_dir=""
  local tester_id=""
  local warnings=""
  local testers_dir=""
  local registry=""

  if [[ -z "$file_path" ]]; then
    return 0
  fi

  if ! printf '%s\n' "$file_path" | grep -q 'strategy-plan\.md'; then
    return 0
  fi

  if ! printf '%s\n' "$file_path" | grep -qE '/run-[^/]+-[0-9]+-'; then
    return 0
  fi

  run_dir=$(printf '%s\n' "$file_path" | sed 's|\(.*run-[^/]*\)/.*|\1|')
  # strategy-workflow currently generates run-<agent>-<suffix>-<seq>-<ts>,
  # so tester_id extraction intentionally assumes a two-segment agent id.
  tester_id=$(printf '%s\n' "$run_dir" | grep -oE 'run-([^-]+-[^-]+)-' | sed 's/^run-//; s/-$//')

  if [[ ! -f "$run_dir/bio.md" ]]; then
    warnings="${warnings}bio.md not found at $run_dir/bio.md. "
  fi

  testers_dir=$(printf '%s\n' "$run_dir" | sed 's|\(.*\.better-work/test\)/.*|\1/testers|')
  if [[ -n "$tester_id" ]]; then
    registry="$testers_dir/$tester_id/registry.md"
    if [[ ! -f "$registry" ]]; then
      warnings="${warnings}registry.md not found at $registry (testers/ directory may not exist yet). "
    fi
  fi

  if [[ -z "$warnings" ]]; then
    return 0
  fi

  jq -n --arg w "⚠ Registration gate: ${warnings}Create missing files before proceeding with testing. See strategy-workflow.md Step 0." '{
    hookSpecificOutput: {
      hookEventName: "PostToolUse",
      additionalContext: $w
    }
  }'
}

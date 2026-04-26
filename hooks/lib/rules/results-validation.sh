#!/bin/bash

bt_results_validation_output() {
  local file_path="$1"
  local content="$2"
  local warnings=""
  local field=""
  local val=""
  local coverage=""
  local items_count=""
  local issues=""
  local bad_ids=""
  local weak_evidence=""

  if [[ -z "$file_path" ]]; then
    return 0
  fi

  if ! printf '%s\n' "$file_path" | grep -q 'results\.json'; then
    return 0
  fi

  if ! printf '%s\n' "$file_path" | grep -qE '\.better-work/test/history/'; then
    return 0
  fi

  if [[ -z "$content" ]] || ! printf '%s\n' "$content" | jq . >/dev/null 2>&1; then
    return 0
  fi

  for field in version run_id mode summary; do
    val=$(printf '%s\n' "$content" | jq -r ".$field // empty" 2>/dev/null)
    if [[ -z "$val" || "$val" == "null" ]]; then
      warnings="${warnings}\n- 缺少顶层字段: $field"
    fi
  done

  coverage=$(printf '%s\n' "$content" | jq '.coverage // empty' 2>/dev/null)
  if [[ -z "$coverage" || "$coverage" == "null" || "$coverage" == "" ]]; then
    warnings="${warnings}\n- 缺少 coverage 段（manifest_total / reachable / tested / reachable_coverage_pct）"
  fi

  items_count=$(printf '%s\n' "$content" | jq '.items | length // 0' 2>/dev/null)
  if [[ "$items_count" == "0" ]]; then
    warnings="${warnings}\n- items 数组为空"
  else
    issues=$(printf '%s\n' "$content" | jq -r '
      [.items[] | select(
        (.assertion_field == null or .assertion_field == "") and
        .status == "pass"
      ) | .id] | join(", ")' 2>/dev/null)

    if [[ -n "$issues" ]]; then
      warnings="${warnings}\n- 以下 pass 项缺少 assertion_field（标 pass 必须有具体字段验证）: $issues"
    fi

    bad_ids=$(printf '%s\n' "$content" | jq -r '
      [.items[] | .id | select(test("^[A-Z]-[0-9]+$") | not)] | join(", ")' 2>/dev/null)

    if [[ -n "$bad_ids" ]]; then
      warnings="${warnings}\n- 非标准 ID 格式（应为 Letter-NN）: $bad_ids"
    fi

    weak_evidence=$(printf '%s\n' "$content" | jq -r '
      [.items[] | select(.status == "pass" and .evidence_level == "indirect") | .id] | join(", ")' 2>/dev/null)

    if [[ -n "$weak_evidence" ]]; then
      warnings="${warnings}\n- 以下 pass 项证据级别为 indirect（pass 至少需要 direct）: $weak_evidence"
    fi
  fi

  if [[ -z "$warnings" ]]; then
    return 0
  fi

  jq -n --arg warnings "⚠ results.json 字段检查发现以下问题：$warnings\n\n请修复后重新写入。" '{
    hookSpecificOutput: {
      hookEventName: "PostToolUse",
      additionalContext: $warnings
    }
  }'
}

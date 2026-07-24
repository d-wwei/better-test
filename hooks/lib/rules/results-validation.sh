#!/bin/bash

BT_RESULTS_VALIDATION_RULES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

bt_results_validation_output() {
  local file_path="$1"
  local content="$2"
  local cwd="${3:-}"
  local force_validation="${4:-false}"
  local schema_version="1"
  local errors=""
  local warnings=""
  local field=""
  local val=""
  local coverage=""
  local items_count="0"
  local missing_status_count="0"
  local issues=""
  local bad_ids=""
  local bad_statuses=""
  local weak_evidence=""
  local mode_val=""
  local no_baseline=""
  local no_value=""
  local pre_existing_pass=""
  local summary_total=""
  local context=""
  local strict_issues=""
  local semantic_issues=""

  if [[ -z "$file_path" || "$(basename "$file_path")" != "results.json" ]]; then
    return 0
  fi

  if [[ "$force_validation" != "true" ]] && ! bt_is_test_history_path "$file_path" "$cwd"; then
    return 0
  fi

  if [[ -z "$content" ]] \
    || ! printf '%s\n' "$content" | jq . >/dev/null 2>&1 \
    || ! printf '%s\n' "$content" | python3 -c '
import json
import sys

def reject_constant(value):
    raise ValueError(f"non-standard JSON constant: {value}")

json.load(sys.stdin, parse_constant=reject_constant)
' >/dev/null 2>&1; then
    errors=$'\n- JSON 无法解析或文件为空'
    context="❌ results.json 字段检查失败（schema validation failed）:${errors}\n\n修复后重新写入；schema v2/v3 错误不能作为有效测试结果继续流转。"
    jq -n --arg context "$context" '{
      hookSpecificOutput: {
        hookEventName: "PostToolUse",
        additionalContext: $context
      }
    }'
    return 2
  fi

  schema_version=$(printf '%s\n' "$content" | jq -r '(.schema_version // 1) | tostring' 2>/dev/null)

  for field in version run_id mode summary; do
    val=$(printf '%s\n' "$content" | jq -r --arg field "$field" '.[$field] // empty' 2>/dev/null)
    if [[ -z "$val" || "$val" == "null" ]]; then
      if [[ "$schema_version" == "2" || "$schema_version" == "3" ]]; then
        errors="${errors}"$'\n'"- 缺少 schema v${schema_version} 顶层字段: $field"
      else
        warnings="${warnings}"$'\n'"- 缺少顶层字段: $field"
      fi
    fi
  done

  if [[ "$schema_version" == "2" || "$schema_version" == "3" ]]; then
    for field in tester_id finished_at; do
      val=$(printf '%s\n' "$content" | jq -r --arg field "$field" '.[$field] // empty' 2>/dev/null)
      if [[ -z "$val" || "$val" == "null" ]]; then
        errors="${errors}"$'\n'"- 缺少 schema v${schema_version} 必填字段: $field"
      fi
    done
  fi

  coverage=$(printf '%s\n' "$content" | jq -c '.coverage // empty' 2>/dev/null)
  if [[ -z "$coverage" || "$coverage" == "null" || "$coverage" == "\"\"" ]]; then
    if [[ "$schema_version" == "2" || "$schema_version" == "3" ]]; then
      errors="${errors}"$'\n'"- schema v${schema_version} 缺少 coverage 段（manifest_total / reachable / tested / reachable_coverage_pct）"
    else
      warnings="${warnings}"$'\n'"- 缺少 coverage 段（manifest_total / reachable / tested / reachable_coverage_pct）"
    fi
  fi

  if ! printf '%s\n' "$content" | jq -e '.items | type == "array"' >/dev/null 2>&1; then
    errors="${errors}"$'\n'"- items 必须是数组"
  else
    items_count=$(printf '%s\n' "$content" | jq '.items | length' 2>/dev/null)
    if [[ "$items_count" == "0" ]]; then
      warnings="${warnings}"$'\n'"- items 数组为空"
    fi
  fi

  if [[ "$schema_version" == "2" || "$schema_version" == "3" ]]; then
    if ! printf '%s\n' "$content" | jq -e '.gate_items | type == "array"' >/dev/null 2>&1; then
      errors="${errors}"$'\n'"- schema v${schema_version} 缺少 gate_items 数组（无适用 gate 时也必须写 []）"
    fi

    if ! printf '%s\n' "$content" | jq -e '.summary.total | type == "number"' >/dev/null 2>&1; then
      errors="${errors}"$'\n'"- schema v${schema_version} 缺少数字型 summary.total"
    else
      summary_total=$(printf '%s\n' "$content" | jq -r '.summary.total' 2>/dev/null)
      if [[ "$summary_total" != "$items_count" ]]; then
        errors="${errors}"$'\n'"- summary.total=$summary_total 与 items 数量=$items_count 不一致"
      fi
    fi
  fi

  if [[ "$schema_version" == "2" || "$schema_version" == "3" ]]; then
    strict_issues=$(printf '%s\n' "$content" | jq -r -f "$BT_RESULTS_VALIDATION_RULES_DIR/results-validation-v2-v3.jq" 2>/dev/null) || {
      strict_issues="- schema v${schema_version} 严格校验器执行失败"
    }
    if [[ -n "$strict_issues" ]]; then
      errors="${errors}"$'\n'"$strict_issues"
    fi
    semantic_issues=$(printf '%s\n' "$content" | python3 \
      "$BT_RESULTS_VALIDATION_RULES_DIR/results-semantic-validation.py" \
      "$file_path") || {
      semantic_issues="- schema v${schema_version} Python 语义校验器执行失败"
    }
    if [[ -n "$semantic_issues" ]]; then
      errors="${errors}"$'\n'"$semantic_issues"
    fi
  elif [[ "$schema_version" != "1" ]]; then
    errors="${errors}"$'\n'"- 不支持的 schema_version: $schema_version（当前支持 1、2、3）"
  fi

  if [[ "$items_count" != "0" ]]; then
    if [[ "$schema_version" == "2" || "$schema_version" == "3" ]]; then
      missing_status_count=$(printf '%s\n' "$content" | jq '[.items[] | select((has("status") | not) or .status == null or .status == "")] | length' 2>/dev/null)
      issues=$(printf '%s\n' "$content" | jq -r '[.items[] | select((has("status") | not) or .status == null or .status == "") | (.id // "<missing-id>")] | join(", ")' 2>/dev/null)
      if [[ "$missing_status_count" != "0" ]]; then
        if [[ "$missing_status_count" == "$items_count" ]]; then
          errors="${errors}"$'\n'"- 所有 items 都缺少 schema v${schema_version} 必填字段 status；legacy verdict 不能替代 status"
        else
          errors="${errors}"$'\n'"- 以下 schema v${schema_version} items 缺少 status: $issues"
        fi
      fi
    fi

    bad_statuses=$(printf '%s\n' "$content" | jq -r '
      [.items[]
        | {id: (.id // "<missing-id>"), value: ((.status // .verdict // "") | tostring | ascii_downcase)}
        | . as $item
        | select(["pass", "pass_with_caveat", "pass-with-caveat", "pass_known_legacy_behavior", "pass-known-legacy-behavior", "fail", "blocked", "skip", "excluded", "pending", "partial", "partial_fail", "partial-fail"] | index($item.value) | not)
        | ($item.id + "=" + $item.value)
      ] | join(", ")' 2>/dev/null)
    if [[ -n "$bad_statuses" ]]; then
      if [[ "$schema_version" == "2" || "$schema_version" == "3" ]]; then
        errors="${errors}"$'\n'"- 缺少或不支持的 item status/verdict: $bad_statuses"
      else
        warnings="${warnings}"$'\n'"- legacy item 使用了未知 status/verdict: $bad_statuses"
      fi
    fi

    issues=$(printf '%s\n' "$content" | jq -r '
      [.items[] | select(
        (((.status // .verdict // "") | tostring | ascii_downcase | test("^pass([_-].+)?$"))) and
        (.assertion_field == null or .assertion_field == "")
      ) | (.id // "<missing-id>")] | join(", ")' 2>/dev/null)
    if [[ -n "$issues" ]]; then
      if [[ "$schema_version" == "2" || "$schema_version" == "3" ]]; then
        errors="${errors}"$'\n'"- 以下 pass 项缺少 assertion_field: $issues"
      else
        warnings="${warnings}"$'\n'"- 以下 pass 项缺少 assertion_field（标 pass 必须有具体字段验证）: $issues"
      fi
    fi

    bad_ids=$(printf '%s\n' "$content" | jq -r '
      [.items[] | (.id // "<missing-id>") | tostring
        | select(test("^[A-Z][A-Z0-9]*([.-][A-Z0-9]+)+$") | not)
      ] | join(", ")' 2>/dev/null)
    if [[ -n "$bad_ids" ]]; then
      warnings="${warnings}"$'\n'"- 非标准 ID 格式（支持 A-01、AUTH-REM-03、CLI.AUTH-01 等层级 ID）: $bad_ids"
    fi

    weak_evidence=$(printf '%s\n' "$content" | jq -r '
      [.items[] | select(
        (((.status // .verdict // "") | tostring | ascii_downcase | test("^pass([_-].+)?$"))) and
        ((.evidence_level // "") | tostring | ascii_downcase) == "indirect"
      ) | (.id // "<missing-id>")] | join(", ")' 2>/dev/null)
    if [[ -n "$weak_evidence" ]]; then
      if [[ "$schema_version" == "2" || "$schema_version" == "3" ]]; then
        errors="${errors}"$'\n'"- 以下 pass 项证据级别为 indirect（pass 至少需要 direct）: $weak_evidence"
      else
        warnings="${warnings}"$'\n'"- 以下 pass 项证据级别为 indirect（pass 至少需要 direct）: $weak_evidence"
      fi
    fi

    mode_val=$(printf '%s\n' "$content" | jq -r '.mode // ""' 2>/dev/null)
    if printf '%s\n' "$mode_val" | grep -qi 'compare'; then
      no_baseline=$(printf '%s\n' "$content" | jq -r '
        [.items[] | select(
          (((.status // .verdict // "") | tostring | ascii_downcase | test("^pass([_-].+)?$"))) and
          (.comparison_baseline == null or .comparison_baseline == "")
        ) | (.id // "<missing-id>")] | join(", ")' 2>/dev/null)
      if [[ -n "$no_baseline" ]]; then
        warnings="${warnings}"$'\n'"- Compare 模式下以下 pass 项缺少 comparison_baseline: $no_baseline"
      fi
    fi

    no_value=$(printf '%s\n' "$content" | jq -r '
      [.items[] | select(
        (((.status // .verdict // "") | tostring | ascii_downcase | test("^pass([_-].+)?$"))) and
        .assertion_field != null and .assertion_field != "" and
        (.assertion_value == null or .assertion_value == "")
      ) | (.id // "<missing-id>")] | join(", ")' 2>/dev/null)
    if [[ -n "$no_value" ]]; then
      if [[ "$schema_version" == "2" || "$schema_version" == "3" ]]; then
        errors="${errors}"$'\n'"- 以下 pass 项有 assertion_field 但缺少 assertion_value: $no_value"
      else
        warnings="${warnings}"$'\n'"- 以下 pass 项有 assertion_field 但缺少 assertion_value（只有字段名没实际值）: $no_value"
      fi
    fi

    if ! printf '%s\n' "$mode_val" | grep -qi 'bug-retest'; then
      pre_existing_pass=$(printf '%s\n' "$content" | jq -r '
        [.items[] | select(
          (((.status // .verdict // "") | tostring | ascii_downcase | test("^pass([_-].+)?$"))) and
          .pre_existing == true
        ) | (.id // "<missing-id>")] | join(", ")' 2>/dev/null)
      if [[ -n "$pre_existing_pass" ]]; then
        warnings="${warnings}"$'\n'"- 以下 pre_existing=true 的项标了 pass（Red Line #18；修复验证请使用 bug-retest mode）: $pre_existing_pass"
      fi
    fi
  fi

  if [[ -n "$errors" ]]; then
    context="❌ results.json 字段检查失败（schema v${schema_version} validation failed）:${errors}"
    if [[ -n "$warnings" ]]; then
      context="${context}\n\n同时发现 advisory:${warnings}"
    fi
    context="${context}\n\n修复后重新写入；schema v2/v3 错误不能作为有效测试结果继续流转。"
    jq -n --arg context "$context" '{
      hookSpecificOutput: {
        hookEventName: "PostToolUse",
        additionalContext: $context
      }
    }'
    return 2
  fi

  if [[ -z "$warnings" ]]; then
    return 0
  fi

  context="⚠ results.json 字段检查发现以下问题:${warnings}\n\n请修复后重新写入。"
  jq -n --arg context "$context" '{
    hookSpecificOutput: {
      hookEventName: "PostToolUse",
      additionalContext: $context
    }
  }'
}

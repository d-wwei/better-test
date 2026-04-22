#!/bin/bash
# better-test L1 Hook: results.json Field Validation
# Checks required fields when results.json is written.
# PostToolUse on Write
#
# Phase B found: agent skips required fields (assertion_field, evidence_level,
# coverage stats, bug_ids), uses non-standard IDs, and inconsistent schemas.
# This hook catches those at write time — not blocking, just warning.
set -e

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Only check Write tool on results.json
if [[ "$TOOL_NAME" != "Write" ]]; then
  exit 0
fi

if ! echo "$FILE_PATH" | grep -q 'results\.json'; then
  exit 0
fi

# Only for .better-work paths
if ! echo "$FILE_PATH" | grep -qE '\.better-work|history'; then
  exit 0
fi

CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // empty')

# Skip if content is empty or not JSON
if [[ -z "$CONTENT" ]] || ! echo "$CONTENT" | jq . >/dev/null 2>&1; then
  exit 0
fi

WARNINGS=""

# Check top-level required fields
for FIELD in version run_id mode summary; do
  VAL=$(echo "$CONTENT" | jq -r ".$FIELD // empty" 2>/dev/null)
  if [[ -z "$VAL" || "$VAL" == "null" ]]; then
    WARNINGS="${WARNINGS}\n- 缺少顶层字段: $FIELD"
  fi
done

# Check coverage section
COVERAGE=$(echo "$CONTENT" | jq '.coverage // empty' 2>/dev/null)
if [[ -z "$COVERAGE" || "$COVERAGE" == "null" || "$COVERAGE" == "" ]]; then
  WARNINGS="${WARNINGS}\n- 缺少 coverage 段（manifest_total / reachable / tested / reachable_coverage_pct）"
fi

# Check items array
ITEMS_COUNT=$(echo "$CONTENT" | jq '.items | length // 0' 2>/dev/null)
if [[ "$ITEMS_COUNT" == "0" ]]; then
  WARNINGS="${WARNINGS}\n- items 数组为空"
else
  # Check a sample of items for required fields
  ISSUES=$(echo "$CONTENT" | jq -r '
    [.items[] | select(
      (.assertion_field == null or .assertion_field == "") and
      .status == "pass"
    ) | .id] | join(", ")' 2>/dev/null)

  if [[ -n "$ISSUES" && "$ISSUES" != "" ]]; then
    WARNINGS="${WARNINGS}\n- 以下 pass 项缺少 assertion_field（标 pass 必须有具体字段验证）: $ISSUES"
  fi

  # Check for non-standard IDs
  BAD_IDS=$(echo "$CONTENT" | jq -r '
    [.items[] | .id | select(test("^[A-Z]-[0-9]+$") | not)] | join(", ")' 2>/dev/null)

  if [[ -n "$BAD_IDS" && "$BAD_IDS" != "" ]]; then
    WARNINGS="${WARNINGS}\n- 非标准 ID 格式（应为 Letter-NN）: $BAD_IDS"
  fi

  # Check evidence_level for pass items
  WEAK_EVIDENCE=$(echo "$CONTENT" | jq -r '
    [.items[] | select(.status == "pass" and .evidence_level == "indirect") | .id] | join(", ")' 2>/dev/null)

  if [[ -n "$WEAK_EVIDENCE" && "$WEAK_EVIDENCE" != "" ]]; then
    WARNINGS="${WARNINGS}\n- 以下 pass 项证据级别为 indirect（pass 至少需要 direct）: $WEAK_EVIDENCE"
  fi
fi

# Output warnings if any
if [[ -n "$WARNINGS" ]]; then
  # Use additionalContext to inject warnings (non-blocking)
  jq -n --arg warnings "⚠ results.json 字段检查发现以下问题：$WARNINGS\n\n请修复后重新写入。" '{
    hookSpecificOutput: {
      hookEventName: "PostToolUse",
      additionalContext: $warnings
    }
  }'
fi

exit 0

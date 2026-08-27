#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXECUTION="$ROOT_DIR/references/test-execution-workflow.md"
TEMPLATES="$ROOT_DIR/references/templates.md"
QUEUE="$ROOT_DIR/references/pending-skill-upgrades.md"
ADR="$ROOT_DIR/docs/adr/0001-data-quality-and-occurrence-accounting.md"
STRATEGY="$ROOT_DIR/references/strategy-workflow.md"
L2="$ROOT_DIR/references/l2-audit-prompts.md"

for file in "$EXECUTION" "$TEMPLATES" "$QUEUE" "$ADR" "$STRATEGY" "$L2"; do
  if [[ ! -f "$file" ]]; then
    echo "FAIL: missing data-quality guidance artifact: $file" >&2
    exit 1
  fi
done

grep -q '查询 / 集合 / 流式数据质量矩阵' "$EXECUTION"
grep -q 'Oracle-conditioned non-empty' "$EXECUTION"
grep -q '64-bit ID/sequence' "$EXECUTION"
grep -q 'Aggregate/detail consistency' "$EXECUTION"
grep -q 'Cache integrity' "$EXECUTION"
grep -q 'occurrence、finding 和 Bug 不是一一对应' "$EXECUTION"
grep -q '修复完整性门' "$EXECUTION"
grep -q '目标症状、保持项、相邻不变量、替代缺陷反例' "$EXECUTION"

grep -q '计数基数分离' "$TEMPLATES"
grep -q 'occurrence（测试执行实例）' "$TEMPLATES"
grep -q 'investigation backlog' "$TEMPLATES"
grep -q '修复闭包矩阵' "$TEMPLATES"

grep -q '修复闭包' "$STRATEGY"
grep -q '不能用删除、截断、默认值或绕过路径换取原断言通过' "$STRATEGY"

grep -q '修复完整性审计' "$L2"
grep -q '原问题关闭、新问题另开' "$L2"

grep -q '查询/集合/流式数据质量矩阵' "$QUEUE"
grep -q 'occurrence → finding → Bug 多对一记账' "$QUEUE"
grep -q '修复复测必须验证保持项与替代缺陷' "$QUEUE"
grep -q 'promoted 2026-08-25' "$QUEUE"
grep -q 'promoted 2026-08-27' "$QUEUE"

echo "data-quality guidance integrity passed"

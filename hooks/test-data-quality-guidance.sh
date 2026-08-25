#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXECUTION="$ROOT_DIR/references/test-execution-workflow.md"
TEMPLATES="$ROOT_DIR/references/templates.md"
QUEUE="$ROOT_DIR/references/pending-skill-upgrades.md"
ADR="$ROOT_DIR/docs/adr/0001-data-quality-and-occurrence-accounting.md"

for file in "$EXECUTION" "$TEMPLATES" "$QUEUE" "$ADR"; do
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

grep -q '计数基数分离' "$TEMPLATES"
grep -q 'occurrence（测试执行实例）' "$TEMPLATES"
grep -q 'investigation backlog' "$TEMPLATES"

grep -q '查询/集合/流式数据质量矩阵' "$QUEUE"
grep -q 'occurrence → finding → Bug 多对一记账' "$QUEUE"
grep -q 'promoted 2026-08-25' "$QUEUE"

echo "data-quality guidance integrity passed"

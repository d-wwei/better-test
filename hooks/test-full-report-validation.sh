#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILDER="$ROOT_DIR/scripts/build-full-report.py"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/better-test-full-report.XXXXXX")"
RUN_DIR="$TMP_DIR/run-codex-a3f2-001"
REPORT="$RUN_DIR/FULL-TEST-REPORT.md"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$RUN_DIR/bugs"

cat >"$RUN_DIR/summary.md" <<'EOF'
# 测试速览

## 一句话结论
发现 1 个需要修复的问题。
EOF

cat >"$RUN_DIR/results.json" <<'EOF'
{
  "run_id": "run-codex-a3f2-001",
  "items": [
    {
      "id": "AUTH-01",
      "status": "fail",
      "bug_ids": ["BUG-001"]
    }
  ]
}
EOF

cat >"$RUN_DIR/audit-report.md" <<'EOF'
# L2 审计结论

已核对执行、覆盖、证据和 Bug Report Schedule 完整性。
EOF

cat >"$RUN_DIR/bugs/BUG-001-auth-timeout.md" <<'EOF'
# BUG-001: auth timeout

## 1. TL;DR
慢速网络下登录超时，用户无法进入服务。

## 2. 现象矩阵
| 网络 | 结果 |
|---|---|
| 正常 | PASS |
| 慢速 | FAIL |

## 3. 基准对照
基准实现成功，被测实现超时。

## 4. 其他对照
完整参数和最小参数均复现。

## 5. 权限/账号排除
同一账号在基准实现登录成功。

## 6. Root cause 推测
evidence: direct。超时窗口未覆盖慢速网络握手。

## 7. 复现步骤
运行慢速网络 fixture，然后启动第一方登录流程。

## 8. 影响评估
阻塞慢速网络用户登录，严重程度 P1。

```yaml
bug:
  id: BUG-001
  title: auth timeout
  status: OPEN
  severity: P1
  evidence_level: direct
  evidence_refs: [AUTH-LOG-01]
  bug_type: environment
  affected_groups: [AUTH]
  affected_scenarios: [slow-network]
  found_in: v1.0.0
  found_by_tester: codex-a3f2
  found_by_run: run-codex-a3f2-001
  related_tests: [AUTH-01]
  version_found: v1.0.0
  version_fixed: null
  regression_canary: true
  post_ship: false
  escape_id: null
```
EOF

python3 "$BUILDER" --run-dir "$RUN_DIR" --output "$REPORT"
python3 "$BUILDER" --run-dir "$RUN_DIR" --output "$REPORT" --validate-only

grep -Fq '慢速网络下登录超时，用户无法进入服务。' "$REPORT"
grep -Fq '## 完整 Bug Reports' "$REPORT"
grep -Fq '## 完整机器结果' "$REPORT"
grep -Fq 'Bug Report Schedule 完整性' "$REPORT"

python3 - "$REPORT" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
path.write_text(
    text.replace(
        "已核对执行、覆盖、证据和 Bug Report Schedule 完整性。",
        "审计正文被截断。",
        1,
    ),
    encoding="utf-8",
)
PY

set +e
output="$(python3 "$BUILDER" --run-dir "$RUN_DIR" --output "$REPORT" --validate-only 2>&1)"
rc=$?
set -e
if [[ "$rc" -eq 0 ]]; then
  echo "FAIL: truncated embedded audit material passed validation" >&2
  exit 1
fi
if [[ "$output" != *"完整正文不一致"* ]]; then
  echo "FAIL: unexpected support validation error: $output" >&2
  exit 1
fi

python3 "$BUILDER" --run-dir "$RUN_DIR" --output "$REPORT"

python3 - "$RUN_DIR/bugs/BUG-001-auth-timeout.md" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
path.write_text(
    text.replace(
        "## 3. 基准对照\n基准实现成功，被测实现超时。\n",
        "## 3. 基准对照\n\n",
        1,
    ),
    encoding="utf-8",
)
PY

set +e
output="$(python3 "$BUILDER" --run-dir "$RUN_DIR" --output "$REPORT" 2>&1)"
rc=$?
set -e
if [[ "$rc" -eq 0 ]]; then
  echo "FAIL: empty required Bug Report section passed validation" >&2
  exit 1
fi
if [[ "$output" != *"必填章节没有正文: 基准对照"* ]]; then
  echo "FAIL: unexpected empty-section error: $output" >&2
  exit 1
fi

python3 - "$RUN_DIR/bugs/BUG-001-auth-timeout.md" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
path.write_text(
    text.replace(
        "## 3. 基准对照\n\n",
        "## 3. 基准对照\n基准实现成功，被测实现超时。\n",
        1,
    ),
    encoding="utf-8",
)
PY

python3 - "$REPORT" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
path.write_text(
    text.replace(
        "慢速网络下登录超时，用户无法进入服务。",
        "正文被截断。",
        1,
    ),
    encoding="utf-8",
)
PY

set +e
output="$(python3 "$BUILDER" --run-dir "$RUN_DIR" --output "$REPORT" --validate-only 2>&1)"
rc=$?
set -e
if [[ "$rc" -eq 0 ]]; then
  echo "FAIL: truncated embedded bug report passed validation" >&2
  exit 1
fi
if [[ "$output" != *"完整正文不一致"* ]]; then
  echo "FAIL: unexpected validation error: $output" >&2
  exit 1
fi

python3 - "$RUN_DIR/bugs/BUG-001-auth-timeout.md" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
path.write_text(text.replace("  severity: P1\n", "", 1), encoding="utf-8")
PY

set +e
output="$(python3 "$BUILDER" --run-dir "$RUN_DIR" --output "$REPORT" 2>&1)"
rc=$?
set -e
if [[ "$rc" -eq 0 ]]; then
  echo "FAIL: bug report missing severity passed validation" >&2
  exit 1
fi
if [[ "$output" != *"缺少 bug 元数据字段: severity"* ]]; then
  echo "FAIL: unexpected metadata error: $output" >&2
  exit 1
fi

python3 - "$RUN_DIR/bugs/BUG-001-auth-timeout.md" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
path.write_text(
    text.replace("  status: OPEN\n", "  status: OPEN\n  severity: P1\n", 1),
    encoding="utf-8",
)
PY

python3 - "$RUN_DIR/bugs/BUG-001-auth-timeout.md" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
path.write_text(
    text.replace("## 8. 影响评估\n", "## 8. 被错误省略的章节\n", 1),
    encoding="utf-8",
)
PY

set +e
output="$(python3 "$BUILDER" --run-dir "$RUN_DIR" --output "$REPORT" 2>&1)"
rc=$?
set -e
if [[ "$rc" -eq 0 ]]; then
  echo "FAIL: incomplete source bug report passed validation" >&2
  exit 1
fi
if [[ "$output" != *"缺少 Bug Report 必填章节: 影响评估"* ]]; then
  echo "FAIL: unexpected incomplete bug error: $output" >&2
  exit 1
fi

python3 - "$RUN_DIR/bugs/BUG-001-auth-timeout.md" "$RUN_DIR/results.json" <<'PY'
from pathlib import Path
import sys

bug_path = Path(sys.argv[1])
bug_path.write_text(
    bug_path.read_text(encoding="utf-8").replace(
        "## 8. 被错误省略的章节\n",
        "## 8. 影响评估\n",
        1,
    ),
    encoding="utf-8",
)
results_path = Path(sys.argv[2])
results_path.write_text(
    results_path.read_text(encoding="utf-8").replace(
        '"BUG-001"',
        '"BUG-002"',
        1,
    ),
    encoding="utf-8",
)
PY

set +e
output="$(python3 "$BUILDER" --run-dir "$RUN_DIR" --output "$REPORT" 2>&1)"
rc=$?
set -e
if [[ "$rc" -eq 0 ]]; then
  echo "FAIL: results bug id without a full bug report passed validation" >&2
  exit 1
fi
if [[ "$output" != *"results 引用了 BUG-002"* ]]; then
  echo "FAIL: unexpected missing bug report error: $output" >&2
  exit 1
fi

NOBUG_DIR="$TMP_DIR/merge-coordinator-c9d4-001"
mkdir -p "$NOBUG_DIR"
cat >"$NOBUG_DIR/merged-summary.md" <<'EOF'
# 测试速览

本轮未发现新问题。
EOF
cat >"$NOBUG_DIR/merged-results.json" <<'EOF'
{
  "merge_id": "merge-coordinator-c9d4-001",
  "items": [
    {
      "id": "QOT-01",
      "status": "pass",
      "bug_ids": []
    }
  ]
}
EOF
python3 "$BUILDER" \
  --run-dir "$NOBUG_DIR" \
  --output "$NOBUG_DIR/FULL-TEST-REPORT-CN.md"
python3 "$BUILDER" \
  --run-dir "$NOBUG_DIR" \
  --output "$NOBUG_DIR/FULL-TEST-REPORT-CN.md" \
  --validate-only
grep -Fq '本轮无 Bug Report。' "$NOBUG_DIR/FULL-TEST-REPORT-CN.md"

echo "full report assembly and bug embedding validation passed"

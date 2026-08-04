#!/bin/bash

bt_post_test_checklist_output() {
  local file_path="$1"
  local cwd="${2:-}"

  if [[ -z "$file_path" ]]; then
    return 0
  fi

  if ! printf '%s\n' "$file_path" | grep -q 'results\.json'; then
    return 0
  fi

  if ! bt_is_test_history_path "$file_path" "$cwd"; then
    return 0
  fi

  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PostToolUse",
      additionalContext: "⚠ better-test post-completion checklist (auto-injected):\n□ strict validator — 用 skill 的 scripts/validate-results.sh 对 results.json 做非 advisory 校验；release run 的 gate / DoD / readiness 都闭合了吗？\n□ bugs/ — 每个 bug 都有按 Schedule 写全的 8 节正文 + 完整 YAML 元数据吗？post-ship bug 是否同步 escapes.json 并通过 validate-escapes.py？\n□ L2 独立验证 — spawn 子 Agent 做对抗审查（执行审计 + 覆盖率对账 + 证据审计 + Bug Report Schedule 完整性）\n□ FULL-TEST-REPORT.md — 用 scripts/build-full-report.py build + --validate-only；逐字包含全部完整 Bug Reports、审计和机器结果；开发者只接收这一份文件\n□ 增量 reflect — 稳定性评分 + 耗时校准 + impact-map 验证 + 经验提取\n□ 共享知识文件更新 — test-groups / impact-map（derived view 由 merge 更新）\n□ progress.md — 关键发现记了吗？\n□ checkpoint — 需要跨 session 续跑吗？\n□ 多 tester 场景 — 完成后通知用户，等所有 tester 完成后由 /better-test merge 合并；final verdict 前完成独立 verdict challenge\n\n## 清理 checklist\n□ 临时凭据 — 只删本 run 登记的精确路径；禁止跨 tester glob\n□ orphan 进程 — 只处理本 run 登记且 PID/binary/start/port/owner 均匹配的进程；归属不明则报告\n□ orphan orders — 专用账号按 standing authorization 自动执行并对账；其他账号需要新授权和独占范围确认\n□ 测试副作用 — margin 消耗、账户状态变化记入 process-log\n\n以上步骤在 Phase B 实测中全部被跳过。不要标 done 直到全部完成。"
    }
  }'
}

#!/bin/bash

bt_post_test_checklist_output() {
  local file_path="$1"

  if [[ -z "$file_path" ]]; then
    return 0
  fi

  if ! printf '%s\n' "$file_path" | grep -q 'results\.json'; then
    return 0
  fi

  if ! printf '%s\n' "$file_path" | grep -qE '\.better-work/test/history/'; then
    return 0
  fi

  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PostToolUse",
      additionalContext: "⚠ better-test post-completion checklist (auto-injected):\n□ bugs/ — 每个 bug 写了独立报告到 run 目录内 bugs/ 吗？\n□ L2 独立验证 — spawn 子 Agent 做对抗审查（执行审计 + 覆盖率对账 + 证据审计）\n□ 增量 reflect — 稳定性评分 + 耗时校准 + impact-map 验证 + 经验提取\n□ 共享知识文件更新 — test-groups / impact-map（derived view 由 merge 更新）\n□ progress.md — 关键发现记了吗？\n□ checkpoint — 需要跨 session 续跑吗？\n□ 多 tester 场景 — 完成后通知用户，等所有 tester 完成后由 /better-test merge 合并\n\n以上步骤在 Phase B 实测中全部被跳过。不要标 done 直到全部完成。"
    }
  }'
}

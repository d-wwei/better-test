# Feedback Workflow

`/better-test feedback <id> <verdict> [note]` — 把开发者/人类对某测试项的反馈录入系统，自动提炼为规则，避免下次 strategy 重复提报已知问题。

## 为什么需要 feedback

测试跑完发现 fail → 提报给开发者 → 开发者回复"这是预期行为"或"已修在另一个分支"。如果不录入：
- 下次 strategy 仍然把这项当 active fail，推荐 bug-retest
- 报告里仍然显眼，淹没真正的新问题
- 知识只活在某次对话里，下个 session 丢失

录入 feedback 把"开发者口头答复"固化为机器可读规则。

## 命令格式

```
/better-test feedback <test_id> <verdict> [--note "<text>"]

verdict 取值（共 6 种）:
  not-a-bug          预期行为，不是 bug
  fixed              已在某 commit 修复，等下次回归验证
  fixed-differently  改动不在 fix 本身，而在 EXPECT_PATTERN/测试逻辑
  wontfix            开发者明确不修
  deferred           推迟到未来某版本修
  revoke             撤销之前对该 test_id 的任何 feedback（详见"撤销 feedback"段）
```

如果用户口头报告但没指定 verdict，agent 应**主动反问**："开发者怎么说？是 not-a-bug、fixed、wontfix 还是 deferred？" 不要自行猜测。

## 执行流程

### Step 1: 验证 test_id 存在

```
读 .better-work/test/history/<current_version>/run-NNN-*/results.json（最近一次）
查找 items[].id == <test_id>
不存在 → 报错并提示用户检查 ID 拼写
存在 → 继续
```

### Step 2: 写 feedback markdown 文件

```
路径: .better-work/test/history/<version>/feedback/<test_id>_<verdict>.md
内容:

---
test_id: <id>
verdict: <verdict>
version: <version>
date: <YYYY-MM-DD>
source: developer | human | inferred
---

## 反馈内容

<note>

## 对测试的影响

- [ ] 该项应改为 skip（预期行为）
- [ ] 该项的断言/EXPECT_PATTERN 需要更新
- [ ] 需要新增测试项覆盖描述的边界情况
- [ ] 无需修改测试（fix 后原测试可通过）

## 经验提取

[待补充：从这次反馈学到的可推广经验]
```

`source` 默认 `developer`。如果是 agent 自己推断的（很少用），标 `inferred` 并要求人类 review。

### Step 3: 自动提炼为规则（write to feedback-rules.json）

按 verdict 类型映射到 `feedback-rules.json` 的不同段：

```json
{
  "suppress": [
    {"test_id": "<id>", "reason": "<note>", "since": "<version>"}
  ],
  "known_behaviors": [
    {"pattern": "<id>", "note": "<note>", "since": "<version>"}
  ],
  "lessons": [
    {"insight": "<text>", "added": "<date>"}
  ]
}
```

| verdict | 写入段 | 行为 |
|---------|-------|------|
| not-a-bug | `suppress` | 永久排除 active failures |
| wontfix | `suppress` | 永久排除 active failures |
| deferred | `known_behaviors` | 仍算 fail，但提示"已知" |
| fixed | （不写 suppress）| 等下次跑通过验证；下次跑通过后自动从 active fail 移除 |
| fixed-differently | `known_behaviors` + 提示用户更新 test-groups.md 中该项的断言 | |

**重要**：`feedback-rules.json` 由本 skill 自动维护，**严禁人手编辑**（red line #7）。如果要调整规则，撤回并重新走 `/better-test feedback`。

### Step 4: 同步更新 known-issues.md（人类视图）

`feedback-rules.json` 是机器视图（json，agent 读），`known-issues.md` 是人类视图（markdown，团队读）。每次 Step 3 后同步：

```markdown
# Known Issues

## 已 suppress（不算 active failures）

| Test ID | Verdict | 来源版本 | 原因 |
|---------|---------|---------|------|
| <id>    | not-a-bug | v<ver> | <reason> |

## 已知行为（仍算 fail，但已知）

| Pattern | 描述 | 来源版本 |
|---------|------|---------|
| <pattern> | <note> | v<ver> |

## 经验教训

- <insight> （<date>）
```

### Step 5: refresh status.md

调用 `context_refresh` 等价的逻辑：基于最新 results.json + feedback-rules.json，重新生成 `status.md`。这样下个 session 加载 status.md 就看到最新状态。

### Step 6: git commit

```
git -C .better-work/ add test/history/feedback test/history/feedback-rules.json test/known-issues.md test/status.md
git -C .better-work/ commit -m "[better-test] feedback: <test_id> (<verdict>) in v<version>"
```

commit message 前缀 `[better-test]` 是子 skill 的来源标记（架构文档第 8.1 节要求）。

## 经验规则（lessons）的特殊处理

`lessons` 段不绑定具体 test_id，是从多次 feedback 提炼出的可推广经验。例：
- "MCP 工具的参数风格是 `symbols` 数组而非 `security_list`"
- "REST POST 必须 unlock-trade 之后才能下单"

写入时机：
- agent 在录入 feedback 时主动识别"这条是不是有可推广性"
- 或用户显式说"把这条也作为 lesson 记下来"
- 不要每条 feedback 都自动产生 lesson（避免噪声）

## 撤销 feedback

如果误录或开发者改口：

```
/better-test feedback <id> revoke
```

执行：
- 从 `feedback-rules.json` 中移除该 id 的所有条目
- 从 `feedback/<id>_*.md` 重命名为 `<id>_<verdict>_REVOKED.md`（保留历史）
- commit message: `[better-test] revoke feedback: <test_id>`

## 不要做的事

- ❌ 不要不带 verdict 就直接写 markdown —— verdict 决定后续自动化行为
- ❌ 不要人手编辑 `feedback-rules.json` —— 破坏自动化，无法追溯来源
- ❌ 不要在 verdict=fixed 时写 suppress —— fixed 应该被下次跑证明，不是被规则掩盖
- ❌ 不要把 lesson 当作"反馈"录入（lesson 不绑定 test_id）—— 用 update workflow 单独维护

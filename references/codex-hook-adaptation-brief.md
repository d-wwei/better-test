# Codex Hook 适配任务 Brief

> 本文件是给 Codex agent 的任务说明。目标：让 better-test 的 L1 Hook 约束层在 Codex 上也能工作。

## 重要前提

**better-test 是跨平台 skill，同时服务 Claude Code 和 Codex。** 任何改动必须保证两个平台都能用。不能改完只有 Codex 能用、Claude Code 坏了。

当前适配方案在 `references/adapters.md`：
- Claude Code：`@` 引用 + settings.json hooks
- Codex：SKILL.md 原生兼容 + AGENTS.md 嵌入 + `$better-test` 调用

---

## 背景：四层约束框架

better-test 设计了 4 层约束机制（详见 `code/constraint-framework.md`）：

| 层 | 机制 | 作用 |
|----|------|------|
| L0 | protocol.md 注入 | 校准 agent 思维方向 |
| L1 | 5 个 Hook 脚本 | 系统级拦截/记录/提醒 |
| L2 | 子 Agent 审查 | 独立验证（执行审计/覆盖率/证据） |
| L3 | 审计面板 | 人类 30 秒审查 |

**L0/L2/L3 是平台无关的**——protocol 注入通过 adapter 适配，L2 prompt 是纯文本，L3 是 markdown 文件。

**L1 是 Claude Code 专属的。** 5 个 hook 脚本依赖 Claude Code 的 `settings.json` 的 `PreToolUse` / `PostToolUse` 机制。Codex 没有等价机制。

---

## 问题：L1 在 Codex 上完全不工作

### 5 个 Hook 及其作用

| Hook | 文件 | 类型 | 作用 | Codex 上的状态 |
|------|------|------|------|---------------|
| 凭证扫描 | `hooks/credential-scan.sh` | PreToolUse Edit/Write | 拦截写入 .better-work/ 的凭证 | **不工作** |
| feedback-rules 保护 | `hooks/feedback-rules-guard.sh` | PreToolUse Edit/Write | 阻止直接编辑 feedback-rules.json | **不工作** |
| 执行日志记录 | `hooks/execution-log.sh` | PostToolUse Bash | 自动记录每条命令到 execution-log.md | **不工作** |
| 测试完成清单 | `hooks/post-test-checklist.sh` | PostToolUse Write | results.json 写入后注入后处理提醒 | **不工作** |
| 结果字段检查 | `hooks/results-validation.sh` | PostToolUse Write | 检查 results.json 必填字段 | **不工作** |

### 影响

没有 L1 → Codex agent 在测试时：
1. **没有执行日志** — L2 子 Agent 做执行审计时没有数据源（"agent 说跑了 9 项，没有 log 可以验证"）
2. **没有完成提醒** — 测试完成后不会弹 checklist，后处理步骤会全部跳过（Phase B 实测已证明：没有提醒 = 全部跳过）
3. **没有字段检查** — results.json 可以写入空断言字段、非标 ID、indirect 证据标 pass
4. **没有凭证拦截** — 可能把密码写入知识文件
5. **没有文件保护** — 可以直接编辑 feedback-rules.json 破坏自动化链

---

## 需要做什么

研究 Codex 的扩展/middleware/hook 机制，找到 L1 的等价实现方式。

### 需要回答的问题

1. **Codex 有没有类似 Claude Code 的 PreToolUse/PostToolUse hook？** 如果有，用什么格式配置？
2. **如果没有原生 hook，Codex 有没有其他方式在工具调用前后执行自定义逻辑？** 比如 middleware、plugin、wrapper、agent hooks 等。
3. **如果完全没有 hook 能力，能否用 wrapper 脚本模式？** 即 agent 不直接跑 `curl xxx`，而是跑 `./tools/run-and-log.sh curl xxx`，wrapper 内部自动记录到 execution-log。

### 实现要求

**不管用什么方式实现，最终效果要和 Claude Code 的 hook 等价：**

| 效果 | 必须做到 |
|------|---------|
| 凭证扫描 | 写入 .better-work/test/ 路径时，自动检查凭证模式 |
| feedback-rules 保护 | 阻止直接编辑 feedback-rules.json |
| 执行日志 | **每条 shell 命令自动记录到 execution-log.md**（这是最关键的——L2 审计依赖它） |
| 完成提醒 | results.json 写入后，agent 能看到后处理 checklist |
| 字段检查 | results.json 写入时检查必填字段 |

### 约束

- **不能破坏 Claude Code 的 hook 配置** — 现有的 `hooks/*.sh` 脚本和 `settings.json` 配置必须继续工作
- **hook 脚本本身是平台无关的 bash** — 如果 Codex 有 hook 机制，可以直接复用同一批脚本
- **如果 Codex 需要不同的配置格式**（比如不是 settings.json 而是 codex.yaml），在 `adapters.md` 中补充 Codex 的 hook 配置方式
- **如果完全无法实现某个 hook**，在 `adapters.md` 中标注"Codex 限制：XXX hook 不可用，降级为 workflow 步骤"

---

## 参考文件

| 文件 | 内容 |
|------|------|
| `hooks/*.sh` | 5 个 hook 脚本源码 |
| `hooks/README.md` | hook 安装和测试说明 |
| `code/constraint-framework.md` | 四层约束框架完整设计（L1 段有 hook 设计理由） |
| `code/phase-b-report.md` | Phase B 实测报告——证明没有 hook 时 agent 遵守率约 40% |
| `references/adapters.md` | 现有的多平台适配方案 |
| `references/l2-audit-prompts.md` | L2 审计 prompt——Audit 1 依赖 execution-log |

---

## 成功标准

1. Codex 上 5 个 hook 效果中至少 3 个有等价实现（execution-log 必须在内）
2. Claude Code 的 hook 继续正常工作（回归验证）
3. `adapters.md` 更新了 Codex 的 hook 配置方式
4. 如果有无法实现的 hook，有明确的降级方案记录

**[English](README.md)** | **中文**

# better-test

### 失败模式 #4："跑错了测试。" 这个仓库解决这个问题。

AI 编程 agent 在大型代码库上有五种失败模式，其中最少被修复的一种：

> 跑错了测试——跑了单元测试，漏了集成测试。

不是态度问题。Agent 不知道哪些测试覆盖哪些变更，不知道哪些测试已经因为已知原因在挂，不知道你关心的那个测试需要真实账户才能跑。

这些知识散落在 Slack 聊天、发布工程师的脑子里、没人再读的事后复盘里。Session 之间蒸发殆尽。

`better-test` 把它们固化——[Full Context + Proportional Control](https://github.com/d-wwei/better-work) 框架的测试侧。持久化的测试手册、开发者反馈循环、经验提取机制，加上 4 层约束框架和 8 个系统级 Hook 防止 agent 偷工减料。

## v3.x 新特性

v3.0：多 Agent 并行测试 + tester/coordinator 两角色架构。
v3.1：Hook 强制执行、Protocol 拆分、Skill 升级管线。
v3.1.2：可扩展 team-role preset，用于多 tester 计划和 merge。
v3.2：严格 results/gate/DoD 校验、可独立审计的证据、完整 Tier-2 资源与确定性 CI。

核心能力：

- **8 个 L1 Hook + gate.sh 统一入口** — 凭证扫描、feedback-rules 保护、derived-view 保护、session 隔离、执行日志、完成清单、结果校验、注册门控。gate.sh 从全局配置自动检测项目（无需逐项目配置）
- **Protocol 拆分** — `protocol-base.md`（skill 级，自动传播）+ 项目 `protocol.md`（安全+项目纪律）。Skill 升级自动同步到所有项目
- **Tester 隔离** — 并行 agent 各自写 `run-<tester-id>-NNN/`。`/better-test merge` 生成统一结果
- **可扩展 team-role preset** — 固定的是 role schema，不固定唯一编制；内置 `release-4way`、`api-3way`、`single-plus-l2`
- **4 层约束框架**（L0 目标校准、L1 Hook、L2 子 Agent 独立验证、L3 人类审计面板）
- **49 条实战经验** 从真实项目测试中提炼并融入（futu-opend-rs v1.4.26-v1.4.59）
- **Skill 升级管线** — medium 风险经验在会话内当场审核并原子落地；只有明确延后或 high 风险项进入 `pending-skill-upgrades.md`
- **经验提取**（`/better-test reflect`）— 从测试历史中学习
- **差异测试**（`compare` 模式）— Rust 重写 vs C++ 原版对照
- **Bug 生命周期管理** — OPEN → CONFIRMED → FIXED → VERIFIED → CLOSED

## 工作原理

三个知识文件存储你的团队知道但 CI 不知道的信息：

| 文件 | 内容 |
|------|------|
| `test-groups.md` | 测试组定义：覆盖范围、运行命令、断言字段、稳定性评分 |
| `impact-map.md` | 变更关键词/文件路径 → 受影响的测试组（带证据分级） |
| `known-issues.md` | 已知失败、开发者判定、flaky 测试稳定性评分、经验教训 |

代码变更后：

```
/better-test strategy
  → 读 impact-map + known-issues + bugs-index + git diff
  → 推荐："跑 A、B、D 组 — 22 项，约 8 分钟"
  → 解释："src/auth/session.rs 命中 impact-map 关键词 'auth' → A 组"
  → 检查：凭证就绪？变更批量？金字塔结构？

# 按项目专属计划执行：
  → 从 test-groups + known-issues + protocol 生成执行计划
  → 四色标记：✅/🟡/🔴/⏭️ 带证据分级
  → 完成后自动增量 reflect：验证映射、更新评分

# 测试失败后开发者反馈：
/better-test feedback D-04 not-a-bug --note "开发者确认是预期行为"
  → 写入 history/ + 提取 suppress 规则
  → 下次 strategy 自动排除 D-04
```

## 反馈循环

大多数测试工具止步于"跑这些测试"。`better-test` 构建一个持续增长的知识库：

```
init → strategy → execute → reflect → feedback → update → strategy（更精准）
  ↑                                                                        ↓
  └──────────────── 知识文件随使用越来越准 ←────────────────────────────────┘
```

每次测试运行让下次更好：impact-map 映射被验证、稳定性评分被校准、耗时预估被修正、经验被提炼。

## 约束框架

4 层防线确保 agent 的测试质量，每层接住上一层漏掉的：

| 层 | 机制 | 捕获什么 |
|----|------|---------|
| L0 目标校准 | protocol.md 把 agent 重定义为"测试审计员" | 训练偏向：倾向乐观/完整/确定 |
| L1 Hook | 8 个系统级 Hook（凭证扫描、权限保护、执行日志、结果校验、注册门控...） | 机械错误：agent 可能忘记检查的 |
| L2 独立验证 | 子 Agent 审计执行日志 vs 声称、覆盖率 vs manifest、证据质量 | 认知错误：跳过步骤、假通过、证据不足 |
| L3 人类审计面板 | 20 行决策导向摘要，从结构化数据组装 | 最终判断：模糊项由人裁决，30 秒通过/打回 |

## 安装

### 所有平台（自动检测）

```bash
git clone https://github.com/d-wwei/better-test.git ~/src/better-test
cd ~/src/better-test
./install.sh            # 自动检测 Claude Code、Codex 等，创建 symlink
./install.sh status     # 查看 canonical 路径、Git revision 和 symlink 状态
```

只保留这一份 canonical Git checkout。Claude 和 Codex 必须通过 symlink 读取同一源码，不要把仓库
复制到多个 skills 目录。安装器不会覆盖已有真实目录；请先备份或迁移，再重新执行安装。

运行时校验依赖 Bash、`jq` 和 Python 3；认证态 Codex 冒烟测试还要求本机 `codex` CLI 已登录。

### Claude Code（手动）

```bash
ln -s ~/src/better-test ~/.claude/skills/better-test
```

### Codex CLI（手动）

```bash
ln -s ~/src/better-test ~/.codex/skills/better-test
```

Codex 用 `$better-test` 调用（不同于 Claude Code 的 `/better-test`）。SKILL.md 格式原生兼容，无需转换。

### 其他平台

Cursor、Gemini CLI、OpenCode、OpenClaw 的适配安装命令见 `references/adapters.md`。测试知识文件是平台无关的。

## 快速开始

```
/better-test init
```

技能分类项目（11 种类型：库、服务、API、CLI、移动端、桌面端、浏览器扩展等），收集材料（API 规范、PRD、错误码表），探索测试结构，生成知识文件。

## 命令参考

| 命令 | 功能 |
|------|------|
| `/better-test init` | 探索测试结构 + 收集材料 + 生成知识文件 |
| `/better-test strategy` | 分析变更 → 推荐测试集。含 `compare` 差异测试模式 |
| `/better-test feedback <id> <verdict>` | 录入开发者判定 → 自动提炼 suppress 规则 + 回归 canary |
| `/better-test update` | 信号驱动的增量更新（新测试、新映射、用户提供的新材料） |
| `/better-test reflect [scope]` | 从历史中提取经验：映射验证、稳定性趋势、bug 热点、经验综合 |
| `/better-test protocol-update [text]` | 从用户输入或会话总结升级认知约束 |
| `/better-test merge` | 合并多 tester 结果 — 交互式选择 run，冲突检测，统一报告 |
| `/better-test checkpoint` | 保存当前测试任务进度 |
| `/better-test resume` | 从上次断点恢复 |

所有命令通过 `/better-work test <cmd>` 同样可用（安装了 better-work 时）。

## 架构

```
references/
├── Tier 1: Workflow 文件（按命令加载）
│   ├── init-workflow.md              探索 + 材料收集 + 代码读取
│   ├── strategy-workflow.md          变更检测 + 影响分析 + 决策树 + 差异测试
│   ├── team-role-presets.md          可扩展 team schema + preset + coordinator 协议
│   ├── test-execution-workflow.md    框架 + 模板，生成项目专属执行计划
│   ├── feedback-workflow.md          判定录入 + 规则提炼 + 回归 canary
│   ├── reflect-workflow.md           6 类历史分析（增量 + 全量）
│   ├── update-workflow.md            6 类信号（含用户新材料）
│   ├── protocol-update-workflow.md   认知约束升级 + changelog
│   └── progress-workflow.md          断点续传
│
├── Tier 2: 扩展流程（条件触发）
│   ├── procedures/bdd-scenarios.md         有 PRD 时触发
│   ├── procedures/tdd-flow.md              写新代码时触发
│   ├── procedures/contract-testing.md      多服务交互时触发
│   ├── procedures/exploratory-charter.md   深度测试时触发
│   ├── procedures/hypothesis-investigation.md   调查升级时触发
│   ├── procedures/mutation-testing.md      代码变更 + full/targeted 时触发
│   ├── procedures/flakiness-scoring.md     flaky 信号时触发
│   ├── procedures/bug-report.md            发现 bug 时触发
│   ├── procedures/longrun-testing.md       24h+ 稳定性测试
│   └── procedures/combinatorial-testing.md pairwise / 等价类覆盖
│
└── Tier 3: 设计文档（人阅读，agent 不加载）
    └── methodologies/design-rationale.md   研究引用 + 设计理由
```

## Better-Work 系列

- **[better-work](https://github.com/d-wwei/better-work)** — Lite Control + 系列入口
- **[better-code](https://github.com/d-wwei/better-code)** — 研发侧的 Full Context
- **better-test**（本仓库）— 测试侧的 Full Context

## 局限性

- **不内置测试执行器。** 推荐跑什么测试和为什么。实际执行用项目自己的工具链。
- **`impact-map.md` 精度随时间增长。** 初始条目基于关键词推断；`/better-test reflect` 从测试历史中验证和升级。
- **`feedback-rules.json` 自动生成。** 严禁手动编辑。用 `feedback <id> revoke` 撤回。
- **Hook 已落地，但需按平台单独安装/启用。** Claude Code 走 `gate.sh` + hooks 配置；Codex 走项目 `.codex/hooks.json`，安装器会识别新版 `hooks` 与旧版 `codex_hooks` feature。具体见 `hooks/README.md` 与 `references/adapters.md`。
- **CI 覆盖确定性检查。** 需要真实认证并调用在线模型的 Codex runtime smoke 仍作为人工发布门禁。

## License

MIT.

---

系列完整介绍：[Full Context, Proportional Control](https://github.com/d-wwei/better-work) 设计理念见系列入口 README。

问题、反馈、讨论：[GitHub issues](https://github.com/d-wwei/better-test/issues)。

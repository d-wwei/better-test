---
name: better-test
description: |
  测试知识管理：为项目构建持久化的测试组定义、变更影响映射、已知问题库和测试认知约束，支持变更驱动的策略推荐、跨 session 反馈循环和断点续传。Better-Work 系列子技能。
  触发场景：发布新版本前回归、修了 bug 想验证、变更后想知道跑哪些测试、录入开发者反馈避免重复提报。独立命令 /better-test，或作为子技能 /better-work test。
  Subcommands: init, update, strategy, feedback, protocol-update, reflect, checkpoint, resume
argument-hint: "init | update | strategy | feedback <id> <verdict> | protocol-update [text] | reflect [scope] | checkpoint | resume"
---

# Better Test

为有持续测试需求的项目（库、daemon、API、CLI）构建和维护测试知识系统。让 agent 在变更后能 ≤2 步内知道该跑哪些测试、哪些是已知 fail、上次跑到哪里。

## Stance

像一个资深测试工程师在做交接——只讲能防止"白跑测试"和"重复提报已知问题"的关键信息。pass 必须基于返回值字段验证而非状态码；skip 必须醒目；feedback 提炼成规则而非沉没在历史里。

## Commands

- `/better-test init` — 探索测试结构，生成 `.better-work/test/` 知识文件
- `/better-test update` — 信号驱动的增量更新（新测试、新 bug、新组）
- `/better-test strategy` — 基于变更分析推荐测试策略（smoke / targeted / bug-retest / full）
- `/better-test feedback <id> <verdict> [--note "..."]` — 录入反馈，提炼为 known-issues 规则。verdict ∈ `not-a-bug` / `fixed` / `fixed-differently` / `wontfix` / `deferred` / `revoke`
- `/better-test protocol-update [text]` — 升级测试认知约束：用户输入新原则或自动总结会话经验，确认后写入 protocol.md + changelog
- `/better-test reflect [scope]` — 从历史数据提取经验：impact-map 验证、稳定性趋势、bug 热点、经验综合、耗时校准、模式提炼。增量版在每次测试后自动执行
- `/better-test checkpoint` — 保存当前测试任务进度
- `/better-test resume` — 从上次断点恢复

## Output Structure

```
.better-work/                              ← 与 better-code 共享
├── shared/                                ← 读/写：所有 skill 可读写（架构 8.1）
│   └── index.md                           ← 优先只读；如写则 commit 标 [better-test]
├── code/                                  ← 只读：高风险区域 → 触发更全面测试
│   └── danger-zones.md
└── test/                                  ← 写：测试专用
    ├── protocol.md                        ← 共享知识：测试认知约束（≤15 行），每对话注入
    ├── protocol-changelog.md              ← 共享知识：变更日志（叙事+KAC 混合格式）
    ├── protocol-versions/                 ← 共享知识：protocol 全文快照（每次 update 前保存）
    ├── test-groups.md                     ← 共享知识：测试组定义 + 运行条件
    ├── impact-map.md                      ← 共享知识：变更关键词 → 测试组映射
    ├── known-issues.md                    ← 共享知识：已知 fail / 预期行为 / 经验
    ├── env-config.md                      ← 共享知识：测试环境配置，init 创建，随时 update
    ├── surface-manifest.md                ← 共享知识：接口清单 SSOT（API/CLI/daemon 适用）
    ├── tools/                             ← 共享：跨版本复用的测试脚本（surface-walk.sh 等）
    ├── reference/                         ← 共享：暂存参考资料
    │
    ├── testers/                           ← tester 注册中心（多 agent 并行隔离）
    │   └── <tester-id>/                   ← 每个 tester 独立目录
    │       ├── bio.md                     ← 身份 + session 链 + working notes + 追溯路径
    │       ├── status.md                  ← 此 tester 的最新测试状态
    │       ├── progress.md                ← 此 tester 的断点
    │       └── strategy-plan.md           ← 此 tester 的分阶段执行计划（strategy 输出）
    │
    ├── status.md                          ← 聚合视图（从 testers/*/status.md 自动合并）
    │
    └── history/                           ← 测试运行历史（git-tracked）
        ├── _meta.json
        ├── feedback-rules.json            ← 共享：自动维护，勿手编
        ├── bugs-index.md                  ← 共享：跨版本 bug 索引
        └── <version>/
            ├── run-<tester-id>-NNN-<ts>/  ← 每次运行归档（tester-id 防并发碰撞）
            │   ├── results.json + summary.md + process-log.md
            │   ├── execution-log.md + l2-findings.md + audit-report.md
            ├── feedback/<test_id>_<verdict>.md
            └── bugs/BUG-<tester-id>-NNN-<slug>.md
```

**tester-id**：格式 `<platform>-<4hex>`（如 `claude-a3f2`、`codex-c9d4`），由 `sha1(session_id + timestamp)[:4]` 生成。一个 tester 可跨 session 存活（通过 resume），但同一时刻一个 tester 只对应一个进程。详见 `references/templates.md` 的 bio.md 模板。

**时间戳规范**：所有时间戳统一为 ISO 8601 + 时区偏移，三档精度：Full `2026-04-21T14:23:07+08:00`、Compact `04-21 14:23:07+08`、Date-only `2026-04-21`。详见 `references/templates.md` 的 Timestamp Format Specification。

**注入**（Claude Code 示例）：项目 CLAUDE.md 中追加 `@.better-work/test/protocol.md`。其他文件按需 Read。

## Red Lines

1. `protocol.md` 超过 15 行 → 必须精简，不可突破
2. pass 判定只依赖退出码或"输出非空"（不验证返回值字段） → 违反测试铁律，必须改用具体字段断言
3. skip 没有醒目标注（视觉上等同 pass） → 违规，必须明确 `~` 或 `[skip]` 标记并附原因
4. `test-groups.md` 中条目缺少"运行条件"（环境、依赖、是否需要真账户）或"如何运行" → 不完整
5. `impact-map.md` 中关键词→测试组的映射没有验证依据（人类知识或历史 fail 共现） → 必须标注 `[未验证]`
6. `known-issues.md` 写入时未附 test_id + 判定来源（developer / human / inferred） → 违规
7. `feedback-rules.json` 被人手编辑（应通过 `/better-test feedback` 提炼） → 违规，破坏自动化
8. `testers/<tester-id>/progress.md` 中记录无法被下一个 session 理解的模糊状态（如"差不多跑完了"） → 违规，必须精确到测试 ID 和组
9. `init` 时跑全部测试以"摸清当前状态" → 违规，init 只读知识不执行测试
10. flaky 测试连续 2+ 次表现不一致时，未在 `known-issues.md` 的 Flaky 段标注或未发起 `/better-test feedback ... deferred` → 违规，flaky 不能默默吞掉
11. `bio.md` 的 working notes 超过 20 条 → 必须归档旧条目到 session log，保持可读性
12. 时间戳不带时区偏移（如裸 `2026-04-21 14:23` 或 `<ISO>` 占位符） → 违规，必须使用三档规范格式

## Acceptance Criteria

1. 新对话加载 `protocol.md` + Read `status.md` 后，agent 能准确说出"当前版本是什么 / 哪些 ID 在挂 / 哪些已 suppress"，无需重跑
2. 代码变更后，agent 通过 `/better-test strategy` 在 ≤2 步内确定要跑的组（基于 impact-map.md + 变更信号），并显示推荐理由
3. 同一个 bug 用 `/better-test feedback <id> wontfix` 录入后，下次 strategy 推荐时该项自动从 active failures 排除，不再重复提报
4. `checkpoint` + `resume` 后，agent 能准确复述上次跑到哪个组的哪个 ID（resume 时列出所有 tester，用户选择要恢复的 tester）。如有 `strategy-plan.md`（status: confirmed 或 in-progress），resume 可跳过重跑 strategy 直接从计划续跑
5. `references/adapters.md` 为每个支持平台（Claude/Cursor/Gemini/Codex/OpenCode/OpenClaw）都给出**可粘贴执行**的注入语法（@ 引用 vs 内容嵌入），无 placeholder 占位
6. 多 tester 并发测试时，各 tester 的 status/progress/run 目录互不干扰，聚合 status.md 正确合并所有 tester 状态

## References

三层加载架构：Tier 1 核心流程嵌入 workflow（每次执行自动加载）、Tier 2 扩展流程按条件加载、Tier 3 方法论参考供人类阅读（agent 不加载）。

### Tier 1: Workflow 文件（含嵌入的核心流程）

| File | Load When | Content |
|------|-----------|---------|
| `references/init-workflow.md` | `/better-test init` | 测试结构探索 + 材料收集 + 代码读取 + 生成知识文件。内嵌：新测试 4 问 |
| `references/update-workflow.md` | `/better-test update` | 5 类信号检测 + 增量更新。内嵌：新测试 4 问 |
| `references/strategy-workflow.md` | `/better-test strategy` | 变更检测 + 影响分析 + 决策树 + 条件检查（批量/组合策略/发布建议） |
| `references/test-execution-workflow.md` | 测试执行阶段 | **框架 + 模板**：结合通用纪律 + 项目知识生成专属执行计划。内嵌：四色标记 + 证据分级 + 错误三问 + 终态规则 + 安全守则 + 覆盖率报告 |
| `references/feedback-workflow.md` | `/better-test feedback` | 反馈录入 + 规则提炼 + suppress。内嵌：回归 canary 提示 |
| `references/l2-audit-prompts.md` | 测试完成后（full/targeted/compare/bug-retest） | L2 子 Agent 审查 prompt：执行审计 + 覆盖率对账 + 证据审计 + l2-findings.md 格式 |
| `references/protocol-update-workflow.md` | `/better-test protocol-update` | 认知约束升级 + changelog |
| `references/reflect-workflow.md` | `/better-test reflect` | 历史经验提取：6 类分析 + 增量/全量两层机制 |
| `references/progress-workflow.md` | `/better-test checkpoint` 或 `resume` | 断点续传 |
| `references/templates.md` | 生成输出文件时 | 核心文件的模板 + 质量标准 |
| `references/adapters.md` | 多平台注入 | Claude / Cursor / Gemini / Codex 适配 |

### Tier 2: 扩展流程（条件触发加载）

| File | 触发者 | 触发条件 | Content |
|------|--------|---------|---------|
| `procedures/bdd-scenarios.md` | init / update | 用户在信号源 F 提供了 PRD 或验收标准 | Given-When-Then 场景生成 |
| `procedures/tdd-flow.md` | agent | 当前任务包含写新功能代码（不只是跑测试） | Red-Green-Refactor |
| `procedures/contract-testing.md` | init | Step 1 分类为 API/Web 服务 **且** 有多服务调用链 | 契约测试步骤 |
| `procedures/exploratory-charter.md` | 用户 / strategy | 用户要求"深度测试"；或 strategy 发现某模块 0 历史记录 | 探索性测试 charter |
| `procedures/hypothesis-investigation.md` | test-execution | 错误解读三问无法定位（3 问都答了仍不确定） | 3-假设法 + 调查阶梯 + 证据分级完整定义 + bug 分类 |
| `procedures/mutation-testing.md` | strategy | full/targeted **且** 有代码变更 **且** 项目有变异测试工具 | 增量变异测试 |
| `procedures/flakiness-scoring.md` | update / strategy | update 检测到 flaky 信号；或推荐组含 known-issues Flaky 项 | 稳定性评分 |
| `procedures/bug-report.md` | test-execution | 发现 bug 需要写报告 | 7 节标准格式 + yaml 元数据 |

### Tier 3: 设计文档（面向人类，agent 不加载）

| File | Content |
|------|---------|
| `references/methodologies/design-rationale.md` | 全部方法论的设计理由和研究依据：覆盖率（ICSE 2014、Google 变异测试）、调查方法（systematic-debugging、证据分级）、测试设计（TDD/BDD/契约/探索性研究数据）、执行纪律（DORA 2024、Meta flakiness）、环境陷阱、Bug Report 格式 |

## Interface Contract（与 better-work 集成）

作为 `/better-work test <cmd>` 的子技能时，better-work 把命令名透传：`/better-work test init` → `/better-test init`。本 skill 不感知是否被路由，独立可用。共享目录 `.better-work/shared/` 可读写，但优先只读；如需写共享内容，commit message 标注 `[better-test]` 来源。

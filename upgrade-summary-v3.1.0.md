# better-test Skill 升级总结 — v3.0.1 → v3.1.0

> 日期: 2026-04-26
> 触发: 17 份测试回顾文件（8 testers, v1.4.48 → v1.4.94, ~450KB）
> 方法: update-workflow Q1-Q4 决策树分流 → 按强制执行层级分配

---

## 一、输入

| 来源 | 文件数 | 原始条目 | 去重后 |
|------|--------|---------|--------|
| S1: v1.4.56 回归总结 | 1 | 19 | — |
| S2: 通用+项目经验（第二份）| 1 | 42 | — |
| S3: 通用+项目经验（第三份）| 1 | 50 | — |
| S4: reference/ 回顾文件 | 17 | ~460（3 agent 并行提取）| — |
| **合计** | **20** | **~571** | **通用 ~80 + 项目 ~30 = ~110** |

去重基准: 已有 known-issues #1-#55 + protocol 5 条项目纪律。

---

## 二、核心设计决策

### 问题

上一轮（v3.0.1）把经验往 known-issues lessons 和 pending-skill-upgrades 里塞——这两个是最弱的执行层。agent 在 strategy Step 0 提取 known-issues 后可能忘；pending-skill-upgrades 是排队完全不生效。

### 解法

按"agent 在什么时刻需要看到这条规则"分配到正确的强制执行层：

```
L0: protocol.md          — 每 session 注入，最强（≤30 行，已满）
L2: test-execution-workflow.md — 执行时加载，字段约束硬卡
L3: strategy-workflow.md      — 规划时加载，步骤级卡点
L4: templates.md              — 写输出时加载，格式标准
L5: merge-workflow.md         — 合并时加载，coordinator 角色
L6: procedures/*.md           — 条件触发加载
L7: known-issues lessons      — strategy Step 0 提取（最弱但仍有价值）
```

---

## 三、变更明细

### 3.1 新建文件

| 文件 | 层级 | 触发条件 | 内容 |
|------|------|---------|------|
| `procedures/longrun-testing.md` | L6 | strategy 包含 24h+ 长跑项 | 10 条长跑经验：三层健康验证 / daemon 6 元组身份 / canary heartbeat / 采样器自包含 / Monitor+Cron 双通道 / 采样粒度权衡 / 关键词覆盖率 / loop auto-stop / 跨 tester 命名隔离 / PID reuse 防误归 |

### 3.2 Skill 文件修改

#### test-execution-workflow.md（L2，执行时硬卡）— +79 行

| 段落 | 增补 | 条数 |
|------|------|------|
| 新增"Pass 判定 4 件套" | 下游效应真发生 / Silent empty 排除（已知有数据参数对照）/ 跨 surface 一致 / 基准对照 | 4 |
| 新增"错误消息先读" | 不同码不同根因，blind retry → anti-flood | 1 |
| 终态规则改为"4-state verdict" | PASS / PARTIAL / FAIL / SKIP，PARTIAL 是合法终态 | 1 |
| 新增"清理纪律 checklist" | kill 进程 / 删 /tmp 凭据 / cancel orphan orders / 副作用显式列出 | 1 |
| 证据质量纪律 +4 条 | inferred 升级步骤 / Before/After diff 最强证据 / timestamp+state / epoch 工具计算 | 4 |
| 环境确认 +2 条 | 端口 bind 验证（启动后 lsof 确认 PID）/ pgrep 精确到 port+account | 2 |

#### strategy-workflow.md（L3，规划时卡点）— +22 行

| 段落 | 增补 | 条数 |
|------|------|------|
| Pre-check | 测试方案可行性验证 / "做不到"前先 subagent | 2 |
| Stage 2 负向测试 | 穷举边界 7+5+4 点标准 / body 格式 4 变体矩阵 | 2 |
| 多 Agent 协调 | Dual-tester blind spot 异构需求 | 1 |
| Accuracy Rules | INCONCLUSIVE for unproven fixes | 1 |
| 不要做的事 | blind retry 禁止 / "做不到"禁止 | 1 |

#### templates.md（L4，写输出时标准）— +28 行

| 段落 | 增补 | 条数 |
|------|------|------|
| summary 写作原则 | 大白话严格定义（零术语 + 完整词汇替换）/ 报告分层 L0/L1/L2（500/1500/8000 字）| 2 |
| bug report 质量 | 三句话格式（scene+symptom+impact）/ P0 证伪门槛 / 证据文件按 bug-id 命名 | 3 |
| 质量标准通则 | denominator clarity / 精确数字可溯源 / DEMOTED header / 版本演化声明 / roundtrip 透明记录 / tester-id 文件名 / Deliverables 4 tier | 7 |

#### merge-workflow.md（L5，合并时卡点）— +33 行

| 段落 | 增补 | 条数 |
|------|------|------|
| 新增"Bug 粒度对齐" | merge 前同步 bug 定义，否则计数永远不一致 | 1 |
| 新增"Cross-Verify 覆盖率分类" | bidirectional_strict / trust_based / indirect 三分类 | 1 |
| 新增"Cross-Verify 流程" | 4 步法 + steelman 原则 + 环境对齐优先 | 1 |

#### SKILL.md — +1 行

| 段落 | 增补 |
|------|------|
| Tier 2 扩展流程表 | `procedures/longrun-testing.md` 触发条件和内容说明 |

### 3.3 项目知识文件修改

#### known-issues.md — +24 条（#67-#90）

**通用方法论（#67-#82）：**

| # | 标题 | 生效层 |
|---|------|--------|
| 67 | 4 阶段测试顺序（黑盒 smoke → 下游验证 → 灰盒 → 白盒）| L7 → strategy 提取 |
| 68 | 测试成熟度 5 级路径（L1-L5）| L7 → strategy 提取 |
| 69 | 黑盒覆盖率上限分层表（校准期望）| L7 → strategy 提取 |
| 70 | External tester 能力边界前置声明 | L7 → strategy 提取 |
| 71 | Agent 时代威胁模型转变 | L7 → strategy 提取 |
| 72 | "被动纠错"3x 成本 | L7 → strategy 提取 |
| 73 | 消耗类资源前置规划 | L7 → strategy 提取 |
| 74 | "零影响"是自欺 | L7 → strategy 提取 |
| 75 | Table↔yaml 同步 re-count | L7 → strategy 提取 |
| 76 | 断言强度语言 | L7 → strategy 提取 |
| 77 | Plausibility bias（整齐数据降低警戒）| L7 → strategy 提取 |
| 78 | 大白话 = 零术语（完整词汇替换）| L7 → strategy 提取 |
| 79 | Adversarial review 报告定稿前必做 | L7 → strategy 提取 |
| 80 | BSD sed 缺 \b（macOS 用 perl/gsed）| L7 → strategy 提取 |
| 81 | 敏感文件 trap EXIT 清理 | L7 → strategy 提取 |
| 82 | 交叉验证应前置（6h/12h 中间 sync）| L7 → strategy 提取 |

**项目专属（#83-#90）：**

| # | 标题 |
|---|------|
| 83 | REST "ret=0 s2c={}" 万能骗模式 |
| 84 | MCP/REST/CLI 三套参数命名不统一 |
| 85 | Credentials Option B 两阶段 |
| 86 | Daemon 启动参数 14 项含陷阱 |
| 87 | 账号/firm/currency 7×7 映射表 |
| 88 | REST adapter c2s.header 嵌套要求 |
| 89 | macOS 特异性坑 8 项 |
| 90 | Legacy vs Scope Mode matrix |

### 3.4 此前已完成的变更（v3.0.0 - v3.0.3）

| commit | 内容 |
|--------|------|
| v3.0.0 (24b2ff7) | SKILL.md +4 red lines (#15-#18) + strategy-workflow ~12 处增补 |
| v3.0.1 (7b9f9d0) | templates +5 处 + feedback/update/progress 各 1 处 |
| v3.0.2 (1b20c86) | test-execution-workflow 同步（证据质量/bug retest/报告规则）|
| v3.0.3 (7b54307) | pending-skill-upgrades 18 条通用候选 |

---

## 四、强制执行层级总览

```
                    ┌─────────────────────────────────────────┐
                    │  L0: protocol.md (每 session 注入)        │
                    │  5 行项目纪律 + L0 校准 + 思维纪律        │
                    └───────────────┬─────────────────────────┘
                                    │
        ┌───────────────────────────┼───────────────────────────┐
        │                           │                           │
┌───────▼───────┐          ┌───────▼───────┐          ┌───────▼───────┐
│ L3: strategy  │          │ L2: execution │          │ L4: templates │
│ 规划时加载     │──────────│ 执行时加载     │──────────│ 写输出时加载   │
│               │          │               │          │               │
│ Pre-check 6项 │          │ Pass 4件套    │          │ 报告分层 3档   │
│ 穷举标准 4类  │          │ 4-state判定   │          │ 3句话格式     │
│ 盲区异构警告  │          │ 清理checklist │          │ Deliverables  │
│ INCONCLUSIVE  │          │ 证据质量 8条  │          │ 4 tier        │
│ blind retry禁 │          │ 环境验证 2条  │          │ 数字可溯源    │
└───────┬───────┘          └───────┬───────┘          └───────┬───────┘
        │                           │                           │
        │     ┌─────────────────────┼─────────────────────┐     │
        │     │                     │                     │     │
  ┌─────▼─────▼──┐          ┌──────▼──────┐       ┌─────▼─────▼──┐
  │ L5: merge    │          │ L6: longrun │       │ L7: known-   │
  │ 合并时加载    │          │ 条件加载     │       │ issues       │
  │              │          │             │       │ Step 0 提取   │
  │ 粒度对齐     │          │ 三层健康    │       │              │
  │ 3分类覆盖率  │          │ 6元组身份   │       │ #1-#90       │
  │ 4步cross-    │          │ 双通道监控  │       │ 90条经验     │
  │ verify       │          │ heartbeat   │       │              │
  └──────────────┘          └─────────────┘       └──────────────┘
```

---

## 五、数量统计

| 指标 | 数量 |
|------|------|
| 原始输入条目 | ~571 |
| 去重后独立经验 | ~110 |
| 写入 skill workflow/template/procedure | 53 条（分布在 6 个文件）|
| 写入项目 known-issues | 90 条（#1-#90，含历史 + 本次新增）|
| 写入项目 protocol 项目纪律 | 5 行 |
| 写入项目 env-config | 5 处 |
| 排队 pending-skill-upgrades | 18 条（待人审核升级）|
| Skill 文件净增行数 | 335 行 |
| 涉及 skill 文件 | 7 个（含 1 个新建）|
| 涉及项目知识文件 | 3 个 |
| Git commits（skill repo）| v3.0.0 → v3.1.0（6 commits）|
| Git commits（project repo）| 4 commits |

---

## 六、修复的问题

本次升级过程中发现并修复了 5 个质量问题：

| # | 问题 | 修复方式 |
|---|------|---------|
| 1 | SKILL.md + strategy-workflow 的 v3.0.0 内容未验证 | 逐行 grep 确认 12/12 改动点存在 |
| 2 | strategy 新规则未同步到 test-execution-workflow | 新增证据质量/bug retest/报告规则 |
| 3 | 10 条"已有覆盖"未逐条验证 | 派 agent 对照，9/10 充分，F7 补认知原理 |
| 4 | known-issues 编号冲突（#9-10, #11-17 三处重复）| 统一为 #1-#90 连续编号 |
| 5 | 首轮去重过度（29 条 vs 实际 82 条）| 严格逐条复盘，补齐 53 条遗漏 |

---

## 七、已知局限

1. **known-issues #67-#82 仍是 L7 层**：这 16 条通用方法论经验在 known-issues 中，依赖 strategy Step 0 提取。如果 agent 跳过 strategy 直接测试，这些经验不会被看到。
2. **pending-skill-upgrades 18 条仍未 promote**：这些是 v3.0.3 排队的候选，需要人审核后写入 skill 文件才能跨项目生效。
3. **项目专属经验（#83-#90）不跨项目传播**：按设计只在 futu-opend-rs 项目生效。通用化需要人判断。
4. **新建的 longrun procedure 未经实测**：procedures/longrun-testing.md 基于回顾提炼，尚未在新的 24h 长跑中验证。

---

## 八、下一步

1. 审核 `pending-skill-upgrades.md` 中 18 条候选 → promote 到 skill 文件
2. 下次 24h 长跑测试中验证 `procedures/longrun-testing.md` 是否生效
3. 考虑将 #67-#69（4 阶段测试法 / 5 级成熟度 / 覆盖率上限表）升级到 strategy-workflow 或 design-rationale（当前在 L7 层偏弱）

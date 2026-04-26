# better-test 约束体系全景 — v3.1.0

> 这份文档说明 better-test skill 目前用了哪些机制来约束 AI 测试 agent 的行为，每一层做了什么，效果如何。
> 版本: v3.1.0 | 日期: 2026-04-26

---

## 总览：一句话解释

**better-test 用 8 个层级控制 AI agent 怎么做测试**——从"每句话都看到的铁律"到"需要时才打开的参考手册"，层级越高执行力越强。最强的是自动拦截（hook），最弱的是写在经验库里等 agent 自己去翻。

```
强 ─────────────────────────────────────────── 弱

L0 协议    L1 Hook   L2 执行流程  L3 规划流程  L4 模板  L5 合并  L6 专项  L7 经验库
每句话     自动拦截   跑测试时     做计划时     写报告时  合并时   条件触发  等被翻到
都看到     不合规     必须看到     必须看到     必须看到  必须看到  才加载
```

---

## L0: Protocol（每个 session 自动注入）

### 大白话

这是 agent 每次开始工作时脑子里"已经有"的规则——不需要打开任何文件，系统自动注入。相当于"测试员上岗培训的第一课"，告诉 agent 你是谁、你的弱点是什么、怎么思考才对。

### 技术细节

**注入方式**：项目 CLAUDE.md 中 `@.better-work/test/protocol.md`，每次对话自动加载到 system context。

**当前内容**（25/30 行）：

| 段落 | 行数 | 内容 |
|------|------|------|
| L0 校准 | 9 行 | 身份定义（"你是测试审计员不是通过助手"）+ 三种认知偏差警告（完整/确定/乐观）|
| 思维纪律 | 3 行 | 推测即验证（同一动作完成）/ 有基准必 compare / 踩坑=UX 改进点 |
| 安全纪律 | 1 行 | 不可逆操作先确认策略 / 凭证不写入 |
| 项目纪律 | 5 行 | 单次观测不定论 / skip 掩盖违规 / severity 最坏场景 / 跨 tester 复现 / 全绿=漏测 |

**Protocol 拆分架构**（v3.0+）：

```
CLAUDE.md 注入两行：
  @~/.claude/skills/better-test/protocol-base.md    ← skill 级（L0 + 思维纪律），随 skill 更新
  @.better-work/test/protocol.md                     ← 项目级（安全纪律 + 项目纪律），项目自己维护
```

**效果**：每个 session 第一句话 agent 就已经知道"pass 要验证返回值""有基准必须对照""推测必须当场验证"。这是所有层级的基础——后续层级的规则再详细，agent 如果连基本思维方式都偏了，细节也没用。

**局限**：≤30 行硬限制，只能放"怎么想"的规则，不能放"怎么做"的步骤。

---

## L1: Hooks（自动拦截，不合规就阻断）

### 大白话

这是"门卫"——agent 每次要做某个操作（写文件、跑命令），hook 自动检查合不合规。不合规的操作直接被拦下来，agent 收到警告。不需要 agent"记住"规则，因为违规的动作根本做不出去。

### 技术细节

**当前 8 个 hook**（全部跨平台 Claude + Codex）：

| Hook | 优先级 | 触发时机 | 拦截什么 | 效果 |
|------|--------|---------|---------|------|
| **credential-scan** | P0 | 写文件前（PreToolUse） | 检查写入 `.better-work/test/` 的内容是否包含密码/token/API key 模式 | 凭据写入 → 阻断 |
| **feedback-rules-guard** | P0 | 写文件前（PreToolUse） | 检查是否直接编辑 `feedback-rules.json` | 手动编辑 → 阻断，必须走 feedback 命令 |
| **execution-log** | P0 | 跑命令后（PostToolUse） | 每条 Bash 命令 + 输出自动追加到 `execution-log.md` | 不可篡改的执行记录，L2 审计数据源 |
| **post-test-checklist** | P1 | 写 results.json 后（PostToolUse） | 检测到 results.json 写入 → 注入完成 checklist 提醒 | agent 收到"该做 L2 审查了"的提醒 |
| **results-validation** | P1 | 写 results.json 后（PostToolUse） | 检查 results.json 必填字段、evidence 语义合法性 | 字段缺失或证据级别非法 → 警告 |
| **derived-view-guard** | P1 | 写文件前（PreToolUse） | tester 尝试写项目级聚合文件（status.md/known-issues.md/bugs-index.md/feedback-rules.json）| 无 merge lockfile → 阻断 |
| **registration-gate** | P1 | 写 strategy-plan.md 后（PostToolUse） | 检查 tester 是否完成注册（registry.md + bio.md 存在）| 未注册 → 警告 |
| **session-write-guard** | P1 | 写文件前（PreToolUse） | tester 尝试写其他 tester 的 run 目录或 registry | 跨 tester 写入 → 阻断 |

**效果**：8 个 hook 覆盖了"凭据泄露""文件权限""执行审计""注册门控""结果校验"五大安全面。这是 skill 中执行力最强的层——agent 犯错直接被拦，不依赖 agent 自觉。

**局限**：当前 hook 主要保护"安全"和"隔离"，还没覆盖"测试质量"（如 pass 判定是否有下游证据、数字是否可溯源）。这些是 Hook 候选，见 upgrade-summary-v3.1.0.md 第八段。

---

## L2: Test Execution Workflow（跑测试时必须遵守）

### 大白话

这是"测试操作手册"——agent 开始跑测试时打开这个文件，里面有所有执行纪律：怎么标记结果、怎么判断 pass、怎么处理错误、怎么分级证据、跑完怎么清理。这些规则通过 results.json 的字段约束来硬卡——没填必填字段就不能标 pass。

### 技术细节

**加载时机**：strategy confirmed 后，测试执行阶段自动加载。

**核心约束模块**：

| 模块 | 约束方式 | v3.1.0 新增 |
|------|---------|------------|
| **Pass 判定 4 件套** | 下游效应 + silent empty 排除 + 跨 surface + 基准对照，全满足才能标 ✅ | v3.1.0 新增 |
| **四色标记** | ✅/🟡/🔴/⏭️，results.json status 字段只接受这 4 种 | 已有 |
| **4-state verdict** | PASS / PARTIAL / FAIL / SKIP，加 PARTIAL 防 binary 丢 nuance | v3.1.0 新增 |
| **结构化记录** | 7 个必填字段（基准/被测/对比/断言字段/断言值/状态/证据级别），空字段 = 不能标 ✅ | 已有 |
| **证据分级** | indirect → direct → binary → confirmed → proven，5 级严格定义 | 已有 |
| **证据质量纪律** | 推测即验证 / 单次观测不定论 / 合理化阻断 / 覆盖声明附比例 / inferred 附升级步骤 / Before/After diff / timestamp+state / epoch 工具计算 | 8 条中 4 条 v3.0.2 新增，4 条 v3.1.0 新增 |
| **🟡 升级路径** | 🟡 产生时就地解决，不积累。同 Phase 内必须升级为终态 | v3.0.2 强化 |
| **错误消息先读** | 不同码不同根因，blind retry → anti-flood | v3.1.0 新增 |
| **三种用户姿态** | 完整参数 / 只传 required / 核心字段(agent)，每个接口都测 | 已有 |
| **字段三态枚举** | key 缺失 / null / 合法值，每个可选字段 | 已有 |
| **Bug Retest 规则** | sim≠real / 全路径覆盖 / 跨 tester 复现 | v3.0.2 新增 |
| **Bug 发现流程** | 两层结构 + severity 最坏场景 + pre-existing 标注 + changelog 标记 | v3.0.2 新增 |
| **清理纪律** | kill 进程 / 删 /tmp 凭据 / cancel orphan / 副作用外部性列出 | v3.1.0 新增 |
| **环境确认** | 端口 bind 验证（启动后 lsof PID）/ pgrep 精确到 port+account / UTC 作 SoT | v3.1.0 新增 |
| **终态规则** | 每个 test item 必须达到 ✅/PARTIAL/🔴/⏭️ 之一 | 已有，v3.1.0 加 PARTIAL |
| **安全守则** | 不写凭证 / 不可逆操作策略 / 优先安全方式 | 已有 |

**效果**：这是执行阶段最重的一层文件。通过 results.json 字段约束做到"不符合就写不进去"——这比"文档里说了希望你遵守"强得多。

---

## L3: Strategy Workflow（做测试规划时必须遵守）

### 大白话

这是"测试总指挥"——agent 在决定"测什么、怎么测、测多少"之前必须看的文件。它告诉 agent 先做功课（读历史、查 changelog、分析影响面），再和用户对齐，然后生成分阶段计划。规则嵌入在每个步骤里——不是"你应该做"，而是"这个步骤里必须包含"。

### 技术细节

**加载时机**：`/better-test strategy` 命令触发。

**核心约束模块**：

| 步骤 | 约束 | v3.1.0 新增 |
|------|------|------------|
| **Step 0 上下文研判** | 必读 8 类材料 + 经验提取（从 known-issues/test-groups/env-config 动态提取） | 已有 |
| **Step 0 全绿校验** | 上次全绿时强制检查 error path / 负向测试 / 三种姿态 / compare | v3.0.0 新增 |
| **Step 1A Changelog** | 逐条映射 + 声称修复标记 `[CHANGELOG 声称修复——需验证]` | v3.0.0 新增 |
| **Pre-check 测试前提** | 标的物有效性 / 环境清理 / 环境确认 / 时段依赖 / **测试方案可行性** / **"做不到"先试 subagent** | 前 4 条 v3.0.0，后 2 条 v3.1.0 |
| **Stage 2 负向测试** | 三种用户姿态 / 字段三态 / error path 显式列出 / **穷举边界标准（7+5+4 点）** / **body 格式 4 变体矩阵** | 前 3 条 v3.0.0，后 2 条 v3.1.0 |
| **Stage 3 回归** | sim≠real / 全路径覆盖 / 跨 tester 复现 | v3.0.0 新增 |
| **Compare 模式** | 强制激活 / Ground truth 层级 / 结构一致性 > 数值 | v3.0.0 新增 |
| **多 Agent 协调** | 资源感知 / 避免重复 / **Dual-tester blind spot 异构需求** | blind spot v3.1.0 新增 |
| **子 Agent 委托** | spot check ≥20% / 资源锁定 / 并行隔离 | v3.0.0 新增 |
| **L2 对抗审查** | 主动触发 / 焦点在挑战定性 | v3.0.0 新增 |
| **Accuracy Rules** | 13 条铁律（推测即验证 / 单次观测 / 合理化阻断 / severity / 覆盖率 / 🟡 即时 / **INCONCLUSIVE for unproven**） | 前 12 条 v3.0.0-v3.0.2，#13 v3.1.0 |
| **假设格式** | IF/THEN/BECAUSE + 具体预期值 + 验证方法 | v3.0.0 强化 |

**效果**：在 agent 开始跑测试之前就卡住——计划不过关不能开始执行。Step 0.5 的用户对齐是门控点，用户不确认就不进入执行。

---

## L4: Templates（写输出文件时必须遵守）

### 大白话

这是"报告格式手册"——agent 每次要写 bug 报告、summary、results.json 时必须看的模板和质量标准。不是"你爱怎么写怎么写"，而是"这几个字段必须有、这个格式必须对、这个标准必须达到"。

### 技术细节

**加载时机**：生成任何输出文件时。

**核心约束模块**：

| 模块 | 约束 | v3.1.0 新增 |
|------|------|------------|
| **执行纪律通则** | 写前 re-read 模板 / 边跑边写 / 数量机械对齐 | v3.0.1 新增 |
| **Bug report** | 两层结构（大白话+技术）/ pre-existing 标注 / changelog 标记 / severity 最坏场景 / **三句话格式（scene+symptom+impact）** / **P0 证伪门槛** / **证据文件按 bug-id 命名** | 前 4 条 v3.0.1，后 3 条 v3.1.0 |
| **Summary** | 外部自包含 / 编号统一 / 先列表再数 / **报告分层 L0/L1/L2（500/1500/8000 字）** / **大白话=零术语严格定义** | 前 3 条 v3.0.1，后 2 条 v3.1.0 |
| **results.json** | schema 含 comparison_baseline + pre_existing 字段 | v3.0.1 新增 |
| **质量标准通则** | **denominator clarity** / **精确数字可溯源** / **DEMOTED header** / **版本演化声明** / **roundtrip 透明记录** / **tester-id 文件名** / **Deliverables 4 tier** | 全部 v3.1.0 新增 |
| **protocol.md 模板** | ≤30 行 / L0 不可省 / 项目纪律 ≤5 行 | 已有 |
| **时间戳规范** | 三档精度（Full/Compact/Date-only）+ 必须带时区 | 已有 |

**效果**：agent 写报告时如果不符合模板，下游读者（L2 审计员、coordinator、开发者）会发现格式不对。这比 hook 弱（不自动阻断），但比 known-issues 强（agent 写文件时必须打开这个文件）。

---

## L5: Merge Workflow（合并多人结果时必须遵守）

### 大白话

这是"裁判规则"——当多个 tester 各自跑完测试、结果需要合并时，coordinator 角色按这个流程工作。它规定了怎么处理两人结论不一致、怎么去重 bug、怎么生成统一报告。重点是"不能默默挑一个人的结论"——任何分歧都必须记录下来让用户看到。

### 技术细节

**加载时机**：`/better-test merge` 命令触发，或单 tester 完成后生成聚合文件。

**核心约束模块**：

| 模块 | 约束 | v3.1.0 新增 |
|------|------|------------|
| **角色隔离** | coordinator 只能写项目级文件，不能改 tester 的 run 目录 | 已有 |
| **Bug 粒度对齐** | merge 前双方同步 bug 定义（4 sub-items = 1 or 4?） | v3.1.0 新增 |
| **Cross-verify 3 分类** | bidirectional_strict / trust_based / indirect，不允许 over-report | v3.1.0 新增 |
| **Cross-verify 4 步法** | 列 claims → 独立复现 → 发现差异怀疑自己 → 定位机制 | v3.1.0 新增 |
| **Steelman 原则** | peer challenge 时先假设自己有盲区 | v3.1.0 新增 |
| **冲突检测** | fail 优先原则 + 全部记入 conflict-log.md | 已有 |
| **Bug 去重** | 按 test_id + error signature 去重 + 项目级编号 | 已有 |
| **用户确认** | 合并结果必须用户确认后才写入项目级文件 | 已有 |

**效果**：解决"两个 tester 说法不一样怎么办"的问题。核心保证是透明——分歧被记录而非隐藏。

---

## L6: Procedures（需要时才打开的专项指南）

### 大白话

这是"急救手册柜"——不是每次测试都需要，但遇到特定情况时自动拿出来用。比如发现了 bug 要写报告 → 拿出 bug-report 手册；要跑 24 小时长测试 → 拿出长跑手册；用三问法查不出根因 → 拿出假设调查手册。

### 技术细节

**加载时机**：条件触发（strategy/execution 阶段检测到信号时自动加载）。

**当前 9 个 procedure**：

| Procedure | 触发条件 | 内容 |
|-----------|---------|------|
| `bug-report.md` | 发现 bug 需要写报告 | 7 节标准格式 + yaml 元数据 |
| `hypothesis-investigation.md` | 错误三问无法定位 | 3-假设法 + 调查阶梯 + 证据分级完整定义 |
| `flakiness-scoring.md` | 检测到 flaky 信号 | 稳定性评分方法 |
| `bdd-scenarios.md` | 用户提供 PRD/验收标准 | Given-When-Then 场景生成 |
| `tdd-flow.md` | 任务包含写新功能代码 | Red-Green-Refactor |
| `contract-testing.md` | API/Web + 多服务调用链 | 契约测试步骤 |
| `exploratory-charter.md` | 用户要求深度测试 | 探索性测试 charter |
| `mutation-testing.md` | 有代码变更 + 变异工具 | 增量变异测试 |
| **`longrun-testing.md`** | **strategy 包含 24h+ 长跑** | **v3.1.0 新增：三层健康验证 / daemon 6 元组 / canary heartbeat / 采样器自包含 / Monitor+Cron 双通道 / 采样粒度 / 关键词覆盖 / loop auto-stop / 跨 tester 隔离 / PID 防误归** |

**效果**：避免让每个 agent 都背诵所有专项知识。只在需要的时候加载，减少 context 消耗。长跑 procedure 是 v3.1.0 最大的新增——consolidate 了 10 条散落在不同回顾文件中的长跑经验。

---

## L7: Known-Issues Lessons（经验库，被策略阶段提取）

### 大白话

这是"前人踩过的坑"——所有 tester 在实战中学到的教训，按编号记录。agent 做测试策略时（Step 0）会翻这个库，提取和当前测试相关的经验。相当于"老员工交接笔记"。

这是最弱的执行层——agent 看了可能忘，也可能提取不到最相关的那条。但它的价值在于积累：90 条经验是 8 个 tester 在 10+ 个版本中真实踩过的坑，每条都附带证据和来源版本。

### 技术细节

**加载时机**：strategy Step 0 经验提取。按关键词匹配当前变更/测试组，筛选相关 lessons。

**当前 90 条**（#1-#90）分布：

| 段落 | 编号范围 | 条数 | 主题 |
|------|---------|------|------|
| 测试方法论 | #1-#14 | 14 | daemon log/pass 验证/三 surface/proto/broker/SDK/filter/cache/C++/合理化/binary/changelog/baseline/及时对照 |
| 流程纪律 | #15-#17 | 3 | compare 不可选/protocol 必须执行/skill 规范不是建议 |
| 产品特性 | #18-#19 | 2 | trd_market=11/OCC 格式 |
| v1.4.49-56 | #20-#28 | 9 | SDK metadata/数据驱动 vs 启发式/agent 调研≠真机/sim≠real/不做对照不下结论/部分验证≠已修/推测即验证/先列后数/UX 改进 |
| v1.4.57 | #29-#32 | 4 | 清 credentials/trivial case/severity/覆盖率声明 |
| v1.4.56-59 综合 | #33-#45 | 13 | error path/ground truth/结构一致/🟡 即时/单次观测/跨 tester 复现/L2 挑战定性/protocol 偏差/三种姿态/字段三态/L2 触发/防漂移锚点/边跑边写 |
| v1.4.69 | #46-#48 | 3 | raw dump 先/absent 验证/REST 层级不统一 |
| v1.4.90 | #49-#55 | 7 | schema≠runtime/weekend block/keys 反模式/多 daemon/binary strings/query-subscription/self-audit 2+ 轮 |
| v1.4.86-94 综合 | #56-#66 | 11 | subscribe silent noop/schema vs runtime/auth vs legacy/端口验证/push 诊断/F3F4 独立/backend push/解锁 3 流程/option-chain/body 格式/telnet |
| **v1.4.86-94 方法论** | **#67-#82** | **16** | **4 阶段测试法/5 级成熟度/覆盖率上限/能力边界/agent 威胁/被动纠错/资源规划/零影响/table yaml/断言语言/plausibility bias/大白话/adversarial review/BSD sed/trap EXIT/交叉验证前置** |
| **v1.4.86-94 项目** | **#83-#90** | **8** | **REST 万能骗/三套命名/credentials 两阶段/启动参数/7x7 映射/c2s 嵌套/macOS 8 坑/scope matrix** |

**效果**：90 条经验是"集体记忆"。即使单条的执行力弱，但作为整体它让新 tester 不用从零踩坑。Strategy Step 0 的经验提取机制保证了"至少在做计划时会看到相关的教训"。

---

## L8: Pending Skill Upgrades（排队，完全不生效）

### 大白话

这是"待审批提案箱"——agent 在测试中发现了可能适用于所有项目的通用规则，先写到这里排队，等人审核后再写入正式的 skill 文件。在被批准之前，这些规则**不会在任何地方生效**。

### 技术细节

**当前 18 条候选**，来自 v3.0.3 的通用经验提取。

**审批层级**：
- Low（design-rationale.md）→ agent 可直接写
- Medium（workflow/templates）→ 用户确认
- High（protocol-base/red lines）→ 用户 + L2 审计

**效果**：防止 agent 自行修改 skill 级文件。但代价是这些经验在被批准前完全不生效。如果长期不审核，等于浪费了提取的工作。

---

## Red Lines（违规红线，贯穿所有层级）

### 大白话

这是"绝对不能做的事"——写在 SKILL.md 里的 18 条禁令。不管 agent 在哪个阶段、用哪个 workflow，这些都是底线。有些由 hook 自动执行（如凭据泄露），有些依赖 L2 审计发现（如 trivial case 凑 pass）。

### 技术细节

**当前 18 条 Red Lines**：

| 类别 | 红线 | 自动执行？ |
|------|------|-----------|
| 安全 | #1 凭据不写入 | Hook: credential-scan |
| 安全 | #7 feedback-rules 不手编 | Hook: feedback-rules-guard |
| 隔离 | #12 tester 不写项目级文件 | Hook: derived-view-guard |
| 隔离 | #13 未注册不开始测试 | Hook: registration-gate |
| 隔离 | #14 不写别人的文件 | Hook: session-write-guard |
| 质量 | #2 pass 必须验证返回值字段 | 文档约束（results-validation hook 部分覆盖） |
| 质量 | #3 skip 必须醒目 | 文档约束 |
| 质量 | #15 bug retest 不能只 sim | v3.0.0 新增，文档约束 |
| 质量 | #16 results.json 必须存在 | v3.0.0 新增，Hook: post-test-checklist 提醒 |
| 质量 | #17 changelog 逐条映射 | v3.0.0 新增，文档约束 |
| 质量 | #18 skip/trivial 掩盖 bug 违规 | v3.0.0 新增，文档约束 |
| 完整性 | #4-#6, #8-#11 | 各类文件格式和内容要求 | 文档约束 |

**效果**：5/18 由 hook 自动执行（最强），13/18 依赖文档约束 + L2 审计（较弱）。这 13 条是 hook 候选——如果全部自动化，执行力会显著提升。

---

## 层级间的协作关系

```
用户发起 /better-test strategy
  │
  ├─ L0 protocol 已在 context 中（思维基础）
  │
  ├─ L3 strategy-workflow 加载
  │     ├─ Step 0 从 L7 known-issues 提取相关经验
  │     ├─ Pre-check 检查环境（参考 env-config）
  │     ├─ 生成计划 → L1 registration-gate hook 检查注册
  │     └─ 用户确认 → status: confirmed
  │
  ├─ L2 test-execution-workflow 加载
  │     ├─ L6 longrun procedure 条件加载（如需要）
  │     ├─ L6 bug-report procedure 条件加载（发现 bug 时）
  │     ├─ L1 execution-log hook 自动记录每条命令
  │     ├─ L1 credential-scan hook 拦截凭据写入
  │     ├─ L1 session-write-guard hook 拦截跨 tester 写入
  │     └─ 写 results.json → L1 results-validation + post-test-checklist hook
  │
  ├─ L4 templates 在写输出时加载
  │
  ├─ L5 merge-workflow 在多 tester 合并时加载
  │     └─ L1 derived-view-guard hook 保护项目级文件
  │
  └─ 通用经验 → L8 pending-skill-upgrades 排队等审批
```

---

## 数量汇总

| 层级 | 约束条目数 | 自动执行？ | 覆盖阶段 |
|------|-----------|-----------|---------|
| L0 Protocol | 12 条（L0 校准 3 + 思维 3 + 安全 1 + 项目 5）| 是（系统注入）| 全阶段 |
| L1 Hooks | 8 个 hook | 是（自动拦截）| 写文件/跑命令时 |
| L2 Execution | ~30 条约束（4 件套 + 8 证据 + 4 色 + 7 字段 + 终态 + 清理 + 环境）| 部分（字段约束）| 执行阶段 |
| L3 Strategy | ~25 条约束（Pre-check 6 + Stage 各项 + Accuracy 13 + 假设格式）| 步骤级门控 | 规划阶段 |
| L4 Templates | ~20 条标准（bug report + summary + results.json + 通则）| 格式约束 | 写输出时 |
| L5 Merge | ~10 条约束（粒度对齐 + 3 分类 + 4 步法 + 冲突 + 去重）| 流程门控 | 合并阶段 |
| L6 Procedures | 9 个 procedure | 条件加载 | 特定场景 |
| L7 Known-Issues | 90 条经验 | 提取依赖 | 规划阶段 |
| L8 Pending | 18 条候选 | 不生效 | — |
| Red Lines | 18 条禁令 | 5 条 hook + 13 条文档 | 全阶段 |

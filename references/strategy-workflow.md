# Strategy Workflow

`/better-test strategy` 在跑测试**之前**做：上下文研判 + 范围对齐 + 变更检测 + 影响分析 + 分阶段执行计划。

## Tester 注册（自动）

strategy 是 tester 自动注册的触发点。首次执行 strategy 时：

1. 检查 `.better-work/test/testers/` 是否有**当前 session 对应的活跃 tester**
2. 如果没有 → 自动注册新 tester：
   - 探测平台（env `CLAUDECODE=1` → claude-code；codex config → codex；等）
   - 获取 session_id、model、device 信息
   - 生成 tester-id：`<platform>-<sha1(session_id+timestamp)[:4]>`
   - 创建 `testers/<tester-id>/bio.md`（填入 Current Session 表）
   - 创建空 `testers/<tester-id>/status.md` 和 `testers/<tester-id>/progress.md`
   - 报告："已注册 tester `<tester-id>`（<platform> / <model>）"
3. 如果有单个 tester 且 last_active < 24h → 自动关联，更新 bio 的 session 信息
4. 如果有多个 tester → 提示用户选择或创建新 tester

后续所有写操作使用此 tester-id 隔离。

---

## 核心流程

```
0. context_research      ← 读历史材料，形成初步判断
0.5 align_with_user      ← 带着判断和用户对齐范围
1. detect_changes        ← 变更检测（含 diff 内容分析）
2. analyze_impact        ← impact-map 匹配 + 函数级精准分析
3. read_history          ← 历史结果 + feedback-rules + bugs-index
4. generate_plan         ← 生成分阶段执行计划（质量优先）
5. form_hypotheses       ← 为每个阶段写测试假设
6. present_to_user       ← 展示计划 + 假设 + 让用户确认
7. emit_to_execution     ← 交给 test-execution-workflow 执行
```

---

> **测试执行纪律**（四色标记、证据分级、对照加固、负向测试等）
> 在 `test-execution-workflow.md`。Strategy 负责"测什么、为什么"，execution 负责"怎么测、怎么判"。

---

## Step 0: 上下文研判（context_research）

在问用户任何问题之前，agent 先做功课——读现有材料形成对"当前测试重点应该是什么"的初步判断。

### 读什么

```
1. CHANGELOG / release notes → 本版本有意改了什么
2. bugs-index.md → 有没有 FIXED 待 VERIFIED 的 bug、有没有 OPEN 的活跃 bug
3. history/ 最近 run 的 results → 上次哪些挂了、哪些 flaky
4. known-issues.md lessons → 有什么相关的历史经验
5. feedback/ 最近的条目 → 开发者最近说了什么
6. status.md → 当前覆盖缺口、测试结构健康度
7. code/danger-zones.md（如有）→ 高风险模块
8. git diff --stat + git log --oneline -10 → 快速浏览最近变更规模和方向
```

### 形成初步判断

```
基于以上材料，综合判断：

  风险区域: "本版本改了 auth 模块，历史上 auth 区域有 3 个 bug（BUG-claude-a3f2-001, 003, 007），
           上次跑 A 组时 A-03 flaky（稳定性 70%），开发者上次反馈说 session 处理重构了"

  建议重点: "A 组全跑 + BUG-claude-a3f2-001 回归验证 + D 组因为和 auth 共享 session fixture 也建议跑"

  待确认: "不确定这次重构是否影响了 MCP 的 auth 路径——代码 diff 可以确认"
```

## Step 0.5: 与用户对齐（align_with_user）

带着初步判断向用户呈现并提问。不是空手问"你想测什么"——是"我研究了一下，我觉得重点是这些，你看对不对"。

```
基于项目历史和当前变更，我的初步判断：

  📋 本版本变更: auth 模块重构 + REST handler 微调
  ⚠ 风险区域: A 组（auth，历史 3 个 bug），D 组（共享 session fixture）
  🔄 待验证: BUG-claude-a3f2-001（FIXED 未 VERIFIED）
  📊 上次状态: A-03 flaky 70%，其余稳定

  我计划做：
    阶段 1: 基础验证（A 组 auth）
    阶段 2: 直接影响（A + B 组）+ 即时对照
    阶段 3: 回归验证（BUG-claude-a3f2-001 相关项）
    阶段 4: 边界扩展（D 组）
    阶段 5: 覆盖审计

几个问题想和你确认：
  1. 这次变更有没有代码 diff 里看不到的重要信息？
     （如"开发者说可能影响 WebSocket"、"内部重构但接口不变"）
  2. 有没有你特别担心的模块？
  3. 你已经手动验证过什么了？
  4. 有什么必须跳过的？（如不能碰真账户）
```

用户可以：
- 确认："没什么补充，按你的来"
- 调整："MCP 也要跑，开发者说 auth 改动影响了 MCP 鉴权"
- 追加："上周客户投诉了 funds 查询变慢，性能也看一下"

agent 把用户输入整合到后续步骤中。

## Step 1: 变更检测（detect_changes）

按以下信号源**逐项尝试**，记录每个信号的来源：

### 信号源 A：CHANGELOG / RELEASE_NOTES

```
查找根目录: CHANGELOG.md / CHANGELOG / RELEASE_NOTES.md / RELEASE_NOTES
读当前版本对应的段落（## v1.4.27 或 # 1.4.27 之间的内容）
最多取前 20 条 bullet，写入待分析队列
来源标记: changelog
```

### 信号源 B：版本快照 diff（如适用）

```
适用于：daemon/CLI 项目，可执行 `<binary> --help` 输出版本快照
对比 history/<prev_version>/_help.txt 与当前版本
diff 中新增/移除的 flag 是强变更信号
来源标记: help-diff
```

### 信号源 C：Git 历史 diff（如适用）

```
适用于：源码仓库可访问的项目
git log <prev_version_tag>..HEAD --stat → 列出变更文件
git log <prev_version_tag>..HEAD --grep="fix|feature|breaking" → 提取关键 commit
来源标记: git-log
```

### 信号源 C+：Diff 内容分析（有源码时增强）

```
git diff <prev_version_tag>..HEAD → 读实际变更内容（不只是文件名）

提取：
  - 哪些函数/方法被修改了？（函数级精度，比文件级准得多）
  - 修改类型：签名变更（影响调用方）vs 内部实现变更（影响行为）vs 注释/格式（无影响）
  - 新增了什么函数/接口？删了什么？
  - 错误处理路径是否变了？

输出：函数级变更清单 → Step 2 做精准 impact 分析的输入
来源标记: diff-content
```

为什么不只看文件名：改了 `src/auth/session.rs` 可能只加了一行注释（无影响），也可能重写了 session 过期逻辑（高影响）。文件名匹配会把两种情况都推荐跑全组，diff 内容分析能区分。

### 信号源 D：Surface Manifest Diff（如有清单）

```
适用于：项目有 surface-manifest.md 且版本更新时
对比 上一版本的 surface-manifest.md 与当前版本（或 --help 输出）
  新增接口 → 标为覆盖缺口，加入阶段 5 优先处理
  删除接口 → 检查 test-groups 中对应项是否需要标废弃
  参数变更 → 检查对应 EXPECT_PATTERN 是否仍然有效
来源标记: manifest-diff
```

### 信号源 E：用户提供（Step 0.5 对齐时已收集）

```
用户在 Step 0.5 中提供的额外上下文：
  - 特别担心的模块
  - 代码 diff 里看不到的信息（如口头讨论、设计决策）
  - 已手动验证的部分
来源标记: user-input
```

如果**所有信号源都为空** → strategy 推荐 `smoke`（最低成本验证基线）。

## Step 2: 影响分析（analyze_impact）

两层分析：关键词匹配（粗）+ 函数级分析（精）。

### 第一层：关键词匹配

读 `.better-work/test/impact-map.md`，做关键词匹配：

```
对每个 changes 中的描述：
  小写化 → 在 impact-map.md 的关键词表中查找匹配
  匹配命中 → 把对应的测试组加入 affected_groups 集合
返回 affected_groups 的去重列表
```

如果 impact-map.md 中某条目标 `[未验证]`，仍然参与匹配但在 present 时提示 "基于未验证映射"。

### 第二层：函数级精准分析（有 diff 内容时）

```
对 Step 1 C+ 的函数级变更清单：
  1. 每个变更的函数 → 搜索 test-groups 中哪些测试项调用了这个函数
  2. 签名变更 → 所有调用方的测试都受影响
  3. 内部实现变更 → 只有直接测试该函数行为的测试受影响
  4. 新增函数 → 检查是否有测试覆盖（没有 → 标为覆盖缺口）

输出：比关键词匹配更精准的 affected_items（测试项级别，不只是组级别）
```

两层取并集：关键词匹配的组 ∪ 函数级分析的项 = 最终影响范围。

> **不内置 ">50% 升级 full" 规则**。futu-tester 源材料无此阈值，本 skill 也不擅自加。如果项目需要这种升级策略，应该在 `impact-map.md` 的"全量触发条件"段（见 templates.md）显式列出，不靠隐式阈值。

## Step 3: 读历史（read_history）

```
读 .better-work/test/history/<current_version>/run-*-*/results.json
取最近一次（按时间戳最新的，跨所有 tester）
统计：total / passed / failed / skipped
提取 fail 项的 id 列表

读 .better-work/test/history/feedback-rules.json
- suppress[].test_id → 这些 id 即使 fail 也不算 active
- known_behaviors[] → 展示给用户但不影响推荐
- lessons[] → 用于人类参考

读 .better-work/test/history/bugs-index.md
- FIXED 但未 VERIFIED 的 bug → 提取其 related_tests 加入 bug_retest_candidates
- OPEN 的 bug → 提取其 related_tests 作为已知活跃 bug（展示但不自动推荐 retest）
```

`active_failures = recent_fails - suppress`
`bug_retest_candidates` = bugs-index 中 FIXED 但未 VERIFIED 的 bug 的 related_tests

## Step 4: 生成分阶段执行计划（generate_plan）

**质量优先是默认模式。** 优先级：准确度（依赖证据质量）> 发现问题数 > 覆盖度。

查错一个 bug 浪费研发团队的时间远超多跑几个测试的时间。所以宁可多跑不漏，不抢速度。

### Compare 模式自动触发

```
IF env-config.md 定义了对照目标（旧版二进制 / C++ SDK / Python SDK / 其他参照物）
   OR shared/index.md 标注了"重写项目"
   OR 用户在 Step 0.5 提供了对照基准：
  → compare 模式自动激活，不需要用户手动选
  → 分阶段计划中每个阶段都先跑基准再跑被测
  → 四色标记规则变为 compare 版本（见 test-execution-workflow）
```

### Changelog 逐条匹配

```
IF Step 1 检测到 CHANGELOG / release notes：
  → 每条 changelog 条目必须映射到至少一个测试项
  → 未映射的条目在 Step 6 展示给用户："以下 changelog 项没有对应测试，确认不需要测？"
  → 用户确认后标为 ⏭️ 写原因，不允许静默跳过
```

### 版本基线快照

```
IF 旧版本仍可用且未保存过基线：
  → 在执行测试前，先用旧版本跑关键接口保存行为快照
  → 存入 history/<old_version>/baseline.json
  → 供 compare 模式和 reflect 使用
```

### 分阶段计划生成

基于 Step 1-3 的输入，生成 5 阶段执行计划：

```
阶段 1: 基础验证
  输入: test-groups 中标注为 foundation 的组（auth / config / startup / health check）
  做什么: 全项执行。全部 ✅ 才继续，有 🔴 → 先解决基础问题
  为什么先跑: 基础不通 → 后续所有 fail 可能是环境问题不是功能 bug → 浪费调查时间

阶段 2: 直接影响 + 即时对照 + 负向测试
  输入: Step 2 影响分析的 affected_groups + affected_items + 用户在 Step 0.5 追加的关注点
  做什么: 全项执行。每个 🔴 立刻加对照（不等最后）。每个 🟡 立刻升级（不积累）
  执行顺序:
    a. 依赖链排序（被依赖的先跑）
    b. 同级按历史风险排序（bug 多的先跑）
  负向测试: 对每个 ✅ pass 的接口，选 1-2 个负向场景（错误参数 / 权限边界 / 边界值）

阶段 3: 回归验证
  输入: bugs-index 中 FIXED 未 VERIFIED 的 bug + active_failures + regression canary
  做什么: 跑 related_tests，和修复前对照验证因果关系
  准确度要求: fix 的验证需要 confirmed 级证据（不是"跑通了就行"）

阶段 4: 边界扩展
  输入: 与阶段 2 组相邻的组（共享依赖 / 调用链上下游）
  扩展范围由 impact-map 信心决定:
    信心 < 50% → 扩展 2 跳
    信心 50-80% → 扩展 1 跳
    信心 > 80% → 可选跳过（用户确认）
  做什么: 至少 smoke 级别覆盖，发现问题则升级为全项执行

阶段 5: 覆盖审计
  输入: surface manifest（如有）
  做什么: 对比 manifest vs 阶段 1-4 已执行项
  未覆盖接口:
    能深测（有 EXPECT_PATTERN + 运行条件满足）→ 执行并要求 field-level 证据
    不能深测 → 标 ⏭️ 写原因。不为覆盖率凑数
  输出: 最终可达覆盖率 T / R = NN%
```

### 贯穿所有阶段的准确度铁律

```
1. 每个 🔴 fail 产生时立刻加对照 → 证据从 direct 升级到 confirmed
2. 每个 🟡 产生时立刻升级 → 不积累模糊状态
3. 每个 ✅ pass 必须有 field-level 证据 → exit=0 级别不算 pass
4. 每个结论的证据级别 ≥ direct → indirect 不能出现在最终结果中
5. 宁可 ⏭️ 写原因也不降低证据标准凑覆盖率
6. 每个阶段完成后报告证据质量分布（confirmed / direct / indirect 各几项）
```

### 特殊情况的简化路径

分阶段计划是默认模式。以下情况可简化：

```
IF 当前版本已测 N 次且全部通过（含 suppress），无待验证 bug:
  → 向用户确认：已全通过，是否需要重测？
  → 否 → 跳过
  → 是 → 只跑阶段 1 + 5（基础验证 + 覆盖审计）

IF 用户在 Step 0.5 明确说"只看 X 模块":
  → 只生成阶段 1（基础）+ 阶段 2（X 模块）+ 阶段 3（X 相关回归）
  → 跳过阶段 4-5

IF 用户选择 compare 模式:
  → 切换到对照测试流程（见下方"对照测试模式"段）
```

## Step 5: 为每个阶段写测试假设（form_hypotheses）

**在看到测试输出之前，先预测哪里会坏、怎么坏。** 这防止看到结果后"合理化"（确认偏误）。

```
对阶段 2 的每个受影响组/项：

  假设格式：
    IF <变更描述> THEN <可能的影响> BECAUSE <推理>
    预期结果: <具体字段名 + 预期值/行为>
    验证方法: <跑什么命令，看什么字段>

  示例：
    假设 1: IF auth 模块重构了 session 过期逻辑
            THEN A-03 (session timeout test) 可能返回不同的 error_code
            BECAUSE session 过期的处理路径变了
            预期结果: A-03 应返回 session_id 字段 (type: string, non-empty)
            验证方法: 跑 A-03，检查 response 中 session_id 字段

    假设 2: IF REST handler 微调
            THEN B-03 (funds query) 的返回格式可能变化
            BECAUSE handler 可能改了 JSON 序列化方式
            预期结果: B-03 应返回 {"power": <number>}，power 不为 null
            验证方法: 跑 B-03，检查 power 字段类型和值
```

假设的价值：
- 测试前就定义了"pass 长什么样"——看到结果时是**对照预期**，不是"看着好像对"
- 假设被证实 → 找到 bug，证据链清晰（"我预测这里会坏，果然坏了，因为..."）
- 假设被否定 → 也有价值（"预测没坏，说明这个变更没影响这个路径"）

## Step 6: 展示计划 + 假设给用户确认（present_to_user）

```
质量优先执行计划 — v<X.Y.Z>

上下文研判:
  [Step 0 的初步判断摘要]

变更分析:
  [Step 1 的变更检测结果，含 diff 内容分析]

影响范围:
  [Step 2 的 affected_groups + affected_items]

分阶段计划:
  阶段 1: 基础验证 — A 组（auth），预计 3 min
  阶段 2: 直接影响 — B, C 组 + 负向测试，预计 15 min
    假设: [列出关键假设 2-3 个]
  阶段 3: 回归验证 — BUG-claude-a3f2-001 (C-05, C-07)，预计 3 min
  阶段 4: 边界扩展 — D 组（impact-map 信心 62%），预计 5 min
  阶段 5: 覆盖审计 — manifest 剩余接口，预计 8 min

总计预估: ~34 min
已知风险: A-03 flaky 70%，D 组映射未完全验证

接受此计划？[y / 调整 / 只跑部分阶段 / 切换 compare 模式]
```

## Step 7: 交给 test-execution-workflow（emit_to_execution）

用户确认后，把计划传递给 `test-execution-workflow.md`：
- 分阶段计划
- 每阶段的假设
- 准确度铁律
- 用户追加的上下文

### 附加提醒（嵌入 Step 6 展示中，条件触发）

```
变更批量 > 15 个文件 → ⚠ "大批量变更风险高，建议拆分后逐批测试"
变更批量 6-15 个文件 → 提醒"变更较多，建议分批"
阶段 2 涉及核心业务变更 → 建议配合代码审查 + 静态分析 + 增量变异测试
```

---

## 对照测试模式（compare）

差异测试：用一个已知正确的实现（基准）验证新实现的行为是否一致。

### 适用场景

| 场景 | 基准 | 被测 |
|------|------|------|
| 语言重写（C++ → Rust） | 旧 C++ 二进制 | 新 Rust 二进制 |
| 版本对比 | v1.4.27 二进制 | v1.4.28 二进制 |
| 修 bug 前后 | 修复前的 commit | 修复后的 commit |
| Feature flag 对比 | flag=off | flag=on |

### 前置条件

test-groups.md 中需要定义测试目标：

```markdown
## 测试目标（compare 模式用）

| 目标名 | 二进制/地址 | 端口 | 说明 |
|--------|-----------|------|------|
| rust-new | ./futu-opend | 11111 | 新 Rust 实现（被测对象） |
| cpp-old | ./moomoo_OpenD | 11112 | 旧 C++ 实现（对照基准） |
```

如果没有定义测试目标，用户可以在 strategy 选择 compare 时临时指定。

### 执行流程

```
1. 确认两个目标都可运行（端口清场、版本确认）
2. 选择测试组（用户指定或用 strategy 推荐的组）
3. 对每个测试项：
   a. 先跑基准目标，记录返回值
   b. 再跑被测目标，记录返回值
   c. 对比两者：
      - 完全一致 → ✅ 行为一致
      - 被测有额外字段/能力 → ℹ️ 新功能（不算 fail）
      - 基准通过但被测返回不同值 → ⚠ 差异（需调查）
      - 基准通过但被测 fail → 🔴 回归
4. 生成差异报告
```

### 差异报告格式

```markdown
# 对照测试报告 — <被测> vs <基准>

## 统计
一致: N/M (NN%)
差异: N/M (NN%)
新功能: N/M (NN%)
回归: N/M (NN%)

## 回归项（🔴 优先处理）

| Test ID | 基准返回 | 被测返回 | 分析 |
|---------|---------|---------|------|
| C-05 | {"order_id": "..."} | -400 bad request | 被测缺失功能 |

## 差异项（⚠ 需调查）

| Test ID | 基准返回 | 被测返回 | 可能原因 |
|---------|---------|---------|---------|
| B-03 | {"power": 153.20} | {"power": 153.2} | 浮点格式差异 |

## 新功能（ℹ️ 仅记录）

| Test ID | 基准 | 被测 | 说明 |
|---------|------|------|------|
| I-10 | 不支持 | {"result": ...} | 新增 MCP 工具 |

## 一致项
<N> 项行为完全一致（列表省略，详见 results.json）
```

### 差异项的后续处理

- 🔴 回归 → 写 bug report（bug_type: regression），加入 bugs-index
- ⚠ 差异 → 调查是"有意的行为变更"还是 bug：
  - 有意变更 → 更新 test-groups 中该项的期望值
  - bug → 写 bug report
- ℹ️ 新功能 → 如果重要，新增到 test-groups + surface manifest

---

## 跨项目通用化要点

futu-tester 原版用 toml profile + bash 脚本实现。本 skill 把这些能力**提炼为知识文件 + workflow 描述**：

- ❌ 不再生成 toml profile —— 改为 markdown 知识文件（test-groups.md、impact-map.md），人类可读可改
- ❌ 不再用 bash 执行决策树 —— 改为 agent 按本文档的决策逻辑思考并报告
- ❌ 不再要求项目装额外脚本 —— agent 用 Read/Bash 工具直接读知识文件 + 跑测试命令
- ✓ 保留：决策树本身、影响分析模式、suppress / known-behaviors 机制

## 不要做的事

- ❌ 不要跳过 Step 0（上下文研判）直接问用户"你想测什么" —— 先做功课再对齐
- ❌ 不要跳过 Step 5（假设）直接开跑 —— 没有预期就没有对照，容易确认偏误
- ❌ 不要在 affected_groups 为空时强行推荐 targeted —— 没有依据的"定向"是欺骗
- ❌ 不要自动执行 —— 计划必须经用户确认后才交给 test-execution-workflow
- ❌ 不要忽略 suppress 列表，把已 suppress 的 fail 算成 active failures
- ❌ 不要为了速度跳过阶段 —— 质量优先是铁律，跳阶段需要用户显式同意

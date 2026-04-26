# Strategy Workflow

`/better-test strategy` 在跑测试**之前**做：上下文研判 + 范围对齐 + 变更检测 + 影响分析 + 分阶段执行计划。

## Tester 注册（自动）

strategy 是 tester 自动注册的触发点。首次执行 strategy 时：

1. 检查 `.better-work/test/testers/` 是否有**当前 session 对应的活跃 tester**
2. 如果没有 → 自动注册新 tester：
   - 探测平台（env `CLAUDECODE=1` → claude-code；codex config → codex；等）
   - 获取 session_id、model、device 信息
   - 生成 tester-id：`<platform>-<sha1(session_id+timestamp)[:4]>`
   - 创建 `testers/<tester-id>/registry.md`（身份 + Resources 段 + Runs 表）
   - 创建 run 目录 `history/<version>/run-<tester-id>-001-<ts>/`
   - 在 run 目录内写入 `bio.md`（此 run 的身份快照，不可变）
   - 报告："已注册 tester `<tester-id>`（<platform> / <model>）"
3. 如果有单个 tester 且 last_active < 24h → 自动关联，创建新 run 目录（NNN 递增），更新 registry.md 的 Runs 表
4. 如果有多个 tester → 提示用户选择或创建新 tester

### 资源感知

```
注册时扫描所有 testers/*/registry.md 的 Resources 段：
  IF 有其他活跃 tester：
    → 展示其资源占用（端口、daemon PID、config 路径）
    → 新 tester 需要避开已占用的资源
    → 将自己的资源声明写入 registry.md Resources 段

  示例：
    "当前活跃 tester:
      claude-a3f2: daemon port 11111, PID 12345
     本 tester 将使用: daemon port 11112"

资源变更时（如重启 daemon 换端口），tester 更新自己的 registry.md Resources 段。
其他 tester 在需要操作共享资源时按需读取（最终一致，非实时轮询）。
```

### Session 注册（Hook 支持）

```
注册完成后，写入 session 标识文件供 hook 识别当前 tester：
  mkdir -p .better-work/test/.active-sessions
  echo '{"tester_id":"<tester-id>","run_dir":"history/<version>/run-<tester-id>-NNN-<ts>"}' \
    > .better-work/test/.active-sessions/$PPID.json

$PPID 是 Claude Code 进程的 PID（从 Bash 工具调用中获取）。
session-write-guard.sh hook 使用此文件识别 tester 身份，阻止跨 tester 写入。

Session 清理：tester 完成所有测试后删除自己的 session 文件。
```

### 注册门控（Gate）

```
注册完成后，必须验证以下文件存在才能继续：
  1. testers/<tester-id>/registry.md — 存在且含 YAML frontmatter
  2. history/<version>/run-<tester-id>-NNN-<ts>/bio.md — 存在
  3. .active-sessions/$PPID.json — 存在（hook 需要）
  任一缺失 → 阻断，不进入 Step 0（context_research）
```

### 写权限矩阵

```
Tester 测试期间可写：
  ✅ testers/<自己的 id>/registry.md     ← 自己的可变状态（资源、Runs 表）
  ✅ history/<version>/run-<自己>-*/      ← 自己的 run 输出（全部文件）

Tester 测试期间不可写：
  ❌ testers/<别人>/ 或 run-<别人>-*/     ← 其他 tester 的文件
  ❌ test/status.md                       ← derived view，coordinator 写
  ❌ test/known-issues.md                 ← derived view，coordinator 写
  ❌ history/bugs-index.md                ← derived view，coordinator 写
  ❌ history/feedback-rules.json          ← derived view，coordinator 从 feedback 文件重建

对其他 tester 的读权限：按需读取 testers/*/registry.md（了解资源占用）。
```

后续所有写操作使用此 tester-id 隔离，产出写入 run 目录。

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
5.5 persist_plan         ← 写 strategy-plan.md（status: draft）
6. present_to_user       ← 从 strategy-plan.md 展示 + 确认 → status: confirmed
7. emit_to_execution     ← execution 读 strategy-plan.md
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

### 经验提取（从现有知识文件提取本次相关的规则）

```
从 known-issues.md lessons 段 → 提取与本次变更/测试组相关的经验教训
从 test-groups.md failure modes → 提取本次涉及的组的典型失败模式
从 env-config.md 注意事项 → 提取当前环境的约束和基准定义

→ 合并为"本次测试需要注意的 N 条关键经验"
→ 在 Step 0.5 展示给用户
→ 传递给 test-execution-workflow 作为执行计划的"本次需特别注意"段
```

这些经验不在 protocol 里（protocol 只放通用思维原则），而是从项目知识文件中**按当前上下文动态提取**。

### 形成初步判断

```
基于以上材料，综合判断：

  风险区域: "本版本改了 auth 模块，历史上 auth 区域有 3 个 bug（BUG-claude-a3f2-001, 003, 007），
           上次跑 A 组时 A-03 flaky（稳定性 70%），开发者上次反馈说 session 处理重构了"

  建议重点: "A 组全跑 + BUG-claude-a3f2-001 回归验证 + D 组因为和 auth 共享 session fixture 也建议跑"

  待确认: "不确定这次重构是否影响了 MCP 的 auth 路径——代码 diff 可以确认"

  ⚠ 全绿校验: IF 上次运行全部通过且本次初步判断无高风险：
    → 不要直接跳过，先检查：error path 覆盖了吗？负向测试做了吗？三种用户姿态测了吗？compare 做了吗？
    → "0 bug 是红灯不是绿灯"——全绿时第一反应应是"漏了什么"
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

  声称修复的条目特殊处理：
  → 在计划中标注 `[CHANGELOG 声称修复——需验证]`，优先级高于普通变更
  → 实测未变时在报告中醒目标出 `[CHANGELOG 声称修复但未确认]`
```

### 版本基线快照

```
IF 旧版本仍可用且未保存过基线：
  → 在执行测试前，先用旧版本跑关键接口保存行为快照
  → 存入 history/<old_version>/baseline.json
  → 供 compare 模式和 reflect 使用
```

### 测试前提验证（Pre-check）

```
在生成分阶段计划之前，验证以下前提条件：

1. 标的物有效性: 确认所有测试标的物（代码/合约/产品/URL）当前有效存在
   → 期货有到期日、期权有行权日、临时 token 会过期——用 stock_list/static-info 确认
   → 标的不存在会被误判为"系统路由错误"，浪费大量排查时间

2. 环境清理: 确认测试环境无残留状态
   → credentials 文件（同 platform 多账号可能碰撞）、端口占用、残留进程
   → 具体清理步骤由 env-config.md 注意事项定义

3. 环境确认: 验证测试前提假设
   → baseline 接口类型（REST vs 二进制协议）、密码可用性、枚举正确值
   → 每个"我以为"都是一个潜在的环境陷阱

4. 时段依赖标注: 标注哪些测试项依赖时间/市场时段
   → 不在正确时段时标 skip + 具体原因，不要强行测得到模糊结果

5. 测试方案可行性: 不只检查环境，还要检查"这个测试方案能不能做"
   → 需要交易密码但没有？需要特定账号类型但没有？需要 real 市场但今天周末？
   → 不是测到一半才发现不可能——Setup 阶段就排除不可执行的项

6. 声称"做不到"前先尝试 subagent 分担
   → 3 个"不可能"在 25min 内被 subagent 解决的真实案例
   → "做不到"是 90% 的借口，除非穷尽了 subagent 方案
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
  三种用户姿态: 每个关键接口列出三种请求体——完整参数(熟悉者) / 只传 required(新手) / 核心字段(LLM agent)
  字段三态枚举: 每个可选字段至少测 3 种状态——key 缺失 / null / 合法值
  error path 显式列出: 计划中为每个接口显式列出 error path 测试项，与 happy path 同等权重。静默失败（ret=0 但无效果）比报错更危险
  穷举边界标准（agent 边际成本 ≈ 0，穷举优于采样）:
    数值: 7 点（min-1 / 0 / 1 / 合理值 / 上限 / 上限+1 / INT_MAX）
    枚举: 全扫 0-100（或 binary 中已知的全部 variant）
    字符串: 5 点（空 / 短 / 长 / 格式错 / 合法）
    日期: 4 点（倒置 / 过去 / 未来 / garbage）
  Body 格式矩阵: 每个 endpoint 测 4 种格式（flat / c2s wrapper / camelCase / snake_case），不同格式走不同解析路径

阶段 3: 回归验证
  输入: bugs-index 中 FIXED 未 VERIFIED 的 bug + active_failures + regression canary
  做什么: 跑 related_tests，和修复前对照验证因果关系
  准确度要求: fix 的验证需要 confirmed 级证据（不是"跑通了就行"）
  sim≠real: 涉及 backend 交互的 bug retest 必须选 real 账号。sim 错误码可能与 real 不同，同一 bug 在 sim 上可能不可见
  全路径覆盖: bug 标 VERIFIED 前必须覆盖所有已知 failure paths。changelog 提到"补修某路径"时该路径必须单独验证
  跨 tester 复现: 采信其他 tester 的 bug 前必须亲自复现——复现不只是确认，还能帮自己排查问题

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

阶段 5+: 状态回验（贯穿所有阶段后）
  测试操作可能改变账户/系统状态（如 margin 消耗、挂单数量变化）
  所有阶段完成后重新验证关键状态，确认无不可逆变化
  如有异常 → 记录到 process-log 并评估是否影响测试结论
```

### 贯穿所有阶段的准确度铁律

```
1. 每个 🔴 fail 产生时立刻加对照 → 证据从 direct 升级到 confirmed
2. 每个 🟡 产生时立刻升级 → 不积累模糊状态
3. 每个 ✅ pass 必须有 field-level 证据 → exit=0 级别不算 pass
4. 每个结论的证据级别 ≥ direct → indirect 不能出现在最终结果中
5. 宁可 ⏭️ 写原因也不降低证据标准凑覆盖率
6. 每个阶段完成后报告证据质量分布（confirmed / direct / indirect 各几项），indirect >30% → 立即补强
7. 推测即验证: 标了推测/indirect 的结论必须在当 Phase 内验证——标注和验证在同一动作完成。推测停留不验证 = 违规
8. 单次观测不定论: 异常值至少两个时间点采样（间隔 ≥5min）+ 参考实现对照，区分暂态(cache)/持久(bug)。暂态未确认持久性不得报 bug
9. 合理化阻断: 看到异常先查参考实现（按 Ground Truth 层级），后下结论。"可能是设计如此"/"可能是闭市"不是调查终点
10. severity 用最坏场景下谁受影响定，不用自己碰到的场景。pre-existing 记在 fix_note 不降 severity
11. 覆盖声明必须附验证数量占总数比例（"4 项验证一致"不等于"184 个接口一致"）
12. 🟡 产生时就地解决——"先全部跑完再处理"导致 🟡 永远不会被处理
13. "Inferred not fixed" ≠ "proven not fixed"：未复现 ≠ fixed，归 INCONCLUSIVE。没做混沌注入就不能说"已修"
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

  假设格式（必须包含具体预期值和验证方法，"应该能工作"/"应该已修"不是合格假设）：
    IF <变更描述> THEN <可能的影响> BECAUSE <推理>
    预期结果: <具体字段名 + 预期值/行为>（必须足够具体，能在测试后机械对照）
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

## Step 5.5: 持久化计划（persist_plan）

Step 4 + 5 完成后，将完整计划（含假设）写入当前 run 目录的 `strategy-plan.md`，status 设为 `draft`。

### 写入流程

```
1. 如果 run-<tester-id>-NNN-<ts>/strategy-plan.md 已存在且 status != completed:
   → 旧文件 status 改为 superseded，last_updated 更新
   → 再写新文件（覆盖）

2. 组装 strategy-plan.md：
   - YAML frontmatter: tester_id, version, mode, status=draft, created, confirmed_at=null, last_updated, total_stages, total_items
   - Context Summary ← Step 0 摘要
   - Change Analysis ← Step 1 变更检测结果
   - Impact Scope ← Step 2 影响分析
   - Phased Plan ← Step 4 分阶段计划
   - Hypotheses 嵌入 Stage 2 ← Step 5 假设
   - Known Risks ← 从 Step 3 提取
   - User Adjustments ← 留空（Step 6 填写）
   - Accuracy Rules ← 准确度铁律

3. 写入 run-<tester-id>-NNN-<ts>/strategy-plan.md
```

### 多 Agent 协调

```
写入前，扫描其他 tester 的 run 目录中的 strategy-plan.md（排除自己）：
  → 读取 testers/*/registry.md 找到各 tester 的最新 run 路径
  → 读取各 run 目录下的 strategy-plan.md

  IF 存在其他 tester 的计划且 status 为 confirmed 或 in-progress：
    → 提取其 Phased Plan 中的 groups 列表
    → 在 Step 6 展示时附加：
      "其他 tester 正在测试的组：
        claude-a3f2: A, B, C 组（in-progress）
        codex-c9d4: D, E 组（confirmed）
       建议避开重复覆盖。"
    → 不自动排除（用户决定），但提供信息

  Dual-tester blind spot 警告：
    → 两个同型 tester（相同 model、相同 prompt）共享盲区
    → 真对抗需：不同 model / 不同角色强制 / 不同 oracle / 不同 evidence 要求
    → 如果只有同型 tester，至少确保用不同账号 + 不同 surface 测试路径
```

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

### 确认后更新 strategy-plan.md

```
用户确认后：
  → 更新 strategy-plan.md YAML: status=confirmed, confirmed_at=<now>, last_updated=<now>
  → 如果用户做了调整 → 填写 "## User Adjustments" 段（具体改了什么）
  → 如果用户原样接受 → User Adjustments 写 "Accepted as-is"
```

## Step 7: 交给 test-execution-workflow（emit_to_execution）

用户确认后，test-execution-workflow 从当前 run 目录的 `strategy-plan.md` 读取计划：
- 分阶段计划（Phased Plan 段）
- 每阶段的假设（Hypotheses 段）
- 准确度铁律（Accuracy Rules 段）
- 用户追加的上下文（User Adjustments 段）

执行开始时更新 `strategy-plan.md` YAML：`status=in-progress, last_updated=<now>`。
所有阶段完成后更新：`status=completed, last_updated=<now>`。
同时更新 `testers/<tester-id>/registry.md` 的 Runs 表状态。

### 子 Agent 委托规则

```
IF 计划中某些阶段/组委托给子 agent 执行：
  1. Spot check: 主 agent 必须抽查 ≥20% 的子 agent ✅ 结论（用不同账号/参数/验证方法）
     → bug retest 结论必须亲自验证关键项（子 agent 缺乏完整上下文，可能做出"局部合理但全局错误"的判断）
  2. 资源锁定: sub-agent 必须锁死资源标识（端口号/账号）
     → 指定资源无响应时报错退出，不自动寻找其他端口
  3. 并行隔离: 破坏性操作（重启服务/切换配置）的测试组最后跑、单独跑
     → 同资源多 agent 会互斥，测试前规划好资源分配（账号、端口、进程）
```

### L2 对抗审查

```
触发条件: full / targeted / compare / bug-retest 模式完成后，主动 spawn 子 Agent 做对抗审查
  → 不是被提醒才做，是流程必做步骤
  → 加载 references/l2-audit-prompts.md

审查焦点: L2 的价值在于挑战定性，不在于发现新 bug
  → severity 评级是否用了"最坏场景"标准
  → pass/fail 判定是否有 field-level 证据（不是用 trivial case 凑 pass）
  → skip 是否掩盖了已知缺陷（应标 fail + pre-existing）
  → 覆盖声明是否附了覆盖率
```

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

### Ground Truth 层级

```
对照时的正确性层级（高到低）：
  1. App / UI（终端用户看到的值）— 最终 ground truth
  2. 参考实现（C++ / Python SDK）— 技术 ground truth
  3. 被测对象（新实现）

比较时对齐字段语义，不只比数值。
  → 参考实现的 power 字段 ≠ App 的"购买力"——它们可能是不同计算
  → 不同账号登录时数据不同，比较返回字段结构一致性（核心字段是否都有）> 数值一致性
```

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
- ❌ 不要 blind retry 错误 —— 先读错误消息，不同码不同根因，盲试可能触发 rate-limit
- ❌ 不要在声称"做不到"前放弃 —— 先尝试 subagent 分担

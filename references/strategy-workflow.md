# Strategy Workflow

`/better-test strategy` 在跑测试**之前**做：变更检测 + 影响分析 + 综合推荐策略。让 agent 不用每次都问"该跑哪组"。

## 核心流程

```
1. detect_changes        ← 从版本/代码差异提取变更信号
2. analyze_impact        ← 用 impact-map 把变更关键词映射到测试组
3. read_history          ← 读历史结果 + feedback-rules
4. recommend_strategy    ← 决策树推荐
5. pre_check             ← 凭证/依赖预检 + 结构性检查
6. present_to_user       ← 展示分析过程 + 让用户确认/调整
7. emit_command          ← 输出可执行的测试命令（不自动跑，由用户决定）
```

---

> **测试执行纪律**（四色标记、错误解读三问、终态规则、安全守则、凭证预检）
> 已移至 `test-execution-workflow.md`。Strategy 负责"推荐跑什么"，execution 负责"怎么跑"。

---

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

### 信号源 D：用户提供（兜底）

```
如果以上都拿不到 → 询问用户："这个版本相比上次有什么变化？"
来源标记: user-input
```

如果**所有信号源都为空** → strategy 推荐 `smoke`（最低成本验证基线）。

## Step 2: 影响分析（analyze_impact）

读 `.better-work/test/impact-map.md`，做关键词匹配：

```
对每个 changes 中的描述：
  小写化 → 在 impact-map.md 的关键词表中查找匹配
  匹配命中 → 把对应的测试组加入 affected_groups 集合
返回 affected_groups 的去重列表
```

如果 impact-map.md 中某条目标 `[未验证]`，仍然参与匹配但在 present 时提示 "基于未验证映射"。

> **不内置 ">50% 升级 full" 规则**。futu-tester 源材料无此阈值，本 skill 也不擅自加。如果项目需要这种升级策略，应该在 `impact-map.md` 的"全量触发条件"段（见 templates.md）显式列出，不靠隐式阈值。

## Step 3: 读历史（read_history）

```
读 .better-work/test/history/<current_version>/run-NNN-*/results.json
取最近一次（按 run 编号最大的）
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

## Step 4: 决策树（recommend_strategy）

按以下顺序判断，第一个匹配的即为推荐：

```
IF 当前版本相比上次测过的版本是 major 或 minor 升级（如 1.3.x → 1.4.0）:
  → full
  reason: "跨 major/minor 版本，推荐全量回归"

ELIF 当前版本从未测过 (run_count == 0):
  IF affected_groups 非空:
    → targeted:<affected_groups>
    reason: "该版本首次测试，基于 changelog 影响分析推荐定向测试"
  ELSE:
    → smoke
    reason: "该版本首次测试且无变更信息，推荐 smoke 快速验证"

ELIF active_failures 非空 OR bug_retest_candidates 非空:
  → bug-retest:<active_fail_ids + bug_retest_candidates>
  reason: "上次有 N 项活跃 fail + M 个已修复待验证 bug，推荐复测"
  注：bug_retest_candidates 来自 bugs-index.md 中 status=FIXED 的 bug 的 related_tests

ELSE:
  → pass (必须显式问 y/N，默认 N)
  reason: "该版本已测 N 次，全部通过（或仅剩 suppress 项），无待验证 bug"
  agent 行为: 显示"该版本已全部通过，确定再跑吗？[y/N]: "，等待用户回复
              y → 降级为 smoke 跑一次最低成本验证
              N（默认）→ 跳过测试，输出"已建议跳过"
```

注意：

- "跨 major/minor" 的判定基于 semver。`1.3.5 → 1.4.0` 是 minor bump，`1.4.5 → 2.0.0` 是 major bump，`1.4.5 → 1.4.6` 是 patch（不触发 full）
- 如果项目不用 semver（如 git SHA、CalVer），用别的判定（询问用户配置）
- `affected_groups` 来自 Step 2，可能为空集

## Step 5: 展示给用户（present_strategy）

给用户看的分析报告应包含：

```
当前版本:    v<version>
历史运行:    <count> 次
上次版本:    v<prev_version>（如有）

检测到的变更（来源: <changelog|help-diff|git-log|user-input|none>）:
  · [前 15 条 bullet]
  ...

受影响测试组:
  <group_letters>

已知行为（可能产生预期内的 fail）:
  · [from known_behaviors]
  ...

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
推荐策略: <smoke|full|bug-retest|targeted:X Y|pass>
理由: <reason>
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

可选操作:
  1) 接受推荐
  2) smoke
  3) full
  4) targeted:<指定组>
  5) bug-retest（若有 active failures 或待验证 bug）
  6) compare（对照测试，需要定义对照目标）
  7) 跳过测试
```

## Step 5.5: 条件检查（Tier 2 — 满足条件时触发）

以下检查不是每次都做。根据 Step 1-4 的结果，条件匹配时才触发。

### 变更批量检查（条件：Step 1 检测到变更文件列表）

```
> 15 个文件 → ⚠ "大批量变更风险高，建议拆分后逐批测试"
6-15 个文件 → 提醒"变更较多，建议分批"
≤ 5 个文件 → 不提醒
```

### 组合策略建议（条件：推荐 full 或 targeted 模式）

```
full 模式 → 建议配合代码审查 + 静态分析（不是 better-test 职责，但值得提醒）
targeted + 核心业务变更 → 建议对变更文件做增量变异测试
```

### 发布策略建议（条件：smoke 模式且场景为发布前回归）

```
供参考：金丝雀发布 / 特性开关 / 蓝绿部署
```

详细说明见 `references/methodologies/` 对应文件。

## Step 6: 输出命令（emit_command）

根据用户选择，**输出**对应的测试命令但**不自动执行**（由用户决定何时跑）：

| 策略 | 输出格式 |
|------|---------|
| smoke | 项目约定的 smoke 命令（来自 test-groups.md 中 `smoke_groups` 段） |
| full | 项目约定的 full 命令 |
| targeted:X Y | 把组 X、Y 对应的命令逐条列出 |
| bug-retest | 列出 active_failures + 待验证 bug 的复测命令 |
| compare | 见下方"对照测试模式" |
| pass | 不输出命令，提示"已建议跳过" |

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

- ❌ 不要跳过 Step 1 直接跑 full —— 这是 strategy 的核心价值（精准 vs 全量）
- ❌ 不要在 affected_groups 为空时强行推荐 targeted —— 没有依据的"定向"是欺骗
- ❌ 不要自动执行测试命令 —— Step 6 只输出，由用户确认
- ❌ 不要忽略 suppress 列表，把已 suppress 的 fail 算成 active failures

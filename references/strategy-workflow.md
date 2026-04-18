# Strategy Workflow

`/better-test strategy` 在跑测试**之前**做：变更检测 + 影响分析 + 综合推荐策略。让 agent 不用每次都问"该跑哪组"。

## 核心流程

```
1. detect_changes        ← 从版本/代码差异提取变更信号
2. analyze_impact        ← 用 impact-map 把变更关键词映射到测试组
3. read_history          ← 读历史结果 + feedback-rules
4. recommend_strategy    ← 决策树推荐
5. present_to_user       ← 展示分析过程 + 让用户确认/调整
6. emit_command          ← 输出可执行的测试命令（不自动跑，由用户决定）
```

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
```

`active_failures = recent_fails - suppress`

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

ELIF active_failures 非空:
  → bug-retest:<active_fail_ids>
  reason: "上次有 N 项活跃 fail（已排除 suppress），推荐复测"

ELSE:
  → pass (必须显式问 y/N，默认 N)
  reason: "该版本已测 N 次，全部通过（或仅剩 suppress 项）"
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
  5) bug-retest（若有 active failures）
  6) 跳过测试
```

## Step 6: 输出命令（emit_command）

根据用户选择，**输出**对应的测试命令但**不自动执行**（由用户决定何时跑）：

| 策略 | 输出格式 |
|------|---------|
| smoke | 项目约定的 smoke 命令（来自 test-groups.md 中 `smoke_groups` 段） |
| full | 项目约定的 full 命令 |
| targeted:X Y | 把组 X、Y 对应的命令逐条列出 |
| bug-retest | 列出 active_failures 中每个 ID 的复测命令 |
| pass | 不输出命令，提示"已建议跳过" |

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

# Test Execution Workflow

测试执行框架。本文件不是固定流程——它是一个**框架 + 模板**，agent 在实际执行测试时结合通用知识 + 项目专属知识生成当次执行计划。

## 设计理念

固定流程无法适应所有项目。一个金融 daemon 的测试执行和一个 CLI 工具的测试执行差异巨大。本 workflow 提供：

1. **通用框架**（本文件）— 所有项目共用的执行纪律和标记规则
2. **项目知识注入点**（标记为 `[PROJECT]`）— agent 从 `.better-work/test/` 读取项目专属信息填入
3. **生成的执行计划**（输出到对话中）— 结合 1+2 为当次测试生成具体步骤

## 执行计划生成

每次开始测试执行前，agent 按以下步骤生成当次执行计划：

```
输入：
  strategy 推荐的测试组和模式（来自 strategy-workflow）
  + test-groups.md       [PROJECT] 测试组定义（运行命令、条件、断言）
  + impact-map.md        [PROJECT] 变更影响映射
  + known-issues.md      [PROJECT] 已知问题（suppress / flaky / lessons）
  + protocol.md          [PROJECT] 测试认知约束
  + 用户提供的材料       [PROJECT] API 规范、错误码表、测试账号等

输出：
  当次测试的具体执行计划（在对话中展示给用户确认）
```

### 执行计划模板

```markdown
# 测试执行计划 — v<version> <mode>

## 环境确认
- [ ] daemon/服务状态: [PROJECT: 从 test-groups.md 运行条件提取]
- [ ] 端口确认: lsof -iTCP:<port> -sTCP:LISTEN → 只有目标进程
- [ ] 测试账号: [PROJECT: 从 test-groups.md 提取所需账号类型]
- [ ] 环境变量: [PROJECT: 从 test-groups.md 提取所需变量]
- [ ] 不可逆操作策略: a) 全执行 / b) 逐项问 / c) 全跳过 → 用户已选: [  ]

## 执行顺序
[PROJECT: 从 strategy 推荐的组列表 + test-groups.md 的组定义生成]

### 组 <Letter>: <Name>（<N> 项）
- 运行命令: [PROJECT: 从 test-groups.md 取]
- 关键断言: [PROJECT: 从 test-groups.md 取 EXPECT_PATTERN]
- 已知问题: [PROJECT: 从 known-issues.md 取该组相关的 suppress/flaky 项]
- 预计耗时: [PROJECT: 从 test-groups.md 取]

### 组 <Letter>: <Name>（<N> 项）
...

## 本次需特别注意
- [PROJECT: 从 known-issues.md lessons 段取与本次测试组相关的经验]
- [PROJECT: 从 impact-map.md 取本次变更可能影响但未在推荐组内的边缘区域]
```

---

## 通用执行纪律（Tier 1 核心流程）

以下规则适用于所有项目的所有测试执行，不依赖项目专属知识。

### 四色标记

每个测试项执行后立即标记结果：

```
✅ = 返回值正常 + 关键字段已验证（具体字段名 + 值）
🟡 = 待确认（模糊错误或空结果）→ 必须升级，不是终态
🔴 = 失败（有错误码或 log 证据）
⏭️ = 显式跳过（必须写原因）
```

### 🟡 升级路径

```
🟡 检测到空结果或模糊错误
  ↓
grep daemon/service log 查 error code
  ↓
有 error code → 🔴（附 code）
无 error code → ✅（确认真空）
模糊 hint   → 错误解读三问（见下方）
```

### 错误解读三问

遇到模糊错误（-400 / -1 / 含 hint 的错误）时：

```
1. 来源：服务自加的 hint 还是 backend 真错？→ 看 debug log 原始 code
2. 参数 vs 程序：换确定正确的等价参数还报同样错？→ 排除参数问题
3. 验证假设：写下"如果是 X，会看到 Y" → 去找 Y → 没有则换假设
禁止：直接重试 / 直接换参数 / 直接放弃
```

三问无法定位 → 加载 Tier 2 `procedures/hypothesis-investigation.md`（3-假设调查法）。

### 证据分级

每个判断必须标注证据级别：

| 级别 | 可用于 |
|------|--------|
| **indirect** | 仅用于形成假设 |
| **direct** | ✅ pass 判定、🔴 fail 报告 |
| **confirmed** | 根因确认、写入 known-issues lessons |
| **proven** | 系统性模式、更新 impact-map 为 verified |

不允许 guess 级别出现在任何输出中。

### 终态规则

```
每个测试项必须到达终态之一：✅ / 🔴 / ⏭️
不允许：
  "暂时跳过"（无原因）
  "下次再看"（不会有下次）
  "应该没问题"（是 guess，不是 evidence）
  🟡 停留（必须升级）
```

### 安全守则

```
- 不把账号/密码/token 写入任何 .better-work/ 文件
- 不可逆操作按用户在"环境确认"中选择的策略执行
- 即使用户允许全执行，也优先用安全方式（sim 账户 + 远离市价 + 立即撤单）
```

---

## 执行过程中的 Tier 2 触发点

执行过程中遇到以下情况时，加载对应的 Tier 2 扩展流程：

| 触发条件 | 加载什么 |
|---------|---------|
| 三问无法定位失败原因 | `procedures/hypothesis-investigation.md` |
| 同一测试连续 2 次结果不一致 | `procedures/flakiness-scoring.md` |
| 用户要求对某模块做深度探索 | `procedures/exploratory-charter.md` |
| 发现 bug 需要写报告 | `methodologies/bug-report.md`（可执行模板） |

---

## 执行记录

L1 Hook（执行日志记录）自动把每条 Bash 命令 + 输出追加到 `.better-work/test/execution-log.md`。Agent 不需要手动记录执行过程——Hook 替它做。

Agent 需要做的记录：
- 每个测试项的四色标记结果 → 写入 results.json
- 每个 ⏭️ 的跳过原因 → 写入 results.json
- 发现的新问题 → 记到对话中，测试完成后由 update workflow 处理

---

## 测试执行中发现 bug

测试中遇到确认的 🔴 fail（evidence: direct 或更高）且不在 known-issues 已知列表中：

```
1. 加载 procedures/bug-report.md 模板
2. 按 7 节格式写 bug report
3. 写入 history/<version>/bugs/BUG-<NNN>-<slug>.md
4. 更新 history/bugs-index.md 新增一行
5. results.json 中相关 items 的 bug_ids 填入 BUG-<NNN>
6. 继续执行剩余测试（不因发现 bug 中断整组测试）
```

Bug ID 全局递增。如果不确定是不是新 bug（可能是已知 bug 的新表现），先检查 bugs-index.md。

---

## 测试过程中：持续写入过程日志

`process-log.md` 是测试过程的流水账，增量追加，记录 agent 的真实思考过程。

```
格式：

## [HH:MM] <做了什么>
<具体细节>

## [HH:MM] <发现了什么>
<证据>

## [HH:MM] <卡在哪 / 改变了什么判断>
<原因>
```

**关键原则**：
- **只追加不删改** — 即使后面推翻了之前的结论，也不回去改前面的记录。新结论追加在后面，标注"推翻了 [HH:MM] 的判断"
- **记录犹豫和转折** — "一开始以为是参数错，后来发现是 daemon 包装了错误码"这种转折是最有复盘价值的
- **记录"试了但没用"** — 排除的路径和走通的路径一样重要
- **不美化** — 不是写给开发者看的报告，是写给未来复盘的自己

示例：

```markdown
## [14:23] 开始阶段 2：直接影响（A, B 组）

假设：auth 重构可能影响 session 过期处理。

## [14:25] 跑 A-01 (login)
返回 {"session_id": "abc123"} ✅ — session_id 存在且非空。

## [14:27] 跑 A-03 (session timeout)
返回 {"error": -400, "msg": "bad request"} 🟡
→ -400 是 daemon hint 还是 backend 真错？需要查 log。

## [14:29] 查 daemon debug log
grep 发现：recv frame code=-1001 "session expired"
→ 原来是 -1001 被 daemon 包装成了 -400。这不是 bad request，是 session 过期。
→ 推翻 [14:27] 的 🟡 → 升级为 🔴
→ 这说明 daemon 的错误码包装逻辑有问题，不只是 session 的问题。

## [14:32] 加对照：用新 session 重跑 A-03
新 session 返回正常 ✅ → 确认是 session 过期问题，不是接口本身的 bug。
→ 推翻 [14:29] 的"daemon 包装逻辑有问题"→ 实际上 daemon 行为正确，只是 hint 不够清晰。

## [14:35] 结论
A-03: ✅ pass（session 过期后返回错误是预期行为）
  但 daemon 的 -400 hint 容易误导，记为 lesson 候选。
```

---

## 测试完成后：生成三份输出文件

```
1. 写入 results.json → history/<version>/run-NNN/results.json
2. 归档 process-log.md → history/<version>/run-NNN/process-log.md
3. 生成 2 分钟速览 → history/<version>/run-NNN/summary.md
4. 汇总 bug reports → history/<version>/bugs/（每个 bug 独立文件）
5. 如果是 full/targeted 模式 → 触发 L2 独立验证（子 Agent）
6. L2 完成后 → 生成 L3 审计面板（audit-report.md）
7. 归档到 history：
   test/execution-log.md  → 复制到 history/<ver>/run-NNN/execution-log.md
   test/l2-findings.md    → 复制到 history/<ver>/run-NNN/l2-findings.md
   test/audit-report.md   → 复制到 history/<ver>/run-NNN/audit-report.md
   test/ 下原文件保留（供快速读取最近状态）
8. 向用户呈现（按顺序）：
   a. 先呈现 2 分钟速览（用户第一时间看到核心结论）
   b. 再呈现审计面板（用户确认质量 → 通过 / 打回 / 调查）
   c. 过程日志和 bug report 不主动呈现，用户需要时 Read
9. 如有 bug-retest 中的项复测通过 → 更新 bugs-index.md 对应 bug 为 VERIFIED
10. 增量 reflect（自动执行，见下方）
11. 建议 /better-test update 更新知识（如有新发现）
12. 建议 /better-test checkpoint（如任务未完成）
```

### 三份文件的定位

| 文件 | 受众 | 目的 | 风格 |
|------|------|------|------|
| `process-log.md` | 测试者自己（复盘用） | 完整记录试了什么、发现什么、卡在哪、哪里推翻了前面的结论 | 流水账，只追加不删改，保留犹豫和转折 |
| `bugs/BUG-NNN.md` | 开发者（修 bug 用） | 每个 bug 的完整技术细节，结构化整理，不重复 | 7 节模板（procedures/bug-report.md），证据确凿，可复现 |
| `summary.md` | 所有人（2 分钟了解要点） | 最重要的信息 + 最核心的技术证据，大白话 | 极简，理解成本最低 |

### 2 分钟速览模板（summary.md）

```markdown
# 测试速览 — v<X.Y.Z> <mode>
# <日期> | <N> 项测试 | 耗时 <M> 分钟

## 一句话结论
<整体状况：通过/有问题/有严重问题。如 "基本正常，发现 2 个 bug 需要修">

## 发现了什么

<如果有 bug>
🔴 BUG-<NNN>: <大白话一句话说是什么问题>
   实锤: <最关键的一条证据，如 "daemon log 显示 code=-1001 但返回给用户的是 -400">
   影响: <谁会受影响，如 "量化策略用户查不到期权链">

🔴 BUG-<NNN>: <同上>
   实锤: <...>
   影响: <...>

<如果没有 bug>
本轮测试未发现新问题。

## 需要关注但不确定的
<🟡 项或可疑项，大白话说不确定什么>

## 数字
覆盖率: <T>/<R> = <NN>%
✅ <N> | 🔴 <N> | ⏭️ <N>（跳过原因: <...>）
回归验证: BUG-<NNN> <VERIFIED/仍然失败>

## 详细信息在哪
- 完整过程: process-log.md（包含每一步的推理和转折）
- Bug 详情: bugs/BUG-<NNN>.md（可复现步骤 + 对照 + root cause）
- 原始数据: results.json
```

**速览的写作原则**：
- 用大白话，不用术语。"daemon 的错误码包装让用户看不到真正的错误原因"比"daemon augments ret_msg hint masking backend error code"好
- 只讲结论不讲过程。过程在 process-log 里
- 证据只放最关键的一条。不是"我做了 5 步调查"，是"debug log 里看到 code=-1001"
- 影响用"谁会受影响"来说，不用技术术语
- 2 分钟能读完。超过了就砍

---

## 增量 reflect（测试完成后自动执行）

每次测试完成后自动执行。用本次运行数据和现有知识文件比较，立即提取可用经验。不需要用户手动触发。

全量 reflect（跨版本趋势分析）见 `references/reflect-workflow.md`。

### 自动应用（纯数学计算，不需要用户确认）

**稳定性评分更新**：

```
对本次 results.json 中每个测试项：
  读 test-groups.md 中该项的当前稳定性评分
  用本次结果更新评分（滑动窗口：最近 10 次运行）
  写回 test-groups.md
```

**耗时校准**：

```
对本次运行的每个测试组：
  实际耗时 = 该组最后一项完成时间 - 第一项开始时间
  预估耗时 = test-groups.md 中该组的"典型耗时"
  偏差 > 50% → 更新 test-groups.md 的典型耗时为：(旧预估 + 实际) / 2
```

### 需要用户确认的建议

**impact-map 映射验证**：

```
本次运行的变更信号（来自 strategy Step 1 记录）
  + 本次实际 fail 的测试组
  → 对比 impact-map.md：

  情况 A：impact-map 有映射 + 本次 fail 了
    → 建议：升级来源为 verified-on-v<X>

  情况 B：impact-map 无映射 + 本次 fail 了
    → 建议：新增映射条目（来源 inferred-from-history）

  情况 C：impact-map 有映射 + 本次没 fail
    → 不做操作（一次不 fail 不代表映射错，可能是巧合）
```

**bug 热点检查**：

```
本次新发现的 bug → 读 bugs-index.md：
  该 bug 所在模块在 index 中已有几个 bug？
  ≥ 3 个 → 建议：标为热点模块，检查 impact-map 中该模块的权重
```

**经验即时提取**：

```
本次 feedback（如有）→ 读 known-issues.md lessons 段：
  这条 feedback 的 note 和某条已有 lesson 类似？
    → 建议：合并/加强该 lesson 的表述
  这条 feedback 的判定模式和历史某条 feedback 相同？
    → 建议：提炼为新 lesson（"第 N 次遇到同样情况"）
```

### 输出格式

```
增量 reflect 完成：
  自动应用：
    ✓ 稳定性评分：更新了 N 项（D-03: 80% → 70%）
    ✓ 耗时校准：C 组 3min → 5min

  建议（需确认）：
    [1/3] impact-map: auth → A 组，升级为 verified-on-v1.4.29
          依据：本次改 auth 后 A-03 fail
          → 接受 / 拒绝？
    [2/3] bug 热点: src/rest/ 模块已有 4 个 bug
          建议在 impact-map 中提升 REST 相关映射权重
          → 接受 / 拒绝？
    [3/3] 经验提炼: "空 funds 是预期行为"已出现 3 次
          建议加入 lessons: "空账户查询 funds 返回空列表是预期，不是 bug"
          → 接受 / 拒绝？
```

---

## 演进机制

本文件不是一成不变的。随着测试经验积累，通用纪律和框架结构都会升级。

### 什么会触发升级

| 触发信号 | 升级什么 | 来源 |
|---------|---------|------|
| 发现新的通用测试纪律 | Tier 1 核心流程段 | `/better-test protocol-update` 或手动更新 |
| 某个 Tier 2 扩展流程被反复使用 | 考虑提升为 Tier 1（嵌入本文件） | update workflow 信号 4 |
| 某条 Tier 1 规则实际执行中从未触发 | 考虑降级到 Tier 2 或删除 | 回顾 execution-log |
| 项目知识变化（test-groups / known-issues 更新） | 执行计划模板的 [PROJECT] 段自动反映 | 无需手动升级 |
| 新增 Tier 2 扩展流程 | 本文件"Tier 2 触发点"表格需同步 | 新建 procedure 文件时 |

### 升级流程

```
1. 识别升级信号（来自 update / feedback / 用户输入 / protocol-update）
2. 草拟修改内容
3. 一致性检查（见下方）
4. 用户确认
5. 写入修改 + changelog 记录
```

### 一致性检查（每次升级必做）

修改本文件的任何内容前，检查是否与以下文件冲突：

```
检查清单：
  □ protocol.md — 本文件的 Tier 1 规则是否与 protocol 的认知约束矛盾？
    例：protocol 说"pass 必须验证字段"，本文件不能有"exit=0 即 pass"的规则
  □ test-groups.md — 本文件的执行顺序/条件是否与 test-groups 的运行条件兼容？
    例：本文件说"组内连续执行"，但某组的运行条件要求交替执行
  □ known-issues.md — 本文件的终态规则是否与 suppress/flaky 规则一致？
    例：suppress 的项不应被标为 🔴 active fail
  □ Tier 2 procedures — 本文件引用的 Tier 2 文件是否都存在？触发条件是否准确？
  □ constraint-framework.md — L0/L1/L2/L3 的约束是否与本文件的执行纪律一致？
    例：L1 Hook 的空结果提问不应与本文件的 🟡 升级路径矛盾
  □ templates.md — 本文件要求的报告格式是否与 templates 中的模板一致？

冲突处理：
  发现冲突 → 不能只改一个文件。确定"哪个是权威源"，然后同步修改所有相关文件。
  权威源优先级：protocol.md > test-execution-workflow.md > procedures/ > templates.md
```

### 变更日志

本文件的每次修改记录到 `.better-work/test/execution-changelog.md`（格式同 protocol-changelog.md）：

```markdown
## [YYYY-MM-DD] <操作>
- **操作**: add / modify / remove
- **段落**: <修改了哪个段落>
- **内容**: <规则文本>
- **来源**: user-input / session-summary / protocol-update
- **一致性检查**: 已检查 N 个文件，无冲突 / 发现冲突并同步修改 [文件列表]
```

---

## 不要做的事

- ❌ 不要跳过"环境确认"直接开跑 — 缺凭证/端口错 = 浪费时间
- ❌ 不要把 🟡 当终态 — 🟡 必须升级
- ❌ 不要在执行中修改 test-groups.md — 执行完后用 update 命令更新
- ❌ 不要在一个组全部跑完前跳到下一个组 — 组内连续执行，组间有序推进
- ❌ 不要忽略 known-issues — 已知 suppress 项不算 active fail，已知 flaky 项要标注
- ❌ 不要修改本文件而不做一致性检查 — 孤立修改会引入文件间矛盾

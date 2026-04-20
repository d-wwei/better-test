# Templates & Quality Standards

每个 `.better-work/test/` 文件的模板和质量标准。

---

## protocol.md

测试认知约束。每对话通过 `@` 引用自动加载。**影响 agent 怎么思考，不告诉 agent 做什么步骤。** 具体执行步骤在 `test-execution-workflow.md`（Tier 1）。

模板分三部分：**L0 目标校准**（所有版本必带）+ **思维纪律**（所有版本必带）+ **风险扩展**（按项目选）。

### 设计理念

protocol.md 不是操作手册。它的作用是：
1. L0 利用首因效应校准 agent 的方向（"什么是好的测试"）
2. 思维纪律影响 agent 在整个测试过程中的判断方式（无法机械化，只能靠 agent 内化）
3. 风险扩展对高风险项目增加额外的思维约束

以下内容**不放 protocol**（已移到 test-execution-workflow.md Tier 1）：
- 四色标记规则（执行步骤）
- 错误解读三问（执行步骤）
- 覆盖率计算（执行步骤）
- 凭证预检清单（执行步骤）
- 终态规则（执行步骤）

### L0 目标校准（所有版本必带）

```markdown
# Test Protocol

你是测试审计员，不是测试通过助手。
你的成果 = 发现的真实问题数 × 证据强度。通过率不是你的 KPI。

你的训练让你倾向于完整、确定、乐观。在测试中这三个倾向都会造成伤害：
- "完整"让你标 ✅ 而不是 ⏭️ — 一个假 ✅ 会把真 bug 送进生产
- "确定"让你写"通过"而不是"待确认" — 用户需要的是实锤不是安慰
- "乐观"让你报好消息省坏消息 — 漏报的 bug 成本是发现它的十倍
```

### 思维纪律（所有版本必带）

这些是无法机械化为 Hook 或 workflow 步骤的认知规则——只能靠 agent 在推理过程中应用。

```markdown
## 思维纪律
- 间接推测必须标"推测"，只有直接证据可下定论
- 遇到模糊错误先诊断再行动，禁止直接重试或放弃
- 用四态定性（✅ 能用 / 🟡 基础设施有业务缺 / 🔴 没有 / 🐛 做了但坏了），不用二分
```

### 严格版扩展（金融、生产 daemon、长跑系统等高风险）

在思维纪律之后追加：

```markdown
## 安全纪律
- 测试开始时确认不可逆操作策略：a) 全执行 b) 逐项问 c) 全跳过
- flaky 连续 2 次不一致 → 提交 feedback deferred，不默默重试
- 不把凭证写入任何 .better-work/ 文件
```

### 标准版扩展（业务 API、库、内部工具）

```markdown
## 安全纪律
- 不可逆操作执行前确认策略
- 不把凭证写入任何 .better-work/ 文件
```

### 宽松版扩展（实验、原型、demo）

```markdown
## 安全纪律
- 不把凭证写入任何 .better-work/ 文件
```

### 生成示例

**严格版完整输出**（L0 + 思维纪律 + 严格扩展）：

```markdown
# Test Protocol

你是测试审计员，不是测试通过助手。
你的成果 = 发现的真实问题数 × 证据强度。通过率不是你的 KPI。

你的训练让你倾向于完整、确定、乐观。在测试中这三个倾向都会造成伤害：
- "完整"让你标 ✅ 而不是 ⏭️ — 一个假 ✅ 会把真 bug 送进生产
- "确定"让你写"通过"而不是"待确认" — 用户需要的是实锤不是安慰
- "乐观"让你报好消息省坏消息 — 漏报的 bug 成本是发现它的十倍

## 思维纪律
- 间接推测必须标"推测"，只有直接证据可下定论
- 遇到模糊错误先诊断再行动，禁止直接重试或放弃
- 用四态定性（✅/🟡/🔴/🐛），不用二分

## 安全纪律
- 测试开始时确认不可逆操作策略：a) 全执行 b) 逐项问 c) 全跳过
- flaky 连续 2 次不一致 → 提交 feedback deferred，不默默重试
- 不把凭证写入任何 .better-work/ 文件
```

**标准版完整输出**（L0 + 思维纪律 + 标准扩展）：

```markdown
# Test Protocol

你是测试审计员，不是测试通过助手。
你的成果 = 发现的真实问题数 × 证据强度。通过率不是你的 KPI。

你的训练让你倾向于完整、确定、乐观。在测试中这三个倾向都会造成伤害：
- "完整"让你标 ✅ 而不是 ⏭️ — 一个假 ✅ 会把真 bug 送进生产
- "确定"让你写"通过"而不是"待确认" — 用户需要的是实锤不是安慰
- "乐观"让你报好消息省坏消息 — 漏报的 bug 成本是发现它的十倍

## 思维纪律
- 间接推测必须标"推测"，只有直接证据可下定论
- 遇到模糊错误先诊断再行动，禁止直接重试或放弃
- 用四态定性（✅/🟡/🔴/🐛），不用二分

## 安全纪律
- 不可逆操作执行前确认策略
- 不把凭证写入任何 .better-work/ 文件
```

**宽松版完整输出**（L0 + 思维纪律 + 最低安全）：

```markdown
# Test Protocol

你是测试审计员，不是测试通过助手。
你的成果 = 发现的真实问题数 × 证据强度。通过率不是你的 KPI。

你的训练让你倾向于完整、确定、乐观。在测试中这三个倾向都会造成伤害：
- "完整"让你标 ✅ 而不是 ⏭️ — 一个假 ✅ 会把真 bug 送进生产
- "确定"让你写"通过"而不是"待确认" — 用户需要的是实锤不是安慰
- "乐观"让你报好消息省坏消息 — 漏报的 bug 成本是发现它的十倍

## 思维纪律
- 间接推测必须标"推测"，只有直接证据可下定论
- 遇到模糊错误先诊断再行动，禁止直接重试或放弃
- 用四态定性（✅/🟡/🔴/🐛），不用二分

## 安全纪律
- 不把凭证写入任何 .better-work/ 文件
```

### 质量标准

| 项目 | 必须满足 |
|------|---------|
| L0 段 | 所有版本必须包含，不可省略 |
| 思维纪律段 | 所有版本必须包含，不可省略 |
| 内容 | 纯思维约束，零执行步骤（步骤在 test-execution-workflow），零项目信息 |
| 每条 | 影响判断方式而非指定操作 |
| 风险匹配 | 风险越高，安全纪律越严 |
| 行数 | 不设硬限制，但遵循"越短注意力越集中"原则。当前严格版 ~15 行、宽松版 ~12 行 |

---

## protocol-changelog.md

protocol.md 的变更日志。不自动加载，仅在 `/better-test protocol-update` 时读写。

```markdown
# Protocol Changelog

protocol.md 的每次变更记录。只追加，不修改已有条目。

## [YYYY-MM-DD] <操作类型>

- **操作**: add / modify / remove
- **段落**: L0 目标校准 / 思维纪律 / 安全纪律
- **内容**: <规则文本>
- **来源**: init / user-input / session-summary
- **原因**: <为什么加/改/删这条>
- **一致性检查**: 已检查 [文件列表]，无冲突 / 冲突已同步修改
```

init 时自动生成首条记录：

```markdown
## [2026-04-19] init

- **操作**: init
- **段落**: all
- **内容**: <严格/标准/宽松>版模板生成
- **来源**: /better-test init
- **原因**: 首次初始化
```

### 质量标准

| 项目 | 必须满足 |
|------|---------|
| 只追加 | 不修改/删除已有条目（历史不可篡改） |
| 每条有来源 | init / user-input / session-summary，不能空 |
| 每条有原因 | 说明为什么做这个变更，不能只写"更新" |
| 与 protocol.md 同步 | 每次 protocol-update 必须同时写两个文件 |

---

## test-groups.md

测试组定义 + 运行命令 + 运行条件。是 agent 选择跑哪组的权威信源。

```markdown
# Test Groups

## <Letter> <Group Name> （<N> 项）
- 覆盖范围: <一句话：测什么>
- 运行命令: `<精确可执行命令>`
- 运行条件: <环境变量 / 依赖项 / 是否需要真账户>
- 典型耗时: <分钟>
- 关键字段断言示例: `EXPECT_PATTERN='"<field_name>"'`
- 失败模式: <这组挂的话通常是什么原因>
- 测试类型: <unit / integration / e2e / contract / performance>

### 测试项列表

| ID | 名称 | 类型 | 断言字段 | 稳定性 |
|----|------|------|---------|--------|
| <Letter>-01 | <名称> | 功能 / 元数据 | `<field_name>` | 100% |
| <Letter>-02 | <名称> | 功能 | `<field_name>` | 80% ⚠ |
| ... | ... | ... | ... | ... |

---

## smoke 集合
groups: <如 A B E>
total_items: <N>
estimated_time: <分钟>
选组标准: 关键用户旅程（不是"跑得快的测试"）

## full 集合
groups: <ALL>
total_items: <N>
estimated_time: <分钟>
```

### 字段说明

- **测试类型**: 用于测试金字塔结构检查（unit > integration > e2e 是健康比例）
- **测试项 ID**: `<组字母>-<序号>` 格式（如 A-01），全局唯一，被 known-issues / feedback / impact-map 引用
- **类型（功能/元数据）**: 元数据测试不计入功能覆盖率（4 问中的第 1 问）
- **断言字段**: 具体到字段名，不是"返回值正确"（4 问中的第 2 问）
- **稳定性**: 从 history/ 自动计算的 flakiness 评分百分比（见 procedures/flakiness-scoring.md）
- **smoke 选组标准**: 必须写明"为什么选这几组"——应该是关键业务路径，不是随便选的

### 质量标准

| 项目 | 必须满足 | 不合格示例 |
|------|---------|-----------|
| 运行命令 | 可直接复制粘贴执行 | "跑 A 组" |
| 运行条件 | 列全所有依赖（环境、二进制、账户） | "需要环境就绪" |
| 关键字段断言 | 给一个具体字段名 | "断言返回值正确" |
| 测试项 ID | `<Letter>-<NN>` 格式，全局唯一 | 无 ID 或重复 |
| smoke / full 集合 | 组字母 + 项数 + 耗时 + 选组理由 | 只列字母 |
| 测试类型标注 | 每组有 unit/integration/e2e/contract/performance | 空 |

---

## impact-map.md

变更关键词 → 受影响测试组的映射。strategy 工作流的输入。

```markdown
# Impact Map

## 关键词 → 测试组映射

| 关键词 | 影响测试组 | 来源 |
|--------|-----------|------|
| login | A | verified-on-v1.4.27（A-01 失败时确认） |
| auth | A | verified-on-v1.4.27 |
| REST | B C D | inferred-from-history（最近 3 次 REST 改动后这三组都跑过） |
| order | C | human-report（开发者文档说 order 路径只走 C 组） |
| WebSocket | D | verified-on-v1.4.26 |
| keychain | H | verified-on-v1.4.27 |
| MCP | I | verified-on-v1.4.27 |
| panic | R | inferred-from-history |

## 路径 → 测试组映射（如适用）

| 文件路径模式 | 影响测试组 | 来源 |
|-------------|-----------|------|
| `src/auth/*` | A F | inferred-from-history |
| `src/mcp/*` | I | verified-on-v1.4.27 |

## 全量触发条件

以下变更不走 targeted，直接推荐 full：
- 跨 major/minor 版本升级
- 修改了启动参数解析（影响 G 组所有项）
- 修改了核心日志框架（影响 J / R 组的 log 读取）
```

### 来源字段与证据分级的对应

| 来源值 | 对应证据级别 | 含义 |
|--------|------------|------|
| `verified-on-vX.Y.Z` | confirmed | 在该版本实际测试中验证过映射关系 |
| `inferred-from-history` | indirect | 从 git 历史/测试历史推断（"最近 3 次改 X 后 Y 组都挂了"） |
| `human-report` | direct | 开发者或团队成员告知 |
| `[未验证]` | guess | 推测，等后续验证。strategy 使用时会提示"基于未验证映射" |

### 质量标准

| 项目 | 必须满足 |
|------|---------|
| 来源 | **必须填**，不能空。值域：`verified-on-vX.Y.Z` / `inferred-from-history` / `human-report` / `[未验证]` |
| 关键词 | 小写化以便匹配 |
| 全量触发条件 | 列出"覆盖太广不如全跑"的边界 |
| 路径映射 | 如果有源码，优先用路径→组映射（比关键词更精确） |

---

## known-issues.md

人类视图的已知问题表。`feedback-rules.json` 是机器视图，本文件是同步出来的人类版本。

```markdown
# Known Issues

## 已 suppress（不算 active failures）

| Test ID | Verdict | 来源版本 | 原因 |
|---------|---------|---------|------|
| B-05 | not-a-bug | v1.4.27 | 开发者说空 funds 是预期（账户无资金时） |
| H-02 | wontfix | v1.4.26 | macOS Keychain 旧版兼容性问题，不修 |

## 已知行为（仍算 fail，但已知）

| Pattern | 描述 | 来源版本 |
|---------|------|---------|
| D-* | 闭市时 quote 返回 stale 数据，不影响功能 | v1.4.27 |

## Flaky

| Test ID | 不稳定原因 | 稳定性评分 | 缓解 | 是否阻塞 |
|---------|-----------|-----------|------|---------|
| D-03 | WebSocket 订阅时序竞争 | 70% (7/10) | retry 3 次 | no |

## 经验教训

- MCP 工具的多符号参数风格统一为 `symbols: []`，不是 `security_list: [{}]`（v1.4.29 开发者澄清）
- F 组的 scope 测试在 daemon 不带 `--rest-keys-file` 时无法跑，autonomous 路径需 `--managed`
```

### 质量标准

| 项目 | 必须满足 |
|------|---------|
| Test ID | 必须是 test-groups.md 中真实存在的 ID（`<Letter>-<NN>` 格式） |
| Verdict | 取自 `not-a-bug / fixed / wontfix / deferred / fixed-differently` |
| 来源版本 | 该规则首次出现的版本 |
| Flaky 稳定性评分 | 从 history/ 自动计算，格式 `NN% (N/N)`（见 procedures/flakiness-scoring.md） |
| 经验教训 | 是可推广的洞察（evidence: proven 级），不是特定 ID 的现象 |

---

## status.md（自动生成，面向 agent）

每次 strategy / update / feedback 后自动 refresh。**不应人手编辑**（会被覆盖）。

与 `audit-report.md` 的区别：status.md 面向 agent（下次会话的上下文），audit-report.md 面向人（本次测试的审查决策）。

```markdown
# <Project Name> 测试状态（自动生成）

> 最后更新: <YYYY-MM-DD HH:MM> | 当前版本: v<X.Y.Z> | 历史运行: <N> 次

## 项目概况
<一句话项目描述，从 .better-work/shared/index.md 读>

## 测试结构
- 测试金字塔: unit <N> / integration <N> / e2e <N>（从 test-groups 统计）
- 结构警告: <如冰淇淋反模式则标出，否则"无">

## 测试覆盖（<N> 组 / <M> 项）
- A 登录链路 (9项, integration, 稳定性 100%)
- B REST 只读 (5项, integration, 稳定性 90%)
- ...

## 当前状态
- 最近测试: v<X.Y.Z> run-NNN — <P>/<T> pass, <F> fail (mode: <m>)
- 可达覆盖率: T/R = NN%（manifest M, 不可测 U, 可达 R）
- 活跃 fail (<N> 项):
  - B-05 funds 查询: no match for 'power'
- 已 suppress (<N> 项):
  - H-02: macOS Keychain 兼容性
- Flaky (<N> 项):
  - D-03: 稳定性 70%
- 全部通过（如适用）

## 关键经验
- <从 known-issues.md lessons 段同步前 5 条>

## 覆盖缺口
| 模块 / 功能 | 引入版本 | 风险 |
|------------|---------|------|
| ...        | ...     | ...  |

## 索引
- 完整测试组定义: test-groups.md
- 变更影响映射: impact-map.md
- 已知问题详情: known-issues.md
- 历史原始数据: history/<version>/run-NNN-*/results.json
- 审计报告（如有）: audit-report.md
```

### 质量标准

| 项目 | 必须满足 |
|------|---------|
| 总长度 | ≤ 100 行（再长就不是"快速概览"） |
| 数据新鲜度 | 必须在生成时是最新的（自动重算，不复制旧值） |
| 索引部分 | 给出文件名让 agent 知道去哪深查 |
| 测试结构 | 从 test-groups 自动统计金字塔比例 |
| 覆盖率 | 用可达覆盖率（T/R），不用总覆盖率（T/M） |

---

## history/ 目录

### 完整目录结构

```
history/
├── _meta.json                              ← 项目元信息（init 创建）
├── feedback-rules.json                     ← suppress/known/lessons 规则（feedback 命令维护）
├── bugs-index.md                           ← 跨版本 bug 索引（全局视图）
│
└── <version>/                              ← 按版本分目录（如 v1.4.27/）
    ├── run-NNN-<ts>/                       ← 每次测试运行的完整归档
    │   ├── results.json                    ← 测试结果
    │   ├── summary.md                      ← 运行摘要（人类可读）
    │   ├── execution-log.md                ← 执行日志（从 test/ 归档）
    │   ├── l2-findings.md                  ← L2 独立验证结果（从 test/ 归档）
    │   └── audit-report.md                 ← L3 审计面板（从 test/ 归档）
    │
    ├── feedback/                           ← test-level 反馈（per test item）
    │   ├── B-05_not-a-bug.md
    │   └── D-03_deferred.md
    │
    └── bugs/                               ← 本版本发现的 bug 报告
        ├── BUG-001-option-chain-empty.md
        └── BUG-002-auth-timeout.md
```

### 归档流程

测试完成后，把 `test/` 下的临时文件归档到对应的 run 目录：

```
test/execution-log.md  → 复制到 history/<ver>/run-NNN/execution-log.md
test/l2-findings.md    → 复制到 history/<ver>/run-NNN/l2-findings.md
test/audit-report.md   → 复制到 history/<ver>/run-NNN/audit-report.md

test/ 下的原文件保留（供下次会话快速读取最近状态）
```

### _meta.json

```json
{
  "schema_version": 1,
  "project": "<project-name>",
  "test_target": "<被测对象描述>",
  "created_at": "<ISO 时间戳>"
}
```

### feedback-rules.json

```json
{
  "schema_version": 1,
  "suppress": [
    {"test_id": "<id>", "reason": "<note>", "since": "<version>"}
  ],
  "known_behaviors": [
    {"pattern": "<id or pattern>", "note": "<note>", "since": "<version>"}
  ],
  "lessons": [
    {"insight": "<text>", "evidence_level": "proven", "added": "<date>"}
  ]
}
```

lessons 的 `evidence_level` 字段——只有 proven 级的洞察才能写入 lessons。

### results.json（每次测试运行的结果）

```json
{
  "schema_version": 1,
  "version": "<X.Y.Z>",
  "run_id": "run-<NNN>-<timestamp>",
  "mode": "smoke | full | targeted | bug-retest",
  "started_at": "<ISO>",
  "finished_at": "<ISO>",
  "summary": {
    "total": 0,
    "passed": 0,
    "failed": 0,
    "skipped": 0,
    "pending": 0
  },
  "coverage": {
    "manifest_total": 0,
    "unreachable": 0,
    "reachable": 0,
    "tested": 0,
    "reachable_coverage_pct": 0.0
  },
  "items": [
    {
      "id": "<Letter>-<NN>",
      "name": "<测试名称>",
      "group": "<Letter>",
      "type": "functional | metadata",
      "status": "pass | fail | skip | pending",
      "color": "green | yellow | red | skip",
      "assertion_field": "<验证的字段名>",
      "assertion_value": "<实际值>",
      "evidence_level": "direct | indirect | confirmed",
      "skip_reason": "<如果 skip，原因>",
      "error_code": "<如果 fail，错误码>",
      "error_detail": "<错误详情，不含凭证>",
      "stability_score": 1.0,
      "bug_ids": []
    }
  ]
}
```

items 中新增 `bug_ids` 字段——关联该测试项触发的 bug 报告。

### execution-log.md（L1 Hook 自动生成）

由 PostToolUse Hook 在每次 Bash 调用后自动追加，agent 不可编辑。测试完成后归档到 `run-NNN/`。

```markdown
# Execution Log（自动生成，不可编辑）

## [<ISO timestamp>] Bash
CMD: <执行的命令>
EXIT: <退出码>
STDOUT (前 200 行):
<输出内容>

---

## [<ISO timestamp>] Agent (spawn)
PROMPT: <子 Agent 的 prompt 摘要，前 100 字>
RESULT_FILE: <子 Agent 写入的文件路径>

---
```

### audit-report.md（L3 审计面板）

由主 Agent 按模板从 l2-findings.md + results.json + execution-log.md 机械组装。测试完成后归档到 `run-NNN/`。格式见 `code/constraint-framework.md` L3 段。

### Bug Report（bugs/ 目录）

每个 bug 一个文件，按**发现的版本**存放。文件名格式 `BUG-<NNN>-<slug>.md`，ID 全局递增。

使用 `procedures/bug-report.md` 的 7 节模板写正文。底部附 yaml 元数据管理 bug 生命周期：

```yaml
bug:
  id: BUG-<NNN>
  title: <简短标题>
  status: OPEN            # OPEN → CONFIRMED → FIXED → VERIFIED → CLOSED
  severity: P1 | P2 | P3
  found_in: v<X.Y.Z>
  found_by_run: run-<NNN>-<ts>
  related_tests: [<Letter>-<NN>, ...]
  bug_type: regression | integration | edge_case | environment | data | concurrency

  # 开发者修复后填入
  fix_commit: null
  fix_version: null
  fix_note: null          # 开发者对修复的说明

  # 验证修复后填入
  verified_in_run: null
  verified_at: null
  regression_canary: false # 是否已加入回归 canary
```

### Bug 生命周期

```
1. 测试中发现 bug
   → agent 写 bug report 到 history/<version>/bugs/BUG-NNN-slug.md
   → status: OPEN
   → results.json 中相关 items 的 bug_ids 填入 BUG-NNN
   → bugs-index.md 新增一行

2. 开发者确认
   → 更新 status: CONFIRMED
   → 可选：开发者补充 root cause 信息到 bug report 第 5 节

3. 开发者修复
   → 更新 status: FIXED + fix_commit + fix_version + fix_note
   → 下次 strategy 自动推荐 bug-retest 覆盖 related_tests

4. 复测验证
   → 复测通过 → status: VERIFIED + verified_in_run + regression_canary: true
   → 复测失败 → status 回退为 OPEN，在 bug report 中追加新的失败记录

5. 关闭
   → 经过至少一个版本的回归验证无复发 → status: CLOSED
```

### 开发者修复反馈与 test-level feedback 的区别

| 场景 | 用什么机制 | 写哪里 |
|------|-----------|--------|
| 开发者对某个**测试项**的判定 | `/better-test feedback <test_id> <verdict>` | `feedback/<id>_<verdict>.md` + `feedback-rules.json` |
| 开发者修了某个 **bug** | 更新 bug report 的 yaml status | `bugs/BUG-NNN.md` → 触发 bug-retest |
| 测试项 fail 关联到 bug | results.json 的 `bug_ids` 字段 | `results.json` items |

两个流程独立但有交叉：一个 bug 可能关联多个 test item，一个 test item 的 fail 可能触发新 bug report。

### bugs-index.md（跨版本 bug 索引）

bug 可能跨版本（v1.4.28 发现，v1.4.29 修复，v1.4.30 验证），需要全局索引：

```markdown
# Bug Index

> 自动维护，每次 bug report 创建/更新时同步刷新。

| ID | 标题 | 状态 | 类型 | 严重 | 发现版本 | 修复版本 | 关联测试 | 回归 canary |
|----|------|------|------|------|---------|---------|---------|------------|
| BUG-001 | option chain 窝轮返回空 | VERIFIED | integration | P1 | v1.4.28 | v1.4.29 | C-05, C-07 | ✓ |
| BUG-002 | auth timeout on slow net | OPEN | environment | P2 | v1.4.28 | — | A-03 | — |
```

**strategy 使用方式**：读 bugs-index.md，如果有 FIXED 但未 VERIFIED 的 bug → 自动推荐 bug-retest 覆盖其 related_tests。

### 质量标准（history/ 整体）

| 项目 | 必须满足 |
|------|---------|
| Bug ID | `BUG-<NNN>-<slug>` 格式，全局递增，不重复 |
| Bug status | 只通过生命周期流程更新，不跳阶段（不能 OPEN → CLOSED） |
| related_tests | 必须是 test-groups.md 中存在的 ID |
| 归档完整性 | 每次 run 归档必须包含 results.json；如有 L2/L3 则一并归档 |
| 不含凭证 | results.json 的 error_detail、bug report 的复现步骤都不能包含密码/token |

---

## progress.md

见 `references/progress-workflow.md`。

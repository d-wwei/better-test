# Protocol Update Workflow

`/better-test protocol-update [text]` — 基于用户输入或会话经验，升级 `test/protocol.md` 中的测试认知约束。

## 为什么需要 protocol-update

protocol.md 在 init 时生成的是模板版本。随着用户实际跑测试、踩坑、积累经验，会发现新的铁律和触发器。这些经验如果只留在对话里，下个 session 就丢了。protocol-update 把它们固化到 protocol.md 中，让每次会话都能受益。

## 输入模式

### 模式 A：用户显式输入

```
/better-test protocol-update "POST 交易类测试必须先 unlock-trade"
```

用户直接提供要加入的原则文本。agent 负责分析它应该归入哪个段落。

### 模式 B：自动总结（无参数）

```
/better-test protocol-update
```

agent 回顾当前会话中的测试相关讨论，提取候选经验：

- 踩过的坑（"原来这个接口闭市后返回空数据，不算 fail"）
- 发现的模式（"所有 MCP 测试都要用 tools/call 不是 tools/list"）
- 重复出现的检查动作（"每次跑 F 组前都要确认 scope 配置"）
- 讨论中达成的共识（"flaky 超过 3 次就该 deferred"）

筛选标准：
- ✓ 可推广到未来所有测试会话的经验 → 候选
- ✗ 只适用于特定测试 ID 或特定版本 → 不适合 protocol，应去 known-issues.md 的 lessons 段或 test-groups.md

## 执行流程

### Step 1: 读取当前状态

```
读 test/protocol.md — 当前活跃规则
读 test/protocol-changelog.md — 变更历史（判断是否重复）
统计当前行数（≤15 行限制）
```

### Step 2: 分析候选原则

对每条候选，判断：

**归属段落**：
- 通用原则 — 所有版本都必须遵守的底线（如 pass 验证、skip 标注、凭证安全）
- 安全 — 涉及不可逆操作、账户安全、数据保护（仅严格版）
- 触发器 — 特定场景下的检查动作（"即将做 X → 先做 Y"）

**冲突检测**：
- 与现有规则重复？→ 建议合并而非新增
- 与现有规则矛盾？→ 标出冲突，让用户决定替换还是放弃
- 是否是项目特定信息？→ 拒绝，引导到 test-groups.md 或 known-issues.md

**行数检查**：
- 加入后仍 ≤15 行？→ 直接加
- 超限？→ 提出瘦身方案：
  - 合并相近的两条规则为一条
  - 将信息密度低的规则降级到 known-issues.md 的 lessons 段
  - 用更简洁的措辞重写

### Step 3: 呈现变更方案

向用户展示：

```
当前 protocol.md（<N>/15 行）:
  [显示完整内容]

提议变更:
  [+ 新增] 在 <段落> 追加: "<新规则>"
  [~ 修改] 将 "<旧规则>" 改为 "<新规则>"
  [- 删除] 移除 "<旧规则>"（原因: <...>）

变更后（<M>/15 行）:
  [显示完整预览]

来源: <用户输入 / 会话总结>
```

### Step 4: 用户确认

等待用户明确确认（y/n/调整）。

- 确认 → 执行 Step 5
- 拒绝 → 丢弃。如果原则有价值但不适合 protocol，建议存到 known-issues.md 的 lessons 段
- 调整 → 用户修改措辞或归属段落后重新呈现

**不可静默写入。** 每次修改必须经过用户确认。

### Step 5: 写入

1. 修改 `test/protocol.md`（活跃规则）
2. 在 `test/protocol-changelog.md` 追加变更记录
3. 如果 protocol.md 已被 `@` 注入到 CLAUDE.md，变更下次会话自动生效

### Step 6: 报告

```
protocol.md 已更新（<M>/15 行）
变更记录已写入 protocol-changelog.md
下次会话将自动加载新规则
```

## protocol-changelog.md 格式

```markdown
# Protocol Changelog

记录 test/protocol.md 的每次变更。每条包含时间、操作、内容、来源。

## [<date>] <操作>

- **操作**: add / modify / remove
- **段落**: 通用原则 / 安全 / 触发器
- **内容**: <规则文本>
- **来源**: user-input / session-summary
- **原因**: <为什么加/改/删>

---

## [2026-04-19] init

- **操作**: init
- **段落**: all
- **内容**: 标准版模板生成
- **来源**: /better-test init
- **原因**: 首次初始化
```

## 不要做的事

- ❌ 不要把项目特定信息写入 protocol.md（测试组名、版本号、文件路径 → 去 test-groups.md）
- ❌ 不要在用户未确认的情况下修改 protocol.md
- ❌ 不要直接编辑 protocol-changelog.md 的历史条目（只追加，不修改已有记录）
- ❌ 不要因为"行数快满了"就放弃有价值的新原则 — 先尝试合并/精简现有规则腾出空间

# Update Workflow

基于本次会话中跑测试/写测试/收到反馈的信号，增量更新测试知识。

## 核心原则

Update 不是"回顾并总结"，而是**检测信号并响应**。只有明确信号才触发更新，没有信号就不动。

> Feedback 录入有专门的 `/better-test feedback` 命令，不在本工作流。本工作流处理 **结构性变化**（新组、新映射、新约定、知识修正、覆盖缺口）。

## 信号检测

回顾本次会话，逐项检测以下 5 类信号：

### 信号 1：新增了测试 / 测试组 → 补充 test-groups.md

**检测**：本次会话中是否新写了测试文件、新加了测试组、或在 CI 配置里新增了 test step？

**响应**：在 `test-groups.md` 中追加新组或新项。

```markdown
# 添加到 test-groups.md

## <Group Letter> <Group Name>
- 覆盖范围: <做什么的测试>
- 运行命令: <精确命令>
- 运行条件: <环境变量 / 依赖 / 是否需要真账户>
- 项数: <N>
- 典型耗时: <分钟数>
- 关键字段断言: <举一个 EXPECT_PATTERN 例子>
```

### 信号 2：发现影响映射 → 补充 impact-map.md

**检测**：本次跑测试时，是否发现"改了 X 模块结果 Y 组的测试挂了"？这是没在 impact-map.md 中记录的因果链。

**响应**：在 `impact-map.md` 追加映射，**附验证依据**。

```markdown
# 添加到 impact-map.md

| 关键词 / 路径 | 影响测试组 | 来源 |
|--------------|-----------|------|
| <keyword>    | <groups>  | <verified-on-vX.Y.Z / inferred-from-history / human-report> |
```

来源**必须**写明，不能空。`inferred-from-history` 适用于"过去 3 次 X 改动后 Y 组都挂"这种数据驱动的推断。

### 信号 3：发现 flaky 测试 → 补充 known-issues.md

**检测**：本次跑测试时，是否有项目时而 pass 时而 fail（同条件下不稳定）？

**响应**：在 `known-issues.md` 的"Flaky"段记录。**不能默默忽略 flaky**（red line #5 隐含约束）。

```markdown
# 添加到 known-issues.md（Flaky 段）

| Test ID | 不稳定原因 | 缓解 | 是否阻塞 |
|---------|-----------|------|---------|
| <id>    | <如：网络抖动 / 时序竞争 / 浮点精度> | <如：retry 3 次 / 增加超时> | <yes/no> |
```

如果是阻塞性的 flaky，建议用户跑 `/better-test feedback <id> deferred --note "flaky pending root cause"` 转为正式规则。

### 信号 4：发现新的测试约定 → 补充 protocol.md（谨慎）或 status.md

**检测**：本次会话中是否发现"项目有一致的测试模式"且未在 protocol.md 中？例如：
- "所有 REST 测试都要先 unlock-trade"
- "MCP 测试必须用 tools/call 而非 tools/list"
- "WebSocket 测试要等 5 秒等订阅数据流"

**响应**：

- 如果是**铁律**（违反就出错）→ 提议加入 `protocol.md`，但要先确认 protocol.md 还有空间（≤15 行）。如已满，建议精简或拆分为 protocol-extras.md
- 如果是**经验**（违反不一定出错）→ 写到 `known-issues.md` 的 lessons 段或 `status.md` 的"关键经验"段

### 信号 5：发现覆盖缺口 → 标记到 status.md

**检测**：本次会话中是否实现了新功能或改了重要模块，但没有对应的测试？这是**覆盖缺口**。

**响应**：在 `status.md` 的"覆盖缺口"段标注：

```markdown
# 添加到 status.md

## 覆盖缺口（待补充测试）

| 模块 / 功能 | 引入版本 | 风险 | 建议测试组 |
|------------|---------|------|-----------|
| <如：新加的 unlock-trade scope 检查> | v1.4.27 | <如：错配 scope 不会立即失败而是返回空> | <group letter or new group> |
```

不要把缺口写成"todo 列表" —— 它是**风险提示**，让 strategy 推荐时知道哪里盲区。

## 优先级权重

| 信号来源 | 权重 | 理由 |
|---------|------|------|
| 实际踩坑（意外失败、flaky、缺口暴露） | 最高 | 真实痛苦，确定有用 |
| 新加测试 / 新加组 | 高 | 结构性变化必须同步 |
| 多次共现的影响关系 | 高 | 数据驱动，可信 |
| 单次推测的影响关系 | 中 | 标 `[未验证]` 写入 |
| "应该是这样"的约定 | 不记录 | 等到验证后再写 |

## 更新流程

1. 扫描本次会话的信号（按上述 5 类）
2. 对每个命中的信号，执行对应文件的增量修改
3. 检查 `protocol.md` 是否仍 ≤15 行；超了则精简
4. 调用 status.md 的自动 refresh（参考 strategy-workflow.md 的 status 生成逻辑）
5. git commit message 前缀 `[better-test] update:`
6. 向用户报告：列出每条信号 + 响应了什么

## 不更新的情况

以下情况**不触发 update**：
- 本次会话只跑了已有测试，没有新增/失败/缺口暴露
- 所有发现的知识已在 `.better-work/test/` 中记录过
- 唯一的"新知识"是推测性的且无法标注来源

此时报告："未检测到新信号，测试知识保持不变。"

## update vs feedback 的区别

| 触发场景 | 用什么命令 |
|---------|-----------|
| 开发者答复"这是 not-a-bug" | `/better-test feedback <id> not-a-bug --note ...` |
| 跑测试发现某项 flaky | `/better-test update`（写到 known-issues.md 的 Flaky 段） |
| 改了 X 模块发现 Y 组挂 | `/better-test update`（写到 impact-map.md） |
| 发现某条测试需要新断言才能验证功能 | `/better-test update`（修 test-groups.md 中该项的"关键字段断言"）|

## 不要做的事

- ❌ 不要把 update 当成"扫一遍当前测试状态"—— 那是 strategy 的工作
- ❌ 不要直接修 `feedback-rules.json` 即使你看到它有 bug —— 走 feedback workflow 的撤销机制
- ❌ 不要把推测性影响映射写成"已验证"—— 标 `[未验证]` 是诚实，不是缺陷

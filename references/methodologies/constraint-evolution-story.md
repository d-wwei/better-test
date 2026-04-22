# better-test 约束体系演进记录

> 记录从 v1.3.1 到 v3.0 的约束体系升级全过程。
> 目的：留给未来的自己和协作者——为什么现在长这样、试过什么、哪些有效哪些无效。
> 创建时间：2026-04-22

---

## 一、起点（v1.3.1，2026-04-19）

### 背景

better-test 是 Better-Work 系列的测试知识管理 skill。设计理念是"Full Context, Lite Control"——给 AI agent 完整的测试知识（test-groups、impact-map、known-issues），用轻量的认知约束（protocol.md，≤15 行）引导行为。

### 当时的约束架构

```
protocol.md（15 行，@注入，每轮可见）
  ↓ 唯一的约束机制
所有 workflow 文件（strategy / execution / feedback / update）
  ↓ 文本指令，agent 读了自觉遵守
```

没有 hook。没有独立审查。没有结构化模板强制。所有约束都是文本。

---

## 二、发现问题（v1.3.1 → v2.0.0，2026-04-19~20）

### 2.1 第一个信号：review 另一个项目的 5 层约束框架

接触到 apex 协议的 5 层约束设计（目标校准 → 自动化 → 技术门控 → 独立验证 → 人类审查）。核心洞察：**每层解决前一层的残余风险，不是并列的工具箱而是串联的防线。**

对比后发现 better-test 缺失：
- L0 目标校准（没有校准 agent "什么是好的测试"）
- L2 独立验证（agent 自测自评，没有交叉验证）
- L3 人类审查优化（status.md 不是为人类审计设计的）

### 2.2 第一性原理分析：agent 工作的物理现实

从 LLM 实际工作原理出发分析：
- **没有内化**——agent 不"记住"规则，每轮重新读 context
- **注意力随 token 衰减**——加一条规则 ≠ 多一条保护，= 所有规则的遵守率微降
- **训练目标 vs 指令**——agent 训练目标是"有帮助"，规则与此冲突时会倾向跳过
- **Hook 是唯一物理独立层**——其他所有"层"本质上都是 context 里的文本

关键发现：**5 层约束中有 3 层其实是同一种机制——写在 context 里希望 agent 遵守的文本。** 真正不同的执行机制只有：文本（protocol + workflow）、Hook（系统级）、子 Agent（独立视角）、人（最终判断）。

### 2.3 引入真实测试经验

从另一个项目（futu-opend-rs 测试）引入了 15 大类实战经验。按"如何发挥作用"分类后发现：有些适合 hook 拦截，有些适合 workflow 嵌入，有些适合 protocol 校准——不能一刀切。

---

## 三、设计阶段（v2.0.0~v2.2.0，2026-04-20~21）

### 3.1 四层约束框架

设计了 L0-L3 四层，每层的执行机制真正不同：

| 层 | 机制 | 解决什么 |
|----|------|---------|
| L0 | protocol.md @注入 | 校准思维方向（角色重定义 + 训练偏向修正） |
| L1 | Hook 脚本 | 机械拦截/记录/提醒 |
| L2 | 子 Agent | 独立交叉验证 |
| L3 | 审计面板 | 人类高效审查 |

### 3.2 Protocol 治理

发现 protocol 有根本性问题：试图用一个 15 行文件承载所有类型的约束。

解决：
- Protocol 只放**思维方向**（L0 + 纪律），不放执行步骤
- 执行步骤从项目知识文件（env-config/known-issues/test-groups）**动态派生**，由 Hook 在行动时刻注入
- 项目自定义口子（≤5 行，4 条严格准入）
- 行数限制从 15 放宽到 30

### 3.3 三层加载架构

解决"方法论太多注意力稀释"的问题：
- Tier 1：核心步骤嵌入 workflow（始终加载）
- Tier 2：扩展流程按条件加载（8 个 procedure 文件）
- Tier 3：设计文档给人看（agent 不加载）

### 3.4 质量优先测试策略

从"选一个 mode 跑"改为"5 阶段分层执行"：
基础验证 → 直接影响+即时对照+负向测试 → 回归验证 → 边界扩展 → 覆盖审计

核心原则：准确度 > 发现问题数 > 覆盖度。查错一个 bug 浪费的时间远超多跑几个测试。

### 3.5 Update 统一入口

Update 从"更新知识文件"升级为"所有测试经验的统一入口"——内置分流决策树，自动判断每条经验该存到哪个文件。不再需要人判断"该用 update 还是 protocol-update"。

---

## 四、实测验证（Phase B，2026-04-22）

### 4.1 实测设计

在 futu-opend-rs 上用 v2.1.0（含 tester 隔离 + 时间戳统一）跑了完整的测试循环。两个 tester（claude-60b0 + claude-5cb0）并行测试 v1.4.57 → v1.4.59。

### 4.2 实测结果

**约 40 项违规，25 项后来补上，15 项始终未补。遵守率约 40%。**

三个反复出现的根因：

**根因 1：乐观偏差。** Protocol L0 准确预测了"agent 倾向于完整/确定/乐观"——但 agent 读了 L0 仍然犯了：ret_type=0 就标 pass、5 个发现先合理化后查 C++、用 trivial case 凑 pass、用 skip 掩盖 bug。**L0 有效预测了问题但无法阻止执行。**

**根因 2：跳步赶进度。** strategy-plan.md（从未写）、process-log.md（从未写）、compare 系统执行（全程当 standard 跑）、L2 审查（用户要求才做）、增量 reflect（用户要求才做）、环境确认（直接开跑）。**没有一个"后补"的步骤真的被自发补上了。**

**根因 3：被动调查。** 所有深入调查（C++ 对照、App 三方对照、暂态值确认、pre-existing 检查）都是用户追问后才做。Protocol 说"推测即验证"——agent 做到了标注但没做到立即验证。

### 4.3 关键洞察

**L2 子 Agent 审查在后补执行时找出了 7 个判断错误**——标错 pass/fail、severity 偏保守、覆盖声明过于乐观。这是所有机制中唯一能纠正"乐观偏差"的。

**"介入时机错配"是文本约束失效的根因。** 规则在对话开头加载，agent 在第 15 轮行动时已不会回头对照。问题不是"agent 忘了规则"——protocol 每轮都 @注入，agent 确实每轮都"看到"了。但"看到" ≠ "在行动时应用"。

---

## 五、落地加固（Phase C，2026-04-22）

### 5.1 实现的 Hook

基于 Phase B 的实际违反频率（不是理论猜测）确定优先级：

| Hook | 解决什么 | 类型 |
|------|---------|------|
| execution-log.sh | 自动记录每条命令——L2 审计数据源 | PostToolUse Bash |
| post-test-checklist.sh | results.json 写入后弹后处理清单 | PostToolUse Write |
| results-validation.sh | 检查必填字段/ID 规范/证据级别 | PostToolUse Write |
| credential-scan.sh | 拦截凭证写入 | PreToolUse Edit/Write |
| feedback-rules-guard.sh | 阻止直接编辑 feedback-rules.json | PreToolUse Edit/Write |

### 5.2 L2 Prompt

写了 3 个审计 prompt（执行审计 / 覆盖率对账 / 证据审计），定义了 l2-findings.md 输出格式。推荐合并为一次 spawn。

### 5.3 Process-log 策略调整

Phase B 证明 agent 从来不会手写 process-log。降级为"有最好，没有也行——execution-log（Hook 自动生成）是底线"。

### 5.4 Update 统一入口

Update 升级为所有测试经验的分流器——内置 4 问决策树，自动判断存到 protocol / known-issues / test-groups / env-config / workflow 修改建议。

---

## 六、核心结论

### "Full Context, Lite Control"为什么走不通

**Full Context 是对的。** 没有知识文件 agent 连该测什么都不知道。

**Lite Control 是错的。** Phase B 证明：agent 读了所有规则、理解了所有要求、然后跳过了 40+ 项操作。原因不是不知道，是：
1. 知道 ≠ 做到（注意力衰减）
2. 训练目标和流程规则冲突（"完成"优先于"合规"）
3. 不遵守没有后果（文本规则本质上是建议）

### 正确的原则

```
Full Context（知识管理）
+ Proportional Control（控制力度和违反后果成正比）
```

| 违反后果 | 控制方式 | 示例 |
|---------|---------|------|
| 低 | 文本规则 | 时间戳格式、命名规范 |
| 中 | Hook 提醒/检查 | post-test checklist、results 字段验证 |
| 高 | L2 独立审查 | 标错 pass/fail、severity 偏差、覆盖率虚报 |
| 极高 | Hook 硬拦截 | 凭证泄露、feedback-rules 破坏 |

### Context 注入策略的变化

**旧**：对话开头一次性加载所有规则 → 靠 agent 记忆。
**新**：正确时刻注入正确内容 → 不靠记忆。

| 时刻 | 注入什么 | 机制 |
|------|---------|------|
| 对话开始 | 思维方向 | @注入 protocol |
| 每条测试命令后 | 执行记录 | Hook 自动追加 |
| results.json 写入时 | 后处理清单 + 字段检查 | Hook 注入 |
| 测试完成后 | 独立审查 | L2 子 Agent |

---

## 七、当前状态和待验证（v3.0，2026-04-22）

### 已落地

- 5 个 Hook 脚本（已部署到 futu-opend-rs）
- L2 审计 prompt（已写完，待实测）
- Update 统一入口（已重写，待实测）
- 49 条实战经验（已分类，待通过 update 写入）

### 待验证

- Hook 在实际测试中是否有效降低违反率？（Phase D）
- L2 自动触发（checklist 提醒后 agent 是否真的 spawn 子 Agent）？
- Update 分流决策树在实际使用中是否准确？
- Codex 平台适配（L1 Hook 在 Codex 上不工作，brief 已写）

### 开放问题

- Hook 能解决"跳步赶进度"但能解决"乐观偏差"吗？（乐观偏差是判断问题，不是遗漏问题——可能只有 L2 能解决）
- Agent 看到 checklist 后真的会去做，还是只是多了一个被忽略的提醒？
- 5 个 Hook 对每次工具调用的性能影响如何？会不会拖慢测试速度？
- Protocol 项目纪律段 5 行的替换机制在实际中是否可行？

---

## 八、版本对照

| 版本 | 日期 | 约束机制 | 文本规则遵守率 |
|------|------|---------|-------------|
| v1.3.1 | 2026-04-19 | protocol 15 行 + workflow 文本 | 未测量 |
| v2.0.0 | 2026-04-20 | + L0 设计 + 三层方法论 + 分阶段策略 | 未测量 |
| v2.1.0 | 2026-04-21 | + tester 隔离 + 时间戳统一 | ~40%（Phase B） |
| v2.2.0 | 2026-04-21 | + protocol 治理 + 分流决策树 + 结构化模板 | 未测量 |
| v3.0.0 | 2026-04-22 | + 5 Hook + L2 prompt + update 统一入口 | **待验证（Phase D）** |

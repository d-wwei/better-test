# Codex L1 Hook 适配实施 Brief

> 本文件是给实现者的执行说明。目标不是“给 Codex 单独做一套临时补丁”，而是把 better-test 的 L1 约束层整理成**跨平台可复用、平台适配可扩展**的结构：Claude Code 继续原样可用，Codex 新增可用，后续扩到 Cursor 等平台时不需要推倒重来。

---

## 0. 已确认前提

### 平台定位

- better-test 是**多 agent 共用的 skill**
- 现有 Claude Code 已有 L1 Hook，**不能回退、不能改坏、不能要求 Claude 用户改工作流**
- Codex 现在有原生 Hooks 能力，可作为 Codex 的 L1 主实现路径
- `AGENTS.md` / `CLAUDE.md` / `GEMINI.md` 负责 **L0 protocol 注入**
- L1 hook 是另一层能力，**不要和 protocol 注入混在一起设计**

### 架构前提

L1 的“业务规则”是跨平台的，平台差异主要在**绑定方式**：

1. Hook 在什么事件上触发
2. Hook 输入 JSON 长什么样
3. Hook 如何把 block / warning / additional context 返回给宿主
4. Hook 配置文件放在哪、如何启用

这意味着：

- **优先复用** `hooks/*.sh` 的规则意图
- 如 Claude / Codex 的 Hook I/O 协议不同，允许加一层**薄适配层**
- **不要**因为接 Codex 就把规则逻辑复制成两套长期分叉版本

---

## 1. 当前问题定义

better-test 的四层约束框架中：

| 层 | 机制 | 状态 |
|----|------|------|
| L0 | protocol 注入 | Claude / Codex 都可工作 |
| L1 | Hook 自动拦截 / 记录 / 提醒 | Claude 已有，Codex 待补齐 |
| L2 | 子 Agent 审查 | 平台无关 |
| L3 | 审计面板 | 平台无关 |

当前 Codex 的缺口只在 **L1**。

### 现有 5 个 Hook

| Hook | 文件 | 作用 | 优先级 |
|------|------|------|--------|
| 凭证扫描 | `hooks/credential-scan.sh` | 阻止把凭证写进 `.better-work/test/` | P0 |
| feedback-rules 保护 | `hooks/feedback-rules-guard.sh` | 阻止直接编辑 `feedback-rules.json` | P0 |
| 执行日志记录 | `hooks/execution-log.sh` | 自动记录每条 shell 命令到 `execution-log.md` | P0 |
| 测试完成清单 | `hooks/post-test-checklist.sh` | `results.json` 写入后提醒后处理步骤 | P1 |
| 结果字段检查 | `hooks/results-validation.sh` | 校验 `results.json` 关键字段 | P1 |

### 风险

没有 Codex L1 时：

1. L2 审计缺少 `execution-log.md` 数据源
2. `results.json` 写完后没有后处理提醒，Phase B 已证明这类步骤会被系统性跳过
3. `results.json` 可写入空字段、非标 ID、弱证据 pass
4. `.better-work/test/` 可能被写入凭证
5. `feedback-rules.json` 可被直接手改，破坏 derived-view 约束

---

## 2. 本次任务的目标

把 L1 从“Claude Code 专属配置”升级为“**跨平台约束规则 + 平台绑定层**”。

本次必须交付：

1. **Claude Code 继续保持原有可用性**
2. **Codex 上新增 L1 Hook 适配**
3. **文档中明确区分：shared hook logic / platform binding / installation**
4. **给未来平台（如 Cursor）留下明确扩展点**

---

## 3. 设计原则

### 原则 A：Claude 优先保守

- 现有 `hooks/*.sh` 和 Claude 的 `settings.json` 安装方式必须继续工作
- 不允许为了让 Codex 跑通而改掉 Claude 现有 Hook 的输入假设，除非先抽出共享层并做回归验证

### 原则 B：平台差异收敛到“适配层”

如果 Codex Hook 输入/输出协议与 Claude 不同，推荐拆成：

- `hooks/lib/*.sh` 或类似目录：共享判定逻辑
- `hooks/*.sh`：保留 Claude 入口，尽量不破坏现状
- `hooks/codex/*.sh` 或等价目录：Codex 入口适配层

允许的变化：

- 入口脚本拆分
- JSON 字段映射
- block / warning / reminder 的返回格式适配

不允许的变化：

- 同一条规则在 Claude 和 Codex 维护两份不同业务语义
- 把平台判断散落进每个脚本，导致后续扩平台成本持续上升

### 原则 C：优先原生 Hooks，wrapper 只做降级方案

- Codex 既然已有原生 Hooks，就以原生 Hooks 为主线方案
- wrapper 脚本只能作为**已验证限制下**的降级路径，不能一上来就绕开原生能力

### 原则 D：L0 / L1 分层保持清晰

- `AGENTS.md` 中嵌入的是 protocol，不是 hook 配置
- `references/adapters.md` 需要新增或细化 Codex 的 Hook 绑定说明，但不能把 Hook 描述混成 protocol 注入说明

---

## 4. 建议实施路径

### Step 1: 验证 Codex Hook 绑定能力

需要确认并落地：

1. Codex Hook 的配置文件位置与启用方式
2. `PreToolUse` / `PostToolUse` 是否覆盖本项目 5 个 Hook 所需事件
3. Hook stdin / stdout 协议是否与现有 Claude 脚本兼容
4. 如不兼容，差异点是什么，适配层最小应该长什么样

输出要求：

- 给出**明确结论**，不是“可能可以”
- 若存在平台前提（例如 feature flag、实验开关、平台限制），必须写入文档和验证步骤

### Step 2: 抽象 Hook 结构

目标结构应体现三层：

1. **规则层**：凭证扫描、结果校验、日志记录等业务规则
2. **平台入口层**：Claude / Codex 的 Hook 入口脚本或配置
3. **安装文档层**：不同平台如何启用

最低要求：

- Claude 配置继续指向稳定入口
- Codex 新增自己的稳定入口或配置
- 后续 Cursor 等平台新增时，只需要加平台入口层和安装文档层

### Step 3: 逐个实现 5 个 Hook 的 Codex 绑定

优先级顺序：

1. `execution-log.sh`
2. `credential-scan.sh`
3. `feedback-rules-guard.sh`
4. `results-validation.sh`
5. `post-test-checklist.sh`

原因：

- 前 3 个属于审计可信度和数据安全底线
- 后 2 个属于合规提醒与结构化质量提升

### Step 4: 更新文档

至少更新：

- `references/adapters.md`
- `hooks/README.md`
- 如有必要，新增 Codex hook 配置样例文件或安装说明文件

文档必须回答：

1. Claude 如何安装 / 启用
2. Codex 如何安装 / 启用
3. 两个平台共存时是否互不影响
4. 哪些脚本是共享规则，哪些是平台适配
5. 如果某条 Hook 在某平台受限，降级方案是什么

### Step 5: 做回归和验收

不能只验证 Codex；必须同时验证 Claude 没坏。

---

## 5. 明确交付物

本任务完成时，仓库中应至少出现以下结果中的大部分：

### 代码 / 配置

- Codex 的 Hook 配置文件或可安装模板
- 如有需要，新增 Hook 适配层脚本
- 如有需要，抽出的共享 Hook 逻辑

### 文档

- `references/adapters.md` 中新增 “Codex L1 Hooks” 安装与绑定说明
- `hooks/README.md` 中补齐 Claude / Codex 双平台说明
- 如有平台限制，记录到文档而不是口头说明

### 验证证据

- Claude 回归结果
- Codex 正向用例结果
- Codex 反向拦截 / 提醒用例结果

---

## 6. 验收标准

### 必须满足

1. Claude Code 原有 Hook 安装方式仍可用，行为不变或仅做等价重构
2. Codex 能启用 L1 Hook，不依赖人工记忆步骤才能生效
3. P0 三项在 Codex 上必须成立：
   - 执行日志自动记录
   - 凭证扫描自动拦截
   - `feedback-rules.json` 直接编辑被阻止
4. P1 两项应尽量做到原生实现：
   - `results.json` 写入后字段检查
   - `results.json` 写入后完成清单提醒

### 可接受降级的条件

只有在满足以下全部条件时，P1 才允许降级：

1. 已验证是平台能力限制，而不是实现偷懒
2. 限制已写入 `references/adapters.md`
3. 给出明确 workflow fallback
4. 不影响 Claude 的完整能力

### 不可接受结果

- 只让 Codex 可用，但 Claude 安装方式或行为被破坏
- 为 Codex 复制一套长期独立维护的规则逻辑
- 把 Hook 配置塞进 `AGENTS.md`，导致 L0 / L1 混层
- 文档没写启用步骤，导致别人拉仓库后无法复现

---

## 7. 建议测试矩阵

### Claude 回归

1. 写入 `.better-work/test/` 含假凭证内容 → 被 block
2. 直接编辑 `feedback-rules.json` → 被 block
3. 执行一条 shell 命令 → `execution-log.md` 自动追加
4. 写入 `results.json` 缺字段 → 收到校验提醒
5. 写入 `results.json` → 收到 post-test checklist

### Codex 验证

1. 重复以上 5 条行为，确认 Codex 路径成立
2. 验证 Codex Hook 启用前 / 启用后差异明确
3. 验证 Hook 与现有 skill 调用、`AGENTS.md` protocol 注入互不冲突

### 共存验证

1. 同一 skill 仓库既能给 Claude 用，也能给 Codex 用
2. 文档描述的安装步骤不会让某一平台覆盖另一平台配置

---

## 8. 给未来平台预留的扩展点

本次实现后，结构上应支持未来新增：

- Cursor
- Gemini 的同类生命周期能力
- 其他支持 tool hook / middleware / guardrail 的 agent 平台

为此，当前实现必须遵守：

1. 规则逻辑尽量平台无关
2. 平台差异集中在配置和入口脚本
3. 文档按“平台适配章”独立组织，而不是把所有平台揉成一段
4. 任何新平台都可以复用本次整理出的验证矩阵模板

---

## 9. 参考文件

| 文件 | 用途 |
|------|------|
| `hooks/*.sh` | 现有 L1 Hook 脚本 |
| `hooks/README.md` | Claude Hook 当前安装与测试方式 |
| `references/adapters.md` | 多平台 skill / protocol 适配说明 |
| `code/constraint-framework.md` | 四层约束框架设计背景 |
| `code/phase-b-report.md` | 没有 Hook 时的实际遵守率问题 |
| `references/l2-audit-prompts.md` | L2 审计对 `execution-log.md` 的依赖 |

外部依据：

- OpenAI 官方 Codex Hooks 文档（确认 Codex 原生 Hooks 能力、配置方式与启用前提）

---

## 10. 一句话定义“完成”

完成不是“Codex 也能跑几个脚本”，而是：

> better-test 的 L1 约束层被整理成了**跨平台共享规则 + 平台绑定适配**的结构，Claude Code 保持原样可用，Codex 新增可用，文档和验证矩阵足够让后续扩到更多 agent 平台。

# Platform Adapters

把 `.better-work/test/` 知识注入到不同 agent 平台。

## 设计原则

- `.better-work/test/` 是测试知识唯一信源
- adapters 是薄胶水，只引用不复制（除非平台不支持引用）
- 与 better-code 的注入并存：注入逻辑应**追加**而非覆盖现有引用
- 团队成员各用不同 agent 平台时，从同一套文件读取

---

## Claude Code

注入方式：项目 CLAUDE.md 中 `@` 引用。

### 应注入的文件

```
@.better-work/test/protocol.md            ← always-on，测试认知约束
```

如果 `.better-work/shared/index.md` 已存在（better-code 创建）但 CLAUDE.md 还没引用 → 一并补上 `@.better-work/shared/index.md`。

### 注入步骤

1. 检查项目根 `CLAUDE.md` 是否存在
2. 如果存在 → 检查是否已含 `@.better-work/test/protocol.md`
3. 缺少 → 在文件末尾追加（不要覆盖其他内容）
4. 如果 CLAUDE.md 不存在 → 创建，含必要的 `@` 引用
5. 如果 `.better-work/code/protocol.md` 存在但 CLAUDE.md 没引用 → 提示用户："better-code 的 protocol 也未注入，要一并加吗？"（不擅自加，避免越权）

### 按需读取的文件

Agent 在需要时通过 Read 工具读：
- `.better-work/test/test-groups.md` — strategy 时读
- `.better-work/test/impact-map.md` — strategy 时读
- `.better-work/test/known-issues.md` — strategy / feedback 时读
- `.better-work/test/status.md` — 每次会话开始可主动读一次
- `.better-work/test/progress.md` — resume 时读
- `.better-work/test/history/` — 调研历史时读

`@` 引用只用于 protocol.md（自动加载，约束始终生效）。其他按需，避免污染对话。

---

## Cursor

Cursor 不支持 `@` 外部引用，需把内容嵌入 `.cursor/rules/`。

### 生成 `.cursor/rules/better-test.mdc`

```markdown
---
description: "Test discipline protocol — loaded for all tasks involving testing"
alwaysApply: true
---

[protocol.md 完整内容嵌入此处]

## 知识文件位置（agent 按需读）
- .better-work/test/test-groups.md — 测试组定义和运行命令
- .better-work/test/impact-map.md — 变更→测试组映射
- .better-work/test/known-issues.md — 已知问题
- .better-work/test/status.md — 当前测试状态
- .better-work/test/progress.md — 上次进度
```

### 同步策略

由于 Cursor 是嵌入而非引用，每次 `update` 修改 protocol.md 后，需同步重生成 `.cursor/rules/better-test.mdc`。

如果 better-code 也装了，会有 `.cursor/rules/better-code.mdc`。两者**独立文件**，不要合并（独立 skill 独立维护）。

---

## Gemini CLI

支持 `@` 引用，逻辑与 Claude Code 相同。

### 注入步骤

1. 找 GEMINI.md（项目根 或 `~/.gemini/GEMINI.md`）
2. 追加 `@.better-work/test/protocol.md`

---

## Codex CLI / OpenCode / OpenClaw

不支持 `@` 引用，需嵌入 AGENTS.md。

### 注入步骤

1. 找配置文件：
   - `~/.codex/AGENTS.md`
   - `~/.config/opencode/AGENTS.md`
   - `~/.openclaw/workspace/AGENTS.md`
2. 在文件中嵌入 protocol.md 内容，用标记包裹便于更新替换：

```markdown
<!-- BETTER-TEST:BEGIN -->
[protocol.md 内容]

知识文件位置（按需读）:
- .better-work/test/test-groups.md
- .better-work/test/impact-map.md
- .better-work/test/known-issues.md
- .better-work/test/status.md
<!-- BETTER-TEST:END -->
```

下次 update 时，定位 BEGIN/END 段整体替换。

---

## 通用 Agent（无特定平台）

提供通用指引：

1. 找该 agent 的系统提示词或启动配置
2. 加入：
   > "在涉及测试的任务前，先读取 `.better-work/test/protocol.md`。
   > 跑测试前先读 `.better-work/test/status.md` 了解上次状态。
   > 推荐策略时读 `.better-work/test/impact-map.md` 和 `.better-work/test/test-groups.md`。"
3. 或直接把 protocol.md 内容嵌入系统提示词

---

## 与 better-code adapter 的并存

如果项目同时装了 better-code 和 better-test，注入到 CLAUDE.md / GEMINI.md / AGENTS.md 时会有多条引用。**不要合并，分别独立维护**：

```
@.better-work/shared/index.md         # 由 better-code 创建/更新
@.better-work/code/protocol.md        # 由 better-code 创建/更新
@.better-work/test/protocol.md        # 由 better-test 创建/更新
```

每条引用对应一个独立的 skill，独立 update，独立失效。

如果 better-test 看到 CLAUDE.md 中已经有 `@.better-work/test/protocol.md` → 不要重复添加，跳过即可（幂等）。

如果 CLAUDE.md 中存在旧的 `@.project-memory/cognitive-protocol.md` 引用（来自旧版 project-memory skill）→ **不要擅自删除**，提示用户："检测到旧版 project-memory 的引用，建议手动迁移到 .better-work/code/protocol.md"。

---

## 注入逻辑（init 内置，无独立 inject 命令）

注入是 `/better-test init` 的内置最后一步，不暴露为独立命令（保持 SKILL.md commands 表干净）。如需重新注入（如换平台、CLAUDE.md 被清空、新增了平台配置）：

- **首选**：重跑 `/better-test init`（幂等：已存在的 protocol.md 不会被覆盖，已存在的 CLAUDE.md 引用不会被重复添加）
- **手动**：直接编辑 CLAUDE.md / GEMINI.md / AGENTS.md，按本文档的注入步骤添加引用或嵌入内容

init 的注入步骤（agent 内部执行）：

1. 验证 `.better-work/test/protocol.md` 存在
2. 检测当前平台（项目根有 CLAUDE.md → claude；有 .cursor/ → cursor；等）
3. 选对应适配策略（本文档前面各小节）
4. 执行注入（追加，不覆盖）
5. 报告注入位置

支持平台：`claude` / `cursor` / `gemini` / `codex` / `opencode` / `openclaw`。多平台同时存在则全部注入。

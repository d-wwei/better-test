# Platform Adapters

把 `.better-work/test/` 知识注入到不同 agent 平台。

## 设计原则

- `.better-work/test/` 是测试知识唯一信源
- adapters 是薄胶水，只引用不复制（除非平台不支持引用）
- 与 better-code 的注入并存：注入逻辑应**追加**而非覆盖现有引用
- 团队成员各用不同 agent 平台时，从同一套文件读取

## 分层架构

所有平台至少有两层：

| 层 | 作用 | 机制 |
|----|------|------|
| **Layer 1: Skill 注册** | 让 agent 能执行 skill 命令（init/strategy/feedback 等） | symlink 到平台 skills 目录 |
| **Layer 2: Protocol 注入** | 让测试纪律在非 skill 触发时也生效（always-on 认知约束） | 在项目配置中引用/嵌入 protocol.md |

Codex 额外有可选的第三层：

| 层 | 作用 | 机制 |
|----|------|------|
| **Layer 3: Hooks 安装** | 在工具生命周期里自动执行 L1 约束 | 项目 `.codex/hooks.json` |

不支持 skill 系统的平台（Cursor、Gemini、OpenCode、OpenClaw）只做 Layer 2。Claude 当前仍是 Layer 1 + Layer 2；Codex 是 Layer 1 + Layer 2 + 可选 Layer 3。

---

## 统一安装器

`install.sh`（项目根目录）自动检测本机已安装的 agent 平台，创建 symlink 完成 Layer 1 注册。

```bash
# 安装（检测所有平台，创建 symlink）
./install.sh

# 查看当前状态
./install.sh status

# 卸载（只移除本脚本创建的 symlink）
./install.sh uninstall
```

安装器**只做 skill 注册**（symlink），不修改任何项目配置文件（CLAUDE.md / AGENTS.md / GEMINI.md），也不安装 hooks。项目级 protocol 注入由 `/better-test init` 的 Step 4 完成；Codex Layer 3 hooks 由 `hooks/install-codex-hooks.sh` 单独处理。

---

## Claude Code

注入方式：项目 CLAUDE.md 中 `@` 引用。

### 应注入的文件

```
@.better-work/shared/index.md                          ← 项目知识入口
@~/.claude/skills/better-test/protocol-base.md         ← skill 级通用原则（L0 + 思维纪律），随 skill 自动更新
@.better-work/test/protocol.md                          ← 项目级扩展（安全纪律 + 项目纪律）
```

### 注入步骤

1. 检查项目根 `CLAUDE.md` 是否存在；不存在则创建
2. 检查是否已含 `@.better-work/shared/index.md`；缺少则追加
3. 检查是否已含 `@~/.claude/skills/better-test/protocol-base.md`；缺少则追加（**新增**）
3. 检查是否已含 `@.better-work/test/protocol.md`；缺少则追加
4. 如果 `.better-work/code/protocol.md` 存在但 CLAUDE.md 没引用 → 提示用户："better-code 的 protocol 也未注入，要一并加吗？"（不擅自加，避免越权）

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

## Codex CLI

Codex 支持原生 skill 系统，但 better-test 在 Codex 上现在是**三层安装**：

1. Layer 1: skill 注册
2. Layer 2: AGENTS.md protocol 注入
3. Layer 3: `.codex/hooks.json` 的 L1 hooks 安装

注意：Layer 3 当前安装 8 条 Codex-active hooks：`execution-log`、`credential-scan`、`feedback-rules-guard`、`derived-view-guard`、`session-write-guard`、`post-test-checklist`、`results-validation`、`registration-gate`。其中 `execution-log` 通过 `PostToolUse/Bash` 记录执行日志；其余 7 条已在 `codex-cli 0.125.0` 上完成双路径适配：Bash 写入继续走 `PreToolUse/PostToolUse + Bash`，built-in 文件编辑则走 `matcher: "Write"`，但真实 payload 是 `tool_name: "apply_patch"` + patch command，而不是 Claude 风格的 `file_path/content`。这也是为什么 Codex 入口层必须保留平台适配，不能直接复用 Claude 的原始 `Write` 入口。`credential-scan` 在 Bash 路径上仍只覆盖命令文本里显式嵌入的 secret，不覆盖外部文件搬运。当前 payload 还没有暴露 shell exit code，所以 Codex 日志会写 `EXIT: ?`。

### Layer 1: Skill 注册

better-test 的 SKILL.md + references/ 在 Codex 上原生可用，无需任何格式修改。

**自动安装（推荐）：**

```bash
./install.sh
```

**手动安装：**

```bash
# 标准路径（Codex ≥0.120）
ln -s /path/to/better-test ~/.agents/skills/better-test

# 旧路径（仍支持）
ln -s /path/to/better-test ~/.codex/skills/better-test
```

安装后 Codex 自动发现 skill。验证：

```bash
codex exec --full-auto "List all available skills."
# 应出现：better-test: Manage persistent testing knowledge...
```

**调用方式：** 在 prompt 中写 `$better-test`（Codex 用 `$` 前缀触发 skill，不同于 Claude Code 的 `/`）。也支持隐式触发——Codex 会根据 SKILL.md description 自动判断是否激活。

### Layer 2: Protocol 注入（项目级）

Skill 注册让 Codex 能执行命令，但 protocol.md 的认知约束需要 always-on。在**项目** AGENTS.md 中嵌入（由 `/better-test init` Step 4 自动完成，也可手动）：

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

### agents/openai.yaml

Codex 旁载文件，已包含在 skill 目录中（`agents/openai.yaml`）。提供 UI metadata 和调用策略。Claude Code 忽略此文件。

### Layer 3: Codex hooks 安装（项目级）

`install.sh` 不负责 Codex hooks。需要单独运行：

```bash
# 安装到当前项目的 .codex/hooks.json
./hooks/install-codex-hooks.sh install

# 查看状态
./hooks/install-codex-hooks.sh status

# 卸载 better-test 自己管理的 Codex hooks
./hooks/install-codex-hooks.sh uninstall
```

行为约束：

- 默认安装到项目 `.codex/hooks.json`
- 默认只检查 `~/.codex/config.toml` 里的 `codex_hooks = true`
- 若未启用，会报错退出
- 只有显式传 `--enable-feature-flag` 时，才会修改用户 `~/.codex/config.toml`
- 安装器只读取 `hooks/registry.json` 中 `platforms.codex.status == active` 的条目
- 真实运行时链路可用 `./hooks/test-codex-runtime.sh` 复验

### 注意事项

- **AGENTS.md 大小限制**：Codex 默认 32 KiB 组合上限（`project_doc_max_bytes`）。protocol.md（≤15 行）远在限制内。如项目 AGENTS.md 已很大，可通过 `~/.codex/config.toml` 调高上限。
- **无 `@file` 引用**：AGENTS.md 不支持 Claude Code 的 `@` 语法，必须嵌入内容。但 skill 的 references/ 可以在运行时通过 `cat` 按需读取（Codex 的 shell_tool 支持）。
- **Hooks 现状**：当前 better-test 在 Codex 上原生落地的是完整 8 条 L1 hooks。`execution-log` 仍是 `PostToolUse/Bash` 专用；其余 7 条同时覆盖 Bash 写路径和 built-in `apply_patch` 写路径。如果后续 registry 新增 active Codex hook，重新跑安装器即可；不需要整套 skill 重新适配。只有当 Codex runtime 再次改变 payload 形状或 matcher 触发规则时，才需要增量更新对应入口和 smoke。

---

## OpenCode / OpenClaw

不支持原生 skill 系统，只做 Layer 2（protocol 嵌入）。

### 注入步骤

1. 找配置文件：
   - `~/.config/opencode/AGENTS.md`
   - `~/.openclaw/workspace/AGENTS.md`
2. 嵌入 protocol.md 内容，用标记包裹便于更新替换：

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

Claude Code 示例（`@` 引用）：
```
@.better-work/shared/index.md         # 由 better-code 创建/更新
@.better-work/code/protocol.md        # 由 better-code 创建/更新
@.better-work/test/protocol.md        # 由 better-test 创建/更新
```

Codex 示例（内容嵌入，各自 BEGIN/END 段）：
```markdown
<!-- BETTER-CODE:BEGIN -->
[code/protocol.md 内容]
<!-- BETTER-CODE:END -->

<!-- BETTER-TEST:BEGIN -->
[test/protocol.md 内容]
<!-- BETTER-TEST:END -->
```

每条引用/嵌入段对应一个独立的 skill，独立 update，独立失效。

幂等规则：
- Claude Code：CLAUDE.md 已有 `@.better-work/test/protocol.md` → 跳过
- Codex：AGENTS.md 已有 `<!-- BETTER-TEST:BEGIN -->` → 定位 BEGIN/END 整体替换（而非重复添加）

如果 CLAUDE.md 中存在旧的 `@.project-memory/cognitive-protocol.md` 引用（来自旧版 project-memory skill）→ **不要擅自删除**，提示用户："检测到旧版 project-memory 的引用，建议手动迁移到 .better-work/code/protocol.md"。

---

## 注入逻辑（init 内置，无独立 inject 命令）

注入是 `/better-test init` 的内置最后一步（Layer 2），不暴露为独立命令。Layer 1（skill 注册）由 `install.sh` 或手动 symlink 完成，与 init 无关。

如需重新注入（如换平台、CLAUDE.md 被清空、新增了平台配置）：

- **首选**：重跑 `/better-test init`（幂等：已存在的 protocol.md 不会被覆盖，已存在的引用/嵌入不会被重复添加）
- **手动**：直接编辑 CLAUDE.md / GEMINI.md / AGENTS.md，按本文档的注入步骤添加引用或嵌入内容

init 的注入步骤（agent 内部执行）：

1. 验证 `.better-work/test/protocol.md` 存在
2. 检测当前平台（项目根有 CLAUDE.md → claude；有 .cursor/ → cursor；有 AGENTS.md 或 `.codex/` → codex；等）
3. 选对应适配策略（本文档前面各小节）：
   - Claude Code → `@` 引用追加到 CLAUDE.md
   - Codex → protocol.md 内容嵌入项目 AGENTS.md（BEGIN/END 标记）
   - Gemini → `@` 引用追加到 GEMINI.md
   - Cursor → 生成 `.cursor/rules/better-test.mdc`
   - OpenCode / OpenClaw → protocol.md 内容嵌入对应 AGENTS.md
4. 执行注入（追加/替换，不覆盖其他内容）
5. 报告注入位置

支持平台：`claude` / `cursor` / `gemini` / `codex` / `opencode` / `openclaw`。多平台同时存在则全部注入。

### Skill 发现路径汇总

| 平台 | 路径 | 备注 |
|------|------|------|
| Claude Code | `~/.claude/skills/better-test/` | 用户级 |
| Codex（标准） | `~/.agents/skills/better-test/` | 跨平台标准路径 |
| Codex（旧） | `~/.codex/skills/better-test/` | deprecated 但仍有效 |
| Codex（仓库级） | `$REPO/.agents/skills/better-test/` | 最高优先级，团队共享 |

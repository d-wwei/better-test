# Codex L1 Hook Adaptation Brief

> 目标：在不破坏 Claude Code 现有可用性的前提下，把 better-test 当前已验证的 Codex L1 落实为可维护方案，并为后续增量扩展保留统一入口。

---

## 1. 现状重置

当前仓库的真实基线已经不是“Claude-only，等待整包迁移”，而是：

1. `protocol-base.md` + 项目级 `protocol.md` 已拆分
2. `hooks/registry.json` 已是 hook 清单与平台状态的单一信源
3. Claude 侧 `hooks/gate.sh` + `hooks/*.sh` 仍是生产路径
4. Codex 侧已完成项目级 `.codex/hooks.json` 安装器、共享 rule 层、runtime smoke 和回归脚本

因此这轮工作的重点不是再造架构，而是让实现、注册表、安装器、测试和文档完全对齐。

---

## 2. 官方边界与仓库决策

OpenAI 官方文档已给出会直接约束实现的边界：

1. Codex hooks 是实验能力，需要开启 `codex_hooks` feature flag
2. Codex 会从激活配置层旁边发现 `hooks.json`，常用位置是 `~/.codex/hooks.json` 和 `<repo>/.codex/hooks.json`，多个文件会叠加执行
3. AGENTS.md、skills、hooks 是不同的定制层
4. CLI 支持用 `--enable` 和 `--config` 做单次配置覆盖

官方来源：

- Hooks: <https://developers.openai.com/codex/hooks>
- Skills: <https://developers.openai.com/codex/skills>
- AGENTS.md: <https://developers.openai.com/codex/guides/agents-md>
- Config basics: <https://developers.openai.com/codex/config-basic>
- Advanced configuration: <https://developers.openai.com/codex/config-advanced>

基于这些边界，本仓库采用下面的分层决策：

- L0: AGENTS.md / skill 文档
- L1: `.codex/hooks.json`
- `install.sh` 只做 skill 注册，不顺手安装 hooks
- Codex hooks 默认走项目级安装，不默认污染全局

注意：官方文档能支持上面 4 条“配置与分层”事实，但**不能直接推出**哪些 matcher 在当前 `codex-cli` 版本可用。具体回调边界必须以 runtime spike 为准。

---

## 3. 当前已落地范围

`hooks/registry.json` 是唯一可信名单。当前 Codex 侧已实装并实测的 active hooks 一共有 8 条：

- `execution-log`
- `credential-scan`
- `feedback-rules-guard`
- `post-test-checklist`
- `results-validation`
- `derived-view-guard`
- `registration-gate`
- `session-write-guard`

它们的运行时语义分别是：

1. `execution-log`
   - `PostToolUse/Bash`
   - 真实记录 Bash 命令和输出到 `execution-log.md`
2. `credential-scan`
   - `PreToolUse/Bash`
   - 只拦截 Bash 命令中显式嵌入 credential-like literal 且目标写入 `.better-work/test/` 的场景
3. `feedback-rules-guard`
   - `PreToolUse/Bash`
   - 只拦截 Bash 命令中能静态提取出写目标、且目标命中受保护 `feedback-rules.json` 的场景
4. `post-test-checklist`
   - `PostToolUse/Bash`
   - 对 Bash 命令提取出的写目标做后置判断；命中 `results.json` 时向模型注入 post-completion checklist advisory
5. `results-validation`
   - `PostToolUse/Bash`
   - 对 Bash 命令提取出的写目标做后置判断；命中 `results.json` 时回读文件内容并向模型注入 validation advisory
6. `derived-view-guard`
   - `PreToolUse/Bash`
   - 只拦截 Bash 命令中能静态提取出写目标、且目标命中受保护派生视图文件的场景
7. `registration-gate`
   - `PostToolUse/Bash`
   - 对 Bash 命令提取出的写目标做后置判断；命中 `strategy-plan.md` 时检查注册材料并向模型注入 advisory
8. `session-write-guard`
   - `PreToolUse/Bash`
   - 只拦截 Bash 命令中能静态提取出写目标、且目标落入其他 tester `run-*` 目录的场景

当前实现没有再把现有 8 条 hook 留在 `planned`，但 runtime 证据仍明确给出下面这些能力边界：

1. 项目级 `.codex/hooks.json` 会被 Codex 读取
2. `PostToolUse/Bash` 会回调
3. `PreToolUse/Bash` 的 `exit 2` 会阻断命令
4. `PostToolUse/Bash` 的 advisory `additionalContext` 当前对模型可见
5. `PostToolUse/Bash` 的非零 hook 仍会执行，但不会让 Codex 命令路径失败；stderr 暴露也不应视作稳定契约
6. 当前 `codex-cli 0.125.0` payload 仍未暴露 shell exit code，所以 Codex 日志里的 `EXIT` 只能记成 `?`
7. `matcher: "Write"` 已在 built-in `file_change` / `apply_patch` 上被 runtime spike 证实会触发
8. 但 Codex native Write payload 不是 Claude 风格的 `tool_name: "Write"` + `file_path/content`，而是 `tool_name: "apply_patch"` + patch command

因此，当前方案不是把 Claude 的 `Write/Edit` 语义硬套给 Codex，而是在 Codex 侧保留一层 `apply_patch` 适配：7 条非 execution-log hooks 同时覆盖 Bash 写路径和 native Write 路径。

---

## 4. 已形成的实现结构

```text
hooks/
├── registry.json
├── gate.sh
├── execution-log.sh
├── credential-scan.sh
├── feedback-rules-guard.sh
├── post-test-checklist.sh
├── results-validation.sh
├── derived-view-guard.sh
├── registration-gate.sh
├── session-write-guard.sh
├── codex/
│   ├── execution-log.sh
│   ├── credential-scan.sh
│   ├── feedback-rules-guard.sh
│   ├── post-test-checklist.sh
│   ├── results-validation.sh
│   ├── derived-view-guard.sh
│   ├── registration-gate.sh
│   └── session-write-guard.sh
├── lib/
│   ├── common.sh
│   └── rules/
│       ├── execution-log.sh
│       ├── credential-scan.sh
│       ├── feedback-rules-guard.sh
│       ├── post-test-checklist.sh
│       ├── results-validation.sh
│       ├── derived-view-guard.sh
│       ├── registration-gate.sh
│       └── session-write-guard.sh
├── fixtures/
│   ├── claude/
│   └── codex/
├── install-codex-hooks.sh
├── test-execution-log-parity.sh
├── test-codex-hooks.sh
├── test-codex-bash-guards.sh
├── test-codex-post-bash-advisories.sh
└── test-codex-runtime.sh
```

设计含义：

1. Claude 入口保留原路径，不回退
2. Codex 入口只做 payload 解析和平台适配
3. 共享业务逻辑收敛到 `hooks/lib/rules/*.sh`
4. 安装器只从注册表读 active Codex 条目
5. 新增 hook 时优先做 registry + shared rule + 平台入口，而不是再做一套平台专用实现

---

## 5. 安装模型

Codex L1 当前采用项目级安装：

- 默认目标：`<project>/.codex/hooks.json`
- 默认行为：只检查 `~/.codex/config.toml` 或 `$CODEX_HOME/config.toml` 是否启用 `codex_hooks`
- 若未启用：安装器报错退出
- 只有显式传 `--enable-feature-flag` 时，才允许修改用户配置

安装器职责：

1. 从 `hooks/registry.json` 读取 `platforms.codex.status == "active"` 的条目
2. 对 active 条目校验 `rule_path` 和 `entrypoint` 都存在
3. 安装 / 卸载时保留项目里无关的第三方 hook 配置
4. 仅管理 `better-test:` 前缀或落在 `hooks/codex/` 下的条目

这意味着以后再增加 hook，不需要“重做一轮 Codex 适配”。只要平台能力已验证，按注册表增量推进即可。

---

## 6. 本轮实现要求

必须做到：

1. Claude 现有 hook 行为不回退
2. Codex 当前 active 8 hook 都能通过安装器落到项目 `.codex/hooks.json`
3. `registry.json` 是安装器唯一来源
4. 文档明确写出 8 条 active hook 的真实触发条件
5. `credential-scan`、`feedback-rules-guard`、`derived-view-guard` 和 `session-write-guard` 必须明确标注为“Bash + native Write 双路径覆盖”，且说明 Codex native Write 的真实 payload 是 `apply_patch`
6. `post-test-checklist`、`results-validation` 与 `registration-gate` 必须明确标注为“`PostToolUse/Bash` + `PostToolUse/Write` 双路径 advisory”，而不是 Bash fallback only
7. runtime smoke 必须锁定 native `Write` 已生效这一事实，而不是继续把它当成未验证能力

不允许出现：

1. 改完后只有 Codex 能用、Claude 回退
2. 为 Codex 复制一套长期独立维护的业务逻辑
3. 默认写入 `~/.codex/hooks.json`
4. 默认修改全局 feature flag
5. 把 Claude 的 `Write/Edit` 路径表述成 Codex 已支持

---

## 7. 回归门禁

当前仓库需要长期保留 5 组门禁：

1. `hooks/test-execution-log-parity.sh`
   - 校验 Claude direct / Claude gate / Codex direct 三路径的 `execution-log` 文件副作用一致
2. `hooks/test-codex-hooks.sh`
   - 校验安装器只读注册表、保留第三方 hooks、支持卸载
3. `hooks/test-codex-bash-guards.sh`
   - 校验四个 Bash guard 的本地写目标提取与阻断语义
4. `hooks/test-codex-post-bash-advisories.sh`
   - 校验三条 `PostToolUse/Bash` advisory hook 的本地输出语义和安装器落点
5. `hooks/test-codex-write-hooks.sh`
   - 校验 Codex native `Write` (`tool_name: apply_patch`) 路径下 4 个 guard + 3 个 advisory 的本地输出语义和安装器落点
6. `hooks/test-codex-runtime.sh`
   - 用真实 `codex exec` 锁定当前运行时基线：
   - 项目 hooks.json 生效
   - `PostToolUse/Bash` 生效
   - `PreToolUse/Bash` 阻断生效
   - `PostToolUse/Bash` additionalContext 对模型可见
   - native `PreToolUse/Write` 阻断生效
   - native `PostToolUse/Write` advisory 对模型可见
   - `credential-scan` 能拦截显式嵌入的 inline secret
   - `post-test-checklist` / `results-validation` / `registration-gate` 的 advisory 可被模型感知
   - `session-write-guard` 能放行 own run、阻断 cross-tester run
   - `PostToolUse/Bash` 非零 hook 仍执行，但不让命令路径失败
   - Codex native Write 仍以 `tool_name: apply_patch` 暴露，而不是 Claude 风格 `file_path/content`

只要 `codex-cli` 升级，上面第 5 条就必须重跑一次。

---

## 8. 本轮结论

当前 Codex 适配已经从“只做 execution-log 的一期”推进到“8 条 runtime-verified hook 的可维护基线”：

1. `execution-log` 已在 Codex 上真实落地
2. `credential-scan`、`feedback-rules-guard`、`derived-view-guard` 与 `session-write-guard` 已以 Bash + native Write 双路径阻断的形式真实落地
3. `post-test-checklist`、`results-validation` 与 `registration-gate` 已以 `PostToolUse/Bash` + `PostToolUse/Write` 双路径 advisory 真实落地
4. native `Write` matcher 已被本地 runtime 观测到，但需要 Codex 专用 `apply_patch` 适配层，不能把 Claude 原始入口直接照搬
5. 以后扩展优先走“注册表增量 + shared rule + runtime spike”，而不是重做整套适配

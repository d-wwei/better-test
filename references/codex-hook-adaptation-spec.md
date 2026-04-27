# Codex L1 Hook Adaptation Spec

> 关联文档：`references/codex-hook-adaptation-brief.md`
>
> 这份 spec 定义当前仓库已经落地并需要持续维护的 Codex L1：8 条 runtime-verified active hooks、共享 rule 层、项目级安装器、回归样例和 runtime smoke。

---

## 1. 交付范围

### 1.1 当前必须存在的交付物

1. `hooks/codex/execution-log.sh`
2. `hooks/codex/credential-scan.sh`
3. `hooks/codex/feedback-rules-guard.sh`
4. `hooks/codex/post-test-checklist.sh`
5. `hooks/codex/results-validation.sh`
6. `hooks/codex/derived-view-guard.sh`
7. `hooks/codex/registration-gate.sh`
8. `hooks/codex/session-write-guard.sh`
9. `hooks/lib/common.sh`
10. `hooks/lib/rules/execution-log.sh`
11. `hooks/lib/rules/credential-scan.sh`
12. `hooks/lib/rules/feedback-rules-guard.sh`
13. `hooks/lib/rules/post-test-checklist.sh`
14. `hooks/lib/rules/results-validation.sh`
15. `hooks/lib/rules/derived-view-guard.sh`
16. `hooks/lib/rules/registration-gate.sh`
17. `hooks/lib/rules/session-write-guard.sh`
18. `hooks/install-codex-hooks.sh`
19. `hooks/fixtures/codex/post-bash.json`
20. `hooks/fixtures/claude/post-bash.json`
21. `hooks/test-codex-hooks.sh`
22. `hooks/test-codex-bash-guards.sh`
23. `hooks/test-codex-post-bash-advisories.sh`
24. `hooks/test-codex-write-hooks.sh`
25. `hooks/test-execution-log-parity.sh`
26. `hooks/test-codex-runtime.sh`
27. `hooks/README.md`、`references/adapters.md`、本 spec / brief 的同步更新

### 1.2 当前 active 基线

当前 Codex active：

- `execution-log`
- `credential-scan`
- `feedback-rules-guard`
- `post-test-checklist`
- `results-validation`
- `derived-view-guard`
- `registration-gate`
- `session-write-guard`

要求：

1. `registry.json` 中 active 状态必须与真实实现一致
2. 安装器只安装 `platforms.codex.status == "active"` 的条目
3. 文档必须明确写出四个 guard 在 Codex 上同时覆盖 Bash 写意图和 native `Write(apply_patch)` 两条路径
4. 文档必须明确写出三个 post-write advisory 在 Codex 上同时覆盖 `PostToolUse/Bash` 和 `PostToolUse/Write`
5. runtime spike 必须持续验证 native `Write` 的真实 payload 形状，而不是把 Claude 的 `file_path/content` 契约直接套到 Codex 上

---

## 2. 官方边界

可以直接依赖的官方事实：

1. Hooks 是实验能力，需要 `codex_hooks` feature flag
2. `hooks.json` 可以跟随配置层被发现，常用位置是 `~/.codex/hooks.json` 和 `<repo>/.codex/hooks.json`
3. 多个 `hooks.json` 会叠加执行，不是互相覆盖
4. AGENTS.md、skills、hooks 是不同的定制层
5. CLI 支持 `--enable` 和 `--config` 做单次配置覆盖

来源：

- <https://developers.openai.com/codex/hooks>
- <https://developers.openai.com/codex/skills>
- <https://developers.openai.com/codex/guides/agents-md>
- <https://developers.openai.com/codex/config-basic>
- <https://developers.openai.com/codex/config-advanced>

不能直接从官方文档推出、必须靠 runtime spike 证明的内容：

1. 哪些 `matcher` 在当前 `codex-cli` 版本上真的会触发
2. `file_change` 与 `Write/Edit` 的映射关系
3. `tool_response` payload 里是否包含 shell exit code
4. built-in 文件编辑触发 `Write` 后，hook payload 是否继续保持 `tool_name: "apply_patch"` + patch command 这一形状

本 spec 同时声明一条仓库内约束：

- better-test 的 Codex L1 默认安装到项目 `.codex/hooks.json`

这是仓库设计选择，不是官方默认行为。

---

## 3. 文件结构

本次实现后，最小结构应为：

```text
hooks/
├── execution-log.sh
├── credential-scan.sh
├── feedback-rules-guard.sh
├── post-test-checklist.sh
├── results-validation.sh
├── derived-view-guard.sh
├── registration-gate.sh
├── session-write-guard.sh
├── registry.json
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
├── test-codex-bash-guards.sh
├── test-codex-post-bash-advisories.sh
├── test-codex-hooks.sh
├── test-codex-runtime.sh
└── test-execution-log-parity.sh
```

说明：

- `hooks/*.sh` 继续是 Claude 稳定入口
- `hooks/codex/*.sh` 只负责 Codex 输入解析
- 真正的业务逻辑只保留一份，在 `hooks/lib/rules/*.sh`

---

## 4. 注册表约束

`hooks/registry.json` 是安装器唯一的数据源。

安装器读取规则：

1. 只读取 `platforms.codex.status == "active"` 的条目
2. 对每个 active 条目同时校验：
   - `rule_path`
   - `platforms.codex.entrypoint`
3. 任一 active 条目缺文件时，安装器必须 fail-closed：
   - 不写入新的 hooks 配置
   - 返回非 0
   - 明确列出缺失项

以后新增 Codex hook 的固定顺序：

1. 先改 `hooks/registry.json`
2. 再补 shared rule / entrypoint
3. 再让安装器自然读到它
4. 再补 fixture / 测试
5. 最后更新文档

只要 hook 列表和语义没变，就不需要“重新做一轮 Codex 适配”；只需要按注册表增量扩展。

---

## 5. 执行契约

### 5.1 `hooks/lib/common.sh`

至少提供：

1. `.better-work/test/` 根目录解析
2. `.better-work` symlink 解析
3. `.active-sessions/<pid>.json` 查找
4. `execution-log.md` 目标路径解析
5. Bash 写目标提取辅助函数

要求：

- 复用 Claude 当前项目检测语义
- Codex 入口不要复制一份检测逻辑
- Bash 写目标提取仅做静态、保守识别；宁可少拦截，也不允许凭空扩张语义

### 5.2 `hooks/lib/rules/execution-log.sh`

只负责共享业务逻辑：

1. 创建 `execution-log.md` 头部
2. 追加 Bash 命令和 exit code
3. 按当前行为截断 stdout
4. 优先写 run 目录；找不到 run 时退回共享 `test/execution-log.md`

当前共享 rule 契约是 shell 函数参数调用，不要求 `BT_*` 环境变量。
当前 `codex-cli 0.125.0` runtime payload 仍不提供 shell exit code；Codex 入口在该字段缺失时应记录 `EXIT: ?`，而不是报错。

### 5.3 `hooks/lib/rules/feedback-rules-guard.sh`

共享规则只接受“已解析出的目标路径”，并按下面语义返回：

1. 非受保护 `feedback-rules.json` 路径：返回 0
2. `run-*` / `merge-*` 目录下的路径：返回 0
3. merge lock 存在：返回 0
4. 项目级受保护路径且检测到活跃 tester session：stderr 提示并返回 2

### 5.4 `hooks/lib/rules/credential-scan.sh`

共享规则只接受“要写入的文本内容”，并按下面语义返回：

1. 内容为空：返回 0
2. 内容中未命中 credential-like pattern：返回 0
3. 内容中命中 credential-like pattern：stderr 提示并返回 2

Codex 侧当前只把“Bash 命令文本里的显式 literal”传给此规则，因此它不覆盖：

1. 从外部文件 `cp` / `mv` / `cat secret.txt > ...` 搬运 secret
2. 子解释器运行时生成的 secret
3. 其他不在命令文本中的动态值

### 5.5 `hooks/lib/rules/derived-view-guard.sh`

共享规则只接受“已解析出的目标路径”，并按下面语义返回：

1. 非派生视图路径：返回 0
2. `run-*` / `merge-*` 目录下的路径：返回 0
3. merge lock 存在：返回 0
4. 项目级受保护派生视图且检测到活跃 tester session：stderr 提示并返回 2

### 5.6 `hooks/lib/rules/post-test-checklist.sh`

共享规则只接受“已解析出的目标路径”，并按下面语义返回：

1. 非 `results.json` 路径：返回 0
2. 不在 `.better-work/test/` / `history/` 范围内：返回 0
3. 命中目标路径：stdout 输出 hook JSON，向模型注入 post-completion checklist advisory

此规则是 advisory，不阻断写入。

### 5.7 `hooks/lib/rules/results-validation.sh`

共享规则接受“已解析出的目标路径 + 目标文件内容”，并按下面语义返回：

1. 非 `results.json` 路径：返回 0
2. 路径不在 `.better-work/test/` / `history/` 范围内：返回 0
3. 文件内容为空或不是合法 JSON：返回 0
4. 字段完整且无明显语义错误：返回 0
5. 命中缺字段 / 弱证据 / 非标准 ID 等问题：stdout 输出 hook JSON，向模型注入 validation advisory

此规则是 advisory，不阻断写入。

### 5.8 `hooks/lib/rules/registration-gate.sh`

共享规则只接受“已解析出的目标路径”，并按下面语义返回：

1. 非 `strategy-plan.md` 路径：返回 0
2. 不在 `run-*` 目录：返回 0
3. `bio.md` 与对应 `testers/<tester-id>/registry.md` 都存在：返回 0
4. 任一注册材料缺失：stdout 输出 hook JSON，向模型注入 registration advisory

此规则是 advisory，不阻断写入。

### 5.9 平台入口职责

`hooks/*.sh` 与 `hooks/codex/*.sh` 只做：

1. 读平台输入 JSON
2. 提取路径 / command / stdout / exit code
3. 调用共享 rule
4. 自己保持静默成功退出，或按共享 rule 返回 2 阻断

入口层不允许承载业务判断分叉。

### 5.10 `hooks/lib/rules/session-write-guard.sh`

共享规则只接受“已解析出的目标路径”，并按下面语义返回：

1. 非 `run-*` 目录路径：返回 0
2. 未找到当前 tester 的 session 文件：返回 0
3. 当前 session 无 `run_dir`：返回 0
4. 目标 run 与当前 run 相同：返回 0
5. 目标 run 属于其他 tester：stderr 提示并返回 2

---

## 6. 安装器

`hooks/install-codex-hooks.sh` 必须支持：

```bash
hooks/install-codex-hooks.sh install [--project <path>] [--enable-feature-flag]
hooks/install-codex-hooks.sh status [--project <path>]
hooks/install-codex-hooks.sh uninstall [--project <path>]
```

### 6.1 默认安装位置

默认写入：

```text
<project-root>/.codex/hooks.json
```

不默认写入：

```text
~/.codex/hooks.json
```

### 6.2 feature flag 处理

1. 安装前检查 `~/.codex/config.toml` 或 `$CODEX_HOME/config.toml`
2. 若未启用 `codex_hooks`：
   - 默认报错退出
   - 不修改全局配置
3. 仅当显式传 `--enable-feature-flag` 时：
   - 备份原文件
   - 原地开启 `codex_hooks = true`

### 6.3 合并策略

安装器不能覆盖项目已有 `.codex/hooks.json`。

必须做到：

1. 安装前先删除 existing better-test 管理项
2. 保留非 better-test 的 hook 组和 hook handler
3. 再把 registry 里 active 的 better-test 条目写回去
4. uninstall 只删除 better-test 自己的条目

当前实现约束：

- 若目标 `matcher` 组已存在，better-test 条目追加到该组 `hooks` 数组末尾，不重排外部条目

better-test 管理项识别条件：

- `statusMessage` 以 `better-test:` 开头
- 或 `command` 落在当前 skill 的 `hooks/codex/` 路径下

---

## 7. 回归

### 7.1 `hooks/fixtures/codex/post-bash.json` / `hooks/fixtures/claude/post-bash.json`

提供一组语义等价的最小 Bash post-hook 样例，用于本地单元级验证和 parity 比较。

### 7.2 `hooks/test-execution-log-parity.sh`

至少覆盖：

1. Claude direct `hooks/execution-log.sh` 会写出 `execution-log.md`
2. Claude `hooks/gate.sh post-bash` 的文件副作用与 direct path 一致
3. Codex `hooks/codex/execution-log.sh` 的文件副作用与 Claude direct path 一致

### 7.3 `hooks/test-codex-hooks.sh`

至少覆盖：

1. `hooks/codex/execution-log.sh` 能创建并追加 `execution-log.md`
2. `install-codex-hooks.sh install` 会把所有 active Codex hook 写入项目 `.codex/hooks.json`
3. install 不会删除无关第三方 hook 条目
4. `uninstall` 只移除 better-test 自己的条目

### 7.4 `hooks/test-codex-bash-guards.sh`

至少覆盖：

1. `credential-scan` 会阻断显式嵌入 secret 的 Bash 写命令
2. `feedback-rules-guard` 会阻断命中的 Bash 写目标
3. `derived-view-guard` 会阻断命中的 Bash 写目标
4. `session-write-guard` 会放行 own run、阻断 cross-tester run
5. 非写命令或允许路径不会误阻断
6. 安装器会把四个 guard 作为 `PreToolUse/Bash` active 条目写入 `.codex/hooks.json`

### 7.5 `hooks/test-codex-post-bash-advisories.sh`

至少覆盖：

1. `post-test-checklist` 会在 Bash 写入 `results.json` 时输出 advisory JSON
2. `results-validation` 会在 Bash 写入坏的 `results.json` 时输出 advisory JSON
3. `registration-gate` 会在 Bash 写入 `strategy-plan.md` 且注册材料缺失时输出 advisory JSON
4. 非目标 Bash 命令不会误输出 advisory
5. 安装器会把三条 advisory hook 作为 `PostToolUse/Bash` active 条目写入 `.codex/hooks.json`

### 7.6 `hooks/test-codex-runtime.sh`

这是当前 schema spike 的落地脚本，至少覆盖：

1. 用安装器生成项目 `.codex/hooks.json`
2. 在真实 `codex exec` 会话里触发 `PostToolUse/Bash`
3. 验证 `execution-log.md` 真正写入，并锁定当前 `EXIT: ?` 行为
4. 在真实 `codex exec` 会话里验证 `credential-scan` 的 `PreToolUse/Bash` 阻断
5. 在真实 `codex exec` 会话里验证 `feedback-rules-guard` 的 `PreToolUse/Bash` 阻断
6. 在真实 `codex exec` 会话里验证 `derived-view-guard` 的 `PreToolUse/Bash` 阻断
7. 在真实 `codex exec` 会话里验证 `session-write-guard` 的 own-run 放行和 cross-tester 阻断
8. 在真实 `codex exec` 会话里验证 `post-test-checklist` advisory 对模型可见
9. 在真实 `codex exec` 会话里验证 `results-validation` advisory 对模型可见
10. 在真实 `codex exec` 会话里验证 `registration-gate` advisory 对模型可见
11. 用 side effect probe 锁定“`PostToolUse/Bash` 非零 hook 仍执行，但不让命令路径失败”的当前行为
12. 对 built-in 文件写入再跑一个 probe，记录当前 `matcher: "Write"` 的可观察行为

### 7.7 仍需保留的运行时验证边界

本地 fixture 回归不等于真实 Codex 生命周期已验证；但 `hooks/test-codex-runtime.sh` 通过后，可以把当前 8 条 active hook 视为“当前版本已实测”。

后续仍需要在版本升级时复验：

1. 升级 `codex-cli` 后再跑一次 runtime smoke
2. 若 native `Write` payload 不再是 `tool_name: "apply_patch"` + patch command，先更新 registry/spec，再推进对应 Codex 入口
3. 若 runtime payload 暴露 exit code，更新 Codex `execution-log` 记录语义和 fixture
4. 若 `PostToolUse/Bash` 非零 hook 的 stderr / failure 语义再次漂移，更新 runtime smoke 的 side-effect probe 口径
5. 若 `file_change` / `Write` 回调模型变化，先更新 registry，再推进对应 hook 入口
6. 若 advisory runtime smoke 失败，先区分是 hook 没触发、模型复述文案漂移，还是 Codex 回调协议变化；先看本地 advisory fixture，再看 runtime JSONL，最后才调整 smoke 断言

---

## 8. 文档同步要求

### 8.1 `hooks/README.md`

必须写清楚：

1. Claude 侧仍是完整 8 hook
2. Codex 侧当前有 8 条 active hook，且都做过 runtime smoke
3. `execution-log` 是 `PostToolUse/Bash`
4. `credential-scan`、`feedback-rules-guard`、`derived-view-guard` 与 `session-write-guard` 同时覆盖 `PreToolUse/Bash` 和 `PreToolUse/Write`
5. `post-test-checklist`、`results-validation` 与 `registration-gate` 同时覆盖 `PostToolUse/Bash` 和 `PostToolUse/Write`
6. Codex hooks 需单独用 `hooks/install-codex-hooks.sh` 安装
7. `install.sh` 不负责 hooks

### 8.2 `references/adapters.md`

Codex 小节必须明确三层：

1. Layer 1: skill 注册
2. Layer 2: AGENTS.md / protocol 注入
3. Layer 3: `.codex/hooks.json` 的 L1 hooks 安装

并明确 Layer 3 当前安装 8 条 active hook，其中 `execution-log` 仍是 `PostToolUse/Bash` 专用，其余 7 条同时覆盖 Bash 写路径和 native `Write`。
并明确 native Write 虽已实测可用，但真实 payload 是 `apply_patch`，所以 Codex 入口仍需要适配层。

---

## 9. 验收标准

必须满足：

1. Claude `hooks/execution-log.sh` 路径仍可用
2. Claude `hooks/credential-scan.sh` 路径仍可用
3. Claude `hooks/feedback-rules-guard.sh` / `hooks/derived-view-guard.sh` 路径仍可用
4. Claude `hooks/session-write-guard.sh` 路径仍可用
5. Codex 8 条 active 入口都存在，且走共享 rule
6. `install-codex-hooks.sh` 只读 `registry.json`
7. 默认安装到项目 `.codex/hooks.json`
8. 默认不改用户 `~/.codex/config.toml`
9. 文档中不再出现“Codex 当前 active 仅 execution-log”的旧口径
10. `hooks/test-execution-log-parity.sh` 通过
11. `hooks/test-codex-hooks.sh` 通过
12. `hooks/test-codex-bash-guards.sh` 通过
13. `hooks/test-codex-post-bash-advisories.sh` 通过
14. `hooks/test-codex-runtime.sh` 通过

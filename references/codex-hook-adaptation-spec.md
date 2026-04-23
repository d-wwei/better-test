# Codex L1 Hook 适配开发 Spec

> 关联文档：`references/codex-hook-adaptation-brief.md`
>
> 本 spec 解决“怎么做”。目标是把 better-test 的 L1 Hook 从 Claude 单平台实现，升级为“共享规则层 + 平台入口层”的结构，并在不破坏 Claude Code 的前提下，为 Codex 增加原生 Hook 支持。

---

## 1. 范围

### 本次 in scope

本次只对 **L1 Core Discipline** 做跨平台抽象和 Codex 落地：

1. `hooks/credential-scan.sh`
2. `hooks/feedback-rules-guard.sh`
3. `hooks/execution-log.sh`
4. `hooks/post-test-checklist.sh`
5. `hooks/results-validation.sh`

### 本次 out of scope

以下 Hook 仍保持 Claude 现状，不要求这次同步迁到 Codex，但实现结构必须为它们留好扩展位：

1. `hooks/derived-view-guard.sh`
2. `hooks/registration-gate.sh`
3. `hooks/session-write-guard.sh`

理由：

- brief 的核心目标是先补齐 Codex 在执行审计、凭证防护、结果提醒上的 L1 缺口
- 后 3 个 Hook 已进入 Phase B / 并发 tester 隔离问题域，迁移复杂度更高
- 如果这次同时迁 8 个 Hook，会把“抽象共享规则层”和“扩平台”两个任务耦合过深

---

## 2. 不可破坏的约束

### Claude 兼容性

1. 现有 `hooks/*.sh` 路径继续存在
2. Claude 的 `.claude/settings.json` 安装方式继续可用
3. Claude 用户不需要切换到新命令、新目录或新 workflow
4. Claude 下现有行为只允许“等价重构”，不允许功能回退

### 分层约束

1. `AGENTS.md` / `CLAUDE.md` / `GEMINI.md` 仍只负责 L0 protocol 注入
2. Codex Hook 配置不允许塞进 `AGENTS.md`
3. 技术设计必须把“规则逻辑”和“平台 I/O 适配”拆开

### 多平台扩展约束

1. 同一条业务规则只维护一份语义
2. 新平台接入时，只新增平台入口和安装文档，不重写规则逻辑
3. Hook 清单和事件绑定不能在多个文档/脚本里长期漂移

---

## 3. 现状基线

### 当前已存在的能力

- Claude Hook 安装与说明：`hooks/README.md`
- Claude Hook 脚本：`hooks/*.sh`
- Codex skill 注册和 L0 protocol 注入：`references/adapters.md`
- Codex skill sidecar：`agents/openai.yaml`

### 当前缺口

1. Codex 没有接入 better-test L1 Hook
2. `references/adapters.md` 当前只有 Codex 的 skill 注册 + protocol 注入，没有 L1 Hook 章节
3. `hooks/README.md` 当前文案主体仍是 Claude 导向
4. 现有 Hook 脚本默认耦合 Claude 风格的输入/输出 JSON

---

## 4. 目标产物

本次完成后，仓库应新增或修改为以下结构：

```text
hooks/
├── credential-scan.sh                  # 保留：Claude 稳定入口
├── feedback-rules-guard.sh             # 保留：Claude 稳定入口
├── execution-log.sh                    # 保留：Claude 稳定入口
├── post-test-checklist.sh              # 保留：Claude 稳定入口
├── results-validation.sh               # 保留：Claude 稳定入口
├── registry.json                       # 新增：Hook 元数据单一信源
├── codex/                              # 新增：Codex 平台入口层
│   ├── credential-scan.sh
│   ├── feedback-rules-guard.sh
│   ├── execution-log.sh
│   ├── post-test-checklist.sh
│   └── results-validation.sh
├── lib/                                # 新增：共享规则和统一返回协议
│   ├── contract.sh
│   ├── io-claude.sh
│   ├── io-codex.sh
│   ├── response-claude.sh
│   ├── response-codex.sh
│   └── rules/
│       ├── credential-scan.sh
│       ├── feedback-rules-guard.sh
│       ├── execution-log.sh
│       ├── post-test-checklist.sh
│       └── results-validation.sh
├── fixtures/                           # 新增：输入/输出夹具
│   ├── claude/
│   └── codex/
└── test.sh                             # 新增：本地回归脚本

references/
├── codex-hook-adaptation-brief.md
├── codex-hook-adaptation-spec.md       # 本文件
└── adapters.md                         # 更新：新增 Codex L1 Hooks 章节

hooks/
├── README.md                           # 更新：Claude + Codex 双平台安装/测试
└── install-codex-hooks.sh              # 新增：Codex Hook 安装/状态/卸载脚本
```

说明：

- `hooks/*.sh` 保持为 Claude 入口，避免破坏现有引用
- `hooks/codex/*.sh` 是 Codex 入口，负责把 Codex Hook I/O 映射到共享契约
- `hooks/lib/rules/*.sh` 是规则层，只处理规范化后的字段，不关心 Claude/Codex 差异
- `hooks/registry.json` 是 Hook 元数据唯一信源，后续新增/下线/分平台支持状态都先改这里

`hooks/install-codex-hooks.sh` 是本次明确产物。重点是：

- **不要**把“安装 Codex hooks”的副作用塞进默认 `install.sh install`
- 安装、状态、卸载都走独立脚本，避免和现有 skill 注册器职责混淆

---

## 5. 统一 Hook 契约

### 5.0 Hook 注册表

`hooks/registry.json` 是 Hook 元数据的单一信源（SSOT）。

它至少服务 4 个用途：

1. 定义仓库当前有哪些 Hook
2. 定义每个 Hook 的 phase、优先级、规则文件、平台入口、平台支持状态
3. 供 `hooks/install-codex-hooks.sh` 读取，生成/合并 Codex Hook 配置
4. 供 `hooks/README.md` 与 `references/adapters.md` 更新时核对支持矩阵，避免文档漂移

注册表不是可选优化，而是本次结构的一部分。后续新增 Hook 时，**先改注册表，再补实现**。

#### 注册表字段

顶层字段：

| 字段 | 含义 |
|------|------|
| `schema_version` | 注册表 schema 版本 |
| `hooks` | Hook 列表 |

每个 Hook 条目至少包含：

| 字段 | 含义 |
|------|------|
| `id` | 稳定 ID，建议 kebab-case |
| `phase` | `core` / `phase-b` 等 |
| `priority` | `P0` / `P1` / `P2` |
| `rule_path` | 共享规则文件路径 |
| `summary` | 单行说明 |
| `platforms.claude` | Claude 入口和事件绑定 |
| `platforms.codex` | Codex 入口和事件绑定 |

平台字段至少包含：

| 字段 | 含义 |
|------|------|
| `status` | `active` / `planned` / `disabled` |
| `event` | `PreToolUse` / `PostToolUse` |
| `matcher` | 工具匹配器 |
| `entrypoint` | 平台入口脚本 |

#### 注册表消费规则

1. `hooks/install-codex-hooks.sh` 只读取 `platforms.codex.status == "active"` 的条目
2. Claude 现有 `hooks/README.md` 中的 Hook 列表需要与注册表一致
3. `phase-b` Hook 即使暂未迁到 Codex，也应在注册表中出现，并标为 `planned`
4. 不允许在安装脚本里硬编码“5 个 Hook 名单”

#### 新增 Hook 的升级流程

以后每次新增 Hook，按固定顺序做：

1. 在 `hooks/registry.json` 新增条目
2. 增加 `hooks/lib/rules/<hook>.sh`
3. 增加 Claude 入口 `hooks/<hook>.sh`
4. 若 Codex 本次支持，则增加 `hooks/codex/<hook>.sh`
5. 运行安装/测试脚本验证
6. 再更新 README / adapters 文档

这样以后 skill 升级时，只有“新增/变更 Hook”才需要做 Hook 适配；纯 workflow、protocol、references 升级不需要动 Codex Hook 层。

### 5.1 共享规则层读取的规范化字段

所有 `hooks/lib/rules/*.sh` 只依赖以下规范化字段：

| 变量 | 含义 |
|------|------|
| `BT_HOOK_PLATFORM` | `claude` / `codex` |
| `BT_HOOK_EVENT` | `PreToolUse` / `PostToolUse` |
| `BT_TOOL_NAME` | `Write` / `Edit` / `Bash` 等 |
| `BT_FILE_PATH` | 被写入/编辑的目标路径 |
| `BT_CONTENT` | Write 内容或 Edit 新内容 |
| `BT_COMMAND` | shell 命令文本 |
| `BT_CWD` | 命令执行目录 |
| `BT_STDOUT` | 命令输出（可截断） |
| `BT_EXIT_CODE` | shell 退出码 |
| `BT_PROJECT_ROOT` | 当前项目根，用于定位 `.better-work/` |

### 5.2 共享规则层可调用的统一返回函数

`hooks/lib/contract.sh` 提供：

1. `bt_allow`
2. `bt_block "<message>"`
3. `bt_warn "<message>"`
4. `bt_append_context "<message>"`

返回策略：

- Claude 入口通过 `response-claude.sh` 转换成 Claude Hook 需要的 stdout / exit code
- Codex 入口通过 `response-codex.sh` 转换成 Codex Hook 需要的 stdout / exit code

### 5.3 入口层职责

`hooks/*.sh` 和 `hooks/codex/*.sh` 只能做三件事：

1. 解析平台 Hook 输入 JSON
2. 写入规范化字段
3. 调用对应规则脚本并输出平台格式结果

禁止入口层做业务判断，避免将来平台越多、逻辑越分叉。

---

## 6. 每个 Hook 的具体设计

### 6.1 `credential-scan`

共享规则文件：

- `hooks/lib/rules/credential-scan.sh`

平台入口：

- Claude: `hooks/credential-scan.sh`
- Codex: `hooks/codex/credential-scan.sh`

行为：

1. 仅检查 `.better-work/test/` 路径写入
2. `Write` 读取全文内容，`Edit` 读取新内容
3. 命中凭证模式时直接 block
4. block message 必须说明命中的近似片段，不输出完整凭证

Codex 验收：

- 写入含假 token 内容时被拦截
- 写入普通 markdown 时允许

### 6.2 `feedback-rules-guard`

共享规则文件：

- `hooks/lib/rules/feedback-rules-guard.sh`

行为：

1. 命中 `feedback-rules.json` 直接 block
2. block message 统一引导使用 `/better-test feedback` 或 merge 流程

Codex 验收：

- `Write` / `Edit` 都阻止
- 非该文件写入不误伤

### 6.3 `execution-log`

共享规则文件：

- `hooks/lib/rules/execution-log.sh`

行为：

1. 仅处理 shell / bash 类型工具
2. 自动定位 `.better-work/test/`
3. 如果存在 `.better-work/test/testers/<tester-id>/` 等新路径结构，优先遵守当前 workflow 约定
4. 若找不到 `.better-work/test/`，静默放行，不报错
5. 自动创建 `execution-log.md` 头部
6. 记录时间、命令、exit code、截断输出

实现要求：

1. 共享规则层只做“写日志”逻辑
2. Claude/Codex 的 shell 输出字段差异在入口层消化
3. 输出截断策略在 Claude/Codex 上保持一致

Codex 验收：

- 任意执行一条 shell 命令后，`execution-log.md` 自动追加
- exit code 和 stdout 能被正确记录
- 不要求人工通过 wrapper 命令触发

### 6.4 `post-test-checklist`

共享规则文件：

- `hooks/lib/rules/post-test-checklist.sh`

行为：

1. 仅在 `.better-work` 范围内写入 `results.json` 时触发
2. 输出 additional context / warning，不阻塞写入
3. 提醒内容保持与 Claude 现有语义等价

Codex 验收：

- 写入合规 `results.json` 后仍能看到 checklist 提醒

### 6.5 `results-validation`

共享规则文件：

- `hooks/lib/rules/results-validation.sh`

行为：

1. 仅在 `.better-work` 范围内写入 `results.json` 时触发
2. 非 JSON 内容直接跳过
3. 缺顶层字段、空 items、非标 ID、indirect pass 等问题给 warning
4. 不阻塞写入，除非平台行为强制且已明确接受该变化

Codex 验收：

- 故意构造缺字段 `results.json`，能收到 warning
- 合规文件不会误报

---

## 7. Codex 安装方案

### 7.1 目标

Codex Hook 安装要满足：

1. 可脚本化
2. 幂等
3. 不干扰现有 `AGENTS.md` 注入逻辑
4. 不覆盖用户已有其他 Hook 配置

### 7.2 支持的安装范围

支持两种 scope：

1. `project`
   - 写入 `<repo>/.codex/hooks.json`
   - 适合团队共享、项目内提交配置
2. `user`
   - 写入 `~/.codex/hooks.json`
   - 适合个人全局安装

默认推荐：

- 先支持 `project`
- `user` 作为可选模式

原因：

- better-test 是项目工作流型 skill，项目级 Hook 更容易和团队共享
- 不会把 better-test 的 Hook 默认施加到用户所有无关仓库

### 7.3 安装脚本职责

新增脚本：`install-codex-hooks.sh`

子命令：

1. `install`
2. `status`
3. `uninstall`

核心职责：

1. 检测 skill 实际路径
2. 从 `hooks/registry.json` 读取 `platforms.codex.status == "active"` 的 Hook 条目
3. 生成这些 Codex 入口脚本对应的 Hook 配置
4. 合并写入目标 `hooks.json`
5. 检查并启用 `~/.codex/config.toml` 中的 `features.codex_hooks = true`
6. `status` 输出当前 scope、配置文件路径、feature flag、注册表中 active Codex Hook 是否都已注册
7. `uninstall` 只删除 better-test 自己写入的 Hook 项

### 7.4 合并策略

`hooks.json` 的合并策略必须是“移除旧 better-test 项，再插入新项”：

识别方式：

- 以 command 路径是否指向 `<skill>/hooks/codex/` 作为 better-test 管理项识别条件

禁止：

- 覆盖整个 `hooks.json`
- 假定文件里只有 better-test 自己的项
- 在安装器里手写 Hook 列表而不读注册表

### 7.5 feature flag 策略

安装脚本对 `~/.codex/config.toml` 的处理要求：

1. 若未开启 `features.codex_hooks = true`，安装时补齐
2. 若用户已有 `[features]` 段，则只做增量修改
3. `uninstall` 不自动关闭该 flag，避免误伤其他 Hook 用户

### 7.6 Windows

本期不承诺 Windows 支持。文档中明确标注：

- v1 目标平台：macOS / Linux
- Windows 待 Codex Hook 能力和脚本运行方式稳定后再单独评估

---

## 8. Claude 兼容实现策略

### 8.1 保持稳定入口

以下路径在本次实现后仍必须可执行：

1. `hooks/credential-scan.sh`
2. `hooks/feedback-rules-guard.sh`
3. `hooks/execution-log.sh`
4. `hooks/post-test-checklist.sh`
5. `hooks/results-validation.sh`

这些脚本的重构方式：

1. 只做 wrapper
2. Claude JSON 解析放到 `hooks/lib/io-claude.sh`
3. 实际业务逻辑落到 `hooks/lib/rules/*.sh`

### 8.2 不触碰的范围

本次不修改以下逻辑语义，只允许做 import/调用重构：

1. Claude block 条件
2. Claude warning 文案的大意
3. Claude execution log 的基本格式

### 8.3 回归底线

如果某次抽象后 Claude 行为和旧脚本不一致，以 Claude 现状为准回调。

---

## 9. 对未来平台的扩展位

### 9.1 目录扩展方式

未来新平台统一按以下方式扩展：

```text
hooks/
├── <existing wrappers>
├── codex/
├── cursor/              # 未来如平台支持 lifecycle hooks
├── gemini/              # 未来如平台支持 lifecycle hooks
└── lib/
    ├── io-<platform>.sh
    ├── response-<platform>.sh
    └── rules/
```

### 9.2 扩展原则

1. 新平台只新增 `io-<platform>.sh`、`response-<platform>.sh` 和入口脚本
2. 不修改已有规则语义，除非所有平台一并受益
3. 若某平台只能支持部分 Hook，在 `references/adapters.md` 明确列出支持矩阵和降级步骤

### 9.3 本次必须预留的能力

本次抽象时必须保证：

1. 一个规则脚本可被多个平台入口复用
2. 返回“block / warn / additional context”不是写死在 Claude 语法上
3. fixture 测试目录可继续增加新平台样本
4. Hook 新增时，平台安装器通过注册表自动感知，而不是手工加名单

---

## 10. 测试与验证设计

### 10.1 夹具

新增：

```text
hooks/fixtures/
├── claude/
│   ├── pre-write-credential.json
│   ├── post-bash-success.json
│   └── post-write-results-invalid.json
└── codex/
    ├── pre-write-credential.json
    ├── post-bash-success.json
    └── post-write-results-invalid.json
```

要求：

1. 夹具来自真实平台 payload 脱敏样本
2. 夹具命名按“事件 + 场景”组织
3. 先用真实样本锁定协议，再做代码抽象

### 10.2 回归脚本

新增：

- `hooks/test.sh`

职责：

1. 跑 Claude fixtures
2. 跑 Codex fixtures
3. 检查 block / allow / warn 输出
4. 检查 execution-log 文件生成和追加
5. 失败时返回非 0

### 10.3 必测清单

Claude：

1. 凭证写入被拦截
2. `feedback-rules.json` 写入被拦截
3. `results.json` 缺字段有 warning
4. `results.json` 写入后 checklist 有提醒
5. Bash 后 execution log 追加

Codex：

1. 重复以上 5 条
2. feature flag 未开启时，`status` 能明确报未启用
3. 安装脚本重复执行保持幂等
4. 卸载只移除 better-test 项

### 10.4 手工烟测

至少做两轮：

1. Claude 项目里真实安装并触发一次
2. Codex 项目里真实安装并触发一次

---

## 11. 实施拆分

### Slice 1: 协议 Spike

输出：

1. 确认 Codex Hook payload 与返回协议
2. 产出脱敏 fixture
3. 形成最小字段映射表

完成标准：

- 能用一句话说明 Claude/Codex 的差异点
- `hooks/fixtures/codex/` 已有至少 3 个样本

### Slice 2: 共享契约层

输出：

1. `hooks/registry.json`
2. `hooks/lib/contract.sh`
3. `hooks/lib/io-claude.sh`
4. `hooks/lib/io-codex.sh`
5. `hooks/lib/response-claude.sh`
6. `hooks/lib/response-codex.sh`

完成标准：

- Claude 和 Codex 的入口脚本都能拿到同一套规范化变量
- 安装器后续可以只靠注册表发现 Codex active Hook

### Slice 3: P0 Hook 迁移

输出：

1. `credential-scan`
2. `feedback-rules-guard`
3. `execution-log`

完成标准：

- Claude 回归通过
- Codex P0 三项通过

### Slice 4: P1 Hook 迁移

输出：

1. `post-test-checklist`
2. `results-validation`

完成标准：

- 能在 Codex 下看到 warning / additional context
- 若某项受平台限制，文档中有明确降级说明

### Slice 5: 安装器 + 文档

输出：

1. `install-codex-hooks.sh`
2. `references/adapters.md` 更新
3. `hooks/README.md` 更新
4. `hooks/test.sh`

完成标准：

- 新用户按文档可完成 Codex Hook 安装
- 旧 Claude 用户无需调整原配置仍可继续使用
- 新增 Hook 时不需要去安装脚本里手改另一份名单

---

## 12. 文档改动要求

### `references/adapters.md`

新增独立章节：

- `## Codex L1 Hooks`

必须包含：

1. Hook 能力说明
2. project / user 两种安装方式
3. feature flag 前提
4. 已支持的 Hook 列表
5. 未支持的 Hook 列表和后续计划
6. 与 `AGENTS.md` protocol 注入的区别

### `hooks/README.md`

改成双平台文档结构：

1. Claude Code
2. Codex
3. Hook 列表
4. 本地测试
5. 限制与降级说明

---

## 13. 风险和决策

### 风险 1：Codex 返回协议与 Claude 差异过大

处理：

- 通过 `response-codex.sh` 收敛
- 不在规则层写平台条件分支

### 风险 2：安装器误覆盖用户已有 Hook

处理：

- 仅按 command path 清理 better-test 自己的项
- 所有写回使用 `jq` 做结构化 merge
- 安装项来源固定读 `hooks/registry.json`

### 风险 3：execution-log 的路径约定和新版 workflow 漂移

处理：

- 以当前 `references/test-execution-workflow.md` 和模板结构为准
- 如果发现路径已变化，先修正文档/模板，再实现 Hook

### 风险 4：本次只迁 5 个 Hook，README 当前却展示 8 个 Hook

处理：

- 文档明确区分 “Codex 已支持 Core 5” 和 “Claude-only Phase B 3”
- 不制造“Codex 已完全等价 Claude”的误导

### 风险 5：以后新增 Hook 时，注册表和实际实现脱节

处理：

- `hooks/test.sh` 增加注册表完整性检查
- 检查每个 active Hook 的 `rule_path` 和 `entrypoint` 文件都存在
- README / adapters 更新时先对照注册表

---

## 14. Definition of Done

以下条件同时满足才算完成：

1. Claude 原有 5 个 Core Hook 安装方式和行为保持可用
2. Codex 可通过原生 Hook 自动触发 5 个 Core Hook 中的 P0 三项
3. P1 两项在 Codex 上实现，或有清晰、已文档化的降级方案
4. `references/adapters.md` 和 `hooks/README.md` 已更新
5. `hooks/test.sh` 能同时回归 Claude fixtures 和 Codex fixtures
6. `hooks/registry.json` 已成为 Hook 名单和平台支持状态的单一信源
7. 结构上已经为未来迁移 `derived-view-guard` / `registration-gate` / `session-write-guard` 留好入口

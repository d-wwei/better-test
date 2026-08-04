# Source Provider Contract v1.0.0

Better Test 的通用层只定义协议，不内置项目目录、测试组、发布 gate 或领域规则。项目通过
`project-profile.json` 声明 Provider；Provider 把源码事实转换为 `source-map.json` 和
`source-impact.json`。源码仓库是事实源和被测对象，不是第三套手工知识库。

## 1. 四个合同

| 合同 | 所有者 | 生命周期 | 用途 |
|---|---|---|---|
| `project-profile` | 项目测试仓库 | git-tracked | Provider、能力、信任边界、降级策略、结果版本开关 |
| `capabilities` | Provider | 每次 probe | available / unavailable / unconfigured / error；每项必须附证据 |
| `source-map` | Provider | cache 或 run artifact，不作人工 SSOT | 源码身份、unit、risk unit、native check、依赖边、native asset hash |
| `source-impact` | Provider | run-local artifact | base/head、changed unit、风险传播、required/recommended/excluded、置信度 |

合同 JSON Schema 位于 `schemas/`；跨字段、路径、身份和证据闭环由
`scripts/validate-provider-output.py` 校验。合同版本独立于 results schema，当前为 `1.0.0`。

`capabilities` 必须完整列出七个标准 capability row：`source-map`、`source-impact`、
`native-test-inventory`、`artifact-identity`、`process-identity`、`session-readiness`、
`typed-subject-identity`。不可用能力也必须显式写成 `unavailable|unconfigured|error`；省略 row
不能被解释为“能力不存在”，否则策略解析会产生错误的模式或结论上限。项目 Provider 可以增加
能力，但不能改写这些标准 row 的含义。

## 2. Provider 操作

Provider 接受以下子命令，成功时 stdout 只能输出一个 JSON 文档，诊断写 stderr：

```text
probe     --project-root <path>
inventory --project-root <path>
impact    --project-root <path> --source-map <file> [--base X --head Y | --changed-file P...]
check     --project-root <path> --check-id <allowlisted-id>
```

- `probe` 输出 capabilities；缺依赖不能伪装 available。
- `inventory` 只读源码并生成 source map；相同输入必须得到相同规范化输出。
- `impact` 必须传播到反向依赖和项目 risk unit，不能把“内部实现变更”缩成直接单测。
- `check` 只能执行 source map 中列出的 allowlisted check；不得接受任意 shell 字符串。

通用 Rust/Cargo 实现在 `scripts/rust-cargo-provider.py`。项目可以叠加自己的 Provider，
但项目级命名、分组、gate、ledger 只能留在项目 Provider/profile 中。

## 3. 信任边界

`project-profile.providers[].trust` 必须声明：

- 相对项目根目录的精确 `path_scope`（可显式指向 sibling source checkout）；禁止个人绝对路径、
  `/`、home 目录等宽泛 scope；
- `source_access=read-only`；若测试任务明确授权修改源码，修改动作仍由主 Agent 执行，
  Provider 不获得隐式写权限；
- implementation `version` 或 `sha256`；复合 Provider 的脚本依赖也在 `dependencies` 逐项 pin，
  runner 会核对输出版本和全部声明 hash；
- `network=deny|explicit`、`external_writes=deny|explicit`；explicit 仍需调用时再次授权；
- 需要下载公开构建依赖时使用单独的 explicit profile，并同时传入显式授权。若启用
  `--scratch-dir`，目录不能是 `/`、HOME、project/source root；Cargo Home、target、HOME/TMP
  都绑定到该声明目录，runner 记录 duration/cache-hit。默认 read-only profile 不因此放宽；
  `--metrics-output` 可把 operation、耗时、scratch/cache 和 check failure count 写入独立
  sidecar；它不进入确定性的 Provider payload，也不能被当作产品测试证据；
- profile、命令、输出不得携带 token、password、OTP、cipher 或其他 secret。

`scripts/run-source-provider.py` 会最小化环境、隔离临时 HOME、拒绝未声明授权并校验输出。
它不是 OS 级网络沙箱；需要硬隔离时，项目必须把平台沙箱 wrapper 本身作为受信、可哈希的
Provider 命令声明，不能把环境变量 `BT_NETWORK_ACCESS=denied` 当成物理隔离证明。

## 4. 身份模型

以下身份必须分别记录，不能因同一版本号而合并：

```text
source -> build -> artifact -> installation -> process -> session -> external service
```

- clean source：commit；dirty source：commit + staged/unstaged/untracked scope + fingerprint。
- build：source ref + toolchain + lock hash + features + profile + output hash。
- artifact/install/process/session：使用各自可复核身份和 relation evidence。
- source 检查只能支持源码层 claim；不能推出进程 ready、业务 canary 或 release GO。
- artifact 与 source 无可验证 relation 时，必须报告 mismatch/blocked，而不是选一个相信。

## 5. 置信度与安全降级

impact 置信度为 high / medium / low。出现未知文件、解析失败、edge 不闭合或 Provider error 时：

1. `fallback_policy` 必须为 `expand-safe-default`；
2. required selection 不得为空；
3. 保留项目既有黑盒 hard gate、negative、recovery、auth/session 与安全约束；
4. 低置信度只能扩范围，不能缩范围；
5. missing capability 必须写入 strategy/results，并下调 `max_claim_scope`。

`source-impact.selections.required` 中每个 ID 都必须被至少一个已闭合结果 item 的
`selection_refs` 引用；仅在 source impact 中列出不算执行闭环。策略要求的 coverage lane 必须
`disposition=measured`、分母大于 0，并通过 `item_refs`、`evidence_refs` 和 subject refs 绑定到
本轮证据。项目 mutation policy 命中时，Provider 生成 required mutation selection，通用层增加
`mutation-adequacy` strategy gate；它是通用证据门，不属于项目产品 gate ledger，不能替代项目
自己的发布门。

只有满足全部条件才可删除旧黑盒 required 项：映射确定、替代证据足够、历史无 escape、原 hard
gate 保留、项目 owner 明确批准。白盒用于选得更准和定位更快，不是取消用户路径验证。

## 6. 版本兼容

- results v3.1：仍为 `schema_version: 3`，可选 `hybrid` 扩展，旧 reader 可忽略。
- results v4：typed subjects/relations、七条 coverage lane、claim scope、provider artifacts。
- shadow 阶段双写 v3/v4；先各自校验，再 canonicalize + semantic diff。
- default 阶段主结果写 v4，仍双写 v3 compatibility；停止 v3 新写入必须满足
  `references/v3-deprecation.md` 并取得明确人类批准。
- semantic diff 必须覆盖 objective、max claim、summary、item 状态/断言/证据数、gate、readiness
  与 carry-forward provenance；`PASS_WITH_CAVEAT`/legacy pass 不得被压成纯 PASS。
- v3 GO 在无法恢复 typed runtime identity 时，投影到 v4 必须 capped 为 blocked；禁止为追求
  “diff 相同”而捏造 process/session 身份。

## 7. 验证命令

```bash
python3 scripts/validate-provider-output.py project-profile <profile.json>
python3 scripts/validate-provider-output.py capabilities <capabilities.json>
python3 scripts/validate-provider-output.py source-map <source-map.json>
python3 scripts/validate-provider-output.py source-impact <source-impact.json>
python3 scripts/validate-results-v4.py <run/results.json> --profile <canonical/project-profile.json>
python3 scripts/hybrid-results.py semantic-diff <v3.json> <v4.json>
python3 scripts/hybrid-results.py dual-write <v3.json> <v4.json> <output-dir>
```

`--profile` 必须指向项目仓库或独立 control-plane 中受版本控制的 canonical profile；
不得指向 run 目录内随结果一起生成的副本。结果内 `input_refs.project_profile` 只做重放绑定，
不能充当自己的信任根。

release GO 除了所有 required/fixed gate 必须精确为 `pass`，还必须逐项满足 canonical profile 的
`evidence_policy.release_required_claim_scopes`。每个 scope 都要有独立的通过 item 并被通过 gate
引用；一个笼统 runtime item 不能复用成所有声明层。archive、installed executable、running
process 和 runtime evidence 的 hash 链分别闭合，包 hash 不能直接冒充安装后 executable hash。

`source_access=read-only` 由 runner 对 source checkout 的 staged、unstaged、untracked、ignored
内容做执行前后指纹比较来强制；发现变化立即拒绝输出。`network` 与 `external_writes` 是声明式
授权和最小环境/路径门禁，不等同 OS sandbox。需要硬隔离的项目必须把平台 sandbox wrapper
作为受 hash 约束的 Provider 命令，并在证据中记录该 enforcement。

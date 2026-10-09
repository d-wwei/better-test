# Product Operation

操作方法独立于 case 设计：case 给行为、前置、输入和 oracle；recipe 给已选入口的控制路径。
本协议挂在 tools / env-config / execution，不启动 init 中发现的命令。init 只读、生成知识，
禁止直接或通过 helper launch、drive、pilot、安装依赖。首次行为试验必须进入明确 execution。

## Capability and tool choice

按以下顺序选工具：项目既有测试/harness → 已安装且适配当前 surface 的控制工具 →
原生 CLI/API → 真实能力缺口才加薄适配器。实际 UI 义务必须从 UI 入口驱动；API 可作独立
后效 observer，不能替代按钮、快捷键、菜单、输入法或窗口行为。

逐项核对：支持的动作、观察通道、实例选择、权限与副作用、隔离方式、失败恢复、版本。
二进制存在、doctor 进程健康都不等于当前控制可用。先用同实例低风险正控制证明
动作和 observer 工作，再用空结果判断“没有副作用”。既有权限/credential policy 优先。

| 已有条件 | 处置 | 不能声称 |
|---|---|---|
| 项目有可用 Playwright suite | 复用现有 runner / profile / selectors；保存实际版本 | 不新增浏览器栈，不把 API 对照算 UI 操作 |
| 普通 CLI argv/stdin 已足够 | 直接运行并分开存 stdout/stderr/exit | 不要求 tmux；TTY 义务不能由 pipe 外推 |
| Electron 原生菜单路径 | 用支持原生菜单的控制面和窗口 identity | renderer DOM click 不能证明原生菜单 |
| 工具无权限/版本不匹配 | 明确环境 blocked；安全替代仅验证其可覆盖的 claim | 不安装全局工具、不标原入口通过 |

平台差异见 `references/tool-operation-platforms.md`。方法适配不等于八平台实测。

## Recipe interface

SSOT 是 resolved `TEST_ROOT` 的 `env-config.md` 具名区段和原有 `tools/`，不建独立 registry。
采用 recipe 的 case 使用 `environment_ref: "test-root:env-config.md#OP-NOTES-WEB"`。
旧自由文本 case 可以写相同引用，无需先迁移 case JSON。`runner_ref` 指实际测试入口，
不能用 recipe 冒充 runner，不增加 `recipe_ref`。保留原 case / tester / run ID。

具名区段的固定形状（内容是待项目绑定的模板，不能照占位值执行）：

```markdown
<a id="OP-NOTES-WEB"></a>
### OP-NOTES-WEB
recipe_revision: 1

#### Purpose
<case/entry 和适用行为；不复制 expected>
#### Capability and tool choice
<工具实际版本、动作/观察能力、选择原因、能力缺口>
#### Preconditions
<subject/build/session/profile、原 run identity、资源 owner、权限及副作用范围>
#### Launch
<项目精确命令、工作目录、拥有的 PID/端口/临时路径；未知命令标 draft>
#### Doctor
<实例绑定、ready 谓词、observer 正控制、等待 deadline>
#### Drive and Wait
<当前可观测目标、一次动作、完成谓词、有界等待>
#### Observe and Evidence
<实际 request/response/exit、原始 UI、重开及独立持久后效；run-local 路径>
#### Failure and Recovery
<归因、保留失败、reconcile、修正、条件重试上限、session reset>
#### Cleanup
<owner+存活确认，精确资源清理，证据前后可读/字节/hash 检查>
#### Proof status
Scope: case/entry revisions; recipe revision; subject/environment
Design: AUTHORED; unresolved: <原因或 none>
Structure: NOT_CHECKED / <真实 checker 输出，只证明结构>
Execution proof: NOT_RUN / <既有实际 run/artifact 及版本环境>
Detection proof: NOT_RUN / <故障与正确对照 run、具体谓词>
Current review: required: <未绑定/变化来源> / current-within-proof-scope
```

`recipe_revision` 和 Proof status 是知识元信息，不增加 results 字段，不藏进
provider_metadata。有真实 proof 且入口/工具/recipe/build/环境匹配，才可写
current-within-proof-scope。旧 proof 保留，新 revision 必须重新评估。

## Launch / Doctor / Drive / Observe / Cleanup

1. **观察与绑定**：从现有 intake/session 绑定 subject，核对 origin/app marker/profile、
   窗口/device、endpoint，或 binary/PID/PTY。doctor 与 drive 必须指同一原 identity。
   发现同名进程不能依名字猜目标；目标不明停止 drive。worktree 隔离不等于 GUI/profile/device
   隔离；真实共享 UI 同时只有一个 driver，或先取得实际隔离资源。
2. **确认前置**：检查 case 前态、数据、权限、owner、side-effect scope；确认 observer
   能在已知变化上观察结果。禁止清除别人实例、读取真实业务数据或扩大已授权副作用。
3. **一项明确操作**：UI 用最新 role/label/stable selector，保存其当前可观察依据；
   CLI 分 argv/stdin/TTY/stdout/stderr/exit；API 保存实参、响应和 correlation；后台/Agent
   跟踪真正业务终态。点击成功、HTTP 成功、进程退出只证明工具/调用层。
4. **有界等待**：优先 event/prompt/状态谓词，每次写 deadline 和最后观察。轮询有固定上限；
   不以任意 sleep 证明 ready，不以无输出证明完成。无项目 SLA 时，本次 timeout 不构成性能承诺。
5. **重新观察**：对照 case oracle 与既有 Pass 四件套；持久化要重开并有独立只读后效观察。
   同源 list API 可能同时错误，不能独力证明对象/事件唯一性。UI 成功提示与错误持久后效并存时
   按业务谓词记录 fail，不能改 expected 迎合工具成功。
6. **保存与清理**：原始失败和成功证据写既有 artifacts/execution-log/process-log，
   结果走原证据等级、hard gates、v3/v4 和 FULL-TEST-REPORT 校验。
   保留原 run，不建立第二个生命周期结果协议或报告。

## Failure and Recovery

失败先保留原始证据、重做 doctor，再归因；无法区分继续调查并限制 claim。

| 归因 | 最小判别证据与处置 |
|---|---|
| TEST-INFRA | driver/wrapper/selector/observer 失败；同身份独立同路径控制正常。修工具后复验原 case |
| 环境 blocked | 权限/依赖/端口/profile/stub 不可用；正控制失败和具体缺口。不能写产品 Bug |
| 文档漂移 | 冻结指令/selector 与当前入口不符；当前同路径正常及 revision 对照。修 recipe 后新 proof |
| 产品缺陷 | 前置/工具/observer 可用，实际入口违背冻结 oracle；排除相关环境因素并保存后效反例 |

进程存活而 UI/PTY prompt 卡住仍要 reset/rebuild 本 run session；先归档失败现场，
不能沿用健康检查宣布恢复。涉及子进程 deadline 继续使用
`references/procedures/subprocess-deadline-triage.md`；归因不明继续原三问/假设调查。

每次重试必须写四项：可重试原因、上限、再次执行前态、幂等性/去重契约。
首轮每个归因修正至多一次验证性重试；项目更严 policy 优先。产品自身正常 retry 按 case
另行验证，不与工具修正混计。不能无限 reset 直到绿、覆盖失败结果或缩小 occurrence 分母。

**写操作应答丢失**：先查回执/对象/真实状态做 reconcile。确认已提交时，不重复非幂等动作；
有冻结的幂等键+payload 合同才可按同 key/payload 验证重放。无法查询或确认生效时保存
一次请求和能力缺口，标 blocked/partial，禁止第二次写入碰运气。
timeout/observer 失效均不说明“无副作用”。

## Execution stage 0

首次或工具/recipe/build/环境变化后，在正式 execution 用一条受控低风险代表路径
完成 Launch → Doctor → Drive/Wait → Observe/Evidence → Cleanup。失败同样做 owned cleanup。
stage 0 是执行准备，不能在 init 偷跑。保留启动目标 identity、observer 正控制、业务后效、
失败/恢复和清理后证据存活。stage 0 blocked 时保留所需用例分母，不能把它们删成“无测试”。

pilot 仅支持实际走过的入口、工具/recipe revision、build 和环境；不能删除既有 required tests，
不能把一次 pilot 外推到全地图，也不能当特定缺陷检测 proof。检测能力须有同 case、同 oracle
的故障和正确控制，分别保留原始 run。

## Cleanup and evidence survival

只清本 run 创建且当前存活身份匹配的 PID/端口/profile/temp；禁止 kill by name、宽 glob、
共享目录递归删除、清理他人账号或删 run artifacts。目标不可确认时保留现场并报告残留。
清理前冻结已完成原始证据的路径/字节/SHA-256；停止后核对可读、存活和 hash。
仍在追加的 trace 先封存 immutable copy，再对 copy 作前后比较，同时保留原日志最终版。
cleanup 破坏证据时 recipe 不能标已验证，失败不能用后来重建的“相似证据”消除。

## Public development apparatus

`fixtures/tool-operation/README.md` 提供真实网页、stdlib 服务和薄 CLI，公开标注故障控制。
`bash hooks/test-tool-operation-fixtures.sh` 只验证装置语义；并非 Agent 遵守本协议、UI 操作、
故障归因或收益试验的证明。实际 Agent 试验必须显式加载集成 worktree Skill，另产原有 run，
冻结输入/expected 后执行，并保持未执行入口与平台 NOT_RUN。

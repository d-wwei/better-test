# Team Role Presets

多 tester / 多 agent 组队测试的抽象骨架。目标不是把某一场 battle 的 4 个角色写死，而是把可扩展的分工机制固化下来。

## 什么时候加载

```
IF 用户明确要求多 agent / team / parallel testing
OR strategy 检测到同时有 2+ 个活跃 tester
OR coordinator 在 merge 前需要理解各 tester 的职责边界
THEN 加载本文件
```

## 核心原则

```
1. 固化机制，不固化唯一编制
   → role schema 固定
   → role preset 可替换

2. 每个 tester 必须有独立 coverage axis
   → 不允许只是"大家都去测一遍"

3. 每个 team 至少有 1 个 skeptical / adversarial 视角
   → 不要求每次启动固定数量 Agent；视角不等于独立证据

4. 每个 role 必须写清 must_not_do
   → 防止资源互撞、破坏 longrun、重复消耗高风险额度

5. merge 按职责边界收口
   → 先看该 role 本来负责什么，再判断它漏没漏、强没强
```

## Role Schema

每个角色都按下面这套字段定义。可以写进 `strategy-plan.md` 的 `Team Contract` 段。

| 字段 | 必填 | 含义 |
|------|------|------|
| `role_name` | 是 | 角色名，可自定义，不要求固定词表 |
| `goal` | 是 | 这个角色最核心的任务 |
| `coverage_axis` | 是 | 它和其他 tester 的区分维度 |
| `primary_targets` | 是 | 优先测哪些对象：changelog / old bugs / longrun / invalid input / contract |
| `preferred_evidence` | 是 | 它最该产出的证据类型 |
| `anti_overlap_rule` | 是 | 如何避免和别人重复 |
| `must_verify` | 是 | 至少要补到什么程度才算完成 |
| `must_not_do` | 是 | 明确禁止事项 |
| `resource_needs` | 否 | 账号 / daemon / 端口 / 市场时段 / 长跑窗口 |
| `handoff_to` | 否 | 最主要的交付对象：coord / peer / longrun reviewer |
| `success_output` | 是 | 产物长什么样才算交差 |

## Team Contract

多 tester 时，不要只写"谁测 A 组谁测 B 组"。要写成一个可审计的 Team Contract。

### Team Contract 最少包含

```markdown
## Team Contract

- Coordination mode: <solo | preset | custom>
- Preset: <release-4way | api-3way | single-plus-l2 | custom | none>
- Coordinator: <tester-id or pending>
- Shared blind-spot guard:
  - <如何避免同模型/同路径/同账号共享盲区>

### My Slot
- Role: <role_name>
- Goal: <goal>
- Coverage axis: <coverage_axis>
- Primary targets: <...>
- Preferred evidence: <...>
- Anti-overlap: <...>
- Must verify: <...>
- Must not do: <...>
- Handoff to: <...>
```

### 组装规则

```
1. 先选 preset，再映射 tester-id 到 slot
2. 若活跃 tester 数 = preset 槽位数 → 直接一一映射
3. 若 tester 少于槽位数：
   → 保留 coverage 差异最大的槽位
   → 低优先槽位并入相邻角色，但要写 merged-axis
4. 若 tester 多于槽位数：
   → 不复制同一角色
   → 拆更细的 coverage axis（如 adversarial-rest / adversarial-mcp）
5. 同型 tester（同模型、同提示、同账号）不能映射到同一 blind-spot cluster
```

## 五类职责与风险配置

职责映射到已有 slot，不新增 runtime 角色枚举；role_name 仍可自定义。

| 职责 | 输入与交付 | 边界 |
|------|------------|------|
| Designer | 来源与行为义务 → 场景、case、oracle 引用 | 当前产品输出不能自动成为 expected |
| Independent reviewer | 先读来源形成义务，再与作者 case 对账 | 不擅改 expected，不 drive 共享产品；建议交知识 owner |
| Explorer | 时间盒 charter、未知与风险 → 尝试、反例、未发现范围 | 探索不替代冻结 case 执行；零发现合法 |
| Executor / driver | 冻结 case/revision、绑定环境 → 自己 run 的原始观察 | 不为使测试通过修改产品契约、expected 或其他 tester 的 run |
| Aggregator / coordinator | 各 run、来源与角色边界 → 证据核对、分歧处置 | 不能把多数票、角色数、模型数当正确性证明 |

低风险小改动可用 `single-plus-l2`：primary-tester 分阶段兼任设计/探索/执行，
l2-skeptic 先独立建义务，再审设计与结果；coordinator 可由 primary 兼任，但原有
Tentative Verdict Challenge 的起草者/挑战者必须不同。只做单 Agent 自审时如实标
`self-review`，不能声称独立 L2，也不能绕过原有 run/merge gates。

高风险发布可用原 `release-4way`，按权限、入口、状态、时序或 oracle 风险拆 axis，
再明确谁承担独立 design reviewer 与 aggregator。无需给五类职责各开一个 Agent。
更多 Agent 带来上下文、工具执行和对账成本；只在有不同风险轴、可用独立来源或可隔离资源时增加。

在 Team Contract 写明兼任角色、作者/审查者身份、模型与 session、共享资料和 artifact 来源。
同一 Agent 换角色、同一模型换提示词、读取同一 golden/cache/log 都不能自行形成独立证据。
不同文件和 independence_key 仍须满足既有 validator；语义上同源的证据另行揭示，不能因共识升级等级。
独立审查采用 `references/l2-audit-prompts.md` 的 A/B 输入边界。

## Preset Library

### `release-4way`

适用：发布前 / fix release / ship decision / cross-verify 较重的版本测试。

| Slot | Goal | Coverage Axis | Must Not Do |
|------|------|---------------|-------------|
| `fix-verify` | 核对 changelog 声称修复是否真实落地 | claim-by-claim verification | 不把 binary-only 写成 fixed |
| `regression` | 确认旧功能没被顺手搞坏 | old bugs + nearby surfaces | 不只跑 changelog 提到的路径 |
| `longrun` | 抓 snapshot 测不出来的时间维问题 | longrun / relogin / reconnect / drift | 不被其他 tester 打断 daemon 节奏 |
| `adversarial` | 主动找 parser / contract / silent success / mode split | invalid input + omitted fields + parity | 不重复大面积 happy path |

### `api-3way`

适用：API / daemon / MCP 项目，目标是快速建立有差异的 3 条测试线。

| Slot | Goal | Coverage Axis |
|------|------|---------------|
| `happy-path` | 建立最小正常面 | valid requests + critical workflows |
| `contract` | 验 schema / enum / field parity | required vs optional / surface parity |
| `adversarial` | 验 silent drop / wrong type / alias / mode split | malformed and omitted input |

### `single-plus-l2`

适用：只有 1 个 tester，但仍需要第二层 skeptical 审视。

| Slot | Goal | Coverage Axis |
|------|------|---------------|
| `primary-tester` | 正常执行 strategy + execution | main planned scope |
| `l2-skeptic` | 审执行与证据，不负责广度发现 | audit / challenge / merge framing |

### `custom`

适用：用户或项目自己定义角色。要求仍然满足 Role Schema。

## Coordinator Dispatch Protocol

Coordinator 派单时，不要只说"你去测这个"。至少要给一张 Dispatch Card。

### Dispatch Card 模板

```markdown
# Dispatch Card

- Preset: <release-4way | api-3way | custom>
- Slot: <role_name>
- Tester: <tester-id>
- Goal: <一句话>
- Coverage axis: <一句话>
- Primary targets:
  - <target 1>
  - <target 2>
- Pass/Fail oracle:
  - <怎么判断通过或失败>
- Preferred evidence:
  - <raw JSON / daemon log / control experiment / binary diff ...>
- Must verify:
  - <最低证据门槛>
- Must not do:
  - <禁止项>
- Frozen inputs: <source/case/map/recipe locators + revisions; unresolved 原因>
- Input stage: <A: source-only | B: reconciliation | frozen execution>
- Shard: <原 case IDs / entry IDs / environment IDs；未执行入口保留缺口>
- Planned overlap: <none | 独立复现/跨入口或跨环境对照 + 理由>
- Evidence origin: <来源/缓存/生成者；与 peer 同源处>
- Resources:
  - <目标 identity / resource owner / side-effect scope / 隔离方式>
  - <使用时段 / bounded wait / 交接条件 / release evidence>
- Driver: <唯一共享 GUI/设备 driver，或独立隔离实例>
- Cleanup owner: <启动资源的 tester；只清理自己可归属的资源>
- Handoff:
  - <交给谁，用什么产物格式>
```

独立 reviewer 的阶段 A 卡片只列原始来源/约束；Primary targets 不暴露作者 case，
Pass/Fail oracle 只引用原契约或 unresolved，Must verify 不偷渡作者预期结论。
作者 case、golden、strategy 和结果留到 A 已留存后的 B 输入；不能把完整执行卡片直接当 A。

### 派单纪律

```
1. 给 coverage axis，不只给文件/接口列表
2. 给 pass/fail oracle，不只给"多测测"
3. 给 must_not_do，防止互相污染环境
4. 对 cross-verify 任务尽量双盲：给指令和判据，不给原结论
5. 同时显式写出该 slot 不负责什么，避免全员默认兜底
```

## 资源分片与单 driver

每轮 dispatch 在现有 `strategy-plan.md` 写分片与重叠理由，并沿用既有 tester registry
记录资源 owner、使用时段、状态与释放证据。case ID 保留原格式；未隔离、未确认 owner 或
尚未释放的资源先排队，不默认并发。registry 文字登记是最终一致记录，**不是真实互斥锁**；
本模块不创建 lock/lease 服务。worktree 只隔离源码，不自动隔离产品资源。

| 对象 | dispatch 必须说明 |
|------|------------------|
| 端口 / daemon / PID | 实例 identity、启动 owner、自己的端口、ready 与退出依据 |
| 数据目录 / DB / queue | tester 专属目录/schema/namespace；共享账户或租户是否仍会互相影响 |
| browser profile / 页面 | 独立 profile 与实例；同桌面的 OS 输入仍需单 driver |
| 设备 / 账户 / 租户 | 实际隔离边界、授权和副作用范围；共享可变状态需串行 |
| 桌面 / 全局快捷键 / OS 输入 | 同一桌面只允许一个 driver；不同 tab/worktree 不构成隔离 |

共享 GUI 或设备只有一个 owner 可以 drive。其他 Agent 做只读设计/日志审查，或等待
原 owner 停止输入并给出释放观察；不通过争抢焦点测试并发。真正隔离的 API namespace
可并发，但身份、数据、资源和 cleanup 都要可归属；不得把 namespace 名不同等同于实际隔离。

接管前核对 registry 与现场 identity/释放观察，不能只按预约时间到点接管。无法确认资源
空闲时串行等待，等待有界，超时记环境问题。启动者负责失败后的清理；aggregator 不按
进程名批量 kill，也不删除其他 tester 的 profile/数据。采用 operation recipe 的项目，
目标 identity、owner、副作用、等待/完成条件和清理依据继续写在原 `env-config.md`。

分片优先避开低价值重复；有意的独立复现、不同 oracle、跨平台或跨入口 parity 保留，
写明目的与证据来源。不为了去重消除独立反例，也不把两次执行同一路径外推为全入口覆盖。

## Merge Protocol

Coordinator 合并时，先按 Team Contract 理解角色，再看结果。

### Tentative Verdict Challenge（多 tester 必做）

Coordinator 先生成**暂定**结论，不得直接发布最终 ship / no-ship verdict。由一个未参与该
结论起草的 `adversarial` tester 审查；若没有独立 adversarial tester，则使用
`single-plus-l2` 的 `l2-skeptic` 补位。挑战者不能只是确认格式，必须尝试证伪结论。

```markdown
## Tentative Verdict
- Drafted by: <coordinator-id>
- Verdict: <GO | NO-GO | BLOCKED | TARGETED-ONLY>
- Claims: <逐条 claim-id>
- Gate / DoD basis: <gate ids + evidence refs>

## Independent Challenge
- Challenger: <tester-id，不能等于 drafted by>
- Overclaim checks: <是否把 targeted pass 写成 release approval>
- Counterevidence: <遗漏或相反证据；没有也要写检索范围>
- Evidence origins: <独立来源与同源缓存/golden/log；不能按人数升级强度>
- Rebuttal and uncertainty: <可复现反驳 / 未验证疑点 / 待验证项>
- Evidence-grade challenges: <confirmed 是否真有两个 independence_key + 两个 run-local 文件；
  proven 是否有 basis + 独立 runtime artifact>
- Coverage / role gaps: <缺 slot、缺环境、缺 gate、缺 DoD>

## Coordinator Disposition
| Challenge ID | accepted / rejected | Evidence-based reason | Follow-up |
```

一人提供独立反例时，先保留原 artifact、核对版本/环境并安排 owner 复现；不能由多数意见覆盖。
分别标明设计问题、证据不足、工具/环境问题、已确认产品缺陷；怀疑不直接进入 confirmed Bug 数量。
允许零 findings，写检索范围与限制；零发现也不自动授予 GO。

所有 challenge 必须有 disposition。存在未处置 challenge 时，`merged-summary.md` 的 release
verdict 只能是 `BLOCKED`。挑战者与 coordinator 可以意见不同，但 coordinator 拒绝 challenge
必须引用原始 artifact / gate / item，不能用叙述性判断带过。

### Merge 关注点

| Role 类型 | merge 时重点看什么 |
|-----------|--------------------|
| `fix-verify` | changelog 是否被原子化验证，是否过度相信 binary |
| `regression` | 是否覆盖旧 bug / 相邻面 / pre-existing 标注 |
| `longrun` | functional / timing / result 三层是否分开 |
| `adversarial` | 是否真的在找新的负向路径，而不是重复 happy path |
| `contract` | parity / enum / null-vs-omit 是否分层写清 |

### 收口纪律

```
1. 先检查每个 slot 有没有完成自己的 success_output
2. 再检查不同 slot 之间有没有共享盲区
3. Coordinator 先写 tentative verdict
4. 独立 adversarial / l2-skeptic 完成 challenge
5. Coordinator 逐条 disposition 后才综合 severity / final ship verdict

不能因为结果好看，就忽略某个关键 slot 根本没完成自己的职责。
```

## 不要做的事

- ❌ 不要把 `release-4way` 写成唯一默认编制
- ❌ 不要让两个 tester 只是在同一 coverage axis 上重复跑
- ❌ 不要只按模块切分，不按测试视角切分
- ❌ 不要派单只写"多测测"、"全测一遍"
- ❌ 不要把 `accepted_peer_evidence` 写成 `live repro`
- ❌ 不要因为以后可能变，就什么都不固化；该固化的是 schema 和 protocol

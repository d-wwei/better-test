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
   → 否则容易共享同一种乐观盲区

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
- Resources:
  - <daemon/port/account/time window>
- Handoff:
  - <交给谁，用什么产物格式>
```

### 派单纪律

```
1. 给 coverage axis，不只给文件/接口列表
2. 给 pass/fail oracle，不只给"多测测"
3. 给 must_not_do，防止互相污染环境
4. 对 cross-verify 任务尽量双盲：给指令和判据，不给原结论
5. 同时显式写出该 slot 不负责什么，避免全员默认兜底
```

## Merge Protocol

Coordinator 合并时，先按 Team Contract 理解角色，再看结果。

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
3. 最后才综合 severity / ship verdict

不能因为结果好看，就忽略某个关键 slot 根本没完成自己的职责。
```

## 不要做的事

- ❌ 不要把 `release-4way` 写成唯一默认编制
- ❌ 不要让两个 tester 只是在同一 coverage axis 上重复跑
- ❌ 不要只按模块切分，不按测试视角切分
- ❌ 不要派单只写"多测测"、"全测一遍"
- ❌ 不要把 `accepted_peer_evidence` 写成 `live repro`
- ❌ 不要因为以后可能变，就什么都不固化；该固化的是 schema 和 protocol

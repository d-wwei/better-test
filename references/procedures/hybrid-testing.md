# Hybrid Testing Procedure

**触发**：项目声明 `hybrid_testing=true`，或 strategy 发现可读源码/构建图/静态检查能力。

## Step 1 — 先定目标，不先选模式

把本轮归为 `source_change`、`package_validation`、`behavior_regression` 或
`release_decision`。目标决定必须回答的 claim；可用能力只决定用什么证据回答。

## Step 2 — 能力探测与身份冻结

1. 校验项目仓库/control-plane 中的 canonical `project-profile.json`；run 内副本不得作为信任根。
2. 经受信 runner 执行 Provider `probe`；区分 unavailable、unconfigured 和 error。
   构建依赖缺失时先记录 BLOCKED_ENV；只有 profile 把 network/external writes 声明为 explicit
   且本次调用获授权，才可用隔离 `--scratch-dir` 下载/缓存，绝不写源码 checkout 或个人 Cargo Home。
3. 冻结 source/build/artifact/process/session 的独立身份。dirty source 必须记录三类 diff
   scope 和 fingerprint；无法绑定 artifact→source 时停止 artifact/source 联合归因。
4. 生成 run-local `capabilities.json`、`source-map.json`，校验并记录 SHA-256。capability 文档必须
   完整报告所有标准 row；项目 feature flag 关闭 hybrid/results-v4 时，策略必须移除相应有效能力，
   不能继续沿用 Provider 原始的 available 声明。

## Step 3 — 计算影响，不替代项目知识

Provider 计算 changed units、反向依赖和项目 risk unit；项目 `impact-map.md`、test groups、gate
ledger 仍由项目层拥有。两者取安全并集：

```text
required = provider required ∪ project hard gates ∪ active bug retests ∪ changelog mappings
recommended = 其余风险传播项
excluded = 仅限有证据、有原因、非 hard gate 的项
```

未知/低置信度时使用 profile 的 safe default。预测某风险但测试通过，不自动说明映射是假阳性；
只有在 oracle 能检测该风险、测试确实执行、变更确实覆盖该路径且重复样本仍无关联时，才能把
映射记为“支持度下降”。

## Step 4 — 七条 coverage lane

| Lane | 分母 | 证据 |
|---|---|---|
| surface | 可达用户/协议 surface | manifest + 实际请求 |
| inventory | Provider 识别的 package/target/native test | source map |
| code | 选定源码检查/测试 | 命令 artifact |
| diff | changed unit | diff + mapping |
| risk | impacted risk unit | risk edges + checks |
| invariant | 项目不变量/ledger | 项目校验器 |
| selection | required/recommended/excluded 决策 | source impact + strategy |

每条 lane 必须写 numerator、denominator、可复算 pct、subject refs、`item_refs`、
`evidence_refs` 和 tool。required lane 必须是 measured 且 denominator > 0；引用的 evidence 必须
属于所引用 item，item 的 subjects 必须覆盖 lane subjects。不同 lane 不相加成一个“总覆盖率”；
缺能力就写 0/unknown 条件和 missing capability，不捏造分母。

## Step 5 — 分层执行与 claim 上限

1. 静态/源码 review：形成假设、识别路径和不变量。
2. compile/unit/integration/mutation：验证 source/build claim。
3. artifact identity：证明被测包与 source/build 的 relation。
4. 黑盒 user-path/runtime：验证进程、session、业务 canary、写生命周期。
5. compare/negative/recovery：验证差异和失败语义。

`static|compile|unit|source_review|mutation` 结果不得 claim runtime/release。release GO 至少要有
绑定到通过项及通过 gate 的 process/session subject、所有 item 完成、所有 required gate 闭环且无
fail/blocked/skip。`confirmed|proven` 的每份证据都必须有匹配 run-local artifact 的 SHA-256；
`proven_basis.runtime_subject_refs` 必须属于当前 item 的 `subject_refs`。mutation 阈值来自项目 policy；
无项目阈值时报告 killed/survived/timeout/unviable 和每个 survivor disposition，不套通用百分比。
所有 required source-impact selection 都必须被闭合 item 引用；当策略要求 mutation 时，每个 required
mutation selection 必须通过，才能形成 `source_correctness`。release GO 还要求 strategy required gate
与项目 fixed gate 全部为 `pass`，并逐项满足 profile 声明的 release claim scopes。

## Step 6 — 双写与 shadow

feature flag 为 shadow 时：

1. 正常产出 v3；把 profile/map/impact/v4 shadow 的本地 hash 引用写入可选 `hybrid` 扩展。
2. 产出 v4，所有 artifact 必须 run-local。
3. 分别运行 v3/v4 validator。
4. canonicalize 并运行 semantic diff；任何结论、计数、item 或 readiness 差异都必须处置。
5. v4 不反向覆盖 v3；两份都原子写，避免半写状态。

## Step 7 — 完成条件

- Provider 同输入重复运行的规范化结果一致；
- project hard gate 无减少且 unknown 会扩围；
- 七 lane 可复算；所有 claim 有正确 subject；
- artifact/source mismatch 用负向夹具被拦截；
- L2 独立审计检查命令、覆盖、证据、身份 relation 和 dual-write semantic diff；
- 只有 shadow pilots 通过、项目 owner 批准后才把 `results_v4` 切为 default。

# L2 Independent Verification — Sub-Agent Prompts

Agent 在测试完成后（full/targeted 模式）读取本文件，spawn 子 Agent 执行独立审查。
设计审查先用下方 A/B 两阶段；执行审计继续用原 Audit 1–4 与既有 run/merge gates。

## 触发条件

```
IF test mode ∈ {full, targeted, compare, bug-retest}
AND results.json 已写入
THEN spawn L2 sub-agent
```

Smoke 模式通常不触发（覆盖率审计对 smoke 无意义）；但 results v4 default 切换、Provider 合同
升级、artifact/source mismatch 或 release GO 即使是 smoke 也必须触发 hybrid identity audit。

## Spawn 方式

主 Agent 使用 Agent tool spawn 子 Agent，prompt 从下方模板填充。子 Agent 的输出写入 `l2-findings.md`。

## 两阶段独立审查：先义务，后对账

设计审查在冻结 case/strategy 前进行；不能等全部执行完才第一次发现设计缺口。
执行后首次启动 L2 时也先完成阶段 A，再提供作者 case 与结果，沿用 Audit 1–4。
提前完成过 A 的 reviewer 保留当时输入版本；来源变化时补做受影响义务，不能倒填成事前独立判断。
M2/M3/M6 的 workflow 触发点见本模块 handoff；未集成时不能声称已经自动调用。

阶段 A 只给来源、需求/契约、变更、入口/状态地图及权限/资源约束。若地图由作者生成，
披露生成者与来源，只作导航，追溯原来源；地图不代替 oracle。暂不提供作者 cases、策略、
expected/golden、results、结论或评审判定依据。原需求里的验收数值仍可提供，不能为盲审删掉真实合同。
已接触作者方案则披露污染并限缩独立性；高风险义务交新 reviewer 或独立来源复核。
阶段 A 结果在本 run 既有 `l2-findings.md` 先写入，再由 reviewer 追加 B；不另建结论账本。

### 阶段 A Prompt（单独发出，不与 B 模板一起发）

```text
你负责独立形成测试义务，不要求一定找到 Bug。只读下列已授权来源；不要搜索作者
cases/expected/results/结论。若输入意外包含这些内容，记录污染范围，不声称盲审。

来源与版本：{requirement_contract_change_locators_and_revisions}
入口/状态地图：{map_locator_revision_author_and_source_refs}
权限、环境和副作用边界：{constraints}
范围与已知缺口：{selected_scope_and_unresolved_sources}
输出：{this_run_l2_findings_path}

先列出带来源 locator/revision 的行为义务：入口、状态、权限、边界、失败影响、
所需观察和 oracle 独立来源。没有独立 oracle 写 unresolved，不从当前输出猜 expected。
标明每条义务适用范围与不确定性；不操作共享产品，不擅改知识或 expected。
写明读了哪些材料、角色兼任/同源判断、未知与零发现范围。完成 A 后停止，等待 B 输入。
```

### 阶段 B Prompt（确认 A 已留存后发出）

```text
继续使用你已记录的阶段 A 义务，不把作者 case 反填成独立发现。
作者 case/策略与冻结版本：{case_and_strategy_locators_revisions}
oracle/fixture 与生成者：{oracle_locators_revisions_origins}
资源分片/recipe 与副作用：{resource_assignment_and_recipe_refs}
执行证据：{actual_run_artifacts_or_NOT_RUN}

逐项对账 A 义务与 case/entry/environment：缺失、重复、弱断言、循环 oracle、
操作不可行、错误的覆盖外推。指出对应来源、case ID 与 artifact；未执行入口保留缺口。
两 reviewer 复制同一 golden/cache/log 不算两份独立证据；人数和共识不能升级强度。
重要分歧要求独立来源或可复现反例。只有疑点时写待调查，交 owner 验证；不要 drive 共享
产品或自行改 expected。零 findings 合法，记录实际检索范围与剩余不确定性。
区分设计问题、证据不足、工具/环境问题、已确认产品缺陷；后者仍需原有证据/gate。
把 B 发现追加至同一 l2-findings.md，保留 A 记录、反例与反驳；执行后继续 Audit 1–4。
```

A/B 是输入发送边界，不是文件权限隔离。coordinator 不在 A 的同一消息附 B、作者材料或
assessor 答案；实跑需用新 session 的输入与调用轨迹检查提前读取、同源抄袭和资源冲突。
本模块 fixture 的方法与静态包装状态不证明 reviewer 准确率或实际协作语义。

## 分歧与发现处置

- 一人有独立反例时保留原始观察、subject/environment/版本，交资源 owner 有界复现，
  不投票裁决。不完整反例可标未验证，但不能删除它或用多数人无发现覆盖。
- 每条 finding 写类型、来源/独立性、观察与解释、反驳、最终处置及待验证项。reviewer
  输出保留原样；owner 的回应写在既有 audit 面板，merge challenge 的处置写在原 merge 位置。
- 零发现写 `✓ 未发现问题` 加 scope/来源/限制。输入缺失写未检查，不能把未检查算零问题。
- 原有 results.status、evidence grades、intake/validate-run 与 merge challenge 仍是权威 gates；
  reviewer 怀疑不能直接并入 confirmed Bug 数，结论一致不代替原始证据。

---

## Audit 1: 执行审计（Execution Audit）

**输入文件**：execution-log.md + results.json + test-groups.md

**Prompt 模板**：

```
你是独立审计员。你的职责是核对执行声明与证据，记录真实缺口；允许零发现，不为满足配额制造问题。

任务：对比执行日志（execution-log.md）和测试结果声明（results.json），检查主 Agent 是否真的执行了它声称的测试。

请阅读以下文件：
1. {path_to_execution_log} — Hook 自动生成的执行记录（不可篡改）
2. {path_to_results_json} — 主 Agent 声称的测试结果
3. {path_to_test_groups} — 测试组定义（每组应该跑什么命令）

检查以下 5 项：

1. **命令覆盖**：results.json 中每个标 ✅ 的测试项，execution-log 中有没有对应的命令记录？
   - 声称测了但 log 中没有对应命令 → ⚠ 标记

2. **结果一致**：execution-log 中命令的实际输出，和 results.json 中声称的 assertion_value 一致吗？
   - 声称 "power": 153.2 但 log 中实际输出不含 power 字段 → ⚠ 标记

3. **跳过的步骤**：test-groups.md 中推荐的组，有没有整组都没在 execution-log 中出现？
   - 整组 0 条命令但 results 中不是全标 ⏭️ → ⚠ 标记

4. **忽略的异常**：execution-log 中有没有包含 error/warning/fail 的输出，但 results.json 中对应项标了 ✅？
   - 输出有 error 但结果标 pass → ⚠ 标记

5. **对照执行**（compare 模式时）：每个测试项，execution-log 中是否有两条命令（先基准后被测）？
   - 只有一条 → ⚠ "没做基准对照"

输出格式见下方"l2-findings.md 格式"段的"执行审计"部分。只输出发现的问题，没问题的不输出。
```

---

## Audit 2: 覆盖率对账（Coverage Reconciliation）

**输入文件**：surface-manifest.md + results.json + known-issues.md

**Prompt 模板**：

```
你是独立审计员。你的唯一职责是检查测试覆盖的完整性。

任务：对比接口清单（surface-manifest.md）和测试结果（results.json），找出遗漏。

请阅读以下文件：
1. {path_to_surface_manifest} — 全部可测接口清单
2. {path_to_results_json} — 实际测试结果
3. {path_to_known_issues} — 已知问题（suppress/skip 的项）

检查以下 4 项：

1. **遗漏接口**：manifest 中有但 results 中没有对应测试的接口。
   - 列出每个遗漏的接口名 + 它在 manifest 的哪一行

2. **skip 审计**：每个标 ⏭️ 的项，skip_reason 是否合理？
   - "暂时跳过"、"下次再看"、"没时间" → ⚠ 不合格
   - "休市"、"需要 TTY 交互"、"安全约束" → ✓ 合格
   - skip 原因是"没配环境"但其实能配 → ⚠ 标记

3. **覆盖率声明**：results.json 中的 coverage 数字和实际计算是否一致？
   - 用 manifest 总数做分母重算覆盖率
   - 与 results.json 中声称的 reachable_coverage_pct 对比
   - 差异 > 5% → ⚠ 标记

4. **changelog 覆盖**（如有 changelog）：读 {path_to_changelog}，每条 changelog 是否有对应的测试项？
   - 未映射的 changelog 条目 → ⚠ "可能漏测"

输出格式见下方"l2-findings.md 格式"段的"覆盖率对账"部分。
```

---

## Audit 3: 证据审计（Evidence Audit）

**输入文件**：results.json + process-log.md（如有）+ bugs/ 目录

**Prompt 模板**：

```
你是独立审计员。你的唯一职责是检查测试证据的质量。

任务：检查每个测试结果是否有充分的证据支撑。

请阅读以下文件：
1. {path_to_results_json} — 测试结果（每项有 assertion_field、evidence_level 等字段）
2. {path_to_bugs_dir} — bug 报告目录（如有）

检查以下 12 项：

1. **pass 证据**：每个标 ✅ 的项：
   - assertion_field 是否具体？（"power" 是具体的，"output" 不是）→ 不具体则 ⚠
   - assertion_value 是否有值？（空 = 没验证）→ 空则 ⚠
   - evidence_level 是否 ≥ direct？（indirect 不够标 ✅）→ indirect 则 ⚠
   - evidence_level=confirmed 时，是否有至少两个不同 `independence_key`，且至少解析到
     两个 run 目录内真实存在的不同 artifact 文件？同一文件不同 fragment 不得算 confirmed
   - evidence_level=proven 时，是否有 source/proto 或 multi-version 的结构化 basis？
     functional pass/fail 是否另有与 basis 文件不同的 runtime artifact？

2. **fail 证据**：每个标 🔴 的项：
   - error_code 或 error_detail 是否有实际值？（不是"失败了"）→ 空则 ⚠
   - 是否有对照？（compare 模式下，有没有基准结果可对比）→ 无对照则 ⚠

3. **severity 评估**：每个 bug 的 severity 是否合理？
   - 影响核心功能（下单/查询/登录）但标了 P3 → ⚠ 建议升级
   - 只影响边缘功能但标了 P1 → ⚠ 建议降级

4. **乐观声明检测**：
   - 覆盖率声明是否和实际项数匹配？
   - "全部通过"声明但有 skip/pending → ⚠
   - "三通道一致"声明但只验证了 < 50% 的接口 → ⚠

5. **推测 vs 实锤**：results 或 bug report 中有没有"可能"、"应该是"、"大概"这种措辞用在结论中？
   - 结论用推测语气但 evidence_level 标了 direct 或更高 → ⚠ 证据级别虚标

6. **binary-only 修复宣称**：
   - 如果结论是"fixed / verified"，但证据只有 binary / strings / literal presence，没有 runtime hit → ⚠

7. **scope 限定是否缺失**：
   - 报告写"已修"、"三 surface 一致"、"全部通过"时，是否写清 mode / surface / 分母？
   - 只测 auth mode 却写成"已修" → ⚠

8. **观测和解读是否混写**：
   - bug report 是否把 observation（看到什么）和 interpretation / impact（怎么理解、影响谁）混成一句
   - impact 没独立证据支撑 → ⚠

9. **Gate / DoD / readiness 闭环**：
   - gate 是否引用真实 item 与 evidence source，verdict 是否与 item 状态一致
   - package-type required DoD checks 是否全存在且结论有证据
   - GO 是否在存在 fail/blocked gate、未通过 DoD 或无批准 skip override 时被错误给出

10. **环境与配置分母**：
    - 声称双配置 / 双环境 / 双机时，是否真的有不同 config_profile /
      environment_id / machine_id
    - 同一 run 或同一配置重复执行不得冒充独立覆盖

11. **Bug Report Schedule 完整性**：
    - `bugs/BUG-*.md` 每份是否都有 TL;DR、现象矩阵、基准对照、其他对照、
      权限/账号排除、Root cause 推测、复现步骤、影响评估共 8 节
    - 复现步骤是否可直接执行，预期/实际、命令参数、环境、对照、证据引用和影响范围
      是否完整，不能用“见日志”“同上”或本地链接代替
    - YAML 是否含完整身份、状态、严重程度、证据、影响范围、发现版本/run/tester、
      related tests、修复版本、回归 canary 和 post-ship/escape 字段
    - 任一节或元数据缺失 → ⚠ 不完整 Bug Report；主报告不得交付

12. **修复完整性审计**：
    - bug-retest / claimed fix 是否同时给出原始症状、保持项、相邻不变量、替代缺陷反例和 oracle
    - 集合/去重修复是否同时验证请求数、oracle 可用数、返回数、唯一数、顺序和集合覆盖
    - 字段修复是否检查参与同一计算或展示的关联字段，而不是只检查原失败字段
    - 若原始 predicate 通过但出现替代性退化，结论必须是“原问题关闭、新问题另开”，
      当前功能和 release gate 仍保持 FAIL；否则标记为 ⚠ 假关闭

输出格式见下方"l2-findings.md 格式"段的"证据审计"部分。
```

## Audit 4: Hybrid 身份与策略审计

**输入文件**：project-profile、capabilities、source-map、source-impact、v3/v4 results、strategy plan。

检查：Provider id/version/hash/path scope 与声明一致；dirty fingerprint 完整；source/build/artifact/
process/session 没有按版本号偷合并；source-only evidence 没有 runtime/release claim；unknown/low
confidence 扩围且 hard gate 未减少；七条 coverage lane 分母可复算；required/recommended/excluded
均有理由；双写文件各自通过 validator 且 semantic diff 已处置；v3 GO 未在缺 typed runtime identity
时被无条件继承。任何一项不满足均写 finding，并把 release readiness 上限降为 blocked/no-go。

---

## l2-findings.md 输出格式

子 Agent 把所有发现写入一个文件。主 Agent 不过滤不改写这个文件——直接嵌入审计面板。

```markdown
# L2 Independent Verification

> Generated: <YYYY-MM-DDTHH:MM:SS±HH:MM>
> Audited: results.json from run-<tester-id>-NNN
> Execution-log available: yes/no
> Review inputs: <A/B 发送时点 + 来源/地图/作者材料 revisions；缺失写未检查>
> Independence: <reviewer/作者/兼任角色；同源资料与提前接触>

## 阶段 A：独立义务

| 义务 | 来源 / revision | entry / state / permission | 所需观察 / oracle | 不确定性 |
|------|-----------------|----------------------------|-------------------|------------|
| <义务> | <原始 locator> | <范围> | <独立依据或 unresolved> | <缺口> |

## 阶段 B：设计对账与分歧

| 义务 / case | 类型 | 发现 / 原始来源 / 同源限制 | 反例或反驳 | 处置 / 待验证 |
|-------------|------|---------------------------|-----------|---------------|
| <引用> | <设计 / 证据 / 工具环境 / 已确认产品缺陷> | <具体依据> | <有界复现或未验证> | <owner 回应引用 / pending> |

无发现：`✓ 未发现问题`，附检索范围；未检查项单列，不计作 confirmed Bug。
reviewer 保留自己的观察与反驳；owner 的处置引用既有 audit/merge challenge，不能改写原发现。

## 执行审计

| # | 问题 | 测试项 | 详情 |
|---|------|--------|------|
| 1 | 声称测了但 log 无对应命令 | A-03 | results 标 ✅ 但 execution-log 中无 auth timeout 相关命令 |
| 2 | 输出有 warning 但标 pass | B-05 | log 中 "stale data" warning 但 results 标 ✅ |

## 覆盖率对账

| # | 问题 | 详情 |
|---|------|------|
| 1 | manifest 遗漏 | 以下 N 个接口无对应测试：[列表] |
| 2 | 覆盖率不一致 | 声称 82%，重算为 73%（差异原因：8 个接口未映射到测试项） |
| 3 | changelog 未覆盖 | 以下 changelog 条目无测试映射：[列表] |

## 证据审计

| # | 问题 | 测试项 | 详情 |
|---|------|--------|------|
| 1 | pass 无字段验证 | D-01 | assertion_field 空，只写了"输出正常" |
| 2 | severity 偏低 | BUG-002 | 影响所有 REST 查询但标 P2，建议 P1 |
| 3 | 推测当结论 | E-07 | 结论写"可能是预期行为"但 evidence_level 标 direct |

## Hybrid 身份与策略审计

| # | 问题 | 详情 |
|---|------|------|
| 1 | subject 越权 | source-only unit 结果被用于 release gate |
| 2 | 安全降级缺失 | unknown change 未扩展 required selection |

## 统计

| 审计项 | 检查数 | 问题数 |
|--------|--------|--------|
| 执行审计 | <N> 项 | <M> 个问题 |
| 覆盖率对账 | <N> 接口 | <M> 个遗漏/不一致 |
| 证据审计 | <N> 项 | <M> 个证据不足 |
| **合计** | | **<总问题数>** |

## 建议

- [基于发现的具体改进建议，如"A-03 需要补做实际测试"、"BUG-002 建议升级到 P1"]
```

---

## 主 Agent 的执行流程

```text
1. 读本文件；设计冻结前先派阶段 A，或在执行后 L2 先派 A
2. 准备 resolved TEST_ROOT 的知识/来源引用，与当前 run 的证据路径
   - test-groups / surface-manifest / known-issues 位于 TEST_ROOT，不冒充 run-local 文件
   - execution-log / results / bugs / l2-findings 位于当前 run；不改其他 tester run
3. 仅发送阶段 A；reviewer 在当前 run 的 l2-findings.md 留存独立义务后暂停
4. 发送阶段 B 的作者 case/策略/recipe；记录输入与版本、同源限制
5. results.json 已写入时，在同一 reviewer session 执行合并 Audit 1–4
   - 非 hybrid 的 Audit 4 写 N/A 及理由；缺输入写未检查，不能隐去 audit
6. reviewer 追加 B 与执行审计至同一 l2-findings.md，保留 A 原文
7. 主 Agent 将原始发现嵌入当前 run 的 audit-report.md，另写回应与待验证项
8. 多 tester merge 继续原 Tentative Verdict Challenge 与逐条 disposition
```

### 合并 Prompt（推荐：一次 spawn 做 4 个审计）

```
你是独立审计员。你的职责是核对主测试 Agent 的声明与来源，保留反例与反驳，允许零发现。

先确认阶段 A 已留存，再读取以下阶段 B/执行输入；执行 4 项审计并追加至同一文件。

文件列表：
- execution-log: {path}
- results.json: {path}
- test-groups.md: {path}
- surface-manifest.md: {path}（如不存在则 Audit 2 写未检查、原因与覆盖限制）
- known-issues.md: {path}
- bugs/: {path}（如不存在则跳过 bug severity 检查）
- project-profile/capabilities/source-map/source-impact/v4 shadow: {paths}（非 hybrid 则 Audit 4 写 N/A）

执行以下 4 项审计：

[Audit 1: 执行审计 — 上方完整内容]
[Audit 2: 覆盖率对账 — 上方完整内容]
[Audit 3: 证据审计 — 上方完整内容]
[Audit 4: Hybrid 身份与策略审计 — 上方完整内容]

将所有发现写入 {path_to_l2_findings}，格式见上方 l2-findings.md 模板。
没有发现的审计项写"✓ 未发现问题"。
```

---

## 不要做的事

- ❌ 主 Agent 不能编辑 l2-findings.md（子 Agent 的原始输出不过滤）
- ❌ 不因共识压下反例，不为凑 findings 造问题；检查证据、保留反驳并说明限制
- ❌ 不要跳过任何一项审计（即使看起来"明显没问题"）
- ❌ 不将普通 smoke 当全覆盖审计；触发条件中的 hybrid identity 例外仍必须执行

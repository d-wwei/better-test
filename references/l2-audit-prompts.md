# L2 Independent Verification — Sub-Agent Prompts

Agent 在测试完成后（full/targeted 模式）读取本文件，spawn 子 Agent 执行独立审查。

## 触发条件

```
IF test mode ∈ {full, targeted, compare, bug-retest}
AND results.json 已写入
THEN spawn L2 sub-agent
```

Smoke 模式不触发（覆盖率审计对 smoke 无意义）。

## Spawn 方式

主 Agent 使用 Agent tool spawn 子 Agent，prompt 从下方模板填充。子 Agent 的输出写入 `l2-findings.md`。

---

## Audit 1: 执行审计（Execution Audit）

**输入文件**：execution-log.md + results.json + test-groups.md

**Prompt 模板**：

```
你是独立审计员。你的唯一职责是找出主测试 Agent 的执行中的问题。不要帮它辩护。

任务：对比执行日志（execution-log.md）和测试结果声明（results.json），检查主 Agent 是否真的执行了它声称的测试。

请阅读以下文件：
1. {path_to_execution_log} — Hook 自动生成的执行记录（不可篡改）
2. {path_to_results_json} — 主 Agent 声称的测试结果
3. {path_to_test_groups} — 测试组定义（每组应该跑什么命令）

检查以下 8 项：

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

检查以下 5 项：

1. **pass 证据**：每个标 ✅ 的项：
   - assertion_field 是否具体？（"power" 是具体的，"output" 不是）→ 不具体则 ⚠
   - assertion_value 是否有值？（空 = 没验证）→ 空则 ⚠
   - evidence_level 是否 ≥ direct？（indirect 不够标 ✅）→ indirect 则 ⚠

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

输出格式见下方"l2-findings.md 格式"段的"证据审计"部分。
```

---

## l2-findings.md 输出格式

子 Agent 把所有发现写入一个文件。主 Agent 不过滤不改写这个文件——直接嵌入审计面板。

```markdown
# L2 Independent Verification

> Generated: <YYYY-MM-DDTHH:MM:SS±HH:MM>
> Audited: results.json from run-<tester-id>-NNN
> Execution-log available: yes/no

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

```
1. 测试完成，results.json 已写入
2. 读本文件（references/l2-audit-prompts.md）
3. 准备输入文件路径（全部在当前 run 目录内）：
   - execution-log: run-<tester-id>-NNN-<ts>/execution-log.md
   - results: run-<tester-id>-NNN-<ts>/results.json
   - test-groups: test/test-groups.md
   - surface-manifest: test/surface-manifest.md（如有）
   - known-issues: test/known-issues.md
   - bugs: run-<tester-id>-NNN-<ts>/bugs/
4. 填充 3 个 prompt 模板的文件路径
5. Spawn 子 Agent（用 Agent tool），传入合并后的 prompt
   建议合并为一次 spawn（3 个审计一起做），减少开销
6. 子 Agent 输出写入 run-<tester-id>-NNN-<ts>/l2-findings.md
7. 主 Agent 读 l2-findings.md，嵌入审计面板（run 目录内 audit-report.md）
```

### 合并 Prompt（推荐：一次 spawn 做 3 个审计）

```
你是独立审计员。你的唯一职责是找出主测试 Agent 的问题。不要帮它辩护。

请阅读以下文件，然后执行 3 项审计。将所有发现写入一个文件。

文件列表：
- execution-log: {path}
- results.json: {path}
- test-groups.md: {path}
- surface-manifest.md: {path}（如不存在则跳过 Audit 2）
- known-issues.md: {path}
- bugs/: {path}（如不存在则跳过 bug severity 检查）

执行以下 3 项审计：

[Audit 1: 执行审计 — 上方完整内容]
[Audit 2: 覆盖率对账 — 上方完整内容]
[Audit 3: 证据审计 — 上方完整内容]

将所有发现写入 {path_to_l2_findings}，格式见上方 l2-findings.md 模板。
没有发现的审计项写"✓ 未发现问题"。
```

---

## 不要做的事

- ❌ 主 Agent 不能编辑 l2-findings.md（子 Agent 的原始输出不过滤）
- ❌ 子 Agent 不要"帮主 Agent 找借口"——发现问题就标记，不要合理化
- ❌ 不要跳过任何一项审计（即使看起来"明显没问题"）
- ❌ 不要在 smoke 模式下触发（覆盖率审计对 smoke 无意义）

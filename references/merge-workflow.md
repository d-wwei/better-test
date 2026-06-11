# Merge Workflow

`/better-test merge` 在多个 tester 完成测试后执行：扫描 run 目录 → 校验覆盖 → 检测冲突 → 合并 bug → 重建聚合文件 → 用户确认。

执行此命令的 agent 承担 **Coordinator** 角色。理想情况下由未参与测试的 agent 执行（更客观），但任何 agent 都可以——workflow 保证步骤完整性。

## 前置条件

- 至少有一个 `run-<tester-id>-NNN-<ts>/` 目录存在
- 单 tester 时不强制 merge：run 目录输出直接就是项目结果。但用户仍可执行 merge 以生成项目级聚合文件
- Coordinator 遵守写权限矩阵：只写 `merge-*/` 目录和项目级聚合文件，不修改任何 tester 的 run 目录

---

## Step 1: 扫描 + 用户选择（scan_and_select）

```
扫描 history/ 下所有 run-*/ 目录：
  → 读每个 run 的 bio.md（tester 身份）+ status.md（结果摘要）
  → 判断"未合并"：该 run 未被任何 merge-*/ 的 merged-results.json 引用
  → 按版本分组展示：

  扫描到以下未合并的 run：

    v1.4.28:
      1. run-claude-a3f2-002-0422T1030+08  | 12/14 pass | completed
      2. run-codex-c9d4-001-0422T1100+08   | 8/8 pass   | completed

    v1.4.27:
      3. run-claude-a3f2-001-0421T1423+08  | 9/9 pass   | completed

  选择要合并的 run（如 "1,2" 或 "1-3"）:

IF 只有 1 个未合并 run：
  → 告知用户"只有一个 run，不需要 merge。如需生成项目级聚合文件，输入 y 继续"
  → 用户确认后执行简化流程（跳过冲突检测）

IF 没有未合并 run：
  → 报告"没有需要合并的 run"并结束
```

## Step 2: Coordinator 注册 + merge 锁文件（register_coordinator）

```
1. 创建 merge 锁文件：
   echo "<coordinator-id> <timestamp>" > .better-work/test/.merge-in-progress
   → derived-view-guard.sh 检测到此文件后放行 derived view 写入

2. 生成 coordinator-id：coordinator-<platform>-<4hex>
3. 创建 merge-<coordinator-id>-<ts>/ 目录
4. 写入 bio.md：
   - coordinator 身份信息（platform、model、session）
   - 合并范围：列出选中的 run 目录
   - 合并开始时间
```

## Step 3: 读取所有选中 run（read_runs）

```
对每个选中 run：
  → 读 results.json（结构化结果）
  → 读 summary.md（tester 结论）
  → 读 strategy-plan.md（此 tester 的计划范围）
  → 读 execution-log.md / l2-findings.md（如存在）
  → 列出 bugs/*.md（bug 报告清单）
  → 列出 feedback/*.md（feedback 清单）

  如 strategy-plan.md 含 `Team Contract`：
  → 提取 preset / role / coverage axis / must_not_do / handoff_to
  → merge 时按角色边界判断"该 tester 是否完成了自己的职责"

汇总并记录：
  - 所有 run 的测试项总数（去重前/后）
  - 各 run 覆盖的测试组
  - 各 run 发现的 bug 数
```

## Step 4: 覆盖校验（coverage_audit）

### Step 4.0: Gate 强制校验（merge 第二道闸，项目有 gate 清单+校验器时必做）

```
对每个候选 run 运行项目的 gate 校验器（如 python3 test/tools/validate-gates.py
--run-dir <run> --package-type <type> --keywords <该 run 的变更关键词>）：

  → 通过 → 继续
  → 非零退出 → 该 run 标 GATE-INCOMPLETE：
      a. 通知对应 tester 补跑缺失 gate（首选）
      b. 无法补跑 → 记入 conflict-log.md "Gate Gaps" 段，merged-summary 必须醒目声明
         "本次合并存在未闭合 gate: <列表>"，发版建议不得高于 SHIP_WITH_NOTES
  → 旧格式 run（无 gate_items 字段）→ 警告记录，不阻断（历史兼容）

价值：单 agent 在执行关口绕过了校验器，合并关口还能拦——gate 覆盖按 gate 维度
（而非组维度）核对还能发现跨 tester 互补：A 漏的 gate B 跑了即闭合，都漏的才是真缺口。
```

```
合并所有 tester 测过的 test_id（取并集）
对照：
  - 各 run 的 strategy-plan.md 中计划测试的 groups + items
  - test-groups.md 的完整测试清单

检查：
  1. 计划覆盖：所有 strategy-plan 中 planned 的 stage 是否都有人测了？
     → 缺失的 stage 记入 conflict-log.md 的 "Coverage Gaps" 段
  2. 交叉覆盖：同一 test_id 被多个 tester 测过的列表
     → 供 Step 5 冲突检测使用
  3. 未计划覆盖：tester 测了 strategy-plan 之外的项
     → 记录但不阻断
```

### Bug 粒度对齐（merge 前必做）

```
Merge 前两方必须显式同步"一个 bug 的定义"：
  → 4 sub-items 算 1 个 bug 还是 4 个？CLI 字段缺失和 REST 字段缺失是同一个还是两个？
  → 不对齐就 merge = 计数永远不一致（12 vs 13 真实案例）
  → 定义对齐后再进入冲突检测
```

### Cross-Verify 采信分类

```
Cross-verify 采信必须按 4 类报告，不允许把 evidence audit / accepted peer 写成 strict repro：

  live_repro: 自己独立重跑并拿到 direct / confirmed 证据
  evidence_audit: 自己没重跑，但检查了 peer raw JSON / log / strings artifact，内部一致
  accepted_peer_evidence: 因风险/成本不重跑，但明确接受 peer direct/proven 证据
  binary_corroboration: 用 binary/source/proto 证据佐证 claim 的某一层，但非完整 runtime 复现

报告时不要把后 3 类写成"已独立复现"。
```

### Cross-Verify 流程

```
1. 列 claims: 对方报告的每条结论逐一列出
2. 尽量双盲派单: 先只给测试指令 + PASS/FAIL 判据，不给原 tester 的结论和 narrative
3. 独立工具复现: 自己跑命令验证，不看对方的 curl/output
4. 发现差异先查自己: peer 结果不同 → 优先假设自己 env 有问题（配置/端口/账号/flag）
   → 列环境差异 → 1:1 重跑 → 单一 factor 切换
5. Steelman peer: peer challenge 时先假设对方全对自己有盲区
   → 先接受再查精度。不用"reviewer context 不全"当挡箭牌
   → peer 比我更准是正常现象（不在我的假设链里）
6. 看 raw artifact，不只看 summary
   → summary 只能当索引，结论必须落回 raw JSON / log block / strings output / bug report 正文
```

## Step 5: 冲突检测（conflict_detection）

```
对所有被多个 tester 测过的 test_id：
  → 比对结果：pass/fail/skip

IF 结果一致：
  → 正常，无冲突

IF 结果不一致（如 tester A 报 pass，tester B 报 fail）：
  → 读两个 run 的 process-log.md 中该 test_id 的相关段落
  → 分析可能原因：
    - 环境差异（不同端口、不同 daemon 实例）
    - 时序差异（A 先测，daemon 状态正常；B 后测，daemon 已崩）
    - 真正的 flaky
    - 测试参数差异
  → 如仍不清楚，做全变量 isolation matrix：
    body shape / headers / mode / account / timing / request order 全列出来，再找最小区分变量组
  → 记入 conflict-log.md：
    test_id、两方结果、分析、建议处置

合并规则：
  - fail 优先：任一 tester 报 fail，聚合结果标 fail（保守原则）
  - 但 conflict-log 保留完整信息供用户裁决
```

## Step 6: Bug 校验 + 重编号（bug_reconciliation）

```
收集所有选中 run 的 bugs/*.md

1. 去重检测：
   - 同一 test_id + 相似错误签名（error message 或 error code 匹配）→ 大概率同一 bug
   - 不同 test_id 但同一 root cause → 标记关联但分别保留

2. 冲突标注：
   - 同一 test_id 一个 tester 报 bug 另一个报 pass → 在 conflict-log.md 标记

3. 分配项目级编号：
   - 格式：BUG-<version>-NNN（NNN 从 bugs-index.md 的最大编号续接）
   - 每个 merged bug 的 YAML frontmatter 增加 source 字段：
     source: run-<tester-id>-NNN-<ts>/bugs/BUG-NNN-<slug>.md

4. 写入 merge-*/bugs/ 目录
```

### Severity 复核（merge 时统一口径）

```
Coordinator 对每个升级/降级建议做 3-anchor check：
  1. definitional：是否满足正式 P0/P1 定义
  2. scope-of-impact：影响人群和分母是否明确
  3. precedent：历史同类项如何定级

单一 anchor 不足以升级 severity。
scope-of-impact 说得很吓人，但 definitional 不满足时，不能硬升。
```

### Coordinator 协议（组队场景）

```
多 tester merge 不只是在收文件，也是在收 team contract：
  1. 读每个 tester 的 Team Contract
  2. 对照它的 role goal / coverage axis / success_output 看是否真的完成
  3. 检查 team 是否出现共享盲区：
     - 同模型 + 同账号 + 同 surface + 同输入姿态
  4. 检查是否有 slot 缺失：
     - 如发布测试没有 skeptical / adversarial 视角
  5. 最后再综合 ship verdict

如用户要 coordinator 派单，派单卡格式见 `references/team-role-presets.md`。
```

## Step 7: 合并 feedback + 重建 feedback-rules.json（merge_feedback）

```
收集所有选中 run 的 feedback/*.md

1. 按 test_id 分组
2. 按时间排序（每个 feedback md 的 YAML frontmatter 中有 timestamp）
3. 对每个 test_id 取最终 verdict：
   - 后写的 revoke 覆盖先写的任何 verdict
   - 同一 test_id 的非 revoke verdict 以最新为准
4. 重建 feedback-rules.json：
   - suppress: verdict 为 not-a-bug / wontfix / deferred 的 test_id
   - known_behaviors: verdict 为 not-a-bug 的（附 note）
   - lessons: 从 feedback notes 中提取 proven 级洞察
```

## Step 8: 生成合并输出（generate_output）

```
在 merge-<coordinator-id>-<ts>/ 目录内生成：

1. merged-summary.md — 统一结论
   - 合并范围（哪些 run）
   - 总覆盖率（去重后）
   - 总结论（pass/fail/skip 计数）
   - 新发现 bug 列表（项目级编号）
   - 冲突项数量（详见 conflict-log.md）
   - Cross-Verify 采信类型统计
   - Minor findings bucket（没单独立 bug 但值得下轮继续看的小问题）

2. merged-results.json — 聚合结果
   - 合并所有 run 的 items（去重，冲突项取 fail）
   - summary 重新计算

3. conflict-log.md — 冲突和差异
   - Coverage Gaps（Step 4）
   - Result Conflicts（Step 5）
   - Bug Conflicts（Step 6）

4. status.md — coordinator 工作状态
   - 合并进度 / 已完成

更新项目级聚合文件：
5. test/status.md — 从 merged-results.json 重新生成
6. history/bugs-index.md — 从 merge-*/bugs/ 重建
7. test/known-issues.md — 从 merged-results + feedback 更新
8. history/feedback-rules.json — Step 7 已重建
```

## Step 9: 展示给用户确认（present_to_user）

```
合并结果 — <N> 个 run

来源:
  run-claude-a3f2-002: 12/14 pass, 2 bugs
  run-codex-c9d4-001: 8/8 pass, 0 bugs

合并后:
  覆盖: 18/20 项（去重后）
  结果: 16 pass, 2 fail, 0 skip
  Bug: 2 个（BUG-v1.4.28-001, BUG-v1.4.28-002）
  冲突: 1 项（B-05: claude pass / codex fail → 标 fail）

详见:
  合并报告: merge-coordinator-xxx/merged-summary.md
  冲突记录: merge-coordinator-xxx/conflict-log.md

确认合并结果？[y / 查看冲突详情 / 重新分析某项]
```

用户确认后：
- 删除 merge 锁文件：`rm .better-work/test/.merge-in-progress`
- 合并完成。

---

## 与其他 workflow 的衔接

```
strategy    → 注册 tester，创建 run 目录，开始测试
跑测试      → tester 只写自己 run 目录内的文件
feedback    → tester 写 run 内 feedback/ 目录（不写 feedback-rules.json）
checkpoint  → tester 写 run 内 progress.md
所有 tester 完成 → 用户触发 /better-test merge
merge       → coordinator 读所有 run，生成合并输出 + 更新项目级文件
```

## 不要做的事

- 不要在 merge 过程中修改任何 tester 的 run 目录内容（只读）
- 不要自动丢弃冲突——全部记入 conflict-log.md 供用户裁决
- 不要跳过覆盖校验——即使所有结果一致，仍需检查是否有遗漏的 stage
- 不要在 tester 未全部完成时强制 merge——由用户判断何时所有 tester 就绪

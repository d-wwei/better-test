---
name: better-test
description: |
  黑盒 + 白盒混合测试知识管理：按目标和实际能力自动选择 blackbox / whitebox / hybrid 策略，为项目构建持久化测试组、源码影响映射、已知问题库和测试认知约束。支持安全降级、typed evidence、跨 session 反馈和断点续传。Better-Work 系列子技能。
  触发场景：发布新版本前回归、修了 bug 想验证、变更后想知道跑哪些测试、录入开发者反馈避免重复提报。独立命令 /better-test，或作为子技能 /better-work test。
  Subcommands: init, update, strategy, feedback, protocol-update, reflect, checkpoint, resume, merge, submit-bugs
argument-hint: "init | update | strategy | feedback <id> <verdict> | protocol-update [text] | reflect [scope] | checkpoint | resume | merge | submit-bugs <run-dir>"
---

# Better Test

为有持续测试需求的项目（库、daemon、API、CLI）构建和维护测试知识系统。让 agent 在变更后能 ≤2 步内知道该跑哪些测试、哪些是已知 fail、上次跑到哪里。

## Stance

像一个资深测试工程师在做交接——只讲能防止"白跑测试"和"重复提报已知问题"的关键信息。pass 必须基于返回值字段验证而非状态码；skip 必须醒目；feedback 提炼成规则而非沉没在历史里。

## Test Root Contract

任何读取、注册、执行、merge 或写入前，先从当前已加载的 Better Test skill 根目录执行：

```bash
TEST_ROOT="$("<skill-root>/scripts/resolve-test-root.sh" "$PWD")"
```

后续所有项目测试路径都相对 `${TEST_ROOT}`。解析顺序是 `BETTER_TEST_DIR` →
最近的 `.better-test-root` → `.better-work/test` → marker-validated flat `test/` → 用户级
registry。存在 `.better-test-root` 时，禁止再直接读取字面量 `.better-work/test`。

## Commands

- `/better-test init` — 探索测试结构，在 `${TEST_ROOT}` 生成测试知识文件
- `/better-test update` — 信号驱动的增量更新（新测试、新 bug、新组）
- `/better-test strategy` — 先判定目标和能力，再推荐 blackbox / whitebox / hybrid 下的 smoke / targeted / bug-retest / full
- `/better-test feedback <id> <verdict> [--note "..."]` — 录入反馈，提炼为 known-issues 规则。verdict ∈ `not-a-bug` / `fixed` / `fixed-differently` / `wontfix` / `deferred` / `revoke`
- `/better-test protocol-update [text]` — 升级测试认知约束：用户输入新原则或自动总结会话经验，确认后写入 protocol.md + changelog
- `/better-test reflect [scope]` — 从历史数据提取经验：impact-map 验证、稳定性趋势、bug 热点、经验综合、耗时校准、模式提炼。增量版在每次测试后自动执行
- `/better-test checkpoint` — 保存当前测试任务进度
- `/better-test resume` — 从上次断点恢复
- `/better-test merge` — 合并多个 tester 的测试结果（交互式选择 run，校验冲突，生成统一报告）
- `/better-test submit-bugs <run-dir>` — 按项目 policy 将 confirmed/proven Bug Reports 幂等提交到 GitHub Issues

## Output Structure

两种角色，严格隔离：**Tester** 在自己的 run 目录内独立工作；**Coordinator** 在所有 tester 完成后合并结果。

```
.better-work/                                  ← 与 better-code 共享
├── shared/                                    ← 读/写：所有 skill 可读写
│   └── index.md                               ← 优先只读；如写则 commit 标 [better-test]
├── code/                                      ← 只读：高风险区域 → 触发更全面测试
│   └── danger-zones.md
└── test/                                      ← 写：测试专用
    ├── protocol.md                            ← 项目级扩展：安全纪律 + 项目纪律（≤15 行），每对话注入。L0 + 思维纪律在 skill 的 protocol-base.md
    ├── protocol-changelog.md                  ← 共享知识：变更日志
    ├── protocol-versions/                     ← 共享知识：protocol 全文快照
    ├── test-groups.md                         ← 共享知识：测试组定义 + 运行条件
    ├── impact-map.md                          ← 共享知识：变更关键词 → 测试组映射
    ├── known-issues.md                        ← derived view（coordinator 写，tester 只读）
    ├── env-config.md                          ← 共享知识：测试环境配置
    ├── surface-manifest.md                    ← 共享知识：接口清单 SSOT
    ├── project-profile.json                   ← 可选：Provider/能力/信任边界/results feature flags
    ├── release-set-policy.json                ← 可选：跨 run 环境/配置/gate 分母
    ├── escapes.json                           ← post-ship escape 机器账本（SSOT）
    ├── escapes.md                             ← escape 人类视图
    ├── status.md                              ← derived view（coordinator 写，tester 只读）
    ├── tools/                                 ← 共享：跨版本复用的测试脚本
    ├── reference/                             ← 共享：暂存参考资料
    │
    ├── testers/                               ← 轻量注册表
    │   └── <tester-id>/
    │       └── registry.md                    ← 身份 + 资源声明 + run 列表（tester 自己可写）
    │
    └── history/                               ← 测试运行产出（git-tracked）
        ├── _meta.json
        ├── feedback-rules.json                ← derived view（coordinator 从各 run 的 feedback/ 重建）
        ├── bugs-index.md                      ← derived view（coordinator 从 merge 输出生成）
        │
        └── <version>/
            ├── run-<tester-id>-NNN-<ts>/      ← tester 的完整工作目录（自包含）
            │   ├── bio.md                     ← 此 run 的 tester 身份快照（不可变）
            │   ├── intake.json                ← 被测物身份声明；results 以 ID + SHA-256 绑定
            │   ├── strategy-plan.md           ← 此 run 的分阶段执行计划
            │   ├── progress.md                ← 断点（checkpoint 写入）
            │   ├── status.md                  ← 此 tester 本 run 的测试结果
            │   ├── results.json               ← 结构化结果
            │   ├── metrics.json               ← 非裁决性运行指标（可选）
            │   ├── capabilities.json          ← hybrid run-local 能力快照
            │   ├── source-map.json            ← hybrid run-local 源码事实缓存（非人工 SSOT）
            │   ├── source-impact.json         ← hybrid run-local 影响与 selection 证据
            │   ├── process-log.md             ← 过程日志
            │   ├── summary.md                 ← 2 分钟速览
            │   ├── FULL-TEST-REPORT.md        ← 开发者唯一交付（含全部完整 Bug Reports）
            │   ├── bug-issue-submissions.json ← 可选：Issue 编号/URL/fingerprint ledger
            │   ├── execution-log.md + l2-findings.md + audit-report.md
            │   ├── bugs/                      ← 此 tester 发现的 bug（run 内编号）
            │   │   └── BUG-NNN-<slug>.md
            │   └── feedback/                  ← 此 tester 录入的 feedback
            │       └── <test_id>_<verdict>.md
            │
            ├── merge-<coordinator-id>-<ts>/   ← coordinator 工作目录（仅多 tester 时需要）
            │   ├── bio.md                     ← coordinator 身份
            │   ├── status.md                  ← 合并工作状态
            │   ├── conflict-log.md            ← tester 间差异和冲突记录
            │   ├── verdict-challenge.md       ← 独立 adversarial 对 coordinator 暂定结论的挑战与处置
            │   ├── merged-summary.md          ← 统一结论
            │   ├── merged-results.json        ← 聚合结果
            │   ├── FULL-TEST-REPORT.md        ← 合并后的唯一开发者交付
            │   └── bugs/                      ← 校验后的 bug（项目级编号）
            │       └── BUG-<version>-NNN-<slug>.md
            │
            ├── input/                         ← 触发本版本测试的开发者输入
            └── baseline.json                  ← 旧版本行为快照（compare 模式用）
```

**写权限矩阵**：

| 角色 | 可写 | 不可写 |
|------|------|--------|
| **Tester**（测试期间） | `testers/<自己>/registry.md` + `run-<自己>-*/` 内全部文件 | 其他 tester 的文件、项目级聚合文件（status.md / known-issues.md / bugs-index.md / feedback-rules.json） |
| **Coordinator**（merge 时） | 项目级聚合文件 + `merge-<自己>-*/` 内全部文件 | tester 的 run 目录（只读） |

**tester-id**：格式 `<platform>-<4hex>`（如 `claude-a3f2`、`codex-c9d4`），由 `sha1(session_id + timestamp)[:4]` 生成。一个 tester 可跨 session 存活（通过 resume），但同一时刻一个 tester 只对应一个进程。详见 `references/templates.md` 的 registry.md 模板。

**时间戳规范**：所有时间戳统一为 ISO 8601 + 时区偏移，三档精度：Full `2026-04-21T14:23:07+08:00`、Compact `04-21 14:23:07+08`、Date-only `2026-04-21`。详见 `references/templates.md` 的 Timestamp Format Specification。

**完成门禁**：跨平台 authority 是
`python3 <skill-root>/scripts/validate-run.py --run-dir <run> --intake-policy required --project-root <project> --validate-report`。
Codex Stop hook 只在 active run 已进入交付阶段时调用该命令；同一 turn 最多阻断 3 次，
达到上限只允许会话退出，不会把失败结果改写为通过。

**注入**（Claude Code 示例）：项目 CLAUDE.md 中追加 skill 级
`@~/.claude/skills/better-test/protocol-base.md`，再追加 resolver 得到的仓库相对
`@<TEST_ROOT>/protocol.md`。其他文件按需 Read，禁止把默认布局硬编码到 flat 项目。

## Red Lines

1. 项目 `protocol.md` 超过 15 行 → 必须精简（安全纪律 ~3 + 项目纪律 ≤5 + 标题/空行 ~5）。L0 + 思维纪律在 skill 的 `protocol-base.md`（~18 行），项目不改
2. pass 判定只依赖退出码或"输出非空"（不验证返回值字段） → 违反测试铁律，必须改用具体字段断言
3. skip 没有醒目标注（视觉上等同 pass） → 违规，必须明确 `~` 或 `[skip]` 标记并附原因
4. `test-groups.md` 中条目缺少"运行条件"（环境、依赖、是否需要真账户）或"如何运行" → 不完整
5. `impact-map.md` 中关键词→测试组的映射没有验证依据（人类知识或历史 fail 共现） → 必须标注 `[未验证]`
6. `known-issues.md` 写入时未附 test_id + 判定来源（developer / human / inferred） → 违规
7. `feedback-rules.json` 被人手编辑（应通过 `/better-test feedback` 提炼或 `/better-test merge` 重建） → 违规，破坏自动化
8. `progress.md` 中记录无法被下一个 session 理解的模糊状态（如"差不多跑完了"） → 违规，必须精确到测试 ID 和组
9. `init` 时跑全部测试以"摸清当前状态" → 违规，init 只读知识不执行测试
10. flaky 测试连续 2+ 次表现不一致时，未在 `known-issues.md` 的 Flaky 段标注或未发起 `/better-test feedback ... deferred` → 违规，flaky 不能默默吞掉
11. 时间戳不带时区偏移（如裸 `2026-04-21 14:23` 或 `<ISO>` 占位符） → 违规，必须使用三档规范格式
12. tester 测试期间写入项目级聚合文件（`test/status.md`、`known-issues.md`、`bugs-index.md`、`feedback-rules.json`） → 违规，这些是 derived view，只有 coordinator 通过 `/better-test merge` 写入
13. tester 注册后未完成 `registry.md` + `run-*/bio.md` 创建就开始执行测试 → 违规，必须先通过注册门控
14. tester 测试期间写入其他 tester 的 `testers/<别人>/` 或 `run-<别人>-*/` → 违规，严格隔离
15. bug retest 涉及 backend 交互（下单/交易/账户操作）时，不得仅在 sim 环境验证 → 违规，sim 错误码可能与 real 不同，同一 bug 在 sim 上可能不可见
16. run 目录缺少 `results.json`（只有 markdown 无结构化数据） → 不完整，机器可解析的结果是跨 session 自动对比的前提
17. strategy 阶段 changelog 条目未逐一映射到测试项且未映射条目无显式标注 `⏭️ 不需要测: <原因>` → 违规，不允许静默跳过
18. 已知有 bug 的功能点标 pass（用 trivial case 凑）或用 skip 掩盖已知缺陷 → 违规，已知缺陷应标 fail + 注明 pre-existing
19. 把 `summary.md`、`bugs/`、`results.json` 等多个文件分别交给开发者 → 违规；它们是内部源，默认只提交通过机器校验的 `FULL-TEST-REPORT.md`
20. `FULL-TEST-REPORT.md` 只放 Bug 摘要、列表或链接，或任一 Bug 缺少 8 节正文/完整 YAML 元数据 → 违规；必须逐字嵌入本轮全部完整 Bug Reports
21. 用源码、compile、unit、mutation 证据宣称进程 ready、业务路径生效或 release GO → 违规；claim 不能超过 evidence subject
22. source/build/artifact/process/session 身份被版本号合并，或 dirty source 缺 staged/unstaged/untracked fingerprint → 违规；身份 relation 必须可复核
23. Provider/impact 不确定或失败时缩小测试范围、清空 required selection 或删除项目 hard gate → 违规；unknown/low confidence 只能 expand-safe-default
24. source-map 被人工维护为项目 SSOT，或项目专属 test group/gate/ledger 泄漏进通用 Provider → 违规；通用协议与项目知识必须分层
25. 多平台发布只用单一 OS/arch/runtime 的 GREEN 外推到全部包 → 违规；支持的平台必须分别绑定 artifact/process/session 证据，远端 runner/CI/长期测试机是合法环境，本机 VM 不是默认要求
26. 未通过完整报告、typed results、secret/PII 和 fingerprint 查重门禁就创建外部 Bug Issue，或把 direct/binary/blocked 结论自动提交 → 违规
27. active test run 调用 credential `rotate/enroll/set-*-pwd`、创建交互式 password bootstrap 或要求用户临场输入账号密码 → 违规；只允许 `profile_id` 非交互消费，缺失/拒绝必须记 `BLOCKED_CREDENTIAL_PROFILE` 并继续安全子集
28. 未先解析 `TEST_ROOT` 就直接读取或写入字面量 `.better-work/test` → 违规；仓库 marker
    与默认布局并存时必须以 `.better-test-root` 为准
29. 新 run 缺少 `intake.json`，或 `results.json.intake_ref` 的 ID / SHA-256 与该文件不一致
    → 违规；历史 run 可 advisory 兼容，但不能伪装为已绑定
30. 把 Codex Stop hook 的未触发、fail-open 或达到每 turn 阻断上限解释为 run 已通过
    → 违规；最终状态只认 portable `validate-run.py` 的真实退出码和证据

## Acceptance Criteria

1. 新对话加载 `protocol.md` + Read `status.md` 后，agent 能准确说出"当前版本是什么 / 哪些 ID 在挂 / 哪些已 suppress"，无需重跑
2. 代码变更后，agent 通过 `/better-test strategy` 在 ≤2 步内确定要跑的组（基于 impact-map.md + 变更信号），并显示推荐理由
3. 同一个 bug 用 `/better-test feedback <id> wontfix` 录入后，下次 strategy 推荐时该项自动从 active failures 排除，不再重复提报
4. `checkpoint` + `resume` 后，agent 能准确复述上次跑到哪个组的哪个 ID（resume 时列出所有 tester，用户选择要恢复的 tester）。如有 `strategy-plan.md`（status: confirmed 或 in-progress），resume 可跳过重跑 strategy 直接从计划续跑
5. `references/adapters.md` 为每个支持平台（Claude/Cursor/Gemini/Codex/OpenCode/OpenClaw）都给出**可粘贴执行**的注入语法（@ 引用 vs 内容嵌入），无 placeholder 占位
6. 多 tester 并发测试时，各 tester 只写自己的 `run-<自己>-*/` 目录和 `testers/<自己>/registry.md`，互不干扰。`/better-test merge` 能从多个 run 目录正确生成聚合 status.md、bugs-index.md、conflict-log.md 和 verdict-challenge.md；最终结论只能在独立 challenge 全部处置后发布
7. 新 run 必须按外部 canonical project profile 写结果并验证（run 内 profile 副本不是信任根）：`results_v4=default` 时主 `results.json` 为 v4 并继续
   双写 v3 兼容结果；否则主结果为 schema v3/v3.1。两版都必须通过各自 validator 与 semantic
   diff；confirmed
   要有两个不同 independence key 和两个不同 run-local artifact 文件，proven 要有
   source/proto/multi-version basis（functional 结论另有独立 runtime artifact），gate /
   package DoD / release readiness 机器闭环，跨环境要求由 release-set validator 对账
8. 每个 run/merge 完成 L2 和 challenge 后，必须用 `scripts/build-full-report.py` 生成并以
   `--validate-only` 复核 `FULL-TEST-REPORT.md`；所有 bug_id 均映射到完整 Bug Report，
   `bugs/` 中每份报告只嵌入一次且正文逐字一致。开发者默认只接收这一份文件
9. 启用 hybrid 的项目必须通过 project profile、capabilities、source map、source impact 和
   results v4 validator；unknown change 必须扩围，七条 coverage lane 可复算，source-only
   negative fixture 不能形成 runtime/release claim
10. results v4 shadow/default 都必须双写并运行 semantic diff；无法从 v3 恢复 typed runtime
    identity 时旧 GO 必须被 capped，不得为兼容而捏造 process/session。停止 v3 新写入必须另有
    明确的人类批准，不能随 v4 default 自动发生
11. 多 tester 的 v4 default 合并必须运行 `validate-merged-results-v4.py`，逐来源保留 subject、
    relation、typed item/evidence、gate、caveat 和 readiness occurrence；v3 merged validator
    仅用于历史兼容，不能作为 v4 主合并路径
12. 项目启用 `bug-issue-policy.json` 时，confirmed/proven Bug 每项独立创建一个 Issue；重跑
    命中 fingerprint 时只回写 run-local ledger，不重复创建，任何 secret/PII 发现均 fail closed
13. 启用无人值守 profile 的项目必须以 hook/validator 证明 active run 无 `rotate/enroll/set-*-pwd`
    或 password bootstrap；profile 缺失、被拒绝或远端 runner 无 secret provider 时必须机器化
    BLOCKED，不能回退为用户输入
14. test-root resolver 回归必须证明：`.better-test-root -> test` 与空 `.better-work/test` 同时存在时，
    init/strategy/execution/progress/merge 全部只访问 marker 指向的 `${TEST_ROOT}`

## References

三层加载架构：Tier 1 核心流程嵌入 workflow（每次执行自动加载）、Tier 2 扩展流程按条件加载、Tier 3 方法论参考供人类阅读（agent 不加载）。

### Tier 1: Workflow 文件（含嵌入的核心流程）

| File | Load When | Content |
|------|-----------|---------|
| `references/init-workflow.md` | `/better-test init` | 测试结构探索 + 材料收集 + 代码读取 + 生成知识文件。内嵌：新测试 4 问 |
| `references/update-workflow.md` | `/better-test update` | 5 类信号检测 + 增量更新。内嵌：新测试 4 问 |
| `references/strategy-workflow.md` | `/better-test strategy` | 变更检测 + 影响分析 + 决策树 + 条件检查（批量/组合策略/发布建议） |
| `references/test-execution-workflow.md` | 测试执行阶段 | **框架 + 模板**：结合通用纪律 + 项目知识生成专属执行计划。内嵌：四色标记 + 证据分级 + 错误三问 + 终态规则 + 安全守则 + 覆盖率报告 |
| `references/feedback-workflow.md` | `/better-test feedback` | 反馈录入 + 规则提炼 + suppress。内嵌：回归 canary 提示 |
| `references/l2-audit-prompts.md` | 测试完成后（full/targeted/compare/bug-retest） | L2 子 Agent 审查 prompt：执行审计 + 覆盖率对账 + 证据审计 + l2-findings.md 格式 |
| `references/protocol-update-workflow.md` | `/better-test protocol-update` | 认知约束升级 + changelog |
| `references/pending-skill-upgrades.md` | `/better-test update` Step 5.5 | 通用经验升级队列（agent 追加，人审核） |
| `references/reflect-workflow.md` | `/better-test reflect` | 历史经验提取：6 类分析 + 增量/全量两层机制 |
| `references/merge-workflow.md` | `/better-test merge` | 多 tester 结果合并：扫描 run → 冲突检测 → bug 校验 → 生成聚合文件 |
| `references/progress-workflow.md` | `/better-test checkpoint` 或 `resume` | 断点续传 |
| `references/templates.md` | 生成输出文件时 | 核心文件的模板 + 质量标准 |
| `references/team-role-presets.md` | strategy / merge 遇到多 tester 组队时 | 可扩展 role schema + preset 库 + coordinator dispatch / merge protocol |
| `references/adapters.md` | 多平台注入 | Claude / Cursor / Gemini / Codex 适配 |
| `references/source-provider-contract.md` | init / strategy / execution 遇到 Provider | 四合同、信任边界、身份、降级与版本兼容 |
| `references/v3-deprecation.md` | execution / merge / reflect 读写 v3/v4 | v4 default、v3 兼容写入、退场条件与回滚 |

### Tier 2: 扩展流程（条件触发加载）

| File | 触发者 | 触发条件 | Content |
|------|--------|---------|---------|
| `references/procedures/bdd-scenarios.md` | init / update | 用户在信号源 F 提供了 PRD 或验收标准 | Given-When-Then 场景生成 |
| `references/procedures/tdd-flow.md` | agent | 当前任务包含写新功能代码（不只是跑测试） | Red-Green-Refactor |
| `references/procedures/contract-testing.md` | init | Step 1 分类为 API/Web 服务 **且** 有多服务调用链 | 契约测试步骤 |
| `references/procedures/exploratory-charter.md` | 用户 / strategy | 用户要求"深度测试"；或 strategy 发现某模块 0 历史记录 | 探索性测试 charter |
| `references/procedures/hypothesis-investigation.md` | test-execution | 错误解读三问无法定位（3 问都答了仍不确定） | 3-假设法 + 调查阶梯 + 证据分级完整定义 + bug 分类 |
| `references/procedures/mutation-testing.md` | strategy | full/targeted **且** 有代码变更 **且** 项目有变异测试工具 | 增量变异测试 |
| `references/procedures/flakiness-scoring.md` | update / strategy | update 检测到 flaky 信号；或推荐组含 known-issues Flaky 项 | 稳定性评分 |
| `references/procedures/bug-report.md` | test-execution | 发现 bug 需要写报告 | 8 节标准格式 + 完整 yaml 元数据 + 单文件嵌入合同 |
| `references/procedures/longrun-testing.md` | strategy | strategy 包含 24h+ 长跑；或用户要求稳定性/耐久性测试 | 长跑监控：canary/采样器/三层健康验证/daemon 身份 6 元组 |
| `references/procedures/combinatorial-testing.md` | strategy | 2+ 个输入因子且穷举成本高；或需要证明 pairwise / 等价类覆盖 | 2-way 覆盖、等价类显式化、高风险 canary 与机器校验 |
| `references/procedures/hybrid-testing.md` | init / strategy | project profile 启用 hybrid，或发现可读源码/构建图能力 | 目标×能力策略、七 lane、claim 上限、v3/v4 双写 |
| `references/procedures/reference-suite-intake.md` | init / update / strategy | 用户提供官方、上游、旧实现或第三方测试仓 | 来源身份、危险扫描、全量 case map、adapter 边界与 drift 同步 |
| `references/procedures/dynamic-fixture-reproducibility.md` | strategy / execution | 用例动态选标的、发现 ID、使用随机池或当前市场状态 | seed、数据池、选中值、fallback 与 claim 分母 |
| `references/procedures/imported-skip-taxonomy.md` | init / execution / merge | imported suite 含 runtime/conditional skip | typed skip、分母影响和 closure action |
| `references/procedures/agent-intent-projection.md` | strategy / update | MCP/Agent/自然语言入口需要用户意图 smoke | 从 case map 生成用户语言检查清单 |
| `references/procedures/bug-issue-submission.md` | execution / merge 完成 | 项目启用 bug issue policy 且存在 confirmed/proven Bug | 完整报告门禁、脱敏、GitHub create-only、fingerprint 幂等和 URL 回写 |
| `references/integrations/macos-credential-broker.md` | strategy / execution | macOS 上存在 `dedicated-real-test` + `standing-all-actions` profile | 稳定 broker、profile_id-only、Keychain 轮换、0600 lease 和精确清理 |

### Tier 3: 设计文档（面向人类，agent 不加载）

| File | Content |
|------|---------|
| `references/methodologies/design-rationale.md` | 全部方法论的设计理由和研究依据：覆盖率（ICSE 2014、Google 变异测试）、调查方法（systematic-debugging、证据分级）、测试设计（TDD/BDD/契约/探索性研究数据）、执行纪律（DORA 2024、Meta flakiness）、环境陷阱、Bug Report 格式 |

## Interface Contract（与 better-work 集成）

作为 `/better-work test <cmd>` 的子技能时，better-work 把命令名透传：`/better-work test init` → `/better-test init`。本 skill 不感知是否被路由，独立可用。共享目录 `.better-work/shared/` 可读写，但优先只读；如需写共享内容，commit message 标注 `[better-test]` 来源。

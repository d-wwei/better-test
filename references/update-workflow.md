# Update Workflow

`/better-test update` — **所有测试经验的统一入口**。自动将经验分流到正确的层和文件。

## 核心原则

Update 是测试知识的**唯一写入通道**（feedback 除外，它专门处理开发者判定）。不管经验来自哪里——测试中踩坑、用户口述、session 自动总结、新材料——都走 update，由 update 自动判断该存哪。

**不再需要人判断"这条经验该用 update 还是 protocol-update"。** Update 内部会分流。

---

## Step 1：经验收集

### 模式 A：自动检测（无参数）

```
/better-test update
```

Agent 回顾当前会话，提取所有候选经验：
- 踩过的坑
- 发现的测试模式
- 重复出现的检查动作
- 环境发现（新的依赖/约束/注意事项）
- 新材料（用户提供的 API 规范、错误码表等）
- 覆盖缺口
- 结构性变化（新测试组、新映射）

同时检查 hybrid 漂移信号：Provider 脚本/version/hash、源码布局、Cargo/build graph、native
inventory/ledger、project profile feature flags 和最近 source-map 生成错误。通用合同变化走 skill
升级；项目 unit/risk/gate 映射变化只更新项目 profile/provider/source-model，禁止跨层复制。

### 模式 B：用户显式输入

```
/better-test update "daemon 会包装所有 backend 错误码，不能信外层 error message"
```

用户直接提供一条经验。Agent 负责分流。

---

## Step 2：分流决策树（每条经验必过）

对每条候选经验，按以下决策树判断该存到哪个文件：

```
Q1: 这条是关于"怎么想/判断"还是"怎么做/执行"？
│
├─ 怎么想（思维方向/判断标准）→ Q2
│
└─ 怎么做（具体步骤/操作）→ 不进 protocol
     │
     ├─ 是通用执行步骤 → 提议修改 test-execution-workflow
     ├─ 是某个测试组的运行方式 → test-groups.md
     ├─ 是环境配置/注意事项 → env-config.md
     └─ 是新的影响映射 → impact-map.md

Q2: 是所有项目通用还是这个项目特有？
│
├─ 所有项目通用 → 标记为"通用原则候选"
│    → 写入 protocol.md 项目纪律段（暂时生效）
│    → changelog 标注"通用原则候选，待人审核后升级到 skill 模板"
│    → 提醒用户："这条可能是通用的，需要你手动审核后修改 skill 的 templates.md"
│
└─ 这个项目特有 → Q3

Q3: 每次测试都需要想到还是特定情况才用？
│
├─ 每次都需要 → protocol.md 项目纪律段（≤5 行）
│    → 走 protocol-update 的验证流程（矛盾/降级/范围/空话检查）
│    → 满 5 行时替换最不常触发的旧条
│
└─ 特定情况 → 不进 protocol
     │
     ├─ 和某个测试组相关 → known-issues.md lessons 段（按组标签）
     ├─ 和某个模块相关 → test-groups.md failure modes
     ├─ 和环境相关 → env-config.md 注意事项
     └─ 是 Hook 应该拦截的 → 记录到 roadmap 的 hook 候选

Q4（对所有进 protocol 的）: 具体到 agent 能对照自检吗？
│
├─ 具体可操作 → 通过
└─ "注意质量"这种空话 → 拒绝，要求改具体
```

---

## Step 3：按分流结果执行写入

### 3a. 知识文件更新（test-groups / impact-map / known-issues / env-config / status / surface-manifest）

按信号类型更新对应文件；先执行下面的写权限约束与变更传播，不能把新输出直接当新预期：

| 信号类型 | 写入文件 | 验证 |
|---------|---------|------|
| 新测试组 / 新测试项 | test-groups.md | 4 问检查 |
| 新影响映射 | impact-map.md | 来源必填，无依据标 `[未验证]` |
| Flaky 发现 | **测试期间**：run 目录内 progress.md 关键发现段；**非测试期间**：known-issues.md Flaky 段 | 稳定性评分 |
| 经验教训 | **测试期间**：run 目录内 progress.md 关键发现段；**非测试期间**：known-issues.md lessons 段 | 沿用现有证据分级；重复观察不自动成为 confirmed/proven |
| 覆盖缺口 | **测试期间**：run 目录内 summary.md；**非测试期间**：status.md 覆盖缺口段 | 标明风险和建议测试组 |
| 新材料 | 对应文件（见下方材料处理表） | 立刻分析影响 |
| 环境发现 | **测试期间**：自己 run 的 progress.md；**非测试期间**：env-config.md | 当场保存脱敏来源、条件与待复核 recipe；合并后更新共享知识，不把账号标识当凭证 |
| surface 变化 | surface-manifest.md | 新增标"未覆盖"，删除标"废弃" |

> **写权限优先**：先按 SKILL 解析 `TEST_ROOT`，核对身份与活跃 session。测试期间 Tester 只写自己 run 的 progress/summary/strategy/feedback 和自己的 registry；共享知识的修改建议也先存自己 run，不能因本表或后续 protocol/材料处理步骤越权写项目文件或别人的 run；这些步骤同样先把建议存自己 run。Coordinator 合并时只读历史 run，在自己的 merge 记录中保留建议与来源，再更新共享知识和 derived views。单 tester 完成后或无活跃测试时才按职责更新项目文件。已冻结历史 run、intake、results、原始 artifact 不因 update 改写。

### 3a.1 变化分类与引用传播

固定 before/after 来源 locator、revision/digest、采集时间、产品/平台/角色/状态范围；未知版本写 `unresolved` 及原因。通过既有引用追踪 requirement → feature/entry/state → case → oracle/recipe；同一 case 的多个 entry 分别核对，不以一次 API pass 代表按钮、快捷键或其他平台。未建立映射时保持 `unknown` 并扩大调查，既有 hard gates 与高风险 canary 不缩小。来源指纹变化只触发复核，不自动证明过时；hash 未变也不证明外部服务、动态 fixture 或权限未变，需 execution doctor/现场数据另证。不要新增 freshness registry、case parser 或全项目扫描器。

| 变化类别 | 传播与更新 | 保留的边界 |
|---|---|---|
| 需求/AC 语义更改 | 先核实需求权威来源与适用版本 → 受影响义务 → test-groups 的 expected/oracle_ref 与 case revision → surface-manifest 入口/状态映射 → 下一轮 strategy 选择 | 只有被证实改变的预期可改；当前产品的新输出、开发者说“修好了”不是需求批准 |
| 入口/状态/权限更改 | surface-manifest 的受影响 entry/角色/状态迁移 → 关联 case 的前置/动作/风险 → env-config 的 recipe 与未执行入口缺口 | 不只扫描后端路径；没有行为依据时保留 expected/oracle |
| 工具/selector/平台更改 | env-config 的 recipe revision、能力/环境范围 → 相关入口的可执行性待复核 → execution 的代表路径 pilot → 下一轮选择 | 不自动改产品 expected；selector 不可达是工具 gap，未经产品取证不报逻辑 Bug；新平台为 NOT_RUN |
| oracle/参考实现更改 | 固定来源差异与适用版本 → 对账需求与允许差异 → 冲突留待调查 → 相关 case 的 oracle 复核 | 不批量接受新输出或自动刷新 golden；未经规范依据不能让新 oracle 吞掉已知缺陷 |
| 同行为纯重构 | 更新 impact-map/source 引用，核对 surface/case 关系，选择定向回归 | 保留 expected 与 oracle；不能仅因文件移动重写所有断言；疑似行为变化仍 unknown，继续调查 |

`case_id` 不重编号。实际 case 合同改变才增加 revision；映射变化可只更新映射。case → recipe 沿用 `environment_ref: "test-root:env-config.md#<recipe_id>"`，runner_ref 仍指实际测试入口，不增 recipe_ref。recipe 在 env-config 的显式锚点、具名标题和 recipe_revision 下维护，不复制到新目录。旧自由文本 case 可写同样引用。

### 3a.2 复核记录与历史证明

每项写在既有 update changelog、自己的 run progress/strategy/feedback 或 coordinator merge 记录内；知识侧在 test-groups 或 env-config 的 Proof status 附复核说明。不建长期状态库。最小信息：

```text
Review reason: 来源 before → after、变化类别、适用范围、已知未知项
Affected refs: requirement/feature/entry/state/case/oracle/recipe 的具体引用与 revisions
Existing evidence: 原 run/artifact locator + 原 subject/environment/entry + 原 revisions
Owner / next: 谁补来源/改知识/执行 pilot/回归；范围、完成条件与阻塞
Scope: case <ID> revision <N>; recipe <ID> revision <N>
Design: AUTHORED; unresolved: 具体原因 / none
Structure: NOT_CHECKED / 实际 checker 输出引用（只证明结构）
Execution proof: NOT_RUN / 原 run 引用及原适用范围；当前范围缺口单列
Detection proof: NOT_RUN / faulty run + correct-control run + fault/predicate
Current review: required: 变化来源与受影响引用
```

这里是文档示意，不是实际 run 或 results.status。来源不完整的历史反馈保持候选义务，不能把 AUTHORED 说成 confirmed/reproduced。结构 `valid` 不证明 oracle 正确、实际可运行或能检测缺陷。

原 run 继续说明当时结果，原始失败证据保留；旧 proof 不原地变成新版本通过。`current-within-proof-scope` 只有真实 proof 且版本、平台/环境、入口与 case/recipe revisions 相符才可写。历史 proof 可与 `required` 并列；recipe pilot 只证明该路径可操作，不证明 case 检测能力。删除/合并重复 case 前保存旧 ID → 保留 ID/废弃理由/来源/历史 run 去向，不删除历史失败或全套重编号。

recipe/selector/工具能力、平台 build 或环境身份范围改变后，安排明确 execution 阶段的代表路径 pilot。进入 execution 后加载 `references/procedures/product-operation.md`，按 `references/test-execution-workflow.md` 的 stage 0 完成 launch/doctor/drive-and-wait/observe/cleanup；确认目标身份、observer 正控制、相关入口范围和清理后证据存活。pilot 结果保留实际 build/环境/入口/case/recipe revisions，未执行入口继续保留缺口。update 与 init 不启动产品、不跑产品测试，也不通过 helper 安装依赖；只读设计结构 checker 不属于产品执行。依赖尚未合入时只留待执行项，不调用不存在的 checker/procedure，不造 stub。

修复知识不关闭 Bug/escape。沿用 test-execution 的修复完整性门：原症状、保持项、相邻不变量、替代缺陷反例和回归均需实际复测；新失败另记 finding，不能靠改 expected 或 recipe 把 release gate 转绿。

### 3b. Protocol 项目纪律更新

走 protocol-update 的验证流程（自动验证 → 分级审批）：
- 矛盾检测
- 降级检测（新规则是否削弱旧规则）
- 范围检查（是思维还是执行）
- 空话检测
- 行数检查（项目纪律段 ≤5 行）
- 保存全文快照到 protocol-versions/

### 3c. Workflow / Hook 修改提议

经验指向执行步骤或 Hook 拦截 → 不直接修改，而是：
- 记录到 `code/roadmap.md` 的候选列表
- 报告给用户："这条经验建议修改 test-execution-workflow / 新增 hook，需要人审核"

### 3d. 材料处理（信号 6）

| 材料类型 | 影响的文件 |
|---------|-----------|
| 新 API 规范 | surface-manifest + test-groups + impact-map |
| 新错误码表 | test-groups（EXPECT_PATTERN） |
| 新 PRD | test-groups（BDD 场景，加载 references/procedures/bdd-scenarios.md） |
| 新 SLA / 性能指标 | test-groups（pass/fail 判定标准） |
| 新架构图 | impact-map（路径→组映射） |
| 新测试账号 | env-config + test-groups 运行条件解除 |
| 合规要求更新 | test-groups（合规必测标注） |

---

## Step 4：一致性检查

写入后检查文件间是否一致（见 test-execution-workflow.md 一致性检查段）：

```
□ protocol ↔ test-execution-workflow（新规则和执行纪律不矛盾）
□ project-profile ↔ Provider 输出（id/version/hash/capabilities/path_scope 一致）
□ source-model ↔ test-groups/impact-map/gates（项目映射闭合；动态 source-map 不是人工 SSOT）
□ 低置信度/Provider error 仍保留 hard gate，并按 expand-safe-default 扩围
□ test-groups ↔ impact-map（新测试项有没有对应的映射）
□ known-issues ↔ feedback-rules.json（lessons 和 suppress 不冲突）
□ surface-manifest ↔ test-groups（feature/entry/角色/状态是否映射，未执行入口是否保留缺口）
□ case expected/oracle ↔ 需求版本（仅经证实的语义更改可调整预期）
□ environment_ref ↔ env-config recipe 锚点/revision（runner_ref 不混用）
□ 当前复核 ↔ 历史 proof 范围（四个完成度分开，历史 artifacts 不改写）
□ feedback 候选 ↔ 抑制规则（未归因、无依据的“误报”不得进入 suppress）
```

对新增/变更的 `test-groups.md`，加载 `references/test-design-contract.md`，使用本次实际加载的 Skill 根与已解析的 TEST_ROOT 运行只读结构检查：

```sh
python3 <skill-root>/scripts/validate-test-design.py --test-root <resolved-root> --format json
```

只调用现有 M1 checker，不另写 parser，不执行命令块、不 import 被测项目代码、不联网。由有权限角色将完整 JSON stdout、stderr、实际命令、退出码和输入 revisions/digests 留在已有 update/strategy 记录中；活跃 Tester 可存到自己 run 的 `artifacts/design-structure-check.json`，并在自己的 progress/strategy 中引用这个真实输出路径。非活跃维护使用现有 update 记录的附件位置，不新增常驻状态库。

从实际 JSON 的 `scope/status/errors/warnings/case_ids` 记录检查结果：

- 退出 0 且 `scope=design_structure/status=valid`：合同结构有效；`warnings` 中的 unresolved、引用内容/anchor/revision 未验证等缺口仍逐项保留 owner/下一步，不是语义通过或环境可执行。
- 退出 0 且 `status=not_adopted`：旧自由文本未采用可选合同；不说结构已验证，也不因缺新字段阻断历史结果。
- 退出 1 / `status=invalid`：`errors` 指定的设计结构错误待修，不能改写产品 verdict 或放宽既有 hard gate。
- 退出 2：文件/参数/schema 等操作错误，保留输出/命令并修调用条件；不是产品 Fail，也不得用空输出替代有效检查。

输出本身及错误/警告 locator 必须可追溯；缺输出/读失败保持 `Structure: NOT_CHECKED` 和原因。将实际输出引用写入对应 case/recipe 的 Structure 说明，仅限本次输入版本；冻结 before/after 或历史 run 原件保持不变，在当前维护记录附新检查事实。结构检查不运行产品，也不授予 oracle 正确、pilot、实际执行或故障检测证明。

---

## Step 5.5：Skill 升级（通用经验向上流——滚动当场审，排队是例外）

> 2026-06-11 机制修订。背景：旧"攒批排队等人审"模式实测停摆——队列积压 21 条达 6 周无一审批
> （审批无触发钩子 + 批量越大启动成本越高的增强回路 + promote 与状态更新可分离导致账实不符 6 条）。
> 修订为：**当场审为默认，排队为例外，水位红线兜底，promote 原子化防账实分离。**

```
对 Step 2 中判定为 Q2="通用" 的每条经验：

1. 已经写入项目文件（Step 3a/3b）→ 当前项目立即受益 ✓

2. 低风险目标（design-rationale.md）→ 直接写入，不排队（规则不变）

3. 中风险目标（workflow / templates）→ **当场展示给用户请求 verdict**（用户就在会话里，
   单条 30 秒）：
   - 批准 → 立即执行"promote 原子三步"（见下）
   - 要改 → 改后执行
   - 用户说"稍后再议" → 才进入队列排队（标题+来源+目标+风险+内容+证据，状态 pending）
   - 一次最多当场审 3 条；超出部分排队并在报告中列明

4. 高风险目标（protocol-base / red lines）→ 一律排队，审批需"用户确认 + L2 审计"（规则不变）
```

**水位红线**：执行 Step 5.5 前先数队列 pending 条数。**pending ≥ 5 → 必须先向用户弹出
待审清单处理（批/拒/稍后逐条过），清到 <5 才能继续入队**。先清后加——宁可本次 update
慢一点，不允许队列再次积压成"专门会议级"工作量（22 条积压 = 永远不会开的会）。

**Promote 原子三步**（任何批准后的写入，三步必须在同一动作内完成，不允许分离）：

```
① 写入目标 skill 文件
② 更新队列条目状态（promoted / promoted-modified + 日期 + 实际落点）
③ git commit（skill 仓库）
```

状态取值新增 `already-present`：grep 发现内容已在 skill 中（历史上有 6 条这种账实不符）
→ 不重复写入，状态记 already-present + 所在位置。它和 promoted 是两种不同事实，不得混用。

**Agent 可以做的**：直接写 design-rationale；当场审批准后的 medium 写入（原子三步）；追加排队
**Agent 不能做的**：未经当场 verdict 或队列审批写 workflow/templates；任何情况下自行写
protocol-base / SKILL.md red lines

审批分级表见 `references/pending-skill-upgrades.md`。

---

## Step 6：报告

向用户展示所有变更，按分流目标分组：

```
Update 完成。处理了 <N> 条经验：

知识文件更新：
  ✓ impact-map: +1 条映射（auth → A 组，inferred-from-history）
  ✓ known-issues lessons: +1 条（"daemon 包装错误码，不信外层 hint"）
  ✓ env-config: +1 条注意事项（"C++ baseline 端口 22222 是二进制协议不是 REST"）

Protocol 项目纪律：
  ✓ +1 条（"daemon 包装所有 backend 错误码——永远不信外层 error message，必须查 debug log 原始码"）
  审批方式: auto-validated（新增项目纪律）
  快照: protocol-versions/v1.2.0.md

分流到其他位置：
  → "开测前检查 C++ baseline 端口类型" — 不进 protocol（执行步骤），已加入 env-config 注意事项
  → "results.json 应该检查非标 ID" — 不进 protocol（Hook 职责），已有 results-validation hook

Skill 升级处理：
  → 当场审核并完成: +N 条（medium；记录用户 verdict + 落点 + commit）
    "单次观测不定论" → strategy-workflow accuracy rules（approved / promoted）
  → 延后排队: +M 条（仅用户明确“稍后再议”或 high risk）
    "全绿=漏测信号" → pending-skill-upgrades（high；等待用户确认 + L2）
  → design-rationale.md: +N 条直接写入（low risk）

未写入（需确认）：
  ? "frozen_cash 暂态值不能单次采样下结论" — 通用还是项目特有？
    → 如果通用：按风险分级；medium 当场审，high/明确延后才排队；项目纪律同步落地
    → 如果特有：加 known-issues lessons
```

---

## update vs feedback vs reflect vs protocol-update

| 命令 | 定位 | 何时用 |
|------|------|--------|
| **update** | **统一入口** — 所有测试经验的分流器 | 测试完成后、发现新经验时、收到新材料时 |
| feedback | **专项** — 开发者对某个测试项的判定 | 开发者说"这是 not-a-bug" |
| reflect | **历史分析** — 从多次运行中提取趋势 | 版本切换时、累积 5+ 次运行后 |
| protocol-update | **精确** — 只改 protocol（跳过分流） | 明确知道要改 protocol 时直接用 |

**大多数情况下用 update**。只有明确要改 protocol 时才用 protocol-update 跳过分流。

---

## 不要做的事

- ❌ 不要让用户判断"这条经验该走哪个命令"—— update 自动分流
- ❌ 不要把执行步骤塞进 protocol —— 分流树 Q1 会拦
- ❌ 不要把空话写入任何文件 —— Q4 检查具体性
- ❌ 不要直接修 feedback-rules.json —— 走 feedback 命令
- ❌ 不要把推测写成 verified —— 标 `[未验证]`
- ❌ 不要收到材料只存着不分析 —— 立刻检查对所有相关文件的影响
- ❌ 不要在没有用户 verdict 时修改 workflow / templates；medium 先当场展示，批准后按
  “目标写入 + 队列状态 + commit”原子三步落地
- ❌ 不要自行修改 protocol-base.md / SKILL.md red lines；high risk 一律排队并需用户确认 + L2
- ✅ 用户明确“稍后再议”或超过当场审核上限时，可以追加 pending 提议
- ✅ 可以直接写入 design-rationale.md（Tier 3 参考文档，零风险）

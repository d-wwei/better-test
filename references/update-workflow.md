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

按信号类型直接写入对应文件：

| 信号类型 | 写入文件 | 验证 |
|---------|---------|------|
| 新测试组 / 新测试项 | test-groups.md | 4 问检查 |
| 新影响映射 | impact-map.md | 来源必填，无依据标 `[未验证]` |
| Flaky 发现 | **测试期间**：run 目录内 progress.md 关键发现段；**非测试期间**：known-issues.md Flaky 段 | 稳定性评分 |
| 经验教训 | **测试期间**：run 目录内 progress.md 关键发现段；**非测试期间**：known-issues.md lessons 段 | 证据级别 ≥ confirmed |
| 覆盖缺口 | **测试期间**：run 目录内 summary.md；**非测试期间**：status.md 覆盖缺口段 | 标明风险和建议测试组 |
| 新材料 | 对应文件（见下方材料处理表） | 立刻分析影响 |
| 环境发现 | env-config.md | **立即更新**——新账号/特殊行为发现时当场写入，不等测试结束。等到结束补时细节已丢失 |
| surface 变化 | surface-manifest.md | 新增标"未覆盖"，删除标"废弃" |

> **测试期间 vs 非测试期间**：如果当前有活跃 tester（`.active-sessions/` 有 session 文件），Flaky/经验/覆盖缺口写到 run 目录内，由 `/better-test merge` 或单 tester 完成后合并到项目级文件。如果不在测试期间（如会话初始化时跑 update），可以直接写项目级文件。

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
| 新 PRD | test-groups（BDD 场景，加载 procedures/bdd-scenarios.md） |
| 新 SLA / 性能指标 | test-groups（pass/fail 判定标准） |
| 新架构图 | impact-map（路径→组映射） |
| 新测试账号 | env-config + test-groups 运行条件解除 |
| 合规要求更新 | test-groups（合规必测标注） |

---

## Step 4：一致性检查

写入后检查文件间是否一致（见 test-execution-workflow.md 一致性检查段）：

```
□ protocol ↔ test-execution-workflow（新规则和执行纪律不矛盾）
□ test-groups ↔ impact-map（新测试项有没有对应的映射）
□ known-issues ↔ feedback-rules.json（lessons 和 suppress 不冲突）
□ surface-manifest ↔ test-groups（新接口有没有对应测试项）
```

---

## Step 5：报告

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

未写入（需确认）：
  ? "frozen_cash 暂态值不能单次采样下结论" — 通用还是项目特有？
    → 如果通用：加 protocol 项目纪律
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
- ❌ 不要自行修改 skill 级 templates.md —— 通用原则升级必须人操作

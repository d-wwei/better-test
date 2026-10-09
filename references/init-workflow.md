# Init Workflow

首次为项目建立测试知识时执行。目标：用最少时间识别测试结构，生成可操作的测试组定义和影响映射。

**init 操作边界**：只读取被测系统已有材料，并写测试知识/知识骨架。材料里的 launch、
install、doctor、pilot、测试命令只记录，不执行；也不能通过 `--help`、配置 loader、
package scripts 或 helper 间接启动产品、安装依赖、导入产品代码或运行测试。优先读取已有
help 快照、schema、脚本文本、工具声明和 CI 配置；缺信息标 `UNKNOWN`，首次真正操作留到
明确 execution 阶段。生成知识不表示工具可用、环境就绪或功能已覆盖。

## Step 1: 测试场景分类

读 `.better-work/shared/index.md`（如存在）+ 项目根目录的测试目录 + CI 配置 + README 中的测试章节。判断属于哪类：

| 项目类型 | 识别信号 | 测试侧重 |
|---------|---------|---------|
| 库 / SDK | `tests/` + `pytest.ini` / `Cargo.toml [test]` / `package.json scripts.test` | 单元测试矩阵、API 兼容性、版本兼容矩阵 |
| Daemon / 服务 | bin + 端口监听 + `--help` 子命令 | 启停链路、健康检查、E2E REST/TCP/WS、长连接稳定性 |
| CLI 工具 | bin + subcommand 树 | 子命令矩阵、参数变体、stdout/stderr/exit 三维断言 |
| API / Web 服务 | routes + middleware | endpoint 矩阵、auth 链、错误响应、rate limit |
| 数据 pipeline | DAG + transformers + schema | fixture 数据、schema 演进、幂等性、回滚 |
| Frontend SPA | components + 状态管理 | 组件单测、e2e、跨浏览器 |
| Mobile App (iOS / Android) | `.xcodeproj` / `Podfile` / `build.gradle` / `AndroidManifest.xml` / Flutter `pubspec.yaml` / React Native `metro.config.js` | 设备矩阵（屏幕尺寸×OS 版本）、UI 自动化（XCUITest / Espresso / Detox）、App 生命周期（后台/前台/推送唤醒）、权限弹窗、离线模式、应用商店合规 |
| Desktop App (macOS / Windows / Linux) | Electron `electron-builder` / Tauri `tauri.conf.json` / `.app` bundle / WPF `.csproj` / Qt `CMakeLists.txt` | 安装/升级/卸载流程、系统权限（沙盒/UAC/Keychain）、多窗口交互、跨 OS 兼容、原生 API 集成（文件系统/通知/托盘） |
| 浏览器扩展 | `manifest.json` (MV2/MV3) + content scripts + background/service worker | 跨浏览器兼容（Chrome/Firefox/Safari）、content script 注入、权限声明、扩展商店审核、与宿主页面隔离 |
| 测试工具 / 测试基础设施 | 自身是 tester + `lib/groups/` 或类似子目录暴露测试套件给用户 + 无主产品被测（tester 就是产品） | 暴露的测试组作为 `test-groups`；自己的单元测试少；关注 integration 模式、用户配置矩阵、fixture 场景 |
| 混合 | 以上都有 | 按主导组件分类，其他组归为辅助 |

## Step 2: 信号驱动探索

不做"读完所有测试代码"。按以下信号源采集：

### 信号源 A：测试目录结构（已有保护与可复用载体）

```
列出 tests/ 或等价目录下的子目录和文件
观察命名规律 → 推断测试组划分（如 tests/unit/、tests/integration/、tests/e2e/）
观察文件数 → 估算每组规模
```

### 信号源 B：CI/CD 配置（运行命令权威源）

```
.github/workflows/*.yml / .gitlab-ci.yml / Jenkinsfile / Makefile 中的 test 步骤
提取：跑哪些命令、依赖什么环境变量、矩阵跑什么版本
这是"如何运行"的最可靠来源，不要凭猜测写
```

### 信号源 C：版本变更源（strategy 的输入）

```
- CHANGELOG.md / RELEASE_NOTES.md → 历史变更记录
- git tags → 版本号格式
- 已有二进制 --help / --version 快照 → 可作为版本输入；init 不运行二进制取快照
- 主包/主二进制是什么 → strategy 的影响分析锚点
```

### 信号源 D：已有测试历史（如有）

```
如果存在 ~/.<project>-test-history/ 或类似目录 → 迁移到 ${TEST_ROOT}/history/
如果没有 → 创建空 history/ 目录 + 初始化 _meta.json + feedback-rules.json
```

### 信号源 E：bug tracker 中的近期 issue（可选）

```
最近 3 个月的 bug issue → 推断常见 fail 模式
但只作为参考，不直接写入 known-issues.md（缺少 test_id 锚点）
```

### 信号源 F：需求与接口定义（向用户收集）

信号源 A-E 是 agent 自己能采集的。信号源 F 需要用户提供——但这些材料对测试质量有决定性影响。

**init 阶段向用户提出 3 个核心问题**（不要一次要求 15 种材料，先问最关键的）：

```
在开始生成测试知识之前，以下材料能显著提升测试质量：

1. 有没有 API 规范？（OpenAPI/Swagger、proto 文件、接口文档）
   → 用于 Surface SSOT 枚举全部接口，是覆盖率对账的基础

2. 有没有 PRD 或验收标准？（需求文档、用户故事、Given-When-Then）
   → 用于需求驱动的测试设计，生成 BDD 测试场景

3. 有没有错误码表？（code → 含义 → 触发条件）
   → 用于精确的 pass/fail 判定，不再猜"这个 -400 是什么意思"

没有也没关系——agent 会从代码和目录结构推断。但有这些材料，测试组定义会更完整、断言会更精确。
```

如果用户提供了，额外采集的信息：

| 材料类型 | 用户提供时机 | 对哪些知识文件有帮助 |
|---------|------------|-------------------|
| **API 规范**（OpenAPI/proto/GraphQL schema） | init | Surface manifest（直接枚举）、test-groups（参数 + 响应结构）、impact-map（接口→模块映射） |
| **PRD / 验收标准** | init | test-groups（BDD 场景生成）、coverage（需求覆盖率） |
| **错误码表** | init | test-groups（EXPECT_PATTERN）、investigation（错误解读） |
| **参数约束文档**（字段类型/取值范围/枚举值） | init 或 strategy | test-groups（边界值测试用例生成） |
| **认证/授权模型**（角色/权限矩阵） | init 或 strategy | test-groups（权限测试矩阵） |
| **样本数据**（真实请求/响应示例，脱敏） | strategy | test-groups（fixture 基础） |
| **SLA / 性能指标**（响应时间/吞吐/并发） | strategy | test-groups（性能测试的 pass/fail 判定标准） |
| **测试账号清单**（类型 + 状态） | strategy | execution（凭证收齐检查） |
| **架构图 / 服务依赖** | init | impact-map（服务间依赖推断） |
| **数据库 schema** | init | test-groups（数据完整性测试） |
| **第三方依赖文档**（外部 API/rate limit/沙箱） | strategy | execution（环境约束） |
| **历史 bug 报告** | feedback | known-issues（风险区域标注）、impact-map（历史关联） |
| **日志格式文档** | 测试执行中 | investigation（调查阶梯中读 log 的依据） |
| **合规要求**（GDPR/金融监管） | init | test-groups（合规必测项，标记为不可跳过） |
| **官方/上游测试仓** | init 或 update | 加载 `references/procedures/reference-suite-intake.md`，生成来源身份、危险扫描和全量 case map |

**分阶段收集策略**：不在 init 一次全收。

| 阶段 | 收集什么 | 为什么这个时候 |
|------|---------|-------------|
| init | API 规范、PRD、错误码表、架构图、数据库 schema、合规要求 | 定义"被测对象是什么" |
| strategy 首次 | 测试账号、SLA/性能指标、样本数据、第三方依赖、参数约束 | 定义"怎么跑" |
| 测试执行中 | 日志格式文档 | 按需，遇到问题时收集 |
| feedback | 历史 bug 报告 | 有测试结果后做上下文补充 |

## Step 2.3: 功能、入口与状态调查（只读，先于旧用例明细）

测试目录说明已有保护，不能定义完整功能分母。先读批准需求/AC、公开契约、用户路径、
变更和已知事故的原始条件；形成来源支持的行为义务，再把现有用例作为对账输入。
如果前面已见测试目录/CI/历史摘要，记录这个输入切片限制，不能称为完全盲审。

调查先形成来源义务草稿，Step 3 建好 TEST_ROOT 知识骨架后增量写入既有
`surface-manifest.md`，保留原接口表，不另建 feature 数据库：

| 新增区段 | 必须记录的内容 |
|---------|----------------|
| 来源与边界 | locator + 条目、revision/digest、采集时间、适用范围、可靠性/冲突；版本不明写 unresolved 及原因 |
| 功能与入口 | 稳定 feature_id、entry_id、用户目标、正式入口（按钮/菜单/快捷键/API/CLI/SDK 等）、可观察结果、来源引用 |
| 角色与状态 | 稳定项目内状态引用/锚点、适用角色/权限、前置状态、合法/拒绝迁移、外部契约、允许与禁止副作用；复杂状态用小型迁移表 |
| 实现与已有保护 | 相关源码 locator、原 case ID/native selector；这是关联，不是正确性证明 |
| 待调查项 | UNKNOWN 的入口/状态/平台、为什么未知、可能风险、下一步材料和调查责任 |

同一事实只在地图保存一处，case 引用 feature/entry ID；不把每个源码函数都当用户功能。
地图只声明当前已知边界；没有记录某入口不等于入口不存在，不标无依据的 exhaustive。
若没有正式需求，标明参考兼容性、历史保证或待确认假设，不从当前实现抄预期。
已知入口即使共享后端仍分开记录；一个按钮 case 通过不能代表快捷键、只读角色或其他平台。

工具发现只读已有 capability 声明、CLI 文档、驱动配置和脚本文本；记录目标 identity、
owner、副作用范围与缺失能力到 `env-config.md`。可写操作 recipe 草稿，但 init 的
Execution proof / Detection proof 均为 `NOT_RUN`；不能伪造 runner 或 fixture。
加载 `references/procedures/product-operation.md` 的 Capability and tool choice / Recipe interface，
以及 `references/tool-operation-platforms.md` 的适用平台能力边界，只用于材料调查和 recipe
草稿。其中正控制、Launch、Doctor、Drive、pilot 与 Cleanup 的真正操作属于 execution，
init 不为补齐能力表调用这些操作，不因工具文件存在而写 available/ready。
具名 recipe、四类完成度与引用方式遵循 `docs/adr/0002-test-design-and-tool-operation.md`。
精确命令只在 env-config/tools 保存，地图引用其锚点，不复制命令。

## Step 2.4: 白盒能力发现（只读）

在读代码前先判断“能获得什么事实”，不要因为看见源码就默认 whitebox/full：

1. 查找已有 `project-profile.json`；存在则只读检查声明，或用本 Skill 的纯数据校验
   `validate-provider-output.py project-profile` 检查形状。init 不调用 Provider `probe` 或
   inventory/source-check helper；声明/脚本文本不是能力已实测，实际探测留到 execution。
2. 无 profile 时只读发现构建系统、源码根、VCS、native test/inventory/static-analysis 命令；
   通用 Rust/Cargo 项目可建议 `better-test.rust-cargo`，项目专属 gate/ledger 不写入通用配置。
3. 已有可信观察可区分 available / unavailable / unconfigured / error，并注明旧证据版本/范围；
   只有声明时保留 UNKNOWN/unconfigured，不用运行 probe 填满表。没有源码能力时
   保持原黑盒知识，不把 unavailable 误写成“项目不需要”。
4. 若用户批准启用 hybrid，按 `references/source-provider-contract.md` 生成项目 profile；
   Provider 默认只读、无网络、无外部写，profile 不含 secret 或个人绝对路径。
5. init 只生成/校验 profile 和知识骨架，不运行 source check 或业务测试；source map 是 strategy
   的 cache/run artifact，不在 init 中手工维护。

信号源 A–E 采集的是结构和元数据。对于有代码仓库的项目，读取测试代码本身能提取更丰富的信息（断言模式、fixture 依赖、环境要求）。

## Step 2.5: 代码读取策略

### 第一遍：签名扫描（始终执行）

对所有测试文件读取前 20 行（imports + 函数/类定义），提取：

- 文件→模块/测试组的归属
- import 链（哪些文件依赖了共享 fixture / base class）
- 模块间耦合度（哪些目录互相依赖，哪些完全独立）
- 文件总数和每组规模

### 呈现扫描结果并询问用户

基于第一遍结果，向用户展示结构概览并提供选择：

```
扫描完成：
  <N> 个测试文件，分布在 <M> 个目录/组中
  共享 fixture: <K> 个文件
  模块耦合: [高 / 中 / 低]

代码读取方式:
  a) 抽取要点 — 每组选 1-2 个代表文件深读，提取断言模式和约定（约 <X> 分钟）
  b) 全量读取 — 逐文件流式读取并提取，覆盖无盲区（约 <Y> 分钟）
  c) 跳过读取 — 仅基于目录结构和 CI 配置生成知识文件
```

耗时估算公式：
- 抽取要点：`组数 × 2 个文件 × 4 秒/文件`（加上共享 fixture 必读）
- 全量读取：`文件总数 × 4 秒/文件`（流式处理，提取后丢弃原文）

### 第二遍：按用户选择执行

**a) 抽取要点**

基于第一遍的结构信息选择深读文件：

| 选择优先级 | 文件类型 | 原因 |
|-----------|---------|------|
| 必读 | 共享 fixture / base class / conftest | 改它影响所有组，必须理解 |
| 每组 1 个 | git 修改频率中等的代表文件 | 稳定模式 = 成熟约定 |
| 每组 1 个 | 被 import 最多的文件（高 fan-in） | 揭示核心测试模式 |

采样后做**覆盖度自检**——对照 test-groups.md 每个必填字段检查是否有来源。≥2 个字段缺失的组追加采样。未采样到的目录在 status.md 标注为"采样盲区"。

**b) 全量读取**

流式逐文件处理，每个文件：读取 → 提取结构化信息 → 丢弃原文。context 中只保留累积的提取结果，不保留代码原文。用户选择了全量读取就读完所有文件，不做提前停止。

**遍历顺序：共享优先 + 深度优先**

1. 先读共享 fixture / base class / conftest（第一遍已识别）— 建立全局约定认知
2. 再按目录逐组深度优先遍历 — 读完一个组的所有文件再进入下一个组

不用广度优先（每组各取一个再回头），因为频繁切换组上下文会降低提取质量。深度优先让每个组的知识提取是连续完整的。

每个文件定向提取：
- 属于哪个测试组
- setup/teardown 依赖什么环境
- 断言验证什么字段（→ test-groups.md 的关键字段断言）
- import 了哪些模块（→ impact-map.md 的映射依据）
- 命名/注释约定

**c) 跳过读取**

不读测试代码，仅基于 Step 2 的信号源 A–E 生成知识文件。test-groups.md 中缺少代码级信息的字段（关键字段断言、fixture 依赖）标 `[未验证-未读代码]`。

### 小项目快速路径

测试文件 < 10 个时，跳过询问，直接全部读入 context（无需流式处理）。

### 备注：超大项目的并行优化

对 500+ 文件且第一遍确认存在明确低耦合模块集群的项目，可考虑对独立模块分发子 Agent 并行做流式提取。但子 Agent 上下文窗口更小，需确认每个集群的文件数在可处理范围内。这是条件性优化，非默认路径。

## Step 3: 生成知识文件

### 3.0 确保 shared/ 存在

在生成 `test/` 文件之前，先检查 `~/.better-work/<project>/shared/` 状态：

**若 `shared/` 不存在**（用户未装 better-code 或其他 skill）→ 创建最小版 `shared/index.md`，内容**仅来自 Step 1 已采集的信息**（不额外探索）：

```markdown
# <Project Name>

<一句话：项目类型 + 技术栈（从 README 前 50 行 + 包管理器配置提取）>

## Testing

- 项目类型: <Step 1 分类结果>
- 测试侧重: <对应的测试侧重>
- 测试目录: <tests/ 或等价路径>
- 测试命令: <从 CI 配置提取的主要测试命令>
```

注意：这是最小版，只包含项目身份 + 测试信息。当 better-code 后续 init 时，会用完整版**替换**（包含 Module Map、Must-Know Rules、Danger Zones 等完整章节），但会**保留** `## Testing` 章节的内容。

**若 `shared/index.md` 已存在**（better-code 或其他 skill 先创建）→ 不覆盖，仅检查是否有 `## Testing` 章节：
- 有 → 跳过
- 无 → 在文件末尾追加 `## Testing` 章节（内容同上）

不创建 `shared/map.md` 或 `shared/progress.md`——这些是 better-code 的职责。

### 3.0.5 预建目录骨架

在生成任何知识文件之前，先建好完整目录结构。这样 agent 在后续测试过程中有明确的"该往哪放"指引，不会随手建新目录。

```bash
# 测试知识
mkdir -p test/tools test/reference
# Protocol 版本管理
mkdir -p test/protocol-versions
# tester 注册中心（多 agent 并行隔离）
mkdir -p test/testers
# 测试历史
mkdir -p test/history
touch test/history/bugs-index.md
# post-ship escape 人类视图；escapes.json 按 templates.md 初始化，不能只建空 JSON
touch test/escapes.md
```

| 目录 | 用途 | 边界 |
|------|------|------|
| `test/tools/` | 跨版本复用的测试脚本（如 surface-walk.sh、mcp-client.py） | 只放可执行脚本，不放文档 |
| `test/reference/` | 暂存区：无法归入版本目录的参考资料 | 放入时必须在文件首行写明原因；积累后细分 |
| `test/testers/` | tester 注册中心，每个 tester 独立子目录 | init 只建空目录，具体 tester 由 strategy/checkpoint 自动注册 |
| `test/history/` | **只放测试运行产出和版本级材料** | 不放参考资料、测试脚本、项目级文档 |
| `test/history/<version>/input/` | 触发本版本测试的开发者输入（fix report、沟通记录） | 每版本一个 input/ |

### 3.1–3.8 生成 test/ 文件

启用 hybrid 时额外生成 `test/project-profile.json` 和项目级 `source-model.md`（名称可按项目
知识布局调整）。前者只声明 Provider/能力/信任边界/feature flags，后者只记录项目专属 unit、
risk、gate、native ledger 映射。通用合同仍引用 skill 的 schema，不复制到项目仓库。

按以下顺序生成（参考 `references/templates.md` 的质量标准）：

1. **`protocol.md`** — **项目级**测试认知约束（安全纪律 + 项目纪律口子）。L0 和思维纪律已在 skill 的 `protocol-base.md` 中，不重复生成。从模板中按风险等级（严格/标准/宽松）选择安全纪律版本，询问用户。**无人值守 fallback**：默认 **标准版**，Step 5 报告中明示。项目纪律段初始为空（由 `/better-test protocol-update` 积累）
2. **`test-groups.md`** — 先固定 Step 2.3 的来源义务，再与信号源 A + B 的既有保护对账，结合 F 复用或生成。每组包含：名称、覆盖范围、运行命令、运行条件（环境变量、依赖、是否需要真账户）；保留原 test ID。仅有元数据、shape 或退出码不能声称业务义务已覆盖
3. **`escapes.json` + `escapes.md`** — 从模板初始化空 escape 账本。JSON 是 SSOT，
   Markdown 是人类视图；写后运行
   `python3 <skill-root>/scripts/validate-escapes.py test/escapes.json`

**新增测试项检查（Tier 1 核心流程）**：每个测试项写入 test-groups.md 前，必须过 4 问：

```
1. 调用的是功能本身还是仅检查元数据？→ 元数据测试标"元数据"，不计入功能覆盖率
2. 返回值里哪个具体字段证明功能真工作？→ 写入 EXPECT_PATTERN
3. 失败时能分辨"参数错 / 服务挂 / 功能 bug"吗？→ 确保测试有诊断价值
4. 跑 1000 次都该验证同一个关键字段吗？→ 确保断言稳定
```

如果用户提供了 API 规范（信号源 F），从规范中提取参数约束生成边界值测试；如果有 PRD，用 Given-When-Then 格式生成场景测试（详见 Tier 2 扩展流程 `references/procedures/bdd-scenarios.md`）。

**质量维度评估（生成 test-groups 后执行一次）**：对照 14 维度清单逐项判定
`强（已有载体）/ 检查单（折叠进现有流程）/ 建组（空白且高风险）/ 不适用`，
结论写入 test-groups.md 头部的"维度覆盖声明"段。原则：**不是每个维度都建组**——
已覆盖的只补声明，轻量的折叠为检查单，防止维度清单变成官僚负担。

```
1 功能正确性  2 鲁棒性/可靠性  3 一致性（多入口同数据）  4 可恢复性（脏状态/中断恢复）
5 性能效率   6 安全          7 可观测性（指标真实性/日志质量/错误信息准确性）
8 数据正确性（精度/币种/时区/大整数）        9 兼容性/升级（旧数据→新版本/降级）
10 配置/安装（mode flag 矩阵）              11 并发/时序（多客户端/agent 节奏）
12 易用性/DX（踩坑即产品反馈）              13 合规/审计（日志完整性/权限位）
14 i18n/本地化
```

空白维度的典型信号：该维度的 bug 只在用户报告中出现、从未被测试组拦截过。
3. **`impact-map.md`** — 从信号源 A 的目录划分 + 信号源 B 的 CI 矩阵推断初始版本。若无依据则只列已知关键词，标 `[未验证]` 待 update 累积
4. **`known-issues.md`** — 初始化为空模板（待 feedback 累积）。如果信号源 E 有强信号可写"待验证条目"
5. **`env-config.md`** — 测试环境配置。从信号源 F（用户提供的材料）+ 信号源 B（CI 配置）中提取：测试账号、服务地址、环境变量、时间依赖、不可逆操作清单、使用注意事项。没有用户提供的信息则写空模板（各段标"待补充"）。随时可通过 update（信号 6）补充
6. **`surface-manifest.md`** — 从信号源 F、已有 help 快照、路由/导出声明及 Step 2.3 生成当前已知接口和功能/入口/状态区段；适用于 UI、库/SDK、API、Daemon、CLI、MCP，不再因纯前端或纯库而跳过。保留既有接口表和原 ID；旧项目增量补区段。初始运行覆盖全标"未执行"，设计映射与实际运行分开；未知边界保留 UNKNOWN，不能凭扫描数量声称全部覆盖
7. **`status.md`** — 自动生成的初始版本（仅项目概况 + 测试组列表，未跑过测试时无运行记录）
7. **`progress.md`** — 初始化为空模板
8. **`history/`** — 创建目录 + 两个 JSON 文件（均含 `schema_version: 1` 字段便于将来迁移）：
   - `_meta.json` — schema: `{schema_version: 1, project: "<project-name>", test_target: "<被测对象描述>", created_at: "<YYYY-MM-DDTHH:MM:SS±HH:MM>"}`
   - `feedback-rules.json` — schema: `{schema_version: 1, suppress: [], known_behaviors: [], lessons: []}`

## Step 3.5: 同步知识 repo 的 .gitignore 标准模板

同步 `~/.better-work/<project>/.gitignore` 的标准内容。

**canonical 源**：`~/.claude/skills/better-work/references/gitignore-template.md`（若 better-work 已装）。若未装，使用内联 fallback：

```gitignore
# Progress & session state
progress.md

# Platform adapter outputs (regenerated from source)
adapters/

# Sensitive files (NEVER commit)
*.pem
*.key
credentials*
*.env
.env.*

# OS/IDE noise
.DS_Store
Thumbs.db
*.swp
.idea/
.vscode/
```

注：此 fallback 与 better-work 的 canonical `gitignore-template.md` 保持一致（v1.3.1+）。若未来 canonical 增项，此处需同步（maintainer 责任）。

策略：文件不存在则创建；已存在则验证每行 template 项，缺则 append（不覆盖用户自定义行）。

## Step 3.7: 同步全局 registry

若 better-work 已装：registry 条目由 `better-work init` 主动维护，按 schema（见 `~/.claude/skills/better-work/references/registry-schema.md`）更新 `last_subskill_init` 字段。

若 better-work 未装（standalone 模式）：在 `~/.better-work/registry.yml` 中创建/更新最小 v1 条目：

```yaml
schema_version: 1
projects:
  <project-name>:
    path: <project-root 绝对路径>
    initialized_by: better-test
    created_at: <YYYY-MM-DDTHH:MM:SS±HH:MM>
    subskills:
      - better-test
```

若 `registry.yml` 已存在但无 `schema_version` 字段，prepend `schema_version: 1` 后再更新条目。

## Step 4: 注入到当前平台

参考 `references/adapters.md`（完整的平台适配策略）。此步骤只做 Layer 2（protocol 注入到项目配置），Layer 1（skill 注册）由 `install.sh` 完成。

### Claude Code

项目 `CLAUDE.md`（若不存在则创建新文件）追加：

```
@.better-work/shared/index.md                          # 项目知识入口
@~/.claude/skills/better-test/protocol-base.md         # skill 级通用原则（自动跟随 skill 升级）
@<TEST_ROOT>/protocol.md                               # 项目级扩展（使用仓库相对 resolved root）
```

注入策略（Step 3.0 已确保 `shared/index.md` 始终存在）：

逐行检查，缺少的追加。已存在的不重复。三行都是必须的。

### Codex CLI

项目 `AGENTS.md`（若不存在则创建新文件）嵌入 protocol.md 内容：

```markdown
<!-- BETTER-TEST:BEGIN -->
[读取 ${TEST_ROOT}/protocol.md 的实际内容嵌入此处]

知识文件位置（按需读）:
- ${TEST_ROOT}/test-groups.md
- ${TEST_ROOT}/impact-map.md
- ${TEST_ROOT}/known-issues.md
- ${TEST_ROOT}/status.md
<!-- BETTER-TEST:END -->
```

注入策略：

1. AGENTS.md **已有** `<!-- BETTER-TEST:BEGIN -->` → 定位 BEGIN/END 段**整体替换**
2. AGENTS.md **尚无** → 追加整个 BEGIN/END 段

### 其他平台

按 `references/adapters.md` 中各平台对应小节执行。多平台同时存在则全部注入。

## Step 5: 报告

向用户展示：

- 项目测试场景分类结果
- 识别到的测试组（数量 + 简要列表）
- impact-map 的初始覆盖率（已映射关键词数 / 推测总关键词数）
- 注入到了哪些平台配置（CLAUDE.md / AGENTS.md / GEMINI.md / .cursor/rules/）
- 建议下一步：跑一次 `/better-test strategy` 看推荐策略

## 深度控制

| 项目规模 | 第一遍（签名扫描） | 第二遍（用户选择） |
|---------|-------------------|-------------------|
| < 10 个测试文件 | 跳过，直接全读 | 自动全量读取（无需询问） |
| 10-200 个 | 扫描全部文件前 20 行 | 询问用户：抽取要点 / 全量读取 / 跳过 |
| > 200 个 | 扫描全部文件前 20 行 | 询问用户（同上，全量读取耗时较长会提示） |
| > 500 个 + 低耦合集群 | 扫描全部文件前 20 行 | 询问用户（同上，额外提示可选子 Agent 并行） |

## 不要做的事

- ❌ 不要在 init 时跑测试以"摸清当前状态"——strategy 选择计划，明确 execution 阶段才操作；init 只读被测系统并生成知识
- ❌ 不要把测试代码内容大段抄到 test-groups.md——只摘要"这组测什么 + 怎么跑"
- ❌ 不要凭直觉写 impact-map.md 的关键词映射——没依据的标 `[未验证]` 等 update 阶段验证

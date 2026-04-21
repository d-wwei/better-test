# Init Workflow

首次为项目建立测试知识时执行。目标：用最少时间识别测试结构，生成可操作的测试组定义和影响映射。

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

### 信号源 A：测试目录结构（最高价值）

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
- 二进制 --help / --version → 可作为版本快照（用于 diff）
- 主包/主二进制是什么 → strategy 的影响分析锚点
```

### 信号源 D：已有测试历史（如有）

```
如果存在 ~/.<project>-test-history/ 或类似目录 → 迁移到 .better-work/test/history/
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

**分阶段收集策略**：不在 init 一次全收。

| 阶段 | 收集什么 | 为什么这个时候 |
|------|---------|-------------|
| init | API 规范、PRD、错误码表、架构图、数据库 schema、合规要求 | 定义"被测对象是什么" |
| strategy 首次 | 测试账号、SLA/性能指标、样本数据、第三方依赖、参数约束 | 定义"怎么跑" |
| 测试执行中 | 日志格式文档 | 按需，遇到问题时收集 |
| feedback | 历史 bug 报告 | 有测试结果后做上下文补充 |

## Step 2.5: 代码读取策略

信号源 A–E 采集的是结构和元数据。对于有代码仓库的项目，读取测试代码本身能提取更丰富的信息（断言模式、fixture 依赖、环境要求）。

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
# tester 注册中心（多 agent 并行隔离）
mkdir -p test/testers
# 测试历史
mkdir -p test/history
touch test/history/bugs-index.md
```

| 目录 | 用途 | 边界 |
|------|------|------|
| `test/tools/` | 跨版本复用的测试脚本（如 surface-walk.sh、mcp-client.py） | 只放可执行脚本，不放文档 |
| `test/reference/` | 暂存区：无法归入版本目录的参考资料 | 放入时必须在文件首行写明原因；积累后细分 |
| `test/testers/` | tester 注册中心，每个 tester 独立子目录 | init 只建空目录，具体 tester 由 strategy/checkpoint 自动注册 |
| `test/history/` | **只放测试运行产出和版本级材料** | 不放参考资料、测试脚本、项目级文档 |
| `test/history/<version>/input/` | 触发本版本测试的开发者输入（fix report、沟通记录） | 每版本一个 input/ |

### 3.1–3.8 生成 test/ 文件

按以下顺序生成（参考 `references/templates.md` 的质量标准）：

1. **`protocol.md`** — 测试认知约束。从模板中选择适合项目风险等级的版本（严格/标准/宽松），询问用户。**无人值守 fallback**（fork 会话 / CI / 无交互通道）：默认选 **标准版**，在 Step 5 报告中明示选择原因让用户可事后切换
2. **`test-groups.md`** — 从信号源 A + B + F 提取。每组包含：名称、覆盖范围、运行命令、运行条件（环境变量、依赖、是否需要真账户）

**新增测试项检查（Tier 1 核心流程）**：每个测试项写入 test-groups.md 前，必须过 4 问：

```
1. 调用的是功能本身还是仅检查元数据？→ 元数据测试标"元数据"，不计入功能覆盖率
2. 返回值里哪个具体字段证明功能真工作？→ 写入 EXPECT_PATTERN
3. 失败时能分辨"参数错 / 服务挂 / 功能 bug"吗？→ 确保测试有诊断价值
4. 跑 1000 次都该验证同一个关键字段吗？→ 确保断言稳定
```

如果用户提供了 API 规范（信号源 F），从规范中提取参数约束生成边界值测试；如果有 PRD，用 Given-When-Then 格式生成场景测试（详见 Tier 2 扩展流程 `references/procedures/bdd-scenarios.md`）。
3. **`impact-map.md`** — 从信号源 A 的目录划分 + 信号源 B 的 CI 矩阵推断初始版本。若无依据则只列已知关键词，标 `[未验证]` 待 update 累积
4. **`known-issues.md`** — 初始化为空模板（待 feedback 累积）。如果信号源 E 有强信号可写"待验证条目"
5. **`env-config.md`** — 测试环境配置。从信号源 F（用户提供的材料）+ 信号源 B（CI 配置）中提取：测试账号、服务地址、环境变量、时间依赖、不可逆操作清单、使用注意事项。没有用户提供的信息则写空模板（各段标"待补充"）。随时可通过 update（信号 6）补充
6. **`surface-manifest.md`**（条件生成）— Step 1 分类为 API/Daemon/CLI/MCP 类项目时生成。从信号源 F（API 规范）或 `--help` 输出或源码路由扫描枚举全部可测接口。纯库/前端项目跳过。初始版本覆盖状态全标"未覆盖"，待首次测试后更新
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

参考 `references/adapters.md`。Claude Code 示例：项目 `CLAUDE.md`（若不存在则创建新文件）追加：

```
@.better-work/shared/index.md         # better-code 创建的项目知识（如已存在）
@.better-work/test/protocol.md        # 测试认知约束
```

注入策略（Step 3.0 已确保 `shared/index.md` 始终存在）：

1. CLAUDE.md **已有** `@.better-work/shared/index.md` → 仅追加 `@.better-work/test/protocol.md`（如尚无）
2. CLAUDE.md **尚无** `@.better-work/shared/index.md` → 两行都追加

## Step 5: 报告

向用户展示：

- 项目测试场景分类结果
- 识别到的测试组（数量 + 简要列表）
- impact-map 的初始覆盖率（已映射关键词数 / 推测总关键词数）
- 注入到了哪些 CLAUDE.md / 平台配置
- 建议下一步：跑一次 `/better-test strategy` 看推荐策略

## 深度控制

| 项目规模 | 第一遍（签名扫描） | 第二遍（用户选择） |
|---------|-------------------|-------------------|
| < 10 个测试文件 | 跳过，直接全读 | 自动全量读取（无需询问） |
| 10-200 个 | 扫描全部文件前 20 行 | 询问用户：抽取要点 / 全量读取 / 跳过 |
| > 200 个 | 扫描全部文件前 20 行 | 询问用户（同上，全量读取耗时较长会提示） |
| > 500 个 + 低耦合集群 | 扫描全部文件前 20 行 | 询问用户（同上，额外提示可选子 Agent 并行） |

## 不要做的事

- ❌ 不要在 init 时跑测试以"摸清当前状态"——这是 strategy 的职责，init 只读知识
- ❌ 不要把测试代码内容大段抄到 test-groups.md——只摘要"这组测什么 + 怎么跑"
- ❌ 不要凭直觉写 impact-map.md 的关键词映射——没依据的标 `[未验证]` 等 update 阶段验证

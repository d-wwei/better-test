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

## Step 3: 生成 .better-work/test/

按以下顺序生成（参考 `references/templates.md` 的质量标准）：

1. **`protocol.md`** — 测试认知约束（≤15 行）。从模板中选择适合项目风险等级的版本（严格/标准/宽松），询问用户
2. **`test-groups.md`** — 从信号源 A + B 提取，每组包含：名称、覆盖范围、运行命令、运行条件（环境变量、依赖、是否需要真账户）
3. **`impact-map.md`** — 从信号源 A 的目录划分 + 信号源 B 的 CI 矩阵推断初始版本。若无依据则只列已知关键词，标 `[未验证]` 待 update 累积
4. **`known-issues.md`** — 初始化为空模板（待 feedback 累积）。如果信号源 E 有强信号可写"待验证条目"
5. **`status.md`** — 自动生成的初始版本（仅项目概况 + 测试组列表，未跑过测试时无运行记录）
6. **`progress.md`** — 初始化为空模板
7. **`history/`** — 创建目录 + `_meta.json` + 空 `feedback-rules.json`（schema: `{suppress:[], known_behaviors:[], lessons:[]}`）

## Step 4: 注入到当前平台

参考 `references/adapters.md`。Claude Code 示例：项目 CLAUDE.md 追加：

```
@.better-work/shared/index.md         # better-code 创建的项目知识（如已存在）
@.better-work/test/protocol.md        # 测试认知约束
```

如果 `.better-work/shared/` 不存在（用户未装 better-code），仅注入 `test/protocol.md`，不要替 better-code 创建 shared/。

## Step 5: 报告

向用户展示：

- 项目测试场景分类结果
- 识别到的测试组（数量 + 简要列表）
- impact-map 的初始覆盖率（已映射关键词数 / 推测总关键词数）
- 注入到了哪些 CLAUDE.md / 平台配置
- 建议下一步：跑一次 `/better-test strategy` 看推荐策略

## 深度控制

| 项目规模 | 预计耗时 | 探索深度 |
|---------|---------|---------|
| < 10 个测试文件 | 1-2 分钟 | 全部读，每文件提取被测对象 |
| 10-50 个测试文件 | 3-5 分钟 | 按目录分组，每组采样 1-2 个文件读全文 |
| 50-200 个测试文件 | 5-10 分钟 | 只看目录结构 + CI 配置，不读测试代码 |
| > 200 个 | 10-15 分钟 | 分模块逐步探索，init 只覆盖 CI 中明确跑的 top groups |

## 不要做的事

- ❌ 不要在 init 时跑测试以"摸清当前状态"——这是 strategy 的职责，init 只读知识
- ❌ 不要把测试代码内容大段抄到 test-groups.md——只摘要"这组测什么 + 怎么跑"
- ❌ 不要凭直觉写 impact-map.md 的关键词映射——没依据的标 `[未验证]` 等 update 阶段验证

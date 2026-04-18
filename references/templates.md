# Templates & Quality Standards

每个 `.better-work/test/` 文件的模板和质量标准。

---

## protocol.md（≤ 15 行）

测试认知约束。每对话通过 `@` 引用自动加载。**纯行为规则，零项目信息。**

按项目风险等级选模板：

### 严格版（金融、生产 daemon、长跑系统等高风险）

```markdown
# Test Protocol
## 测试铁律
- pass 必须基于返回值字段验证（如 `"power"`、`"warrant_list"`），不能只看退出码或"输出非空"
- skip ≠ pass，必须用 `~` 或 `[skip]` 醒目标注并附原因
- 同一条 flaky 测试连续 2 次不一致 → 不再默默重试，提交 `feedback deferred`
## 安全
- 不把账号密码写入任何文件（progress.md、history、feedback）
- 不对真账户做不可逆操作（下单、转账、销户）；只对模拟账户操作并立即回滚
## 触发器
- 即将报告"测试通过" → 重读断言条件，确认验证的是功能字段不是元数据
- 改了被多组测试依赖的代码 → 先查 impact-map.md，不查直接跑等于撞运气
- 新功能无对应测试 → 在 status.md 的覆盖缺口段标注，不要假装覆盖
```

### 标准版（业务 API、库、内部工具）

```markdown
# Test Protocol
## 测试铁律
- pass 基于返回值字段验证，不只看退出码
- skip 必须醒目标注并附原因
## 触发器
- 报告"通过"前确认验证的是功能字段
- 改了多组依赖的代码先查 impact-map.md
- 新功能无测试 → 标注覆盖缺口
```

### 宽松版（实验、原型、demo）

```markdown
# Test Protocol
- pass 必须能区分"功能 work"和"调用没崩"
- 新功能无测试时显式说明
```

### 质量标准

| 项目 | 必须满足 |
|------|---------|
| 总行数 | ≤ 15 行 |
| 内容 | 纯认知规则，零项目特定信息（如组名、版本号） |
| 每条 | 可机械检查（agent 能对照自检） |
| 风险匹配 | 风险越高，约束越严 |

---

## test-groups.md

测试组定义 + 运行命令 + 运行条件。是 agent 选择跑哪组的权威信源。

```markdown
# Test Groups

## <Letter> <Group Name> （<N> 项）
- 覆盖范围: <一句话：测什么>
- 运行命令: `<精确可执行命令>`
- 运行条件: <环境变量 / 依赖项 / 是否需要真账户>
- 典型耗时: <分钟>
- 关键字段断言示例: `EXPECT_PATTERN='"<field_name>"'`
- 失败模式: <这组挂的话通常是什么原因>

---

## smoke 集合
groups: <如 A B E>
total_items: <N>
estimated_time: <分钟>

## full 集合
groups: <ALL>
total_items: <N>
estimated_time: <分钟>
```

### 质量标准

| 项目 | 必须满足 | 不合格示例 |
|------|---------|-----------|
| 运行命令 | 可直接复制粘贴执行 | "跑 A 组" |
| 运行条件 | 列全所有依赖（环境、二进制、账户） | "需要环境就绪" |
| 关键字段断言 | 给一个具体字段名 | "断言返回值正确" |
| smoke / full 集合 | 列出组字母 + 项数 + 耗时 | 只列字母 |

---

## impact-map.md

变更关键词 → 受影响测试组的映射。strategy 工作流的输入。

```markdown
# Impact Map

## 关键词 → 测试组映射

| 关键词 | 影响测试组 | 来源 |
|--------|-----------|------|
| login | A | verified-on-v1.4.27（A-01 失败时确认） |
| auth | A | verified-on-v1.4.27 |
| REST | B C D | inferred-from-history（最近 3 次 REST 改动后这三组都跑过） |
| order | C | human-report（开发者文档说 order 路径只走 C 组） |
| WebSocket | D | verified-on-v1.4.26 |
| keychain | H | verified-on-v1.4.27 |
| MCP | I | verified-on-v1.4.27 |
| panic | R | inferred-from-history |

## 路径 → 测试组映射（如适用）

| 文件路径模式 | 影响测试组 | 来源 |
|-------------|-----------|------|
| `src/auth/*` | A F | inferred-from-history |
| `src/mcp/*` | I | verified-on-v1.4.27 |

## 全量触发条件

以下变更不走 targeted，直接推荐 full：
- 跨 major/minor 版本升级
- 修改了启动参数解析（影响 G 组所有项）
- 修改了核心日志框架（影响 J / R 组的 log 读取）
```

### 质量标准

| 项目 | 必须满足 |
|------|---------|
| 来源 | **必须填**，不能空。值域：`verified-on-vX.Y.Z` / `inferred-from-history` / `human-report` / `[未验证]` |
| 关键词 | 小写化以便匹配 |
| 全量触发条件 | 列出"覆盖太广不如全跑"的边界 |

---

## known-issues.md

人类视图的已知问题表。`feedback-rules.json` 是机器视图，本文件是同步出来的人类版本。

```markdown
# Known Issues

## 已 suppress（不算 active failures）

| Test ID | Verdict | 来源版本 | 原因 |
|---------|---------|---------|------|
| B-05 | not-a-bug | v1.4.27 | 开发者说空 funds 是预期（账户无资金时） |
| H-02 | wontfix | v1.4.26 | macOS Keychain 旧版兼容性问题，不修 |

## 已知行为（仍算 fail，但已知）

| Pattern | 描述 | 来源版本 |
|---------|------|---------|
| D-* | 闭市时 quote 返回 stale 数据，不影响功能 | v1.4.27 |

## Flaky

| Test ID | 不稳定原因 | 缓解 | 是否阻塞 |
|---------|-----------|------|---------|
| D-03 | WebSocket 订阅时序竞争 | retry 3 次 | no |

## 经验教训

- MCP 工具的多符号参数风格统一为 `symbols: []`，不是 `security_list: [{}]`（v1.4.29 开发者澄清）
- F 组的 scope 测试在 daemon 不带 `--rest-keys-file` 时无法跑，autonomous 路径需 `--managed`
```

### 质量标准

| 项目 | 必须满足 |
|------|---------|
| Test ID | 必须是 test-groups.md 中真实存在的 ID |
| Verdict | 取自 `not-a-bug / fixed / wontfix / deferred / fixed-differently` |
| 来源版本 | 该规则首次出现的版本 |
| 经验教训 | 是可推广的洞察，不是特定 ID 的现象 |

---

## status.md（自动生成）

每次 strategy / update / feedback 后自动 refresh。**不应人手编辑**（会被覆盖）。

```markdown
# <Project Name> 测试状态（自动生成）

> 最后更新: <YYYY-MM-DD HH:MM> | 当前版本: v<X.Y.Z> | 历史运行: <N> 次

## 项目概况
<一句话项目描述，从 .better-work/shared/index.md 读>

## 测试覆盖（<N> 组 / <M> 项）
- A 登录链路 (9项)
- B REST 只读 (5项)
- ...

## 当前状态
- 最近测试: v<X.Y.Z> run-NNN — <P>/<T> pass, <F> fail (mode: <m>)
- 活跃 fail (<N> 项):
  - B-05 funds 查询: no match for 'power'
- 已 suppress (<N> 项):
  - H-02: macOS Keychain 兼容性
- 全部通过（如适用）

## 关键经验
- <从 known-issues.md lessons 段同步前 5 条>

## 测试铁律
- <从 protocol.md 同步前 3 条铁律>

## 覆盖缺口
| 模块 / 功能 | 引入版本 | 风险 |
|------------|---------|------|
| ...        | ...     | ...  |

## 索引
- 完整测试组定义: test-groups.md
- 变更影响映射: impact-map.md
- 已知问题详情: known-issues.md
- 历史原始数据: history/<version>/run-NNN-*/results.json
```

### 质量标准

| 项目 | 必须满足 |
|------|---------|
| 总长度 | ≤ 100 行（再长就不是"快速概览"） |
| 数据新鲜度 | 必须在生成时是最新的（自动重算，不复制旧值） |
| 索引部分 | 给出文件名让 agent 知道去哪深查 |

---

## progress.md

见 `references/progress-workflow.md`。

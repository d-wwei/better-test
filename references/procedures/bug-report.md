# Bug Report 格式

触发条件：测试中发现 bug 需要写报告时

---

## 标准格式：8 节 + 结构化元数据

每份 bug report 必有以下 8 节叙事部分 + 1 个结构化元数据块。任何一节缺失都属于
不完整 Bug Report，不能进入最终开发者报告。

### 叙事部分（面向人阅读）

**1. TL;DR**

一句话：现象 + 影响。

```
示例：resource_query 对边界资源返回空列表，影响批处理用户的资源查询。
```

**2. 现象矩阵**

表格展示哪些组合失败、哪些通过。用对照让 pattern 可见。

```markdown
| 标的类型 | REST | CLI | MCP | 结果 |
|---------|------|-----|-----|------|
| 股票 HK.00700 | ✅ | ✅ | ✅ | 全通 |
| 期权 HK.TCH... | 🔴 | 🔴 | 🔴 | 全挂 |
| 边界资源 R.67890 | ✅ | ✅ | 🔴 | RPC 不一致 |
```

**3. 基准对照（必填）**

如果有基准实现（旧版本/C++ SDK/Python SDK），此段**必填**。没有基准对照的 bug report 视为不完整。

```markdown
| 操作 | 基准结果 | 被测结果 | 结论 |
|------|---------|---------|------|
| funds 查询（完整参数） | {"power": 153.2} | {"power": null} | 🔴 被测返回空 |
| funds 查询（缺 filterConditions） | {"power": 153.2} | -400 bad request | 🔴 被测缺省处理有问题 |
| history-orders（同参数） | 13 条记录 | 0 条 | 🔴 被测缺失 default fill |
```

无基准时写"无可用基准：<原因>"。但应尽力找替代对照（同接口不同参数、同接口不同账户等）。

**4. 其他对照**

```
- 同 endpoint 不同标的（排除标的问题）
- sim vs real 账号（排除权限问题）
- 完整参数 vs 缺省参数（排除 default-fill 问题）
```

**5. 权限/账号排除**

明确排除用户配置错误的可能性。

```
- 已 unlock-trade：是
- 账户类型：sim + real 都测过
- 权限范围：scope 包含 options
```

**6. Root cause 推测**

配合 debug log / 源码位置 / wire 分析。**必须标注证据级别**（见 investigation.md 证据分级）。

```
推测（evidence: direct）：daemon 在处理 resource_query 时把
warrant 类型的 security_type 错误映射为 stock，导致查询
走了股票路径返回空。

依据：daemon log 中 recv frame 显示 security_type=3（warrant），
但下一行 process 显示 query type=1（stock）。

源码位置（如有）：src/handlers/resource_query.rs:142 的 match 分支
缺少 security_type=3 的处理。
```

**7. 复现步骤**

完整的本地可复现 shell 命令。不能是"试一下该接口"——必须可复制粘贴执行。

```bash
# 1. 启动 daemon
./sample-service --log-level debug --port 18111

# 2. 调用待测资源查询接口
curl -X POST http://localhost:18111/api/v1/resource_lookup \
  -H "Content-Type: application/json" \
  -d '{"resource": "sample", "category": "example"}'

# 3. 观察返回值
# 预期：非空 JSON 列表
# 实际：[]

# 4. 对照（股票标的）
curl -X POST http://localhost:18111/api/v1/resource_query \
  -H "Content-Type: application/json" \
  -d '{"security": "HK.00700", "type": "stock"}'
# 返回正常 JSON 列表
```

**8. 影响评估**

阻塞哪些用户群、哪些 roadmap 项。

```
- 阻塞用户群：批处理用户（依赖 resource_query 做资源分析）
- 阻塞 roadmap：Agent 自动化功能（需要 resource_query 做决策输入）
- 严重程度：P1（核心功能不可用，无 workaround）
```

### 结构化元数据（面向 agent 机器读取）

附在 bug report 末尾或作为单独的 yaml 块：

```yaml
bug:
  id: <BUG-XXX>
  title: <简短标题>
  status: OPEN | CONFIRMED | FIXED | VERIFIED | CLOSED | WONTFIX
  severity: P0 | P1 | P2 | P3 | undetermined
  evidence_level: indirect | direct | binary | confirmed | proven
  evidence_refs: [<results.json source_id 或 artifact path>]
  bug_type: regression | integration | edge_case | environment | data | concurrency
  affected_groups: [B, C, I]
  affected_scenarios: [warrant, agent]
  found_in: v1.4.28
  found_by_tester: <tester-id>
  found_by_run: <run-id>
  related_tests: [B-01, C-02]
  version_found: v1.4.28
  version_fixed: null
  regression_canary: true  # 是否已加入回归 canary
  post_ship: false
  escape_id: null  # post_ship=true 时必须是 ESC-NNN
```

bug_type 和 evidence_level 取值见
`references/procedures/hypothesis-investigation.md`；confirmed 的 evidence refs 必须能回到
两个不同 independence key。post_ship=true 时同步更新并校验 `test/escapes.json`。

---

## 单文件开发者交付合同

`bugs/BUG-*.md` 是 run/merge 内部的结构化源文件，不是要开发者另外打开的附件。最终只交付
`FULL-TEST-REPORT.md`（项目可使用等价本地化文件名，如 `FULL-TEST-REPORT-CN.md`），并满足：

1. 每个 `bugs/BUG-*.md` 的 8 节正文和完整 YAML 元数据必须逐字嵌入主报告；
2. 不允许只放 TL;DR、摘要、表格行或本地文件链接；
3. `results.json` / `merged-results.json` 引用的每个 `bug_id` 都必须有对应完整 Bug Report；
4. 主报告同时包含测试结论、审计材料和完整机器结果，开发者无需第二份文件才能理解或复现；
5. 交付前运行：

```bash
python3 <skill-root>/scripts/build-full-report.py \
  --run-dir <run-or-merge-dir> \
  --output <run-or-merge-dir>/FULL-TEST-REPORT.md
```

该命令会校验 8 节、必填元数据、`bug_id` 对应关系，并按 SHA-256 验证主报告内嵌正文与
`bugs/` 源文件完全一致。任一项不满足即失败，报告不得交付。

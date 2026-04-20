# Bug Report 格式

触发条件：测试中发现 bug 需要写报告时

---

## 标准格式：7 节 + 结构化元数据

每份 bug report 必有以下 7 节叙事部分 + 1 个结构化元数据块。

### 叙事部分（面向人阅读）

**1. TL;DR**

一句话：现象 + 影响。

```
示例：option_chain 对窝轮代码返回空列表，影响量化策略用户的期权链查询。
```

**2. 现象矩阵**

表格展示哪些组合失败、哪些通过。用对照让 pattern 可见。

```markdown
| 标的类型 | REST | CLI | MCP | 结果 |
|---------|------|-----|-----|------|
| 股票 HK.00700 | ✅ | ✅ | ✅ | 全通 |
| 期权 HK.TCH... | 🔴 | 🔴 | 🔴 | 全挂 |
| 窝轮 HK.67890 | ✅ | ✅ | 🔴 | MCP 不一致 |
```

**3. 关键对照**

列出正常 case 作为参照。对照让 bug 报告说服力翻倍。

```
- 同 endpoint 股票标的返回正常 JSON（排除接口本身问题）
- sim 账号同参数也失败（排除真账户权限问题）
- v1.4.26 同参数返回正常（定位为 regression）
```

**4. 权限/账号排除**

明确排除用户配置错误的可能性。

```
- 已 unlock-trade：是
- 账户类型：sim + real 都测过
- 权限范围：scope 包含 options
```

**5. Root cause 推测**

配合 debug log / 源码位置 / wire 分析。**必须标注证据级别**（见 investigation.md 证据分级）。

```
推测（evidence: direct）：daemon 在处理 option_chain 时把
warrant 类型的 security_type 错误映射为 stock，导致查询
走了股票路径返回空。

依据：daemon log 中 recv frame 显示 security_type=3（warrant），
但下一行 process 显示 query type=1（stock）。

源码位置（如有）：src/handlers/option_chain.rs:142 的 match 分支
缺少 security_type=3 的处理。
```

**6. 复现步骤**

完整的本地可复现 shell 命令。不能是"试一下 option_chain"——必须可复制粘贴执行。

```bash
# 1. 启动 daemon
./futu-opend --log-level debug --port 11111

# 2. 调用 option_chain（窝轮标的）
curl -X POST http://localhost:11111/api/v1/option_chain \
  -H "Content-Type: application/json" \
  -d '{"security": "HK.67890", "type": "warrant"}'

# 3. 观察返回值
# 预期：非空 JSON 列表
# 实际：[]

# 4. 对照（股票标的）
curl -X POST http://localhost:11111/api/v1/option_chain \
  -H "Content-Type: application/json" \
  -d '{"security": "HK.00700", "type": "stock"}'
# 返回正常 JSON 列表
```

**7. 影响评估**

阻塞哪些用户群、哪些 roadmap 项。

```
- 阻塞用户群：量化策略（依赖 option_chain 做期权链分析）
- 阻塞 roadmap：Agent 自主交易功能（需要 option_chain 做决策输入）
- 严重程度：P1（核心功能不可用，无 workaround）
```

### 结构化元数据（面向 agent 机器读取）

附在 bug report 末尾或作为单独的 yaml 块：

```yaml
bug:
  id: <BUG-XXX>
  status: OPEN | CONFIRMED | FIXED | WONTFIX
  evidence_level: indirect | direct | confirmed | proven
  bug_type: regression | integration | edge_case | environment | data | concurrency
  affected_groups: [B, C, I]
  affected_scenarios: [warrant, agent]
  version_found: v1.4.28
  version_fixed: null
  regression_canary: true  # 是否已加入回归 canary
```

bug_type 取值见 investigation.md 的 Bug 分类表。evidence_level 取值见 investigation.md 的证据分级体系。

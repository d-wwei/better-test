# Test Execution Workflow Changelog

## [2026-08-25] modify
- **操作**: modify
- **段落**: Pass 判定 / 查询数据质量
- **内容**: 在 silent success 基础上增加 oracle-conditioned non-empty、数值/时间值域、64 位身份、aggregate/detail、cache integrity 和 normalized parity 六层矩阵。
- **来源**: user-input + futu-opend-rs v1.6.3-v1.6.5 data-quality audit
- **一致性检查**: 与既有 Pass 4 件套、compare 模式、字段四态和证据分级兼容；项目专属 market/symbol/range 留在项目知识库。

## [2026-08-25] modify
- **操作**: modify
- **段落**: Bug 发现 / 输出模板
- **内容**: 分离 occurrence、finding、Bug 三种计数基数；多 occurrence 同根因去重，未归因差异留 investigation backlog。
- **来源**: user-input + futu-opend-rs Official parity triage
- **一致性检查**: 与 results occurrence 保留、fingerprint 去重、完整 Bug Report 和 Issue submission 门禁一致。

## [2026-07-27] modify
- **操作**: modify
- **段落**: 完成流程 / Bug Report / merge / 输出模板 / L2 审计
- **内容**: 开发者默认只接收一份 FULL-TEST-REPORT.md；其中逐字包含本轮全部 8 节 Bug Reports、完整 YAML 元数据、结论、审计材料和机器结果。新增 build + validate-only 终门，缺节、缺元数据、bug_id 断链、遗漏、重复、截断或正文漂移都会失败。
- **来源**: user-input
- **一致性检查**: 已检查 SKILL、test-execution、bug-report procedure、templates、merge、L2、Hook checklist、README 和 CHANGELOG；内部结构化源继续保留，但不再要求开发者分别打开。

## [2026-07-27] modify
- **操作**: modify
- **段落**: 安全守则 / strategy 可行性 / env-config 模板
- **内容**: 专用实盘 campaign 复用持久会话，并在 strict-ready 后自动发现可派生的交易账户 ID；禁止把账号、密码或账户 ID 重新变成逐 run 用户输入。
- **来源**: user-input
- **一致性检查**: 已检查 protocol-base、strategy-workflow、test-execution-workflow、templates、README 和 CHANGELOG；未削弱凭据隔离、普通账号 fail-closed 或证据/清理要求。

## [2026-07-27] modify
- **操作**: modify
- **段落**: 安全守则 / strategy 可行性 / env-config 模板
- **内容**: 产品登录和关键用户旅程必须通过第一方 GUI、官方 CLI 或官方配置验证；Agent 自行完成启动，credential broker/wrapper 只作幕后 secret/session 处理，不得要求用户执行，也不得替代产品证据。
- **来源**: user-input
- **一致性检查**: 已检查 protocol-base、strategy-workflow、test-execution-workflow、templates、README 和 CHANGELOG；与专用账号 standing 授权、凭据隔离、普通账号 fail-closed、证据及清理规则兼容。

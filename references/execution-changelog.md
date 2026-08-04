# Test Execution Workflow Changelog

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

# 测试到 Agent 用户意图投影

触发条件：被测对象包含 MCP、Agent Skill、自然语言 CLI assistant，且需要验证“用户会怎么说”。

## Purpose

把已激活的主流程测试投影为用户自然语言检查清单。它是测试入口补充，不替代原始 schema、负向和字段断言。

## Generation

```bash
python3 <skill-root>/scripts/project-reference-suite-intents.py \
  test/reference/<suite>-case-map.json \
  --output test/reference/<suite>-agent-intents.md
```

默认只投影 `direct/adapted` 且 `none/read` 的 case。写入型意图必须由项目单独启用并附授权。

## Rules

1. 每条意图保留 target test ID。
2. 使用用户语言，不要求用户知道 SDK 方法或 proto 参数。
3. 执行结果必须记录 success/fail/blocked/warning。
4. “调用成功”不能替代原 case 的 oracle/evidence boundary。
5. 生成物可进入 Skill smoke，但 release verdict 仍由正式 results/gates 决定。

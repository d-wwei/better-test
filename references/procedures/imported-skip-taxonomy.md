# Imported Suite Skip Taxonomy

触发条件：外部/上游测试仓存在 runtime skip、conditional skip、缺权限、无数据或限频处理。

## Categories

```text
missing_capability
missing_entitlement
missing_account
market_closed
data_unavailable
rate_limited
upstream_not_implemented
unsafe_without_approval
fixture_failure
product_behavior
unclassified
```

## Denominator Rules

- `missing_capability`：保留在 surface denominator，标 blocked/not-applicable 取决于产品合同。
- `missing_entitlement` / `missing_account`：环境分母未满足，不能写 pass。
- `market_closed` / `data_unavailable`：可延期重测，但不能替代 required runtime evidence。
- `rate_limited`：测试基础设施/节奏问题，默认不从 required denominator 删除。
- `upstream_not_implemented`：上游执行器限制；case 保留 oracle-only/blocked。
- `unsafe_without_approval`：等待 policy/profile，不是产品 pass。
- `fixture_failure`：测试未开始，必须 fail/blocked，不得美化为 skip。
- `product_behavior`：被测行为导致，通常应 fail 或 known issue。
- `unclassified`：禁止 release GO；必须在 merge 前归类。

## Required Output

每个 skip item 写：

```text
category
reason
subject_refs
environment identity
retry/closure action
denominator impact
```

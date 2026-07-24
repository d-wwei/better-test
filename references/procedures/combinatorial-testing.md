# Pairwise 组合测试与等价类

触发条件：存在至少两个独立输入因子、每个因子有多个可枚举取值，且全笛卡尔积的执行成本明显高于风险收益。

典型场景包括多平台 × 协议 × 权限、功能开关 × 数据类型、客户端 × 服务端版本等组合。若主要风险来自调用顺序、并发时序或长状态链，应改用状态/序列测试；pairwise 不能证明这些风险已覆盖。

---

## 核心边界

- pairwise 只保证任意两个因子的取值组合至少出现一次，不保证业务断言正确。
- 等价类必须显式列出并绑定到测试用例，不能从 factor 名称或自然语言里暗推。
- 边界值、历史故障、资金/权限/数据破坏等高风险 canary 必须单独指定，不能因为 pairwise 已覆盖同一取值就删除。
- 一个 canary 可以复用 pairwise 用例，但必须在 `high_risk_canaries` 中保留可机械检查的引用。
- 生成器输出不是通过证据；执行结果、断言和原始证据仍按主测试流程记录。

## JSON 结构

```json
{
  "factors": [
    {"name": "transport", "levels": ["http", "grpc"]},
    {"name": "auth", "levels": ["none", "token"]}
  ],
  "cases": [
    {
      "id": "C001",
      "values": {"transport": "http", "auth": "none"},
      "classes": ["public-access"]
    }
  ],
  "required_equivalence_classes": [
    {
      "id": "public-access",
      "factor": "auth",
      "levels": ["none"]
    },
    {
      "id": "expired-token",
      "factor": "auth",
      "predicate": "token is syntactically valid but expired"
    }
  ],
  "high_risk_canaries": [
    {"id": "CANARY-AUTH-DENY", "case_id": "C004"}
  ]
}
```

字段规则：

- `factors[].name` 和同一 factor 内的 `levels[]` 必须非空且唯一。
- 每个 `cases[]` 必须为每个 factor 恰好提供一个合法取值；不得缺失或夹带未知 factor。
- `classes[]` 引用 `required_equivalence_classes[].id`。每个必需等价类至少被一个 case 引用。
- 等价类使用非空 `levels` 或非空 `predicate` 描述。`levels` 必须属于其 factor；引用基于 `levels` 的 class 时，case 的对应取值必须落在这些 levels 中。
- `predicate` 只是把人工/业务判定条件显式化；校验器只能检查它已定义且被 case 引用，
  不能证明自然语言 predicate 在运行时为真。该证明必须进入正式执行证据。
- `high_risk_canaries[].case_id` 必须指向真实 case。

## 执行步骤

1. 列出独立 factor 和有限 levels；不要把期望结果混进 factor。
2. 在选组合前定义必需等价类，包含合法、非法、边界和历史故障类。
3. 标出高风险 canary，并为其保留明确 case。
4. 生成或人工选择组合，使全部 2-way value pair 被覆盖。
5. 运行机械校验：

   ```bash
   python3 <skill-root>/scripts/validate-pairwise.py path/to/pairwise-plan.json
   ```

6. 校验通过后执行这些 case，并在正式结果中记录断言、证据等级和证据路径。

校验器只使用 Python 标准库。成功返回 `0`；结构错误、pair 缺口、等价类缺口或 canary 悬空时返回 `1` 并列出具体问题。

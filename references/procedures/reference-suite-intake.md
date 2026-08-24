# 外部参考测试仓吸纳

触发条件：用户提供官方、上游、旧实现、友商或第三方测试仓，并希望把其中用例作为 oracle、baseline 或候选回归集。

目标不是复制测试代码，而是建立可追溯的来源身份、危险面、case map、项目映射和同步合同。

## 1. Source Identity

先记录：

```text
repo URL
actual test branch
40-character commit SHA
fetch timestamp
dirty status
license/access boundary
```

入口分支和实际测试分支必须分别验证。分支名、版本号或目录名不能代替 commit identity。

## 2. Static-First Gate

在执行任何 upstream 测试前，先做静态扫描：

```bash
python3 <skill-root>/scripts/build-reference-suite-map.py \
  --repo <upstream-root> \
  --suite-id <stable-id> \
  --test-root <pytest-root> \
  --output <project-test-root>/reference/<suite>-case-map.json

python3 <skill-root>/scripts/validate-reference-suite-map.py \
  <project-test-root>/reference/<suite>-case-map.json
```

builder 只解析 AST 和文本，不 import 测试模块，不启动服务，不访问网络。

危险扫描至少覆盖：

- autouse/session fixture
- process launch/kill
- credential-related config
- credential in argv/log
- network/external writes
- account mutation
- real trade/unlock
- random input
- fixed sleep
- runtime skip

危险扫描未完成时，外部套件只能作为 source/oracle evidence，不能形成 runtime 或 release claim。

## 3. Case Classification

每个静态 test function 必须进入 case map，并标注：

```text
side_effect: none/read/write/destructive
execution_level: L0/L1/L2/L3/L4
adoption_status:
  direct
  adapted
  oracle-only
  duplicate
  blocked
  not-applicable
  rejected
target_test_ids
oracle_type
environment
skip_categories
evidence_boundary
```

不支持或暂时不能运行的 case 仍保留在 map 中，不得因无法执行而丢弃。

## 4. Project Mapping

项目仓负责把通用 case map 映射到自己的：

- test groups
- impact map
- surface manifest
- release gates
- environment/capability matrix
- known upstream issues

通用 skill 不保存项目账号、市场、具体股票代码、券商规则或 release gate。

## 5. Adapter Boundary

保留 upstream mirror，不长期修改 upstream。项目 adapter 负责：

- 参数化 host/port/profile/market
- 禁止读取 upstream 默认凭证
- 选择允许的 execution level
- 将 upstream 结果转换成项目 `results.json`
- 保存 source/process/session identity
- typed skip/blocked reason
- cleanup/reconcile

read-only 必须是默认模式。write/destructive case 需要项目 policy 和运行时授权。

## 6. Skip Taxonomy

imported skip 必须归类：

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

`rate_limited`、`fixture_failure`、`product_behavior` 和 `unclassified` 不得静默缩小 required denominator。

## 7. Upstream Drift

同步时比较：

- branch/SHA
- added/deleted files
- added/deleted test functions
- marker/fixture/call changes
- side-effect level changes
- orphan/duplicate target mappings

新 SHA 先生成 diff 和新 case map，不自动替换项目 pinned SHA。

## 8. Completion Gate

吸纳完成至少要求：

1. upstream 全部静态 test functions 已映射。
2. map validator PASS。
3. danger scan completed。
4. 无 orphan/duplicate case ID。
5. 每个 activated case 有 oracle 和 evidence boundary。
6. write case 有授权、ownership、reconcile 和 cleanup。
7. upstream bug 与被测产品 bug 分开归因。

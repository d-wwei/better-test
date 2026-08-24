# 动态 Fixture 可复现合同

触发条件：测试在运行时随机选标的、从列表发现 ID、依赖动态数据池，或使用当前时间/市场状态构造输入。

## Required Evidence

每个动态 case 至少记录：

```text
selector/provider identity
candidate pool source + SHA/update time
random seed
selected values
selection filters
market/time window
fallback path
```

## Rules

1. 优先 list -> ID -> detail，不使用文档 placeholder ID。
2. random 必须显式 seed；失败证据保存 seed 和候选池。
3. 静态 smoke 样本与动态 discovery 分开，不互相替代。
4. 数据池刷新必须整池原子化，失败保留 last-good，不产生半更新池。
5. selector 返回空时区分 capability、entitlement、market closed 和 data unavailable。
6. 动态输入不能改变 required denominator；无法构造时标 typed blocked/skip。
7. 重跑 bug 时优先复用原 seed/selected value，再做新样本扩展。

## Claim Boundary

动态样本单次 PASS 只证明该样本。要宣称品类/市场整体可用，需声明采样分母或运行完整矩阵。

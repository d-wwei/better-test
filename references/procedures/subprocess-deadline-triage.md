# Subprocess Deadline Triage

触发条件：测试通过 spawn 子进程、等待 readiness/退出/PID 文件，且结果受固定 deadline、
调度负载或并发度影响。

## 分类原则

超时首先是 `TEST-INFRA candidate`，不能直接归因产品。只有候选二进制的独立 runtime
控制也在同一业务断言上失败，才能升级为产品 failure。

必须同时记录：

1. spawn、ready、deadline、artifact-created、terminate、reap 的单调时钟时间点；
2. 子进程 argv 摘要、binary hash、PID、端口和退出状态；
3. 测试 wrapper 的 deadline 与产品自身 timeout，二者不得混写；
4. direct binary/control 的同输入结果；
5. 串行、默认并发、受控负载下的重复分布。

## 判定

- direct control 稳定通过、wrapper 随调度变化：`TEST-INFRA FAIL`，产品项不得 FAIL。
- direct control 同样超时或业务断言失败：按产品 failure 调查，但仍分开记录 wrapper 缺陷。
- deadline 到达后读取 PID 文件、socket 或日志前必须先判断 artifact 是否存在；禁止
  unconditional unwrap 把“未创建”伪装成 cleanup failure。
- sub-second 固定等待只能用于主动 poll 的单次间隔，不能作为跨平台 readiness 总预算。
- readiness 应使用 condition-based polling，并设置项目校准的总预算和明确 cleanup budget。

## 最小复现矩阵

| 路径 | 次数 | 目的 |
|---|---:|---|
| wrapper 原并发 | 10 | 量化 flake |
| wrapper 串行 | 10 | 隔离资源竞争 |
| direct binary/control | 10 | 区分产品与 harness |
| 受控负载 | 10 | 验证 deadline 对调度敏感性 |

若样本不足，保持 `candidate` 或 `partial`，不要用一次重跑 PASS 覆盖原失败。

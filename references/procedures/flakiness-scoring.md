# Flakiness 稳定性评分

触发条件：update workflow 检测到 flaky 信号，或 strategy 推荐的组包含已知不稳定测试

---

## 计算方法

```
稳定性评分 = 过去 N 次运行中结果一致的次数 / N

数据来源：history/<version>/run-NNN-*/results.json
```

## 评分表

| 评分 | 分类 | strategy 行为 |
|------|------|-------------|
| 100% | 稳定 | 正常推荐 |
| 80-99% | 轻微不稳定 | 推荐时标注"近期有不稳定记录" |
| 50-79% | 显著不稳定 | 醒目提示，建议先解决 flakiness |
| < 50% | 严重 flaky | 自动建议 `feedback <id> deferred` |

## 更新时机

- 每次测试运行后，update workflow 自动刷新评分
- 评分写入 known-issues.md Flaky 段

## 关键数据

- Google：~16% 的测试存在某种 flakiness
- 84% 的 pass→fail 转换涉及 flaky 测试
- 三次连续不一致再标 flaky（避免单次误判）

方法论详解见 `methodologies/execution.md`。

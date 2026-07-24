# 3-假设调查法

触发条件：测试失败且错误解读三问（Tier 1）无法定位原因

---

## 步骤

1. 基于已有证据生成 3 个不同假设：

```
假设 1: [基于证据最可能的原因]
  验证: [怎么确认或排除]
  需要: [什么证据能证明]

假设 2: [替代原因]
  验证: [怎么确认或排除]
  需要: [什么证据能证明]

假设 3: [如果前两个都错呢？]
  验证: [怎么确认或排除]
  需要: [什么证据能证明]
```

2. 从最可能的假设开始验证
3. 找到支持证据 → 确认，标注证据级别（见 Tier 1 证据分级）
4. 找不到 → 排除，转下一个假设

## 3-失败规则

3 个假设都被证伪 →

1. **停下**。不随机生成假设 4-7
2. **重审前提**。你认为正确的某个前提是错的
3. **回到分析**。重新 trace 执行路径
4. **检查 bug 分类**：是不是分类错了？（Regression → 其实是 Environment）

## Bug 分类参考

| 类型 | 信号 | 调查方向 |
|------|------|---------|
| Regression | "之前是好的" | git log 找变更点 |
| Integration | "单独没事一起挂" | 查组件间数据传递 |
| Edge case | "只有这个条件挂" | 找触发条件共同特征 |
| Environment | "换环境就好了" | diff 环境配置 |
| Data | "只有这条数据挂" | 检查数据特征 |
| Concurrency | "有时挂有时不挂" | 多次跑 + 看时序 |

## 调查阶梯（有源码版）

```
1. strings binary | grep → binary（只能证明 artifact/literal 存在，不能证明 runtime 生效）
2. daemon --log-level debug → direct
3. curl + xxd / python read → direct（换了观测工具，不自动变成 confirmed）
4. 用不同 tester，或不同环境 / 输入路径 / 验证方法独立复现 → confirmed
5. git log / blame / 读源码，或 proto / API spec → proven
无源码时最高可到 confirmed，但必须真的有两个不同 `independence_key` 和两个不同的
run-local artifact 文件
```

## 证据分级完整定义

调查过程中每个判断必须标注证据级别：

| 级别 | 定义 | 可用于 | 不可用于 |
|------|------|--------|---------|
| **guess** | 无任何依据的猜测 | 不可出现在任何输出中 | 一切 |
| **indirect** | 间接推测（上下文推断 / 类比 / 未执行的因果解释） | 仅形成假设 | pass/fail 判定 |
| **direct** | 直接证据（debug log / 命令输出 / 具体字段值） | ✅ pass、🔴 fail、假设验证 | 根因确认 |
| **binary** | binary/artifact 中的 literal、symbol 或结构证据 | 证明代码/资源已落入 artifact | 单独判 runtime pass/fail 或 fixed |
| **confirmed** | 至少两份不同 `independence_key`、两个不同 run-local artifact 文件的直接证据交叉验证 | 根因确认 | 声称系统性模式、写长期 lessons |
| **proven** | 结构化 source/proto 或 multi-version basis；functional claim 另有独立 runtime artifact | 系统性模式、impact-map 标 verified、known-issues lessons | — |

### 语气匹配

- indirect → 必须说"推测"、"可能"、"疑似"
- direct → 可说"观察到"、"log 显示"
- confirmed → 可说"确认"、"根因是"
- proven → 可说"系统性地"、"所有 X 都是 Y"

### 在 better-test 场景中的应用

| 场景 | 最低要求 |
|------|---------|
| ✅ pass 判定 | direct（具体字段 + 值） |
| 🔴 fail 报告 | direct（错误码或 log） |
| Bug report root cause | confirmed |
| known-issues lessons | proven |
| impact-map 标 verified | confirmed |

方法论详解见 `references/methodologies/design-rationale.md` 的调查方法章节。

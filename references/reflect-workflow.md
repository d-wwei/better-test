# Reflect Workflow

`/better-test reflect [scope]` — 从历史数据中提取跨会话、跨版本的测试经验，更新知识文件。

与增量 reflect 的区别：增量 reflect 在每次测试后自动执行，只用本次运行数据对比知识文件。全量 reflect 读所有历史数据，做单次运行看不到的趋势分析和模式提炼。

## 命令

```
/better-test reflect                    ← 全量分析（6 类全做）
/better-test reflect impact-map         ← 只做 impact-map 映射精度评估
/better-test reflect stability          ← 只做稳定性趋势分析
/better-test reflect bugs               ← 只做 bug 热点和模式分析
/better-test reflect lessons            ← 只做经验综合
/better-test reflect timing             ← 只做执行效率校准
/better-test reflect patterns           ← 只做通用模式提炼
```

## 触发时机

```
自动建议：
  - 版本切换时（strategy 检测到新版本）→ "上个版本有 N 次运行，建议先 reflect"
  - 累积 5+ 次运行且从未做过 reflect → strategy 时提醒
  - 3+ 个新 bug 累积且未做过 bug 分析 → feedback 时提醒

用户手动：
  - /better-test reflect [scope]
```

## 核心原则

reflect 的产出是**修改建议**，不是直接修改。每条建议需要用户确认。

原因：历史数据中的 pattern 可能是巧合（两次恰好都挂了 ≠ 因果关系）。人需要判断"这确实是规律"还是"碰巧而已"。

---

## 分析 1：Impact-map 映射精度评估

```
输入：
  - impact-map.md（当前映射）
  - 所有 results.json × N 次运行（每次运行的变更信号 + 实际 fail 组）

步骤：
  1. 对每次运行，提取：
     - strategy 记录的变更信号（关键词/文件路径）
     - impact-map 基于这些信号预测应该 fail 的组
     - 实际 fail 的组
  2. 统计每条映射的命中率：
     - 预测且命中（真阳性）
     - 预测但没命中（假阳性）
     - 没预测但命中（假阴性 = 缺失映射）
  3. 输出建议：
     - 命中率高的映射 → 升级来源为 verified
     - 从未命中的映射 → 标注"N 次未命中，考虑是否过宽"
     - 多次假阴性 → 建议新增映射

输出：
  impact-map 整体准确率: NN%（真阳性 / (真阳性 + 假阳性)）
  召回率: NN%（真阳性 / (真阳性 + 假阴性)）
  逐条映射的修改建议列表
```

---

## 分析 2：稳定性趋势分析

```
输入：
  - 所有 results.json × N 次运行
  - test-groups.md（当前稳定性评分）
  - known-issues.md Flaky 段

步骤：
  1. 对每个测试项，画出最近 N 次运行的 pass/fail 时间线
  2. 识别趋势：
     - 稳定 → 不稳定（最近 3 次开始 fail，之前一直 pass）→ 新增 Flaky 候选
     - 不稳定 → 稳定（之前 flaky，最近 5 次全 pass）→ 从 Flaky 段移除候选
     - 持续不稳定 → 如果 > 10 次中 fail > 50% → 建议 feedback deferred
  3. 对 Flaky 项，尝试识别 pattern：
     - 某测试只在特定时段 fail？（开市/休市相关）
     - 某测试只在某版本后开始 fail？（regression 候选）
     - 某测试的 fail 与另一个测试的 fail 总是同时出现？（共因）

输出：
  新增 Flaky: [列表]
  移除 Flaky: [列表]
  趋势恶化需关注: [列表]
  疑似 pattern: [列表 + 假设]
```

---

## 分析 3：Bug 热点和模式分析

```
输入：
  - bugs-index.md
  - 所有 bug reports
  - impact-map.md

步骤：
  1. 按模块统计 bug 数量
     src/auth/     3 个 bug
     src/rest/     5 个 bug  ← 热点
     src/mcp/      1 个 bug
  2. 按 bug_type 统计分布
     regression: 4, integration: 3, edge_case: 2, environment: 1
  3. 识别热点（同一模块 ≥ 3 个 bug）
  4. 检查 impact-map 中热点模块的映射：
     - 权重足够？（热点模块的变更应该触发更多测试组）
     - 有没有映射缺失？
  5. 读 bug report 的 root cause 段，识别重复出现的根因主题：
     - "daemon 错误码包装" 出现 3 次 → 系统性问题
     - "参数类型不匹配" 出现 2 次 → 接口契约问题

输出：
  热点模块: [模块 → bug 数]
  impact-map 权重调整建议: [列表]
  重复根因主题: [主题 → 出现次数 → 是否已在 lessons 中]
```

---

## 分析 4：经验综合

```
输入：
  - 所有 feedback/*.md 的 note 字段
  - 所有 bug report 的 root cause 段和修复记录
  - known-issues.md 的现有 lessons
  - feedback-rules.json 的现有 lessons

步骤：
  1. 提取所有 feedback note + bug root cause → 去重 → 聚类
  2. 识别重复出现的判定模式：
     - "expected behavior" 类判定出现了几种不同场景？能否合并为一条通用规则？
     - 同样的 root cause 出现在不同模块？→ 是系统性问题不是个案
  3. 对比 known-issues.md 现有 lessons：
     - 新 pattern（不在 lessons 中）→ 建议新增
     - 已有 lesson 需要加强（更多验证证据）→ 建议更新 evidence_level
  4. 判断是项目特有还是通用：
     - 项目特有 → known-issues lessons
     - 通用 → 提议加入 protocol 或 test-execution-workflow（通过 protocol-update）

输出：
  新 lesson 候选: [列表 + 证据来源]
  已有 lesson 加强: [列表 + 新增证据]
  通用模式（可能升级到 protocol）: [列表]
```

---

## 分析 5：执行效率校准

```
输入：
  - 所有 results.json 的时间戳（started_at / finished_at）
  - test-groups.md 的典型耗时

步骤：
  1. 对每个测试组计算：
     - 平均实际耗时（跨 N 次运行）
     - 最短 / 最长实际耗时
     - 当前预估耗时
  2. 偏差分析：
     - 实际 > 预估 × 1.5 → 预估过低，建议上调
     - 实际 < 预估 × 0.5 → 预估过高，建议下调
  3. smoke / full 集合的总耗时也需要校准

输出：
  耗时校准建议: [组 → 旧预估 → 新预估（基于 N 次实测平均）]
  smoke 总耗时: 旧 X 分钟 → 新 Y 分钟
  full 总耗时: 旧 X 分钟 → 新 Y 分钟
```

---

## 分析 6：通用模式提炼

```
输入：
  - 所有 bug report 的 root cause + 修复方式
  - 所有 execution-log 中的调查过程
  - test-execution-workflow.md 的当前 Tier 1 规则
  - protocol.md 的当前思维纪律

步骤：
  1. 从 root cause 中提取反复出现的原因类型
     "错误码被 daemon 包装" × 3 → 调查模式："遇到模糊错误时先看 debug log 原始码"
  2. 从 execution-log 的调查过程中提取反复使用的调查路径
     "每次 debug 都是先 grep log 再读源码" → 已有的调查阶梯是否需要更新？
  3. 判断：这个模式是否应该升级到更高层级？
     - 在 3+ 个不同场景中都适用 → 候选升级到 Tier 1 或 protocol
     - 只在特定类型 bug 中适用 → 留在 known-issues lessons
  4. 检查现有 Tier 1/protocol 中是否有从未触发的规则
     → 如果某条 Tier 1 规则在 N 次执行中从未被实际使用 → 候选降级

输出：
  候选升级到 Tier 1 / protocol: [模式 + 出现频次 + 适用场景]
  候选降级: [规则 + 未使用次数]
  知识文件演进建议: [具体修改]
```

---

## 全量 reflect 输出报告

全量 reflect 完成后生成综合报告：

```markdown
# Reflect 报告 — <日期>

## 数据范围
分析了 <N> 次运行（<version_range>），<M> 个 bug，<K> 条 feedback

## 关键发现

### 知识文件健康度
- impact-map 准确率: NN%（建议: +N 条新映射，-N 条过宽映射）
- test-groups 耗时偏差: 平均 NN%（建议校准 N 组）
- 稳定性变化: N 项新增 flaky，N 项恢复稳定

### 经验提炼
- 新 lesson 候选: N 条
- 通用模式候选（可升级到 protocol/Tier 1）: N 条
- Tier 1 规则降级候选: N 条

### Bug 趋势
- 热点模块: [列表]
- 重复根因: [列表]

## 修改建议列表
[逐条列出，每条可独立接受/拒绝]
```

---

## 一致性检查

reflect 修改知识文件前，执行与 test-execution-workflow 相同的一致性检查（见 test-execution-workflow.md "一致性检查"段）。

特别注意：
- reflect 建议升级到 protocol 的内容 → 必须走 `/better-test protocol-update` 流程，不能直接写
- reflect 建议修改 impact-map → 来源标为 `inferred-from-history`（不是 verified，除非有单次运行的直接验证）
- reflect 建议新增 lesson → evidence_level 标为 `confirmed`（多次出现）或 `proven`（有 root cause 验证）

---

## 不要做的事

- ❌ 不要把 reflect 建议直接写入知识文件 — 必须经过用户确认
- ❌ 不要把相关性当因果 — "改了 X 后 Y 组 fail 了 2 次"可能是巧合，标 inferred 不标 verified
- ❌ 不要在数据不足时做趋势分析 — 少于 3 次运行不足以判断趋势
- ❌ 不要把 reflect 当成 update — update 处理当前会话的结构性变化，reflect 处理历史积累的经验

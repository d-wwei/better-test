# 测试方法论：设计理由与研究依据

> **本文件面向人类读者**（skill 维护者、想理解"为什么这样设计"的用户）。
> Agent 执行时不加载本文件。核心步骤在 workflow 文件（Tier 1）和 procedures/ 目录（Tier 2）。
> 本文件合并了原 5 个方法论文件的设计理由和研究数据。

---

## 一、覆盖率体系设计理由

### 为什么用可达覆盖率而非总覆盖率？

很多项目物理上不可能在单次测试中覆盖 100% 接口（休市/环境缺/安全禁跑）。如果用总覆盖率，full 模式永远达不到 100%，阈值就失去了意义。可达覆盖率 = 已测 / (总数 - 物理不可测)，让 100% 成为真正可追求的目标。

### 为什么覆盖率不是最重要的指标？

ICSE 2014 里程碑研究（Inozemtseva & Holmes）：控制测试套件大小后，覆盖率与缺陷检出仅有低到中等相关性。测试数量比覆盖率百分比更能预测有效性。
来源：[Coverage Is Not Strongly Correlated with Test Suite Effectiveness](https://www.cs.ubc.ca/~rtholmes/papers/icse_2014_inozemtseva.pdf)

Goodhart 定律：当覆盖率成为目标而非度量，团队行为扭曲——为凑数字写无意义测试。

### 质量度量优先级

1. **变异测试得分** — Google 6000 工程师使用，87%+ 变异体被杀死。增量式（只对变更代码）解决了成本问题。来源：[Practical Mutation Testing at Scale (TSE 2021)](https://homes.cs.washington.edu/~rjust/publ/practical_mutation_testing_tse_2021.pdf)
2. **缺陷逃逸率** — 精英团队 < 2%（Capers Jones 数据）
3. **断言密度** — AI 生成测试中位断言 2.0，可能引入 Assertion Roulette。来源：[arXiv 2025](https://arxiv.org/html/2603.13724)
4. **MTTR** — 反映反馈循环效率
5. **覆盖率** — 防遗漏但不代表"测得好"

### 测试金字塔

经典比例 70% 单元 / 20% 集成 / 10% E2E（Mike Cohn）。冰淇淋反模式（E2E 重、单元轻）是最常见的结构问题。

### 组合方法的 DRE

Capers Jones 40 年数据：单元测试 DRE 25-35%，代码审查高达 85%，组合方法可达 97%+。单一测试方法的效果有上限。
来源：[Software Defect Removal Efficiency](https://www.ppi-int.com/wp-content/uploads/2021/01/Software-Defect-Removal-Efficiency.pdf)

---

## 二、调查方法设计理由

### 为什么 5 级证据分级？

原始设计是二分（"推测 vs 定论"）。从 systematic-debugging 借鉴了 5 级分级——因为测试中的证据有明确的可信度阶梯：strings binary 推测 < debug log 直接观察 < wire capture 金标准 < 源码权威。二分法无法区分"debug log 观察"和"源码验证"的可信度差异，而这个差异在报告根因时很关键。
来源：[systematic-debugging SKILL.md](https://github.com/d-wwei/systematic-debugging)

### 为什么 3-假设规则？

systematic-debugging 的统计：假设 1（直觉）正确率 ~60%，假设 2（替代）覆盖 ~30%，假设 3（反思）覆盖 ~10%。3 个假设覆盖 ~99% 的情况。

3-失败规则（3 个都错 → 停下重审前提）防止无效的随机尝试。

### 错误解读三问的来源

来自实际项目教训：v1.4.37/38 版本中 daemon 把 backend 的 `-102 CONN can not find command service` 硬包成 `-400 bad request` + 一串自检 hint，误导排查方向。三问的核心是"先判断错误码来源再行动"。

### Bug 分类表

借鉴 systematic-debugging 的 6 类（Regression / Integration / Edge case / Environment / Data / Concurrency），每类有不同的调查方向和 strategy 推荐行为。

---

## 三、测试设计方法论设计理由

### 为什么 MECE + 场景化并存？

结构化 group（按技术分：HTTP/REST/MCP）适合 CI 和 strategy 推荐——边界清晰、命令明确。但缺乏业务视角——"交易用户关心什么"这个问题 group 回答不了。

场景化 scenario（按业务分：期权/交易/Agent）填补这个空白。两者互补：group 回答"怎么跑"，scenario 回答"为什么跑"。

### 对照组的价值和陷阱

加对照组比加失败项更重要——bug report 有对照说服力翻倍。但对照条件必须等价，否则无效。三个常见陷阱：
- sim 不走 unlock（条件不等价）
- 开市 vs 休市对比（行为本身不同）
- 空账户 vs 有持仓（不等价）

### TDD 的工业证据

Microsoft + IBM 四团队案例研究（Nagappan et al., 2008）：缺陷密度降低 40-90%，初始开发时间增加 15-35%。
来源：[Realizing Quality Improvement Through TDD](https://www.microsoft.com/en-us/research/wp-content/uploads/2009/10/Realizing-Quality-Improvement-Through-Test-Driven-Development-Results-and-Experiences-of-Four-Industrial-Teams-nagappan_tdd.pdf)

### BDD 的适用条件

有结构化需求文档时有效。没有 PRD 时不强行套——直接用 MECE + 代码分析。

### 契约测试

微服务测试最重要的演进之一（Martin Fowler）。消费者驱动，比全链路 E2E 更稳定更快。
来源：[Pactflow — Contract Testing vs Integration Testing](https://pactflow.io/blog/contract-testing-vs-integration-testing/)

### 探索性测试效率

F-Secure TET 研究：0.99 缺陷/小时 vs 脚本 0.24 缺陷/小时（4 倍差距）。
来源：[The Effect of Team Exploratory Testing](https://mmantyla.github.io/Raappana_TAIC-PART-2016_The_Effect_of_Team_Exploratory_Testing-Experience%20Report%20from%20F-Secure.pdf)

---

## 四、执行纪律设计理由

### 为什么凭证必须开测前一次性收齐？

实际项目教训：测到一半才发现缺凭证 → "下次补" → 永远不补 → 漏测。

### 为什么不允许 🟡 作为终态？

🟡 是"待确认"——不是 pass 也不是 fail。如果允许 🟡 停留，这些项永远不会被升级。久而久之，🟡 累积成"都不知道是好是坏"的测试债务。

### Flakiness 稳定性评分

Google 数据：约 16% 的测试存在某种 flakiness，84% 的 pass→fail 转换涉及 flaky 测试。二分法（flaky/非 flaky）不够用。
Meta 开发了概率化 Flakiness 评分（PFS），用贝叶斯推断，把 flaky 从二分变成连续光谱。
来源：[Meta — Probabilistic Flakiness](https://engineering.fb.com/2020/12/10/developer-tools/probabilistic-flakiness/)

### 反模式

- 冰淇淋反模式：金字塔倒置
- Assertion Roulette：单测试 5+ 断言
- Happy Path 偏好：只有正向测试
来源：[NDepend Blog — Should You Aim for 100% Coverage?](https://blog.ndepend.com/aim-100-percent-test-coverage/)

### 小批量变更

DORA 2024 连续两年发现 AI 工具提升个人生产力但损害交付表现，根因是更大变更批量。
来源：[DORA 2024 Report](https://dora.dev/research/2024/dora-report/)

---

## 五、环境与工程陷阱（项目经验）

这些来自实际项目教训，不是通用研究，但对类似项目有参考价值：

- **端口清场**：moomoo_OpenD 和 Rust futu-opend 绑同端口，macOS 给 localhost 绑定优先者，lsof 是唯一可靠检测
- **UTF-8 截断**：head -c N 切坏多字节 → json.dump 崩 → results.json 写一半中断。用 python3 字符截断
- **测试环境隔离**：只 kill --managed 模式启的 daemon，临时文件保留 7 天，测试数据用 tmpdir
- **daemon hint 不可全信**：v1.4.37/38 教训——daemon 把 backend 错误码包装成模糊 hint

---

## 六、Bug Report 格式设计理由

7 节格式来源于实际 bug 报告的效果评估：

- TL;DR — 接收方 10 秒判断优先级
- 现象矩阵 — 用表格让 pattern 可见（比叙述有效得多）
- 关键对照 — 对照让报告说服力翻倍
- 权限/账号排除 — 排除"用户配置错误"这个最常见的误报来源
- Root cause 推测 — 必须标证据级别，避免猜测被当定论
- 复现步骤 — 可复制粘贴执行，不是"试一下 X"
- 影响评估 — 让决策者判断优先级

yaml 元数据块（status / evidence_level / bug_type）供 agent 机器读取，用于 strategy 的回归推荐。

---

## 七、"验证者思维 vs 测试者思维"教训

来源：2026-04-20 真实项目测试反思（history-order-fills API 测试中 7 小时未发现、同事 10 分钟锁定的 bug）。

### 核心教训

测试者（agent）在写 curl / 请求 body 时下意识写"自己觉得合理的参数"——完整字段、正确类型、合法值。这是**验证者思维**（验证接口能不能工作），不是**测试者思维**（找到接口在什么条件下会坏）。

具体表现：
1. 只跑 happy path，从没试过"不传 filterConditions"或"只传一半"
2. 没有系统枚举字段的 presence × absence（缺失/空/合法三态）
3. 对照组比较时也只传完整参数，失去了揭示 default-filling 差异的价值
4. 同事（或同事让 LLM 跑的）省略了 optional 字段立刻撞上 bug——因为 schema 没标 required

### 为什么加入三种用户姿态

测试请求应模拟三种写法：
- **熟悉者**：完整参数（你的默认，最不可能触发 bug）
- **新手**：只传 required，省略所有 optional（最常暴露 default-filling / validation 缺失）
- **LLM agent**：只传核心字段、名称可能有变体（暴露参数容错性）

后两种是最能暴露 daemon/server 客户端侧 default fill / validation 缺失的姿态。这条来自"自测 7 小时没发现、同事 10 分钟锁定"的直接教训。

### 字段三态枚举的依据

API 契约里每个可选字段应至少测 3 种状态：key 缺失 / key 存在但值为空 / key 存在且合法。只测第 3 种 = 只测 happy path。boundary testing 完全缺席是 agent 最常见的盲区。

# Test Execution Workflow

测试执行框架。本文件不是固定流程——它是一个**框架 + 模板**，agent 在实际执行测试时结合通用知识 + 项目专属知识生成当次执行计划。

## 设计理念

固定流程无法适应所有项目。一个金融 daemon 的测试执行和一个 CLI 工具的测试执行差异巨大。本 workflow 提供：

1. **通用框架**（本文件）— 所有项目共用的执行纪律和标记规则
2. **项目知识注入点**（标记为 `[PROJECT]`）— agent 从 `.better-work/test/` 读取项目专属信息填入
3. **生成的执行计划**（输出到对话中）— 结合 1+2 为当次测试生成具体步骤

## 执行计划生成

每次开始测试执行前，agent 按以下步骤生成当次执行计划：

```
输入：
  strategy 推荐的测试组和模式（来自当前 run 目录的 strategy-plan.md，或会话内 strategy 输出）
  + test-groups.md       [PROJECT] 测试组定义（运行命令、条件、断言）
  + impact-map.md        [PROJECT] 变更影响映射
  + known-issues.md      [PROJECT] 已知问题（suppress / flaky / lessons）
  + protocol.md          [PROJECT] 测试认知约束
  + 用户提供的材料       [PROJECT] API 规范、错误码表、测试账号等

输出：
  当次测试的具体执行计划（在对话中展示给用户确认）
```

### 执行计划模板

```markdown
# 测试执行计划 — v<version> <mode>

## 环境确认（从 env-config.md 生成）
- [ ] 服务状态: [PROJECT: 从 env-config.md 服务表提取，逐项检查健康状态]
- [ ] 端口清场: 启动前 `nc -z 127.0.0.1 <port>` 确认空闲；启动后 `lsof -nP -iTCP:<port> -sTCP:LISTEN` 确认是自己 PID（daemon 可能静默 bind 失败但继续跑 → curl 打到别人的 daemon）
- [ ] 进程识别: pgrep 模式精确到 port+account（不只 binary name），多 daemon 环境 PID+name 不够
- [ ] 测试账号: [PROJECT: 从 env-config.md 账号表提取，确认状态=可用]
- [ ] 环境变量: [PROJECT: 从 env-config.md 环境变量表提取，确认已设置]
- [ ] 时间依赖: [PROJECT: 从 env-config.md 时间依赖表，当前是否在窗口内]
- [ ] 不可逆操作策略: [PROJECT: 从 env-config.md 不可逆操作清单] → 用户已选: a) 全执行 / b) 逐项问 / c) 全跳过

## 执行顺序
[PROJECT: 从 strategy 推荐的组列表 + test-groups.md 的组定义生成]

### 组 <Letter>: <Name>（<N> 项）
- 运行命令: [PROJECT: 从 test-groups.md 取]
- 关键断言: [PROJECT: 从 test-groups.md 取 EXPECT_PATTERN]
- 已知问题: [PROJECT: 从 known-issues.md 取该组相关的 suppress/flaky 项]
- 预计耗时: [PROJECT: 从 test-groups.md 取]

### 组 <Letter>: <Name>（<N> 项）
...

## 本次需特别注意
- [PROJECT: 从 known-issues.md lessons 段取与本次测试组相关的经验]
- [PROJECT: 从 impact-map.md 取本次变更可能影响但未在推荐组内的边缘区域]
```

---

## 通用执行纪律（Tier 1 核心流程）

以下规则适用于所有项目的所有测试执行，不依赖项目专属知识。

### 四色标记

每个测试项执行后立即标记结果：

**标准模式**（无对照基准）：

```
✅ = 返回值正常 + 关键字段已验证（具体字段名 + 值）
🟡 = 待确认（模糊错误或空结果）→ 必须升级，不是终态
🔴 = 失败（有错误码或 log 证据）
⏭️ = 显式跳过（必须写原因）
```

**Compare 模式**（有对照基准时，规则更严格）：

```
✅ = 被测返回值正确 + 与基准一致（两者都验证了关键字段）
🟡 = 被测返回值看起来对但没做基准对照 → 必须补做对照才能升级
🔴 = 被测与基准不一致（基准正常但被测异常）
⏭️ = 显式跳过（必须写原因）
ℹ️ = 被测有但基准没有（新功能，不算 fail）

关键规则：compare 模式下，没做基准对照的不能标 ✅，只能标 🟡。
```

### Pass 判定 4 件套（标 ✅ 前必须全部满足）

```
1. 下游效应真发生: ret_type=0 只是前提条件，不是充分条件
   → 状态改动类（subscribe/place-order/unlock）：follow-up 查询验证状态确实变了
   → 查询类（funds/orders/quote）：验证字段值语义正确，不只看 shape 非空

2. Silent empty 排除: 看到 ret=0 + 空/默认数据 → 不能直接标 pass
   → 用已知有数据的参数对照（如 US.AAPL rehab 应非空）
   → 传 garbage 参数看是否也返空/返同样数据 → endpoint 可能没真正 parse 参数
   → 合法空（新账户无持仓）vs 没 parse 参数（任何输入都返空）是完全不同的情况

3. 跨 surface 一致: 如果同 endpoint 在另一 surface（MCP/CLI）有不同行为 → 不能标 pass
   → 同 daemon 同 backend 不同 surface 行为不一致 = surface translator 层 bug

4. 基准对照（compare 模式下）: 被测结果必须和基准一致
   → 详见 Compare 模式四色标记规则
```

### 结构化测试记录（每个测试项必填）

每标记一个测试项结果时，必须填写以下结构化记录。此记录同时写入 process-log.md 和 results.json。

**必填字段不能为空——空字段 = 不能标 ✅。**

```markdown
### <Test-ID>: <Name>
- 基准结果: <必填（compare 模式）| "无基准" + 原因（标准模式）>
- 被测结果: <必填：实际返回值摘要>
- 对比: <match / mismatch / not_compared / no_baseline>
- 断言字段: <必填：验证的具体字段名，如 "power">
- 断言值: <必填：实际值，如 "153.2">
- 状态: <✅ / 🟡 / 🔴 / ⏭️>
- 证据级别: <indirect / direct / binary / confirmed / proven>
```

**验证规则（状态 ≤ 字段组合约束）**：

| 如果... | 则状态不能是... | 只能是... |
|---------|---------------|----------|
| `基准结果` = 空 且 compare 模式 | ✅ | 🟡（补做对照后才能升级） |
| `断言字段` = 空 | ✅ | 🟡 或 🔴 |
| `证据级别` = indirect | ✅ | 🟡（升级证据后才能标 ✅） |
| `对比` = mismatch | ✅ | 🔴 |

**这不是建议，是结构约束**——模板的必填字段跳不过，违反验证规则的组合不允许。

### 🟡 升级路径（产生时就地解决，不积累）

🟡 产生时**立刻**升级——"先全部跑完再处理 🟡"的思路导致 🟡 永远不会被处理。

```
🟡 检测到空结果或模糊错误
  ↓
grep daemon/service log 查 error code
  ↓
有 error code → 🔴（附 code）
无 error code → ✅（确认真空）
模糊 hint   → 错误解读三问（见下方）
```

### 错误消息先读——不 blind retry

```
不同错误码是不同根因，blind retry → 可能触发 anti-flood / rate-limit：
  ret_type=-1  → 通用错误，看 daemon log 详情
  ret_type=-8  → 需要 OTP 二次验证
  ret_type=-15 → 重试间隔过短或 session 冲突
  ret_type=-20011 → 功能不支持（如 moomoo 端 unlock）
  
  先读 hint/error_code → 判断根因 → 针对性处理。不要看到 error 就重试。
```

### 错误解读三问

遇到模糊错误（-400 / -1 / 含 hint 的错误）时：

```
1. 来源：服务自加的 hint 还是 backend 真错？→ 看 debug log 原始 code
2. 参数 vs 程序：换确定正确的等价参数还报同样错？→ 排除参数问题
3. 验证假设：写下"如果是 X，会看到 Y" → 去找 Y → 没有则换假设
禁止：直接重试 / 直接换参数 / 直接放弃
```

三问无法定位 → 加载 Tier 2 `procedures/hypothesis-investigation.md`（3-假设调查法）。

### 预期错误 ≠ 测试失败

API 返回错误码不一定是 bug。区分三种情况：

```
1. 业务拒绝（如 -400 "insufficient balance"）
   → 如果测试场景预期被拒绝（权限测试、边界测试），这是 ✅ pass
   → 关键：验证错误码和错误消息是否与预期一致

2. 参数错误（如 -1 "invalid parameter"）
   → 先排除是测试自身参数写错。换已知正确的参数重跑
   → 如果确认参数正确但仍报错 → 🔴 这是 bug

3. 服务内部包装（如 daemon 把 backend -1001 包装成 -400）
   → 看 debug log 中的原始错误码，不依赖外层包装
   → 包装导致信息丢失本身可能值得作为 lesson 记录
```

经验法则：**错误码是数据，不是判决**。pass/fail 取决于"这个错误码在当前测试场景中是否是预期行为"。

### 证据分级

每个判断必须标注证据级别：

| 级别 | 可用于 | 典型来源 |
|------|--------|---------|
| **indirect** | 仅用于形成假设 | 行为观察、类比推断 |
| **direct** | ✅ pass 判定、🔴 fail 报告 | debug log、命令输出、具体字段值 |
| **binary** | 验证"代码修改确实生效了" | `strings binary \| grep` 证明 literal 变化 |
| **confirmed** | 根因确认、写入 known-issues lessons | 多重直接证据 + 基准对照交叉验证 |
| **proven** | 系统性模式、更新 impact-map 为 verified | 源码/proto 验证、多版本验证 |

不允许 guess 级别出现在任何输出中。

**binary 级证据的使用场景**：当开发者声称"修了一个 hardcode 字符串"或"改了错误消息格式"，用 `strings <binary> | grep "<关键字>"` 验证 literal 是否真的变了。这比"跑接口看返回"更直接——证明代码路径确实改了，不只是"碰巧返回对了"。

### 证据质量纪律

```
1. 推测即验证: 标了推测/indirect 的结论必须在当 Phase 内验证（查基准/查 debug log/换参数重跑）
   → 标注和验证在同一个动作中完成。"标了推测继续往下测"= 永远不会回来处理的 TODO

2. 单次观测不定论: 异常值不能单次定论（不能定"是 bug"也不能定"不是 bug"）
   → 至少两个时间点采样（间隔 ≥5min）+ 参考实现对照，再下结论
   → 区分暂态(cache 延迟) vs 持久(真 bug)。暂态值未确认持久性不得报 bug

3. 合理化阻断: 看到异常现象后，先查参考实现（App/UI > C++ > 被测对象），后下结论
   → "可能是设计如此"/"可能是闭市"/"可能是我参数写错了"不是调查终点
   → 顺序不能反：先合理化再查证据 = 确认偏误

4. 覆盖声明: 声称"X surface 一致"必须附验证数量占总数比例
   → "4 项验证一致"不能说成"三 surface 一致"（实际有 184 个接口）

5. "推断"标签必须附升级步骤: indirect/inferred 不是终态
   → 每个推断标签需说明"做什么能升级为 direct/confirmed"
   → 如"推断未修" → 具体升级步骤："启 daemon + 用 X 参数跑 Y 命令 → 看 Z 字段"

6. Before/After diff 是判定 fix 生效的最强证据类型
   → 同账号同数据，v1.4.N vs v1.4.N+1 对比
   → 15 分钟下载多版本 binary 可以把 direct 升到 proven（4 版本一致 = 非偶然）

7. 每个数据点需附 timestamp + 环境状态
   → 无时间戳的数据无法交叉对账，异时数据无法对比
   → 环境状态（如 market session open/closed）影响结论有效性

8. 时间计算必须用工具
   → Epoch 转换用 `date -r <epoch>` 或 Python `datetime.fromtimestamp()`，不手算
   → 手算错 8 小时的真实案例（UTC vs local 混淆）
   → `ls -la` 用 local time，daemon log 用 UTC——时间戳一律转 UTC 作 SoT

9. Self-correct 触发信号
   → 结论只基于 binary evidence、只测了单一 mode、CHANGELOG 只验了一半、或 verdict 只基于单一 signal
   → 任一命中都要主动补 1 轮验证，不等 coord / peer 来 challenge
```

### Binary 落地 ≠ runtime 生效

```
binary / strings 证据只能证明"代码或字面已经进包"：
  → 可以证明 code landed / literal present
  → 不能单独证明 runtime path hit / state machine 生效 / cooldown 真挡住了

以下类型的 claim 必须 live runtime：
  - 安全修复
  - retry / cooldown / backoff
  - wiring / route / state machine
  - silent success → loud fail

结论规则：
  binary-only → 最多写 "代码已落地"
  runtime 命中 + field/log/counter 对齐 → 才能写 "fixed"
```

### 每个接口的测试深度（happy path 只是起点）

happy path 通过后，对每个接口主动尝试 break——silent failure 最难抓，必须主动找。

**三种用户姿态测试**：

```
对每个 API / 接口 / 命令：

1. 熟悉者姿态（你的默认方式）：完整参数、正确类型、合法值
   → 这是 happy path，过了只是基线

2. 新手姿态：只传 schema 标 required 的字段，省略所有 optional
   → 暴露 daemon/server 是否正确处理缺省值（最常见的 silent failure 来源）

3. LLM agent 姿态：只传核心字段，名称可能略有变体
   → 暴露参数名容错性和 validation 健壮性
```

**字段四态枚举**（每个可选字段至少测 4 种状态）：

```
对 API 的每个可选字段：
  状态 1：key 缺失（不传这个字段）
  状态 2：key 存在但值为空（null / "" / {} / []）
  状态 3：key 存在且值为 false / 0 / 空串这类"有效但假值"
  状态 4：key 存在且值合法非空（正常值）

只测了状态 4 = 只测了 happy path。
状态 1、2、3 是暴露 default-filling、proto3 default、null-filter、validation 缺失的关键。
```

### Claim Scope 五问

```
每条 claimed fix / release note / peer verdict，都先问 5 个 scope 问题：
1. 只修了 happy path 吗？
2. 只修了一个 mode 吗？（auth / legacy / default / real / sim）
3. 只修了一个 surface 吗？（REST / CLI / MCP / WS）
4. 只证明了 binary literal 落地吗？
5. error path、missing field、wrong enum 是否仍然 silent？

任一问题答不清，就不要写笼统的"已修"。
结论必须写成带限定词的句子，例如：
  "fixed in auth mode"
  "REST loud-fails, MCP 未验证"
  "code landed, runtime 未确认"
```

### Control Experiment / Same-State Contrast

```
遇到 silent-drop、parser mismatch、contract drift 时，不要只盯着怀疑 endpoint 重试。

标准做法：
  1. 找一个同 daemon、同账号、同 state 下已知会 loud-fail 或已知正确的 sibling endpoint
  2. 用同一组输入分别打 baseline 和 suspect endpoint
  3. 比较 truth-value：
     - baseline loud / suspect silent
     - baseline 正常生效 / suspect ret=0 但零效果
  4. 这个 same-state contrast 往往比孤立重试更快拿到实锤
```

### Functional / Timing / Result 三层验证

```
对长跑、自愈、重连、重试、状态切换类 bug，不要只看"好像执行了"：

1. Functional layer: 路径真的被 invoke 了吗？（counter / marker / raw log hit）
2. Timing layer: 发生的时间窗口对吗？（backoff / ladder / cooldown 时间）
3. Result layer: 执行后结果真的对吗？（目标 state flip / push 恢复 / 数据恢复流动）

三层都对齐才算 PROVEN。
任意一层缺失 → 只能写 INCONCLUSIVE 或 direct，不要过度定性。
```

**其他负向场景**（按适用性选择）：

```
- 错误字段类型：string 传 int、int 传 string、array 传 object
- 字段冲突：传了互斥的参数组合
- 边界值：最大值 / 最小值 / 0 / 负数 / 超长字符串
- 特殊字符：中文 / emoji / SQL 注入 pattern / HTML 标签
```

**对照组也要变参**：

对照组不能只用完整参数。如果 happy path 对照和 happy path 测试都传完整参数，对照失去了揭示 default-filling 差异的价值。对照时也用新手姿态 / 缺字段版本，才能发现"一个实现填了默认值另一个没填"的差异。

### 终态规则（4-state verdict）

```
每个测试项必须到达终态之一：✅ / 🟡→PARTIAL / 🔴 / ⏭️

  ✅ PASS      = 功能完全按预期工作（field-level 证据）
  🟡 PARTIAL   = 部分工作但范围有限 / 环境依赖 / caveat 存在
                  例：V5 G6 field 正确 parse 但 doctrine 语义错
                  PARTIAL 是合法终态（不同于需升级的初始 🟡）
  🔴 FAIL      = 失败（有错误码或 log 证据）
  ⏭️ SKIP      = 显式跳过（必须写原因，视觉必须醒目）

不允许：
  "暂时跳过"（无原因）
  "下次再看"（不会有下次）
  "应该没问题"（是 guess，不是 evidence）
  初始 🟡 停留（必须升级为上述 4 态之一）

二元 ✅/❌ 丢失 nuance。PARTIAL 防止强行标 ✅ 掩盖 caveat。
```

### 安全守则

```
- 不把账号/密码/token 写入任何 .better-work/ 文件
- 不可逆操作按用户在"环境确认"中选择的策略执行
- 即使用户允许全执行，也优先用安全方式（sim 账户 + 远离市价 + 立即撤单）
```

### 清理纪律（session 结束 checklist）

```
测试完成或 session 结束前：
1. kill 所有测试进程（daemon、采样器、monitor）→ `kill $(cat /tmp/daemon-<tester-id>.pid)`
2. 删 /tmp 含凭据的文件 → `rm -f /tmp/futu-pwd-*`（trap EXIT 更好）
3. cancel orphan orders → 先尝试 `/api/cancel-all-order`，不行则标注"需用户清理"
4. 副作用作为 bug 的"外部性成本"显式列出 → 如"测试消耗了 $X margin"

敏感文件最佳实践：trap "rm -f $TMPFILE" EXIT 在启动时设置，不依赖手动清理。
```

---

## 执行过程中的 Tier 2 触发点

执行过程中遇到以下情况时，加载对应的 Tier 2 扩展流程：

| 触发条件 | 加载什么 |
|---------|---------|
| 三问无法定位失败原因 | `procedures/hypothesis-investigation.md` |
| 同一测试连续 2 次结果不一致 | `procedures/flakiness-scoring.md` |
| 用户要求对某模块做深度探索 | `procedures/exploratory-charter.md` |
| 发现 bug 需要写报告 | `methodologies/bug-report.md`（可执行模板） |

---

## 执行记录

L1 Hook（执行日志记录）自动把每条 Bash 命令 + 输出追加到当前 tester 的 run 目录内 `execution-log.md`。Agent 不需要手动记录执行过程——Hook 替它做（需要 `.active-sessions/` 中的 session 文件来定位 run 目录）。

Agent 需要做的记录：
- 每个测试项的四色标记结果 → 写入 results.json
- 每个 ⏭️ 的跳过原因 → 写入 results.json
- 发现的新问题 → 记到对话中，测试完成后由 update workflow 处理

---

## 测试执行中发现 bug

测试中遇到确认的 🔴 fail（evidence: direct 或更高）且不在 known-issues 已知列表中：

```
1. 加载 procedures/bug-report.md 模板
2. 按 7 节格式写 bug report（两层结构：先大白话说影响，再技术细节）
3. 先分 Observation / Interpretation / Impact 三层
   → 观测是什么，和你如何解读、谁会受影响，必须分开写
4. severity 用"最坏场景下谁受影响"定，不用自己碰到的场景。pre-existing 记在 fix_note 不降 severity
5. pre-existing 必须标注（found_in 字段）——不标注开发者会误判为回归
6. changelog 声称修复但实测未变 → 醒目标注 [CHANGELOG 声称修复但未确认]
7. 如果没有 live repro，只做了 evidence audit / accepted peer evidence，也要显式写出
8. 写入 run 目录内 bugs/BUG-NNN-<slug>.md（run 内编号）
9. results.json 中相关 items 的 bug_ids 填入 BUG-NNN
10. 单 tester: 完成后更新 bugs-index.md；多 tester: 由 /better-test merge 合并
11. 继续执行剩余测试（不因发现 bug 中断整组测试）
```

Bug ID 全局递增。如果不确定是不是新 bug（可能是已知 bug 的新表现），先检查 bugs-index.md。

### Bug Retest 规则

```
对 FIXED 未 VERIFIED 的 bug 做 retest 时：
1. sim≠real: 涉及 backend 交互的 bug retest 必须用 real 账号。sim 错误码可能与 real 不同，同一 bug 在 sim 上可能不可见
2. 全路径覆盖: bug 标 VERIFIED 前必须覆盖所有已知 failure paths。changelog 提到"补修某路径"时该路径必须单独验证
3. 跨 tester 复现: 采信其他 tester 的 bug 前必须亲自复现——复现不只是确认，还能帮自己排查问题
```

---

## 测试过程记录：两层机制

### 第一层：execution-log.md（Hook 自动生成，必定存在）

L1 Hook 自动记录每条 Bash 命令和输出到 tester 的 run 目录内 `execution-log.md`（通过 session 文件定位）。Agent 不需要手动做任何事——Hook 替它做。这是不可篡改的执行记录，L2 审计的数据源。

### 第二层：process-log.md（Agent 手写，最佳实践但非强制）

> **Phase B 实测发现**：两个 tester 都从未手写过 process-log。Agent 的行为是"跑完写 summary"而不是"边跑边记"。因此 process-log 从"必须产出"降级为"有最好，没有也可以——execution-log 作为底线保证过程可追溯"。

如果 agent 愿意写 process-log（鼓励但不强制），格式如下：

```
## [MM-DD HH:MM:SS±ZZ] <做了什么>
<具体细节>

## [MM-DD HH:MM:SS±ZZ] <发现了什么>
<证据>

## [MM-DD HH:MM:SS±ZZ] ⟲ 推翻 [HH:MM] 的判断
原来以为: <旧结论>
实际是: <新结论>
```

原则：只追加不删改，记录犹豫和转折，记录"试了没用"的路径。

### 两层的关系

| | execution-log | process-log |
|--|---------------|-------------|
| 谁写 | Hook 自动 | Agent 手动 |
| 一定存在吗 | **是**（Hook 部署后） | 否（鼓励但不强制） |
| 内容 | 原始命令 + 输出 | 推理过程 + 转折 + 判断 |
| 用途 | L2 执行审计（对照声称 vs 实际） | 人类复盘（理解 agent 为什么这样判断） |
| 归档到 run 目录 | 是 | 是（如存在） |

---

## 测试完成后：输出 + L2 审查 + 归档

> post-test-checklist hook 会在 results.json 写入后自动注入提醒清单。按清单逐项执行。

```
1. 写入 results.json → history/<version>/run-<tester-id>-NNN-<ts>/results.json
2. 生成 2 分钟速览 → run 目录内 summary.md
3. 汇总 bug reports → run 目录内 bugs/（每个 bug 独立文件，run 内编号 BUG-NNN）
4. 触发 L2 独立验证（读 references/l2-audit-prompts.md，spawn 子 Agent）
   → 子 Agent 读 run 目录内 execution-log + results + manifest + known-issues
   → 输出 run 目录内 l2-findings.md
5. 基于 l2-findings 生成 run 目录内 audit-report.md
6. 所有文件已直接在 run 目录内产出，无需归档复制步骤
7. 向用户呈现（按顺序）：
   a. 先呈现 2 分钟速览（用户第一时间看到核心结论）
   b. 再呈现审计面板（用户确认质量 → 通过 / 打回 / 调查）
   c. 过程日志和 bug report 不主动呈现，用户需要时 Read
9. 如有 bug-retest 中的项复测通过 → 更新 bugs-index.md 对应 bug 为 VERIFIED
10. 增量 reflect（自动执行，见下方）
11. 建议 /better-test update 更新知识（如有新发现）
12. 建议 /better-test checkpoint（如任务未完成）
```

### 输出文件定位

| 文件 | 受众 | 来源 | 必须存在？ |
|------|------|------|-----------|
| `execution-log.md` | L2 审计员 + 人复盘 | **Hook 自动生成** | 是（Hook 部署后） |
| `results.json` | Agent + L2 | Agent 写入 | 是 |
| `summary.md` | 所有人（2 分钟） | Agent 写入 | 是 |
| `bugs/BUG-*.md` | 开发者 | Agent 写入 | 是（有 bug 时） |
| `l2-findings.md` | 审计面板 + 人 | L2 子 Agent 写入 | 是（full/targeted） |
| `audit-report.md` | 人（30 秒判断） | 主 Agent 组装 | 是（有 L2 时） |
| `process-log.md` | 人复盘 | Agent 手写 | **否**（鼓励但不强制，execution-log 是底线） |

### 2 分钟速览模板（summary.md）

```markdown
# 测试速览 — v<X.Y.Z> <mode>
# <日期> | <N> 项测试 | 耗时 <M> 分钟

## 一句话结论
<整体状况：通过/有问题/有严重问题。如 "基本正常，发现 2 个 bug 需要修">

## 发现了什么

<如果有 bug>
🔴 BUG-<NNN>: <大白话一句话说是什么问题>
   实锤: <最关键的一条证据，如 "daemon log 显示 code=-1001 但返回给用户的是 -400">
   影响: <谁会受影响，如 "量化策略用户查不到期权链">

🔴 BUG-<NNN>: <同上>
   实锤: <...>
   影响: <...>

<如果没有 bug>
本轮测试未发现新问题。

## 需要关注但不确定的
<🟡 项或可疑项，大白话说不确定什么>

## 数字
覆盖率: <T>/<R> = <NN>%
✅ <N> | 🔴 <N> | ⏭️ <N>（跳过原因: <...>）
回归验证: BUG-<NNN> <VERIFIED/仍然失败>

## 详细信息在哪
- 完整过程: process-log.md（包含每一步的推理和转折）
- Bug 详情: bugs/BUG-<NNN>.md（可复现步骤 + 对照 + root cause）
- 原始数据: results.json
```

**速览的写作原则**：
- 用大白话，不用术语。"daemon 的错误码包装让用户看不到真正的错误原因"比"daemon augments ret_msg hint masking backend error code"好
- 只讲结论不讲过程。过程在 process-log 里
- 证据只放最关键的一条。不是"我做了 5 步调查"，是"debug log 里看到 code=-1001"
- 影响用"谁会受影响"来说，不用技术术语
- 2 分钟能读完。超过了就砍
- **外部自包含**：给开发者的报告不能引用本地路径。复现步骤、证据、对照全部在一个文件内
- **先列表再数**：写"一共 X 个"之前，先输出编号列表逐个确认状态（active/推翻/合并），从列表机械地数
- **边跑边写**：results.json / process-log 每跑完一项就写一条，不攒到最后补

---

## 增量 reflect（测试完成后自动执行）

每次测试完成后自动执行。用本次运行数据和现有知识文件比较，立即提取可用经验。不需要用户手动触发。

全量 reflect（跨版本趋势分析）见 `references/reflect-workflow.md`。

### 自动应用（纯数学计算，不需要用户确认）

**稳定性评分更新**：

```
对本次 results.json 中每个测试项：
  读 test-groups.md 中该项的当前稳定性评分
  用本次结果更新评分（滑动窗口：最近 10 次运行）
  写回 test-groups.md
```

**耗时校准**：

```
对本次运行的每个测试组：
  实际耗时 = 该组最后一项完成时间 - 第一项开始时间
  预估耗时 = test-groups.md 中该组的"典型耗时"
  偏差 > 50% → 更新 test-groups.md 的典型耗时为：(旧预估 + 实际) / 2
```

### 需要用户确认的建议

**impact-map 映射验证**：

```
本次运行的变更信号（来自 strategy Step 1 记录）
  + 本次实际 fail 的测试组
  → 对比 impact-map.md：

  情况 A：impact-map 有映射 + 本次 fail 了
    → 建议：升级来源为 verified-on-v<X>

  情况 B：impact-map 无映射 + 本次 fail 了
    → 建议：新增映射条目（来源 inferred-from-history）

  情况 C：impact-map 有映射 + 本次没 fail
    → 不做操作（一次不 fail 不代表映射错，可能是巧合）
```

**bug 热点检查**：

```
本次新发现的 bug → 读 bugs-index.md：
  该 bug 所在模块在 index 中已有几个 bug？
  ≥ 3 个 → 建议：标为热点模块，检查 impact-map 中该模块的权重
```

**经验即时提取**：

```
本次 feedback（如有）→ 读 known-issues.md lessons 段：
  这条 feedback 的 note 和某条已有 lesson 类似？
    → 建议：合并/加强该 lesson 的表述
  这条 feedback 的判定模式和历史某条 feedback 相同？
    → 建议：提炼为新 lesson（"第 N 次遇到同样情况"）
```

### 输出格式

```
增量 reflect 完成：
  自动应用：
    ✓ 稳定性评分：更新了 N 项（D-03: 80% → 70%）
    ✓ 耗时校准：C 组 3min → 5min

  建议（需确认）：
    [1/3] impact-map: auth → A 组，升级为 verified-on-v1.4.29
          依据：本次改 auth 后 A-03 fail
          → 接受 / 拒绝？
    [2/3] bug 热点: src/rest/ 模块已有 4 个 bug
          建议在 impact-map 中提升 REST 相关映射权重
          → 接受 / 拒绝？
    [3/3] 经验提炼: "空 funds 是预期行为"已出现 3 次
          建议加入 lessons: "空账户查询 funds 返回空列表是预期，不是 bug"
          → 接受 / 拒绝？
```

---

## 演进机制

本文件不是一成不变的。随着测试经验积累，通用纪律和框架结构都会升级。

### 什么会触发升级

| 触发信号 | 升级什么 | 来源 |
|---------|---------|------|
| 发现新的通用测试纪律 | Tier 1 核心流程段 | `/better-test protocol-update` 或手动更新 |
| 某个 Tier 2 扩展流程被反复使用 | 考虑提升为 Tier 1（嵌入本文件） | update workflow 信号 4 |
| 某条 Tier 1 规则实际执行中从未触发 | 考虑降级到 Tier 2 或删除 | 回顾 execution-log |
| 项目知识变化（test-groups / known-issues 更新） | 执行计划模板的 [PROJECT] 段自动反映 | 无需手动升级 |
| 新增 Tier 2 扩展流程 | 本文件"Tier 2 触发点"表格需同步 | 新建 procedure 文件时 |

### 升级流程

```
1. 识别升级信号（来自 update / feedback / 用户输入 / protocol-update）
2. 草拟修改内容
3. 一致性检查（见下方）
4. 用户确认
5. 写入修改 + changelog 记录
```

### 一致性检查（每次升级必做）

修改本文件的任何内容前，检查是否与以下文件冲突：

```
检查清单：
  □ protocol.md — 本文件的 Tier 1 规则是否与 protocol 的认知约束矛盾？
    例：protocol 说"pass 必须验证字段"，本文件不能有"exit=0 即 pass"的规则
  □ test-groups.md — 本文件的执行顺序/条件是否与 test-groups 的运行条件兼容？
    例：本文件说"组内连续执行"，但某组的运行条件要求交替执行
  □ known-issues.md — 本文件的终态规则是否与 suppress/flaky 规则一致？
    例：suppress 的项不应被标为 🔴 active fail
  □ Tier 2 procedures — 本文件引用的 Tier 2 文件是否都存在？触发条件是否准确？
  □ constraint-framework.md — L0/L1/L2/L3 的约束是否与本文件的执行纪律一致？
    例：L1 Hook 的空结果提问不应与本文件的 🟡 升级路径矛盾
  □ templates.md — 本文件要求的报告格式是否与 templates 中的模板一致？

冲突处理：
  发现冲突 → 不能只改一个文件。确定"哪个是权威源"，然后同步修改所有相关文件。
  权威源优先级：protocol.md > test-execution-workflow.md > procedures/ > templates.md
```

### 变更日志

本文件的每次修改记录到 `.better-work/test/execution-changelog.md`（格式同 protocol-changelog.md）：

```markdown
## [YYYY-MM-DD] <操作>
- **操作**: add / modify / remove
- **段落**: <修改了哪个段落>
- **内容**: <规则文本>
- **来源**: user-input / session-summary / protocol-update
- **一致性检查**: 已检查 N 个文件，无冲突 / 发现冲突并同步修改 [文件列表]
```

---

## 不要做的事

- ❌ 不要跳过"环境确认"直接开跑 — 缺凭证/端口错 = 浪费时间
- ❌ 不要把 🟡 当终态 — 🟡 必须升级
- ❌ 不要在执行中修改 test-groups.md — 执行完后用 update 命令更新
- ❌ 不要在一个组全部跑完前跳到下一个组 — 组内连续执行，组间有序推进
- ❌ 不要忽略 known-issues — 已知 suppress 项不算 active fail，已知 flaky 项要标注
- ❌ 不要修改本文件而不做一致性检查 — 孤立修改会引入文件间矛盾

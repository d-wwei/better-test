# Pending Skill Upgrades

> 通用测试经验的升级队列。**2026-06-11 机制修订**（背景：旧攒批模式积压 21 条 6 周无人审 +
> 6 条账实不符；机制详见 update-workflow Step 5.5）：
> 1. **当场审为默认**：medium 项在 update/reflect 会话内当场展示请 verdict（单次 ≤3 条），
>    本队列只收"用户说稍后再议"的 medium 项和全部 high 项
> 2. **水位红线**：pending ≥ 5 → update 必须先清队再入队
> 3. **Promote 原子三步**：写入 skill 文件 + 更新本文件状态 + git commit 同一动作完成，禁止分离
> 4. **对账**：全量 reflect 分析 7 对本队列账实核对（pending 内容 grep / promoted 落点抽查 /
>    30 天陈化清单）
>
> Agent 不能自行修改 skill 的 protocol 模板、red lines 或 SKILL.md。
> Agent 可以追加到本文件（排队提议）。

## 队列格式

```
### [YYYY-MM-DD] <经验标题>
- **来源项目**: <project-name>
- **来源**: <update session-summary / user-input / reflect>
- **建议目标**: <strategy-workflow / templates.md / protocol-base.md / SKILL.md red lines>
- **风险等级**: low（design-rationale）/ medium（workflow/templates）/ high（protocol-base/red lines）
- **内容**: <具体的规则或修改>
- **证据**: <为什么这是通用的——在几个场景中验证过>
- **状态**: pending / approved / rejected / promoted / promoted-modified /
           already-present（内容已在 skill 中，标注位置，不重复写入）/ pilot
```

## 审批规则

| 目标文件 | 风险 | 审批方式 |
|---------|------|---------|
| `methodologies/design-rationale.md` | low | Agent 可直接写入（纯参考文档） |
| `references/*.md` workflow 步骤 | medium | 展示给用户确认后写入 |
| `templates.md` 质量标准 | medium | 展示给用户确认后写入 |
| `protocol-base.md` | high | 用户确认 + L2 审计 |
| `SKILL.md` red lines | high | 用户确认 + L2 审计 |

## 当前队列

### [2026-04-26] Silent success 检测：ret=0 必须验证下游效应
- **来源项目**: futu-opend-rs (v1.4.57-v1.4.94, 8 testers)
- **来源**: 多 tester session retrospective 综合
- **建议目标**: test-execution-workflow.md (pass 判定规则)
- **风险等级**: medium
- **内容**: ret=0 只是先决条件。pass 必须验证下游效应真实发生（状态改变 / push 到达 / 数据非空且语义正确）。Silent success（ret=0 + 零动作）比 loud error 危险 10x——用户不报错 → 系统不发 ticket → 长期积累
- **证据**: NEW-c22f-012 REST subscribe 跨 7 版无人发现（ret=0 但 daemon 从未发送 CMD6211）；funds currency=null 也是 ret=0
- **状态**: promoted 2026-06-11（确认已存在：test-execution Pass 判定 4 件套条 1/2 即此内容）

### [2026-04-26] 进程存活 ≠ 功能健康：三层验证
- **来源项目**: futu-opend-rs (v1.4.86-v1.4.90 longrun)
- **来源**: 24h 长跑 retrospective
- **建议目标**: test-execution-workflow.md (长跑测试段)
- **风险等级**: medium
- **内容**: (1) 进程存活 (2) 内部状态字段正常 (3) 主业务输出在流动——缺第三层 = 空壳验证。daemon PID 存在 17h + qot_logined=True 但 push stream 完全断裂
- **证据**: dbfb 203 次采样全部 qot_logined=True 但 push_stream_healthy=False + total_pushes 冻结 17h
- **状态**: promoted 2026-06-11（test-execution F/T/R 段补长跑健康三层）

### [2026-04-26] 穷举优于采样：agent 边际成本 ≈ 0
- **来源项目**: futu-opend-rs (c22f/4411/5318 综合)
- **来源**: 多 tester 比较
- **建议目标**: strategy-workflow.md (Stage 2 负向测试)
- **风险等级**: medium
- **内容**: 数值边界 7 点标准（min-1/0/1/值/上限/上限+1/INT_MAX）、枚举字段全扫 0-100、字符串 5 点（空/短/长/格式错/合法）、日期 4 点（倒置/过去/未来/garbage）。人类 ROI 低不穷举；agent 可 24/7 系统扫描
- **证据**: MCP schema 不一致从采样 5 处扩展到穷举 17 处（3.4×）；subscribe whitelist 穷举发现 100% 无效
- **状态**: promoted 2026-06-11（确认已存在：strategy 阶段 2 穷举边界标准；本次补 pairwise/等价类互补条目）

### [2026-04-26] 证据等级 4 级严格定义（不能凭感觉）
- **来源项目**: futu-opend-rs (e4da/2b2f/01b4/5318 综合)
- **来源**: 多 tester 反复犯同样的定级错误
- **建议目标**: templates.md (证据分级段) + test-execution-workflow.md
- **风险等级**: medium
- **内容**: proven = 多版本 binary 或源码/proto 级验证；confirmed = 双向独立复现；direct = 单 tester 观察（哪怕 5 次）；indirect = 逻辑推断。"5 次独立观察 by 1 tester" = direct 不是 confirmed。不得发明中间等级
- **证据**: e4da/2b2f 3 轮定级 drift；01b4 round 4 从 "pass 17" 改 "confirmed 11 + direct 4" 未声明 calibration shift
- **状态**: promoted 2026-06-11（test-execution 证据分级表补定级铁律：confirmed=双向独立复现）

### [2026-04-26] 双向验证 = 不同输入测同一 claim，不是同一输入 ×2
- **来源项目**: futu-opend-rs (01b4/5318 cross-verify)
- **来源**: peer cross-verify 发现
- **建议目标**: strategy-workflow.md (L2/cross-verify 段)
- **风险等级**: medium
- **内容**: 两个 tester 用相同 curl 命令得到相同响应 = 单次观察 ×2，不是双向验证。双向 = 用不同 body/endpoint/工具测同一 claim。P0-E schema vs runtime 两层 split 就是因为两 tester 自然走了不同路径
- **证据**: 01b4 看到 4-variant runtime rejection，5318 看到 9-variant schema acceptance——两人都半对，合并才完整
- **状态**: promoted 2026-06-11（strategy 子 Agent 委托规则条 5：双向验证定义）

### [2026-04-26] 配置依赖型 bug 需多配置矩阵
- **来源项目**: futu-opend-rs (0419 v1.4.93-94)
- **来源**: BUG-0419-001 auth-mode vs legacy 双配置
- **建议目标**: strategy-workflow.md (Step 4 pre-check)
- **风险等级**: medium
- **内容**: 有 mode flag 的 daemon/服务，必须在 smoke test 阶段用双配置（有/无 flag）跑同一组 endpoint，auto-diff 差异。单配置只看到一半
- **证据**: BUG-0419-001 legacy 模式正常，auth 模式 3 endpoint 返 404——单配置测不出
- **状态**: promoted 2026-06-11（strategy Pre-check 条 9：多配置矩阵）

### [2026-04-26] 端口污染：daemon 启动后必须验证绑定成功
- **来源项目**: futu-opend-rs (e4da/2b2f port 22342 事件)
- **来源**: 端口被其他 daemon 占用导致误判
- **建议目标**: test-execution-workflow.md (环境确认段)
- **风险等级**: medium
- **内容**: 启动前 `nc -z` 确认端口空闲，启动后 `lsof -nP -iTCP:<port>` 确认是自己 PID。daemon 可能静默 bind 失败但继续跑，curl 打到别人的 daemon
- **证据**: 22342 被占 → 新 daemon REST 没 bind → curl 路由到另一 daemon → 差异被误判为 bug
- **状态**: promoted 2026-06-11（确认已存在：test-execution 执行计划模板'端口清场'即此内容）

### [2026-04-26] 异步操作观察窗口 ≥30s
- **来源项目**: futu-opend-rs (7c64 v1.4.93-94 REST dispatch)
- **来源**: REST subscribe CMD6211 dispatch 延迟
- **建议目标**: test-execution-workflow.md (证据质量纪律段)
- **风险等级**: medium
- **内容**: 异步 endpoint batch delay ~4-10s。5s 观察窗口 → 误判"0 dispatch"。扩展到 30s 后看到实际 dispatch。异步路径 ≥30s，WS ≥10s，TCP reconnect ≥60s
- **证据**: 7c64 REST subscribe 初判 0 dispatch（5s 窗口），30s 窗口后发现 24 条 CMD6211
- **状态**: promoted-modified 2026-06-11（按通用化措辞写入 test-execution 证据质量纪律条 10；项目校准值留 env-config）

### [2026-04-26] 否定断言需肯定验证（"不存在" ≠ "没找到"）
- **来源项目**: futu-opend-rs (0419 --audit-log, e4da crash log)
- **来源**: strings grep 误判、log 归属错误
- **建议目标**: test-execution-workflow.md (证据质量纪律段)
- **风险等级**: medium
- **内容**: 声称"X 不存在"必须用肯定方法验证（run --help 验证 flag 存在性，而非 grep 返 0 就下结论）。grep 返 0 ≠ 不存在——可能是 stripped、命名不同、或搜错了文件
- **证据**: 声称 v1.4.86 无 --audit-log（strings grep 0），实际 --help 能看到；e4da 声称 silent crash（log 里没看到），实际是看了别人的 log
- **状态**: promoted 2026-06-11（test-execution 证据质量纪律条 11）

### [2026-04-26] 子 agent prompting：上下文 + 资源分配 + 独立性护栏
- **来源项目**: futu-opend-rs (01b4 3 subagent 实战)
- **来源**: subagent 成功模式总结
- **建议目标**: strategy-workflow.md (子 Agent 委托规则段)
- **风险等级**: medium
- **内容**: 成功 prompt 模式：显式指定 daemon 端口/keys/账号；禁止读主 tester 的 bug 判定（保持双向独立性）；25-30min 时间上限；结果纳入不做防御性抵抗。最有价值的是 subagent 推翻主 tester 结论
- **证据**: subagent C 推翻了 BUG-004 severity；3 个 subagent 解决了"单 tester 无法双向验证"难题
- **状态**: promoted 2026-06-11（strategy 子 Agent 委托规则条 4：prompt 护栏/时限/独立性）

### [2026-04-26] 跨 tester 分歧先查环境对齐，不是先查谁对
- **来源项目**: futu-opend-rs (5318/01b4 NEW-C-02 WS token 分歧)
- **来源**: 跨 tester cross-verify
- **建议目标**: strategy-workflow.md (L2/cross-verify 段)
- **风险等级**: medium
- **内容**: 分歧 → 先检查配置差异（一个有 --rest-keys-file 一个没有 → 路由到不同分支 → 各自行为都对）。大多数 cross-verify 分歧源于环境差异而非数据编造
- **证据**: WS /ws token 401 vs 101 分歧 = auth 配置不同；01b4 "0 dispatch" vs 5318 "24 dispatch" = 观察窗口不同
- **状态**: promoted 2026-06-11（确认已存在：strategy 准确度铁律 17 + Peer Cross-Verify 分歧处理）

### [2026-04-26] 用户反复质疑 = QC 系统失效信号
- **来源项目**: futu-opend-rs (4411/01b4/e4da 综合)
- **来源**: 多 tester 共同模式
- **建议目标**: test-execution-workflow.md (自审纪律段)
- **风险等级**: medium
- **内容**: 一个 session 3+ 次用户质疑成立 → 不是用户挑剔，是自己 QC 失效。主动暂停，反思 claim 错误率为什么高。用户工作是 act on 结论，不是给 agent 做 QC
- **证据**: 4411 被反复质疑 over-claim；01b4 "不可能吧" 3 次各发现实质问题
- **状态**: promoted-merged 2026-06-11（与 Over-claim 5 条合并为 test-execution'自审纪律'段）

### [2026-04-26] 观测与解读必须文本分离
- **来源项目**: futu-opend-rs (5318 funds.currency=null)
- **来源**: 用户 challenge
- **建议目标**: templates.md (bug report 质量标准)
- **风险等级**: medium
- **内容**: "currency=null"是观测；"用户会混淆 HK vs USD 账户"是解读。分开写。impact 声明需要独立证据（"HK 账户本来就只有 HK，没混淆空间"→ impact 不成立）
- **证据**: 5318 report 混写观测+解读被用户一句话推翻
- **状态**: promoted 2026-06-11（确认已存在：templates Bug Report 写作规则 O/I/I 分离）

### [2026-04-26] Over-claim 防御 5 条规则
- **来源项目**: futu-opend-rs (4411 session)
- **来源**: 被反复 challenge 后总结
- **建议目标**: test-execution-workflow.md (自审纪律段)
- **风险等级**: medium
- **内容**: (1) 形容词 → 有数字支持？ (2) 关系 → 暗示对等还是层级？ (3) 聚合 → 分类有无 false-positive？ (4) 扮演质疑者角色 skim (5) 用户反复质疑 ≠ 我做对了，是 QC 失效
- **证据**: 4411 session 3+ 次 challenge 均成立
- **状态**: promoted 2026-06-11（test-execution'自审纪律'段，与用户质疑信号合并）

### [2026-04-26] 长跑 24h+ 作独立 session fork
- **来源项目**: futu-opend-rs (bd0a/e4da/dbfb longrun)
- **来源**: 三个 24h longrun session
- **建议目标**: strategy-workflow.md (特殊情况段) 或 test-execution-workflow.md
- **风险等级**: medium
- **内容**: 长跑不占主 session。独立 daemon + 独立采样器 + 独立 tester-id。主 session port-clean 做覆盖。两 session 互不干扰。P1 non-deterministic bug 只有长跑发现
- **证据**: bd0a 24h 发现 F3/F4 节奏规律；e4da 24h 发现 push 44% downtime；dbfb 17h 发现 push stream 冻结
- **状态**: promoted 2026-06-11（strategy 特殊情况段：长跑独立 session fork）

### [2026-04-26] 多版本 binary diff 是 P1+ 定级的高 ROI 投入
- **来源项目**: futu-opend-rs (5318/2b2f v1.4.86-90)
- **来源**: 下载 4 版本 binary 做 strings diff
- **建议目标**: test-execution-workflow.md (证据分级段)
- **风险等级**: medium
- **内容**: 15 分钟下载多版本 tarball，可以：升级 audit perm 到 proven（4 版本一致 = 非偶然）；降级 enum bug 到 pre-existing（v86 就有）；重分类 regression→pre-existing。多版本 diff 改变 severity calibration
- **证据**: 5318 用 4 版本 diff 把 BUG-001 audit perm 从 direct 升 proven；把 BUG-01b4-001 从 regression 降为 pre-existing
- **状态**: promoted 2026-06-11（确认已存在：test-execution 证据质量纪律条 6 多版本 binary diff）

### [2026-04-26] 监控关键词覆盖率 > 采样粒度
- **来源项目**: futu-opend-rs (dbfb 24h longrun)
- **来源**: 203 次采样遗漏 push_stream_healthy
- **建议目标**: test-execution-workflow.md (长跑测试段)
- **风险等级**: medium
- **内容**: 如果关键词漏了 F3/F4/stale/circuit_tripped/resubscribe，17h 的 30s 采样产出近零事件。关键词列表必须在启动监控前对照所有已知自愈机制审核
- **证据**: dbfb 采集 203 样本但未分析 push_stream_healthy=False 字段，17h push 冻结完全漏掉
- **状态**: promoted 2026-06-11（test-execution F/T/R 段：监控关键词覆盖率 > 采样粒度）

### [2026-04-26] Calibration shift 必须显式声明
- **来源项目**: futu-opend-rs (01b4 round 4)
- **来源**: 计数方法论变更未声明
- **建议目标**: templates.md (报告质量标准)
- **风险等级**: medium
- **内容**: 修改计数方法论时（如从"pass 17"改为"confirmed 11 + direct 4"），必须声明"原按 X 定义计 Y，修正后按 Z 定义计 W"。方法论变更本身是信息，不标注 = 读者困惑
- **证据**: 01b4 round 4 改了定义没声明，peer review 抓到
- **状态**: promoted 2026-06-11（templates summary 规则：Calibration shift 显式声明）

### [2026-04-28] Origin attribution 3-layer template
- **来源项目**: futu-opend-rs (v1.4.102, adversarial retrospective)
- **来源**: retrospective / cross-verify resolution
- **建议目标**: procedures/bug-report.md + test-execution-workflow.md
- **风险等级**: medium
- **内容**: 当 finding 的来源归因不清（daemon / tester script / 历史残留）时，必须走 3 层归因链：时间戳 vs ship date、跨版本 binary literal、历史 session 对账。任一层不吻合 → 只能写 undetermined，不能 commit 高 severity
- **证据**: BUG-ADV-NEW-001 从 P0 自降到 P2，靠的就是 3 层归因链，而不是 narrative 降温
- **状态**: promoted 2026-06-11（test-execution bug 流程 7.5 + templates Bug Report 写作规则）

### [2026-04-28] Role boundary redesign: adversarial 审 coord tentative verdict
- **来源项目**: futu-opend-rs (v1.4.102, 4-tester retrospective)
- **来源**: retrospective
- **建议目标**: methodologies/design-rationale.md + merge-workflow.md
- **风险等级**: high
- **内容**: 考虑把 adversarial 从纯 Tier-1 finding 角色升级为 "tester findings + coord tentative verdict 的双向审"，形成 Tier 1A tester / Tier 1B adversarial / Tier 2 coord / Tier 3 L2 / Tier 4 external 的新分层
- **证据**: v1.4.102 中一部分 coord framing bug，其实 adversarial 就能先挑战出来，能减轻 L2 的系统性审查负担
- **状态**: pilot 2026-06-11（high 风险不直接写入；下次多 tester merge 试运行 adversarial 审 coord verdict 一轮，凭实测再定）

### [2026-04-28] Cross-role daemon borrowing fallback
- **来源项目**: futu-opend-rs (v1.4.102)
- **来源**: 4-tester retrospective
- **建议目标**: strategy-workflow.md (多 agent 协调段)
- **风险等级**: medium
- **内容**: 当 tester A 的 daemon 不可用、tester B 有同版本 fresh login 时，允许在只读/低副作用前提下借用对方 daemon 作为 fallback；必须写清不改 state、不写对方 HOME、做完通报 request 清单
- **证据**: 多次高成本 blocker 实际不是"彻底做不到"，而是没把 session 内所有可借用 daemon 先枚举清楚
- **状态**: promoted 2026-06-11（strategy 多 Agent 协调段：cross-role daemon borrowing）

---

## 2026-06-11 批次（futu-opend-rs 测试策略重组 v2 提案产出，人审通过后直接写入）

> 审批记录：triage 清单见项目库 `test/reference/skill-upgrade-queue-triage-20260611.md`，
> 用户批复"按建议执行"。high 风险项 N9 经 L2 对抗审计（verdict: REJECT protocol-base 落点，
> 改写后落 strategy-workflow Pre-check 6.5"证据分层调度"）。

| ID | 条目 | 落点 | 状态 |
|----|------|------|------|
| N1 | 14 质量维度评估 | init-workflow 3.1 维度评估段 | promoted 2026-06-11 |
| N2 | 体系六部件框架 | design-rationale 第八章 | promoted 2026-06-11（low 直写） |
| N3 | pairwise 组合取样 + 等价类显式化 | strategy 阶段 2（穷举标准旁） | promoted 2026-06-11 |
| N4 | oracle catalog 模板 | templates.md 新文件模板段 | promoted 2026-06-11 |
| N5 | Gate Execution Ledger + results.json gate_items | test-execution summary 模板 + strategy"Release Gate 映射"段 + templates results.json schema | promoted 2026-06-11 |
| N6 | Escape analysis 五字段制度 | feedback-workflow 新段 | promoted 2026-06-11 |
| N7 | 按包类型分级 DoD | strategy"Release Gate 映射"段 | promoted 2026-06-11 |
| N8 | UX/DX findings 固定节 | test-execution summary 模板（沿用 feedback UX-NNN 格式） | promoted 2026-06-11 |
| N9 | 证据分层调度（原"最便宜层拦截"） | strategy Pre-check 6.5（L2 审计否决 protocol-base 落点并改写措辞） | promoted-modified 2026-06-11 |
| — | 探索性 charter 执行钩子 | strategy 阶段 5（规则原已在 SKILL.md Tier 2 表，补执行点） | promoted 2026-06-11 |
| — | L2 审计前移（plan 确认时预约） | strategy L2 对抗审查段 | promoted 2026-06-11 |
| N10 | Gate 强制校验双关口（执行完成 1.5 步 + merge Step 4.0） | test-execution-workflow + merge-workflow | promoted 2026-06-11（**滚动当场审首例**：会话内展示→用户批准"先执行 promote 原子三步"→原子写入。机读 gate 清单+校验器的项目必跑；确定性代码跨 agent 一致，解"不同 agent 漏不同关键测试点"） |

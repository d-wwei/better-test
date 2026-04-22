# Progress Workflow — 断点续传

管理 `run-<tester-id>-NNN-<ts>/progress.md` 文件，让多轮长测试任务在跨 session 时不丢上下文。每个 tester 的 progress 在自己的 run 目录内，互不干扰。

## 适用场景

测试任务往往拉得很长：

- 跨 session 跑全量回归（46 项 ×多版本）
- 跑到一半 daemon 崩了，需要从某组某项续测
- 录入 feedback 录到一半被打断
- 重写某个测试组的过程中

如果不 checkpoint，下个 session 的 agent 只能从头摸：哪些跑了？哪些挂了？feedback 录到哪条？

## Checkpoint（保存断点）

触发：用户执行 `/better-test checkpoint` 或 session 即将结束时主动建议。

### 写入内容

```markdown
# progress.md — 测试任务进度
# Tester: <tester-id>
# 最后更新: <YYYY-MM-DDTHH:MM:SS±HH:MM>

## 当前任务
[一句话：在做什么测试任务，为什么]

## 测试上下文
- 当前版本: v<version>
- 测试模式: <smoke / full / targeted:X Y / bug-retest>
- 启动方式: <bring-your-own / managed / 其他>
- 关键环境变量: <如 FUTU_DIR / DAEMON_LOG_PATH，但不要写凭证！>

## 已完成
- [x] [组 + 项 ID + 简要结果，如 "A 组全部 pass (9/9)"]
- [x] [...]

## 进行中
- [ ] [当前组 / 当前测试 ID]
  - 已跑: [pass/fail 计数]
  - 卡在: [如果挂了，描述错误]
  - 下一步: [继续下一项 / 调研失败 / 补 feedback]

## 待跑
- [ ] [组 + 大致项数]
- [ ] [...]

## 待录 feedback
- [ ] [test_id + 开发者答复 + verdict]

## 关键发现
- [本次跑出来的新 fail / flaky / 覆盖缺口，准备 update 时补充]

## 恢复上下文
[给下一个 session 的交接信息：]
- 当前 daemon 状态: [running PID xxxx / not running / managed by skill]
- 测试输出目录: [/tmp/futu-test-xxx/ 或对应项目的位置]
- 上次 results.json 路径: [.better-work/test/history/<ver>/run-<tester-id>-NNN-*/results.json]
- 需要参考的 known-issues 条目: [test_ids]
- 用户尚未回复的问题: [如有]
```

### 安全约束

**严禁**写入：
- 任何凭证（账号、密码、token、API key）
- results.json 的完整内容（可能含敏感数据，只写路径）
- daemon 日志的完整内容（同上）

如果某条进度依赖凭证才能续传 → 在 progress.md 中标 "[需用户提供凭证]" 而非真值。

### 质量标准

每条记录必须满足"下一个 agent 不用问用户就能续上"：

| ✓ 可接受 | ✗ 不可接受 |
|---------|-----------|
| "B 组前 4 项 pass，B-05 fail (no match for 'power')，待录 feedback" | "B 组跑了一半" |
| "卡在 D-03：WebSocket 订阅 5s 后无 push，daemon log 显示 CMD3020 未触发" | "WS 那个挂了" |
| "下一步：等用户提供 FUTU_TEST_API_KEY 后跑 F 组" | "等用户给点东西" |

### 多任务情况

同时有多个测试任务（如同时跑 v1.4.27 smoke 和 v1.4.26 bug-retest），用 `## 任务 1` / `## 任务 2` 分隔。

---

## Resume（从断点恢复）

触发：用户执行 `/better-test resume` 或新 session 用户说"继续上次的测试"。

### 执行步骤

1. **列出所有 tester**：扫描 `.better-work/test/testers/` 目录，读每个 tester 的 `registry.md`

2. **展示 tester 列表**（从 registry.md 找到最新 run，读 run 内 progress.md）：

```
可用 tester:

  1. claude-a3f2 | claude-code / opus-4-6 | last active: 04-21 14:23:07+08
     latest run: run-claude-a3f2-002-... (v1.4.28, in-progress)
     progress: B 组进行中 (9/14 done), 待录 feedback 2 条

  2. codex-c9d4 | codex / gpt-5.4 | last active: 04-21 14:25:30-07
     latest run: run-codex-c9d4-001-... (v1.4.28, completed)
     progress: 全部完成 (8/8 pass)

选择要恢复的 tester（输入编号）:
```

**快捷路径**：如果只有 1 个 tester 且 last_active < 24h → 自动恢复，跳过选择，告知用户。

3. 用户选择后，从 registry.md 的 Runs 表定位最新 run 目录

4. 读 run 目录内的 `progress.md`，向用户汇报：

```
恢复 tester: claude-a3f2
Run: run-claude-a3f2-002-...
上次进度:
- 任务: <任务描述>
- 版本: v<version>，模式: <mode>
- 已完成 N 项，进行中 M 项，待跑 K 项，待录 feedback L 项
- 上次停在: <恢复上下文中的位置>
- 距上次更新: <时间差>
```

4.5 读 run 目录内的 `strategy-plan.md`（如存在）：

```
IF 文件存在：
  读取 YAML frontmatter 的 status 字段，在汇报中追加"策略状态"行：

  status: draft       → "策略已生成但未确认。需先确认计划再继续执行。"
  status: confirmed   → "策略已确认但未开始执行。可直接开始执行，无需重跑 strategy。"
  status: in-progress → "策略正在执行中。结合 progress.md 确定断点，从当前阶段续跑。"
  status: completed   → "策略已完成。无需续跑此计划。"
  status: superseded  → "此计划已被新计划替代。检查是否有新的 strategy-plan.md。"

IF 文件不存在：
  → "无策略记录。需重新运行 /better-test strategy。"

汇报格式追加：
  恢复 tester: <tester-id>
  Run: <run directory>
  上次进度:
  - ...（原有字段）
  - 策略状态: <status 对应的描述>
  - 当前阶段: Stage <N> of <total>（仅 in-progress 时显示）
```

**Resume 决策逻辑**：
- `confirmed` → 跳过 strategy，直接进入 test-execution-workflow（最大收益场景）
- `in-progress` → 结合 progress.md 的"已完成/进行中/待跑"确定精确断点
- `draft` → 展示 strategy-plan.md 内容，让用户确认（相当于从 Step 6 恢复）
- `completed` / `superseded` / 不存在 → 正常 resume 流程，可能需要重跑 strategy

5. 如果距上次更新超过 7 天 → 提醒：
   "进度记录已过 7 天。可能的变化：版本可能升级、daemon 状态可能不同、known-issues 可能新增。建议先跑 `/better-test update` 检查测试知识，再决定从哪续。"

6. 检查环境状态：
   - 如果上次是 managed 模式 → 检查 daemon 是否还在跑
   - 如果上次依赖某临时文件 → 检查是否还存在
   - 如果当前设备与 bio 记录的设备不同 → 报告差异
   - 读 `testers/*/registry.md` 的 Resources 段，检查资源冲突（端口被其他 tester 占用）
   - 如果有变化 → 报告差异

7. 询问用户："从 [进行中的项] 续测，还是从头跑某段？"

8. 用户确认后：
   - 更新 `testers/<tester-id>/registry.md` 的 last_active
   - 如果需要新 run → 创建新 run 目录 + bio.md，更新 registry.md Runs 表
   - 如果续跑同一 run → 继续写入同一 run 目录
   - 按上次的"测试上下文"恢复环境，继续执行

### 冲突处理

如果 progress.md 提到的 daemon 已崩 / 端口被占 / 凭证过期：
- 读 `testers/*/registry.md` Resources 段确认端口占用情况
- 报告具体差异
- 不自动重启 daemon —— 让用户决定

---

## 自动 checkpoint 建议

Agent 检测到以下情况时，主动建议 checkpoint：

1. 已经连续跑测试超过 30 分钟且有实质进展（多组完成）
2. 对话长度接近 context 压缩阈值
3. 跑完了一个测试组准备开始下一组（天然的检查点）
4. 即将跑高风险操作（如 G 组的 daemon 启停参数验证、或可能扣费的下单测试）
5. 即将提交 feedback 但开发者还在评估

建议话术：
> "建议保存断点 —— 现在跑完了 A/B 两组（14/14 pass），即将开始 C 组（POST 交易，有真实下单风险）。如果出问题可以回滚到这里。要我执行 checkpoint 吗？"

---

## 与其他 workflow 的衔接

```
init       → 创建 testers/ 目录（不创建具体 tester，等 strategy 或 checkpoint 时自动注册）
strategy   → 如无活跃 tester 则自动注册（创建 registry.md + run 目录 + bio.md）；生成 strategy-plan.md 到 run 目录
跑测试中   → 30 分钟提醒 / 跑完每组后提醒；所有写操作在 run 目录内
feedback   → 录入完一条后写入 run 目录内 feedback/；追加到 progress.md 的"已录 feedback"段
update     → update 完后清空当前 run progress.md 的"待录 feedback"段（已处理）
resume     → 扫描 testers/*/registry.md → 用户选择 → 读 run 目录内 progress + strategy-plan → 报告 → 续跑
checkpoint → 写入 run 目录内 progress.md + 更新 registry.md last_active
merge      → 所有 tester 完成后，coordinator 读各 run 目录合并结果
```

## 不要做的事

- ❌ 不要把凭证写入 progress.md 或 bio.md
- ❌ 不要把 results.json 全文复制进 progress.md（只存路径）
- ❌ 不要写"差不多/快完成了"这种模糊状态
- ❌ 不要在没有 checkpoint 的情况下假装能 resume —— 没有就承认"无进度记录"
- ❌ 不要跨 tester 写 progress —— 每个 tester 只写自己 run 目录内的 `progress.md`
- ❌ 不要在测试期间写项目级聚合文件（status.md、known-issues.md 等）—— 那是 coordinator 的职责

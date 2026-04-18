# Progress Workflow — 断点续传

管理 `.better-work/test/progress.md` 文件，让多轮长测试任务在跨 session 时不丢上下文。

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
# 最后更新: <ISO 时间戳>

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
- 上次 results.json 路径: [.better-work/test/history/<ver>/run-NNN-*/results.json]
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

1. 读 `.better-work/test/progress.md`
2. 向用户汇报：

```
上次进度:
- 任务: <任务描述>
- 版本: v<version>，模式: <mode>
- 已完成 N 项，进行中 M 项，待跑 K 项，待录 feedback L 项
- 上次停在: <恢复上下文中的位置>
- 距上次更新: <时间差>
```

3. 如果距上次更新超过 7 天 → 提醒：
   "进度记录已过 7 天。可能的变化：版本可能升级、daemon 状态可能不同、known-issues 可能新增。建议先跑 `/better-test update` 检查测试知识，再决定从哪续。"

4. 检查环境状态：
   - 如果上次是 managed 模式 → 检查 daemon 是否还在跑
   - 如果上次依赖某临时文件 → 检查是否还存在
   - 如果有变化 → 报告差异

5. 询问用户："从 [进行中的项] 续测，还是从头跑某段？"

6. 用户确认后，按上次的"测试上下文"恢复环境，继续执行

### 冲突处理

如果 progress.md 记录的 results.json 路径已被修改（比如新跑了一次）：
- 读最新 results.json
- 对比上次 progress 中"已完成"列表
- 用最新数据修正进度（已完成可能更多了）
- 报告："上次 checkpoint 后又跑了 N 项，进度已自动合并"

如果 progress.md 提到的 daemon 已崩 / 端口被占 / 凭证过期：
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
init       → 创建空 progress.md 模板
strategy   → 执行前提示用户："要不要先 checkpoint？"
跑测试中   → 30 分钟提醒 / 跑完每组后提醒
feedback   → 录入完一条后自动追加到 progress.md 的"已录 feedback"段
update     → update 完后清空 progress.md 的"待录 feedback"段（已处理）
resume     → 读 progress.md → 报告 → 询问 → 续跑
```

## 不要做的事

- ❌ 不要把凭证写入 progress.md
- ❌ 不要把 results.json 全文复制进 progress.md（只存路径）
- ❌ 不要写"差不多/快完成了"这种模糊状态
- ❌ 不要在没有 checkpoint 的情况下假装能 resume —— 没有就承认"无进度记录"

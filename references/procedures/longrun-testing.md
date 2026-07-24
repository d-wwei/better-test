# Long-Run Testing Procedure (24h+)

> **触发条件**：strategy 推荐包含 24h+ 稳定性/耐久性测试，或用户要求长时间压力测试。
> **加载时机**：Tier 2 扩展流程，由 strategy-workflow 在 plan 中包含长跑项时自动加载。

---

## 核心原则

长跑测试的目标不是"跑久一点看会不会崩"，而是**有监控地持续观测系统行为变化**。没有监控的长跑 = 浪费时间。

## 1. Session 隔离

长跑必须作独立 session fork，不占主测试 session：
- 独立 tester-id、独立 daemon（不同端口/不同账号）
- 独立 run 目录、独立采样器
- 主 session port-clean 做覆盖测试，两 session 互不干扰
- P1 non-deterministic bug 往往只有长跑能发现

## 2. 三层健康验证

**进程存活 ≠ 功能健康。** daemon PID 存在 17h + 内部状态 qot_logined=True 但 push stream 完全断裂的真实案例。

```
Layer 1: 进程存活
  → pgrep / kill -0 $PID / lsof port
  → 必须精确匹配：port + account + 启动时间（PID 单独不够，会 reuse）

Layer 2: 内部状态正常
  → 查询 daemon 健康接口（如 /api/push-subscriber-info、/api/admin/status）
  → 验证关键状态字段（如 qot_logined=True、push_stream_healthy=True）

Layer 3: 主业务输出在流动
  → 关键计数器单调递增（如 total_pushes_received 在交易时段应持续增长）
  → 计数器冻结 = push stream 可能断裂，即使 Layer 1+2 正常

缺第三层 = 空壳验证。
```

## 3. Daemon 身份 6 元组

多 daemon 环境下标识同一个 daemon 必须匹配 6 项：

```
1. binary path（版本号）
2. port 集（TCP + REST + WS + gRPC）
3. account（login-account）
4. 启动时间（log 首行 timestamp）
5. keys-file 路径（如有 --rest-keys-file）
6. log 路径

PID 单独不足（reuse）。binary name 单独不足（多版本）。
port + account 组合才能唯一标识。
```

## 4. 采样器设计

### 4.1 自包含原则

```
采样脚本必须 nohup + disown，完全独立于 Claude session：
  nohup /tmp/futu-sampler-<tester-id>.sh > /tmp/futu-sampler-<tester-id>.log 2>&1 &
  disown

脚本结束时自己写 SAMPLER_DONE 标记。
Agent 只是"读取者"——session 崩了不影响采样。
```

### 4.2 关键词覆盖率 > 采样粒度

```
关键词覆盖率决定能发现什么，采样粒度只决定发现多快。
如果关键词漏了某个 self-heal 字段（如 resubscribe_triggers），
17 小时的 30 秒采样也产出零事件。

Bootstrap 前必须：
  curl <health-endpoint> | jq keys  → 列出全部可用字段
  对照项目已知的 self-heal 机制（F3/F4/F6 等），确认每个机制都有对应关键词
  默认采全部字段——多采 cost 极低，漏采毁分析
```

### 4.3 采样粒度权衡

| 粒度 | 优点 | 缺点 | 适用场景 |
|------|------|------|---------|
| 1 min | 瞬态捕获力强 | 噪声高，数据量大 | 已知高频事件调查 |
| **5 min** | **甜点：信噪比最佳** | 30s 内瞬态可能漏 | **默认推荐** |
| 15 min | 低噪声，长期趋势清晰 | 弱瞬态检测 | 48h+ 超长跑 |

## 5. 监控架构：双通道互补

单靠 Monitor（事件驱动）→ 稳态无信号时完全静默。
单靠 Cron/Loop（定期轮询）→ 漏瞬态事件。
推荐双通道：

```
Channel 1: Monitor（事件驱动 wake-up）
  tail -F <daemon.log> | grep --line-buffered "ALERT\|ERROR\|panic\|heartbeat" | while read line; do
    echo "[$(date -u +%FT%TZ)] $line" >> /tmp/monitor-<tester-id>.log
  done &
  
  关键：--line-buffered 必须加，否则 pipe 缓冲延迟 5+ 分钟

Channel 2: Cron/Loop（定期兜底）
  每 5min 采样 health endpoint + 计算 delta
  连续 N tick 数据无变化 → 标注"数据冻结，可能采样结束或 push 断裂"
```

## 6. Canary/Heartbeat 设计

Crash 时 canary 本身可能先挂。只 grep "ALERT" → 什么都收不到 → 误判为"一切正常"。

```
Canary 必须：
1. 定期发 heartbeat（如整点 + 半点写一行 "HEARTBEAT <timestamp>"）
2. Monitor grep "ALERT|heartbeat"
3. 无 heartbeat → 先诊断 canary 自己是否挂了（不是"没事发生"）

Canary 告警升级：
  v1: absolute 阈值 → 噪声压死信号
  v2: delta-based + .last_state 文件对比 → 信噪比好
```

## 7. Loop Auto-Stop

```
连续 N tick（如 3 次，即 15min@5min interval）数据完全无变化 →
  主动标注"数据冻结"
  如果是预期的（闭市时段）→ 记录 + 继续
  如果是非预期的 → 标注异常 + 可考虑 CronDelete 自动停止
```

## 8. 跨 Tester 隔离

```
Canary 命名：/tmp/canary-<tester-id>-<daemon-port>.log（不是 /tmp/canary-24h.log）
Log 命名：/tmp/futu-<tester-id>-<port>.log（不是 /tmp/futu-daemon.log）
PID 文件：/tmp/daemon-<tester-id>.pid

跨 tester 的 PID reuse + 共享 /tmp 导致 log 归属错误的真实案例：
  → e4da canary 检测 PID 3921 消失 → 归档 log → 实际是另一个 tester 的 daemon
  → 验证必须四项匹配：port + account + 启动时间 + log 最后行时间
```

## 9. 时间戳纪律

```
多数据源交叉对账时：
  ls -la 用 local time（如 HKT）
  daemon log 用 UTC
  → 差 8 小时

规则：所有时间戳转 UTC 作 SoT。
  macOS: stat -f "%Sm" -t "%Y-%m-%dT%H:%M:%SZ" <file>
  Epoch 计算：必须用工具（date -r / Python datetime），不手算
  手算错 8h 的真实案例：29cd v9 算错导致结论反转
```

## 10. /tmp 污染控制

```
多 tester 长跑后 /tmp 可能有 44+ 个 futu-*.log 文件。

清理规则：
  自己的 log → tester-id 前缀 + session 结束后归档到 run 目录
  查找时 → find /tmp -name "futu-*" -newer <session-start-stamp> -user $(whoami)
  不用 grep /tmp 全部文件——先限定时间范围和归属
```

## 不要做的事

- 不要跑无监控的长跑——等于浪费时间
- 不要用 PID 单独判断进程身份——PID 会 reuse
- 不要用 absolute 阈值做告警——delta-based 信噪比好 10 倍
- 不要等长跑结束才分析数据——每 6h checkpoint 中间分析
- 不要让 canary/sampler 依赖 Claude session——nohup+disown 独立运行
- 不要 grep 时省略 `--line-buffered`——pipe 缓冲延迟 5+ 分钟

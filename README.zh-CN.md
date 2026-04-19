<!-- Synced with README.md as of 2026-04-18 -->

**[🇺🇸 English](README.md)** | **🇨🇳 中文**

# better-test

### 第 4 号失败模式："没跑对测试"。这个 repo 专治这个。

AI coding agent 在 10 万行代码里翻车的五种方式里，这一种最少有人修：

> 没跑对测试 — 跑了单元测试，没跑集成测试。

这不是态度问题。Agent 不知道哪些测试覆盖哪些改动。它不知道哪些测试本身就已知挂了。它不知道你在意的那个测试需要真实账号才能跑。

这些知识藏在 Slack 的线程里、在发版工程师的脑子里、在没人回看的 postmortem 里。每次会话结束就蒸发。

`better-test` 把它捕获下来——[Full Context + Lite Control](https://github.com/d-wwei/better-work) 框架里测试那一半。一份持续维护的测试档案 + 一套开发者反馈回路，让同一个已关闭的 bug 不会被重复提报三次。

## 这个 repo 知道的，你的 agent 不知道

你的团队有 CI 不捕捉的知识：

- "那组 WebSocket 测试只有 `subscribe.rs` 动了才需要跑。"
- "auth 组里那个 flaky——开发说是测试本身的问题，忽略吧。"
- "上次发版 keychain 回归漏了，因为没人跑 H 组。这次别漏。"

三个文件承载这些：

| 文件 | 装什么 |
|------|--------|
| `test-groups.md` | 测试怎么分组、每组覆盖什么、每组跑起来需要什么 |
| `impact-map.md` | 变更文件/关键词 → 受影响的测试组 |
| `known-issues.md` | 哪些已知挂、为什么挂、开发的裁定 |

代码改完之后跑 `/better-test strategy`，skill 读这三个文件 + 你的 `git diff`，给你一个最小测试集 + 挑选理由。你能看清楚为什么选了 A、B、D 三组，哪些已 triage 的项被自动排除了。

## 反馈回路

大多数测试 skill 停在"跑这些测试"。`better-test` 还会问：开发对上次的失败回复了什么？

Bug 报告被开发回复了——"这是预期行为"、"修了但不是你预期的方式"、"不修"——你把这个裁定喂回去：

```
/better-test feedback D-04 not-a-bug --note "开发确认——cancel 返回 404 是预期行为"
```

skill 把裁定写进 `history/`，自动提炼成 suppress 规则写入 `feedback-rules.json`，下次 `/better-test strategy` 自动排除 D-04。同一个 bug 不会提报三遍。

六种 verdict：

| Verdict | 含义 | 效果 |
|---------|------|------|
| `not-a-bug` | 开发确认是预期行为 | 从活跃失败排除 |
| `fixed` | 本版本已修 | 再跑一次确认后归档 |
| `fixed-differently` | 修了但不是你预期的方式 | 用新预期输出重测 |
| `wontfix` | 确认但不修 | 永久排除，带备注 |
| `deferred` | 已知问题，推迟 | 到目标版本前排除 |
| `revoke` | 撤销之前的裁定 | 重新激活该测试 ID |

## 安装

### Claude Code（原生）

```bash
git clone https://github.com/d-wwei/better-test.git ~/repos/better-test
ln -s ~/repos/better-test ~/.claude/skills/better-test
```

### 其他平台

Cursor / Gemini CLI / Codex / OpenCode / OpenClaw 的 adapter 在 `references/adapters.md`。`/better-test init` 产出的测试知识文件跨平台通用。

## 快速开始

进到项目目录（之前跑过 `/better-code init`，`.better-work/shared/` 已存在会更顺）：

```
/better-test init
```

skill 先判断测试场景（library / daemon / API / CLI / 多服务），探索现有测试结构，然后生成：

- `.better-work/test/protocol.md` — 测试认知约束
- `.better-work/test/test-groups.md` — 测试组定义 + 运行条件
- `.better-work/test/impact-map.md` — 变更文件模式 → 测试组
- `.better-work/test/known-issues.md` — 已知问题 + 裁定

典型循环：

```
# 改完代码：
/better-test strategy
  → 读 impact-map.md + known-issues.md + 当前 git diff
  → 推荐："跑 A、B、D 三组，共 22 个测试，约 5 分钟"
  → 理由："src/subscribe.rs 改了，命中订阅流程（D 组）..."

# 某项挂了，开发回复了：
/better-test feedback D-04 not-a-bug --note "开发确认是预期行为"
  → 把裁定写进 history/
  → 自动提炼 suppress 规则
  → 下次 strategy 自动排除 D-04
```

## strategy 输出示例

改了 `src/rest/funds.rs` 和 `src/auth/session.rs`：

```
推荐：A（登录链路）、B（REST 只读）、C（REST POST）三组
  — 22 个测试，约 8 分钟，bring-your-own 模式

理由：
  • src/auth/session.rs 命中 impact-map 关键词 "auth" → A 组（9 项）
  • src/rest/funds.rs 命中 "REST" → B、C 组（5 + 8 项）

跳过：D、E、F、H、I（无变更信号）
排除：C-03（wontfix，推迟到 v1.5）、B-07（2026-03-12 标为 not-a-bug）

跑法：cargo test -- --test-groups A,B,C
```

每个推荐指向它的 impact-map 条目，每个排除指向它的 feedback 裁定。推荐理由是可审计的，开始跑之前你可以覆盖任何一条。

## 命令参考

| 命令 | 做什么 |
|------|--------|
| `/better-test init` | 首次探索测试结构 + 生成知识文件 |
| `/better-test update` | 信号驱动的增量更新 |
| `/better-test strategy` | 分析 git diff + impact-map，推荐最小测试集并给理由 |
| `/better-test feedback <id> <verdict>` | 录入开发裁定，自动提炼 suppress 规则 |
| `/better-test checkpoint` | 保存当前测试任务状态 |
| `/better-test resume` | 读进度并继续 |

六个命令直接调用或通过 `/better-work test <cmd>`（装了 better-work 时）行为完全一致。

## 输出结构

测试知识放在 `.better-work/test/` 下（是到 `~/.better-work/<project>/test/` 的符号链接）：

```
<project>/.better-work/                      → ~/.better-work/<project-name>/
├── shared/                                  （读；需要写时打 [better-test] 标签）
│   └── index.md                             项目知识入口
├── code/                                    （只读；用来判断测试优先级）
│   └── danger-zones.md                      高风险文件 → 更全面的测试
└── test/                                    （better-test 专属）
    ├── protocol.md                          ≤15 行——测试认知约束
    ├── test-groups.md                       组定义 + 运行条件
    ├── impact-map.md                        变更关键词 → 受影响的组
    ├── known-issues.md                      已知问题 / 预期行为 / 裁定
    ├── status.md                            自动刷新的汇总
    ├── progress.md                          已 gitignore——当前测试任务状态
    └── history/                             测试运行历史，纳入 git
        ├── feedback-rules.json              自动维护，勿手编
        └── <version>/
            └── run-NNN-<ts>/                每次运行的 results.json + summary.md
```

### 一条反常识规则

**pass 必须验证返回值里的字段，不能只看 exit code。** daemon 返空列表 exit 也是 0——"exit 0 = pass"等于给坏 API 放行。`protocol.md` 把这条写成红线。它是建议性的（better-test 不替你跑测试），但会在 review 阶段把坏测试挑出来。

## Better-Work 系列

- **[better-work](https://github.com/d-wwei/better-work)** — Lite Control + 系列入口。完整设计故事看那里。
- **[better-code](https://github.com/d-wwei/better-code)** — 研发 Full Context
- **better-test**（本 repo） — 测试 Full Context

`better-test` 会读其他子技能填过的 `shared/index.md`（项目身份）和 `code/danger-zones.md`（高风险文件 → 更全面测试）。它只写 `test/` 目录，必要时写 `shared/` 并打 `[better-test]` commit 标签。

## 已知限制

- **不内置测试运行器。** `better-test` 推荐要跑哪些测试 + 给理由，真正跑是你项目自己的工具（`cargo test` / `pytest` / `go test` / 自定义 harness）。跑完通过 `/better-test feedback` 或把 `results.json` 存到 `history/` 反馈回来。
- **`impact-map.md` 准确度靠反馈。** 初始条目靠关键词种子，准确度是 `/better-test feedback` 和 `/better-test update` 逐步逼近的。
- **`feedback-rules.json` 自动生成。** 不要手编。用 `/better-test feedback <id> revoke` 撤销，用新 verdict 重新录入。
- **`strategy` 不跑测试。** 给你测试集 + 调用命令，你自己跑。
- **目前没有 CI 集成。** GitHub Actions / GitLab CI 的集成在规划中。
- **`protocol.md` 的红线是建议性的。** 阻止不了你写坏测试，只能在 review 时暴露。

## License

MIT。

---

完整故事：系列入口 README 里的 [Full Context, Lite Control](https://github.com/d-wwei/better-work) 长文。

问题、反馈或讨论：[GitHub issues](https://github.com/d-wwei/better-test/issues)。

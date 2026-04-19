<!-- Synced with README.md as of 2026-04-18 -->

**[🇺🇸 English](README.md)** | **🇨🇳 中文**

# better-test

### 变更之后只跑该跑的测试——并且记住那些你已经 triage 过的项

`better-test` 是一个 Claude Code skill，给项目构建一份持续维护的测试知识库：测试是怎么分组的、哪些已知会挂以及为什么、什么文件变动该触发哪一组测试。AI agent 在推荐测试策略之前先读这份知识——你拿到的不是"全量跑"或"跑个 smoke"，而是一小组带理由的测试集 + "为什么只跑这些"的说明。

同时它能捕获开发者对 bug 的反馈（6 种 verdict），自动提炼为 suppress 规则。engineering 已经关了的问题，你不会再三次重复提报。

原生支持 Claude Code，自带 Cursor / Gemini CLI / Codex / OpenCode / OpenClaw 适配器。[Better-Work 系列](https://github.com/d-wwei/better-work-skill) 的一部分，但可以独立安装独立使用。

## 为什么需要它

跑全量测试矩阵那是 CI 的事。本地迭代要的不一样——一个小的、变更感知的测试集，而且要让团队累积的知识真的派上用场。

你的团队有 CI 不知道的知识。"那组 WebSocket 测试只有 subscribe.rs 动了才需要跑。""auth 组里那个 flaky——开发说是测试本身的问题，忽略吧。""上次发版的 keychain 回归是没人跑 H 组漏的——这次别漏。"

这些知识每次会话结束就蒸发。它们藏在 Slack 的线程里，靠某位发版工程师的半记忆维系。新人第一次跑测试，只能靠试错重新学一遍。

`better-test` 把它们捕获下来。三个文件做这件事：

- **`test-groups.md`** —— 测试怎么分组，每组覆盖什么，跑起来需要什么条件
- **`impact-map.md`** —— 变更文件/关键词 → 受影响的测试组
- **`known-issues.md`** —— 哪些已知挂、为什么挂、开发的裁定是什么

外加一套反馈回路：当开发者对 bug 报告回复"not-a-bug"或"wontfix"或"fixed-differently" 时，`/better-test feedback` 把这条裁定转成 suppress 规则。下次 strategy 推荐时，已 triage 的项自动排除。同一个 bug 不会被重复提报三遍。

## 安装

### Claude Code（原生）

```bash
git clone https://github.com/d-wwei/better-test.git ~/repos/better-test
ln -s ~/repos/better-test ~/.claude/skills/better-test
```

下次开 Claude Code 会话，`better-test` 就出现在 skill 列表里。

### 其他平台

`references/adapters.md` 里有可粘贴的安装命令，覆盖 Cursor / Gemini CLI / Codex / OpenCode / OpenClaw。`/better-test init` 产出的测试知识文件本身跨平台通用。

## 快速开始

进到项目目录（如果之前跑过 `/better-code init`，`.better-work/shared/` 已存在，会更顺）：

```
/better-test init
```

skill 先判断测试场景类型（library / daemon / API / CLI / 多服务），探索现有测试结构，然后生成：

- `.better-work/test/protocol.md` —— 测试认知约束，≤15 行
- `.better-work/test/test-groups.md` —— 测试组定义 + 运行条件
- `.better-work/test/impact-map.md` —— 变更文件模式 → 测试组
- `.better-work/test/known-issues.md` —— 已知问题 + 裁定

初始化完毕后，典型循环长这样：

```
# 改完代码之后：
/better-test strategy
  → 读 impact-map.md + known-issues.md + 当前 git diff
  → 推荐："跑 A、B、D 三组，共 23 个测试，约 5 分钟"
  → 给理由："src/subscribe.rs 改动了，命中订阅流程（D 组）..."

# 跑完之后如果有失败：
/better-test feedback D-04 not-a-bug --note "开发确认——这里 cancel 返回 404 是预期行为"
  → 把裁定写进 history/
  → 自动提炼成 suppress 规则写入 feedback-rules.json
  → 下次 /better-test strategy 自动排除 D-04
```

## 命令参考

| 命令 | 做什么 |
|------|--------|
| `/better-test init` | 首次探索测试结构 + 生成知识文件 |
| `/better-test update` | 信号驱动的增量更新（新测试 / 新 bug / 新组 / 新约定） |
| `/better-test strategy` | 分析当前 git diff + impact-map，推荐最小测试集并给理由 |
| `/better-test feedback <id> <verdict> [--note "..."]` | 录入开发者对 bug 的裁定，自动提炼为 suppress 规则 |
| `/better-test checkpoint` | 把当前测试任务状态写到 `progress.md` |
| `/better-test resume` | 读 `progress.md`，按断点恢复 |

### 六种 feedback verdict

| Verdict | 含义 | 对未来 `strategy` 的影响 |
|---------|------|-------------------------|
| `not-a-bug` | 开发确认这是预期行为 | 从活跃失败中排除 |
| `fixed` | 本版本已修复 | 再跑一次确认，然后归档 |
| `fixed-differently` | 修了但不是你预期的方式 | 用新的预期输出重测 |
| `wontfix` | 已确认，但不会修 | 永久排除（带备注） |
| `deferred` | 已知问题，推迟到后续版本 | 到目标版本前排除 |
| `revoke` | 撤销之前的裁定（情况变化） | 重新激活该测试 ID |

六个命令直接调用或通过 `/better-work test <cmd>`（装了 better-work 时）行为完全一致。

### strategy 输出示例

改了 `src/rest/funds.rs` 和 `src/auth/session.rs` 后，跑 `/better-test strategy` 会返回类似这样的结果：

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

推荐理由是可审计的：每个推荐组指向它的 impact-map 条目，每个排除项指向它的 feedback 裁定。开始跑之前你可以覆盖任何一条。

## 输出结构

测试知识放在 `.better-work/test/` 下（本身是到 `~/.better-work/<project>/test/` 的符号链接）：

```
<project>/.better-work/                      → ~/.better-work/<project-name>/
├── shared/                                  （better-test 只读；需要写时会打 [better-test] 标签）
│   └── index.md                             项目知识入口
├── code/                                    （better-test 只读；用来判断测试优先级）
│   └── danger-zones.md                      高风险文件 → 更全面的测试
└── test/                                    （better-test 专属）
    ├── protocol.md                          ≤15 行——测试认知约束
    ├── test-groups.md                       组定义 + 运行条件
    ├── impact-map.md                        变更关键词 → 受影响的组
    ├── known-issues.md                      已知问题 / 预期行为 / 裁定
    ├── status.md                            自动汇总：当前版本 / 活跃 fail / 已 suppress
    ├── progress.md                          已 gitignore——当前测试任务状态
    └── history/                             测试运行历史，纳入 git
        ├── _meta.json
        ├── feedback-rules.json              自动维护，勿手编
        └── <version>/
            ├── run-NNN-<ts>/                每次运行的 results.json + summary.md
            └── feedback/<test_id>_<verdict>.md
```

### 为什么 `status.md` 是自动生成的

每次 `strategy` / `update` / `feedback` 之后，`better-test` 会刷新 `status.md`，包含：

- 当前被测项目版本
- 活跃失败数量（排除已 triage 的）
- 已 suppress 的项 + 裁定
- 最近一次测试运行的摘要

新会话第一步读 `status.md`，agent 立刻拿到情况报告——不用翻 `history/`，也不用重跑。

### 设计取舍

| 选择 | 为什么 |
|------|--------|
| 测试历史按版本分 + 纳入 git | 让"v1.4.3 我们试过了"这类知识在工程师和发版之间留存 |
| `feedback-rules.json` 自动生成，永不手编 | 手编会破坏维持 suppress 规则一致性的自动化 |
| `test-groups.md` 强制写"运行条件" + "如何运行" | 没前置条件和调用方式的组就等于不可用，写入时强制可防静默漏洞 |
| `impact-map.md` 条目需要验证来源 | 否则 map 就是一堆猜测；verified / inferred / `[未验证]` 必须显式标注 |
| pass 必须验证返回值里的字段，不能只看 exit code | daemon 返空列表 exit 也是 0——"exit 0 = pass"等于给坏 API 放行 |

## 在 Better-Work 系列里的位置

`better-test` 是 [Better-Work 系列](https://github.com/d-wwei/better-work-skill) 的测试学科子技能。整个系列是一组 AI agent skill，共享同一套项目知识树：

- `better-work` —— 系列入口、项目初始化、通用执行协议
- `better-code` —— 研发知识和约束（[better-code](https://github.com/d-wwei/better-code)）
- `better-test` —— 本 repo，测试知识和约束
- `better-plan` / `better-design` / `better-write` —— 规划中

`better-test` 会读其他子技能填过的 `shared/index.md`（项目身份）和 `code/danger-zones.md`（高风险文件 → 更全面的测试）。它只写 `test/` 目录，必要时写 `shared/` 并打 `[better-test]` commit 标签。

装了 `better-work` 之后，`/better-work test <cmd>` 就是别名。没装的话，`/better-test` 照样独立跑。

## 接口契约

Better-Work 系列的每个子技能都暴露四条标准命令：

| 命令 | 承诺 |
|------|------|
| `init` | 幂等首次初始化，不显式 `--force` 不覆盖已有文件 |
| `update` | 增量更新，保留不相关内容 |
| `checkpoint` | 写 `shared/progress.md`，格式下次会话能解析 |
| `resume` | 读 `progress.md`，按测试 ID / 组级别汇报——不能是"差不多跑完了" |

`better-test` 多两条学科专属命令：`strategy` 和 `feedback`。通过 `/better-work test` 调用时，better-work 原样透传参数——不检查。

## 已知限制

- **不内置测试运行器。** `better-test` 推荐要跑哪些测试 + 给理由，但真正跑测试是你项目自己的工具（cargo test / pytest / go test / 自定义 harness）。跑完把 `results.json` 喂回来。
- **`impact-map.md` 的准确度取决于你。** 初始条目靠关键词匹配——真正的准确度是靠 `/better-test feedback` 和 `/better-test update` 逐步逼近的。全新的 `impact-map.md` 可能会推多了或推少了。
- **`feedback-rules.json` 是自动生成的——不要手编。** 想改某条规则就用 `/better-test feedback <id> revoke` 撤销，然后用新的 verdict 重新录入。
- **`strategy` 不跑测试。** 它给你测试集 + 调用命令。你跑完通过 `/better-test feedback` 或把 `results.json` 存到 `history/` 反馈回来。
- **目前没有 CI 集成。** GitHub Actions / GitLab CI 的集成在规划中，尚未实现。
- **`protocol.md` 的红线是建议性的。** "pass 必须验证字段"这种红线活在 skill 的知识里，agent 会遵守，但阻止不了你写坏测试——坏测试会在 review 时暴露，不在 harness 层拦住。

## License

MIT License.

---

问题、反馈或讨论：[GitHub issues](https://github.com/d-wwei/better-test/issues)。

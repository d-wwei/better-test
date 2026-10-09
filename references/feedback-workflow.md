# Feedback Workflow

`/better-test feedback <id> <verdict> [note]` — 把开发者/人类对某测试项的反馈按来源和适用范围录入；证据充分的判定才进入规则，未归因的反馈保留候选。

## 为什么需要 feedback

测试跑完发现 fail → 提报给开发者 → 开发者回复"这是预期行为"或"已修在另一个分支"。如果不录入：
- 下次 strategy 仍然把这项当 active fail，推荐 bug-retest
- 报告里仍然显眼，淹没真正的新问题
- 知识只活在某次对话里，下个 session 丢失

录入 feedback 保存答复与证据。口头判定不能替代抑制所需的事实依据，也不能改写历史结果。用户明确调用 feedback 并指定 verdict 已授予录入授权，已有授权或可信开发者反馈也不重复请求确认；材料不足时保存候选和下一步，缺的是归因材料，不是重复审批。

## 命令格式

```
/better-test feedback <test_id> <verdict> [--note "<text>"]

verdict 取值（共 6 种）:
  not-a-bug          预期行为，不是 bug
  fixed              已在某 commit 修复，等下次回归验证
  fixed-differently  有依据地修正 EXPECT_PATTERN/测试逻辑，仍需复测
  wontfix            开发者明确不修
  deferred           推迟到未来某版本修
  revoke             撤销之前对该 test_id 的任何 feedback（详见"撤销 feedback"段）
```

如果用户口头报告但没指定 verdict，agent 应**主动反问**："开发者怎么说？是 not-a-bug、fixed、wontfix 还是 deferred？" 不要自行猜测。

## 执行流程

### Step 1: 验证 test_id 存在

```
读当前 tester 的 run 目录内 results.json
查找 items[].id == <test_id>
不存在 → 扩大搜索到同版本其他 run-*-*/results.json
仍不存在 → 报错并提示用户检查 ID 拼写
存在 → 继续
```

### Step 1.5: 固定来源、范围与归因

先按 SKILL 解析 TEST_ROOT 与 tester/run 身份，所有写入服从角色矩阵：活跃 Tester 只写自己的 run；其他 run 只读，不能因扩大搜索而在别人目录录入。Coordinator 在自己的 merge 记录承接并更新 derived views；单 tester 完成后才自行重建。

每份反馈保存脱敏原来源 locator/revision/digest、采集时间、产品版本/环境/角色/entry、case/oracle/recipe revision、输入与可复现范围、缺材料和可靠性。缺精确版本标 unresolved，不能伪造 hash。历史 Bug/生产反馈缺输入/原始后效时，仅提出候选测试义务，不生成 confirmed/reproduced case；重复转述不算独立证据。

“误报”按工具、环境、文档、产品四层核对：selector 未命中、错实例或测试断言错不能凭单句话成为永久豁免。查原始观察、权威需求、环境身份与独立后效；独立后效证实违反契约时保留产品 finding。not-a-bug 需可定位的契约依据及相符观察/复现范围；wontfix 需可信来源的明确不修决定及承担范围，并保留缺陷/风险。fixed-differently 要说明原断言为何错、替代 oracle 的独立依据与保持项，不能跟随产品 Bug 放宽 expected 或自动刷新 golden。

授权明确且依据/范围充分时直接进入 Step 2，无需重复确认。未归因、自动推断待 review 或材料缺失时，将 requested verdict、来源、未知项、owner/待补材料写自己 run 的 progress.md（非活跃期写现有 update/feedback 待办），**不要放入会被 merge 自动读取的 feedback/*.md**；现有失败、规则和历史证据保持原样。补齐依据后再生成正式反馈。若对旧规则发现依据缺失，提出 revoke/范围收窄，未获相应授权不暗中重写规则。

### Step 2: 写有依据的 feedback markdown 文件

```
路径: run-<tester-id>-NNN-<ts>/feedback/<test_id>_<verdict>.md
内容:

---
test_id: <id>
verdict: <verdict>
version: <version>
date: <YYYY-MM-DDTHH:MM:SS±HH:MM>
source: developer | human | inferred
tester_id: <tester-id>
---

## 反馈内容

<note>

## 来源与适用范围

- 原始来源/时间/可靠性: <脱敏 locator + revision/digest；未知项>
- Scope: <产品版本、环境、角色、entry、case/oracle/recipe revisions>
- 依据/复现/原始后效: <真实 run/artifact/契约引用；未执行则 NOT_RUN>
- 归因: <工具/环境/文档/产品；已排除项与未知项>
- Owner / next: <下一步、完成条件与阻塞>

## 对测试的影响

- [ ] 在上述 scope 内处理预期行为（不改历史结果，不代表未执行入口通过）
- [ ] 该项的断言/EXPECT_PATTERN 需要更新
- [ ] 需要新增测试项覆盖描述的边界情况
- [ ] 无需修改测试（等待原测试与保持项实际复测）

## 经验提取

[待补充：从这次反馈学到的可推广经验]
```

`source` 取实际来源，不因默认值把 Agent 推断冒充 developer；Agent 推断标 inferred，未 review 时保持 Step 1.5 候选。正式反馈按事件追加：若同名文件已有内容，用唯一时间后缀保存新事件，不覆盖原反馈；revoke 同样追加。用户指定 verdict 的授权无需重复确认。

### Step 3: 规则映射（不直接写 feedback-rules.json）

只有 Step 1.5 已满足且有范围/依据的正式 Feedback markdown 才按 verdict 映射；未归因候选不进入规则。**但 tester 测试期间不直接写 feedback-rules.json** — 该文件由 coordinator 通过 `/better-test merge` 从所有 run 的 feedback/ 文件重建。

单 tester 场景：tester 在 run 完成后按相同依据和范围规则自行重建 feedback-rules.json。

映射规则（coordinator 或单 tester 在重建时使用）：

| verdict | 映射到 feedback-rules.json 的段 | 行为 |
|---------|------|------|
| not-a-bug | `suppress` | 仅依据相符的 scope 内排除 active failures；需求/版本/环境/入口变化触发复核 |
| wontfix | `suppress` | 在明确不修决定的 scope 内排除 active 提报；缺陷及接受风险仍可见，不代表产品通过 |
| deferred | `known_behaviors` | 仍算 fail，但提示"已知" |
| fixed | （不写 suppress）| 保持待复测；修复完整性门与回归实际通过后按原流程关闭 |
| fixed-differently | `known_behaviors` | 经来源核实后走 update 修正断言/oracle；仍需复测与回归 |
| revoke | 撤销该 test_id 之前的任何 verdict | 按时间序列处理，后写的 revoke 覆盖先写的 verdict |

**回归保护（Tier 1 核心流程）**：verdict=fixed 或 fixed-differently 时，自动提示：

```
1. 该测试项是否已加入 bug-regress canary？未加 → 建议加入
2. fixed-differently → 按 references/update-workflow.md 核实语义与独立 oracle 依据，按写权限修正对应断言；不自动接受新输出
3. 下次 strategy 推荐 bug-retest，并记录原症状、保持项、相邻不变量、替代缺陷反例和回归范围
4. 按 references/test-execution-workflow.md 修复完整性门实际执行；知识更新、fixed 声称或 pilot 不等于 VERIFIED，escape closure 仍需原验证器
```

**范围检查优先**：消费规则前对账原依据及产品/环境/entry/case/recipe revisions。超出范围、需求变更或出现反证时标 required 并重新选择验证；历史 run/results 不改写为 skip/pass。当前规则格式若不能表达所需范围，不增加 schema 字段或藏在 provider_metadata；保持候选、拒绝升级成全局 suppress，并在现有记录留下阻塞。范围检查是工作流纪律，不声称现有机器 merge 已校验。

**重要**：`feedback-rules.json` 由 `/better-test merge` 自动重建或单 tester 在 run 完成后重建，**严禁人手编辑**（red line #7）。如果要调整规则，撤回并重新走 `/better-test feedback`。

### Step 4: 同步更新 known-issues.md（人类视图）

`feedback-rules.json` 是机器视图（json，agent 读），`known-issues.md` 是人类视图（markdown，团队读）。由有写权限的 Coordinator 或完成后的单 tester 在 Step 3 重建后同步；活跃 Tester 只保留自己 run 的建议：

```markdown
# Known Issues

## 已 suppress（不算 active failures）

| Test ID | Verdict | 来源版本与范围 | 原因/依据/复核触发 |
|---------|---------|---------|------|
| <id>    | not-a-bug | <产品/环境/entry/revisions> | <reason + source refs> |

## 已知行为（仍算 fail，但已知）

| Pattern | 描述 | 来源版本 |
|---------|------|---------|
| <pattern> | <note> | v<ver> |

## 经验教训

- <insight> （<date>）
```

### Step 5: refresh status.md

同样只由有权限角色在正式规则重建后调用 `context_refresh` 等价的逻辑：基于最新 results.json + feedback-rules.json，重新生成 `status.md`。这样下个 session 加载 status.md 就看到最新状态。

### Step 6: git commit

先检查已解析 TEST_ROOT 的实际仓库边界与 diff，只提交本次有权限修改的 feedback 或 derived views；路径按真实根解析，不使用硬编码 `.better-work/test`。活跃 Tester 不提交项目级反馈规则/status；Coordinator 不修改或提交别人的 run 原件。commit message 使用 `[better-test] feedback: <test_id> (<verdict>) in <version>`。

commit message 前缀 `[better-test]` 是子 skill 的来源标记（架构文档第 8.1 节要求）。

## 经验规则（lessons）的特殊处理

`lessons` 段不绑定具体 test_id，是从多次 feedback 提炼出的可推广经验。例：
- "MCP 工具的参数风格是 `symbols` 数组而非 `security_list`"
- "REST POST 必须 unlock-trade 之后才能下单"

写入时机：
- agent 在录入 feedback 时主动识别"这条是不是有可推广性"
- 或用户显式说"把这条也作为 lesson 记下来"
- 不要每条 feedback 都自动产生 lesson（避免噪声）

## 撤销 feedback

如果误录或开发者改口：

```
/better-test feedback <id> revoke
```

执行：
- 追加新的 revoke 事件并引用被撤销的旧反馈；不重命名、覆盖、删除历史 run 的原反馈或 artifacts
- 活跃 Tester 在自己 run 写 revoke；Coordinator/完成后的单 tester 按时间重建规则，移除该 id 对应的旧规则，历史来源仍可读
- commit message: `[better-test] revoke feedback: <test_id>`

## Escape Analysis（post-ship bug 强制流程）

任何 **post-ship bug**（发布后才被外部/用户发现的缺陷）录入时，除常规 feedback 外，
必须在 `test/escapes.json` 新增结构化记录并同步 `test/escapes.md` 人类视图。修的不是
bug，是放走 bug 的流程
——这是测试体系自身的 double-loop learning。

```
Markdown 视图格式（每条）:
  ## ESC-NNN: <一句话标题>
  - 逃逸 bug: <是什么、谁报告的、修复包/复测结果>
  - 本应拦截的 gate 条目: <critical-matrix / test-groups 中的具体 ID；不存在则写"不存在"——这本身就是发现>
  - 当时是否执行: <执行了但没拦住 / 未执行 / 无条目可执行；附证据（run 记录、ledger）>
  - 未拦住根因: <可多层：用例缺失 / 矩阵未执行 / oracle 缺失 / 方向性验证 / 维度盲区>
  - 体系修正动作: <新用例 / 新 gate / impact-map 补边 / 流程修正；逐项标落地状态>
```

铁律：
- "本应拦截的 gate 条目"必须取证到具体 run 记录，不凭印象回答"应该跑过了"
- 根因停在"用例缺失"不够——追问"为什么当时的体系没让这个用例存在/被执行"
- 每条 escape 的修正动作进 update workflow 落地，escape 记录保持 open 直到实际验证；知识/工具已修不代表 closure
- 漏测根因分别核对需求没发现、用例没设计、工具无法操作、oracle 错误、执行没选、证据误判；各自落到来源/地图、case、recipe、oracle、strategy 或证据审查，不能全部归为“缺用例”
- 活跃 Tester 将 post-ship/escape 候选写自己 run，Coordinator 或完成后的单 tester 才同步项目 escapes；不得越过角色隔离
- feedback / bug 元数据必须写 `post_ship: true` 和 `escape_id: ESC-NNN`
- `closed` 只在所有 corrective action 均为 `verified` 且有 closure evidence 时允许；写后必须运行
  `python3 <skill-root>/scripts/validate-escapes.py test/escapes.json`

## UX 改进建议（附加输出）

不是 verdict（不绑定 test_id），是 feedback 的附加产出；活跃 Tester 只写自己 run 的反馈材料。测试过程中每次操作失误、被不明确的错误信息误导、或在文档缺失中浪费时间时，反问"产品能否改进让后续用户不踩这个坑"。

```
写入: 活跃期为自己 run 的 progress.md UX 段；完成后/Coordinator 合并时在现有反馈视图追加，不修改旧 run 原件

格式（每条）:
  ## UX-NNN: <一句话标题>
  踩坑场景: <操作了什么、看到了什么>
  根因: <为什么会操作错>
  建议: <产品可以怎么改进——更好的错误信息 / 预校验 / 文档>

与 bug report 一起交付给开发者。
```

## 不要做的事

- ❌ 不要将未归因/缺依据反馈放入正式 feedback/*.md；候选放现有 progress/update 待办，不能自动产生 suppress
- ❌ 不要人手编辑 `feedback-rules.json` —— 破坏自动化，无法追溯来源
- ❌ 不要在 verdict=fixed 时写 suppress —— fixed 应该被下次跑证明，不是被规则掩盖
- ❌ 不要把 lesson 当作"反馈"录入（lesson 不绑定 test_id）—— 用 update workflow 单独维护
- ❌ 不要用 ignore、放宽断言、自动 golden 更新或永久全局豁免掩盖未解决失败；wontfix 也不证明产品通过
- ❌ 不要因 feedback/update 修改原历史结果、重命名旧 run 反馈或删除失败证据

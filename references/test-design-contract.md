# 可选用例设计合同 v1

这是 test-groups.md 的 opt-in 设计元数据，不是执行器、可执行断言语言或产品 gate。
原 test ID、旧自由文本和 native tests 保留；原生实现只写稳定文件/selector 引用。
所有实际执行、观察、results 和 FULL-TEST-REPORT 继续使用既有流程。

## 先固定来源，再设计预期

按“来源 → 测试义务 → 场景 → 输入/状态 → 动作 → 预期/依据 → 证据”编写。

1. 固定原需求/契约/已确认 Bug 的 locator、revision/digest、范围和不确定性；无法固定时
   用 unresolved + reason。代码 diff 是行为线索，生产反馈先脱敏、复现和界定条件，不能
   将目标当前输出抄成 golden。缺少需求是需求缺口，与违反已确认契约的产品缺陷分开。
2. 写清谁在何种角色/状态下经何入口做何动作，必须或不得发生什么。按失败后果给出风险；
   在既有 surface-manifest 中引用 feature/entry ID，不在合同另建地图。
3. 保留既有四问：实际调用功能还是只看元数据；哪个具体观察字段证明义务成立；失败是否
   能区分参数、服务、产品；关键字段/关系是否稳定。元数据测试仍有价值，留在对应 lane。
4. 在合成 fixture 上独立推导预期，列初始状态、观察点、比较关系和失败含义。允许多个
   expected 属于同一 case；relation 是人读的设计描述，checker 不计算它。
5. 运行前按既有执行流程绑定 subject/environment、等待条件和上限、归一化、setup/cleanup
   ownership、禁止副作用与故障归因。精确命令在 tools/recipe；合同只引用入口。

没有批准需求的原型仍可探索，但规范性预期保持 unresolved。明确标为 characterization
的历史行为快照只能描述兼容性目标下的所见行为，不能自动提升为“应当如此”。

## Oracle 按主张选择

每条规范性主张记录 authority、scope、revision 和已知局限。可选择批准需求/公开契约、
独立算法或可信参考、状态不变量、关系性质、已确认 Bug。参考实现须对齐参数、权限、
时间窗、数据与字段语义；它的已知 Bug 不是正确答案。独立算法不能调用被测函数计算 expected。

不存在 UI 永远最高的固定排名：UI 是观察渠道，特定兼容性目标下才成为所选参考。
现有 oracle-catalog 的来源目录和失效/降级条件保留，发生来源冲突时记录冲突范围并调查，
不能让 Agent 静默选边。版本未知必须显式保留缺口。

每条 expected 的 observe 说明看哪里，relation 说明比较规则及差异意味着什么，value
可补静态预期。非空、200、退出 0 仅在它本身就是待验证义务时可单独使用；业务保存
还须观察重开内容、持久状态或副作用。零副作用的判断需要可观察探针的正控制，不能把
观察器失效当成产品正确。目标故障反例/变异证明仍按既有 mutation 和 run 流程取证。

## 合同字段与标记

仅 TEST_ROOT/test-groups.md 中独占一行的标记、后接 fenced json block 被读取；两者之间
只允许空白行，不能插入段落。支持 Markdown 的至少三个反引号或波浪号 fence；关闭 fence
同字符且长度不短于开启 fence。未标记 JSON、其它 fenced 示例里的标记不会被采用。
标记后的 JSON 破损不能回退为旧格式。每个 block 是一个 case object。

规范样例为 fixtures/test-design/valid.json。复制到 test-groups.md 时：

````markdown
<!-- better-test:case-contract:v1 -->
```json
{
  "case_id": "J-02",
  "revision": 1,
  "requirements": ["test-root:reference/jobs-v2.md#AC-2@fixture-r1"],
  "features": ["F-JOB-SUBMIT"],
  "entries": ["API-POST-JOBS", "CLI-JOB-SUBMIT"],
  "risk": {"failure": "重试创建重复任务或 outbox 事件", "priority": "high"},
  "preconditions": ["专用租户 T1，已存在 K/P1 的任务", "隔离 CLI/API 共用同一持久状态"],
  "input_fixture": "test-root:reference/job-small.json@fixture-r1",
  "actions": ["CLI 再提交相同 key 和 payload", "通过独立持久状态探针查询任务及 outbox"],
  "expected": [
    {"observe": "responses.job_id", "relation": "与原任务 ID 相同，差异意味着重放语义错误"},
    {"observe": "durable_jobs_and_outbox_matching_key", "relation": "任务与事件分别等于 1；任一大于 1 表示重复副作用", "value": {"jobs": 1, "outbox": 1}}
  ],
  "oracle_ref": "test-root:oracle-catalog.md#O-JOB-IDEMPOTENCY@fixture-r1",
  "runner_ref": "test-root:tools/test_jobs.py::test_retry_same_key@fixture-r1",
  "environment_ref": "test-root:env-config.md#OP-JOBS",
  "cleanup_ref": "test-root:tools/jobs-fixture.py#cleanup-owned-run",
  "evidence_required": ["原始请求与响应", "持久任务与 outbox 计数", "subject/environment identity"]
}
```
````

不要将示意占位 hash 写成已固定来源；这里的 fixture-r1 是合成 fixture 标签，不是产品版本。
UI/API 完整可选 block 在 fixtures/test-design/ui-example.md 与
fixtures/test-design/api-example.md；它们是合成设计，未运行产品。

| 字段 | 约束 |
|---|---|
| case_id / revision | 非空 string / integer >= 1，保留原 ID |
| requirements | 非空 Reference 列表 |
| features / entries | 非空的非空 string 列表，引用地图 ID |
| risk | object；failure 非空 string；priority 为 low/medium/high |
| preconditions / actions / evidence_required | 非空的非空 string 列表 |
| input_fixture / oracle_ref / runner_ref / environment_ref / cleanup_ref | Reference |
| expected | 非空 object 列表；observe、relation 非空 string；value 可为任意 JSON；可选 oracle_ref 覆盖 case 默认依据 |

Reference 是非空 locator string，或只含 status/reason 的 object：
`{"status":"unresolved","reason":"来源版本待确认"}` 或
`{"status":"not_applicable","reason":"纯函数无外部清理"}`。
这两种状态结构合法，也会进入 warnings，不代表可执行或语义通过。

root/risk/expected 对象允许补充设计信息，例如适用范围、失败含义；补充字段不被
checker 解释、授予 proof 或写入结果。Reference 状态对象不接受额外字段。
空白字符串、错误类型、空必填列表、重复 JSON key、NaN/Infinity 和重复 case ID 均拒绝。
同一 case 多条 expected 不按断言数量另计用例。具体结构权威为 schemas/test-design.schema.json。

## 引用与安全边界

- `test-root:reference/jobs-v2.md#AC-2@fixture-r1`：显式 TEST_ROOT 内文件引用。
- `test-root:tools/test_jobs.py::test_retry_same_key@fixture-r1`：原生测试文件及 selector。
- `test-root:env-config.md#OP-NOTES-WEB`：指向具名 recipe，不能把 runner 与环境合并。
- `spec/jobs-v2.md#AC-2@revision`、URL、外部路径：仅 locator，不自动读取或联网。

本地形式为 `test-root:<relative-POSIX-file>[#anchor | ::selector][@revision-or-digest]`。
路径按字面处理，不进行 shell/环境变量/URL 解码。`#`、`::`、`@` 作为 locator 分隔符，
因此包含这些字符的文件名不能用本地形式检查，可作为普通外部 locator 保留未核验。
不允许绝对路径、`..`、反斜杠、NUL 或指向 TEST_ROOT 外的 symlink。
只检查文件存在性，不读引用内容、不验证 anchor、selector、revision/digest 或地图 ID。

缺本地文件是 local_reference_missing warning（如 fixture 尚未生成），文件存在仍是
local_reference_unverified；其内容和语义未确认。URL/外部 locator 是
external_reference_unverified。明确 unresolved、不适用、来源未固定版本分别提示；
普通 requirements locator 无 @ 时提示 source_revision_not_fixed。@ 只承载版本声明，
不证明它准确，含 @ 的 URL 也不构成固定来源证明。共享最小 Reference 形状不能承载
所有 authority/scope/revision 事实，语义审查必须读取原来源并核验，不能依赖字符串启发式。

checker 不调用 shell、不 import 被测源码、不执行合同中 actions/命令、不 fetch URL。
仅读取已授权 root 的 test-groups.md 与 Skill 自身 schema，并复用 Skill 自带
hybrid_core.validate_json_schema；import 禁写 bytecode。test-groups 本身越界是操作错误。
这里是静态路径安全检查，不承诺抵御扫描期间恶意并发替换文件的竞态。

## 调用与结果

先沿用 scripts/resolve-test-root.sh 解析现有项目 TEST_ROOT；本 checker 不另选根目录：

```text
python3 <this-worktree>/scripts/validate-test-design.py --test-root <resolved-root> --format json
```

JSON 固定基础字段：

```json
{"schema_version":1,"scope":"design_structure","status":"not_adopted","errors":[],"warnings":[],"case_ids":[]}
```

| 结果 | 退出码与含义 |
|---|---|
| valid | 0；结构合法，包括带 unresolved/missing warning 的 case |
| not_adopted | 0；旧文件存在、无可采用标记，明显提示未升级 |
| invalid | 1；破损 block、缺字段/类型错、重复 ID、危险本地引用 |
| operation_error | 2；文件不存在/不可读、根目录不合法、CLI 错或 Skill schema 不可用；输出 status=invalid，errors 明确标 operation_error |

errors/warnings 是带 block/marker 行号和字段路径的字符串列表；全局提示无 block 位置。
case_ids 是已解析 JSON 中声明的非空 ID，去重后保留顺序，invalid 时也可能列出部分 ID，
不能据此激活用例。调用方必须保留 status、errors、warnings 与退出码，不能只凭 exit 0 或
valid 声称已升级、可执行或通过。`--format text` 是人工视图；JSON 是固定消费接口。

受支持 Schema 关键字限于本合同所需的 `$ref`（本地 #/$defs）、`anyOf`、`type`、
`required`、`properties`、`additionalProperties: false`、`items`、`minItems`、`minimum`、
`pattern`、`enum`；识别 `$schema/$id/title/description/$defs` 注解/定义。本 checker 使用
既有 helper 的子集，新增未支持关键字会操作失败，不声称支持整个 Draft 2020-12。revision 使用 JSON 整数字面量（如 1）；现有 helper
按 Python int 区分 integer，1.0 不作为 revision 整数接受。

## 重复与设计审查

相同义务、前置状态等价类、输入分区、预期及观察路径的重复可合并；保留历史 ID 映射与
处置理由。不同权限、入口、平台、副作用或独立 oracle 的场景不能因标题相似删除。
checker 只拒绝相同 case ID，不执行自然语言去重。语义审查还须判断低价值断言和循环 oracle。
fixtures/test-design/review-scenarios.md 提供三份压力审查输入和判断依据；Agent 识别能力
由 M6 独立试运行验证，当前 NOT_RUN。

## 四种完成度分别留证

在原 test-groups.md 的 case 旁记录以下文档事实，不增加状态账本，不写入 results.status：

```text
Scope: case J-02 revision 1; recipe OP-JOBS revision 1
Design: AUTHORED; unresolved: 具体原因 / none（经核验后）
Structure: NOT_CHECKED / checker 输出引用（仅结构）
Execution proof: NOT_RUN / 既有真实 run + subject/environment + case/recipe revisions
Detection proof: NOT_RUN / faulty run + correct-control run + fault + predicate
Current review: required: 变化与受影响引用 / current-within-proof-scope（须有相符 proof）
```

设计已写、结构检查、指定环境实际执行、指定故障检测是独立事实。后两者必须引用已有真实
run，不能用 verified 布尔值自证。历史 Pass 不自动迁移为设计质量已验证。历史 proof 保留；
需求、输入、预期、oracle、runner、recipe 或其 scope/revision 变化触发复核，不改写旧 run。

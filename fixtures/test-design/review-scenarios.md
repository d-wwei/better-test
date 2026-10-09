# 语义审查压力输入（人工标准，Agent 试运行 NOT_RUN）

这些是合成材料。结构 valid 不能区分以下设计质量；不要编造通过率。

## A：低价值断言

来源：合成 notes-v2 AC-5 要求关闭重开后显示保存内容。旧 Bug 为 toast 成功但正文未持久化。
候选：动作点击保存；expected 只检查 toast 非空；以 toast 作为唯一 oracle。
审查判断：拒绝作为 AC-5 的完整证明。toast 可以证明提示义务，但不能证明持久化；应补
重开 title/body、独立持久记录与初始计数，明确各自失败含义。不能据此删除真正的提示用例。
checker 预期：字段齐全可 valid，仍 semantic_review_required；checker 不发现这个语义缺陷。

## B：循环 oracle / 错误实现 golden

来源：合成 jobs-v2 AC-2 明确任务与 outbox 各一次。错误新实现返回 outbox=2。
候选：读取新 job handler 输出写 expected=2，下一次再调用同一函数，结果等于 golden 即成功。
审查判断：拒绝。expected 独立依据是 AC-2，不能用被测实现给自己证明；独立状态探针
应比较计数 1。若只需 characterization，明确范围与已知缺陷，不将快照声明为规范性正确。
checker 预期：test_wrong_implementation_golden_remains_structurally_valid 已证明结构仍可 valid。
是否 Agent 能独立识别与提出有效替代，由 M6 试运行另留证，当前 NOT_RUN。

## C：同义重复与不能合并的入口

来源：同租户/同 key/同 payload 重试只生效一次。
候选 J-02“重复提交不重复建任务”与 J-12“retry 保持一条任务”，具有同状态、输入、API
入口、持久观察路径、expected 与 oracle，只是标题不同。
审查判断：可合并为参数化/原用例，保留 J-12 历史映射及处置理由；标题计数不形成新覆盖。
另一个 J-13 经 CLI 重放，或 J-14 改 denied role、跨租户、response-lost 状态，具有不同
权限、入口或副作用路径，不能因文字相似删掉。仅确认 ID 不重复不足以判断语义独特性。
checker 预期：不同 ID 可同时 valid；语义去重需独立审查，不自动删除。

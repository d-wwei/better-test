# 增量变异测试

触发条件：full/targeted 模式 + 有代码变更 + 项目有变异测试工具

---

## 什么是变异测试

对变更的代码自动生成"变异体"（微小代码改动，如 `>` 改 `>=`），然后跑现有测试。如果测试仍然通过 → 测试没检测到这个变异 → 测试质量不足。

## 步骤

1. 识别本次变更的文件（来自 strategy Step 1）
2. 仅对变更文件生成变异体（增量式，不对全量代码）
3. 对每个变异体运行受影响的测试组
4. 分开统计 killed / survived / timeout / unviable；score 的分母和工具版本必须写明
5. 每个 survived 变异体必须处置：测试盲区 / equivalent / out-of-scope / tool limitation，附证据
6. 将结果绑定 source/build subject；mutation 不能支持 runtime/release claim

## 工具（按语言）

| 语言 | 工具 |
|------|------|
| Java | PIT (pitest) |
| Python | mutmut, cosmic-ray |
| JavaScript | Stryker |
| Rust | cargo-mutants |
| Go | go-mutesting |

## 结果解读

不存在通用固定分数线。若 `project-profile.evidence_policy.mutation.minimum_score` 明确配置，按项目
阈值判 gate；未配置时只报告完整分类和 survivor disposition，不把任何百分比自动翻译成
“良好/可接受/失败”。即使达到项目阈值，关键风险上的单个未处置 survivor 仍可阻断 source gate。

## 不做的事

- 不对全量代码做变异（计算成本太高）— 只对变更的代码
- 不把变异测试得分作为唯一质量指标 — 它是覆盖率的补充不是替代
- 不要求每个项目都做 — 这是可选增强，不是必须

方法论详解见 `references/methodologies/design-rationale.md` 的覆盖率章节。

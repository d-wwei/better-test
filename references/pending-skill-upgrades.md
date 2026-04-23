# Pending Skill Upgrades

> 通用测试经验的升级队列。由 `/better-test update` Step 6 自动追加，由人审核后写入 skill 文件。
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
- **状态**: pending / approved / rejected / promoted
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

（空——由 update Step 6 自动追加）

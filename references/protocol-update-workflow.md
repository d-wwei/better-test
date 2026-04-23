# Protocol Update Workflow

`/better-test protocol-update [text]` — 升级 `test/protocol.md` 中的测试认知约束。

## 输入模式

### 模式 A：用户显式输入

```
/better-test protocol-update "daemon 会包装所有 backend 错误码，永远不信外层 error message"
```

### 模式 B：自动总结（无参数）

```
/better-test protocol-update
```

Agent 回顾当前会话，提取候选经验。

---

## Step 1: 内容分流（在写入前必须先判断该写哪）

对每条候选知识，按以下决策树判断归属：

```
Q1: 这条是关于"怎么想/判断"还是"怎么做/执行"？
    怎么做 → NOT protocol
      → 执行步骤 → test-execution-workflow.md
      → 流程步骤 → strategy/feedback/update workflow
    怎么想 → 继续 Q2

Q2: 这条是所有项目通用还是这个项目特有？
    所有项目通用 → skill 的 protocol-base.md（L0 + 思维纪律）
      ⚠ 修改 protocol-base.md 影响所有项目 → 排队到 pending-skill-upgrades.md，需人审核 + L2 审计
    这个项目特有 → 继续 Q3

Q3: 每次测试都需要想到还是特定情况才用？
    每次都需要 → protocol.md 项目纪律段（≤5 行）
    特定情况 → NOT protocol
      → 测某模块时才用 → known-issues.md lessons（按组标签，Hook 提取）
      → 特定环境 → env-config.md 注意事项
      → 特定测试组 → test-groups.md failure modes

Q4: 具体到 agent 能对照自检吗？
    "注意质量" → 拒绝（空话）
    "daemon 包装错误码，不信外层 message，查 debug log 原始码" → 通过（具体）
```

**如果候选知识不属于 protocol → 告知用户该写哪里，引导到正确的文件。**

---

## Step 2: 自动验证

通过 Step 1 分流后进入 protocol 的候选，自动检查以下 5 项：

| 检查项 | 检查方式 | 不通过怎么办 |
|--------|---------|------------|
| **矛盾检测** | 新规则和现有 protocol 规则是否矛盾？ | 标出冲突，让用户决定替换还是放弃 |
| **降级检测** | 新规则是否削弱了现有规则的严格程度？ | 需要用户确认（不能自动通过） |
| **范围检查** | 是否在 protocol 范围内（思维/判断，不是执行步骤）？ | 重新分流到正确文件 |
| **空话检测** | 是否具体到 agent 能对照自检？ | 拒绝，要求改具体 |
| **行数检查** | 项目 protocol.md ≤ 15 行？项目纪律段 ≤ 5 行？ | 超限 → 提出替换方案 |

---

## Step 3: 分级审批

| 变更类型 | 审批方式 | 理由 |
|---------|---------|------|
| 新增到项目纪律段 | **自动验证通过 → 自动写入** | 低风险，只是追加项目经验 |
| 修改项目纪律段现有规则 | **自动验证 + 通知用户**（不阻塞） | 中风险 |
| 修改 protocol-base.md（L0/思维纪律） | **排队 pending-skill-upgrades → 人审核 + L2 审计** | 高风险——影响所有项目 |
| 删除任何规则 | **用户确认 + L2 审计 + 触发检查** | 最高风险——检查最近 5 次是否被触发 |

### L2 审计 protocol 变更时检查

- 新规则和现有规则是否矛盾？
- 删除的规则在最近 N 次测试中是否被实际触发过？（触发过 = 有用，不该删）
- 变更后的 protocol 整体是否仍然自洽？
- 变更是否在 protocol 范围内？

---

## Step 4: 呈现变更方案

```
当前项目 protocol.md（安全纪律 + 项目纪律，≤15 行）:
  [显示完整内容]

分流结果:
  → protocol 项目纪律: "<新规则>"
  → known-issues lessons: "<另一条不属于 protocol 的经验>"（已引导到正确文件）

提议变更:
  [+ 新增] 在项目纪律段追加: "<新规则>"

验证结果:
  □ 矛盾检测: 无冲突
  □ 降级检测: 无降级
  □ 范围检查: 通过（思维层面）
  □ 空话检测: 通过（具体可检）
  □ 行数检查: 项目纪律 3/5 行 → 4/5 行

变更后（<M>/15 行，项目 protocol）:
  [显示完整预览]

审批方式: auto-validated（新增项目纪律）
```

---

## Step 5: 写入

```
1. 保存当前 protocol.md 全文到 protocol-versions/v<X.Y.Z>.md
2. 修改 protocol.md
3. 在 protocol-changelog.md 追加记录（叙事+KAC 格式）
4. 项目 protocol.md 通过 `@.better-work/test/protocol.md` 注入 CLAUDE.md（配合 skill 的 `@protocol-base.md`），变更下次会话自动生效
```

### 项目纪律段满 5 行的处理

```
如果项目纪律段已满 5 行，新增一条必须替换一条：
  1. 展示当前 5 条 + 新候选
  2. 建议替换"最近 5 次测试中触发最少的那条"
  3. 被替换的规则降级到 known-issues.md lessons 段（不是删除）
  4. 用户确认替换方案
```

---

## Step 6: 通用原则升级提议

如果发现一条经验可能是**所有项目通用**的：

```
Agent 提出候选："这条经验在 3 个不同场景中都适用，可能是通用的"
  → 写入项目 protocol 项目纪律段（当前项目立即生效）
  → 排队到 skill 的 references/pending-skill-upgrades.md（等人审核）
  → protocol-changelog 标注"通用原则候选"

Agent 不能自动修改 skill 的 protocol-base.md。通用原则升级走 pending-skill-upgrades 排队。
```

---

## 不要做的事

- ❌ 不要把执行步骤写入 protocol（去 workflow）
- ❌ 不要把能从 env-config/known-issues 派生的规则写入 protocol（让 Hook 注入）
- ❌ 不要把空话写入 protocol（"注意质量"不是规则）
- ❌ 不要直接修改 skill 的 protocol-base.md — 排队到 pending-skill-upgrades.md
- ❌ 不要删除规则而不检查最近是否被触发
- ❌ 不要跳过保存全文快照到 protocol-versions/

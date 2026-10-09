# 探索性测试 Charter

触发条件：用户要求深度测试、strategy 发现某模块无深测历史，或来源/入口/状态 UNKNOWN、
义务对账存在缺口假设。Charter 是一次有界调查，发现回写原知识；不建立长期探索报告体系。

## 步骤

1. 从 `surface-manifest.md` / 当前 `strategy-plan.md` 引用未知或缺口及其来源版本，
   说明风险假设：“在某角色/入口/状态下，某保证可能失效或尚不明确”。
2. 约定范围、时间盒、工具能力、目标 identity、owner、副作用/授权和停止条件。
   init 只能写 charter 草稿，不操作产品；真正探索进入明确 execution 阶段。
3. 围绕假设探索输入分区、状态迁移、权限、替代入口、恢复或高阶事故条件。
   时间盒不是固定 90 分钟；按成本/风险选 30/60/90 分钟等，并给有界等待和清理规则。
4. 原 run 的 process-log 记录观察、来源、证据级别、oracle/冲突与下一步。
   oracle 不足的项保持 unresolved；发现“没有用例”不能直接报产品 Bug。
5. 到点或触发停止条件就停，检查所拥有资源/状态并清理。将已确认入口/状态增量写回
   surface，判定场景复用/补入 test-groups/native tests，风险和选择写回 strategy-plan。
   实际违反契约且有证据才走既有 Bug/feedback；剩余 UNKNOWN 留调查责任和后续来源。
   遵守 tester 写权限矩阵：共享知识由允许写入的 owner/coordinator 经既有 update/feedback
   收口，tester 先在自己的 run 留变更建议，不跨 tester 写文件。

## Charter 模板

```markdown
目标: 调查 [来源义务/缺口引用] 在 [entry_id + 角色/状态] 下的行为
来源: [surface/需求 locator + revision/digest；未知版本写 unresolved + 原因]
假设/风险: [可能失效的保证/禁止副作用；当前知道与不知道的边界]
范围: [包含的入口/状态/平台] | 不含: [边界及理由]
时间盒: [时长及理由] | 停止条件: [到点/安全阈值/需要新授权/目标身份异常]
操作条件: [目标 identity、owner、recipe/工具引用、授权、副作用范围、等待上限、cleanup]
观察/oracle: [具体字段/持久结果/关系、正控制、独立依据、未解决项]
关注点:
  - [选定输入分区/权限/迁移/替代入口及理由]
  - [已知三因素故障或关键时序；pairwise 不能替代]
回写: [surface/test-groups/strategy-plan 的增量建议、责任人]
```

## 记录格式

```text
[MM-DD HH:MM:SS±ZZ] 观察: <具体输入/状态/输出，含 artifact locator>
        证据: <direct / indirect / confirmed 与真实独立性依据>
        Oracle: <source scope/revision 或 unresolved；冲突双方>
        后续: <补地图/补 case/待确认/既有 Bug 流程及理由>
```

## 关键原则

- 探索补未知边界，自动化防回归；两者不替代 hard gates、高风险 canary 和已定义不变量。
- 时间盒到点即停，完成的是调查范围；不能称枚举完整或“未发现 Bug = 全覆盖”。
- 所有结论沿用既有证据标准，运行/检测证明引用真实 run；不同 reviewer 的共识不升级证据。
- design、structure、execution proof、detection proof 分开记录，不新增 results verdict。

方法论详解见 `references/methodologies/design-rationale.md` 的测试设计章节。

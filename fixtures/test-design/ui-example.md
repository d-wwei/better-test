# UI：平台快捷键保存 U-02

合成需求与设计示例；不是产品执行记录。来源与环境需在真实项目中绑定。

<!-- better-test:case-contract:v1 -->
```json
{
  "case_id": "U-02",
  "revision": 1,
  "requirements": [
    {
      "status": "unresolved",
      "reason": "REPORT §9.1 notes-v2 AC-1/5 是合成契约；真实需求 authority/revision 待绑定"
    }
  ],
  "features": [
    "F-NOTE-SAVE"
  ],
  "entries": [
    "E-NOTE-SHORTCUT-MAC"
  ],
  "risk": {
    "failure": "快捷键未保存，或成功提示后内容未持久化",
    "priority": "high"
  },
  "preconditions": [
    "隔离 macOS 浏览器 profile 与空笔记库",
    "独立 fixture 标题为两个前置空格 + Sprint note + 两个后置空格，正文 draft-A",
    "绑定正确 build、writer 与完成事件；harness 上限不是产品 SLA"
  ],
  "input_fixture": {
    "status": "unresolved",
    "reason": "专用 notes fixture 尚未生成；不能读取真实用户笔记"
  },
  "actions": [
    "仅通过 Cmd+Enter 保存，不点击按钮",
    "等待具名 recipe 的明确完成条件后关闭并重开笔记"
  ],
  "expected": [
    {
      "observe": "reopened.title",
      "relation": "等于 trim 后的 Sprint note；差异表示标题规则被破坏",
      "value": "Sprint note"
    },
    {
      "observe": "reopened.body",
      "relation": "逐字等于 draft-A；差异表示正文丢失或被修改",
      "value": "draft-A"
    },
    {
      "observe": "durable_notes_matching_owned_fixture",
      "relation": "数量等于 1；0 表示未持久化，大于 1 表示重复副作用",
      "value": 1
    }
  ],
  "oracle_ref": {
    "status": "unresolved",
    "reason": "独立 notes-v2 契约未绑定；禁止读取 shortcut handler 返回值生成 expected"
  },
  "runner_ref": {
    "status": "unresolved",
    "reason": "项目原生 browser E2E 文件/selector 待确认"
  },
  "environment_ref": "test-root:env-config.md#OP-NOTES-WEB",
  "cleanup_ref": {
    "status": "unresolved",
    "reason": "仅删除本 run 拥有的隔离 fixture/profile 的清理工具待绑定"
  },
  "evidence_required": [
    "按键与保存时间线",
    "DOM/可访问性树或截图",
    "重开 title/body 与持久记录数",
    "build/process/session identity"
  ]
}
```

Design: AUTHORED; unresolved: 真实产品来源、runner、recipe 和 fixture 绑定待完成
Structure: NOT_CHECKED（仓库 fixture checker 可验证结构，不能证明产品）
Execution proof: NOT_RUN
Detection proof: NOT_RUN
Current review: required: 绑定真实项目与来源版本

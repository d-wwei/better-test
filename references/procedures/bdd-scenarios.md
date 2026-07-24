# BDD 场景生成

触发条件：用户提供了 PRD 或需求文档（信号源 F）

---

## 步骤

1. 提取 PRD 中的每个功能需求
2. 为每个需求写 Given-When-Then 场景：
   - 至少 1 个正向场景（happy path）
   - 至少 1 个异常场景（错误输入/权限不足/超时）
3. MECE 检查：PRD 每个需求点是否都有对应场景
4. 将场景转化为 test-groups.md 条目（每个 Given-When-Then = 一个测试用例）

## 格式

```
Given <前置条件>
When <用户操作>
Then <预期结果，带具体字段/值/时间>

Given <异常前置条件>
When <同样操作>
Then <错误处理预期>
```

## 示例

```
需求："用户登录后看到首页"

场景 1（正向）:
  Given 用户已注册且账户未锁定
  When 输入正确邮箱和密码并点击登录
  Then 3 秒内跳转到 /dashboard，页面显示用户昵称

场景 2（异常）:
  Given 用户连续输错密码 3 次
  When 再次尝试登录
  Then 显示"账户已锁定，请 30 分钟后重试"
```

## 不做的事

- 没有 PRD 不强行套 BDD — 直接用 MECE 用户场景 + 代码分析
- 不为内部实现细节写 BDD — BDD 描述用户可见行为，不描述内部状态

方法论详解见 `references/methodologies/design-rationale.md` 的测试设计章节。

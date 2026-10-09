# API/CLI：幂等重放 J-02

合成需求与设计示例；不是产品执行记录。来源与环境需在真实项目中绑定。

<!-- better-test:case-contract:v1 -->
```json
{
  "case_id": "J-02",
  "revision": 1,
  "requirements": [
    "test-root:reference/jobs-v2.md#AC-2@fixture-r1"
  ],
  "features": [
    "F-JOB-SUBMIT"
  ],
  "entries": [
    "API-POST-JOBS",
    "CLI-JOB-SUBMIT"
  ],
  "risk": {
    "failure": "重试创建重复任务或 outbox 事件",
    "priority": "high"
  },
  "preconditions": [
    "专用租户 T1，已存在 K/P1 的任务",
    "隔离 CLI/API 共用同一持久状态"
  ],
  "input_fixture": "test-root:reference/job-small.json@fixture-r1",
  "actions": [
    "CLI 再提交相同 key 和 payload",
    "通过独立持久状态探针查询任务及 outbox"
  ],
  "expected": [
    {
      "observe": "responses.job_id",
      "relation": "与原任务 ID 相同，差异意味着重放语义错误"
    },
    {
      "observe": "durable_jobs_and_outbox_matching_key",
      "relation": "任务与事件分别等于 1；任一大于 1 表示重复副作用",
      "value": {
        "jobs": 1,
        "outbox": 1
      }
    }
  ],
  "oracle_ref": "test-root:oracle-catalog.md#O-JOB-IDEMPOTENCY@fixture-r1",
  "runner_ref": "test-root:tools/test_jobs.py::test_retry_same_key@fixture-r1",
  "environment_ref": "test-root:env-config.md#OP-JOBS",
  "cleanup_ref": "test-root:tools/jobs-fixture.py#cleanup-owned-run",
  "evidence_required": [
    "原始请求与响应",
    "持久任务与 outbox 计数",
    "subject/environment identity"
  ]
}
```

Design: AUTHORED; unresolved: 真实产品来源、runner、recipe 和 fixture 绑定待完成
Structure: NOT_CHECKED（仓库 fixture checker 可验证结构，不能证明产品）
Execution proof: NOT_RUN
Detection proof: NOT_RUN
Current review: required: 绑定真实项目与来源版本

# Confirmed Bug Issue Submission

触发条件：项目存在启用的 `bug-issue-policy.json`，且 run/merge 已完成结果、L2 和
`FULL-TEST-REPORT` 校验。

## 目标

对证据等级足够高的新 Bug 建立研发 tracker 闭环：

- 每个 Bug 创建一个独立 GitHub Issue；
- Issue 内嵌完整、已脱敏的 8 节 Bug Report，不只放本地路径或摘要；
- 本地 run/merge 继续保存原始证据和完整报告；
- 重跑使用稳定 fingerprint 查重，绝不重复开单；
- 创建或关联后写入 run-local `bug-issue-submissions.json`。

## 自动提交门禁

必须同时满足：

1. `bug.status` 在 policy 的 `eligible_statuses`，默认仅 `OPEN/CONFIRMED`；
2. `bug.evidence_level` 和 validated results 中引用该 `bug_id` 的 typed evidence 都是
   `confirmed` 或 `proven`；
3. Bug Report 通过 8 节正文、完整 YAML 元数据和 `FULL-TEST-REPORT --validate-only`；
4. `results.json` 或 `merged-results.json` 通过对应 validator；
5. `bug.submission_key` 是稳定的项目级键，不使用会重复的 run-local `BUG-001` 充当身份；
6. secret/PII scan 无发现：密码、token、authorization、账号/订单/设备身份、邮箱、本机
   用户路径、非本地 IP 均不得进入 Issue；
7. GitHub 身份对目标仓有 `WRITE` 以上权限，仓库已开启 Issues。

`direct`、`binary`、`indirect`、`blocked`、推断性根因、source-only runtime claim 一律不自动
提交。发现敏感内容时 fail closed，不做猜测式自动脱敏。

v4 run/merge 应在项目的 `bug-issue-policy.json` 中声明 `project_profile`，存在多个历史
profile revision 时使用 `project_profiles` 数组。相对路径先按 policy 文件所在目录解析，
再兼容按 run 目录解析；这样 reviewer 不需要依赖本机
`BETTER_TEST_TRUSTED_PROFILE` 环境变量，也不会把 run-local profile 副本误当 trust anchor。

单 tester run 可在完成 L2 后提交；多 tester 任务必须等待 merge，只由 coordinator 对合并后
仍成立的 Bug 提交。submitter 使用仓库级同机进程锁覆盖“远端查重 → 创建 → ledger 回写”，
避免同一机器上的并发竞态。跨机器仍以 coordinator 单写者规则为最终约束。

## 元数据扩展

可提交的 Bug Report 在标准 `bug:` 元数据中增加：

```yaml
  submission_key: simulate-current-order-symbol-projection
```

同一个真实缺陷跨版本复测时沿用同一个 `submission_key`。Issue fingerprint 由
`provider + repository + submission_key` 计算，因此报告补证或改写标题不会重复开单。
项目可通过 policy 的 `body_preamble` 配置 Issue 正文前言；未配置时使用默认英文前言。

## 命令

```bash
# 只做本地合同校验，不访问 GitHub
python3 <skill-root>/scripts/submit-bug-issues.py \
  --run-dir <run-or-merge-dir> \
  --policy <project>/test/bug-issue-policy.json \
  --validate-only --offline

# 访问 GitHub 做权限和远端 fingerprint 查重，但不创建
python3 <skill-root>/scripts/submit-bug-issues.py \
  --run-dir <run-or-merge-dir> \
  --policy <project>/test/bug-issue-policy.json \
  --dry-run

# 创建或关联；每个 eligible Bug 一个 Issue
python3 <skill-root>/scripts/submit-bug-issues.py \
  --run-dir <run-or-merge-dir> \
  --policy <project>/test/bug-issue-policy.json \
  --submit
```

可用 `--bug <bug_id-or-submission_key>` 限定单个 Bug。`--submit` 成功后 ledger 记录：

```json
{
  "issue_number": 123,
  "issue_url": "https://github.com/owner/repo/issues/123",
  "submitted_at": "2026-08-14T20:00:00+08:00",
  "submission_fingerprint": "<sha256>"
}
```

## 幂等与权限边界

Issue body 自动加入：

```markdown
<!-- better-test-bug-fingerprint: <sha256> -->
<!-- better-test-source-run: <run_id> -->
<!-- better-test-submission-key: <stable-key> -->
```

每次提交先扫描远端全部 open/closed Issues。命中 fingerprint 时只回写本地关联，不创建新
Issue。默认能力是 create-only：不自动关闭、重开、编辑、分配 owner、设置 milestone，也不
修改已有 Issue 的 label 或正文；这些动作必须由项目另行授权。

历史 Bug 不做无差别回填。需要 backfill 时逐个选择当前仍存在、已重新确认、已脱敏并通过
同一门禁的 run/merge。

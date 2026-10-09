# Team review input fixtures

All six scenarios are synthetic, self-contained authored inputs. They do not represent
actual Better Test product runs, reviewers or resources. Semantic rehearsal: **NOT_RUN**.

Use the worktree's `references/l2-audit-prompts.md` and `references/team-role-presets.md`.
This is optional review material, not a case registry, results schema or second report.

| Scenario | A input | B input |
|----------|---------|---------|
| shortcut-gap | shortcut-gap/phase-a.md | shortcut-gap/phase-b.md |
| shared-golden | shared-golden/phase-a.md | shared-golden/phase-b.md |
| minority-counterexample | minority-counterexample/phase-a.md | minority-counterexample/phase-b.md |
| shared-desktop | shared-desktop/phase-a.md | shared-desktop/phase-b.md |
| isolated-api | isolated-api/phase-a.md | isolated-api/phase-b.md |
| zero-findings | zero-findings/phase-a.md | zero-findings/phase-b.md |

Coordinator supplies only the selected phase-a.md and its source.md in a fresh reviewer
session. No entire folder, README, phase B, author claims or assessor material in A's
message. The repo is not an access sandbox: inspect actual input/tool traces for early
reads. If the reviewer reads B early, record contaminated independence; do not relabel it.
After A is saved in the rehearsal run's existing l2-findings.md, supply phase-b.md;
reviewer reconciles and appends B there. Preserve A, actual inputs, tool traces and
observations in existing run artifacts/process-log; use existing audit/merge disposition.

Only the assessor reads `assessor-only.md` after collecting actual reviewer outputs.
Assess source-based obligations, handling of disagreement and resource choices, rather
than exact wording. Record zero findings, unverified items and a failure to follow A/B.
A resource proposal does not prove mutual exclusion. Actual parallel/GUI behavior needs
isolated authorized sandbox runs with identity, driver and cleanup observations.

Static check from this worktree:

```sh
python3 fixtures/team-review/check-packaging.py
python3 fixtures/team-review/test-packaging.py
```

It checks complete slices, A's source-only links and local input existence. It does not
judge reviewer correctness, prove no hidden reads or execute a product/GUI/Agent.
Do not infer reviewer accuracy, runtime concurrency or installed Skill validation.

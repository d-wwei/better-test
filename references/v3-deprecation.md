# Results v3 compatibility and deprecation policy

## Current policy

`results_v4=default` changes the primary authoring/reporting model to typed v4;
it does not retire v3. Every active default-v4 project continues to dual-write a
validated v3 compatibility result and must keep canonical semantic differences
at zero or explicitly block the run.

Historical v1/v2/v3 readers remain available. A v3 GO that lacks recoverable
typed process/session identity projects to v4 as blocked; compatibility never
authorizes invented subjects or relations. Caveated and known-legacy passes
remain distinct and cannot become unconditional PASS.

Multi-tester merge follows the same split: v4 default uses
`validate-merged-results-v4.py` and preserves each source subject, relation,
typed item/evidence occurrence, gate, caveat disposition and readiness verdict.
`validate-merged-results.py` remains a v3 compatibility reader only. A v3
merged document cannot replace or authorize a v4 default merge.

## Preconditions to propose stopping new v3 writes

All of the following are required:

1. every active validator, merge, report and reflect path reads v4;
2. historical v3 reads remain deterministic and covered by golden fixtures;
3. no active automation consumes only v3;
4. the project-defined stability window has consecutive zero semantic diffs;
5. the migration note names a tested rollback version and data recovery path;
6. the user/project owner explicitly approves stopping v3 writes.

Until then, v3 write status is `supported-compatibility`, not deprecated or
removed. The generic layer never chooses a fixed number of runs for the
stability window; each project records the required change/environment classes.

## Rollback

If v4 validation, subject binding, merge/report compatibility, or semantic diff
regresses, set `results_v4=shadow`, keep v3 as the release input, preserve both
outputs and the diff receipt, and reopen the failing contract/pilot. Rollback
must not delete v4 evidence or hide the reason for the transition.

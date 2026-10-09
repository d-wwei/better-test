# M2 Frozen Feature-Coverage Scenarios

Version: 1 (2026-10-09). All source IDs, products, cases and historical observations are synthetic.
`SHA256SUMS` pins 21 source/case/expectation files; from this directory run
`shasum -a 256 -c SHA256SUMS`. Declared source revisions are fixture metadata; manifest pins actual bytes.
These inputs are not executable runners, product tests or proof of a run. Missing bindings stay missing.

Each scenario splits sources.md, existing-cases.md and expected-disposition.md. The Agent forms obligations
from sources first, then reads old cases. Hide expected dispositions until review. Judge obligations,
traceability and uncertainty, not fixed wording, IDs or number of cases. No new parser or scoring engine.

| Scenario | Decision observed |
|---|---|
| 01-ui-entry-permission | Alternate entry and read-only obligations beyond toolbar tests |
| 02-api-idempotency-permission | Retry/concurrency/authorization order and side effects from contract |
| 03-known-three-factor | Required three-factor sequence survives low-risk pairwise |
| 04-two-body-types | Supported encodings vs explicit rejection; no four-format assumption |
| 05-oracle-conflict | Independent contract beyond shared UI/API parity |
| 06-init-no-execution | Commands stay text; indirect helper/help execution also forbidden |
| 07-legacy-not-adopted | Free text participates; real M1 non-adoption checked after I0 only |

## Three minimal fresh-session tasks for M6

Use an isolated temporary synthetic project and TEST_ROOT, never the installed checkout/global
`/better-test` or real account/product. Explicitly name the tested worktree and HEAD in each Agent prompt,
load that worktree's Skill/workflow, resolve its TEST_ROOT and retain complete trace + knowledge artifacts
in the existing acceptance run layout. Confirm the workflow actually loaded; resource-links cannot prove it.

1. UI: “Use this worktree's strategy workflow. Derive obligations from scenario 01 sources.md and record
   the first pass in strategy-plan before opening existing-cases.md; then reconcile and propose surface/
   test-groups deltas with selection and unresolved bindings. Do not operate a product.” Reviewer later
   checks expected disposition and trace for shortcut/menu permission, independent persistence predicate,
   original IDs, Windows unknown and no false runnable/coverage claim.
2. API: Use the same staged prompt for scenario 02. Reviewer checks obligations precede old cases,
   concurrent retry, revoked permission/cache order, tenant isolation, durable/effect counts, response-loss
   reconciliation and binding gaps. Existing green responses must not end analysis.
3. Init: “Use this worktree's init workflow on scenario 06. Read setup and knowledge; only generate
   knowledge drafts in isolated TEST_ROOT.” M6 fixes an empty isolated BT_INIT_SENTINEL_DIR and records
   pre-inventory, provides it only as context, then examines complete operation trace and post-inventory
   for launch.sentinel/install.sentinel/helper.sentinel. Any launch/install/doctor/helper/--help/product
   import fails even without sentinel. Reads and knowledge writes stay visible. Do not intentionally
   execute source commands to test the sentinel; observe Agent choices. Missing capability stays UNKNOWN.

At I0 for scenario 07, copy its unmarked existing-cases slice into isolated TEST_ROOT/test-groups.md;
run the actual integrated M1 checker and require status=not_adopted/exit 0. Do not add a stub/parser in M2.

Current proof: AUTHORED frozen semantic scenarios only. Checksums/loading show integrity/discoverability.
Fresh Agent trials, trace/sentinel observations, M1 integration and fault-detection comparison are NOT_RUN.
M6 records real run/trace locators and subject/worktree scope before any proof claim. Copying expected
answers does not constitute an Agent trial; preserve original results and one FULL-TEST-REPORT.

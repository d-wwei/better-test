# Better Test Upgrade Status

> Current baseline: v3.2.0
> Reconciled: 2026-07-24
> This file is the current upgrade ledger. Older `v3.1.0` plan/summary/landscape files are historical snapshots.

## Closed from the 2026-07 freeze

| Area | Final state | Enforcement |
|------|-------------|-------------|
| U1 test-root resolution | complete | resolver + flat-layout fixtures |
| U2 results schema hardening | superseded by schema v3 | strict v1/v2/v3 validator + positive/negative fixtures |
| U3 canonical checkout provenance | complete | installer status + provenance test |
| Tier-2 resource split | complete | all procedures under `references/procedures/` + link-integrity test |
| N3 pairwise / equivalence | complete | procedure + deterministic validator + fixtures |
| N5 gate ledger | complete | gate identity, verdict, reason, item/evidence references and semantic consistency |
| N6 escape analysis | complete | structured escape ledger + closure validator + fixtures |
| N7 package DoD | complete | schema v3 required checks for hotfix / feature / rc / non-release |
| N10 two gate checkpoints | complete | direct validator command required at execution and merge |
| Evidence grading | complete | run-local artifact existence + distinct confirmed files + structured proven basis + separate runtime evidence |
| Cross-run config evidence | complete | release-set policy + environment/machine/profile validator |
| Rolling skill review | complete | in-session medium review; queue only for deferred/high-risk items; queue audit test |
| Coordinator verdict challenge | complete | independent adversarial/L2 challenge + merge-level validator before final verdict |
| Codex runtime drift | complete | authenticated Bash + native Write smoke on `0.146.0-alpha.3.1` |

## Historical queue reconciliation

- The 12 candidates in `upgrade-plan-from-lessons.md` were already implemented before this release.
- The old “18 pending” count was a 2026-04 snapshot. The current queue has no `pending` or `pilot` entry.
- The queue Markdown heading (`date + title`) is the stable record key. CI rejects missing/unknown states,
  unresolved pilots without a review deadline, and a pending count at or above the waterline.

## #67–#69 disposition

- **#67 four-step verification order**: promoted as black-box → downstream effect → gray-box →
  white-box, with early-stop rules and a runtime-evidence guard.
- **#68 five-level maturity model**: rejected as a universal workflow. It duplicated existing
  enforcement layers and had no measured decision benefit.
- **#69 fixed black-box coverage ceilings**: superseded. Project-specific percentages must not
  become a universal rule; denominator clarity, reachable coverage, and release-set policy are the
  supported controls.

## Explicit evidence debt, not unfinished framework work

- A fresh 24h longrun is still required before claiming the longrun procedure is field-proven.
  The procedure is usable; this is product-run evidence debt.
- Platform hooks may only surface post-write advisories on runtimes that do not honor PostToolUse
  exit codes. `scripts/validate-results.sh` is therefore the portable non-zero release gate.
- Machine validation proves artifact existence, run containment, reference closure and declared
  independence shape. Whether artifact content actually supports the business claim remains an L2
  evidence-audit responsibility.
- Port binding is project-specific, number-traceability needs semantic/NLP judgment, and periodic
  heartbeat scheduling has no portable hook lifecycle. These remain delegated workflow checks, not
  falsely “planned” universal hooks.

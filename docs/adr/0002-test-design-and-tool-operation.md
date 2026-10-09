# ADR-0002: Advisory Test Design and Tool Operation

## Status

Accepted for the C0 development baseline — 2026-10-09.

This freezes interfaces for the parallel upgrade. C0 does not implement M1–M5,
require a nonexistent checker, or establish execution/detection proof. The
baseline before this decision is `e7f9125226ff3f78e80b61b9448224cc49fcfd86`.

## Context

Existing testing knowledge, identities, evidence and validators remain the
foundation. The upgrade adds source-backed case design, entry/state coverage,
operation recipes, independent review and drift handling without creating
parallel knowledge databases or changing run verdicts.

## Decision: Knowledge Sources

All project files below are relative to the existing resolved `TEST_ROOT`.

| Information | Single authoritative location |
|---|---|
| Requirements / original contracts / issues | Original source; fixed material in existing `reference/` when needed |
| Feature / entry / state / case mapping | Extended `surface-manifest.md` |
| Case ID / conditions / input / expected / oracle | Optional case blocks in `test-groups.md`; native tests stay in their current locations |
| Environment / named operation recipe / tool instructions | `env-config.md` and existing `tools/` |
| Selection / exclusions / roles / frozen revisions | Per-run `strategy-plan.md` |
| Actual observations / evidence / results | Existing run artifacts, process-log and results |

Retain original test IDs. `feature_id`, `entry_id` and `recipe_id` are stable
project-local references; example prefixes are not mandatory global formats.
References describe locator, revision/digest, scope and uncertainty. Unknown
versions remain unresolved, never fabricated hashes. One case may cover several
entries, but unexecuted entries remain explicit coverage gaps.

## Decision: Optional Case Interface (M1)

Only `test-groups.md` blocks marked with
`<!-- better-test:case-contract:v1 -->`, immediately followed by a fenced `json`
block, form case contracts. Each block is one JSON object. Ordinary example JSON
and old free text are not implicitly adopted. The planned read-only command is:

```text
python3 <worktree>/scripts/validate-test-design.py --test-root <resolved-root> --format json
```

It must not execute commands, import project code or access the network. Until
M1 implements and integration connects it, this is an interface reservation,
not a command users must run.

| Field | Frozen minimum type |
|---|---|
| `case_id` / `revision` | Nonempty string / integer >= 1 |
| `requirements` | Nonempty list of Reference |
| `features` / `entries` | Nonempty lists of nonempty strings referring to map IDs |
| `risk` | Object with nonempty `failure` string and `priority`: low / medium / high |
| `preconditions` / `actions` / `evidence_required` | Nonempty lists of nonempty strings |
| `input_fixture` / `oracle_ref` / `runner_ref` / `environment_ref` / `cleanup_ref` | Reference |
| `expected` | Nonempty list of objects with nonempty `observe` and `relation` strings; optional `value` (any JSON), `oracle_ref` (Reference overriding the case oracle) |

Reference is either a nonempty locator string or an object with
`status: unresolved | not_applicable` and a nonempty `reason`. Explicit gaps or
inapplicability are structurally allowed and never imply semantic acceptance.
`test-root:` denotes a checkable file within TEST_ROOT; other locators are not
automatically read, and unknown resolvability is a warning. Native tests use
file/selector locators; precise commands remain in tools/recipes. Describing an
expected relation does not mean the checker evaluates that relation.

The minimum JSON output contract is:

```json
{"schema_version":1,"scope":"design_structure","status":"not_adopted","errors":[],"warnings":[],"case_ids":[]}
```

Status is `not_adopted | valid | invalid`. Exit 0 means valid structure or no
adoption (inspect status); exit 1 means invalid contract structure; exit 2 means
an operational file/argument error. `valid` proves neither oracle correctness,
executability nor product success. External-reference failures and unknown
business semantics remain distinct. M2/M3/M5 must consume M1's parser rather
than adding their own case parser.

## Decision: Operation Recipe Interface (M3)

A named recipe in `env-config.md` uses these sections:

`Purpose / Capability and tool choice / Preconditions / Launch / Doctor /
Drive and Wait / Observe and Evidence / Failure and Recovery / Cleanup /
Proof status`.

A case adopts a recipe using only:

```text
environment_ref: "test-root:env-config.md#OP-NOTES-WEB"
```

The target section contains `<a id="OP-NOTES-WEB"></a>`, the heading
`### OP-NOTES-WEB`, and `recipe_revision: 1`. No new `recipe_ref` field is added.
General environment references can target their own anchors; recipe adoption
must target the recipe anchor, not the entire file. `runner_ref` identifies the
actual test entry and remains distinct from environment/operation instructions.
Old free-text cases may use the same recipe reference.

Every operation identifies its target, owner, side-effect scope, completion
condition and bounded wait. Lost non-idempotent responses require reconciliation
before retry. Init reads and creates knowledge only: no launch, testing, pilot
or dependency installation, including indirect helper calls. Pilot/self-check
belongs to an explicit execution phase. M3 does not introduce a universal
runtime, driver SDK, lease service or lifecycle results protocol.

## Decision: Four Independent Facts

Case design, structural checking, execution in a specific environment, and
ability to detect a specified fault are independent facts. Store case-side
statements in `test-groups.md` and recipe-side statements in `Proof status`.
The following is notation, not an actual run:

```text
Scope: case J-02 revision 1; recipe OP-JOBS revision 1
Design: AUTHORED; unresolved: none / specific reason
Structure: NOT_CHECKED / reference to checker output (structure only)
Execution proof: NOT_RUN / existing run artifact + subject/environment + revisions
Detection proof: NOT_RUN / faulty run + correct-control run + fault and predicate
Current review: current-within-proof-scope / required: changed source and affected refs
```

Use real artifact locators before claiming proof. Current proof requires matching
versions, environments and entries. Historical proof is preserved when review
becomes required. A recipe pilot is not case fault-detection proof; if detection
is not applicable at recipe level, say so and refer to the case. Reviewer
agreement does not upgrade evidence strength. These labels never become
`results.status`; knowledge changes do not rewrite historical runs.

## Decision: Ownership and Integration

Whole-file owners prevent simultaneous workflow edits:

| Owner | Files |
|---|---|
| M6 | `SKILL.md`, `references/templates.md`, README (both languages), CHANGELOG, CI, `scripts/test-all.sh`, `hooks/test-resource-links.sh`; ADR and integration handoff |
| M1 | Case contract/schema/checker, BDD procedure, design fixtures/tests/handoff |
| M2 | `references/init-workflow.md`, `references/strategy-workflow.md`, `references/procedures/exploratory-charter.md`; coverage fixtures/handoff |
| M3 | `references/test-execution-workflow.md`; operation procedure, platform guide, isolated fixtures/tests/handoff |
| M4 | `references/team-role-presets.md`, `references/l2-audit-prompts.md`; review fixtures/handoff |
| M5 | `references/update-workflow.md`, `references/reflect-workflow.md`, `references/feedback-workflow.md`; maintenance fixtures/handoff |

Ownership changes go through the integration owner. From C0, modules deliver
own-file methods and tests. Missing dependency loads, checker calls and template
insertions go in `docs/upgrade-handoffs/pstack/<module>.md`, with target file,
section, content and acceptance scenario. No dangling runtime links or fake
stubs are added. Once actual dependencies form I0, each file owner connects and
rechecks their files. Handoffs and public development inputs are governance
material, not another runtime configuration.

## Decision: Resource Integrity

`hooks/test-resource-links.sh` checks canonical skill-root `references/*.md`
locators found in SKILL, README (both languages) and reference Markdown files,
including nested directories. A qualified path inside another skill or a URL
is outside this graph, including its query/fragment contents. Complete locator
tokens are classified before extracting local paths; local anchors/queries do
not create additional edges. Referenced local documents must exist; actual
procedure files must be referenced and reachable from SKILL/README through document edges.
Self links, isolated cycles and links only from disconnected workflows fail.
The old fixed count of 17 is removed; split top-level `procedures/` stays invalid.
Tables and code spans can carry static locators. Relative Markdown links without
the canonical `references/` prefix are outside this specific check. Static
reachability is discoverability only, not proof the Agent follows instructions.

## Preserved Boundaries and Consequences

Retain TEST_ROOT resolution, tester/run isolation, intake, typed identity,
evidence levels, existing hard gates, v3/v4 dual writes and semantic diff, and
one `FULL-TEST-REPORT.md`. `input_refs.strategy` remains machine strategy JSON,
not `strategy-plan.md`; `provider_metadata` cannot host authoritative new gates.
Do not change results schemas, `hybrid_core.py`, `validate-run.py` verdicts,
Agent evals core, or real business data. Do not introduce a persistent case or
feature database, run ledger, or second formal report.

Module checks are not integration or Agent trial proof; eight-platform method
coverage is not eight-platform execution. The installed checkout/link, push,
main merge and release are outside this development stage. Results protocol
bindings require a separate later decision.

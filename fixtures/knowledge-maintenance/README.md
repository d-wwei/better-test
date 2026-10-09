# M5 maintenance fixtures

Status: AUTHORED. Agent update semantic exercise, actual product execution,
M1 checker integration and long-term maintenance effect: **NOT_RUN**.
Every source and historical artifact here is synthetic input, never real proof.
There is no runnable product, native test or installed tool in these fixtures.

Each directory has frozen `before/`, `source-before.txt`, `source-after.txt`,
`source.diff` and one reasonable authored `after/`. `manifest.json` stores original
SHA-256s and the sample's change scope. It is an isolated fixture manifest, not a
project freshness registry. History bytes are identical across snapshots.

| Scenario | Oracle / expected | Case | Recipe | Next execution |
|---|---|---|---|---|
| semantic-change | AC-TITLE rev 2 explicitly trims; add empty-after-trim rejection, retain body/count invariants | U-01 rev 2; same ID; affected entries/state map updated | Unchanged | Both entries and rejection boundary; current proof NOT_RUN |
| pure-refactor | Original bytes preserved; no contract change established | U-01 rev 1 unchanged; update impact reference/strategy only | Unchanged | Directed regression; unknown reachability expands investigation |
| tool-change | Original contract and expected preserved | U-01 contract rev 1 unchanged; knowledge-side proof scope/review updated | OP-NOTES-WEB rev 2, selector replaced | Explicit representative pilot, evidence survival and related regression; not a product Bug from selector error alone |

Run from this worktree:

```sh
python3 fixtures/knowledge-maintenance/check-fixtures.py
```

Seven checks cover original hashes, source diff correspondence, edit scope,
historical preservation and temporary mutations: rewriting before, deleting
source, rewriting case after refactor, rewriting oracle for a tool-only change,
rewriting history and adding a registry. They do not parse case contracts,
validate natural-language expectations, run an Agent or prove drift attribution.
Use the actual M1 checker only after I0 integrates it; runner/cleanup are honestly
unresolved rather than fake runnable paths.

For M6's semantic exercise, copy `before/` to an isolated scratch TEST_ROOT.
Provide frozen sources/diff to a new Agent using the worktree Skill update flow;
never let it edit the authored snapshots or installed checkout. Record complete
calls, actual changed files and before/source/history hashes in the existing
experiment records. Compare behavior with the table, allowing equivalent wording
and justified extra review notes. Exact after text is not the semantic oracle.
A static green suite is not an Agent exercise result.

Additional held-out review scenarios (AUTHORED, NOT_RUN):

| Input | Semantic acceptance |
|---|---|
| Reference output changes without a requirement revision | Preserve expected, record oracle conflict/source versions, investigate; no automatic golden refresh |
| Same source on an unexecuted new platform build | Keep old platform history; new platform Execution/Detection proof remains NOT_RUN |
| Historical feedback lacks exact input/environment/raw effect | Candidate obligation, missing materials, reliability and owner; no confirmed/reproduced case or suppress |
| “False positive” feedback conflicts with independently observed forbidden persistence | Preserve product finding and raw evidence; investigate attribution; no ignore or weakened assertion |
| New shortcut/state/reader permission entry | Propagate entry/role/state → case preconditions/actions → recipe/coverage gaps; do not infer coverage from button pass |

These additional rows are review prompts, not completed trial cases or new runtime
registrations. The three full snapshots are the minimal required before/after set.

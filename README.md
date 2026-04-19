**🇺🇸 English** | **[🇨🇳 中文](README.zh-CN.md)**

# better-test

### Run the right tests after each change — and remember what you've already triaged.

`better-test` is a Claude Code skill that builds a persistent test knowledge base for your project: which tests are grouped how, which tests are known to fail and why, and which changed files should trigger which groups. Your AI agent reads the knowledge before suggesting a test run — so instead of "run everything" or "run smoke," you get a small, reasoned test set plus the reason it was selected.

It also captures developer feedback on bug reports (6 verdicts) and auto-refines them into suppress rules, so you don't keep re-filing the same issue that engineering already closed.

Works natively on Claude Code. Ships with adapters for Cursor, Gemini CLI, Codex, OpenCode, and OpenClaw. Part of the [Better-Work series](https://github.com/d-wwei/better-work-skill). Installs and runs standalone.

## Why This?

Running the full test matrix is what CI is for. Local iteration needs something else: a small, change-aware test run that your team's accumulated knowledge actually informs.

Your team knows things that CI doesn't. "The WebSocket tests only matter when subscribe.rs changed." "That flaky one in the auth group — dev says it's a test bug, ignore it." "Last release we missed the keychain regression because nobody ran group H — check that this time."

This knowledge evaporates between sessions. It lives in Slack threads, half-remembered by whichever engineer cut the last release. A new contributor running tests for the first time has to re-learn everything by trial and error.

`better-test` captures it. Three files do the work:

- **`test-groups.md`** — how tests are grouped, what each group covers, what it needs to run
- **`impact-map.md`** — mapping from changed files / keywords to the test groups they affect
- **`known-issues.md`** — what's already known to fail, why, and the developer's verdict

Plus a feedback loop: when a developer responds to a bug report with "not-a-bug" or "wontfix" or "fixed-differently," `/better-test feedback` turns that verdict into a suppress rule. Next strategy recommendation quietly excludes the triaged item. You don't re-file the same bug three times.

## Installation

### Claude Code (native)

```bash
git clone https://github.com/d-wwei/better-test.git ~/repos/better-test
ln -s ~/repos/better-test ~/.claude/skills/better-test
```

`better-test` appears in the skill list on the next Claude Code session.

### Other platforms

`references/adapters.md` has copy-paste install commands for Cursor, Gemini CLI, Codex, OpenCode, and OpenClaw. The test knowledge files produced by `/better-test init` are platform-agnostic.

## Quick Start

Inside a project directory (works best if you've already run `/better-code init`, so `.better-work/shared/` exists):

```
/better-test init
```

The skill classifies the testing situation (library / daemon / API / CLI / multi-service), explores the existing test structure, and writes:

- `.better-work/test/protocol.md` — ≤15 lines of testing cognitive constraints
- `.better-work/test/test-groups.md` — test group definitions with run conditions
- `.better-work/test/impact-map.md` — changed-file patterns → test groups
- `.better-work/test/known-issues.md` — known failures + verdicts

Once initialized, the typical loop looks like this:

```
# After making code changes:
/better-test strategy
  → reads impact-map.md + known-issues.md + your git diff
  → recommends: "Run groups A, B, D — total 23 tests, ~5 min"
  → explains why: "Changed src/subscribe.rs touches the subscription flow (group D)..."

# After running tests, if a test fails:
/better-test feedback D-04 not-a-bug --note "dev confirmed — cancel is expected to return 404 here"
  → writes the verdict to history/
  → extracts a suppress rule into feedback-rules.json
  → next /better-test strategy automatically excludes D-04
```

## Command Reference

| Command | What it does |
|---------|--------------|
| `/better-test init` | First-time exploration of the test structure + generate knowledge files |
| `/better-test update` | Signal-driven incremental update (new tests, new bugs, new groups, new conventions) |
| `/better-test strategy` | Analyze the current git diff + impact-map → recommend a minimal test set with reasoning |
| `/better-test feedback <id> <verdict> [--note "..."]` | Record a developer verdict on a bug report; auto-refine into suppress rules |
| `/better-test checkpoint` | Save current test task state to `progress.md` |
| `/better-test resume` | Read `progress.md` and continue from the checkpointed state |

### The six feedback verdicts

| Verdict | Meaning | Effect on future `strategy` runs |
|---------|---------|----------------------------------|
| `not-a-bug` | Developer confirms this is expected behavior | Excluded from active failures |
| `fixed` | Addressed in this release | Re-tested once to confirm; then archived |
| `fixed-differently` | Fixed but not how you expected | Re-tested with new expected output |
| `wontfix` | Acknowledged, won't be addressed | Excluded permanently with a note |
| `deferred` | Known issue, postponed to a later release | Excluded until the target version |
| `revoke` | Retract a previous verdict (the situation changed) | Re-activates the test ID |

All six commands work identically whether invoked directly, or via `/better-work test <cmd>` when `better-work` is installed.

### Example strategy output

After modifying `src/rest/funds.rs` and `src/auth/session.rs`, running `/better-test strategy` returns something like this:

```
Recommended: groups A (auth), B (REST read), C (REST POST)
  — 22 tests, ~8 minutes, bring-your-own mode

Reasoning:
  • src/auth/session.rs matches impact-map keyword "auth" → group A (9 items)
  • src/rest/funds.rs matches "REST" → groups B, C (5 + 8 items)

Skipping: groups D, E, F, H, I (no change signal)
Excluded: C-03 (wontfix, deferred to v1.5), B-07 (not-a-bug from 2026-03-12)

Run with: cargo test -- --test-groups A,B,C
```

The reasoning is auditable: every recommended group points to its impact-map entry, and every excluded item points to its feedback verdict. You can override anything before running.

## Output Structure

Test knowledge lives under `.better-work/test/` (which itself is a symlink to `~/.better-work/<project>/test/`):

```
<project>/.better-work/                      → ~/.better-work/<project-name>/
├── shared/                                  (read by better-test; written only when needed, tagged [better-test])
│   └── index.md                             project entry point
├── code/                                    (read-only for better-test; informs test priority)
│   └── danger-zones.md                      high-risk files → more thorough tests
└── test/                                    (better-test writes here)
    ├── protocol.md                          ≤15 lines — testing cognitive constraints
    ├── test-groups.md                       group definitions + run conditions
    ├── impact-map.md                        change keyword → affected groups
    ├── known-issues.md                      known failures / expected behaviors / triage
    ├── status.md                            auto-refreshed summary: current version, active fails, suppressed
    ├── progress.md                          gitignored — current test-task state
    └── history/                             test run history, git-tracked
        ├── _meta.json
        ├── feedback-rules.json              auto-maintained, do not hand-edit
        └── <version>/
            ├── run-NNN-<ts>/                results.json + summary.md per run
            └── feedback/<test_id>_<verdict>.md
```

### Why `status.md` is auto-generated

After every `strategy` / `update` / `feedback`, `better-test` refreshes `status.md` with:

- Current project version under test
- Count of active failures (excluding triaged)
- Suppressed items with verdicts
- Latest test run summary

Loading `status.md` on a new session gives the agent an immediate situation report — no need to walk through `history/` or re-run anything.

### Design decisions

| Choice | Why |
|--------|-----|
| Test history is per-version + git-tracked | So "we tried that in v1.4.3" survives between engineers and releases |
| `feedback-rules.json` is auto-generated, never hand-edited | Hand-edits break the automation that keeps suppress rules consistent |
| `test-groups.md` mandates "run conditions" + "how to run" | A group without prerequisites or invocation is unusable; forcing these at write time prevents silent gaps |
| `impact-map.md` entries need a verification source | Otherwise the map is a pile of guesses; verified entries vs inferred vs `[未验证]` is tracked explicitly |
| Pass must verify returned fields, not exit codes | A daemon returning an empty list has exit 0 — if "exit 0 = pass" you've just greenlit a broken API |

## Where better-test Fits in the Better-Work Series

`better-test` is the testing-discipline subskill in the [Better-Work series](https://github.com/d-wwei/better-work-skill). The series is a family of AI-agent skills that share one project knowledge tree:

- `better-work` — series entry point, project init, generic execution protocol
- `better-code` — coding knowledge and constraints ([better-code](https://github.com/d-wwei/better-code))
- `better-test` — this repo; testing knowledge and constraints
- `better-plan` / `better-design` / `better-write` — forthcoming

`better-test` reads `shared/index.md` (project identity) and `code/danger-zones.md` (high-risk files → more thorough tests) from whatever other subskills populated them. It writes only to `test/` and, when necessary, to `shared/` with a `[better-test]` commit tag.

Installing `better-work` enables `/better-work test <cmd>` as an alias. Without `better-work`, `/better-test` still works standalone.

## Interface Contract

Every Better-Work subskill exposes these four standard commands:

| Command | Guarantee |
|---------|-----------|
| `init` | Idempotent first-time setup; never overwrites existing files without `--force` |
| `update` | Incremental; preserves unrelated content |
| `checkpoint` | Writes `shared/progress.md` in a format the next session can parse |
| `resume` | Reads `progress.md`, reports test-ID-level / group-level status — no "almost done" |

`better-test` adds two discipline-specific commands: `strategy` and `feedback`. When invoked via `/better-work test`, better-work forwards arguments unchanged — no inspection.

## Limitations

- **No test runner built in.** `better-test` recommends which tests to run and why, but running them is your project's existing test tooling (cargo test / pytest / go test / custom harness). `better-test` reads the results afterward via `results.json`.
- **`impact-map.md` accuracy depends on you.** Initial entries are seeded from keywords; true accuracy grows as `/better-test feedback` and `/better-test update` refine the mappings. A brand-new `impact-map.md` may over- or under-recommend.
- **`feedback-rules.json` is auto-generated — do NOT hand-edit.** If you need to override a rule, use `/better-test feedback <id> revoke` to retract, then re-enter with a fresh verdict.
- **`strategy` does not run tests.** It returns the test set + invocation command. You run the tests, then feed results back via `/better-test feedback` or save `results.json` into `history/`.
- **No CI integration yet.** Integration with GitHub Actions / GitLab CI is planned but not implemented.
- **`protocol.md` enforcement is advisory.** The red lines ("pass must verify fields, not exit codes") live in the skill's knowledge and guide the agent, but can't prevent you from writing a bad test — they surface the bad test in review, not at the harness layer.

## License

MIT License.

---

Questions, issues, or discussion: [GitHub issues](https://github.com/d-wwei/better-test/issues).

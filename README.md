**🇺🇸 English** | **[🇨🇳 中文](README.zh-CN.md)**

# better-test

### Failure mode #4: "Didn't run the right tests." This repo solves that one.

Of the five ways AI coding agents fail on 100k-line codebases, this one is the most under-fixed:

> Didn't run the right tests — ran the unit tests, missed the integration tests.

It's not an attitude problem. The agent doesn't know which tests cover which changes. It doesn't know which tests are already failing for known reasons. It doesn't know the test you care about needs a real account to run.

This knowledge lives in Slack threads, in the release engineer's head, in postmortems nobody re-reads. It evaporates between sessions.

`better-test` captures it — the testing half of a [Full Context + Lite Control](https://github.com/d-wwei/better-work-skill) framework. A persistent test playbook plus a developer-feedback loop that stops you from re-filing the same closed bug three times.

## What this repo knows that your agent doesn't

Your team has knowledge CI doesn't capture:

- "The WebSocket tests only matter when `subscribe.rs` changed."
- "That flaky one in the auth group — dev says it's a test bug, ignore it."
- "Last release we missed the keychain regression because nobody ran group H. Don't miss it again."

Three files hold this:

| File | What it contains |
|------|------------------|
| `test-groups.md` | How tests are grouped, what each covers, what each needs to run |
| `impact-map.md` | Changed files / keywords → the test groups they affect |
| `known-issues.md` | What's already known to fail, why, and the developer's verdict |

When you change code and run `/better-test strategy`, the skill reads all three plus your `git diff`, then recommends a minimal test set with reasoning. You see exactly why groups A, B, D were picked — and which already-triaged items were excluded.

## The feedback loop

Most testing skills stop at "run these tests." `better-test` also asks: what did the developer say about the last failure?

When a bug report gets a developer response — "that's expected behavior," "fixed in a different way," "won't fix" — you feed it back:

```
/better-test feedback D-04 not-a-bug --note "dev confirmed — cancel returning 404 is expected"
```

The skill writes the verdict to `history/`, extracts a suppress rule into `feedback-rules.json`, and the next `/better-test strategy` run quietly excludes D-04. You don't re-file the same bug three times.

Six verdict types:

| Verdict | Meaning | Effect |
|---------|---------|--------|
| `not-a-bug` | Developer confirms expected behavior | Excluded from active failures |
| `fixed` | Addressed in this release | Re-tested once, then archived |
| `fixed-differently` | Fixed but not how you expected | Re-tested with new expected output |
| `wontfix` | Acknowledged, won't address | Excluded permanently with a note |
| `deferred` | Known issue, postponed | Excluded until the target version |
| `revoke` | Retract a previous verdict | Re-activates the test ID |

## Installation

### Claude Code (native)

```bash
git clone https://github.com/d-wwei/better-test.git ~/repos/better-test
ln -s ~/repos/better-test ~/.claude/skills/better-test
```

### Other platforms

Adapter install commands for Cursor, Gemini CLI, Codex, OpenCode, and OpenClaw live in `references/adapters.md`. Test knowledge files produced by `/better-test init` are platform-agnostic.

## Quick Start

Inside a project directory (works best if `/better-code init` has already been run, so `.better-work/shared/` exists):

```
/better-test init
```

The skill classifies the testing situation (library / daemon / API / CLI / multi-service), explores the existing test structure, and writes:

- `.better-work/test/protocol.md` — testing cognitive constraints
- `.better-work/test/test-groups.md` — test group definitions with run conditions
- `.better-work/test/impact-map.md` — changed-file patterns → test groups
- `.better-work/test/known-issues.md` — known failures + verdicts

Then the typical loop:

```
# After making code changes:
/better-test strategy
  → reads impact-map.md + known-issues.md + your git diff
  → recommends: "Run groups A, B, D — 22 tests, ~5 min"
  → explains why: "Changed src/subscribe.rs touches the subscription flow (group D)..."

# If a test fails and the dev responds:
/better-test feedback D-04 not-a-bug --note "dev confirmed expected behavior"
  → writes verdict to history/
  → extracts a suppress rule
  → next strategy auto-excludes D-04
```

## Example strategy output

After modifying `src/rest/funds.rs` and `src/auth/session.rs`:

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

Every recommendation points to its impact-map entry. Every exclusion points to its feedback verdict. The reasoning is auditable; you can override anything before running.

## Command Reference

| Command | What it does |
|---------|--------------|
| `/better-test init` | First-time exploration of the test structure + generate knowledge files |
| `/better-test update` | Signal-driven incremental update |
| `/better-test strategy` | Analyze git diff + impact-map → recommend minimal test set with reasoning |
| `/better-test feedback <id> <verdict>` | Record developer verdict → auto-refine suppress rules |
| `/better-test checkpoint` | Save current test task state |
| `/better-test resume` | Read progress and continue |

All six work identically whether invoked directly or via `/better-work test <cmd>` (when better-work is installed).

## Output Structure

Test knowledge lives under `.better-work/test/` (a symlink to `~/.better-work/<project>/test/`):

```
<project>/.better-work/                      → ~/.better-work/<project-name>/
├── shared/                                  (read; written only when needed, tagged [better-test])
│   └── index.md                             project entry point
├── code/                                    (read-only; informs test priority)
│   └── danger-zones.md                      high-risk files → more thorough tests
└── test/                                    (better-test writes here)
    ├── protocol.md                          ≤15 lines — testing cognitive constraints
    ├── test-groups.md                       group definitions + run conditions
    ├── impact-map.md                        change keyword → affected groups
    ├── known-issues.md                      known failures / expected behaviors / triage
    ├── status.md                            auto-refreshed summary
    ├── progress.md                          gitignored — current test task state
    └── history/                             test run history, git-tracked
        ├── feedback-rules.json              auto-maintained, do not hand-edit
        └── <version>/
            └── run-NNN-<ts>/                results.json + summary.md per run
```

### One non-obvious rule

**Pass must verify returned fields, not exit codes.** A daemon that returns an empty list has exit code 0 — if "exit 0 = pass" you've just greenlit a broken API. `protocol.md` enforces this as a red line. It's advisory (better-test can't run your tests for you), but it surfaces the bad test at review time.

## The Better-Work series

- **[better-work-skill](https://github.com/d-wwei/better-work-skill)** — Lite Control + series entry point. Start there for the full design story.
- **[better-code](https://github.com/d-wwei/better-code)** — Full Context for coding
- **better-test** (this repo) — Full Context for testing

`better-test` reads from `shared/index.md` (project identity) and `code/danger-zones.md` (high-risk files → more thorough tests) when other subskills have populated them. It writes only to `test/` and, when necessary, to `shared/` with a `[better-test]` commit tag.

## Limitations

- **No test runner built in.** `better-test` recommends which tests to run and why. Actually running them is your project's existing tooling (`cargo test` / `pytest` / `go test` / custom harness). Feed `results.json` back via `/better-test feedback` or save into `history/`.
- **`impact-map.md` accuracy depends on feedback.** Initial entries are seeded from keywords. True accuracy grows as `/better-test feedback` and `/better-test update` refine the mappings.
- **`feedback-rules.json` is auto-generated.** Do NOT hand-edit. Use `/better-test feedback <id> revoke` to retract, then re-enter with a fresh verdict.
- **`strategy` doesn't run tests.** It returns the test set + invocation command. You run them.
- **No CI integration yet.** GitHub Actions / GitLab CI integration is planned.
- **`protocol.md` enforcement is advisory.** Can't prevent you from writing a bad test; can only flag it at review time.

## License

MIT.

---

Companion write-up: the full [Full Context, Lite Control](https://github.com/d-wwei/better-work-skill) story lives in the series entry-point README.

Questions, issues, discussion: [GitHub issues](https://github.com/d-wwei/better-test/issues).

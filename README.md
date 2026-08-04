**English** | **[中文](README.zh-CN.md)**

# better-test

### Failure mode #4: "Didn't run the right tests." This repo solves that one.

Of the five ways AI coding agents fail on 100k-line codebases, this one is the most under-fixed:

> Didn't run the right tests — ran the unit tests, missed the integration tests.

The agent doesn't know which tests cover which changes. It doesn't know which tests are already failing for known reasons. It doesn't know the test you care about needs a real account to run.

`better-test` captures this knowledge — the testing half of a [Full Context + Proportional Control](https://github.com/d-wwei/better-work) framework. Persistent test playbook, developer-feedback loops, experience extraction, and a 4-layer constraint framework that prevents the agent from cutting corners.

## What's new in v3.x

v3.0: Multi-agent parallel testing + tester/coordinator two-role architecture.
v3.1: Hook enforcement, protocol split, skill upgrade pipeline.
v3.1.2: Extensible team-role presets for multi-tester planning and merge.
v3.2: Strict results/gate/DoD validation, independently auditable evidence, complete Tier-2 resources, and deterministic CI.
v4: Objective- and capability-driven black-box/white-box/hybrid strategy, versioned Provider
contracts, typed evidence, seven coverage lanes, lossless legacy projection, and safe v3/v4
dual-write migration. Projects graduate from shadow to default through their own audited window.

Key capabilities:

- **8 L1 hooks + gate.sh universal entry** — credential scan, derived-view guard, session isolation, execution logging, post-test checklist, results validation. gate.sh auto-detects better-test projects from global config (no per-project setup)
- **Protocol split** — `protocol-base.md` (skill-level, auto-propagates) + project `protocol.md` (safety + project discipline). Skill upgrades reach all projects automatically
- **Tester isolation** — parallel agents write to separate `run-<tester-id>-NNN/` directories. `/better-test merge` produces unified results
- **Extensible team-role presets** — stable role schema, replaceable presets (`release-4way`, `api-3way`, `single-plus-l2`, custom)
- **4-layer constraint framework** (L0 goal calibration, L1 hooks, L2 independent sub-agent verification, L3 human audit panel)
- **49 field-tested lessons** distilled from multiple real-world testing campaigns
- **Skill upgrade pipeline** — medium-risk lessons are reviewed in-session and promoted atomically; only deferred or high-risk changes enter `pending-skill-upgrades.md`
- **Experience extraction** (`/better-test reflect`) — learns from test history
- **Differential testing** (`compare` mode) — test a Rust rewrite against the C++ original
- **Capability-driven hybrid testing** — resolves objective plus observed source/build/artifact/runtime
  capability into black-box, white-box, or hybrid execution; errors and unknown impact expand the
  safe black-box set instead of weakening it
- **Generic/project layer separation** — Better Test owns contracts, resolution, and a neutral
  Rust/Cargo Provider; each project owns its package/risk/test-group/gate/ledger/history knowledge
- **Results v4 default with v3 compatibility** — typed v4 subjects and relations, strict validation,
  atomic dual-write and semantic diff; v3 stays supported until an explicit retirement approval,
  and source-only checks cannot become runtime or release evidence
- **Lossless v4 multi-tester merge** — immutable source hashes plus exact typed subject, relation,
  item/evidence, gate, caveat and readiness occurrences; v3 merge remains compatibility-only
- **Dedicated real-account automation** — `dedicated-real-test` +
  `standing-all-actions` treats login, unlock, order, modify, cancel,
  cancel-all, and cleanup as standing account-level authorization with no
  per-action, per-run, or per-session prompt; persistent sessions are reused
  and trading-account identifiers are discovered automatically
- **First-party user-path evidence** — the agent launches and validates the
  product through its normal GUI, official CLI, or official configuration;
  credential brokers and wrappers stay internal and never become a second
  user login flow or substitute product evidence
- **One-file developer handoff** — each run/merge produces one validated
  `FULL-TEST-REPORT.md` containing the conclusion, audits, complete machine
  ledger, and every full 8-section Bug Report with metadata; summaries or
  links cannot substitute for the Bug Report body
- **Bug lifecycle management** — OPEN → CONFIRMED → FIXED → VERIFIED → CLOSED

## How it works

Three knowledge files capture what your team knows but CI doesn't:

| File | What it contains |
|------|------------------|
| `test-groups.md` | How tests are grouped, what each covers, run commands, assertions, stability scores |
| `impact-map.md` | Changed files / keywords → the test groups they affect (with evidence grading) |
| `known-issues.md` | Known failures, developer verdicts, flaky tests with stability scores, lessons learned |

When you change code:

```
/better-test strategy
  → reads impact-map + known-issues + bugs-index + your git diff
  → recommends: "Run groups A, B, D — 22 tests, ~8 min"
  → explains: "src/auth/session.rs matches impact-map 'auth' → group A"
  → checks: credentials ready? batch size ok? pyramid structure healthy?

# Execute with per-project plan:
  → generates execution plan from test-groups + known-issues + protocol
  → four-color marking: pass/pending/fail/skip with evidence grading
  → incremental reflect after completion: validates mappings, updates scores

# If a test fails and the dev responds:
/better-test feedback D-04 not-a-bug --note "dev confirmed expected behavior"
  → writes verdict to history/ + extracts suppress rule
  → next strategy auto-excludes D-04
```

## The feedback loop

Most testing skills stop at "run these tests." `better-test` builds a compounding knowledge base:

```
init → strategy → execute → reflect → feedback → update → strategy (smarter)
  ↑                                                                      ↓
  └──────────────── knowledge files get more accurate over time ←────────┘
```

Every test run makes the next one better: impact-map mappings get verified, stability scores get calibrated, timing estimates get corrected, lessons get extracted.

## Constraint framework

The agent's quality is ensured by 4 layers, each catching what the previous misses:

| Layer | Mechanism | What it catches |
|-------|-----------|-----------------|
| L0 Goal calibration | Protocol.md reframes agent as "test auditor, not test-pass assistant" | Training bias toward optimistic/complete/certain answers |
| L1 Hooks | 8 system-level hooks (credential scan, write guards, execution logging, result validation, registration...) | Mechanical errors the agent might forget to check |
| L2 Independent verification | Sub-agent audits execution log vs claims, coverage vs manifest, evidence quality | Cognitive errors: skipped steps, false passes, insufficient evidence |
| L3 Human audit panel | 20-line decision-oriented summary assembled from structured data | Final judgment on ambiguous items; 30-second approve/reject |

## Installation

### All platforms (auto-detect)

```bash
git clone https://github.com/d-wwei/better-test.git ~/src/better-test
cd ~/src/better-test
./install.sh            # detects Claude Code, Codex, etc. and creates symlinks
./install.sh status     # verify canonical path, Git revision, and symlink state
```

Keep this as the single canonical Git checkout. Claude and Codex must load the same source through symlinks;
do not copy the repository into multiple skill directories. The installer never overwrites an existing real
directory: back it up or migrate it first, then rerun installation.

Runtime validation requires Bash, `jq`, and Python 3. The authenticated Codex smoke test also requires a
logged-in `codex` CLI.

### Claude Code (manual)

```bash
ln -s ~/src/better-test ~/.claude/skills/better-test
```

### Codex CLI (manual)

```bash
ln -s ~/src/better-test ~/.codex/skills/better-test
```

Codex invokes the skill with `$better-test` (instead of `/better-test`). The SKILL.md format is natively compatible — no conversion needed.

### Other platforms

Cursor, Gemini CLI, OpenCode, and OpenClaw adapter instructions live in `references/adapters.md`. Test knowledge files are platform-agnostic.

## Quick Start

```
/better-test init
```

The skill classifies the project (11 types: library, daemon, API, CLI, mobile app, desktop app, browser extension, etc.), collects materials (API specs, PRD, error code tables), explores test structure, and generates knowledge files.

## Command Reference

| Command | What it does |
|---------|--------------|
| `/better-test init` | Explore test structure + collect materials + generate knowledge files |
| `/better-test strategy` | Analyze changes → recommend test set with reasoning. Includes `compare` mode for differential testing |
| `/better-test feedback <id> <verdict>` | Record developer verdict → auto-refine suppress rules + regression canary |
| `/better-test update` | Signal-driven incremental update (new tests, new mappings, new materials from user) |
| `/better-test reflect [scope]` | Extract experience from history: impact-map validation, stability trends, bug hotspots, lessons |
| `/better-test protocol-update [text]` | Upgrade cognitive constraints from user input or session summary |
| `/better-test merge` | Merge results from multiple testers — interactive run selection, conflict detection, one self-contained developer report |
| `/better-test checkpoint` | Save current test task state |
| `/better-test resume` | Read progress and continue |

All commands work identically via `/better-work test <cmd>` when better-work is installed.

## Architecture

```
references/
├── Tier 1: Workflows (always loaded per command)
│   ├── init-workflow.md              exploration + material collection + code reading
│   ├── strategy-workflow.md          change detection + impact analysis + decision tree + compare mode
│   ├── team-role-presets.md          extensible team schema + preset library + coordinator protocol
│   ├── test-execution-workflow.md    framework + template for per-project execution plans
│   ├── feedback-workflow.md          verdict recording + rule extraction + regression canary
│   ├── reflect-workflow.md           6-type historical analysis (incremental + full)
│   ├── update-workflow.md            6 signal types including new user materials
│   ├── protocol-update-workflow.md   cognitive constraint upgrade + changelog
│   └── progress-workflow.md          checkpoint / resume
│
├── Tier 2: Procedures (condition-triggered)
│   ├── procedures/bdd-scenarios.md         when PRD is provided
│   ├── procedures/tdd-flow.md              when writing new code
│   ├── procedures/contract-testing.md      when multiple services interact
│   ├── procedures/exploratory-charter.md   when deep testing requested
│   ├── procedures/hypothesis-investigation.md   when error diagnosis needs escalation
│   ├── procedures/mutation-testing.md      when code changes in full/targeted mode
│   ├── procedures/flakiness-scoring.md     when flaky signal detected
│   ├── procedures/bug-report.md            when bug found during testing
│   ├── procedures/longrun-testing.md       for 24h+ stability testing
│   └── procedures/combinatorial-testing.md for pairwise/equivalence coverage
│
└── Tier 3: Design docs (human reference, agent doesn't load)
    └── methodologies/design-rationale.md   all research citations + design reasoning
```

## The Better-Work series

- **[better-work](https://github.com/d-wwei/better-work)** — Lite Control + series entry point
- **[better-code](https://github.com/d-wwei/better-code)** — Full Context for coding
- **better-test** (this repo) — Full Context for testing

## Limitations

- **No test runner built in.** Recommends which tests to run and why. Running them is your project's tooling.
- **`impact-map.md` accuracy grows over time.** Initial entries are seeded from keywords; `/better-test reflect` validates and upgrades them from test history.
- **`feedback-rules.json` is auto-generated.** Do NOT hand-edit. Use `feedback <id> revoke` to retract.
- **Hooks require platform installation.** Claude Code uses `gate.sh`; Codex uses project `.codex/hooks.json`. See `hooks/README.md` and `references/adapters.md`.
- **CI covers deterministic checks.** Authenticated Codex runtime smoke remains a manual release gate because it calls the live CLI/model.

## License

MIT.

---

Companion write-up: the full [Full Context, Proportional Control](https://github.com/d-wwei/better-work) story lives in the series entry-point README.

Questions, issues, discussion: [GitHub issues](https://github.com/d-wwei/better-test/issues).

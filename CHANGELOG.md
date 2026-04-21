# Changelog

All notable changes to **better-test** (Better-Work series testing subskill) are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this project uses [Semantic Versioning](https://semver.org/).

## [2.0.5] - 2026-04-20

Extracted generalizable testing patterns from futu-rust-opend-tester battle experience (v1.4.26-v1.4.45).

### Added

- `surface-manifest.md` as first-class output file: enumeration of all testable interfaces (REST/CLI/MCP/WS) as coverage denominator SSOT. Conditional generation for API/CLI/daemon projects (`SKILL.md`, `templates.md`, `init-workflow.md`)
- Version-pinned manifest diff: detect new/removed/changed interfaces between versions as strategy signal source D (`strategy-workflow.md`)
- Cross-group scenario definitions in `test-groups.md` template: named end-to-end paths spanning multiple test groups (`templates.md`)
- Per-group smoke subsets in `test-groups.md` template: define mini validation subset per large group for smoke mode (`templates.md`)
- "Expected error ≠ test failure" guidance: explicit 3-case classification for API error codes in execution discipline (`test-execution-workflow.md`)

### Source

Patterns extracted from [futu-rust-opend-tester](https://github.com/d-wwei/futu-rust-opend-tester) Iron Rules #6-9 and surface manifest system. Domain-specific knowledge (futu-opend-rs test groups, manifests, MCP parameter styles) remains in project-level test knowledge.

## [2.0.0] - 2026-04-20

Major redesign: constraint framework, three-tier methodology architecture, test execution framework, experience extraction, and differential testing.

### Added

**Constraint Framework (L0-L3)**
- L0 goal calibration: role reframe ("测试审计员") + training bias correction in `protocol.md`
- L1 Hook design: 5 hooks (credential scan, feedback-rules protection, empty result prompt, result consistency, execution logging)
- L2 independent verification: 3 checks (execution audit, coverage reconciliation, evidence audit) via sub-agent
- L3 human audit panel: 20-25 line decision-oriented `audit-report.md` assembled from structured data
- Full constraint framework design document: `code/constraint-framework.md`

**New Workflows**
- `test-execution-workflow.md`: framework + template for per-project execution plans, combining universal discipline (four-color marking, evidence grading, error diagnosis, terminal state rules, safety) with project-specific knowledge (`[PROJECT]` injection points)
- `reflect-workflow.md`: 6-type historical analysis (impact-map precision, stability trends, bug hotspots, lesson synthesis, timing calibration, pattern extraction). Incremental reflect runs automatically after each test; full reflect via `/better-test reflect [scope]`
- `protocol-update-workflow.md`: upgrade test cognitive constraints from user input or session summary, with changelog tracking

**New Procedures (Tier 2)**
- `procedures/bdd-scenarios.md`: Given-When-Then scenario generation from PRD
- `procedures/tdd-flow.md`: Red-Green-Refactor for new feature development
- `procedures/contract-testing.md`: consumer-driven contract testing for microservices
- `procedures/exploratory-charter.md`: structured exploratory testing with time-boxed charters
- `procedures/hypothesis-investigation.md`: 3-hypothesis rule + investigation ladder + 5-level evidence grading + bug classification
- `procedures/mutation-testing.md`: incremental mutation testing for changed code
- `procedures/flakiness-scoring.md`: probabilistic stability scoring from test history
- `procedures/bug-report.md`: 7-section standard format + yaml metadata

**New Commands**
- `/better-test protocol-update [text]`: upgrade cognitive constraints with changelog
- `/better-test reflect [scope]`: extract experience from historical data
- `compare` mode in strategy: differential testing between implementations/versions

**Testing Methodology**
- `methodologies/design-rationale.md`: consolidated Tier 3 design document with all research citations (ICSE 2014, Google mutation testing, Meta flakiness, DORA 2024, F-Secure exploratory testing, Microsoft TDD, systematic-debugging)

**History & Bug Management**
- `bugs/` directory per version for structured bug reports with lifecycle (OPEN → CONFIRMED → FIXED → VERIFIED → CLOSED)
- `bugs-index.md`: cross-version bug index, drives strategy bug-retest recommendations
- `results.json` schema: formal definition with coverage stats, per-item evidence level, stability score, bug associations
- `execution-log.md` format: L1 Hook auto-generated execution record
- Per-run archiving: execution-log + l2-findings + audit-report archived to `history/<version>/run-NNN/`

### Changed

**Protocol Redesign**
- Structure: old "通用原则 + 触发器" → new "L0 目标校准 + 思维纪律 + 安全纪律"
- Execution steps (four-color marking, error three-questions, etc.) moved to `test-execution-workflow.md` Tier 1
- Protocol now only contains mindset rules (evidence strength, diagnosis before retry, four-state thinking), not procedural steps
- Removed fixed ≤15 line limit; replaced with "shorter = better attention" principle

**Three-Tier Loading Architecture**
- Tier 1 (always loaded): core procedures embedded directly in workflow files
- Tier 2 (condition-triggered): 8 standalone procedure files in `procedures/`, each with explicit trigger condition
- Tier 3 (human reference): 5 methodology files consolidated into 1 `design-rationale.md`, agent does not load

**Init Workflow Enhancements**
- Classification table: added Mobile App, Desktop App, Browser Extension (11 types total)
- Any skill can create `shared/` (not just better-code): minimal version with project identity + Testing section
- Code reading strategy: two-pass (signature scan → user choice: extract/full/skip), streaming extraction for large codebases
- Material collection: Signal Source F with 3 core questions at init + staged collection across workflow phases
- New test 4-question check embedded in init and update

**Strategy Workflow**
- Decision tree: bug-retest now includes FIXED-but-unverified bugs from `bugs-index.md`
- Step 5.5 conditional checks: batch size warning, combined strategy suggestion, release strategy advice
- Compare mode: differential testing between two targets with structured diff report

**Update Workflow**
- Signal 6: accept new materials at any time (API specs, error code tables, PRD, SLA, etc.)
- Three-way distinction table: update vs feedback vs reflect

**Feedback Workflow**
- Regression canary prompt: auto-suggest adding to canary on verdict=fixed/fixed-differently

**Templates**
- `test-groups.md`: added test type field (unit/integration/e2e), per-item ID table with stability scores, smoke selection criteria
- `impact-map.md`: evidence grade correspondence table for source field values
- `known-issues.md`: flakiness stability score column in Flaky section
- `status.md`: test pyramid structure check, reachable coverage format, flaky item list, link to audit-report
- `protocol-changelog.md`: updated section names to match new protocol structure, added consistency check field

**Knowledge Evolution**
- File dependency graph + consistency check checklist for cross-file updates
- Authority priority: protocol.md > test-execution-workflow.md > procedures/ > templates.md
- Changelog mechanism for both protocol.md and test-execution-workflow.md

## [1.3.1] - 2026-04-19

### Added
- `init-workflow.md` Step 1: added **"测试工具 / 测试基础设施"** category (eighth row in the classification table) for projects where the tester itself is the product (e.g., `futu-rust-opend-tester`-like skills)
- `init-workflow.md` Step 3.5: new "同步知识 repo 的 .gitignore 标准模板" subsection. References `better-work/references/gitignore-template.md` as canonical source with inline fallback
- `init-workflow.md` Step 3.7: new "同步全局 registry" subsection referencing `better-work/references/registry-schema.md` (v1); defines standalone fallback when better-work is not installed

## [1.3.0] - 2026-04-19

### Changed
- README rewritten with **"failure-mode-4 framing"**: emphasizes the feedback loop (`strategy → test → feedback → known-issues`) that turns repeated bugs into one-time learnings, mapping to the "didn't run the right tests" failure mode

## [1.2.0] - 2026-04-18

### Added
- Initial release scaffolded from `futu-rust-opend-tester` abstractions
- 7 workflow references:
  - `init-workflow.md` — 5 steps + 7 test-scenario categories
  - `update-workflow.md` — 5 signal types (new group / new mapping / flaky / new convention / coverage gap)
  - `strategy-workflow.md` — 6 steps (change detection → impact analysis → history → decision tree → present → output command)
  - `feedback-workflow.md` — 6 verdicts (`not-a-bug` / `fixed` / `fixed-differently` / `wontfix` / `deferred` / `revoke`)
  - `progress-workflow.md` — checkpoint / resume with safety constraints (no credentials in memory)
  - `templates.md` — protocol.md 3-level (strict/standard/relaxed) + test-groups.md + impact-map.md + known-issues.md + status.md
  - `adapters.md` — Claude Code / Cursor / Gemini / Codex / OpenCode / OpenClaw
- `SKILL.md` (495 words, 10 red lines, 5 acceptance criteria)
- `LICENSE` (MIT)
- `README.md` + `README.zh-CN.md` (206-208 lines each, native bilingual)

### Fixed (post-v1.2.0 patches)
- `init-workflow.md` Step 3.1: risk-level prompt unattended fallback (default `standard`)
- `init-workflow.md` Step 3 history/: expanded both `_meta.json` and `feedback-rules.json` schemas with `schema_version: 1` field
- `init-workflow.md` Step 4: specified three injection cases based on `shared/` existence (avoid duplicate injection)

---

[2.0.0]: https://github.com/d-wwei/better-test/compare/v1.3.1...v2.0.0
[1.3.1]: https://github.com/d-wwei/better-test/compare/v1.3.0...v1.3.1
[1.3.0]: https://github.com/d-wwei/better-test/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/d-wwei/better-test/releases/tag/v1.2.0

# Changelog

All notable changes to **better-test** (Better-Work series testing subskill) are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this project uses [Semantic Versioning](https://semver.org/).

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

[1.3.1]: https://github.com/d-wwei/better-test/compare/v1.3.0...v1.3.1
[1.3.0]: https://github.com/d-wwei/better-test/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/d-wwei/better-test/releases/tag/v1.2.0

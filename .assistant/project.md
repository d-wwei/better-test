# Project Memory: better-test

- Status: active
- Initialized: 2026-07-24
- Canonical checkout: `/Users/eli/Documents/AI/better-test`
- Remote: `https://github.com/d-wwei/better-test.git`
- Purpose: Persistent testing-knowledge skill and hook enforcement for agent-driven software testing.

## Stable decisions

- This checkout is the canonical Codex skill source; `~/.codex/skills/better-test` points here by symlink.
- Keep credentials, private test evidence, generated artifacts, and project-specific test histories out of this repository.
- Validate hook changes with the deterministic `hooks/test-*.sh` suites before pushing.

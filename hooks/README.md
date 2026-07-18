# better-test Hooks

L1 constraint hooks. Run automatically before/after tool calls to enforce testing discipline.

## Test Root Resolution

Hooks resolve one test root per project in this order:

1. absolute `BETTER_TEST_DIR` override
2. nearest repository `.better-test-root` file containing one repository-relative path such as `test`
3. nearest `.better-work/test/`
4. flat `test/` containing `protocol.md` plus `test-groups.md`, `status.md`, or `history/`
5. `~/.better-work/<project>/test/`

Use only one root in a project. Commit `.better-test-root` for a flat or non-default repository layout; this is
shared by Claude and Codex and does not require per-machine shell configuration. Use `BETTER_TEST_DIR` only for
an absolute, temporary override.

## Support Matrix

`hooks/registry.json` is the single source of truth for hook support status.

| Hook | Claude | Codex |
|------|--------|-------|
| credential-scan | active | active |
| feedback-rules-guard | active | active |
| execution-log | active | active |
| post-test-checklist | active | active |
| results-validation | active | active |
| derived-view-guard | active | active |
| registration-gate | active | active |
| session-write-guard | active | active |

## Installation (Recommended: gate.sh global)

Add the following to **global** `~/.claude/settings.json`. Gate.sh resolves the project test root and dispatches to individual hooks. Non-better-test projects exit immediately.

```json
{
  "hooks": {
    "PreToolUse": [
      {"matcher": "Edit|Write", "hooks": [{"type": "command", "command": "\"$HOME\"/.claude/skills/better-test/hooks/gate.sh pre-edit-write"}]}
    ],
    "PostToolUse": [
      {"matcher": "Bash", "hooks": [{"type": "command", "command": "\"$HOME\"/.claude/skills/better-test/hooks/gate.sh post-bash"}]},
      {"matcher": "Write", "hooks": [{"type": "command", "command": "\"$HOME\"/.claude/skills/better-test/hooks/gate.sh post-write"}]}
    ]
  }
}
```

Note: `install.sh` only creates skill symlinks (Layer 1 registration). It does **not** configure hooks. Global hook config must be added manually per the JSON above, or by a future `install-hooks.sh` script.

## Codex Installation

Codex hooks are installed per project and managed separately from `install.sh`.

```bash
# install active better-test Codex hooks into <project>/.codex/hooks.json
./hooks/install-codex-hooks.sh install

# inspect feature flag + install state
./hooks/install-codex-hooks.sh status

# remove only better-test-managed Codex hook entries
./hooks/install-codex-hooks.sh uninstall
```

Both `install` and `status` print the resolved `test root:`. Treat an unresolved or unexpected root as an
installation failure before running tests.

Current Codex-active hook set: `execution-log`, `credential-scan`, `feedback-rules-guard`, `derived-view-guard`, `session-write-guard`, `post-test-checklist`, `results-validation`, and `registration-gate`.
These were runtime-verified on `codex-cli 0.125.0` and re-verified on `0.145.0-alpha.18` with the renamed `hooks` feature and hook-trust requirement.
`execution-log` runs on `PostToolUse/Bash`.
`credential-scan`, `feedback-rules-guard`, `derived-view-guard`, and `session-write-guard` each run on both `PreToolUse/Bash` and `PreToolUse/Write`.
`post-test-checklist`, `results-validation`, and `registration-gate` each run on both `PostToolUse/Bash` and `PostToolUse/Write`.
On current Codex runtime, built-in file edits surface as `matcher: "Write"` with `tool_name: "apply_patch"`, not Claude-style `tool_name: "Write"` plus `file_path/content`.
Current runtime payloads also omit shell exit code, so Codex-generated `execution-log.md` entries record `EXIT: ?`.
`PostToolUse/Bash` hook commands that exit nonzero still run, but they do not fail the Codex command path; stderr surfacing from those post hooks is not treated as stable.

Notes:
- `hooks/install-codex-hooks.sh` reads active Codex entries from `hooks/registry.json`
- default target is project-local `.codex/hooks.json`
- it detects the current runtime feature name (`hooks` on Codex 0.145+, legacy `codex_hooks` on older builds) and also accepts a runtime-enabled stable default
- it does not touch the feature flag unless you pass `--enable-feature-flag`
- install / uninstall preserve unrelated hook entries already present in `.codex/hooks.json`
- Codex now covers both shell write-intent and built-in `apply_patch`/`file_change` for all active guards and advisories except `execution-log`, which remains `PostToolUse/Bash` only
- The Bash path still matters: shell writes and built-in `apply_patch` writes are separate runtime surfaces, and both stay installed
- `hooks/test-codex-runtime.sh` is the manual runtime smoke for current Codex behavior

## Alternative: Per-project installation (legacy)

Add the following to your project's `.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "<SKILL_PATH>/hooks/credential-scan.sh"
          },
          {
            "type": "command",
            "command": "<SKILL_PATH>/hooks/feedback-rules-guard.sh"
          },
          {
            "type": "command",
            "command": "<SKILL_PATH>/hooks/derived-view-guard.sh"
          },
          {
            "type": "command",
            "command": "<SKILL_PATH>/hooks/session-write-guard.sh"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Write",
        "hooks": [
          {
            "type": "command",
            "command": "<SKILL_PATH>/hooks/registration-gate.sh"
          },
          {
            "type": "command",
            "command": "<SKILL_PATH>/hooks/post-test-checklist.sh"
          },
          {
            "type": "command",
            "command": "<SKILL_PATH>/hooks/results-validation.sh"
          }
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "<SKILL_PATH>/hooks/execution-log.sh"
          }
        ]
      }
    ]
  }
}
```

Replace `<SKILL_PATH>` with the actual path to the better-test skill directory.

## Hooks

### Phase A: Core Discipline

#### credential-scan.sh
- **Type**: PreToolUse on Edit|Write
- **What it does**: Scans content being written to the resolved test root for credential patterns (password, token, api_key, secret, Bearer tokens)
- **Action on match**: Blocks the write (exit 2)
- **Codex note**: Codex now runs this on both `PreToolUse/Bash` and `PreToolUse/Write`. The Bash path scans command text for explicit credential-like literals; the native Write path scans added `apply_patch` lines. External file copies such as `cp leaked-creds.txt ...` remain outside this guard on the Bash path.

#### feedback-rules-guard.sh
- **Type**: PreToolUse on Edit|Write
- **What it does**: Blocks any direct edit to `feedback-rules.json`
- **Why**: feedback-rules.json is a derived view, rebuilt by `/better-test merge` or single-tester completion
- **Codex note**: Codex now runs this on both `PreToolUse/Bash` and `PreToolUse/Write`. Built-in file edits are covered through `matcher: "Write"` with `tool_name: "apply_patch"`, while Bash writes still rely on extracted shell targets.

#### execution-log.sh
- **Type**: PostToolUse on Bash
- **What it does**: Records every Bash command + output to execution-log.md for L2 audit

#### post-test-checklist.sh
- **Type**: PostToolUse on Write
- **Trigger**: When results.json is written
- **What it does**: Injects post-completion checklist reminder + **cleanup checklist** (v3.1.0: /tmp 凭据残留检查、orphan daemon/sampler 进程 kill、orphan orders cancel、测试副作用记入 process-log)
- **Codex note**: Codex now runs this on both `PostToolUse/Bash` and `PostToolUse/Write`. The Bash path infers shell write targets; the native Write path observes built-in `apply_patch` writes to `results.json`.

#### results-validation.sh
- **Type**: PostToolUse on Write
- **Trigger**: When results.json is written
- **What it does**: Validates results.json structure and **pass-evidence quality**:
  - Schema v2 requires version, run_id, mode, summary, tester_id, finished_at, coverage, items, and gate_items
  - Every v2 item must contain `status`; a legacy `verdict` cannot satisfy this requirement
  - Schema v1/unversioned history can still be read through `status // verdict`
  - Hierarchical IDs such as `AUTH-REM-03` and `CLI.AUTH-01` are accepted
  - Coverage section exists
  - Items array non-empty
  - Pass items have non-empty assertion_field
  - Stable item ID format
  - Pass items evidence_level >= direct
  - **(v3.1.0)** Compare mode: pass items must have comparison_baseline non-null
  - **(v3.1.0)** Pass items must have assertion_value non-empty (field name alone insufficient)
  - **(v3.1.0)** pre_existing=true items cannot be marked pass (Red Line #18)
- **Codex note**: Codex now runs this on both `PostToolUse/Bash` and `PostToolUse/Write`. Both paths re-read `results.json` after the write completes and inject validation errors/advisories via `additionalContext`. The shared validator returns failure for schema v2 errors; PostToolUse adapters surface that failure after the write because the runtime cannot undo an already-completed write.

### Phase B: Tester/Coordinator Isolation (v3.0)

#### derived-view-guard.sh
- **Type**: PreToolUse on Edit|Write
- **What it does**: Blocks writes to project-level derived view files (`test/status.md`, `test/known-issues.md`, `history/bugs-index.md`, `history/feedback-rules.json`) unless a merge lockfile (`.merge-in-progress`) exists
- **Merge bypass**: `/better-test merge` creates `.better-work/test/.merge-in-progress` at start, deletes at end. While the lockfile exists, derived view writes are allowed
- **Run/merge directory writes**: Always allowed (tester writes to `run-*/`, coordinator writes to `merge-*/`)
- **Codex note**: Codex now runs this on both `PreToolUse/Bash` and `PreToolUse/Write`. Bash writes still use extracted shell targets; built-in edits are covered via `apply_patch` target extraction.

#### registration-gate.sh
- **Type**: PostToolUse on Write
- **Trigger**: When `strategy-plan.md` is written to a `run-*/` directory
- **What it does**: Verifies that `bio.md` exists in the same run directory AND `registry.md` exists for the tester. **Warns if missing** (PostToolUse cannot block an already-completed write — it injects a warning via additionalContext urging the agent to create the missing files before proceeding)
- **Why**: Catches agents that start test execution without completing registration
- **Codex note**: Codex now runs this on both `PostToolUse/Bash` and `PostToolUse/Write`. It watches either Bash-inferred write targets or built-in `apply_patch` targets for `strategy-plan.md` and injects registration warnings via `additionalContext`.

#### session-write-guard.sh
- **Type**: PreToolUse on Edit|Write
- **What it does**: Uses PID-keyed session files to identify which tester is writing. Blocks writes to other testers' `run-*/` directories
- **Session registration**: Strategy workflow Step 0 writes `.active-sessions/<pid>.json` with tester-id and run directory path
- **PID detection**: Tries `$PPID` (direct parent), then grandparent PID (handles intermediate shell processes)
- **Graceful fallback**: If no session file found, allows write (doesn't block unregistered agents, e.g., during init)
- **PPID caveat**: Hook assumes `$PPID` = Claude Code process PID. This matches Bash tool behavior but **must be verified on first deployment** to a target project. If Claude Code spawns hooks via an intermediate shell, the grandparent fallback handles it. Run `/better-test strategy` once and check `.active-sessions/` matches hook detection.
- **Codex note**: Codex now runs this on both `PreToolUse/Bash` and `PreToolUse/Write`. Both paths use the same PID-keyed session file contract; only the write-target extraction differs.

## Session File Lifecycle

```
Agent starts
  └→ /better-test strategy (Step 0 registration)
      └→ writes .active-sessions/<PID>.json
         {"tester_id":"claude-a3f2","run_dir":"history/v1.4.28/run-claude-a3f2-002-..."}
      └→ session-write-guard.sh now enforces cross-tester isolation

Agent completes testing
  └→ deletes .active-sessions/<PID>.json
```

## Merge Lockfile Lifecycle

```
/better-test merge (Step 2)
  └→ creates .better-work/test/.merge-in-progress
  └→ derived-view-guard.sh now allows derived view writes

/better-test merge (Step 9, after user confirmation)
  └→ deletes .better-work/test/.merge-in-progress
  └→ derived view writes blocked again
```

## Hook Execution Order

PreToolUse hooks on Edit|Write run in config array order. All must pass (exit 0) for the tool call to proceed. Any exit 2 blocks the call.

Recommended order (most specific first, cheapest first):
1. `credential-scan.sh` — cheap content check, blocks dangerous writes early
2. `feedback-rules-guard.sh` — filename match, very fast
3. `derived-view-guard.sh` — filename match + lockfile check
4. `session-write-guard.sh` — filename match + session file read (most expensive)

PostToolUse hooks are informational/validation — they inject warnings via `additionalContext` (exit 0 + JSON), not block (the write already happened). Order matters less.

## .gitignore

On target projects, these temp files are inside `.better-work/test/` which should already be in `.gitignore`:
- `.active-sessions/` — PID-keyed session files (transient)
- `.merge-in-progress` — merge lockfile (transient)

If `.better-work/` is NOT gitignored on the target project, add:
```
.better-work/test/.active-sessions/
.better-work/test/.merge-in-progress
```

## Testing

```bash
# execution-log regression: Claude direct vs gate vs Codex direct
./hooks/test-execution-log-parity.sh

# local Bash write-intent guard coverage
./hooks/test-codex-bash-guards.sh

# local PostToolUse/Bash advisory coverage
./hooks/test-codex-post-bash-advisories.sh

# local native Write(apply_patch) guard + advisory coverage
./hooks/test-codex-write-hooks.sh

# local Codex fixture + installer smoke
./hooks/test-codex-hooks.sh

# real Codex runtime smoke (requires authenticated codex CLI)
./hooks/test-codex-runtime.sh

# keep temp artifacts for debugging a failing runtime smoke
BT_KEEP_TMP=1 ./hooks/test-codex-runtime.sh

# Test derived-view-guard: should block
echo '{"tool_name":"Write","tool_input":{"file_path":"/project/.better-work/test/status.md","content":"test"}}' | ./hooks/derived-view-guard.sh
# Expected: exit 2

# Test derived-view-guard: should allow (run directory)
echo '{"tool_name":"Write","tool_input":{"file_path":"/project/.better-work/test/history/v1/run-claude-a3f2-001-1234/status.md","content":"test"}}' | ./hooks/derived-view-guard.sh
# Expected: exit 0

# Test registration-gate: should warn (no bio.md) — PostToolUse, exit 0 with additionalContext
echo '{"tool_name":"Write","tool_input":{"file_path":"/project/.better-work/test/history/v1/run-claude-a3f2-001-1234/strategy-plan.md","content":"test"}}' | ./hooks/registration-gate.sh
# Expected: exit 0, JSON with additionalContext warning about missing bio.md

# Test session-write-guard: should allow (no session file = graceful fallback)
echo '{"tool_name":"Write","tool_input":{"file_path":"/project/.better-work/test/history/v1/run-claude-a3f2-001-1234/results.json","content":"test"}}' | ./hooks/session-write-guard.sh
# Expected: exit 0 (no session file, graceful fallback)
```

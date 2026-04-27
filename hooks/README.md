# better-test Hooks

L1 constraint hooks. Run automatically before/after tool calls to enforce testing discipline.

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

Add the following to **global** `~/.claude/settings.json`. Gate.sh auto-detects whether the current project uses better-test and dispatches to individual hooks. Non-better-test projects: ~10ms overhead (immediate exit).

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

Current Codex-active hook set: `execution-log`, `credential-scan`, `feedback-rules-guard`, `derived-view-guard`, `session-write-guard`, `post-test-checklist`, `results-validation`, and `registration-gate`.
These are runtime-verified on `codex-cli 0.122.0`.
`execution-log` runs on `PostToolUse/Bash`.
`credential-scan` runs on `PreToolUse/Bash` and blocks commands that explicitly embed credential-like literals while writing into `.better-work/test/`.
`feedback-rules-guard` and `derived-view-guard` run on `PreToolUse/Bash` and block Bash commands whose write target resolves into protected `.better-work/test/` paths.
`session-write-guard` runs on `PreToolUse/Bash` and blocks Bash writes into another tester's `run-*` directory once the current tester has registered a matching `.active-sessions/<pid>.json`.
`post-test-checklist`, `results-validation`, and `registration-gate` are also active on `PostToolUse/Bash`: they infer Bash write targets, then emit advisory `additionalContext` after commands that write `results.json` or `strategy-plan.md`.
Native `matcher: "Write"` still has not been observed firing on `file_change`, so these three Codex hooks currently use a Bash write-intent fallback rather than Codex-native `Write`.
Current runtime payloads also omit shell exit code, so Codex-generated `execution-log.md` entries record `EXIT: ?`.
`PostToolUse/Bash` hook commands that exit nonzero still run, but they do not fail the Codex command path; stderr surfacing from those post hooks is not treated as stable.

Notes:
- `hooks/install-codex-hooks.sh` reads active Codex entries from `hooks/registry.json`
- default target is project-local `.codex/hooks.json`
- it checks `~/.codex/config.toml` for `codex_hooks = true`
- it does not touch the feature flag unless you pass `--enable-feature-flag`
- install / uninstall preserve unrelated hook entries already present in `.codex/hooks.json`
- Bash path guards currently cover shell write-intent only, not built-in `file_change` / `Write` / `Edit`
- Codex post-write advisories currently cover Bash writes only, not built-in `file_change`
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
- **What it does**: Scans content being written to `.better-work/test/` for credential patterns (password, token, api_key, secret, Bearer tokens)
- **Action on match**: Blocks the write (exit 2)
- **Codex note**: Codex currently maps this guard to `PreToolUse/Bash` only. It scans the Bash command text for explicit credential-like literals when the command writes into `.better-work/test/`, so it does not cover secrets copied from external files such as `cp leaked-creds.txt ...` or values generated inside child interpreters.

#### feedback-rules-guard.sh
- **Type**: PreToolUse on Edit|Write
- **What it does**: Blocks any direct edit to `feedback-rules.json`
- **Why**: feedback-rules.json is a derived view, rebuilt by `/better-test merge` or single-tester completion
- **Codex note**: Codex currently maps this guard to `PreToolUse/Bash` only. It inspects extracted Bash write targets, so coverage is intentionally narrower than Claude's native `Edit|Write` path.

#### execution-log.sh
- **Type**: PostToolUse on Bash
- **What it does**: Records every Bash command + output to execution-log.md for L2 audit

#### post-test-checklist.sh
- **Type**: PostToolUse on Write
- **Trigger**: When results.json is written
- **What it does**: Injects post-completion checklist reminder + **cleanup checklist** (v3.1.0: /tmp 凭据残留检查、orphan daemon/sampler 进程 kill、orphan orders cancel、测试副作用记入 process-log)
- **Codex note**: Codex currently maps this hook to `PostToolUse/Bash` only. It triggers when a Bash command's extracted write target resolves to `results.json`, then injects advisory `additionalContext`; it does not currently observe built-in `Write`.

#### results-validation.sh
- **Type**: PostToolUse on Write
- **Trigger**: When results.json is written
- **What it does**: Validates results.json structure and **pass-evidence quality** (v3.1.0):
  - Required top-level fields (version, run_id, mode, summary)
  - Coverage section exists
  - Items array non-empty
  - Pass items have non-empty assertion_field
  - Item ID format (Letter-NN)
  - Pass items evidence_level >= direct
  - **(v3.1.0)** Compare mode: pass items must have comparison_baseline non-null
  - **(v3.1.0)** Pass items must have assertion_value non-empty (field name alone insufficient)
  - **(v3.1.0)** pre_existing=true items cannot be marked pass (Red Line #18)
- **Codex note**: Codex currently maps this hook to `PostToolUse/Bash` only. It re-reads `results.json` after a Bash write and injects validation warnings via `additionalContext`; it does not currently observe built-in `Write`.

### Phase B: Tester/Coordinator Isolation (v3.0)

#### derived-view-guard.sh
- **Type**: PreToolUse on Edit|Write
- **What it does**: Blocks writes to project-level derived view files (`test/status.md`, `test/known-issues.md`, `history/bugs-index.md`, `history/feedback-rules.json`) unless a merge lockfile (`.merge-in-progress`) exists
- **Merge bypass**: `/better-test merge` creates `.better-work/test/.merge-in-progress` at start, deletes at end. While the lockfile exists, derived view writes are allowed
- **Run/merge directory writes**: Always allowed (tester writes to `run-*/`, coordinator writes to `merge-*/`)
- **Codex note**: Codex currently maps this guard to `PreToolUse/Bash` only. It matches paths extracted from Bash write commands, not the full Claude `Edit|Write` surface.

#### registration-gate.sh
- **Type**: PostToolUse on Write
- **Trigger**: When `strategy-plan.md` is written to a `run-*/` directory
- **What it does**: Verifies that `bio.md` exists in the same run directory AND `registry.md` exists for the tester. **Warns if missing** (PostToolUse cannot block an already-completed write — it injects a warning via additionalContext urging the agent to create the missing files before proceeding)
- **Why**: Catches agents that start test execution without completing registration
- **Codex note**: Codex currently maps this hook to `PostToolUse/Bash` only. It watches Bash write targets for `strategy-plan.md` and injects registration warnings via `additionalContext`; it does not currently observe built-in `Write`.

#### session-write-guard.sh
- **Type**: PreToolUse on Edit|Write
- **What it does**: Uses PID-keyed session files to identify which tester is writing. Blocks writes to other testers' `run-*/` directories
- **Session registration**: Strategy workflow Step 0 writes `.active-sessions/<pid>.json` with tester-id and run directory path
- **PID detection**: Tries `$PPID` (direct parent), then grandparent PID (handles intermediate shell processes)
- **Graceful fallback**: If no session file found, allows write (doesn't block unregistered agents, e.g., during init)
- **PPID caveat**: Hook assumes `$PPID` = Claude Code process PID. This matches Bash tool behavior but **must be verified on first deployment** to a target project. If Claude Code spawns hooks via an intermediate shell, the grandparent fallback handles it. Run `/better-test strategy` once and check `.active-sessions/` matches hook detection.
- **Codex note**: Codex currently maps this guard to `PreToolUse/Bash` only. It protects run directories that can be resolved from extracted Bash write targets, using the same PID-keyed session file contract as Claude.

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

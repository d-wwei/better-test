# better-test Hooks

L1 constraint hooks. Run automatically before/after tool calls to enforce testing discipline.

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

#### feedback-rules-guard.sh
- **Type**: PreToolUse on Edit|Write
- **What it does**: Blocks any direct edit to `feedback-rules.json`
- **Why**: feedback-rules.json is a derived view, rebuilt by `/better-test merge` or single-tester completion

#### execution-log.sh
- **Type**: PostToolUse on Bash
- **What it does**: Records every Bash command + output to execution-log.md for L2 audit

#### post-test-checklist.sh
- **Type**: PostToolUse on Write
- **Trigger**: When results.json is written
- **What it does**: Injects post-completion checklist reminder

#### results-validation.sh
- **Type**: PostToolUse on Write
- **Trigger**: When results.json is written
- **What it does**: Validates required fields in results.json

### Phase B: Tester/Coordinator Isolation (v3.0)

#### derived-view-guard.sh
- **Type**: PreToolUse on Edit|Write
- **What it does**: Blocks writes to project-level derived view files (`test/status.md`, `test/known-issues.md`, `history/bugs-index.md`, `history/feedback-rules.json`) unless a merge lockfile (`.merge-in-progress`) exists
- **Merge bypass**: `/better-test merge` creates `.better-work/test/.merge-in-progress` at start, deletes at end. While the lockfile exists, derived view writes are allowed
- **Run/merge directory writes**: Always allowed (tester writes to `run-*/`, coordinator writes to `merge-*/`)

#### registration-gate.sh
- **Type**: PostToolUse on Write
- **Trigger**: When `strategy-plan.md` is written to a `run-*/` directory
- **What it does**: Verifies that `bio.md` exists in the same run directory AND `registry.md` exists for the tester. Blocks if missing
- **Why**: Prevents agents from starting test execution without completing registration

#### session-write-guard.sh
- **Type**: PreToolUse on Edit|Write
- **What it does**: Uses PID-keyed session files to identify which tester is writing. Blocks writes to other testers' `run-*/` directories
- **Session registration**: Strategy workflow Step 0 writes `.active-sessions/<pid>.json` with tester-id and run directory path
- **PID detection**: Tries `$PPID` (direct parent), then grandparent PID (handles intermediate shell processes)
- **Graceful fallback**: If no session file found, allows write (doesn't block unregistered agents, e.g., during init)
- **PPID caveat**: Hook assumes `$PPID` = Claude Code process PID. This matches Bash tool behavior but **must be verified on first deployment** to a target project. If Claude Code spawns hooks via an intermediate shell, the grandparent fallback handles it. Run `/better-test strategy` once and check `.active-sessions/` matches hook detection.

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

PostToolUse hooks are informational/validation — they don't block the already-completed tool call (exit 2 shows a warning but the write already happened). Order matters less.

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
# Test derived-view-guard: should block
echo '{"tool_name":"Write","tool_input":{"file_path":"/project/.better-work/test/status.md","content":"test"}}' | ./hooks/derived-view-guard.sh
# Expected: exit 2

# Test derived-view-guard: should allow (run directory)
echo '{"tool_name":"Write","tool_input":{"file_path":"/project/.better-work/test/history/v1/run-claude-a3f2-001-1234/status.md","content":"test"}}' | ./hooks/derived-view-guard.sh
# Expected: exit 0

# Test registration-gate: should block (no bio.md)
echo '{"tool_name":"Write","tool_input":{"file_path":"/project/.better-work/test/history/v1/run-claude-a3f2-001-1234/strategy-plan.md","content":"test"}}' | ./hooks/registration-gate.sh
# Expected: exit 2 (bio.md not found)

# Test session-write-guard: should allow (no session file = graceful fallback)
echo '{"tool_name":"Write","tool_input":{"file_path":"/project/.better-work/test/history/v1/run-claude-a3f2-001-1234/results.json","content":"test"}}' | ./hooks/session-write-guard.sh
# Expected: exit 0 (no session file, graceful fallback)
```

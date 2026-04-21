# better-test Hooks

L1 constraint hooks for Claude Code. These run automatically before tool calls to enforce testing discipline.

## Installation

Add the following to your project's `.claude/settings.json` (or `~/.claude/settings.json` for global):

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
          }
        ]
      }
    ]
  }
}
```

Replace `<SKILL_PATH>` with the actual path to the better-test skill directory. For example:

```json
"command": "/Users/you/.claude/skills/better-test/hooks/credential-scan.sh"
```

Or use the `$CLAUDE_PROJECT_DIR` variable if the skill is linked in the project:

```json
"command": "\"$HOME\"/.claude/skills/better-test/hooks/credential-scan.sh"
```

## Hooks

### credential-scan.sh

- **Type**: PreToolUse on Edit|Write
- **What it does**: Scans content being written to `.better-work/test/` for credential patterns (password, token, api_key, secret, Bearer tokens)
- **Action on match**: Blocks the write (exit 2) with a message explaining what was detected
- **False positive handling**: Ignores template placeholders (`<password>`), quoted strings, and short values

### feedback-rules-guard.sh

- **Type**: PreToolUse on Edit|Write
- **What it does**: Blocks any direct edit to `feedback-rules.json`
- **Action on match**: Blocks with a message directing the agent to use `/better-test feedback` command instead
- **Why**: feedback-rules.json is auto-maintained by the feedback workflow. Direct edits break the automation chain and make changes untraceable.

## Testing

```bash
# Test credential scan
echo '{"tool_name":"Write","tool_input":{"file_path":".better-work/test/progress.md","content":"password=mysecret123"}}' | ./hooks/credential-scan.sh
# Should exit 2 and print warning to stderr

echo '{"tool_name":"Write","tool_input":{"file_path":".better-work/test/progress.md","content":"no credentials here"}}' | ./hooks/credential-scan.sh
# Should exit 0 (allow)

# Test feedback-rules guard
echo '{"tool_name":"Edit","tool_input":{"file_path":".better-work/test/history/feedback-rules.json","old_string":"x","new_string":"y"}}' | ./hooks/feedback-rules-guard.sh
# Should exit 2 and print warning

echo '{"tool_name":"Edit","tool_input":{"file_path":".better-work/test/known-issues.md","old_string":"x","new_string":"y"}}' | ./hooks/feedback-rules-guard.sh
# Should exit 0 (allow)
```

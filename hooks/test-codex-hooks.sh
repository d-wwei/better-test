#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FIXTURE_FILE="$SCRIPT_DIR/fixtures/codex/post-bash.json"
TMP_DIR="$(mktemp -d)"
PROJECT_DIR="$TMP_DIR/project"
HOME_DIR="$TMP_DIR/home"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$PROJECT_DIR/.better-work/test" "$PROJECT_DIR/.codex" "$HOME_DIR/.codex"

jq --arg cwd "$PROJECT_DIR" '.cwd = $cwd' "$FIXTURE_FILE" | "$SCRIPT_DIR/codex/execution-log.sh"

LOG_FILE="$PROJECT_DIR/.better-work/test/execution-log.md"
if [[ ! -f "$LOG_FILE" ]]; then
  echo "execution-log hook did not create $LOG_FILE" >&2
  exit 1
fi

grep -q 'CMD: printf "hello from codex"' "$LOG_FILE"
grep -q 'EXIT: 0' "$LOG_FILE"

cat > "$HOME_DIR/.codex/config.toml" <<'EOF'
[features]
hooks = true
EOF

cat > "$PROJECT_DIR/.codex/hooks.json" <<'EOF'
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "/tmp/unrelated-hook.sh",
            "statusMessage": "foreign: keep-me"
          }
        ]
      }
    ]
  }
}
EOF

HOME="$HOME_DIR" "$SCRIPT_DIR/install-codex-hooks.sh" install --project "$PROJECT_DIR" >/dev/null

jq -e '
  any(.hooks.PostToolUse[]?.hooks[]?; (.statusMessage // "") == "better-test: execution-log")
' "$PROJECT_DIR/.codex/hooks.json" >/dev/null

jq -e '
  any(.hooks.PostToolUse[]?; .matcher == "Bash" and any(.hooks[]?; (.statusMessage // "") == "better-test: post-test-checklist"))
' "$PROJECT_DIR/.codex/hooks.json" >/dev/null

jq -e '
  any(.hooks.PostToolUse[]?; .matcher == "Bash" and any(.hooks[]?; (.statusMessage // "") == "better-test: results-validation"))
' "$PROJECT_DIR/.codex/hooks.json" >/dev/null

jq -e '
  any(.hooks.PostToolUse[]?; .matcher == "Bash" and any(.hooks[]?; (.statusMessage // "") == "better-test: registration-gate"))
' "$PROJECT_DIR/.codex/hooks.json" >/dev/null

jq -e '
  any(.hooks.PostToolUse[]?; .matcher == "Write" and any(.hooks[]?; (.statusMessage // "") == "better-test: post-test-checklist"))
' "$PROJECT_DIR/.codex/hooks.json" >/dev/null

jq -e '
  any(.hooks.PostToolUse[]?; .matcher == "Write" and any(.hooks[]?; (.statusMessage // "") == "better-test: results-validation"))
' "$PROJECT_DIR/.codex/hooks.json" >/dev/null

jq -e '
  any(.hooks.PostToolUse[]?; .matcher == "Write" and any(.hooks[]?; (.statusMessage // "") == "better-test: registration-gate"))
' "$PROJECT_DIR/.codex/hooks.json" >/dev/null

jq -e '
  any(.hooks.PreToolUse[]?; .matcher == "Bash" and any(.hooks[]?; (.statusMessage // "") == "better-test: credential-scan"))
' "$PROJECT_DIR/.codex/hooks.json" >/dev/null

jq -e '
  any(.hooks.PreToolUse[]?; .matcher == "Bash" and any(.hooks[]?; (.statusMessage // "") == "better-test: feedback-rules-guard"))
' "$PROJECT_DIR/.codex/hooks.json" >/dev/null

jq -e '
  any(.hooks.PreToolUse[]?; .matcher == "Bash" and any(.hooks[]?; (.statusMessage // "") == "better-test: derived-view-guard"))
' "$PROJECT_DIR/.codex/hooks.json" >/dev/null

jq -e '
  any(.hooks.PreToolUse[]?; .matcher == "Bash" and any(.hooks[]?; (.statusMessage // "") == "better-test: session-write-guard"))
' "$PROJECT_DIR/.codex/hooks.json" >/dev/null

jq -e '
  any(.hooks.PreToolUse[]?; .matcher == "Write" and any(.hooks[]?; (.statusMessage // "") == "better-test: credential-scan"))
' "$PROJECT_DIR/.codex/hooks.json" >/dev/null

jq -e '
  any(.hooks.PreToolUse[]?; .matcher == "Write" and any(.hooks[]?; (.statusMessage // "") == "better-test: feedback-rules-guard"))
' "$PROJECT_DIR/.codex/hooks.json" >/dev/null

jq -e '
  any(.hooks.PreToolUse[]?; .matcher == "Write" and any(.hooks[]?; (.statusMessage // "") == "better-test: derived-view-guard"))
' "$PROJECT_DIR/.codex/hooks.json" >/dev/null

jq -e '
  any(.hooks.PreToolUse[]?; .matcher == "Write" and any(.hooks[]?; (.statusMessage // "") == "better-test: session-write-guard"))
' "$PROJECT_DIR/.codex/hooks.json" >/dev/null

jq -e '
  any(.hooks.PostToolUse[]?.hooks[]?; (.statusMessage // "") == "foreign: keep-me")
' "$PROJECT_DIR/.codex/hooks.json" >/dev/null

HOME="$HOME_DIR" "$SCRIPT_DIR/install-codex-hooks.sh" uninstall --project "$PROJECT_DIR" >/dev/null

jq -e '
  any(.hooks.PostToolUse[]?.hooks[]?; (.statusMessage // "") == "foreign: keep-me")
' "$PROJECT_DIR/.codex/hooks.json" >/dev/null

if jq -e '
  any(.hooks.PostToolUse[]?.hooks[]?; (.statusMessage // "") == "better-test: execution-log")
' "$PROJECT_DIR/.codex/hooks.json" >/dev/null 2>&1; then
  echo "better-test hook entry still present after uninstall" >&2
  exit 1
fi

if jq -e '
  any(.hooks.PreToolUse[]?.hooks[]?; ((.statusMessage // "") | startswith("better-test:")))
' "$PROJECT_DIR/.codex/hooks.json" >/dev/null 2>&1; then
  echo "better-test pre hook entry still present after uninstall" >&2
  exit 1
fi

echo "codex hook smoke tests passed"

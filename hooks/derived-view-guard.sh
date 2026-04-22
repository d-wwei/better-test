#!/bin/bash
# better-test L1 Hook: Derived View Write Protection
# Blocks writes to project-level aggregation files unless /better-test merge is in progress.
# These files are derived views — only coordinator writes them during merge.
# PreToolUse on Edit|Write
set -e

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Only check .better-work paths
if [[ "$FILE_PATH" != *".better-work/"* ]]; then
  exit 0
fi

# Derived view files (project-level aggregation files)
# These should only be written by coordinator during /better-test merge
DERIVED_VIEWS=(
  "test/status.md"
  "test/known-issues.md"
  "test/history/bugs-index.md"
  "test/history/feedback-rules.json"
)

IS_DERIVED=false
MATCHED_VIEW=""
for VIEW in "${DERIVED_VIEWS[@]}"; do
  # Match the derived view at project level (not inside run-*/ or merge-*/ directories)
  if echo "$FILE_PATH" | grep -q "\.better-work/$VIEW"; then
    # Allow writes inside run-*/ or merge-*/ directories (those are tester/coordinator workspace)
    if echo "$FILE_PATH" | grep -qE '/(run-|merge-)'; then
      exit 0
    fi
    IS_DERIVED=true
    MATCHED_VIEW="$VIEW"
    break
  fi
done

if [[ "$IS_DERIVED" == "true" ]]; then
  # Check for merge lockfile — if present, coordinator is running merge, allow write
  # Extract the .better-work base path from the file path
  BETTER_WORK_DIR=$(echo "$FILE_PATH" | sed 's|/test/.*|/test|; s|/history/.*|/test|')
  # Try both /test and one level up for history paths
  LOCKFILE_CANDIDATES=(
    "$(echo "$FILE_PATH" | sed 's|\(.*\.better-work/test\)/.*|\1|')/.merge-in-progress"
    "$(echo "$FILE_PATH" | sed 's|\(.*\.better-work\)/.*|\1|')/test/.merge-in-progress"
  )

  # Determine the .better-work/test base path for checking lockfile and sessions
  TEST_BASE=$(echo "$FILE_PATH" | sed 's|\(.*\.better-work/test\)/.*|\1|')

  # Bypass 1: merge lockfile exists → coordinator is merging, allow
  if [[ -f "$TEST_BASE/.merge-in-progress" ]]; then
    exit 0
  fi

  # Bypass 2: no active sessions → not in parallel testing, allow
  # (update/reflect/single-tester completion can write directly)
  SESSION_DIR="$TEST_BASE/.active-sessions"
  if [[ ! -d "$SESSION_DIR" ]] || [[ -z "$(ls -A "$SESSION_DIR" 2>/dev/null)" ]]; then
    exit 0
  fi

  # Active sessions exist + no merge lockfile → block
  echo "better-test L1 Hook: Write to derived view '$MATCHED_VIEW' blocked. Active tester sessions detected — use /better-test merge after all testers complete, or clear .active-sessions/ if testing is done." >&2
  exit 2
fi

exit 0

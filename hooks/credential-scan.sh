#!/bin/bash
# better-test L1 Hook: Credential Scan
# Blocks writes to .better-work/test/ that contain credential patterns.
# PreToolUse on Edit|Write
set -e

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Only check writes to .better-work/test/ paths
if [[ "$FILE_PATH" != *".better-work/test/"* ]] && [[ "$FILE_PATH" != *".better-work/test\\"* ]]; then
  exit 0
fi

# Get the content being written
if [[ "$TOOL_NAME" == "Write" ]]; then
  CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // empty')
elif [[ "$TOOL_NAME" == "Edit" ]]; then
  CONTENT=$(echo "$INPUT" | jq -r '.tool_input.new_string // empty')
else
  exit 0
fi

# Skip empty content
if [[ -z "$CONTENT" ]]; then
  exit 0
fi

# Credential patterns (case-insensitive)
# Matches: password=xxx, token: xxx, api_key=xxx, secret=xxx, etc.
# Excludes: template placeholders like <password>, "password", comments about passwords
PATTERNS=(
  'password[[:space:]]*[=:][[:space:]]*[^[:space:]<"'"'"']{4,}'
  'token[[:space:]]*[=:][[:space:]]*[^[:space:]<"'"'"']{8,}'
  'api_key[[:space:]]*[=:][[:space:]]*[^[:space:]<"'"'"']{8,}'
  'api[-_]?secret[[:space:]]*[=:][[:space:]]*[^[:space:]<"'"'"']{8,}'
  'secret_key[[:space:]]*[=:][[:space:]]*[^[:space:]<"'"'"']{8,}'
  'access_key[[:space:]]*[=:][[:space:]]*[^[:space:]<"'"'"']{8,}'
  'Bearer[[:space:]]+[A-Za-z0-9_\-\.]{20,}'
)

for PATTERN in "${PATTERNS[@]}"; do
  if echo "$CONTENT" | grep -qiE "$PATTERN"; then
    MATCHED=$(echo "$CONTENT" | grep -oiE "$PATTERN" | head -1)
    echo "better-test L1 Hook: Credential detected in write to $FILE_PATH. Matched pattern near: ${MATCHED:0:30}... Remove credentials before writing to .better-work/ files." >&2
    exit 2
  fi
done

exit 0

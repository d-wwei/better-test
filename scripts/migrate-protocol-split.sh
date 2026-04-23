#!/bin/bash
# better-test migration: split protocol.md into skill-base + project-extension
#
# Usage: ./scripts/migrate-protocol-split.sh <project-root>
#
# What it does:
# 1. Reads project's current protocol.md (full version with L0 + discipline + safety + project)
# 2. Strips L0 and thinking discipline (now in skill's protocol-base.md)
# 3. Keeps only safety discipline + project discipline sections
# 4. Updates CLAUDE.md to add protocol-base.md injection
# 5. Backs up original files before modifying
set -e

PROJECT_ROOT="${1:-.}"

# Find protocol.md
PROTOCOL=""
if [[ -f "$PROJECT_ROOT/.better-work/test/protocol.md" ]]; then
  PROTOCOL="$PROJECT_ROOT/.better-work/test/protocol.md"
else
  PROJECT_NAME=$(basename "$PROJECT_ROOT")
  if [[ -f "$HOME/.better-work/$PROJECT_NAME/test/protocol.md" ]]; then
    PROTOCOL="$HOME/.better-work/$PROJECT_NAME/test/protocol.md"
  fi
fi

if [[ -z "$PROTOCOL" ]]; then
  echo "Error: protocol.md not found for project at $PROJECT_ROOT"
  exit 1
fi

echo "Found protocol.md: $PROTOCOL"

# Backup
cp "$PROTOCOL" "${PROTOCOL}.backup-$(date +%Y%m%d)"
echo "Backed up to ${PROTOCOL}.backup-$(date +%Y%m%d)"

# Extract safety discipline + project discipline (everything from "## 安全纪律" onward)
# If no safety discipline section, extract from "## 项目纪律" onward
SPLIT_POINT=""
if grep -q "## 安全纪律" "$PROTOCOL"; then
  SPLIT_POINT="## 安全纪律"
elif grep -q "## 项目纪律" "$PROTOCOL"; then
  SPLIT_POINT="## 项目纪律"
fi

if [[ -z "$SPLIT_POINT" ]]; then
  echo "Warning: No safety/project discipline section found. Creating minimal protocol."
  cat > "$PROTOCOL" << 'EOF'
# Test Protocol — Project Extension

> L0 + 思维纪律在 skill 的 protocol-base.md（自动加载）。
> 本文件只放项目级的安全纪律和项目纪律。

## 安全纪律
- 不把凭证写入任何 .better-work/ 文件

## 项目纪律
（由 /better-test protocol-update 写入）
EOF
else
  # Extract from split point to end
  TEMP=$(mktemp)
  cat > "$TEMP" << 'HEADER'
# Test Protocol — Project Extension

> L0 + 思维纪律在 skill 的 protocol-base.md（自动加载）。
> 本文件只放项目级的安全纪律和项目纪律。

HEADER
  sed -n "/$SPLIT_POINT/,\$p" "$PROTOCOL" >> "$TEMP"
  mv "$TEMP" "$PROTOCOL"
fi

echo "Protocol split done: $PROTOCOL"
echo "  - L0 + thinking discipline: removed (now in skill's protocol-base.md)"
echo "  - Safety + project discipline: kept"

# Update CLAUDE.md
CLAUDE_MD="$PROJECT_ROOT/CLAUDE.md"
if [[ -f "$CLAUDE_MD" ]]; then
  SKILL_PATH="$HOME/.claude/skills/better-test/protocol-base.md"

  if grep -q "protocol-base.md" "$CLAUDE_MD"; then
    echo "CLAUDE.md: protocol-base.md already injected, skipping"
  else
    # Add protocol-base.md before the project protocol line
    if grep -q "@.better-work/test/protocol.md" "$CLAUDE_MD"; then
      sed -i '' "s|@.better-work/test/protocol.md|@~/.claude/skills/better-test/protocol-base.md\n@.better-work/test/protocol.md|" "$CLAUDE_MD"
      echo "CLAUDE.md: added protocol-base.md injection before project protocol"
    else
      echo "@~/.claude/skills/better-test/protocol-base.md" >> "$CLAUDE_MD"
      echo "CLAUDE.md: appended protocol-base.md injection"
    fi
  fi
else
  echo "Warning: CLAUDE.md not found at $CLAUDE_MD — manual injection needed"
fi

echo ""
echo "Migration complete. Verify:"
echo "  1. cat $PROTOCOL"
echo "  2. cat $CLAUDE_MD"
echo "  3. New session should load both protocol-base.md and protocol.md"

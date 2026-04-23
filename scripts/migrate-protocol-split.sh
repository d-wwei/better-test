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

# Update CLAUDE.md — ensure both lines present in correct order (base before project)
CLAUDE_MD="$PROJECT_ROOT/CLAUDE.md"
BASE_LINE="@~/.claude/skills/better-test/protocol-base.md"
PROJECT_LINE="@.better-work/test/protocol.md"

if [[ -f "$CLAUDE_MD" ]]; then
  HAS_BASE=false
  HAS_PROJECT=false
  grep -qF "protocol-base.md" "$CLAUDE_MD" && HAS_BASE=true
  grep -qF "$PROJECT_LINE" "$CLAUDE_MD" && HAS_PROJECT=true

  if [[ "$HAS_BASE" == "true" && "$HAS_PROJECT" == "true" ]]; then
    # Both present — check order: base must come before project
    BASE_LINE_NUM=$(grep -nF "protocol-base.md" "$CLAUDE_MD" | head -1 | cut -d: -f1)
    PROJECT_LINE_NUM=$(grep -nF "$PROJECT_LINE" "$CLAUDE_MD" | head -1 | cut -d: -f1)
    if [[ $BASE_LINE_NUM -gt $PROJECT_LINE_NUM ]]; then
      # Wrong order — remove base, re-insert before project
      grep -vF "protocol-base.md" "$CLAUDE_MD" > "$CLAUDE_MD.tmp"
      sed "/$PROJECT_LINE/i\\
$BASE_LINE" "$CLAUDE_MD.tmp" > "$CLAUDE_MD"
      rm -f "$CLAUDE_MD.tmp"
      echo "CLAUDE.md: reordered — moved protocol-base.md before project protocol.md"
    else
      echo "CLAUDE.md: both present in correct order, no changes"
    fi
  elif [[ "$HAS_PROJECT" == "true" && "$HAS_BASE" == "false" ]]; then
    # Has project but missing base — insert base BEFORE project line
    sed -i '' "s|$PROJECT_LINE|$BASE_LINE\\
$PROJECT_LINE|" "$CLAUDE_MD"
    echo "CLAUDE.md: inserted protocol-base.md before existing project protocol"
  elif [[ "$HAS_BASE" == "true" && "$HAS_PROJECT" == "false" ]]; then
    # Has base but missing project — append project AFTER base line
    sed -i '' "/protocol-base.md/a\\
$PROJECT_LINE" "$CLAUDE_MD"
    echo "CLAUDE.md: appended project protocol.md after existing base"
  else
    # Neither present — append both in correct order
    echo "$BASE_LINE" >> "$CLAUDE_MD"
    echo "$PROJECT_LINE" >> "$CLAUDE_MD"
    echo "CLAUDE.md: added both injections (base then project)"
  fi
else
  echo "Warning: CLAUDE.md not found at $CLAUDE_MD — manual injection needed"
fi

echo ""
echo "Migration complete. Verify:"
echo "  1. cat $PROTOCOL"
echo "  2. cat $CLAUDE_MD"
echo "  3. New session should load both protocol-base.md and protocol.md"

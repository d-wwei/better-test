#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
TMP_DIR="$(mktemp -d)"
HOME_DIR="$TMP_DIR/home"
ENTRY_LINK="$TMP_DIR/better-test-entry"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$HOME_DIR/.claude/skills" "$HOME_DIR/.codex/skills" "$HOME_DIR/.agents/skills"
ln -s "$REPO_ROOT" "$ENTRY_LINK"

INSTALL_OUT=$(HOME="$HOME_DIR" "$ENTRY_LINK/install.sh")
STATUS_OUT=$(HOME="$HOME_DIR" "$ENTRY_LINK/install.sh" status)

for link in \
  "$HOME_DIR/.claude/skills/better-test" \
  "$HOME_DIR/.codex/skills/better-test" \
  "$HOME_DIR/.agents/skills/better-test"
do
  if [[ ! -L "$link" ]]; then
    echo "installer did not create managed symlink: $link" >&2
    exit 1
  fi
  resolved=$(cd "$link" && pwd -P)
  if [[ "$resolved" != "$REPO_ROOT" ]]; then
    echo "installer linked $link to $resolved instead of canonical $REPO_ROOT" >&2
    exit 1
  fi
done

printf '%s\n' "$INSTALL_OUT" | grep -F "canonical source: $REPO_ROOT" >/dev/null
printf '%s\n' "$STATUS_OUT" | grep -F "source revision: $(git -C "$REPO_ROOT" rev-parse HEAD)" >/dev/null
printf '%s\n' "$STATUS_OUT" | grep -F "Linked platforms: claude-code, codex, codex-canonical" >/dev/null

HOME="$HOME_DIR" "$ENTRY_LINK/install.sh" uninstall >/dev/null
for link in \
  "$HOME_DIR/.claude/skills/better-test" \
  "$HOME_DIR/.codex/skills/better-test" \
  "$HOME_DIR/.agents/skills/better-test"
do
  if [[ -e "$link" || -L "$link" ]]; then
    echo "installer did not remove managed symlink: $link" >&2
    exit 1
  fi
done

echo "install provenance tests passed"

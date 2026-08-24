#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/scripts/macos-credential-broker.c"
INSTALL_DIR="${BETTER_TEST_BROKER_DIR:-$HOME/.local/libexec/better-test}"
TARGET="$INSTALL_DIR/macos-credential-broker"
TMP="$(mktemp "${TMPDIR:-/tmp}/macos-credential-broker.XXXXXX")"
trap 'if [ -e "$TMP" ]; then unlink "$TMP"; fi' EXIT

mkdir -p "$INSTALL_DIR"
chmod 700 "$INSTALL_DIR"
clang -O2 -Wall -Wextra -Werror \
  -Wno-deprecated-declarations \
  -framework Security -framework CoreFoundation \
  "$SOURCE" -o "$TMP"
chmod 700 "$TMP"
mv "$TMP" "$TARGET"
trap - EXIT

"$TARGET" self-test
printf 'installed=%s\n' "$TARGET"

#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/better-test-broker-test.XXXXXX")"
INSTALL_DIR="$TMP_ROOT/install"
BAD_DIR="$TMP_ROOT/bad-lease"
GOOD_DIR="$TMP_ROOT/good-lease"

cleanup() {
  if [ -e "$INSTALL_DIR/macos-credential-broker" ]; then
    unlink "$INSTALL_DIR/macos-credential-broker"
  fi
  for dir in "$INSTALL_DIR" "$BAD_DIR" "$GOOD_DIR" "$TMP_ROOT"; do
    if [ -d "$dir" ]; then
      rmdir "$dir"
    fi
  done
}
trap cleanup EXIT

BETTER_TEST_BROKER_DIR="$INSTALL_DIR" \
  "$ROOT/scripts/install-macos-credential-broker.sh" >/dev/null
BROKER="$INSTALL_DIR/macos-credential-broker"

"$BROKER" self-test | jq -e \
  '.status == "PASS" and .cross_process_read == true' >/dev/null
"$BROKER" status missing-test-profile | jq -e \
  '(.login_account == false) and
   (.login_password == false) and
   (.trade_password == false)' >/dev/null

mkdir "$BAD_DIR"
chmod 755 "$BAD_DIR"
if "$BROKER" materialize-login missing-test-profile "$BAD_DIR" \
  >/dev/null 2>&1
then
  echo "unsafe lease directory unexpectedly accepted" >&2
  exit 1
fi

mkdir "$GOOD_DIR"
chmod 700 "$GOOD_DIR"
if "$BROKER" materialize-login missing-test-profile "$GOOD_DIR" \
  >/dev/null 2>&1
then
  echo "missing profile unexpectedly materialized" >&2
  exit 1
fi

if "$BROKER" status 'invalid/profile' >/dev/null 2>&1; then
  echo "invalid profile_id unexpectedly accepted" >&2
  exit 1
fi

echo "macOS credential broker tests passed"

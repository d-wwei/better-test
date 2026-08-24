#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
. "$ROOT/hooks/lib/common.sh"

CWD="${1:-$PWD}"
TEST_ROOT="$(bt_resolve_test_dir "$CWD")" || {
  echo "better-test: unable to resolve the project test root from $CWD" >&2
  exit 2
}

printf '%s\n' "$TEST_ROOT"

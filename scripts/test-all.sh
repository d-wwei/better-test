#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INCLUDE_RUNTIME=false

if [[ "${1:-}" == "--include-runtime" ]]; then
  INCLUDE_RUNTIME=true
elif [[ "$#" -ne 0 ]]; then
  echo "usage: $0 [--include-runtime]" >&2
  exit 64
fi

passed=0
for test_script in "$ROOT_DIR"/hooks/test-*.sh; do
  if [[ "$test_script" == */test-codex-runtime.sh && "$INCLUDE_RUNTIME" != "true" ]]; then
    continue
  fi
  echo "RUN $(basename "$test_script")"
  bash "$test_script"
  passed=$((passed + 1))
done

echo "PASS: $passed test suites"
if [[ "$INCLUDE_RUNTIME" != "true" ]]; then
  echo "NOTE: authenticated test-codex-runtime.sh is a manual release gate"
fi

#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

PROJECT="$TMP_DIR/project"
mkdir -p "$PROJECT/test/history" "$PROJECT/.better-work/test"
printf 'test\n' >"$PROJECT/.better-test-root"
printf '# protocol\n' >"$PROJECT/test/protocol.md"
printf '# groups\n' >"$PROJECT/test/test-groups.md"

RESOLVED="$("$ROOT/scripts/resolve-test-root.sh" "$PROJECT")"
EXPECTED="$(cd "$PROJECT/test" && pwd -P)"
LEGACY="$(cd "$PROJECT/.better-work/test" && pwd -P)"

if [[ "$RESOLVED" != "$EXPECTED" ]]; then
  echo "marker did not win over legacy directory: $RESOLVED" >&2
  exit 1
fi
if [[ "$RESOLVED" == "$LEGACY" ]]; then
  echo "resolver selected the empty legacy directory" >&2
  exit 1
fi

rm "$PROJECT/.better-test-root"
RESOLVED="$("$ROOT/scripts/resolve-test-root.sh" "$PROJECT")"
if [[ "$RESOLVED" != "$LEGACY" ]]; then
  echo "default legacy layout no longer resolves without a marker" >&2
  exit 1
fi

CORE_WORKFLOWS=(
  "$ROOT/protocol-base.md"
  "$ROOT/references/init-workflow.md"
  "$ROOT/references/strategy-workflow.md"
  "$ROOT/references/test-execution-workflow.md"
  "$ROOT/references/protocol-update-workflow.md"
  "$ROOT/references/progress-workflow.md"
  "$ROOT/references/merge-workflow.md"
  "$ROOT/references/templates.md"
)
set +e
grep -n -E '\.better-work/test' "${CORE_WORKFLOWS[@]}" >"$TMP_DIR/literals.txt"
guard_rc=$?
set -e
if [[ "$guard_rc" -eq 0 ]]; then
  echo "Tier-1 workflow still hardcodes .better-work/test" >&2
  cat "$TMP_DIR/literals.txt" >&2
  exit 1
elif [[ "$guard_rc" -ge 2 ]]; then
  echo "Tier-1 workflow literal guard failed (exit $guard_rc)" >&2
  exit 1
fi

echo "test root resolution precedence passed"

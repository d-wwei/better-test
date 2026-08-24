#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VALIDATOR="$ROOT_DIR/scripts/validate-reference-suite-map.py"
VALID="$ROOT_DIR/hooks/fixtures/reference-suite-map-valid.json"
MISSING_COMMIT="$ROOT_DIR/hooks/fixtures/reference-suite-map-missing-commit.json"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

expect_failure() {
  local label="$1"
  local expected="$2"
  local fixture="$3"
  if python3 "$VALIDATOR" "$fixture" >"$TMP_DIR/$label.out" 2>"$TMP_DIR/$label.err"; then
    echo "$label unexpectedly passed" >&2
    exit 1
  fi
  grep -F "$expected" "$TMP_DIR/$label.err" >/dev/null
}

python3 "$VALIDATOR" "$VALID" >"$TMP_DIR/valid.out"
grep -F "reference suite map validation passed" "$TMP_DIR/valid.out" >/dev/null

cp -R "$ROOT_DIR/hooks/fixtures/reference-suite-project" "$TMP_DIR/project"
git -C "$TMP_DIR/project" init -q
git -C "$TMP_DIR/project" config user.email fixture@example.invalid
git -C "$TMP_DIR/project" config user.name fixture
git -C "$TMP_DIR/project" add .
git -C "$TMP_DIR/project" commit -qm initial
python3 "$ROOT_DIR/scripts/build-reference-suite-map.py" \
  --repo "$TMP_DIR/project" \
  --suite-id transitive-write \
  --repo-url git@example.invalid:fixture/reference-suite.git \
  --branch main \
  --commit "$(git -C "$TMP_DIR/project" rev-parse HEAD)" \
  --test-root testcases \
  --generated-at 2026-08-14T09:00:00+08:00 \
  --output "$TMP_DIR/transitive-map.json" >/dev/null
jq -e '
  ([.cases[] | select(.function == "test_write_through_helper")][0] |
    .side_effect == "write" and
    .execution_level == "L4" and
    (.call_names | index("place_order"))) and
  ([.cases[] | select(.function == "test_dynamic_skip")][0].skip_categories |
    index("data_unavailable"))
' "$TMP_DIR/transitive-map.json" >/dev/null

expect_failure \
  "missing-commit" \
  "suite.commit: expected a 40-character lowercase git SHA" \
  "$MISSING_COMMIT"

python3 - "$VALID" "$TMP_DIR/duplicate-case.json" <<'PY'
from pathlib import Path
import json
import sys

document = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
document["cases"].append(dict(document["cases"][0]))
document["summary"]["static_tests"] = 2
document["summary"]["cases"] = 2
document["summary"]["side_effects"]["read"] = 2
document["summary"]["adoption_statuses"]["adapted"] = 2
Path(sys.argv[2]).write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")
PY
expect_failure \
  "duplicate-case" \
  "cases: duplicate id" \
  "$TMP_DIR/duplicate-case.json"

python3 - "$VALID" "$TMP_DIR/bad-summary.json" <<'PY'
from pathlib import Path
import json
import sys

document = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
document["summary"]["cases"] = 2
Path(sys.argv[2]).write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")
PY
expect_failure \
  "bad-summary" \
  "summary.cases: expected 1, got 2" \
  "$TMP_DIR/bad-summary.json"

python3 - "$VALID" "$TMP_DIR/incomplete-danger-scan.json" <<'PY'
from pathlib import Path
import json
import sys

document = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
document["danger_scan"]["completed"] = False
Path(sys.argv[2]).write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")
PY
expect_failure \
  "incomplete-danger-scan" \
  "danger_scan.completed: must be true before activation" \
  "$TMP_DIR/incomplete-danger-scan.json"

echo "reference suite map tests passed"

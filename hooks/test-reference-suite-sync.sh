#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VALID="$ROOT_DIR/hooks/fixtures/reference-suite-map-valid.json"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

cp "$VALID" "$TMP_DIR/old.json"
python3 - "$VALID" "$TMP_DIR/new.json" <<'PY'
from pathlib import Path
import json
import sys

document = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
document["suite"]["commit"] = "b" * 40
document["cases"][0]["markers"].append("prelaunch")
document["cases"][0]["source_hash"] = "b" * 64
new_case = dict(document["cases"][0])
new_case["id"] = "testcases/quote/test_global.py::TestGlobal::test_second"
new_case["function"] = "test_second"
new_case["target_test_ids"] = ["Q-GLOBAL-002"]
document["cases"].append(new_case)
document["summary"]["static_tests"] = 2
document["summary"]["cases"] = 2
document["summary"]["side_effects"]["read"] = 2
document["summary"]["adoption_statuses"]["adapted"] = 2
Path(sys.argv[2]).write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")
PY

python3 "$ROOT_DIR/scripts/sync-reference-suite.py" \
  "$TMP_DIR/old.json" "$TMP_DIR/new.json" --output "$TMP_DIR/diff.json"
jq -e '
  .summary.added == 1 and
  .summary.removed == 0 and
  .summary.changed == 1 and
  .new.commit == ("b" * 40) and
  (.changed[0].fields | index("markers")) and
  (.changed[0].fields | index("source_hash"))
' "$TMP_DIR/diff.json" >/dev/null

if python3 "$ROOT_DIR/scripts/sync-reference-suite.py" \
  "$TMP_DIR/old.json" "$TMP_DIR/new.json" --fail-on-drift >/dev/null 2>&1
then
  echo "drift unexpectedly passed fail-on-drift" >&2
  exit 1
fi

python3 "$ROOT_DIR/scripts/project-reference-suite-intents.py" \
  "$TMP_DIR/new.json" --output "$TMP_DIR/intents.md"
grep -F "Q-GLOBAL-001" "$TMP_DIR/intents.md" >/dev/null
grep -F "Q-GLOBAL-002" "$TMP_DIR/intents.md" >/dev/null
grep -F "## global" "$TMP_DIR/intents.md" >/dev/null

echo "reference suite sync and intent tests passed"

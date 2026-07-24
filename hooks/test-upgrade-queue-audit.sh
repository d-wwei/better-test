#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VALIDATOR="$ROOT_DIR/scripts/audit-upgrade-queue.py"
QUEUE="$ROOT_DIR/references/pending-skill-upgrades.md"
TMP_QUEUE="$(mktemp "${TMPDIR:-/tmp}/better-test-upgrade-queue.XXXXXX")"
trap 'rm -f "$TMP_QUEUE"' EXIT

python3 "$VALIDATOR" "$QUEUE" --today 2026-07-24 >/dev/null

python3 - "$QUEUE" "$TMP_QUEUE" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text(encoding="utf-8")
source = source.replace(
    "- **状态**: promoted 2026-06-11",
    "- **状态**: pilot 2026-06-11",
    1,
)
Path(sys.argv[2]).write_text(source, encoding="utf-8")
PY

if python3 "$VALIDATOR" "$TMP_QUEUE" --today 2026-07-24 >/dev/null 2>&1; then
  echo "FAIL: pilot without review deadline was accepted" >&2
  exit 1
fi

python3 - "$QUEUE" "$TMP_QUEUE" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text(encoding="utf-8")
source = source.replace(
    "- **状态**: promoted 2026-06-11",
    "- **复核期限**: 2026-06-12\n- **状态**: pilot 2026-06-11",
    1,
)
Path(sys.argv[2]).write_text(source, encoding="utf-8")
PY
if python3 "$VALIDATOR" "$TMP_QUEUE" --today 2026-07-24 >/dev/null 2>&1; then
  echo "FAIL: expired pilot was accepted" >&2
  exit 1
fi

python3 - "$QUEUE" "$TMP_QUEUE" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text(encoding="utf-8")
late = []
for index in range(5):
    late.append(
        f"\n### [2026-07-{19 + index:02d}] Late pending {index}\n"
        "- **状态**: pending\n"
    )
Path(sys.argv[2]).write_text(source + "".join(late), encoding="utf-8")
PY
if python3 "$VALIDATOR" "$TMP_QUEUE" --today 2026-07-24 >/dev/null 2>&1; then
  echo "FAIL: pending records appended after batch ledgers were ignored" >&2
  exit 1
fi

python3 - "$QUEUE" "$TMP_QUEUE" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text(encoding="utf-8")
source += (
    "\n### [2026-99-99] Invalid heading date\n"
    "- **状态**: rejected 2026-07-24（invalid date test）\n"
)
Path(sys.argv[2]).write_text(source, encoding="utf-8")
PY
if python3 "$VALIDATOR" "$TMP_QUEUE" --today 2026-07-24 >/dev/null 2>&1; then
  echo "FAIL: invalid queue heading date was ignored" >&2
  exit 1
fi

python3 - "$QUEUE" "$TMP_QUEUE" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text(encoding="utf-8")
source = source.replace(
    "- **状态**: promoted 2026-06-11",
    "- **状态**: promoted whatever",
    1,
)
Path(sys.argv[2]).write_text(source, encoding="utf-8")
PY
if python3 "$VALIDATOR" "$TMP_QUEUE" --today 2026-07-24 >/dev/null 2>&1; then
  echo "FAIL: final status without date and landing detail was accepted" >&2
  exit 1
fi

python3 - "$QUEUE" "$TMP_QUEUE" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text(encoding="utf-8")
source = source.replace(
    "- **状态**: promoted 2026-06-11",
    "- **状态**: approved 2026-06-11",
    1,
)
Path(sys.argv[2]).write_text(source, encoding="utf-8")
PY
if python3 "$VALIDATOR" "$TMP_QUEUE" --today 2026-07-24 >/dev/null 2>&1; then
  echo "FAIL: persistent approved state bypassed atomic promotion" >&2
  exit 1
fi

python3 - "$QUEUE" "$TMP_QUEUE" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text(encoding="utf-8")
source += (
    "\n#### [2026-07-24] Hidden pending with malformed heading\n"
    "- **状态**: pending\n"
)
Path(sys.argv[2]).write_text(source, encoding="utf-8")
PY
if python3 "$VALIDATOR" "$TMP_QUEUE" --today 2026-07-24 >/dev/null 2>&1; then
  echo "FAIL: malformed queue heading hid a pending status line" >&2
  exit 1
fi

echo "skill upgrade queue audit passed"

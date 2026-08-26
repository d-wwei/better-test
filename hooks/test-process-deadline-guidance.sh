#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUIDE="$ROOT_DIR/references/procedures/subprocess-deadline-triage.md"

grep -F 'TEST-INFRA candidate' "$GUIDE" >/dev/null
grep -F 'direct binary/control' "$GUIDE" >/dev/null
grep -F 'condition-based polling' "$GUIDE" >/dev/null
grep -F 'unconditional unwrap' "$GUIDE" >/dev/null
grep -F '受控负载' "$GUIDE" >/dev/null

echo "subprocess deadline triage guidance passed"

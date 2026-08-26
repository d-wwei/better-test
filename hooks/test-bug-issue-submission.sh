#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUBMITTER="$ROOT_DIR/scripts/submit-bug-issues.py"
BUILDER="$ROOT_DIR/scripts/build-full-report.py"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/better-test-bug-issues.XXXXXX")"
RUN_DIR="$TMP_DIR/run-codex-a3f2-issue"
POLICY="$TMP_DIR/policy/policy.json"
FAKE_BIN="$TMP_DIR/bin"
FAKE_STATE="$TMP_DIR/fake-gh-state.json"
CREATE_COUNT="$TMP_DIR/create-count"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$RUN_DIR/bugs" "$RUN_DIR/artifacts" "$FAKE_BIN" "$(dirname "$POLICY")"
cp "$ROOT_DIR/hooks/fixtures/artifacts/"* "$RUN_DIR/artifacts/"
cp "$ROOT_DIR/fixtures/providers/project-profile-valid.json" \
  "$(dirname "$POLICY")/project-profile.json"

jq '
  .run_id = "run-codex-a3f2-issue"
  | .items += [(
      .items[0]
      | .id = "AUTH-SLOW-01"
      | .name = "slow authentication handshake"
      | .status = "fail"
      | .bug_ids = ["BUG-001"]
      | .evidence_sources[0].source_id = "SRC-SLOW-DAEMON-01"
      | .evidence_sources[1].source_id = "SRC-SLOW-CLIENT-01"
    )]
  | .dod.verdict = "fail"
  | .dod.check_results += [{
      check_id: "confirmed-bug",
      verdict: "fail",
      reason: "The confirmed bug blocks the contract.",
      item_ids: ["AUTH-SLOW-01"],
      gate_ids: [],
      evidence_refs: ["SRC-SLOW-DAEMON-01", "SRC-SLOW-CLIENT-01"]
    }]
  | .release_readiness = {verdict:"no-go"}
  | .summary.total = 2
  | .summary.passed = 1
  | .summary.failed = 1
  | .coverage.manifest_total = 2
  | .coverage.reachable = 2
  | .coverage.tested = 2
' "$ROOT_DIR/hooks/fixtures/results-v3-valid.json" >"$RUN_DIR/results.json"

cat >"$RUN_DIR/summary.md" <<'EOF'
# Test Summary

One confirmed authentication bug is open.
EOF

cat >"$RUN_DIR/bugs/BUG-001-auth-timeout.md" <<'EOF'
# BUG-001: auth timeout

## 1. TL;DR
Slow network authentication times out and blocks the user session.

## 2. 现象矩阵
| Network | Result |
|---|---|
| Normal | PASS |
| Slow fixture | FAIL |

## 3. 基准对照
The reference implementation completes the same slow handshake.

## 4. 其他对照
Both minimal and complete request variants reproduce the failure; order_id_ex=0
is a safe sentinel, not a real order identity.

## 5. 权限/账号排除
The sanitized test profile succeeds against the reference implementation.

## 6. Root cause 推测
Evidence is confirmed; the timeout window does not cover the slow handshake.

## 7. 复现步骤
Run the synthetic slow-network fixture and start the first-party login flow.

## 8. 影响评估
Slow-network users cannot establish a session. Severity is P1.

```yaml
bug:
  id: BUG-001
  title: auth timeout on slow handshake
  status: CONFIRMED
  severity: P1
  evidence_level: confirmed
  evidence_refs: [SRC-DAEMON-LOG-01, SRC-CLIENT-JSON-01]
  bug_type: environment
  affected_groups: [AUTH]
  affected_scenarios: [slow-network]
  found_in: v1.1.0
  found_by_tester: codex-a3f2
  found_by_run: run-codex-a3f2-issue
  related_tests: [AUTH-READY-01]
  version_found: v1.1.0
  version_fixed: null
  regression_canary: true
  post_ship: false
  escape_id: null
  submission_key: auth-slow-handshake-timeout
```
EOF

cat >"$POLICY" <<'EOF'
{
  "schema_version": 1,
  "provider": "github",
  "repository": "example/project",
  "enabled": true,
  "eligible_statuses": ["OPEN", "CONFIRMED"],
  "eligible_evidence_levels": ["confirmed", "proven"],
  "labels": ["bug"],
  "require_submission_key": true,
  "require_full_report": true,
  "require_results_validation": true,
  "title_template": "[{version_found}] {title}",
  "body_preamble": "这是通过机器门禁校验的完整 Bug Report。",
  "report_names": ["FULL-TEST-REPORT.md"],
  "ledger_name": "bug-issue-submissions.json",
  "max_body_bytes": 60000,
  "project_profile": "project-profile.json",
  "redaction": {
    "block_emails": true,
    "block_nonlocal_ips": true,
    "additional_patterns": []
  }
}
EOF

python3 "$BUILDER" --run-dir "$RUN_DIR" \
  --output "$RUN_DIR/FULL-TEST-REPORT.md"

python3 "$SUBMITTER" --run-dir "$RUN_DIR" --policy "$POLICY" \
  --validate-only --offline >"$TMP_DIR/validate.json"
jq -e '.eligible_count == 1 and .planned[0].bug_id == "BUG-001"' \
  "$TMP_DIR/validate.json" >/dev/null

cp "$RUN_DIR/bugs/BUG-001-auth-timeout.md" "$TMP_DIR/bug-clean.md"
python3 - "$RUN_DIR/bugs/BUG-001-auth-timeout.md" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
path.write_text(
    text.replace("  evidence_level: confirmed\n", "  evidence_level: direct\n", 1),
    encoding="utf-8",
)
PY
python3 "$BUILDER" --run-dir "$RUN_DIR" \
  --output "$RUN_DIR/FULL-TEST-REPORT.md"
python3 "$SUBMITTER" --run-dir "$RUN_DIR" --policy "$POLICY" \
  --validate-only --offline >"$TMP_DIR/direct-skip.json"
jq -e '
  .eligible_count == 0
  and (.skipped[0].reason | contains("evidence_level=direct"))
' "$TMP_DIR/direct-skip.json" >/dev/null
cp "$TMP_DIR/bug-clean.md" "$RUN_DIR/bugs/BUG-001-auth-timeout.md"

python3 - "$RUN_DIR/bugs/BUG-001-auth-timeout.md" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
path.write_text(
    text.replace(
        "Run the synthetic slow-network fixture",
        "Run with --acc-id 281756478825151816 and the synthetic fixture",
        1,
    ),
    encoding="utf-8",
)
PY
python3 "$BUILDER" --run-dir "$RUN_DIR" \
  --output "$RUN_DIR/FULL-TEST-REPORT.md"
set +e
output="$(python3 "$SUBMITTER" --run-dir "$RUN_DIR" --policy "$POLICY" \
  --validate-only --offline 2>&1)"
rc=$?
set -e
if [[ "$rc" -eq 0 || "$output" != *"sensitive CLI identifier"* ]]; then
  echo "FAIL: account identifier was not blocked" >&2
  printf '%s\n' "$output" >&2
  exit 1
fi
cp "$TMP_DIR/bug-clean.md" "$RUN_DIR/bugs/BUG-001-auth-timeout.md"

python3 - "$RUN_DIR/bugs/BUG-001-auth-timeout.md" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
path.write_text(
    text.replace(
        "Run the synthetic slow-network fixture",
        "Run the synthetic fixture with 账号：900048",
        1,
    ),
    encoding="utf-8",
)
PY
python3 "$BUILDER" --run-dir "$RUN_DIR" \
  --output "$RUN_DIR/FULL-TEST-REPORT.md"
set +e
output="$(python3 "$SUBMITTER" --run-dir "$RUN_DIR" --policy "$POLICY" \
  --validate-only --offline 2>&1)"
rc=$?
set -e
if [[ "$rc" -eq 0 || "$output" != *"localized sensitive identifier"* ]]; then
  echo "FAIL: localized account identifier was not blocked" >&2
  printf '%s\n' "$output" >&2
  exit 1
fi
cp "$TMP_DIR/bug-clean.md" "$RUN_DIR/bugs/BUG-001-auth-timeout.md"
python3 "$BUILDER" --run-dir "$RUN_DIR" \
  --output "$RUN_DIR/FULL-TEST-REPORT.md"

cat >"$FAKE_BIN/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "$1" == "auth" && "$2" == "status" ]]; then
  exit 0
fi
if [[ "$1" == "repo" && "$2" == "view" ]]; then
  printf '{"viewerPermission":"WRITE","hasIssuesEnabled":true}\n'
  exit 0
fi
if [[ "$1" == "api" && " $* " == *" --paginate "* ]]; then
  if [[ -s "$FAKE_GH_STATE" ]]; then
    body="$(jq -r '.body' "$FAKE_GH_STATE")"
    jq -n --arg body "$body" \
      '[[{number:42,html_url:"https://github.com/example/project/issues/42",state:"open",body:$body}]]'
  else
    printf '[[]]\n'
  fi
  exit 0
fi
if [[ "$1" == "api" && " $* " == *" --method POST "* ]]; then
  sleep "${FAKE_GH_CREATE_DELAY:-0}"
  cat >"$FAKE_GH_STATE"
  count=0
  [[ -f "$FAKE_GH_CREATE_COUNT" ]] && count="$(cat "$FAKE_GH_CREATE_COUNT")"
  printf '%s\n' "$((count + 1))" >"$FAKE_GH_CREATE_COUNT"
  jq -n \
    '{number:42,html_url:"https://github.com/example/project/issues/42",state:"open"}'
  exit 0
fi
echo "unexpected fake gh call: $*" >&2
exit 2
EOF
chmod +x "$FAKE_BIN/gh"

PATH="$FAKE_BIN:$PATH" \
FAKE_GH_STATE="$FAKE_STATE" \
FAKE_GH_CREATE_COUNT="$CREATE_COUNT" \
python3 "$SUBMITTER" --run-dir "$RUN_DIR" --policy "$POLICY" --submit \
  >"$TMP_DIR/submit.json"
jq -e '.submitted[0].status == "created" and .submitted[0].issue_number == 42' \
  "$TMP_DIR/submit.json" >/dev/null
jq -e '
  .submissions["auth-slow-handshake-timeout"].issue_number == 42
  and .submissions["auth-slow-handshake-timeout"].submission_fingerprint
' "$RUN_DIR/bug-issue-submissions.json" >/dev/null
jq -e '
  (.body | contains("Slow network authentication times out"))
  and (.body | contains("better-test-bug-fingerprint"))
  and (.body | contains("这是通过机器门禁校验的完整 Bug Report。"))
' "$FAKE_STATE" >/dev/null

rm "$RUN_DIR/bug-issue-submissions.json"
PATH="$FAKE_BIN:$PATH" \
FAKE_GH_STATE="$FAKE_STATE" \
FAKE_GH_CREATE_COUNT="$CREATE_COUNT" \
python3 "$SUBMITTER" --run-dir "$RUN_DIR" --policy "$POLICY" --submit \
  >"$TMP_DIR/dedupe.json"
jq -e '.submitted[0].status == "linked_existing"' \
  "$TMP_DIR/dedupe.json" >/dev/null
[[ "$(cat "$CREATE_COUNT")" == "1" ]] || {
  echo "FAIL: duplicate issue was created" >&2
  exit 1
}

rm -f "$RUN_DIR/bug-issue-submissions.json" "$FAKE_STATE"
printf '0\n' >"$CREATE_COUNT"
PATH="$FAKE_BIN:$PATH" \
FAKE_GH_STATE="$FAKE_STATE" \
FAKE_GH_CREATE_COUNT="$CREATE_COUNT" \
FAKE_GH_CREATE_DELAY=1 \
python3 "$SUBMITTER" --run-dir "$RUN_DIR" --policy "$POLICY" --submit \
  >"$TMP_DIR/concurrent-1.json" &
pid1=$!
PATH="$FAKE_BIN:$PATH" \
FAKE_GH_STATE="$FAKE_STATE" \
FAKE_GH_CREATE_COUNT="$CREATE_COUNT" \
FAKE_GH_CREATE_DELAY=1 \
python3 "$SUBMITTER" --run-dir "$RUN_DIR" --policy "$POLICY" --submit \
  >"$TMP_DIR/concurrent-2.json" &
pid2=$!
wait "$pid1"
wait "$pid2"
[[ "$(cat "$CREATE_COUNT")" == "1" ]] || {
  echo "FAIL: concurrent submit created duplicate issues" >&2
  exit 1
}
jq -s -e '
  ([.[].submitted[0].status] | sort)
  == ["created", "linked_existing"]
' "$TMP_DIR/concurrent-1.json" "$TMP_DIR/concurrent-2.json" >/dev/null

if [[ "${BUG_ISSUE_REAL_DRY_RUN:-0}" == "1" ]]; then
  if [[ -n "${BUG_ISSUE_REAL_POLICY:-}" ]]; then
    cp "$BUG_ISSUE_REAL_POLICY" "$TMP_DIR/real-policy.json"
  else
    jq '.repository = "futuleaf/futu-opend-rs"' \
      "$POLICY" >"$TMP_DIR/real-policy.json"
  fi
  python3 "$SUBMITTER" --run-dir "$RUN_DIR" \
    --policy "$TMP_DIR/real-policy.json" --dry-run \
    >"$TMP_DIR/real-dry-run.json"
  jq -e '
    .repository == "futuleaf/futu-opend-rs"
    and .mode == "dry-run"
    and .eligible_count == 1
    and (.planned | length) == 1
  ' "$TMP_DIR/real-dry-run.json" >/dev/null
fi

echo "bug issue submission tests passed"

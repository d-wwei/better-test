#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$SCRIPT_DIR/codex/stop-gate.sh"
TMP_DIR="$(mktemp -d)"
PROJECT_DIR="$TMP_DIR/project"
TEST_ROOT="$PROJECT_DIR/.better-work/test"
HOME_DIR="$TMP_DIR/home"
CODEX_HOME_DIR="$HOME_DIR/.codex"
STATE_DIR="$TMP_DIR/state"
LOG_FILE="$TMP_DIR/stop-gate.log"
INVALID_RUN="$TEST_ROOT/history/v1/run-codex-a3f2-001-invalid"
VALID_RUN="$TEST_ROOT/history/v1/run-codex-a3f2-002-valid"
ACTIVE_DIR="$TEST_ROOT/.active-sessions"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$ACTIVE_DIR" "$INVALID_RUN" "$VALID_RUN" "$CODEX_HOME_DIR" "$STATE_DIR"
git -C "$PROJECT_DIR" init -q
cat >"$TEST_ROOT/protocol.md" <<'EOF'
# protocol
EOF
cat >"$TEST_ROOT/test-groups.md" <<'EOF'
# groups
EOF
cat >"$INVALID_RUN/strategy-plan.md" <<'EOF'
---
status: completed
---
EOF

cp "$SCRIPT_DIR/fixtures/results-v3-valid.json" "$VALID_RUN/results.json"
cp -R "$SCRIPT_DIR/fixtures/artifacts" "$VALID_RUN/artifacts"
cat >"$VALID_RUN/intake.json" <<'EOF'
{
  "schema_version": 1,
  "intake_id": "intake-stop-gate-valid",
  "produced_by": "fixture",
  "attested_at": "2026-08-24T14:30:00+08:00",
  "subjects": [
    {
      "id": "source",
      "type": "source",
      "identity": {"commit": "fixture", "dirty": false}
    }
  ],
  "relations": []
}
EOF
INTAKE_SHA="$(shasum -a 256 "$VALID_RUN/intake.json" | awk '{print $1}')"
jq --arg sha "$INTAKE_SHA" \
  '.intake_ref={intake_id:"intake-stop-gate-valid",sha256:$sha}' \
  "$VALID_RUN/results.json" >"$VALID_RUN/results.next"
mv "$VALID_RUN/results.next" "$VALID_RUN/results.json"
cat >"$VALID_RUN/summary.md" <<'EOF'
# Test summary

The fixture run passed.
EOF
python3 "$ROOT_DIR/scripts/build-full-report.py" \
  --run-dir "$VALID_RUN" \
  --output "$VALID_RUN/FULL-TEST-REPORT.md"
cp "$VALID_RUN/results.json" "$TMP_DIR/results-valid.json"

write_session() {
  local run_rel="$1"
  cat >"$ACTIVE_DIR/$$.json" <<EOF
{"tester_id":"codex-a3f2","run_dir":"$run_rel"}
EOF
  cat >"$ACTIVE_DIR/$PPID.json" <<EOF
{"tester_id":"codex-a3f2","run_dir":"$run_rel"}
EOF
}

run_hook() {
  local turn_id="$1"
  local cwd="${2:-$PROJECT_DIR}"
  jq -n \
    --arg cwd "$cwd" \
    --arg turn_id "$turn_id" \
    '{
      session_id:"session-stop-gate",
      turn_id:$turn_id,
      cwd:$cwd,
      hook_event_name:"Stop",
      stop_hook_active:false,
      last_assistant_message:"done"
    }' |
    HOME="$HOME_DIR" \
    BETTER_TEST_STOP_STATE_DIR="$STATE_DIR" \
    BETTER_TEST_STOP_LOG_FILE="$LOG_FILE" \
    "$HOOK"
}

write_session "history/v1/run-codex-a3f2-001-invalid"
for attempt in 1 2 3; do
  output=$(run_hook "turn-invalid")
  printf '%s' "$output" | jq -e \
    --arg attempt "$attempt" \
    '.decision == "block"
      and (.reason | contains("completion gate failed (" + $attempt + "/3)"))
      and (.reason | contains("missing results.json"))' >/dev/null
done

output=$(run_hook "turn-invalid")
if [[ -n "$output" ]]; then
  echo "fourth invalid Stop in one turn must be rate-limited open" >&2
  exit 1
fi
grep -Fq 'code=RATE_LIMITED_INVALID_RUN' "$LOG_FILE"

output=$(run_hook "turn-next")
printf '%s' "$output" | jq -e \
  '.decision == "block" and (.reason | contains("completion gate failed (1/3)"))' >/dev/null

write_session "history/v1/run-codex-a3f2-002-valid"
output=$(run_hook "turn-valid")
if [[ -n "$output" ]]; then
  echo "valid finalizing run was unexpectedly blocked" >&2
  printf '%s\n' "$output" >&2
  exit 1
fi
remaining_sessions=$(find "$ACTIVE_DIR" -maxdepth 1 -type f -name '*.json' | wc -l | tr -d ' ')
if [[ "$remaining_sessions" -ne 1 ]]; then
  echo "valid finalizing run did not clear exactly one matched active session file" >&2
  exit 1
fi

rm -f "$ACTIVE_DIR"/*.json
rm -f "$VALID_RUN/results.json"
output=$(run_hook "turn-valid")
printf '%s' "$output" | jq -e '
  .decision == "block"
  and (.reason | contains("missing results.json"))
' >/dev/null

cp "$TMP_DIR/results-valid.json" "$VALID_RUN/results.json"
UNSAFE_SESSION_FILE="$TMP_DIR/outside-session.json"
printf '%s\n' keep >"$UNSAFE_SESSION_FILE"
jq -n \
  --arg run_dir "$VALID_RUN" \
  --arg session_file "$UNSAFE_SESSION_FILE" \
  '{
    turn_id:"turn-tamper",
    run_dir:$run_dir,
    session_file:$session_file
  }' >"$STATE_DIR/better-test-stop-context-session-stop-gate.json"
output=$(run_hook "turn-tamper")
if [[ -n "$output" || ! -f "$UNSAFE_SESSION_FILE" ]]; then
  echo "tampered context caused an unexpected block or unsafe file deletion" >&2
  exit 1
fi
grep -Fq 'code=UNSAFE_SESSION_CLEANUP_PATH' "$LOG_FILE"

rm -f "$VALID_RUN/FULL-TEST-REPORT.md"
cat >"$VALID_RUN/strategy-plan.md" <<'EOF'
---
status: in-progress
---
EOF
write_session "history/v1/run-codex-a3f2-002-valid"
output=$(run_hook "turn-in-progress")
if [[ -n "$output" ]]; then
  echo "non-finalizing run was unexpectedly blocked" >&2
  exit 1
fi

write_session "history/v1/run-codex-a3f2-001-invalid"
output=$(BETTER_TEST_STOP_GATE=0 run_hook "turn-disabled")
if [[ -n "$output" ]]; then
  echo "BETTER_TEST_STOP_GATE=0 did not disable the gate" >&2
  exit 1
fi

output=$(BETTER_TEST_VALIDATE_RUN="$TMP_DIR/missing-validator.py" run_hook "turn-validator-error")
if [[ -n "$output" ]]; then
  echo "missing validator must fail open" >&2
  exit 1
fi
grep -Fq 'code=VALIDATOR_MISSING' "$LOG_FILE"

cat >"$TMP_DIR/crashing-validator.py" <<'EOF'
raise RuntimeError("intentional validator crash")
EOF
output=$(BETTER_TEST_VALIDATE_RUN="$TMP_DIR/crashing-validator.py" run_hook "turn-validator-crash")
if [[ -n "$output" ]]; then
  echo "crashing validator must fail open" >&2
  exit 1
fi
grep -Fq 'code=VALIDATOR_ERROR' "$LOG_FILE"

rm -f "$ACTIVE_DIR/$$.json" "$ACTIVE_DIR/$PPID.json"
output=$(run_hook "turn-no-active")
if [[ -n "$output" ]]; then
  echo "missing active run was unexpectedly blocked" >&2
  exit 1
fi
grep -Fq 'code=NO_ACTIVE_RUN' "$LOG_FILE"

NON_TEST_PROJECT="$TMP_DIR/non-test-project"
mkdir -p "$NON_TEST_PROJECT"
output=$(run_hook "turn-non-test" "$NON_TEST_PROJECT")
if [[ -n "$output" ]]; then
  echo "non-Better-Test project was unexpectedly blocked" >&2
  exit 1
fi

cat >"$CODEX_HOME_DIR/config.toml" <<'EOF'
[features]
hooks = true
EOF
cat >"$PROJECT_DIR/.codex-hooks-base.json" <<'EOF'
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "python3 /tmp/rnr-like-stop.py",
            "statusMessage": "foreign: rnr-like"
          }
        ]
      }
    ]
  }
}
EOF
mkdir -p "$PROJECT_DIR/.codex"
cp "$PROJECT_DIR/.codex-hooks-base.json" "$PROJECT_DIR/.codex/hooks.json"
HOME="$HOME_DIR" CODEX_HOME="$CODEX_HOME_DIR" \
  "$SCRIPT_DIR/install-codex-hooks.sh" install --project "$PROJECT_DIR" >/dev/null

jq -e '
  (.hooks.Stop | length) == 1
  and (.hooks.Stop[0] | has("matcher") | not)
  and any(.hooks.Stop[0].hooks[]?; (.statusMessage // "") == "foreign: rnr-like")
  and any(
    .hooks.Stop[0].hooks[]?;
    (.statusMessage // "") == "better-test: stop-gate"
    and .timeout == 30
  )
' "$PROJECT_DIR/.codex/hooks.json" >/dev/null

HOME="$HOME_DIR" CODEX_HOME="$CODEX_HOME_DIR" \
  "$SCRIPT_DIR/install-codex-hooks.sh" uninstall --project "$PROJECT_DIR" >/dev/null
jq -e '
  any(.hooks.Stop[]?.hooks[]?; (.statusMessage // "") == "foreign: rnr-like")
  and ([.hooks.Stop[]?.hooks[]? | select((.statusMessage // "") == "better-test: stop-gate")] | length) == 0
' "$PROJECT_DIR/.codex/hooks.json" >/dev/null

echo "stop gate tests passed"

# Synthetic fixture operation recipes — revision 1

This is sample project knowledge for copying into the resolved TEST_ROOT,
not an autoexecuted config or secondary registry. Variables below are supplied
by the actual harness/run. `BT_FIXTURE_ROOT` is the loaded worktree fixture path;
`BT_RUN_ID` is original registered run identity; `BT_OPERATION_DATA` is a fresh
owned absolute data directory under research run artifacts. No variable is a
guessed port/profile/PID. Read `README.md` for exact controls and source limits.

<a id="OP-NOTES-WEB"></a>
### OP-NOTES-WEB
recipe_revision: 1

#### Purpose

U-01..U-05 notes-v2 AC-1..5. Browser button/actual-OS shortcut, rejection,
overlapping trigger, cancel and persisted reopen. runner_ref names the actual
browser runner/tool trajectory; environment_ref uses this anchor.

#### Capability and tool choice

Use existing installed browser control in a dedicated context/profile, one
driver. Bind tool version/profile and confirm supported real click/key/field
reading/screenshot actions. No browser harness is bundled or installed here.
If that capability is absent, UI blocked; API only verifies fixture service.

#### Preconditions

Freeze notes-v2.md digest, fixture source/build, original intake/run/session,
allowed temporary data and resource owner. No real accounts/data. Different
worktrees cannot concurrently drive a shared browser. Empty fresh data for
independent U-01 and U-02; pilot uses a separate fresh resource path in same run.

#### Launch

Execution only, never init. Commands resolve identity from a real launch:

```bash
BT_ID_FILE="$BT_OPERATION_DATA/identity.json"
python3 "$BT_FIXTURE_ROOT/lifecycle.py" launch --data-dir "$BT_OPERATION_DATA" --identity "$BT_ID_FILE" --run-id "$BT_RUN_ID"
BT_ENDPOINT="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["endpoint"])' "$BT_ID_FILE")"
BT_DATABASE="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["database"])' "$BT_ID_FILE")"
```

Then open BT_ENDPOINT using the assigned isolated browser driver; actual host
API is selected and recorded by the harness. No guessed vendor API invocation.

#### Doctor

```bash
python3 "$BT_FIXTURE_ROOT/lifecycle.py" doctor --owner "$BT_RUN_ID" --identity "$BT_ID_FILE" --deadline 3
python3 "$BT_FIXTURE_ROOT/jobctl.py" snapshot --db "$BT_DATABASE"
```

Check page marker `better-test-synthetic-notes`, instance ID/PID/run/origin equal
receipt, own profile/tab, state clean. Stage 0 real save + DB snapshot is the
observer positive control; later zero-effect cases cannot pass without it.

#### Drive and Wait

Current observable New note → Title/Body → Save or actual-platform key. Wait
state saved with explicit 3s apparatus budget (no source SLA); preserve last
state on timeout. Close editor then saved-title list button reads stored fields.
For U-04 set note_response_delay=1, require two actual triggers between
note_reply_wait/note_reply, second ui_event submitting; final one row.
Reject all-space title and cancel draft by actual UI separately, not HTTP calls.

#### Observe and Evidence

Raw click/key trajectory, current DOM/AX/screenshot, request/response/time,
reopen Title/Body and independently read notes count/content. Preserve trace,
SQLite snapshot, identity and observer positive-control artifact in original run.
Success toast/HTTP alone never passes. No UI permission case is added.

#### Failure and Recovery

Doctor again and save failed browser state before owned profile reset. Stale
selector/current same-path control → TEST-INFRA/document drift; observer positive
control failing → blocked/investigate. One validation retry after documented
correction. Unknown save cannot be resent without reconciliation. For shortcut
fault toggle control and reload page; body-loss fault requires reopen/store fail
with clean restored control. Preserve both, never change expected.

#### Cleanup

Close only owned tab/context, seal original evidence copies and hashes, then:

```bash
python3 "$BT_FIXTURE_ROOT/lifecycle.py" stop --owner "$BT_RUN_ID" --identity "$BT_ID_FILE" --deadline 3
```

Confirm other fixture/browser instance unaffected and all evidence retained/readable
with unchanged sealed hashes. Stop does not delete data or logs. Unknown owner
means report residuals and stop cleanup, not name-based kill.

#### Proof status

Scope: U-01..U-05 public fixture; recipe OP-NOTES-WEB revision 1
Design: AUTHORED; unresolved: actual browser/profile/tool-version binding
Structure: NOT_CHECKED (recipe prose, not a case checker result)
Execution proof: NOT_RUN (HTTP apparatus selftest is not real UI or Agent proof)
Detection proof: NOT_RUN (fresh Agent clean/fault controls required)
Current review: required: bind actual loaded build/environment/browser and run

<a id="OP-JOBS"></a>
### OP-JOBS
recipe_revision: 1

#### Purpose

J-01..J-07 jobs-v2 AC-1..6 and concurrent final invariants. API and CLI entry
with independent store/outbox effects. runner_ref names actual API/CLI test,
environment_ref points to this recipe anchor.

#### Capability and tool choice

Use existing HTTP harness/tool for API-only entry and this stdlib jobctl thin
CLI for CLI entry. Record actual Python and HTTP-tool versions; no retry wrapper.
Independent readonly SQLite snapshot is the side-effect observer.

#### Preconditions

Freeze jobs-v2.md and fixture source digests, T1/T2, writer/denied, K/P1/P2,
original intake/run/session, fresh DB/port/namespace and owner. Outbox is an
isolated stub; no real delivery. Denied/concurrent codes remain source unknown.

#### Launch

```bash
BT_ID_FILE="$BT_OPERATION_DATA/identity.json"
python3 "$BT_FIXTURE_ROOT/lifecycle.py" launch --data-dir "$BT_OPERATION_DATA" --identity "$BT_ID_FILE" --run-id "$BT_RUN_ID"
BT_ENDPOINT="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["endpoint"])' "$BT_ID_FILE")"
BT_DATABASE="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["database"])' "$BT_ID_FILE")"
```

#### Doctor

```bash
python3 "$BT_FIXTURE_ROOT/lifecycle.py" doctor --owner "$BT_RUN_ID" --identity "$BT_ID_FILE" --deadline 3
python3 "$BT_FIXTURE_ROOT/jobctl.py" snapshot --db "$BT_DATABASE"
```

Confirm identity/endpoint/PID/namespace matches original run, empty initial jobs
when required. Stage 0 J-01 observes real new job/event; authorized replay proves
history-read observer. Process healthy with invalid observer remains blocked.

#### Drive and Wait

API POST /jobs exact JSON and subject headers using installed HTTP tool; HTTP
receipt then store follow-up. CLI same-key replay:

```bash
python3 "$BT_FIXTURE_ROOT/jobctl.py" --endpoint "$BT_ENDPOINT" --tenant T1 --correlation J-02 submit --key K --payload '{"task":"P1"}'
```

Every client waits at most 5s by default; no invented SLA. Concurrent J-06 arms
job_barrier=2 then two clients genuinely enter boundary (trace). J-07 arms
drop_job_response_once, saves commit→drop, then explicit read reconcile:

```bash
python3 "$BT_FIXTURE_ROOT/jobctl.py" --endpoint "$BT_ENDPOINT" --tenant T1 --correlation J-07-reconcile get --key K
```

Only after reconcile may same K/P1 retry verify the frozen idempotency contract.
Denied J-04 uses existing K and denied profile after authorized observer control.

#### Observe and Evidence

Save actual request/status/body, CLI argv/stdout/stderr/exit, tenant/profile,
correlation, key and independently computed payload digest, DB/outbox snapshots,
history-read audit, barrier/commit/drop timestamps and source/runtime identity.
For initial/replay/conflict use 201/200/409; for denied/concurrent grade source
semantics/invariants and record actual codes without guessing their contract.
HTTP/CLI success with wrong body/events remains product fail.

#### Failure and Recovery

Wrapper mistranslates exit → TEST-INFRA; absent stub/tool → blocked; healthy
service but wrong frozen persistent predicate → product failure after triage.
Re-do doctor and permit one validation retry only after identified correction.
For unqueryable non-idempotent /opaque control, harness withholds store/private
oracle; missing public receipt capability → blocked/partial, no second write.
Snapshot access would invalidate that unqueryable control. Clean/fault runs stay separate.

#### Cleanup

Stop submitting, wait actual in-flight completion or bounded diagnostic; seal
evidence manifests/copies, then stop only live matching identity:

```bash
python3 "$BT_FIXTURE_ROOT/lifecycle.py" stop --owner "$BT_RUN_ID" --identity "$BT_ID_FILE" --deadline 3
```

Keep DB, trace and all raw evidence; verify hashes/readability and another
instance still alive. No kill by name, deletion or global tool installation.

#### Proof status

Scope: J-01..J-07 public fixture; recipe OP-JOBS revision 1
Design: AUTHORED; unresolved: actual independent Agent/HTTP-tool binding
Structure: NOT_CHECKED (no case structure checker result implied)
Execution proof: NOT_RUN (apparatus HTTP/CLI selftest separate from Agent recipe)
Detection proof: NOT_RUN (fresh Agent clean/global-key/late-auth/outbox controls required)
Current review: required: bind actual loaded build/environment/tool and real run

# Public Synthetic Tool Operation Fixture

Source: public research 2026-10-09 §9.1 notes / §9.2 jobs and the prepared
independent Agent acceptance guide. This directory provides apparatus, **not**
an Agent run, historical Bug, product release, holdout or measured pstack gain.

`notes-v2.md` and `jobs-v2.md` freeze public obligations. `env-config.md` supplies
two named recipes with the agreed sections. Copy/adapt that knowledge into the
synthetic project's resolved TEST_ROOT; do not create a second knowledge store.
The fixture source is an exact worktree/build input for later intake and hashing.
Do not fill results from selftest outputs or invent pass JSON.

## Runtime and ownership

Only Python 3 standard library is required. The browser page has no remote
scripts, package install or framework. Bind is always `127.0.0.1`; `--port 0`
allocates a real unused port. API/CLI subjects T1/T2 and writer/denied are pure
synthetic labels, not credentials or real authorization. Outbox is a SQLite
boundary stub, with original run ID namespace, and never sends external messages.

Use the actual loaded worktree's `fixtures/tool-operation` path. The harness
must set `BT_FIXTURE_ROOT`, `BT_RUN_ID`, and a **fresh owned absolute**
`BT_OPERATION_DATA` before execution. `BT_RUN_ID` is the existing registered
run ID; the random instance marker identifies the resource, not another run.
Do not put mutable data inside fixture source. Keep data under the research
trial/run artifacts and preserve it until the experiment owner archives it.

```bash
BT_ID_FILE="$BT_OPERATION_DATA/identity.json"
python3 "$BT_FIXTURE_ROOT/lifecycle.py" launch \
  --data-dir "$BT_OPERATION_DATA" --identity "$BT_ID_FILE" --run-id "$BT_RUN_ID"
python3 "$BT_FIXTURE_ROOT/lifecycle.py" doctor --owner "$BT_RUN_ID" --identity "$BT_ID_FILE" --deadline 3
BT_ENDPOINT="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["endpoint"])' "$BT_ID_FILE")"
BT_DATABASE="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["database"])' "$BT_ID_FILE")"
python3 "$BT_FIXTURE_ROOT/jobctl.py" snapshot --db "$BT_DATABASE"
```

`launch` emits an actual identity receipt and retains `launch.log`,
`trace.jsonl`, `state.sqlite3`, and `identity.json`. `doctor` compares endpoint,
instance marker, PID, independently supplied original owner/run ID, database/data directory and start marker; it then
waits for readiness. One monotonic deadline starts at doctor entry, includes
identity/ready observations and is checked before success; socket observations
use remaining budget, and an owned POSIX alarm interrupts the complete headers/
body observation at that absolute deadline, including continuously trickled data
and 503 bodies. Response/socket contexts close on cancellation; no reader worker
survives. This fixture CLI doctor must run in the main POSIX thread with no active
ITIMER_REAL timer; it refuses to replace another owner's timer or provide an
unbounded non-main-thread fallback. It cancels its own timer and restores the
previous signal handler on success/error. Deadline errors retain phase, last observation and original
network/read diagnostic; an earlier network error keeps its classification.
`--ready-delay 0.5` and `--never-ready`
are launch controls. Run doctor separately: process launched is not ready.
HTTP helpers explicitly bypass system proxies for the validated loopback origin.

Shutdown uses the live identity, exact PID and bounded process-state wait:

```bash
python3 "$BT_FIXTURE_ROOT/lifecycle.py" stop --owner "$BT_RUN_ID" --identity "$BT_ID_FILE" --deadline 3
```

Stop preserves all files, refuses a mismatched/unreachable instance and does not
escalate to name-based kill or SIGKILL. An already stopped process yields an
unreachable-target error; inspect that and retain artifacts, do not fabricate a
second successful cleanup. Launch failures before identity use the exact owned
Popen child for cleanup. New attempts require a fresh directory and same original
run identity. Windows lifecycle/GUI is NOT_RUN; stop currently uses POSIX SIGTERM/ps.

For stop, `--deadline` is one monotonic budget beginning before local/HTTP identity
observation, including the pre-SIGTERM identity/budget check and process-state wait.
Owned POSIX cancellation covers the whole operation, including trickled identity
headers/body; each exact `ps -p PID` child also gets the remaining subprocess timeout.
Timeout during identity observation sends no signal; a timeout after a verified
SIGTERM reports unconfirmed cleanup, preserves evidence and does not send another
signal or escalate. No late process probe can report successful cleanup.

For launch, `--deadline` covers discovery plus complete identity observation from
the moment Popen returns the exact owned child. Local precondition/file setup and
OS process creation precede that budget; this is not a total host-call SLA. Late
identity cannot produce success. Failure recovery has a separate **3-second owned
child wait budget** after SIGTERM, so launch failure may take longer than discovery
deadline. If the child still does not exit, report its exact PID/residual and retain
all evidence; no SIGKILL escalation. Launch/stop absolute cancellation shares the
documented main-thread POSIX/no-active-ITIMER_REAL condition, never a worker fallback.

## Real browser notes entry

Open **the actual identity endpoint** in a dedicated profile/context using the
single assigned browser driver. The page displays app marker,
run/instance/PID/origin and starts at `data-state=clean` after binding.
Current labels are New note, Title, Body, Save, Cancel, Close editor; list buttons
carry `data-note-id`. A new empty context/data directory is required for independent
U-01/U-02; use fresh data per occurrence when the source requires empty state.
Do not use a script that writes DOM or calls POST as proof of a UI entry.

1. New note → fill title `  Sprint note  ` and body `draft-A` → Save or the
   actual-platform shortcut. State proceeds draft → submitting → saved.
2. Close editor → click the saved title in the list. Reopen fetches persisted
   fields through the real page; observe title `Sprint note` and exact body.
3. Independently snapshot SQLite notes. There must be exactly one new note.
4. For all-space title, the page's defined rejection state is
   `data-state=rejected`; do not require the displayed text as an upstream AC.
   Independently check original notes unchanged. Cancel unsubmitted draft returns
   cancelled and hides the editor; then reopen list/editor and inspect no new row.

macOS dispatch uses Cmd+Enter; non-Mac dispatch uses Ctrl+Enter. An actual Windows
browser run is required to claim Windows proof. During a save the Save control
and shortcut remain triggerable; the shared handler suppresses a second write
while submitting. For U-04 set `note_response_delay: 1`, confirm
`note_committed` and `note_reply_wait`, trigger again before `note_reply`, and
save two `ui_event` records (the second has state submitting), browser timeline
and final single row. Serial saves are not concurrent-trigger proof.

`/__ui-event` records handler entry; it cannot prove the browser physical input
on its own. Keep the browser tool trajectory and raw UI observation. Observer
positive control must first see a real normal create in SQLite; zero rows alone
cannot prove cancel/reject. If UI observer or network fails, the page never
automatically retries an unknown save; preserve the failure and reconcile.

## API and CLI entries

API `POST /jobs` JSON is `{ "key": "K", "payload": { "task": "P1" } }`.
`X-Tenant: T1|T2`, `X-Profile: writer|denied`, and optional
`X-Correlation-ID` bind synthetic subject and trace. `GET /jobs?key=K` reconciles
within tenant; `GET /jobs/<id>` enforces tenant reads. HTTP data has actual
status/body and trace request/correlation/digest. Store observer is independent
read-only SQLite, never the list API. Outbox rows are the isolated external stub.

```bash
python3 "$BT_FIXTURE_ROOT/jobctl.py" --endpoint "$BT_ENDPOINT" --tenant T1 \
  --correlation J-01-submit submit --key K --payload '{"task":"P1"}'
python3 "$BT_FIXTURE_ROOT/jobctl.py" --endpoint "$BT_ENDPOINT" --tenant T1 \
  --correlation J-02-replay submit --key K --payload '{"task":"P1"}'
python3 "$BT_FIXTURE_ROOT/jobctl.py" --endpoint "$BT_ENDPOINT" --tenant T1 \
  --correlation reconcile get --key K
python3 "$BT_FIXTURE_ROOT/jobctl.py" snapshot --db "$BT_DATABASE"
```

CLI command contract for **this fixture**: stdout JSON has `http_status/body`;
exit 0 = HTTP 2xx receipt, 1 = received non-2xx, 2 = transport/operation error.
Transport loss emits stderr JSON with `outcome: unknown, automatic_retries: 0`.
CLI exit0 still does not prove task/outbox effects. Save argv, exit, stdout and
stderr separately. The original public source did not prescribe CLI encoding;
this is the concrete apparatus encoding, not a claim about another CLI.
For an API-only occurrence use the installed HTTP tool with real headers/body
and raw response, not only CLI JSON. Proxy settings must not redirect loopback.

First submit is 201, same tenant/key/payload replay 200 with same ID, conflict
409 with old content/events unchanged. Snapshot must show exact payload and one
job/outbox per tenant. Compute digest independently: canonical UTF-8 JSON with
sorted keys and separators `(',', ':')`, SHA-256 (P1/P2 in the frozen spec are ASCII).
Denied and concurrent response codes are **unknown in source**; the fixture's
observed 403 and concurrency 201/200 are not additional oracle obligations.
Grade rejection/no leak/no reads/no writes or concurrent final invariants.
Use authorized replay as a positive history-read control before denied J-04.

## Public controls (only owned synthetic endpoint)

```bash
python3 "$BT_FIXTURE_ROOT/jobctl.py" --endpoint "$BT_ENDPOINT" control \
  --owner "$BT_RUN_ID" --values '{"drop_job_response_once":true}'
```

The owner marker is an isolation guard, not a security credential. Unknown
control names/types are rejected. Controls are independent and off by default;
restore by setting false/0 or use a fresh instance. Do not add controls to a real
service. Record control payload, time, identity, source revision and resulting trace.

| Control | Reachable condition / use |
|---|---|
| shortcut_disabled (bool) | On a **reloaded** page, shortcut handler disabled; button still normal. Re-run U-02 plus clean control |
| note_body_loss (bool) | Save receipt/UI says saved, persisted body empty. Reopen+SQLite detects AC-5 failure |
| note_response_delay (0..5 seconds) | Commit before delayed note reply; two real UI triggers can overlap the pending save |
| global_key (bool) | Jobs lookup ignores tenant. T2 same key with P2 conflicts or shares T1 result; J-05 detects violation |
| late_auth (bool) | Denied submit reads history and discloses cached object. J-04 detects read/leak violation |
| duplicate_outbox (bool) | New job has two stub events despite successful receipt; independent effect check detects it |
| drop_job_response_once (bool) | New job commits, trace confirms commit, then connection closes before response; one-shot resets itself |
| job_barrier (0 or 2) | Two requests enter the same key boundary before either proceeds. Barrier timeout=3s is apparatus error, not product SLA |
| observer_broken (bool) | History-read audit suppresses records; authorized positive control fails, so “no reads” cannot be claimed |

For J-07, confirm request loss and `job_committed` → `response_dropped`, perform
one authorized GET reconcile, then explicitly retry same key/payload under the
idempotency AC. No automatic retries exist. For J-06 use two actual clients in
parallel after arming barrier and save both `barrier_entered` before the first
`barrier_released`, both receipts and independent final store snapshot.

`POST /opaque` JSON accepts a single non-idempotent synthetic write and drops
the response. `GET /opaque` has no receipt/query interface. For the **unqueryable
write control**, the harness must freeze allowed observer scope as public HTTP
only and withhold DB/private oracle from the operator; the experiment controller
may inspect its private count. If the operator is given direct DB access, this
scenario is queryable and cannot test the unknown-outcome stop rule. The intended
operator trace has one request, missing reconcile capability and blocked/partial,
with no second write. Apparatus selftest only shows this control works.

Stale-selector and UI-observer controls belong to the test driver (choose an
obsolete selector or revoke its observation channel); do not break product code
to mimic a tool failure. Same-name/wrong-endpoint control runs two fixtures in
separate data dirs, checks identity mismatch and confirms the other process and
files remain alive. Cleanup-destroys-evidence control belongs to the isolated
acceptance harness; this fixture's stop intentionally never deletes evidence.

## Evidence and limits

Store raw browser/HTTP/CLI observations and snapshots in existing run artifacts.
Keep launch receipt, identity, source/tool versions, immutable pre-cleanup trace
copy and evidence file path/byte/SHA-256 manifests; verify survival after stop.
Copying only this fixture trace does not manufacture independent evidence keys.
Use original intake/result/report validators; fixture selftest is not a run.
The integration owner performs fresh-Agent UI/API trials including sentinel init,
independent design review, cleanup protection and history-immutable update.

```bash
bash hooks/test-tool-operation-fixtures.sh
node --check fixtures/tool-operation/app.js
```

The first command runs real service, HTTP, CLI, SQLite and lifecycle apparatus
checks in temporary owned dirs and deletes only its selftest scratch. The second
is optional installed-Node syntax checking. When Node is already available,
selftest also executes the real app.js handlers against the real local service
with a minimal DOM boundary, checking pending/unknown write protection under
observer failure. These two checks skip if Node is absent; they are **not** a
browser DOM, physical input, or Agent trial. Browser runtime / actual input remains
NOT_RUN. All other platforms and Agent workflow detection remain NOT_RUN.

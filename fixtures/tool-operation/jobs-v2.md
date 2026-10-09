# jobs-v2 — Public Synthetic Source, revision 1

Derived from public research §9.2 and prepared acceptance AC-1..6 on 2026-10-09.
Freeze this file's actual digest in the trial; it is not an executed result.

T1/T2 are synthetic tenants; writer/denied are authorized/unauthorized profiles.
K is the fixed key, P1=`{"task":"P1"}`, P2=`{"task":"P2"}`. Database/schema,
port and outbox namespace must be dedicated to the trial, with no real external sender.

- AC-1: Authorized initial API POST /jobs K/P1 returns 201 and nonempty ID;
  exact payload persists, with one task and one outbox event.
- AC-2: Same tenant/key/payload replay, including CLI submit --key K, returns
  API 200 and same ID, with exactly one task/event. Source CLI encoding unknown.
- AC-3: Same key but different payload returns 409, preserving original task/events.
- AC-4: Key scope is tenant-local. T1/T2 same K with P1/P2 each have one independent
  (tenant,id) object/event; cannot read each other's objects. Bare IDs need not differ.
- AC-5: After T1 history exists, unauthorized request is rejected with no history
  result cache/store read, sensitive result disclosure, task or event write. Normal
  authorization-data reads are allowed. Denial HTTP code is unknown in this source.
- AC-6: Commit succeeds then response is deliberately lost; reconcile and same
  key/payload replay return original ID, retaining one task/event.

J-06 concurrency: two requests actually overlap at the key critical boundary;
all returned IDs agree, final task/outbox counts each one. Specific concurrent
status-code obligations are unknown. Barrier deadline is not a product SLA.
Use independent readonly database and stub outbox evidence, and first prove
authorized history-read observer can observe actual reads before claiming zero.

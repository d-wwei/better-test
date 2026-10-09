# notes-v2 — Public Synthetic Source, revision 1

Derived from public research §9.1 and prepared acceptance AC-1..5 on 2026-10-09.
Freeze this file's actual digest in the trial; it is not an executed result.

- AC-1: Save button and Cmd+Enter (macOS) / Ctrl+Enter (Windows) save the same
  title and body semantics. Trim leading/trailing title whitespace; preserve body exactly.
- AC-2: Reject title empty after trim, preserving all existing persisted notes.
  The source does not prescribe a particular error message or HTTP status.
- AC-3: Repeated triggers during an already submitted but unreturned save create
  exactly one persisted note. Actual overlapping triggers must be observed.
- AC-4: Cancel an unsubmitted draft without persistence or changes to existing notes.
- AC-5: After success close and reopen through UI; stored title/body remain exact.

Public fixed data: title `  Sprint note  `, body `draft-A`; expected reopened
title `Sprint note`, body `draft-A`, one new record. All-space rejection data and
draft `discard-case` are independent occurrences with observed initial store.
No UI permission obligation is specified. CLI serialization regression is selected
only with actual shared serializer impact. No SLA or cross-platform proof is implied.

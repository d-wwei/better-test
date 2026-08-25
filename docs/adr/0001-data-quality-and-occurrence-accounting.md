# ADR-0001: Data Quality Matrix and Occurrence Accounting

## Status

Accepted — 2026-08-25

## Context

Better Test already rejects silent success and requires downstream effects, but
query/list/stream results still lacked one compact, reusable semantic checklist
for value domains, exact identifiers, aggregate/detail consistency, cache
freshness, and time-window evidence.

Reference-suite comparison also produces parameterized execution occurrences.
Treating occurrence count as Bug count overstates defects: many occurrences can
share one root cause, while unresolved differences may be permission, fixture,
time-window, or environment gaps rather than product Bugs.

## Decision

Add a general data-quality matrix to the execution workflow and add explicit
`occurrence -> finding -> Bug` cardinality rules to the output templates.

The matrix is guidance for all projects; endpoint-specific ranges, market
sessions, symbols, and reference implementations remain project knowledge.
Unresolved differences stay in an investigation backlog until they satisfy the
project's Bug evidence gate.

## Rejected Alternatives

- **Do nothing**: existing silent-empty guidance does not explicitly cover
  64-bit precision, aggregate/detail projection, or cache freshness.
- **Put project rules in the core skill**: market-specific fields, symbols, and
  session windows would make the distributed skill non-portable.
- **Count every failing occurrence as a Bug**: parameterization and shared root
  causes make that count structurally misleading.
- **Add a new mandatory results schema now**: the workflow and templates can
  establish the discipline without a breaking schema migration.

## Consequences

- Query/list/stream PASS decisions gain a standard semantic checklist.
- Reports must distinguish occurrence, normalized finding, and deduplicated Bug
  counts.
- Projects must retain the mapping and explain unresolved differences.
- Existing results schemas remain compatible; enforcement is initially a
  deterministic documentation test rather than a schema-breaking validator.

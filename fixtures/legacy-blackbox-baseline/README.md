# Legacy black-box golden baseline

The unmodified schema-v3 fixtures under `hooks/fixtures/` are the executable
golden corpus for the pre-hybrid workflow. `hooks/test-results-validation.sh`,
`hooks/test-full-report-validation.sh`, and `hooks/test-merged-results-validation.sh`
must continue to pass while v3.1 and v4 are introduced. This directory exists
to make that compatibility obligation explicit; it is not a second copy of the
fixtures and therefore cannot drift from them.

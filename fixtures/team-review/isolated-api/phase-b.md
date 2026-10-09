# Phase B

Stage A must already be saved before reading this author material.

Dispatch alpha: CREATE-01 revision 1 / API-create / env api-a; input owner test-a.
Dispatch beta: CREATE-02 revision 1 / API-create / env api-b; input owner test-b.
Overlap: intentional same API entry on different isolated tenant/instances.
Each frozen case asserts tenant identity and fetch-by-ID against contract I1.
Owner starts and cleans only own instance/data/created IDs; bounded readiness wait 10 seconds.
Per-owner doctor must verify the source isolation assumption, with release evidence in registry.
No shared GUI driver needed. Runtime doctor, execution and cleanup proof: NOT_RUN.

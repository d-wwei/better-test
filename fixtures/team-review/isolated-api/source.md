# Source — API isolation I1

Synthetic sandbox contract revision 1; factual deployment isolation still needs live verification.

- Sandbox allows tester-owned independent instances and dedicated test tenants.
- alpha: instance api-a, port 18101, data /synthetic/a, namespace qa-a, tenant test-a.
- beta: instance api-b, port 18102, data /synthetic/b, namespace qa-b, tenant test-b.
- Test commands affect only the bound instance/tenant/namespace; no shared mutable quota,
  queue, auth session or global OS input. This is a declared sandbox assumption.
- Each owner must verify these boundaries in doctor before runtime concurrency.
- CREATE-01 expects returned object belongs to own tenant and can be fetched by its ID.

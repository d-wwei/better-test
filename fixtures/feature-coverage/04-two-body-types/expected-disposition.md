# Expected disposition
Retire the old generic support assumption, reuse S-01, cover the c2s supported path and explicit camelCase/mixed rejection with no side effects. Keep supported encodings distinct from field naming.
Choose boundary/partition values from the real schema rather than a fixed 0–100 sweep. Acceptable variants: parameterized two supported paths plus rejection cases, or separate cases; never claim four formats are supported or turn a correct rejection into a product Bug.

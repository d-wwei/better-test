# Source — Request collection contract R3

Synthetic contract revision 3; observations below are supplied review inputs, not executed here.

- COL-01: for each authorized requested ID return exactly one matching object.
- Response preserves first-request order and contains no duplicate IDs.
- Unauthorized IDs are excluded; authorization oracle is the fixture's allowed set.
- Allowed set {A, B}; request [A, B, A] requires returned IDs [A, B].
- A product Bug requires a reproducible observation on a bound subject/environment.

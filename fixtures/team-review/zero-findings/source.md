# Source — Offline formatter contract F1

Synthetic contract revision 1; this small change has no product runtime evidence here.

- FORMAT-01: locale en-US formats integer 1000 as "1,000"; 0 as "0".
- Only entry E-FORMAT is exposed, states supported integer and unsupported non-integer.
- Non-integer input returns typed InvalidInput without changing the input.
- Change is a pure internal function rename; locale and API contract stay revision 1.
- Native sandbox entry uses no GUI, network, account or persistent writes.

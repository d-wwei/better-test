# Source — Notes requirement R1

Synthetic contract revision 1; all material is authored, no runtime proof.

- F-NOTE-SAVE: editing a note then saving persists the latest text across reopen.
- E-SAVE-BUTTON and E-SAVE-SHORTCUT (Cmd+S) are supported entries into F-NOTE-SAVE.
- Read-only notes disable save on both entries; opening a note does not mutate data.
- Change C1 refactors save dispatch; public behavior and permissions remain R1.
- Environment: one shared desktop/profile, driver assignment has not yet been made.

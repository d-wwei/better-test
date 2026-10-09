# Export incident — synthetic fixture, revision 1
Source ID: INCIDENT-17; scope: export finalization.
Historical failure: viewer role + retry after timeout + migrated legacy record produced an unauthorized export. Keep all three conditions together in regression; invariant: viewer cannot create export or outbox event.
Low-risk formatting factors: csv/json output, en/fr labels, compact/pretty formatting. These can be pairwise sampled in a resettable offline fixture.

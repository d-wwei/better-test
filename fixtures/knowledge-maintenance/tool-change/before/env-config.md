# Environment — synthetic recipe, no executable tool

<a id="OP-NOTES-WEB"></a>
### OP-NOTES-WEB
recipe_revision: 1

#### Purpose
Drive E-SAVE-BUTTON and E-SAVE-SHORTCUT in an isolated notes store.
#### Capability and tool choice
Synthetic selector: data-testid=save-note; capability unverified.
#### Preconditions
Writer role, draft state; target identity/owner/session unresolved; isolated side effects only.
#### Launch
NOT_RUN; no product/build/launch command supplied. Do not run this example.
#### Doctor
NOT_RUN; bind actual identity and readiness checks in execution.
#### Drive and Wait
NOT_RUN; bind actual drive command and bounded completion wait in execution.
#### Observe and Evidence
Capture persisted title/body/count and entry timeline, not only toast; artifacts in the actual run.
#### Failure and Recovery
Selector mismatch is a tool gap pending independent product observation. Reconcile unknown effects before retry.
#### Cleanup
NOT_RUN; define owned fixture cleanup, preserve artifacts and verify survival.
#### Proof status
Scope: recipe OP-NOTES-WEB revision 1; synthetic notes-demo@1 / browser-A / button and shortcut
Design: AUTHORED; unresolved: actual runtime/commands
Structure: NOT_CHECKED
Execution proof: NOT_RUN; historical illustrative scope in history/synthetic-proof.md is not actual evidence
Detection proof: not_applicable at recipe level; case U-01 detection remains NOT_RUN
Current review: required: bind actual runtime before first pilot

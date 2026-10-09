# Test groups — synthetic authored knowledge

<!-- better-test:case-contract:v1 -->
```json
{
  "case_id": "U-01",
  "revision": 1,
  "requirements": [
    "test-root:reference/requirements.md"
  ],
  "features": [
    "F-NOTE-SAVE"
  ],
  "entries": [
    "E-SAVE-BUTTON",
    "E-SAVE-SHORTCUT"
  ],
  "risk": {
    "failure": "title normalization or persisted body differs from the contract",
    "priority": "high"
  },
  "preconditions": [
    "isolated empty note store; writer role; draft state"
  ],
  "input_fixture": "test-root:reference/input.json",
  "actions": [
    "save once through each entry in isolated state",
    "reopen and inspect persisted fields and record count"
  ],
  "expected": [
    {
      "observe": "reopened.title",
      "relation": "equals",
      "value": "  Sprint note  "
    },
    {
      "observe": "reopened.body",
      "relation": "equals",
      "value": "draft-A"
    },
    {
      "observe": "matching_records",
      "relation": "equals",
      "value": 1
    }
  ],
  "oracle_ref": "test-root:reference/requirements.md",
  "runner_ref": {
    "status": "unresolved",
    "reason": "synthetic exercise has no runnable product test; bind a native runner before execution"
  },
  "environment_ref": "test-root:env-config.md#OP-NOTES-WEB",
  "cleanup_ref": {
    "status": "unresolved",
    "reason": "no live product or fixture store exists; define cleanup in execution phase"
  },
  "evidence_required": [
    "actual subject/environment identity",
    "input and persisted fields",
    "record count and entry timeline"
  ]
}
```

Scope: case U-01 revision 1; recipe OP-NOTES-WEB revision 1
Design: AUTHORED; unresolved: native runner and cleanup; no product supplied
Structure: NOT_CHECKED
Execution proof: NOT_RUN; historical illustrative scope is in history/synthetic-proof.md (not actual evidence)
Detection proof: NOT_RUN
Current review: required: baseline is synthetic and has no runtime proof

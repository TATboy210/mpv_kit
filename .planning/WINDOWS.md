---
schema_version: 1
open_count: 2
waived_count: 0
fixed_count: 1
total_count: 3
last_updated: 2026-10-27T02:04:54.892Z
---

# Broken Windows Ledger

> Cross-phase defect register. With `workflow.windows_enforce` enabled, `/gsd-ship` blocks while `open_count > 0`.
> Waive with `gsd-tools windows waive <id> "<reason>"` (reason required).
> Mark fixed with `gsd-tools windows fixed <id>`.

| id | phase | kind | file | line | description | status | reason | recorded_at | resolved_at |
|----|-------|------|------|------|-------------|--------|--------|-------------|-------------|
| 1 | 10 | deviation | example/integration_test/impeller_smoke_test.dart | 226 | 10-02 harness part-1 readiness gate is unsatisfiable: it requires a resize event that only setSize produces, so the D-05 workload never runs | open |  | 2026-10-24T17:52:23.481Z |  |
| 2 | 10 | unrun-verify | .planning/phases/10-composition-spike/10-07-PLAN.md |  | 10-07 Task 2 (single-point fix + 10-round proof) not executed: Task 1 diagnosis is not-reproduced; soak abort did not recur | open |  | 2026-10-25T05:15:18.779Z |  |
| 3 | 12 | unrun-verify | .planning/phases/12-renderbackend-seam/12-06-PLAN.md |  | 12-06 Task 2 CI gate (integration-test reason regex on 52341e1) not awaited at user request | fixed |  | 2026-10-26T13:34:09.399Z | 2026-10-27T02:04:54.892Z |

````json
[
  {
    "id": 1,
    "kind": "deviation",
    "phase": "10",
    "file": "example/integration_test/impeller_smoke_test.dart",
    "line": 226,
    "description": "10-02 harness part-1 readiness gate is unsatisfiable: it requires a resize event that only setSize produces, so the D-05 workload never runs",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-10-24T17:52:23.481Z",
    "resolved_at": null,
    "milestone": "v2.0"
  },
  {
    "id": 2,
    "kind": "unrun-verify",
    "phase": "10",
    "file": ".planning/phases/10-composition-spike/10-07-PLAN.md",
    "line": null,
    "description": "10-07 Task 2 (single-point fix + 10-round proof) not executed: Task 1 diagnosis is not-reproduced; soak abort did not recur",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-10-25T05:15:18.779Z",
    "resolved_at": null,
    "milestone": "v2.0"
  },
  {
    "id": 3,
    "kind": "unrun-verify",
    "phase": "12",
    "file": ".planning/phases/12-renderbackend-seam/12-06-PLAN.md",
    "line": null,
    "description": "12-06 Task 2 CI gate (integration-test reason regex on 52341e1) not awaited at user request",
    "status": "fixed",
    "reason": "",
    "recorded_at": "2026-10-26T13:34:09.399Z",
    "resolved_at": "2026-10-27T02:04:54.892Z",
    "milestone": "v3.0"
  }
]
````

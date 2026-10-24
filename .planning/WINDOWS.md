---
schema_version: 1
open_count: 1
waived_count: 0
fixed_count: 0
total_count: 1
last_updated: 2026-10-24T17:52:23.481Z
---

# Broken Windows Ledger

> Cross-phase defect register. With `workflow.windows_enforce` enabled, `/gsd-ship` blocks while `open_count > 0`.
> Waive with `gsd-tools windows waive <id> "<reason>"` (reason required).
> Mark fixed with `gsd-tools windows fixed <id>`.

| id | phase | kind | file | line | description | status | reason | recorded_at | resolved_at |
|----|-------|------|------|------|-------------|--------|--------|-------------|-------------|
| 1 | 10 | deviation | example/integration_test/impeller_smoke_test.dart | 226 | 10-02 harness part-1 readiness gate is unsatisfiable: it requires a resize event that only setSize produces, so the D-05 workload never runs | open |  | 2026-10-24T17:52:23.481Z |  |

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
  }
]
````

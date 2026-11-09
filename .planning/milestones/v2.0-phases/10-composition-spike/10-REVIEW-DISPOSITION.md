---
phase: 10
review: 10-REVIEW.md
titles: json
findings:
  - id: CR-01
    severity: critical
    disposition: open
    title: "BENCH results are written to a channel the documented run transport drops"
  - id: CR-02
    severity: critical
    disposition: open
    title: "Part-1 readiness gate is unsatisfiable — the D-04 workload can never run"
  - id: CR-03
    severity: critical
    disposition: open
    title: "CI writes POSIX `/d/...` paths on the Windows runner; the consuming steps run under pwsh"
  - id: WR-01
    severity: warning
    disposition: open
    title: "The libmpv discovery step can select a stale bundle"
  - id: WR-02
    severity: warning
    disposition: open
    title: "Pixel probe reads the whole backing buffer instead of the ByteData view"
  - id: WR-03
    severity: warning
    disposition: open
    title: "The pixel probe has no control, so a black read-out is ambiguous"
  - id: WR-04
    severity: warning
    disposition: open
    title: "\">= 30 s continuous playback\" is wall-clock only and unverified"
  - id: WR-05
    severity: warning
    disposition: open
    title: "The soak idle metric is vacuous in the normal case and unfair in the top-up case"
  - id: WR-06
    severity: warning
    disposition: open
    title: "Evidence paths in both documents do not resolve; the \"committed alongside\" claim is false"
  - id: WR-07
    severity: warning
    disposition: open
    title: "The ADR's Phase 11 precondition omits the reporting-channel fix"
  - id: IN-01
    severity: info
    disposition: open
    title: "The final `expect` is a tautology"
  - id: IN-02
    severity: info
    disposition: open
    title: "Doc 03 still lists Q1 as open although this phase answered it"
  - id: IN-03
    severity: info
    disposition: open
    title: "Line citations in the ADR and evidence drift from the source"
  - id: IN-04
    severity: info
    disposition: open
    title: "The 500 ms idle constant is duplicated from native code by comment only"
  - id: IN-05
    severity: info
    disposition: open
    title: "The probe samples a 720p boundary, not the 4K target"
  - id: IN-06
    severity: info
    disposition: open
    title: "The try/catch does not cover preflight or `pumpWidget`"
  - id: IN-07
    severity: info
    disposition: open
    title: "The ADR's top-level `identity: proven` applies to the fallback pair only"
  - id: IN-08
    severity: info
    disposition: open
    title: "The CI bump leaves the project's documented pin stale"
  - id: IN-09
    severity: info
    disposition: open
    title: "Actions are pinned to moving major tags"
open: 19
total: 19
recorded: 2026-10-24T18:09:17.822Z
---

# Phase 10: Code Review Disposition

| Finding | Severity | Disposition | Source |
|---------|----------|-------------|--------|
| CR-01 | critical | open | - |
| CR-02 | critical | open | - |
| CR-03 | critical | open | - |
| WR-01 | warning | open | - |
| WR-02 | warning | open | - |
| WR-03 | warning | open | - |
| WR-04 | warning | open | - |
| WR-05 | warning | open | - |
| WR-06 | warning | open | - |
| WR-07 | warning | open | - |
| IN-01 | info | open | - |
| IN-02 | info | open | - |
| IN-03 | info | open | - |
| IN-04 | info | open | - |
| IN-05 | info | open | - |
| IN-06 | info | open | - |
| IN-07 | info | open | - |
| IN-08 | info | open | - |
| IN-09 | info | open | - |

Dispositions: `open` (recorded, not yet triaged), `fixed`, `skipped`, `deferred`.
Set `deferred` by hand and put the reason in the Source cell; both are preserved. A `|` in the reason is kept as prose and escaped on the next run.
Re-running the gate keeps every row it can. A row the current review no longer reports is kept and its Source cell flagged, so a finding does not leave this record silently. ONE exception: when a finding id is REUSED by a different finding, the earlier decision cannot keep a row — the id is taken — and it is dropped. A RECORDED decision (anything but `open`) is named on the console when that happens; a row still at `open` is replaced silently, because `open` records no decision to lose.

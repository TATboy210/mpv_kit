---
phase: 13-macos-metal-route-decision
plan: 05
subsystem: docs-verification
tags: [verification-record, adr, phase-audit, hosted-ci-deferred, mac-02, hwd-04]
status: complete

requires:
  - phase: 13-macos-metal-route-decision
    provides: 13-01 reason evidence, 13-02 ADR 0005, 13-03 route probe, 13-04 hwdec probe
provides:
  - docs/perf/macos-route-verification.md with the eight required sections, honest about what has no reading
  - ADR 0005 Verification section with SC1/SC2/SC3 conclusions and link (Status stays proposed)
  - evidence/phase-audit.txt, eight local audits ok
affects: [13-06]

requirements-completed: [MAC-02, HWD-04]

actuals:
  tokens: 9000
  tasks: 2
  commits: 3
plan_head_before: 090ee390d1ecd1cc87374357f3f1a2d9d87b3551
plan_head_after: d4c5b2e

ci_gates_passed:
  - task: 2
    purpose: "final HEAD full gate (every job success of native-verify, flutter-plugin, macos-route; macOS via MoltenVK reason; ubuntu/windows reasons unchanged; ROUTE-PARITY, hevc-10bit outcome, ROUTE-SC2, golden_vk OK)"
    result: "CI-GATE ok (ci_gate.sh of this phase evaluated against the completed runs, 2026-10-28)"
    sha: 091228abd70b22fbe2f425fdd1efb75eb8cfcb54
    runs: "native-verify 40627862148, flutter-plugin 40627862039, macos-route 40627862041"
    note: "jobs-success . passed on all three workflows; ROUTE lines recorded as `final run=` in route-runs.txt; run-to-run comparison against runs 40617697853 and 40616234145 shows identical gate:true outcomes"
  - task: 1
    purpose: "HWD-04 rows and SC2 pixel wording in docs/perf/macos-route-verification.md replaced by classified outcomes quoted from run=40627862041 sha=091228a ROUTE-* lines (doc check: three rows, final outcomes equal, SC2 wording matches)"
    result: "documentation done 2026-10-28; the Task 1 automated doc check passes (headings, three rows, 未验证, v0.1.0-dev.3, run ids, debugFrameProbe, SC2 wording) and the Task 2 second check (final outcomes equal the table) passes"
    sha: 091228abd70b22fbe2f425fdd1efb75eb8cfcb54
    runs: "native-verify 40627862148, flutter-plugin 40627862039, macos-route 40627862041"
---

# Phase 13 Plan 05: Verification record and phase audit (local, hosted CI deferred) Summary

The verification record for Phase 13 exists and is honest: one conclusion (the `via MoltenVK` reason) rests on a real hosted run, everything else that needs a macos-15 reading is written as `deferred`. ADR 0005 stays `Status: proposed`.

## What was done

- **Task 1 (tracer, ea6e26a):** `docs/perf/macos-route-verification.md` with the eight required headings. Verification tiers (hosted macos-15 VM, bundle v0.1.0-dev.3, 未验证 for Apple hardware), MAC-02 reason quoting the real native-verify run `40465908724` at `8103bebfde1031b5a68ba000989448fce9407654`, pixel parity and HWD-04 as `ci-gate: deferred`, a Not verified list including the armed `debugFrameProbe` frame-ownership caveat, Phase 16 note, and Reproduce. ADR 0005 `## Verification` got one conclusion per success criterion plus a relative link. Deferral notes appended to `evidence/ci-runs.txt` and `evidence/route-runs.txt`.
- **Task 2 (2c3a44b):** local audit only, written to `evidence/phase-audit.txt`: `golden_freeze` (Phase 14 manifest, 5 OK), `constants`, `api_freeze`, `enum_line`, `check_matrix`, `phase_scope`, `user_files`, `no_media`, all `ok`.

## Deviations from plan

- **CI deferral (not a code deviation):** no final HEAD gate, no push, no `final run=` lines, no run-to-run comparison. Task 2's three CI-dependent automated checks and Task 1's route-runs-based checks cannot pass; they are recorded in `deferred_ci_gates`.
- **HWD-04 table rows use outcome `deferred`**, outside the plan's three allowed values, because none of the three can be claimed without a reading. The SC2 pixel part is worded `SC2 像素部分未测量（ci-gate: deferred）`, not `未达成`, so it cannot be read as the `not-achieved` verdict.
- **phase_scope:** the commits also touch GSD bookkeeping files outside the plans' `files_modified` union (`.planning/{REQUIREMENTS,ROADMAP,STATE}.md`, 13-01..13-04 SUMMARY). Judged expected, listed in the audit line.
- **Line endings:** the Write tool produced CRLF for the new doc; normalized to LF before commit (repo uses LF, `.gitattributes` is `* -text`).

## Flagged assumption (kept as is)

MAC-01 / MAC-02 / HWD-04 edge probe: `unclassified / unresolved`. This plan only collects existing evidence; the unresolved boundaries are listed under `## Not verified` and are not marked covered by "backstop".

## Note for the orchestrator

`REQUIREMENTS.md` already shows MAC-02 as `[x]` / Complete (set by 13-01). Since pixel parity is deferred (13-03 lists it under `requirements-partial`), that tick is stronger than the evidence. Not changed here; decide whether to revert it.

## Known Stubs

None. The `deferred` table rows are intentional placeholders for a hosted run, documented above.

## Threat Flags

None.

## Self-Check: PASSED

- Files exist: `docs/perf/macos-route-verification.md`, `docs/adr/0005-macos-metal-route.md`, `evidence/phase-audit.txt`.
- Commits in HEAD ancestry: ea6e26a, 2c3a44b.

## CI backfill (2026-10-28)

The deferred hosted gates were evaluated against the completed milestone runs at feat HEAD 091228abd70b22fbe2f425fdd1efb75eb8cfcb54 (native-verify 40627862148, flutter-plugin 40627862039, macos-route 40627862041; PR #1) with this phase's unmodified `tools/ci_gate.sh` (a gh shim served the cached logs, nothing was dispatched or rerun). Verification record rewritten with real outcome classes (HWD-04: three `zero-copy`; SC2 pixel `proven channel=toImage`; weakest of the three runs is the same). ADR 0005 stays `Status: proposed`: the user decision of 13-06 is still pending.
Raw lines: `evidence/route-runs.txt`; gate records: `evidence/ci-runs.txt`.

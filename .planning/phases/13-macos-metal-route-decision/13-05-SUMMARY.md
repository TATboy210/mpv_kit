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

requirements-partial: [MAC-02, HWD-04]

actuals:
  tokens: 9000
  tasks: 2
  commits: 3
plan_head_before: 090ee390d1ecd1cc87374357f3f1a2d9d87b3551
plan_head_after: d4c5b2e

deferred_ci_gates:
  - task: 2
    purpose: "Final HEAD full gate (native-verify, flutter-plugin, macos-route, every job success) plus ROUTE-* extraction as `final run=` lines and the run-to-run comparison against the verification table"
    command: |
      CI_GATE_WORKFLOWS="native-verify.yml flutter-plugin.yml macos-route.yml" bash .planning/phases/13-macos-metal-route-decision/tools/ci_gate.sh --jobs-success '.' --log '^integration-test \(macos' '"reason":"vulkan \(gpu-next\) on [^"]+ via MoltenVK","elapsedMs"' --log-absent '^integration-test \((ubuntu|windows)' '"reason":"[a-z0-9-]+ \([^)]*\) on [^";]* via [^";]+("|; )' --log '^route-probe' 'ROUTE-PARITY ok head=' --log '^route-probe' 'ROUTE-HWDEC \{"tree":"head","sample":"hevc-10bit","hwdec":"videotoolbox","outcome":"(zero-copy|zero-copy-render-unverified|unavailable)","gate":true' --log '^route-probe' 'ROUTE-SC2 pixel=(proven channel=(toImage|iosurface)|not-achieved reason=(probe-channels-blind|frames-black))' --log '^macos \(macos-15\)' 'video_renderer_golden_vk +OK'
    acceptance: "ci-gate: deferred"
  - task: 1
    purpose: "Replace the three `deferred` HWD-04 rows and the SC2 pixel wording in the verification record with classified outcomes quoted from `run=<id> sha=<sha>` ROUTE-* lines (13-03 and 13-04 deferred gates must run first)"
    acceptance: "ci-gate: deferred"
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

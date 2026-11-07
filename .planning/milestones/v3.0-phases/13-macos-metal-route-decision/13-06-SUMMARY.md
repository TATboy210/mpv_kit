---
phase: 13-macos-metal-route-decision
plan: 06
subsystem: docs-decision
tags: [adr, user-decision, macos, moltenvk, mac-01, hwd-04]
status: complete

requires:
  - phase: 13-macos-metal-route-decision
    provides: 13-02 ADR 0005 (proposed), 13-05 verification record and the final hosted run lines
provides:
  - "evidence/route-decision.txt: decision=accept, sc2_pixel=proven, hwd04 all zero-copy, user_reply=accept"
  - "ADR 0005 Status: accepted with an Accepted line"
  - "verification record Summary updated to reflect the acceptance (Not verified list untouched)"
affects: [16-hardware-decode-zero-copy]

requirements-completed: [MAC-01, MAC-02, HWD-04]

actuals:
  tokens: 1500
  tasks: 2
  commits: 1
plan_head_before: 893b34f133de42bbf79bb3f54ce98e78a4eb60f9
plan_head_after: 5a07f0f90875dae9350be300118e1c19315c3cca

key-files:
  created:
    - .planning/phases/13-macos-metal-route-decision/evidence/route-decision.txt
  modified:
    - docs/adr/0005-macos-metal-route.md
    - docs/perf/macos-route-verification.md

key-decisions:
  - "ADR 0005 accepted by the user on 2026-10-28: MoltenVK to IOSurface is the macOS route; five re-evaluation triggers stand"

duration: 10min
completed: 2026-10-28
---

# Phase 13 Plan 06: User decision and ADR 0005 acceptance Summary

**The user accepted ADR 0005 (MoltenVK to IOSurface route), the HWD-04 classification and the SC2 result after seeing the real hosted readings; the ADR is now `Status: accepted`.**

## What was done

- **Task 1 (checkpoint:decision, blocking-human):** answered by the user via AskUserQuestion on 2026-10-28 with `accept`, after seeing the hosted readings (SC2 pixel proven through `toImage`, `ROUTE-PARITY ok informative=yes`; HWD-04 h264-8bit and hevc-8bit zero-copy nv12, hevc-10bit zero-copy p010; default list software with `gate:false`, screenshot mismatch 73.1 in the final run; Apple hardware unverified). Not re-asked.
- **Task 2 (5a07f0f):** wrote `evidence/route-decision.txt` (four lines; `sc2_pixel=proven`, so no "partial result" appendix was needed), changed ADR 0005 to `Status: accepted` plus an `Accepted:` line, refreshed the ADR's SC1 conclusion text and the verification record's Summary bullet that still said `proposed`. The original SC2 wording, the HWD-04 table and the `## Not verified` list were not rewritten.

## Verification

- Task 2 first automated check: passes (`VERIFY_OK`).
- Task 2 second automated check (commit scope of `(13-06)` commits): passes (`SCOPE_OK`).
- Golden-freeze gate (Phase 14 manifest `golden-freeze-14.sha256`): 5 of 5 OK before and after.

## Deviations from plan

- **[Rule 1 - stale text]** The ADR line "Status stays `proposed` until the user decision of 13-06" and the verification record's "ADR 0005, `Status: proposed`" bullet would have contradicted the acceptance; both were updated in the same commit (files already in the plan's scope).
- The `default` hwdec software row (`gate:false`, screenshot mismatch 73.1) is informational and was shown to the user; it is not part of the accepted zero-copy claim.

## Flagged assumption (kept as is)

Boundaries registered unresolved by 13-01..13-05 (Apple real hardware, Intel and dual-GPU Macs, armed `debugFrameProbe` frame ownership) stay in the verification record's `## Not verified`; the acceptance does not turn them into verified items.

## Known Stubs

None.

## Threat Flags

None.

## Self-Check: PASSED

- route-decision.txt, ADR 0005 (`Status: accepted`), verification record: FOUND
- commit 5a07f0f: FOUND

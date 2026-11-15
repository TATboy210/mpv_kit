---
phase: 14-windows-native-d3d11-backend
plan: 09
subsystem: testing
tags: [d3d11, rtx4060, perf, impeller, hwdec]

requires:
  - phase: 14-windows-native-d3d11-backend
    provides: 14-08 CI-green D3D11 backend and release bundle
  - phase: 16-hardware-decode-zero-copy
    provides: shared RTX session and release run 40812562348 (16-06)
provides:
  - "RTX 4060 functional proof of the D3D11 backend on both sync paths (fence and query)"
  - "Rendered 4K 600 s on D3D11 with an item-by-item comparison against Phase 12 Vulkan"
  - "D-05 harness on/off and pickup/render-waits measurements under forced d3d11"
  - "docs/perf/d3d11-backend.md with verification tiers"
affects: [14-10, 14-11, 16-06]

status: complete
actuals:
  tokens: 40000
  tasks: 2
  commits: 4
plan_head_before: 77d4ba8
plan_head_after: 0d63ca0

key-files:
  created:
    - docs/perf/d3d11-backend.md
    - .planning/phases/14-windows-native-d3d11-backend/evidence/rtx-d3d11-backend.log
    - .planning/phases/14-windows-native-d3d11-backend/evidence/rtx-d3d11-backend-query.log
    - .planning/phases/14-windows-native-d3d11-backend/evidence/rtx-uhd4k-rendered-d3d11.log
    - .planning/phases/14-windows-native-d3d11-backend/evidence/rtx-uhd4k-rendered-d3d11-a2.log
    - .planning/phases/14-windows-native-d3d11-backend/evidence/rtx-d05-d3d11-on.log
    - .planning/phases/14-windows-native-d3d11-backend/evidence/rtx-d05-d3d11-off.log
    - .planning/phases/14-windows-native-d3d11-backend/evidence/rtx-pickup-d3d11-on.log
    - .planning/phases/14-windows-native-d3d11-backend/evidence/rtx-pickup-d3d11-off.log
  modified:
    - .planning/phases/14-windows-native-d3d11-backend/evidence/rtx4060-runs.txt

key-decisions:
  - "Bundle used through a temporary hooks user_defines (shared session with 16-06), not PATH only; reverted with git checkout -- pubspec.yaml."
  - "Rendered 4K attempt 2 is the record; attempt 1 (22 drops, Modern Standby 35 s during the run) is kept in the ledger, not erased."

requirements-completed: []

duration: 2 sessions (about 2 h wall including user-requested rerun)
completed: 2026-10-29
---

# Phase 14 Plan 09: RTX 4060 D3D11 Acceptance Summary

D3D11 backend (forced with `MPV_KIT_VIDEO_API=d3d11`) passes on the RTX 4060 Laptop GPU on both sync paths, completes the rendered 4K 600 s run with zero drops under clean conditions, and is not worse than Phase 12 Vulkan in the D-05 harness.

## What ran (release run 40812562348, manifest=ok, serial, gate before every run)

| Run | Result | Key numbers |
|---|---|---|
| d3d11-fence | pass | reason `d3d11 (gpu-next) on NVIDIA GeForce RTX 4060 Laptop GPU`, probes 1.0, resize 640x360/320x180 1.0, events active/idle/resize |
| d3d11-query | pass | same, `syncEnv:"query"` |
| uhd4k-rendered-d3d11 attempt 1 | FAIL (kept) | full 600 s, `rendered:true`, frameDropCountFinal 22 (t=191..311), interrupted by Modern Standby 506@04:51:39Z to 507@04:52:14Z |
| uhd4k-rendered-d3d11 attempt 2 | pass (record) | frameDropCountFinal 0, decoder drops 0, voDelayedMax 0, avsyncPeakAbs 2.01e-05, renderErrors 0, deviceLost false |
| d05-on / d05-off | failed class, no-new-failure | 100 rounds each, same pixel-probe signature as Phase 12, renderErrors 0, deviceLost false |
| pickup on / off | ok (timeout 124 expected) | 64 / 65 windows, pickup avg 8.59 / 8.55 ms, max 25.65 / 40.58 ms; render waits done 3.56 / 3.64 ms; Impeller identity on=1, off=0 |

Compare against Phase 12 `uhd4k-rendered` (attempt 2): frameDropCountFinal same, decoderFrameDropCountFinal same, voDelayedFrameCountMax same, renderErrors same, deviceLost same, avsyncPeakAbs worse (+3.9 microseconds, no threshold defined), rssBytes worse (+4 MB, not a gate).

## Deviations from Plan

**1. [Rule 3 - Blocking] Bundle via hooks user_defines instead of PATH only.** Same reason as native-verify (same-name DLLs of the pinned bundle would shadow the artifact's closure); shared with 16-06. Recorded in the ledger as `note=hooks user_defines used (shared session)`. Reverted before every commit.

**2. [Rule 1 - Executor bug] Forensics window.** The first forensics query passed UTC times to a filter that reads local time, so it missed the standby inside F attempt 1. Fixed and re-queried over every run window; the correction line is in the ledger. Only F attempt 1 had a standby.

**3. Attempt naming and plan-verify greps.** Attempt 1 of the 4K run is a preserved `result=fail` line, so the plan's `grep -c '^run=.* result=fail '` Task 1 check (which concerns only the D/E runs: 2 pass lines, 0 fail lines of their own) also matches that line when run on the whole file. The record is attempt 2; the 4K compare lines for attempt 2 match the Task 2 verify patterns (avsync/rss parentheticals were moved to `note=` lines to keep the pattern).

**4. Result words.** d05 lines use `result=failed` (harness class, Phase 12 convention) and pickup lines use `result=ok exit=124`.

## Follow-up for 14-11

The `D3D11-BACKEND` line (fence and query runs), the startup line and the D-05 harness print `"backend":"vulkan"` next to the d3d11 reason. Probably a Dart-side backend label bug; not changed here.

## Requirements

D3D-06 and D3D-08 were not ticked: D3D-08 needs 14-11, and the 4K attempt-2 result is a single run under clean conditions. The RTX data for them is in `rtx4060-runs.txt` and `docs/perf/d3d11-backend.md`.

## Self-Check: PASSED

- docs/perf/d3d11-backend.md, all `rtx-*.log` files and `rtx4060-runs.txt` exist; the Task 2 verify patterns (`"rendered":true`, six `compare uhd4k-rendered` lines, two d05 compare lines, two pickup lines, `## Verification tiers`, `MPV_KIT_BENCH_SECONDS=600`, `MPV_KIT_VIDEO_API=d3d11`, unverified) were checked.
- Commits 822ef58, 0a111b6, 353bf9a and 0d63ca0 are ancestors of HEAD; nothing was pushed (origin at f644220).

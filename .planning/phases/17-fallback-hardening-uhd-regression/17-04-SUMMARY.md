---
phase: 17-fallback-hardening-uhd-regression
plan: 04
subsystem: testing
tags: [rtx-4060, forced-backend, hwdec-guard, soak, vram, uhd-4k-1800, d3d11, vulkan, evidence]

requires:
  - phase: 17-fallback-hardening-uhd-regression
    provides: 17-02 forced backend matrix and MPV_KIT_REQUIRE_HWDEC guard, 17-03 soak harness, memory rule, rtx_run.sh and rtx-prep.txt
  - phase: 12-renderbackend-seam
    provides: run=uhd4k and run=uhd4k-rendered reference rows (final-runs.txt)
  - phase: 16-hardware-decode-zero-copy
    provides: hwd02 4K HEVC Main10 reference line
provides:
  - "RTX 4060 real-plugin probes for forced d3d11, vulkan and software: reason equals the registered expectation, nonBlack 1.0/1.0"
  - "MPV_KIT_REQUIRE_HWDEC=d3d11va positive (8 ok / 0 fail, incl. 3840x2160 HEVC Main10, pixelformat d3d11 / hwPixelformat p010, same as Phase 16) and real-GPU negative (software, loud failure)"
  - "100-round soak on d3d11, vulkan, software with flat RSS and flat process VRAM"
  - "Vulkan 4K 1800 s rendered: 0 VO drops, 0 decoder drops, 0 delayed, no errors"
  - "d3d11 4K HEVC Main10 1800 s under the d3d11va guard: 0 drops, 179 loops, hwdecCurrent=d3d11va"
  - "FINDING: forced d3d11 4K 1800 s (lavfi) had 3 and 5 VO drops in two attempts; carried to 17-05"
  - "Two session-tool fixes (forensics window UTC offset, cumulative process VRAM column)"
affects: [17-05]

# VER-02 and VER-03 evidence is complete on the RTX 4060 (hosted matrix from 17-02 plus the real-GPU cells here).
# VER-04 is NOT ticked: the d3d11 4K 1800 s gate (0 drops) failed twice; soak and vulkan 4K parts passed.
requirements-completed: [VER-02, VER-03]
requirements-partial: [VER-04]

actuals:
  tokens: 14000
  tasks: 3
  commits: 7
plan_head_before: b34a402fcb1e9d1a973ba8ceb413556ee4399997
plan_head_after: 5bee42b23263dea0283fd4c431d2bada816f9b86

tech-stack:
  added: []
  patterns:
    - "Gate before every hardware run, never overwrite a log, interrupted or failed runs are kept as recorded attempts"
    - "Process VRAM for a texture-presenting process is read from LocalUsage, not the cumulative DedicatedUsage"

key-files:
  created:
    - .planning/phases/17-fallback-hardening-uhd-regression/evidence/rtx-session.txt
    - .planning/phases/17-fallback-hardening-uhd-regression/evidence/rtx-runs.txt
    - .planning/phases/17-fallback-hardening-uhd-regression/evidence/rtx-verdicts.txt
    - .planning/phases/17-fallback-hardening-uhd-regression/evidence/rtx-*.log
    - .planning/phases/17-fallback-hardening-uhd-regression/evidence/rtx-*.vram.csv
  modified:
    - .planning/phases/17-fallback-hardening-uhd-regression/tools/rtx_run.sh
    - .planning/phases/17-fallback-hardening-uhd-regression/tools/vram_sample.ps1

key-decisions:
  - "User decision (relayed): d3d11 4K VO drops are recorded as a finding and carried to 17-05; no third attempt."
  - "User approved session-tool fixes only (rtx_run.sh, vram_sample.ps1); no product code changed (native_equal=yes at every gate)."
  - "process_dedicated_mib is unavailable for any run that presents frames; long-run VRAM uses process_local_mib plus the adapter column."

patterns-established:
  - "Get-WinEvent -FilterHashtable bounds must be local-kind DateTime"

duration: about 3h (session 07:54Z to 10:33Z, plus preparation)
completed: 2026-10-30
status: complete
---

# Phase 17 Plan 04: RTX 4060 Session Summary

**RTX 4060 evidence: all forced-backend probes, the hwdec guard (positive and negative), three soaks, Vulkan 4K 1800 s and the d3d11 HEVC 4K 1800 s pass, but forced d3d11 4K 1800 s (lavfi) had 3 and 5 VO drops in two attempts, so the VER-04 zero-drop gate is not met for d3d11.**

## Performance

- **Session:** 2026-10-30T07:54Z (gate) to 10:33Z; user reply `start` at 07:56:34Z.
- **Tasks:** 3 (Task 3 completed with a recorded finding)
- **Files modified:** evidence files for this plan plus two session tools

## Accomplishments

- **VER-02 (Windows vulkan cell):** `matrix-rtx-d3d11/vulkan/software` each match `expect_reason_<api>` verbatim, nonBlackRatio 1.0 and 1.0 after resize, exit 0.
- **VER-03:** `hwdec-require-d3d11va` 8 ok / 0 fail over four samples; the 4K HEVC Main10 line reads pixelformat=d3d11, hwPixelformat=p010, equal to Phase 16's hwd02 row. `hwdec-require-negative-software` printed `REQUIRE-HWDEC-NEGATIVE ok required=d3d11va api=software exit=1`.
- **VER-04 soaks:** each backend ran 100 rounds (39.2 s, 38.4 s, 30.9 s), renderErrors 0, deviceLost 0, idleSoak 0, apiMismatches 0, RSS flat, `vram_verdict` flat (11 checkpoints, MiB):
  - d3d11: 182.3, 135.6, 135.9, 134.5, 135.9, 135.9, 126.8, 135.9, 134.6, 135.9, 126.8 (RSS 449.4, 435.2, 434.4, 431.9, 433.2, 432.3, 436.1, 439.3, 450.1, 447.5, 448.7)
  - vulkan: 288.2, 174.0 (x8), 148.8, 174.0 (RSS curve in the SOAK line of rtx-soak-vulkan.log)
  - software: 111.3, then 51.7 (x10) (RSS curve in the SOAK line of rtx-soak-software.log)
  - lastControllerFrame was not-presented for all three (recorded only, never asserted).
- **Vulkan 4K 1800 s rendered:** frameDropCountFinal 0, decoderFrameDropCountFinal 0, voDelayedFrameCountMax 0, renderErrors 0, deviceLost false, example foreground 1773/1775 samples; process local VRAM 7.8 to 559.2 MiB max, adapter 1389.4 to 1887.3.
- **d3d11 4K HEVC Main10 1800 s (guard d3d11va):** 0 / 0 / 0, 179 loops, hwdecCurrentFinal d3d11va, 2 HWDEC-REQUIRE ok, process local VRAM flat at about 1123 MiB after the first minutes.

## Finding for 17-05 (not ticked)

Forced d3d11, 3840x2160 lavfi, 1800 s: attempt 1 had 3 VO drops (between t=191 and 251 s), attempt 2 had 5 (3 between t=251 and 311 s, 2 between t=1031 and 1091 s). Decoder drops 0, vo-delayed 0, renderErrors 0, no device loss, no standby or crash. Both attempts are kept as failed runs; attempt 1 was not relabeled. User decision: record and carry to 17-05, no third attempt.

Context, not an established cause: in both attempts the example window was covered by WindowsTerminal or msedge for much of the run (attempt 2: example foreground in about 472 of 1775 samples), while the Vulkan lavfi run and the d3d11 HEVC run ran with the example in front (1773 and 1774 of 1775 samples) and had 0 drops. The Phase 12 rendered 4K reference (`run=uhd4k-rendered`) ran only 600 s at sha 7007447, before the FIFO change 0e792c8, with the example foreground in 268 of 270 samples, so the comparison is not like-for-like (duration, FIFO, occlusion differ). Worse items for the human check: frameDropCountFinal d3d11 (3 and 5), and avsyncPeakAbs d3d11 attempt 2 and vulkan (1.96e-05 and 1.98e-05 s against 1.62e-05 s; microsecond-scale, any increase is worse by the Phase 12 method).

## Task Commits

1. **Task 1: start confirmation** - `d8e76a6` (docs)
2. **Task 2: short segment** - `682035a` (test)
3. **Task 3: long segment** - `1aadfd1` (attempt 1 failure), `3529c48` (tool fixes), `595bf5e` (attempt 2 failure and diagnostic runs), `803a04f` (vulkan and HEVC runs), `5bee42b` (full BENCH lines)

**Plan metadata:** the docs commit for this SUMMARY, STATE and ROADMAP.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug, user-approved] Forensics window 8 h early in rtx_run.sh**
- **Found during:** Task 3 (attempt 1 ledger showed `standby_during=507@00:26:43Z`)
- **Issue:** `Get-WinEvent -FilterHashtable` reads StartTime/EndTime as local time; UTC-kind bounds shifted the window by the UTC offset on this UTC+8 host.
- **Fix:** bounds passed as `.ToLocalTime()`; proven with a known 507 at 07:00:42Z (found only in its own window, absent from the session window).
- **Impact:** ledger lines before the fix (all short-segment runs and attempt 1) carry a value from a shifted window; an independent read-only check over 07:50Z to 08:45Z found no Kernel-Power 506/507, no Application 1000/1001 for the example and no CrashDumps. Attempt 2 and later lines use the fixed window.
- **Files modified:** `tools/rtx_run.sh`
- **Committed in:** `3529c48`

**2. [Rule 1 - Bug, user-approved] process_dedicated_mib is a cumulative counter**
- **Found during:** Task 3 (first long run, 7.8 to 3,442,753.7 MiB)
- **Issue:** `GPUProcessMemory.DedicatedUsage` accumulates per presented frame (about 1.96 GB/s at 4K, 30 fps); LocalUsage and TotalCommitted stay flat.
- **Fix:** `vram_sample.ps1` appends `process_local_mib` and `process_committed_mib` (columns 1 to 5 unchanged); validated on a 60 s diagnostic run before the long runs. The dedicated column is marked unavailable for frame-presenting runs.
- **Files modified:** `tools/vram_sample.ps1`
- **Committed in:** `3529c48`

**3. [Plan allowance exceeded, user-approved] Second d3d11 attempt**
- The plan's rule allows a user-approved repeat as a new attempt; attempt 2 was approved after the tool fixes and also failed.

**Total deviations:** 2 auto-fixed (Rule 1, tools only), 1 approved repeat. No product code, threshold or classifier table changed.

## Issues Encountered

- Plain `powercfg /getactivescheme` prints garbage in Git Bash (path conversion of `/`); read with `MSYS_NO_PATHCONV=1` and a GBK to UTF-8 conversion.
- The user used the terminal and browser during the d3d11 long runs; the plan's hands-off condition was not held (see the finding).

## Known Stubs

None.

## Threat Flags

None.

## Next Phase Readiness

17-05 receives: the d3d11 4K finding (with both attempts and the occlusion context), the Vulkan and HEVC passes, the compare lines, and the open question whether VER-04's d3d11 clause needs a hands-off re-measurement or a wording change (user decision at 17-05).

## Self-Check: PASSED

Verified in the repository: evidence files for every run in rtx-runs.txt, verdict lines for each probe, require, soak, vram, bench, compare and hevc item, the commits listed above, and `pubspec.yaml` unmodified.

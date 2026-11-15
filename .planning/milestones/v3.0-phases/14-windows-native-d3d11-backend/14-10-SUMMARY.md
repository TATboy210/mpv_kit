---
phase: 14-windows-native-d3d11-backend
plan: 10
subsystem: testing
tags: [d3d11, vulkan, hybrid-gpu, gtx960m, hd530, flutter-windows, frame-queue]

requires:
  - phase: 14-windows-native-d3d11-backend
    provides: 14-09 RTX 4060 verified D3D11 backend and release run 40812562348 bundle
provides:
  - "Laptop acceptance case (GTX 960M + HD 530) recorded as human-verified evidence: never software, cause isolated as not-compositor-adapter"
  - "Four traceable demo packages (+ one experimental control) built from the release-run bundle, each with bundle_match/angle_audit/debug-switch checks"
  - "Runner HighPerformancePreference (power-aware), compositor adapter log line, hybrid-GPU hint, log-only superseded/repeated/queued probe counters"
  - "FIFO ready queue of two frames with the mpv swap reported at publish (quick 261029-rcc)"
affects: [14-11, 17-fallback-hardening-uhd-regression]

status: complete
actuals:
  tokens: 130000
  tasks: 3
  commits: 8
plan_head_before: 11b728a9298302ca202560232248e132405c3dfd
plan_head_after: 3e1139ace457d35b20f029690873b4a2a116a645

tech-stack:
  added: []
  patterns:
    - "Runner opts into the discrete GPU (set_gpu_preference) because the plugin must follow Flutter's compositor adapter"
    - "Render-thread FIFO ready queue (cap 2) between publish and compositor acquire; mpv swap reported at publish"

key-files:
  created:
    - .planning/phases/14-windows-native-d3d11-backend/evidence/gtx960-laptop.txt
  modified:
    - .planning/phases/14-windows-native-d3d11-backend/evidence/laptop-package.txt
    - .planning/todos/pending/2026-10-27-gtx960-igpu-laptop-4k-falls-back-to-software.md

key-decisions:
  - "verdict=pass-with-drops-accepted: d3d11/auto never software; GTX 960M auto about 0.5 percent effective drops; HD-530-only drops are a documented limitation; user accepted by choosing the optimization path"
  - "Windows auto stays Vulkan-first for Maxwell-class GPUs (d3d11 slower there); 14-11 switch decision must carry this"
  - "Swap-at-publish alone (newest-wins) was rejected; FIFO depth 2 shipped instead"

patterns-established:
  - "Estimated numbers from pasted logs are labelled (est) and carry no durations the user did not report"

requirements-completed: [D3D-06, D3D-07]

duration: ~1 day (laptop rounds were user-paced)
completed: 2026-10-29
---

# Phase 14 Plan 10: GTX 960M + HD 530 laptop acceptance Summary

**The user's GTX 960M + HD 530 laptop no longer falls back to software: the cause was the compositor adapter (Flutter on the HD 530), a runner GPU preference moves it to the GTX 960M, and a two-frame FIFO queue brings effective drops on vulkan/auto to about 0.5 percent (estimate).**

## Performance

- **Duration:** several laptop rounds over 2026-10-29 (user-paced)
- **Tasks:** 3 (Task 1 demo package, Task 2 user checkpoint run as five package rounds, Task 3 evidence and todo)
- **Files modified:** 3 owned by this plan; code changes landed through quick tasks 261029-ljp, 261029-nwm, 261029-rcc

## Accomplishments

- Task 1: package1 built from the release-run bundle with 24/24 DLLs byte-identical, 25/25 ANGLE-free, no debug switches in the Release plugin; copied to the desktop (evidence/laptop-package.txt).
- Task 2: the user ran packages 1-4 on the laptop and pasted logs. Cause isolated by the 14-02 reason split: `Vulkan 1.3 on Intel(R) HD Graphics 530, NVIDIA GeForce GTX 960M is not the compositor adapter` (cause=not-compositor-adapter, not a Vulkan 1.2 driver).
- Task 3: evidence/gtx960-laptop.txt, todo Resolution section.

Laptop results (ORCHESTRATOR-COMPUTED ESTIMATES from the pasted logs; the user reported no durations, windows x 120 frames at 59.94 fps):

| Package | Config | Result |
|---|---|---|
| package1 11b728a (no preference) | auto and forced d3d11 on Intel HD 530, hwdec d3d11va | dropped 477-561; 726-3310 with Windows per-app "High performance" (adapter did not move); dec-drop 0 |
| package2 824a69e (HighPerformancePreference) | adapter GTX 960M | auto vulkan: done 6-7 ms, pickup about 8 ms, mpv drops about 2.7-6 percent; forced d3d11: done 8 to 15-17 ms, drops about 25-34 percent |
| package3 ade3eea (swap at pickup) | main | drops keep rising (user) |
| package3-control (swap at publish, uncommitted patch) | newest-wins | auto: mpv drops 0, superseded avg about 12-13/120 (peaks 35-42), about 10 percent effective; d3d11: mpv drops 10, superseded about 25/120, about 20 percent; pickup avg oscillates 3 to 13 ms, period about 14 s (59.94/60 Hz beat) |
| package4 0e792c8 (FIFO, final) | high-performance (AC, saver off), GTX 960M luid 00000000:000198A8 | auto vulkan: about 82 windows (about 164 s), 24 mpv drops all in one window (max_done 140 ms, single stall), superseded about 25, effective about 0.5 percent (about 0.25 percent without the stall), queued 0-113/window, repeated 0, done 0.03-0.1 ms, pickup avg 2.5-14 ms; forced d3d11: about 98 windows (about 196 s), 7 mpv drops, superseded about 400 (0-20/window), effective about 3.5 percent, done avg 3-13 ms (max about 30), queued 6-119 |
| Battery run | power-aware preference on battery | NOT RUN, unverified |

## Task Commits

1. **Task 1: demo package provenance** - `479c7a8` (docs), later package sections `0bf0bb6`, `4be7678`, `3e1139a`
2. **Task 2: user checkpoint** - no commit (user hardware runs; evidence recorded in Task 3)
3. **Task 3: evidence + todo** - recorded in the docs commit that carries this summary

Code commits that came out of the laptop rounds (quick tasks): `824a69e` (261029-ljp), `6a712eb` and `ade3eea` (261029-nwm), `0e792c8` (261029-rcc).

## Files Created/Modified

- `.planning/phases/14-windows-native-d3d11-backend/evidence/gtx960-laptop.txt` - per-run lines for all packages, probe facts, reject reason, cause, verdict.
- `.planning/phases/14-windows-native-d3d11-backend/evidence/laptop-package.txt` - provenance sections for packages 1-4 and the control package.
- `.planning/todos/pending/2026-10-27-gtx960-igpu-laptop-4k-falls-back-to-software.md` - `resolved: 2026-10-29`, `resolved_by: 14-10`, Resolution section; file not moved.

## Decisions Made

- verdict `pass-with-drops-accepted`. Basis: auto and d3d11 never choose software; the GTX 960M auto path ends at about 0.5 percent effective drops; the HD-530-only case (Flutter on the integrated GPU) remains a documented GPU-capability limitation; the user accepted continuing by choosing the optimization path rather than `block`.
- d3d11 on Maxwell is slower than vulkan (done 8-17 ms vs 6-7 ms; about 3.5 percent effective vs about 0.5 percent after the FIFO), so Vulkan stays first for this GPU class and 14-11 must decide the auto-chain switch with this data.

## Deviations from Plan

### Auto-fixed / scope additions

**1. [Rule 3 - Blocking] Laptop round 1 showed Flutter on the HD 530, not the GTX 960M**
- **Found during:** Task 2 (user run of package1)
- **Issue:** d3d11 was correct but ran on the integrated GPU; Windows per-app "High performance" did not move the compositor adapter; drops 477-3310.
- **Fix:** quick 261029-ljp (runner `HighPerformancePreference` + adapter log line), then quick 261029-nwm (power-aware preference, hybrid hint, log-only `superseded=`).
- **Commits:** 824a69e, 6a712eb, ade3eea

**2. [Rule 1 - Bug, user-directed] Hidden frame loss at the compositor hand-over**
- **Found during:** Task 2 (packages 2 and 3)
- **Issue:** swap at compositor pickup left mpv drops rising; swap at publish with newest-wins removed mpv drops but threw away 10-20 percent of frames (superseded).
- **Fix:** quick 261029-rcc, FIFO ready queue of two frames with the mpv swap reported at publish. Golden re-freeze approved by the user (only the extra ring image lines).
- **Commit:** 0e792c8

### Plan deviations

- The checkpoint ran as five package rounds instead of one; the plan's verdict rule (d3d11, non-software, drops needing the user's accept) held. The user's accept was given by choosing the optimization path, not as an explicit `accept` word (recorded as such in evidence).
- The user's pasted probe file was not stored; probe facts were reduced into gtx960-laptop.txt.
- Requirements D3D-06 and D3D-07 are listed in `requirements-completed` per the plan frontmatter; REQUIREMENTS.md was not updated by this docs run.

## Known Stubs

None.

## Open follow-ups

- **Battery-branch laptop test** (power-aware preference falling back to NoPreference): unverified, the user will re-test later.
- **HUD backend label** prints `vulkan` for forced d3d11 (14-11).
- **Linux/macOS FrameReady-from-compositor-thread** (FIFO queue change) is verified only by CI, not on hardware.
- **d3d11 on Maxwell slower than vulkan**: keep Vulkan first (14-11 decision).
- **Optional step 2 timestamp picker** (smoothed target-time on the same queue) only if the FIFO proves insufficient.
- CI for the FIFO commit chain was pending at the time of this summary.

## Threat Flags

None.

## Self-Check: PASSED

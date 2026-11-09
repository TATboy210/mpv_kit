---
phase: 12-renderbackend-seam
plan: 03
subsystem: video-output
tags: [dart, method-channel, api-freeze, adr, render-backend, reason-grammar]

requires:
  - phase: 12-01
    provides: "green hosted CI and ci_gate.sh"
provides:
  - "Dart accepts the private GPU wire names d3d11/opengl/vulkan (exact match) and maps them to the frozen MpvVideoBackend.vulkan"
  - "Always-run enum freeze guard: MpvVideoBackend.values == ['vulkan', 'software']"
  - "ADR 0004: reason grammar (head/trail, sanitising, why vocabulary), wire set, strict MPV_KIT_VIDEO_API semantics, renderer-first auto order"
affects: [12-06, 12-10, 14, 15]

actuals:
  tokens: 5300
  tasks: 2
  commits: 2
plan_head_before: edfaa2606a3ab0b80d6fd2ff51604d5e852ab5d9
plan_head_after: c0548e747a736139d3ace8b16c2645ac78aa34f3

tech-stack:
  added: []
  patterns:
    - "Private wire-name set (static const Set) validated by exact membership before the response is trusted"

key-files:
  created:
    - docs/adr/0004-render-backend-reporting.md
  modified:
    - packages/mpv_kit_video/lib/src/video_controller.dart
    - packages/mpv_kit_video/test/controller_channel_test.dart
    - packages/mpv_kit_video/test/video_controller_test.dart
    - README.md
    - packages/mpv_kit_video/README.md

key-decisions:
  - "MpvVideoBackend stays {vulkan, software}; vulkan means GPU zero-copy backend, the real API is reason's first token (ADR 0004)"
  - "Wire set is exactly d3d11|opengl|vulkan|software, case-sensitive, no prefix match; anything else stays render_init (STAB-04 unchanged)"
  - "reason grammar: head = api (renderer) on device; trail = api/renderer unavailable: why; ';' becomes ',' and control characters become spaces in device and why"
  - "MPV_KIT_VIDEO_API is native, read per create, ^[a-z0-9-]{1,16}$, never falls back (software included), intersects with the renderer selection; empty intersection is render_init"

patterns-established:
  - "New native backends only add a wire name to _gpuWireNames plus a candidate entry; no Dart public API change"

requirements-completed: []  # RBE-07 also owned by 12-06/12-10, RBE-08 by 12-10; this plan delivers the Dart side + contract only

coverage:
  - id: D1
    description: "d3d11/opengl/vulkan map to MpvVideoBackend.vulkan, reason preserved, no softwareFallback"
    requirement: RBE-07
    verification:
      - kind: unit
        ref: "controller_channel_test.dart: create maps every private GPU wire name to MpvVideoBackend.vulkan"
        status: pass
    human_judgment: false
  - id: D2
    description: "D3D11, empty, metal, garbage throw render_init and release the texture (4 dispose calls)"
    requirement: RBE-07
    verification:
      - kind: unit
        ref: "controller_channel_test.dart: unknown backend wire names still throw render_init and release the texture"
        status: pass
    human_judgment: false
  - id: D3
    description: "Concurrent creates validate independently: only textureId 8 released, controller 7 still routes events"
    requirement: RBE-07
    verification:
      - kind: unit
        ref: "controller_channel_test.dart: concurrent creates validate their own responses independently"
        status: pass
    human_judgment: false
  - id: D4
    description: "Enum freeze guard and api_freeze_test.dart byte-identical to 3a5f450; no new public identifiers in the Dart diff"
    requirement: RBE-07
    verification:
      - kind: unit
        ref: "video_controller_test.dart: MpvVideoBackend stays {vulkan, software} (API freeze); grep gate in plan verify"
        status: pass
    human_judgment: false
  - id: D5
    description: "Hosted CI build x3 and flutter-video-coverage green on 1227b93 (25 tests per OS, 91.4% line coverage)"
    requirement: RBE-07
    verification:
      - kind: other
        ref: "ci_gate.sh --jobs-success '^build \\(' --jobs-success '^flutter-video-coverage' (native-verify 40281585616, flutter-plugin 40281585561)"
        status: pass
    human_judgment: false
  - id: D6
    description: "ADR 0004 and both READMEs document the reason grammar and MPV_KIT_VIDEO_API (contract for RBE-08; implementation is 12-10)"
    requirement: RBE-08
    verification:
      - kind: other
        ref: "plan Task 2 grep verifies (ADR_OK, README_OK)"
        status: pass
    human_judgment: false

duration: 33min
completed: 2026-10-26
status: complete
---

# Phase 12 Plan 03: Render Backend Reporting Summary

**The Dart side now accepts the private GPU wire names `d3d11`, `opengl` and `vulkan` and maps all three to the frozen `MpvVideoBackend.vulkan`. Any other value still fails loudly with `render_init`. ADR 0004 fixes the `reason` grammar and the strict meaning of `MPV_KIT_VIDEO_API`, so 12-06 and 12-10 have one written contract to implement.**

## Performance

- **Duration:** about 33 min
- **Started:** 2026-10-26T06:31Z
- **Completed:** 2026-10-26T07:04Z
- **Tasks:** 2
- **Files modified:** 6 (1 created)

## Accomplishments

- `_gpuWireNames = {'d3d11', 'opengl', 'vulkan'}` is a private static const set. The validation checks exact membership (or `'software'`). The mapping now treats `'software'` as the only software value. The error message and details are unchanged, and so is the `_release(textureId)` path.
- The enum and `reason` docs now define `vulkan` as the GPU zero-copy backend and give the ADR 0004 grammar with two examples. No public member was added (the grep gate passed).
- Four new tests, all passing locally (Windows host, `MPV_KIT_REQUIRE_LIBMPV=1`, 25 tests, none skipped) and on hosted CI for linux, windows and macos:
  - wire-name mapping
  - unknown-name rejection, with exactly 4 dispose calls
  - concurrent create isolation (only textureId 8 released; controller 7 still receives `resize`)
  - enum value freeze guard
- ADR 0004 has five decisions: frozen enum, exact wire set, reason grammar with sanitising rules and the `why` vocabulary, strict `MPV_KIT_VIDEO_API`, and `auto` as data ordered by renderer quality first. It also covers Consequences, Alternatives rejected and Re-evaluation triggers.
- Root README and plugin README:
  - The new reason examples replace `software (<why Vulkan was not used>)`.
  - A `MPV_KIT_VIDEO_API` section was added.
  - The Troubleshooting entry mentions the API switch.

## Task Commits

1. **Task 1: wire names, three tests and the enum freeze guard.** `1227b93` (feat). Pushed to origin/feat/mpv-master-upgrade. CI gate ok: native-verify 40281585616, flutter-plugin 40281585561.
2. **Task 2: ADR 0004 and both READMEs.** `c0548e7` (docs). Local only; it contains documentation only.

## Files Created/Modified

- `packages/mpv_kit_video/lib/src/video_controller.dart`: private wire-name set, validation and mapping, enum and reason docs.
- `packages/mpv_kit_video/test/controller_channel_test.dart`: three new tests, added after the existing ones. No existing line changed (`git diff 3a5f450` has 0 removed lines).
- `packages/mpv_kit_video/test/video_controller_test.dart`: freeze guard for the enum value sequence.
- `docs/adr/0004-render-backend-reporting.md`: new ADR.
- `README.md`, `packages/mpv_kit_video/README.md`: reason examples and `MPV_KIT_VIDEO_API`.
- `.planning/phases/12-renderbackend-seam/evidence/ci-runs.txt`: gate result lines for 1227b93, appended by ci_gate.sh.

## Decisions Made

- The ADR examples use two software heads: a plain Vulkan failure, and `MPV_KIT_VIDEO_API=software` excluding the Vulkan candidates. There is no `d3d11` example yet, because that backend does not exist until Phase 14.
- In the ADR, the trail definition is stated as "every candidate ranked before the winner (failed or excluded)". This makes the exclusion trails required by Decision 4 consistent with Decision 3.
- The plugin README links ADR 0004 by an absolute GitHub URL. The package README is published to pub.dev, where a relative path to `docs/` would break. The root README uses a relative link.

## Deviations from Plan

### Verification adjustments

**1. [Rule 3 - Blocking] The first ci_gate.sh invocation died on a GitHub API transport error**
- **Found during:** Task 1, CI gate.
- **Issue:** `gh run view` returned `EOF` while it was polling native-verify 40281585616. The script exited 1 without a CI result. This was not a workflow failure.
- **Fix:** I confirmed with `gh run list` that the runs were still in progress, or already green, then re-ran the gate with the same arguments. It reported `CI-GATE ok sha=1227b93…`. No CI rerun was requested.
- **Commit:** none (only the evidence lines in ci-runs.txt).

The local verify printed `All tests passed!`, so the plan's literal grep held as written. Hosted CI prints `🎉 25 tests passed.` on all three OSes.

**Total deviations:** 1 (verification transport retry). **Impact:** none on the code.

## Issues Encountered

None beyond the transient `gh` EOF above.

## Known Stubs

None. `MPV_KIT_VIDEO_API` is documented only; its native implementation is 12-10's scope, as the plan states.

## Next Phase Readiness

- 12-06 can assemble native `reason` strings against ADR 0004 Decision 3. The golden `native/tests/golden/sw.txt` should start with `software (sw) on cpu`.
- 12-10 implements Decision 4. Neither requirement is marked complete here. RBE-07 still needs the native reason assembly (12-06, 12-10), and RBE-08 still needs its implementation (12-10). This plan delivers the Dart side and the written contract.

## Self-Check: PASSED

- FOUND: docs/adr/0004-render-backend-reporting.md
- FOUND: packages/mpv_kit_video/test/controller_channel_test.dart (3 new test names, each grep count 1)
- FOUND: packages/mpv_kit_video/test/video_controller_test.dart (freeze guard name, grep count 1)
- FOUND commits: 1227b93, c0548e7 (both ancestors of HEAD)
- api_freeze_test.dart unchanged vs 3a5f450

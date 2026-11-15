---
phase: 12-renderbackend-seam
plan: 05
subsystem: video-output
tags: [cpp17, meson, golden-test, fake-libmpv, video-renderer, sanitizers, ci]

requires:
  - phase: 12-01
    provides: "green hosted CI, ci_gate.sh, push-green-only authorization"
provides:
  - "native/tests/renderer_harness.h: FakeMpv (nine render symbols, scripted results, poke barrier, render hold, thread-id call log), FakeInterop, read-only golden loader/comparer, swap invariant, SetEnv, NormalizeReason"
  - "video_renderer_golden_sw: 12 software-path scenarios driving the real video_renderer.cc/vulkan_backend.cc without libmpv, OK on linux x64/arm64, windows x64/arm64, macos arm64 and sanitizers"
  - "native/tests/golden/sw.txt: expected traces, one [scenario] section each"
  - "meson: cpp language, mpv_kit_volk + mpv_kit_renderer static libs from the plugin's shared sources, sanitizer-aware slack"
affects: [12-06, 12-07, 12-08, 12-09, 12-10, 12-11, 12-12]

actuals:
  tokens: 15181
  tasks: 2
  commits: 4
plan_head_before: a866d3db7537bd3d3a613e2249a32708af25ea3a
plan_head_after: d6a3a35bf551b51eabee39e36d0d2f283a3ec9d5

tech-stack:
  added: []
  patterns:
    - "Fake MpvApi table: captureless lambdas bound to a process-wide FakeMpv; renderer touched only through its public surface"
    - "Render-thread lines are queued in program order and merged into the trace only at poke barriers (Poke + WaitPokeSeen), so traces are deterministic"
    - "Timing asserted as golden expectation + [-5 ms, +slack] bounds; the measured value is printed only on failure"

key-files:
  created:
    - native/tests/renderer_harness.h
    - native/tests/video_renderer_golden_sw.cc
    - native/tests/golden/sw.txt
  modified:
    - native/tests/meson.build
    - .planning/phases/12-renderbackend-seam/evidence/ci-runs.txt

key-decisions:
  - "Golden expectations came from reading the current video_renderer.cc and matched the renderer on the first run, locally (MSVC) and on all six CI jobs; no expectation was adjusted to fit observed behaviour"
  - "sw-resize-retries-at-once resizes after 5 failures (1600 ms backoff), not 3, so an immediate retry stays distinguishable from the scheduled one under the 1000 ms sanitizer slack"
  - "Retire-on-resize holds the first new-size render inside the fake (HoldRenders) to observe the reallocated-but-unpublished window deterministically, instead of racing it"
  - "RBE-02 stays Pending in REQUIREMENTS.md: the publish-gating (Vulkan) half is 12-07"

patterns-established:
  - "Every golden scenario ends with quiesce (swaps == render calls, skips and failures included) and teardown frees"
  - "Local pre-push check on this Windows host: MSVC build/run plus the clang frontend via VS's clang-tidy (-checks=-*,cert-err52-cpp) to catch GCC/clang-only errors"

requirements-completed: []

coverage:
  - id: D1
    description: "Fake libmpv drives the real renderer; video_renderer_golden_sw OK on linux x64/arm64, windows x64/arm64, macos arm64 and sanitizers"
    requirement: RBE-02
    verification:
      - kind: integration
        ref: "ci_gate.sh --log <six jobs> 'video_renderer_golden_sw +OK' (native-verify 40285441269 on e69ddcd)"
        status: pass
    human_judgment: false
  - id: D2
    description: "All 12 software scenarios pass under ASan + UBSan; existing render_vk_smoke (gpu-next, gpu) and stream_bridge results unchanged"
    requirement: RBE-02
    verification:
      - kind: integration
        ref: "ci_gate.sh ... --log '^sanitizers' 'GOLDEN ok scenarios=12' (native-verify 40286642083 on e612ca1; 40288892406 on d6a3a35)"
        status: pass
    human_judgment: false
  - id: D3
    description: "No product code change: git diff --stat 3a5f450 HEAD -- packages/mpv_kit_video/src is empty, and nothing under packages/ changed in this plan"
    requirement: RBE-02
    verification:
      - kind: other
        ref: "git diff --stat a866d3d HEAD -- packages/ (empty)"
        status: pass
    human_judgment: false
  - id: D4
    description: "Golden files are read-only: no ofstream, no write-mode fopen, no --update mode in harness or test"
    requirement: RBE-02
    verification:
      - kind: other
        ref: "plan Task 1 grep verify (count 0)"
        status: pass
    human_judgment: false

duration: 53min
completed: 2026-10-26
status: complete
---

# Phase 12 Plan 05: Software Renderer Golden Summary

**A fake libmpv, filled into the nine-pointer `MpvApi` table, now drives the real `video_renderer.cc` with no libmpv in the process. Twelve software-path golden scenarios cover fallback reasons, quarantine rotation, retire-on-resize, backoff and its cap, idle/active, ICC and invalid sizes. They pass on all six native-verify jobs, sanitizers included, with no change to product code.**

## Performance

- **Duration:** about 53 min
- **Started:** 2026-10-26T07:15Z
- **Completed:** 2026-10-26T08:08Z
- **Tasks:** 2 (4 commits)
- **Files:** 3 created, 1 modified (plus the evidence ledger)

## Accomplishments

- **Harness (`renderer_harness.h`, 800 lines).**
  - `FakeMpv` records every call with its thread id (12-11 needs the ids; they never appear in a trace). It scripts create, get_info and render results. `QueueFrames` controls `MPV_RENDER_UPDATE_FRAME`.
  - Two hooks make the tests deterministic. `Poke()` + `WaitPokeSeen()` is a barrier on the renderer's next `update` call. `HoldRenders()` parks a render inside the fake after its pixels are written.
  - Software targets are validated (size, `rgb0`/`bgr0`, stride, pointer). Each one is mapped to a buffer ordinal within its size generation and stamped with a frame number in its first pixel.
  - Render parameter types are compared through the enum's underlying integer. This keeps UBSan quiet about the out-of-range Vulkan types.
- **Scenarios (`video_renderer_golden_sw.cc`).**
  - Fallback and start: `sw-requested-basic`, `sw-fallback-no-interop`, `sw-fallback-interop-reason`, `sw-create-fails`.
  - Ring rotation: `sw-ring-q2` (ring 5, rendering rotates through 4 buffers) and `sw-ring-q4` (ring 7, `bgr0`, rotates through 6). Both are also checked against the test's own front/in-use/quarantine model.
  - Resize: `sw-retire-on-resize` (index -2, 64x36, old frame 4 visible until the new frame is published, its pixels read under ASan) and `sw-resize-retries-at-once`.
  - Backoff: `sw-backoff` (100, 200, 400, 800, 1600, 3200, 5000, 5000 ms; `render_error` on failures 1, 2, 4 and 8; a skip while backing off; `recovered` at the cap).
  - Other: `sw-idle-active`, `sw-icc` (bytes `010203`, then cleared), `sw-setsize-invalid`.
- **Meson.** The project now builds C and C++17. `mpv_kit_volk` is built with warnings off. `mpv_kit_renderer` builds `video_renderer.cc` and `vulkan_backend.cc` from `packages/mpv_kit_video/src` at warning_level=1 with -Werror, the same list as the Windows/Linux CMake shared sources. The golden test gets `--slack-ms=250`, or 1000 when `b_sanitize` is set. The existing test definitions are untouched, and the workflow did not need any change.
- **CI results.** The suite takes about 24 s on every job (mostly the backoff schedule up to the 5 s cap), well inside the 120 s timeout. render_vk_smoke and stream_bridge are unchanged. The Windows render_vk_smoke SKIP (77) was already there on 1227b93.

## Task Commits

1. **Task 1 (tracer): harness + `sw-requested-basic`.** `e69ddcd` (test). CI gate ok on e69ddcd (native-verify 40285441269, flutter-plugin 40285441252). The tracer feedback gate re-ran end-to-end and passed before expanding.
2. **Task 2: the 11 remaining scenarios.** `e612ca1` (test). CI gate ok on e612ca1, including `GOLDEN ok scenarios=12` in sanitizers (40286642083 / 40286642129).
3. **Compaction below the 800-line file limit.** `2daa12d` (refactor). Red on CI, see Deviations.
4. **Compile fix.** `d6a3a35` (fix). CI gate ok on d6a3a35 (40288892406 / 40288892437).

## Files Created/Modified

- `native/tests/renderer_harness.h`: fake libmpv, FakeInterop, golden I/O, invariants.
- `native/tests/video_renderer_golden_sw.cc`: the 12 scenarios and `main` (`<golden> [--slack-ms=N]`, exits 0 or 1).
- `native/tests/golden/sw.txt`: the expected traces, with a vocabulary header.
- `native/tests/meson.build`: cpp language, the two static libraries and the golden test.
- `.planning/phases/12-renderbackend-seam/evidence/ci-runs.txt`: lines appended by the gate, plus a note on the accidental red run.

## Decisions Made

See `key-decisions` in the frontmatter. The most important one: every golden line came from reading the source **before** the first run, and all of them matched. The software path behaves the way its source reads, so there is no mismatch to report.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Accidental red push (2daa12d) from a refactor that only MSVC accepted**
- **Found during:** follow-up compaction after Task 2, which brought `renderer_harness.h` under the 800-line file limit (CLAUDE.md coding style).
- **Issue:** the `Locked()` helper had a deduced `auto` return type and was called by members defined before it. MSVC accepted this, but GCC and clang reject it. native-verify run 40287928268 failed to compile on every job. It was not an intentionally red commit, but a red commit did reach origin. The push-green-only authorization only forbids pushing intentionally red commits, so this is disclosed rather than hidden.
- **Fix:** added a trailing `-> decltype(f())`. Before pushing, I checked it with the clang frontend (VS's bundled clang-tidy), which reproduces the GCC/clang error on 2daa12d and is clean on d6a3a35.
- **Files modified:** `native/tests/renderer_harness.h`
- **Commit:** `d6a3a35`. The evidence ledger has a `note sha=2daa12d red=accidental ...` line.

**2. [Rule 2 - Test validity] Resize-retry measured after 5 failures, not 3**
- **Issue:** after 3 failures the backoff is 400 ms. That is below the 1000 ms sanitizer slack, so an "immediate" retry could not be told apart from the scheduled one.
- **Fix:** resize after 5 failures (1600 ms backoff). The scenario resizes twice: once while still failing, once when the retry succeeds and recovers.
- **Commit:** `e612ca1`

**3. [Rule 3 - Determinism] Barriers instead of sleeps in `sw-idle-active`**
- The three idle pokes are synchronised with the poke barrier rather than 50 ms sleeps. That gives the same SKIP_RENDERING frames and `idle` event with no timing dependence. The plan's threat T-12-11 asks for exactly this (barrier based on poke sequence, not sleep).

## Flagged Assumption (kept verbatim from the plan)

The phase has no `-SPEC.md`, and the deterministic edge probe returns `unclassified / unresolved` for RBE-02. This plan does not invent a boundary-coverage conclusion: the golden's boundary is the scenarios listed above. Behaviour not listed (e.g. device lost, which cannot be injected before the refactor with a real VulkanContext and belongs to Phase 17 VER-01's fake-backend fault injection) stays unresolved and must **not** be auto-marked as covered by a "backstop". The RBE-02 prohibition stays `status: unresolved`.

## Issues Encountered

- This host (Windows, Git Bash) has no meson or GCC/clang. Locally I built and ran with MSVC 19.44 at `/W4 /WX`: 30 sequential and 8 parallel runs of the full suite all passed. Compile checks used the clang frontend. Acceptance comes from the CI gate.
- One transient GitHub API EOF while polling (gate on 2daa12d). That run really was red, and the cause is item 1 above.

## Next Phase Readiness

- 12-06 (reason grammar) may update the reason lines in `golden/sw.txt` in its own commit. That is the only allowed edit to those lines.
- 12-07 adds the Vulkan scenarios. `FakeMpv::VulkanTarget` is the reserved entry point, and the call log already records thread ids for 12-11.
- 12-04 (RTX 4060 baseline) is still valid: nothing under `packages/` changed.

## Self-Check: PASSED

- FOUND: native/tests/renderer_harness.h, native/tests/video_renderer_golden_sw.cc, native/tests/golden/sw.txt, native/tests/meson.build
- FOUND commits on HEAD: e69ddcd, e612ca1, 2daa12d, d6a3a35
- Task 1 and Task 2 automated verifies: VERIFY1_OK, VERIFY2_OK; CI-GATE ok on d6a3a35 with all seven log expectations
- `grep -c 'vulkan()' native/tests/video_renderer_golden_sw.cc` = 0; `git diff --stat a866d3d HEAD -- packages/` empty

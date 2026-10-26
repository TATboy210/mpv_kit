---
phase: 12-renderbackend-seam
plan: 11
subsystem: video-output
tags: [cpp17, render-thread, thread-affinity, report-swap, render-context-free, debug-assert, golden-test, integration-test, soak, architecture-doc, adr-0004]

requires:
  - phase: 12-05
    provides: "renderer_harness.h: FakeMpv call log with thread ids (frozen)"
  - phase: 12-07
    provides: "synchronous publish gate (depth 1), retire/free fixes, golden_vk"
  - phase: 12-09
    provides: "RenderBackend with Release ordering and no-op BindThread/UnbindThread"
  - phase: 12-10
    provides: "wire names, MPV_KIT_VIDEO_API"
provides:
  - "Every mpv_render_* call after Start runs on the render thread: AcquireFront only counts swaps_to_report_, RenderLoop reports them before update; the update-callback removal and RenderBackend::Release run on the render thread before it exits, between BindThread and UnbindThread"
  - "VideoRenderer::ReportSwaps (the only render_context_report_swap call site) and AssertRenderThread (debug builds) at every render/update/set_parameter/report_swap/release call site"
  - "native/tests/video_renderer_affinity_test.cc + meson registration: AFFINITY ok sw / AFFINITY ok vk / AFFINITY vk skipped: <why>"
  - "docs/ARCHITECTURE.md: thread ownership, ## RenderBackend seam, deferred-release contract; ADR 0004 follow-ups from 12-09/12-10"
  - "real_plugin_test: mounted Texture, 10 resize rounds with a front, 10 create/dispose cycles, INTEGRATION-SOAK {json}"
affects: [12-12, 14, 15, 17]

actuals:
  tokens: 8700
  tasks: 2
  commits: 5
plan_head_before: 217d24fe2ec6f9aa9fcb7dc4b05ce1afc411a5eb
plan_head_after: c3edb9ee06ed08af15cfca491bdc77b3f3ff3a0f

tech-stack:
  added: []
  patterns:
    - "Raster-thread work that needs libmpv is a counter under the renderer lock plus a wake-up; the render thread makes the call"
    - "A thread-affinity test reads the fake's per-call thread ids instead of relying on the product's debug assertions"
    - "Integration soak segments are inserted into real_plugin_test without changing its existing steps and assertions"

key-files:
  created:
    - native/tests/video_renderer_affinity_test.cc
    - .planning/phases/12-renderbackend-seam/evidence/red-local-12-11-affinity.log
  modified:
    - packages/mpv_kit_video/src/video_renderer.h
    - packages/mpv_kit_video/src/video_renderer.cc
    - packages/mpv_kit_video/src/render_backend.h
    - native/tests/meson.build
    - docs/ARCHITECTURE.md
    - docs/adr/0004-render-backend-reporting.md
    - example/integration_test/real_plugin_test.dart
    - .planning/phases/12-renderbackend-seam/evidence/ci-runs.txt

key-decisions:
  - "RED evidence is local only (user, verbatim: \"只在本地跑 golden 测试拿到红色结果作为证据，不推送\"); this replaces Task 1's red_commits=12-07,12-11 precondition"
  - "Hosted CI gates of both tasks deferred (user, verbatim: \"做好推送即可，CI 验收不着急\"); green heads c4019dc and c3edb9e pushed, gates recorded pending"
  - "The destructor keeps a free path only for a render thread that never started (std::thread threw after the context existed); it binds the backend around the release there"
  - "BindThread's result is not acted on: always true for Vulkan and software; Phase 15 (GL) decides what a failure means"
  - "ADR 0004 follow-ups applied here because the plan touches docs: `platform has no <api> backend` added to the why vocabulary; Decision 4 states a forced run also drops the gpu-next/gpu software fallback"
  - "RBE-05 and RBE-06 left Pending: both tasks' hosted gates are deferred, and RBE-06 also needs 12-12"

patterns-established:
  - "New native tests that only need the frozen harness go into new files with their own meson test()"

requirements-completed: []  # RBE-05, RBE-06: implemented and verified locally; mark complete once the deferred 12-11 gates are CI-GATE ok (RBE-06 also after 12-12)

coverage:
  - id: D1
    description: "report_swap, render, update, set_parameter, the update-callback removal and render_context_free all run on the render thread; free exactly once after the last render; create/get_info on the Start caller"
    requirement: RBE-05
    verification:
      - kind: unit
        ref: "evidence/red-local-12-11-affinity.log (41bfa89, before the change): report_swap on the raster thread x11 (sw and vk), set_update_callback removal and render_context_free on the main thread; exit 1"
        status: pass
      - kind: unit
        ref: "native/tests/video_renderer_affinity_test.cc at c4019dc (MSVC /W4 /WX, asserts on, RTX 4060): AFFINITY ok sw, AFFINITY ok vk (3 runs + 20 loops); no-ICD run: AFFINITY ok sw, AFFINITY vk skipped"
        status: pass
      - kind: integration
        ref: "Hosted CI gate for Task 1 on c4019dc (affinity test OK on linux x64 with AFFINITY ok sw/vk, windows-2025, macos-15, sanitizers; goldens and api test unchanged): DEFERRED by the user"
        status: unknown
    human_judgment: false
  - id: D2
    description: "Debug builds assert the render thread at every mpv_render_* call site; the real plugin passes with the assertions on"
    requirement: RBE-05
    verification:
      - kind: other
        ref: "scratch mutation (ReportSwaps called from AcquireFront): affinity test aborts with 'Assertion failed: std::this_thread::get_id() == render_thread_id_.load()'"
        status: pass
      - kind: e2e
        ref: "flutter build windows --debug && real_plugin_test -d windows at c4019dc: All tests passed!, vulkan (gpu-next) on NVIDIA GeForce RTX 4060 Laptop GPU"
        status: pass
    human_judgment: false
  - id: D3
    description: "Frozen goldens, api test and constants unchanged and passing"
    requirement: RBE-05
    verification:
      - kind: unit
        ref: "c4019dc: api_test 10, golden_sw 12, golden_vk 8, golden_vk_fallback, golden_vk_retire_twice, golden_sw_retire_twice OK x3; sha256sum -c golden-freeze 5xOK; CONSTANTS ok; clang front end rc=0"
        status: pass
    human_judgment: false
  - id: D4
    description: "Mounted-texture soak in real_plugin_test: 10 resize rounds of a controller with a front, 10 create/dispose cycles, no device loss"
    requirement: RBE-06
    verification:
      - kind: e2e
        ref: "real_plugin_test -d windows at c3edb9e (RTX 4060, 2 runs + forced software): INTEGRATION-SOAK {\"resizeEvents\":30,\"cycles\":10,\"renderErrors\":0,\"deviceLost\":0}"
        status: pass
      - kind: integration
        ref: "Hosted CI gate for Task 2 on c3edb9e (integration-test on ubuntu, windows, macos with INTEGRATION-SOAK {): DEFERRED by the user"
        status: unknown
    human_judgment: false
  - id: D5
    description: "ARCHITECTURE documents the seam, the candidate chain, MPV_KIT_VIDEO_API, swap and free ownership and the shared deferred-release contract"
    requirement: RBE-06
    verification:
      - kind: other
        ref: "Task 2 grep verify: ## RenderBackend seam, MPV_KIT_VIDEO_API, 0004-render-backend-reporting, quarantine + 1 all present"
        status: pass
    human_judgment: true
    rationale: "Whether the prose matches the code is a reading judgment; the grep only proves the sections exist"
  - id: D6
    description: "Timing impact of moving the swap report to the render thread (flip_page, dropped frames, vo-delayed-frame-count) under real 4K rendering"
    requirement: RBE-05
    verification: []
    human_judgment: true
    rationale: "Flagged assumption kept from the plan: only 12-12's MPV_KIT_BENCH_RENDER=1 4K run against the 12-08 reference can judge it; not covered by a backstop"

duration: 23 min (23:13Z to 23:36Z)
completed: 2026-10-26
status: complete
---

# Phase 12 Plan 11: Render-thread affinity for swaps and render context release Summary

**What this plan delivered:**
- **Render-thread affinity.** After `Start`, every `mpv_render_*` call now runs on the render thread. `AcquireFront` (raster thread) makes no libmpv call: it counts a due swap in `swaps_to_report_` and wakes the render thread. The render thread reports the swaps before its next `render_context_update`, and does not call update when it woke only for swaps. Before exiting, the render thread removes the update callback and frees the render context through `RenderBackend::Release`, between `BindThread` and `UnbindThread`. The destructor now only quits, joins and destroys the backend.
- **Proof.** A new affinity test checks the thread of every call from the fake's call log. Debug builds also assert the render thread at every call site.
- **Docs and soak.** ARCHITECTURE.md documents the seam and the shared release contract. `real_plugin_test` now soaks resize and create/dispose with the texture mounted.

## Performance

- **Duration:** about 23 min, 2026-10-26T23:13:14Z to 23:36Z (host clock).
- **Tasks:** 2 (Task 1 tracer + TDD with local RED, then GREEN; Task 2).
- **Files:** 3 product files, 2 test files (1 new), 1 integration test, 2 docs, 2 evidence files.

## Task Commits

| Step | Commit | Content | Pushed |
|---|---|---|---|
| Task 1 RED | `41bfa89` | `video_renderer_affinity_test.cc`, meson registration (tests only) | only as an ancestor of c4019dc |
| RED evidence | `fb6cd9e` | `red-local-12-11-affinity.log`, `red_local` line | as an ancestor |
| Task 1 GREEN | `c4019dc` | `swaps_to_report_`, `ReportSwaps`, `AssertRenderThread`, release on the render thread, destructor | yes (green head) |
| Task 1 evidence | `96fb962` | green_local, local_real_plugin, pending gate lines | as an ancestor |
| Task 2 | `c3edb9e` | ARCHITECTURE.md, ADR 0004 follow-ups, real_plugin_test soak | yes (green head) |

Plan metadata is this SUMMARY's docs commit. It also holds the Task 2 evidence lines, and is not pushed on its own.

## Task 1: swaps and free on the render thread

**Implementation** (`video_renderer.h` / `.cc`):
- **New members.** `int swaps_to_report_` (guarded by `mutex_`), `std::atomic<std::thread::id> render_thread_id_`, `ReportSwaps(int)` and `AssertRenderThread()`.
- **`AcquireFront`.** It moves a presented frame's swap from `swap_pending_` into `swaps_to_report_`, then calls `notify_one` when the frame was presented or the view resumed.
- **`RenderLoop` start.** It records the thread id and calls `BindThread()`. The wait predicate now includes `swaps_to_report_ > 0`.
- **After waking:**
  - if `quit_` is set, leave the loop;
  - otherwise take every counted swap and check whether there is other work (update, resize, redraw or retry);
  - with no other work, report the swaps outside the lock and `continue`, without calling update;
  - with other work, report the swaps outside the lock, then follow the old path.
- **Single call site.** The present-timeout, `SkipFrame`, failed-render, publish-gate and RenderOnce swaps all go through `ReportSwaps`. `render_context_report_swap` now appears on exactly one code line.
- **Exit path** (render thread): assert, `set_update_callback(nullptr)`, `Release`, `render_ctx_ = nullptr`, `UnbindThread`. Swaps not yet reported are dropped.
- **Destructor.** quit, notify, join. A remaining `render_ctx_` is possible only when `std::thread` threw in `Start` after the context existed. In that case the destructor frees it on its own thread, with the backend bound, and a comment says why. Then the backend is destroyed, device last.
- **Assertions.** `AssertRenderThread()` comes before `render_context_update`, `set_parameter` (ICC), `SkipFrame`'s render, `RenderBackend::Render`, every report_swap (inside `ReportSwaps`) and the exit-path release.
- **Unchanged.** Constants and reasons (`CONSTANTS ok`). `render_backend.h`'s thread comment now says Release runs on the render thread.

**Test** (`video_renderer_affinity_test.cc`, uses only the frozen harness):
- **Setup.** The main thread calls Start. A raster thread runs `AcquireFront` every 2 ms. The test sets an ICC profile and sends 12 frames, with a resize after 6, waiting after each frame until the raster thread has taken it. It then stops the raster thread and destroys the renderer on the main thread.
- **Checks on the call log:**
  - every call except create, get_info and the first `set_update_callback` runs on the thread of the first render, which is neither the raster thread nor the main thread;
  - create and get_info run on the main thread;
  - the second `set_update_callback` (the removal) comes before `free`;
  - `free` runs exactly once, after the last render;
  - at least one swap and one set_parameter were recorded;
  - no call passed a foreign render context, and the callback is no longer set.
- **Scenarios.** Software runs everywhere. Vulkan runs only with a device, using golden_vk's probe; without one it prints `AFFINITY vk skipped: <why>`.

**Tracer gate** (interactive, `end-of-phase`, automated-only verify, so no checkpoint). `⚡ Tracer verified end-to-end — expanding`, with these local checks:
- `flutter build windows --debug`: no `error C`/`warning C`; video_renderer.obj was rebuilt.
- `real_plugin_test` in a debug build (assertions on): All tests passed!
- The grep gate: exactly one non-comment `render_context_report_swap` line.
- Golden freeze 5xOK and `CONSTANTS ok`.
- The hosted CI gate is deferred.

## TDD Gate Compliance (Task 1)

| RED commit (tests only) | RED evidence (local, that exact commit, sources clean) | GREEN commit | GREEN evidence |
|---|---|---|---|
| 41bfa89 | `evidence/red-local-12-11-affinity.log`: `AFFINITY violation sw: render_context_report_swap on the raster thread (expected: render thread) (x11)`, `... render_context_set_update_callback on the main thread (removal, expected: render thread) (x1)`, `... render_context_free on the main thread (expected: render thread) (x1)`, and the same three for vk; exit 1. api_test and all five goldens OK on the same build | c4019dc | `AFFINITY ok sw`, `AFFINITY ok vk` (3 runs + 20 loops); all goldens and the api test OK ×3; no-ICD run passes with the vk scenario skipped |

- **Semantic assessment.** Every violation is the planned one, exactly what the must-have predicted: report_swap on the raster thread, free (and the callback removal) on the main thread. There was no build, timeout or fixture failure. render, update and set_parameter were already on the render thread and correctly did not fail.
- **Classifier.** The `tdd-red-evidence` classifier was not run, because the output is not one of its formats (as in 12-07, 12-09 and 12-10).
- **Push.** The RED commit was never pushed alone (`red_evidence=local-only`). It reached origin only as an ancestor of c4019dc.

## Task 2: documentation and soak

**ARCHITECTURE.md:**
- **Threading model.**
  - Ownership: every `mpv_render_*` call after Start runs on the render thread, and why (render.h; OpenGL).
  - Swap reporting: the raster thread only counts swaps.
  - A new "Render context release" bullet.
  - Dispose ordering: one sentence saying the free happens on the render thread.
- **`## RenderBackend seam`.** A table of methods, jobs and threads. What stays in the platform (`FrameReady`, `RetainFrame`, `CompositorLatency`, `VulkanInterop`). The candidate chain (`DefaultCandidates`, `Interop::BackendCandidates` / `CreateBackend`). `MPV_KIT_VIDEO_API`. The reason grammar, with a link to ADR 0004.
- **Frame ring.** The shared deferred-release contract:
  - only the old front is retired;
  - it is freed exactly once, after the first new-size frame and quarantine + 1 acquisitions;
  - 12-07 and 12-09 fixed the earlier defects;
  - platform references keep compositor-held objects alive: Windows COM reference and the `UnregisterTexture` callback; Linux GL graveyard and the 1 s release delay; macOS `CVPixelBuffer` reference count;
  - the goldens that pin the contract are listed.

**ADR 0004** (follow-ups flagged by 12-09 and 12-10):
- `platform has no <api> backend` is now in the why vocabulary.
- Decision 4 now says a forced run also drops the software fallback of a gpu-next or gpu chain.

**real_plugin_test.dart.** The diff is insertions only (112 lines, 0 removed). Before `runAsync`, the test now pumps `Directionality` → `ValueListenableBuilder<int?>` → `SizedBox(640, 360)` → `Texture`, with no child when the id is null.
- **(a)** After the `INTEGRATION` line, the original controller's texture is mounted for 10 rounds. Each round sets `setSize(640, 360)` and waits for that resize event (≤ 5 s), waits 300 ms, then does the same at 320x180. After the rounds the texture is unmounted and the test waits one frame.
- **(b)** After the original dispose, second dispose and event assertions, there are 10 cycles of create → mount → `setSize(320, 180)` → resize event (≤ 5 s) → unmount → one frame → dispose.
- **Report.** `INTEGRATION-SOAK {"resizeEvents", "cycles", "renderErrors", "deviceLost"}`, then asserts resizeEvents ≥ 20, deviceLost == 0 and renderErrors < 10.

**Local results** (`dart analyze --fatal-infos`: No issues found):
- RTX 4060, two runs: `INTEGRATION-SOAK {"resizeEvents":30,"cycles":10,"renderErrors":0,"deviceLost":0}`, All tests passed!
- `MPV_KIT_VIDEO_API=software`: same soak line, passed.

**12-08 open finding** (a second controller may never get presented frames). Segment (b) waits only for each new controller's resize event, which needs one render call and no mpv frame. All 10 arrived on Vulkan and on software. Whether the later controllers present decoded frames was not measured here. This is an observation only, and stays with 12-12.

## Decisions Made

See `key-decisions`. The user's words, verbatim: "只在本地跑 golden 测试拿到红色结果作为证据，不推送" (local RED evidence only) and "做好推送即可，CI 验收不着急" (push is enough; CI acceptance can wait).

## Deviations from Plan

**1. [User decision] RED evidence is local, not a CI run**
- The precondition `red_commits=12-07,12-11` is replaced by `red_evidence=local-only ... scope=...,12-11-task1` in push-authorization.txt.
- RED 41bfa89 was committed locally, then built and run on that exact commit with no source changes. The log is `evidence/red-local-12-11-affinity.log`, and the `red_local` line is in ci-runs.txt.
- The plan's "RED fails on CI (run id in SUMMARY)" became "RED fails locally (log in evidence)".

**2. [User instruction] Both hosted CI gates are deferred**
- Only `pending` lines are in ci-runs.txt. I glanced once: flutter-plugin 40420012135 on c4019dc succeeded.
- **Task 1** (c4019dc, native-verify 40420012159): `CI_GATE_SHA=c4019dc4e490269751050ddde3dfbdf555a7a538 bash .planning/phases/12-renderbackend-seam/tools/ci_gate.sh --jobs-success '^build \(' --jobs-success '^integration-test' --jobs-success '^sanitizers' --log '^linux \(ubuntu-24\.04\)' 'AFFINITY ok sw' --log '^linux \(ubuntu-24\.04\)' 'AFFINITY ok vk' --log '^windows \(windows-2025' 'video_renderer_affinity_test +OK' --log '^macos \(macos-15\)' 'video_renderer_affinity_test +OK' --log '^sanitizers' 'video_renderer_affinity_test +OK' --log '^sanitizers' 'video_renderer_golden_vk +OK' --log '^sanitizers' 'video_renderer_golden_sw +OK' --log '^linux \(ubuntu-24\.04\)' 'video_renderer_api_test +OK'`
- **Task 2** (c3edb9e, native-verify 40420762139, flutter-plugin 40420762174): `CI_GATE_SHA=c3edb9ee06ed08af15cfca491bdc77b3f3ff3a0f bash .planning/phases/12-renderbackend-seam/tools/ci_gate.sh --jobs-success '^integration-test' --log '^integration-test \(ubuntu' 'INTEGRATION-SOAK \{' --log '^integration-test \(windows' 'INTEGRATION-SOAK \{' --log '^integration-test \(macos' 'INTEGRATION-SOAK \{'`
- **Windows runners:** the affinity test prints `AFFINITY vk skipped` there (no Vulkan ICD), and meson still reports it as OK, because the binary exits 0. That matches the user's "windows-2025 / windows-11-arm accept golden_vk* OK-or-SKIP".
- **Superseded run:** if c3edb9e's push cancelled c4019dc's native-verify, the Task 2 run also covers Task 1's native tests, because c3edb9e contains c4019dc.

**3. [Rule 2 – doc correctness] `render_backend.h` thread comment updated**
- The file is not in the plan's list, but its comment said Release runs "before the render thread starts or after it was joined". That is no longer true.
- Comment-only change, in c4019dc.

**4. [Orchestrator note] ADR 0004 follow-ups applied**
- `docs/adr/0004-render-backend-reporting.md` is not in the plan's file list.
- The orchestrator asked for these follow-ups to be applied if this plan touches docs, and it does. Two text additions, in c3edb9e.

**5. [Test design]**
- **Raster pacing.** The test waits after each frame until the raster thread has taken it (`WaitAcquisitions(2)`). Without that, frames came faster than the 2 ms raster on Windows, and the render thread reported the pending swaps itself. The first draft's RED then showed only the free and callback violations, not the raster-thread swaps the must-have names.
- **Violation output.** Each violation is printed once, with a count.

**6. [Interface detail]**
- `BindThread()`'s bool is not acted on. It is always true for Vulkan and software, and Phase 15 decides what a GL bind failure means.
- `AcquireFront` also wakes the render thread when it presents a frame (`presented || resumed`), as the plan specified.

**Total deviations:** 6
- 2 user-directed
- 1 Rule 2 (doc comment)
- 1 orchestrator-directed doc follow-up
- 1 test-design note
- 1 interface note

**Impact:** no scope creep. The frozen goldens, api test and constants are unchanged.

## Issues Encountered

None. No new product defect was found. The local Python heredoc edits needed `encoding='utf-8'`, because the renderer sources contain non-ASCII characters; the remaining `.cc` edits were made with the Edit tool. LF line endings were kept.

## Flagged Assumption (kept from the plan)

The RBE-05 edge probe is `unclassified / unresolved`. This plan proves which thread makes each call, through the fake's call log and the debug assertions. The timing impact of reporting swaps on the render thread is judged only by 12-12's real 4K render run (`MPV_KIT_BENCH_RENDER=1`, mounted texture, compared with 12-08's reference for dropped frames, `vo-delayed-frame-count` and avsync). It is **not** marked covered by a backstop.

## Known Stubs

None.

## Threat Flags

None. No new surface.
- **T-12-23 (swap ↔ flip_page) mitigated:** the swaps are reported before update, with no lock held, and a swap-only wake skips update. The real check is 12-12.
- **T-12-24 (free and teardown order) mitigated:** free runs on the render thread before join returns, and the backend is destroyed after the join. The affinity test asserts free exactly once after the last render. The sanitizer job runs the new test with the deferred gate.

## Next Phase Readiness

- **For Phase 15 (GL):** `BindThread`/`UnbindThread` are now called on the render thread. The only remaining Start-thread calls are Create and get_info.
- **For 12-12:** run the two deferred gates above first. Then use the real-render 4K run to judge the timing assumption.
- **Requirements:** RBE-05 can be marked complete once both gates are OK. RBE-06 needs those gates and 12-12.

## Self-Check: PASSED

- Files exist: native/tests/video_renderer_affinity_test.cc, evidence/red-local-12-11-affinity.log, this SUMMARY.
- Commits 41bfa89, fb6cd9e, c4019dc, 96fb962 and c3edb9e are ancestors of HEAD. c4019dc and c3edb9e are on origin/feat/mpv-master-upgrade.
- `sha256sum -c` gives 5 × OK; `CONSTANTS ok`.

---
*Phase: 12-renderbackend-seam*
*Completed: 2026-10-26*

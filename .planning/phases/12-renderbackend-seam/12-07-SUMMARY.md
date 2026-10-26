---
phase: 12-renderbackend-seam
plan: 07
subsystem: video-output
tags: [cpp17, vulkan, golden-test, lavapipe, moltenvk, publish-gate, retire-on-resize, use-after-free, ci]

requires:
  - phase: 12-05
    provides: "fake-libmpv harness (renderer_harness.h) and golden_sw"
  - phase: 12-06
    provides: "ADR 0004 reason grammar on both paths; golden_sw in the new grammar"
provides:
  - "video_renderer_golden_vk: 8 Vulkan scenarios on the runner's real Vulkan 1.3 device; `GOLDEN skip:` + exit 77 without loader, instance or 1.3 device"
  - "FakeVulkanInterop + never-freed FakeImages registry: DOUBLE DESTROY / USE AFTER DESTROY are invariants, not test UB"
  - "Publish-gate fix: a Vulkan frame waits for its own timeline value right after its render call and is published in the same RenderOnce (pipeline depth 2 -> 1)"
  - "AllocateRing fix: `*keep_retired = SharedImage{};` after the retire copy; the retired front is destroyed once, after its countdown"
  - "evidence/golden-freeze.sha256 (5 files), frozen at 2d639ab"
affects: [12-08, 12-09, 12-10, 12-11, 12-12]

actuals:
  tokens: 17200
  tasks: 5
  commits: 10
plan_head_before: f303b3ceeb64582aebad753150a8884e2122764d
plan_head_after: 2d639ab87f2ee38e37334971d7b8ae8dab88eba9

tech-stack:
  added: []
  patterns:
    - "Fake platform objects live in a registry that is never freed, so lifetime bugs in the code under test are counted, not undefined"
    - "Render-thread lines that no barrier can wait for (an event raised while the thread sits in a timeline wait) are awaited with FakeMpv::WaitNoted"
    - "RED evidence is a local golden run on the exact test-only commit; only green heads are pushed (user decision)"

key-files:
  created:
    - native/tests/video_renderer_golden_vk.cc
    - native/tests/golden/vk.txt
    - .planning/phases/12-renderbackend-seam/evidence/golden-freeze.sha256
    - .planning/phases/12-renderbackend-seam/evidence/red-local-12-07-publish-gate.log
    - .planning/phases/12-renderbackend-seam/evidence/red-local-12-07.log
    - .planning/phases/12-renderbackend-seam/evidence/explore-12-07-fallback-after-resize.log
  modified:
    - native/tests/renderer_harness.h
    - native/tests/meson.build
    - packages/mpv_kit_video/src/video_renderer.cc
    - packages/mpv_kit_video/src/video_renderer.h
    - packages/mpv_kit_video/src/vulkan_backend.cc
    - .planning/phases/12-renderbackend-seam/evidence/ci-runs.txt
    - .planning/phases/12-renderbackend-seam/evidence/push-authorization.txt

key-decisions:
  - "Publish gate (user decision 1 = A): synchronous wait right after the Vulkan render call; the top-of-round gate and pending_front_ are removed. Behaviour change against the 12-04 baseline; 12-08 re-measures"
  - "windows-2025 x64 has no lavapipe Vulkan instance, so its golden_vk expectation is OK|SKIP, as for windows-11-arm (user decision 2 = a)"
  - "RED evidence is local-only for 12-07 Task 2, the 12-07 publish-gate fix and 12-11 Task 1. Quoted user reply: \"只在本地跑 golden 测试拿到红色结果作为证据，不推送\". ci-runs.txt holds `red_local` lines, not `red sha=… run=…`"
  - "The probe also skips on `vkCreateInstance failed`, not only on `Vulkan loader` / `no Vulkan 1.3 device`: that is the windows runners' actual reason"
  - "Retire defect confirmed (RED branch): the fix is exactly the planned line, plus a 3-line comment"

patterns-established:
  - "Golden files encode correct behaviour; the RED commit carries tests and golden only, and the GREEN commit carries product code only"
  - "Frozen five-file golden set; later plans add new test files only"

requirements-completed: [RBE-02, RBE-06]

coverage:
  - id: D1
    description: "Vulkan publish gate: no front frame while frame 1's timeline value is unsignalled, frame 1 after the signal, one swap per render (vk-publish-gate)"
    requirement: RBE-02
    verification:
      - kind: integration
        ref: "ci_gate.sh on f77378f (native-verify 40341371979 attempt 2, flutter-plugin 40341371920): CI-GATE ok; golden_vk OK on linux x64, macos-15, sanitizers; SKIP on windows-2025"
        status: pass
      - kind: other
        ref: "evidence/red-local-12-07-publish-gate.log (f6df1fa, pre-fix): `frame 1 was published before its GPU work completed`, swaps (7) != render calls (4)"
        status: pass
    human_judgment: false
  - id: D2
    description: "Vulkan reasons, ring rotation q2/q4, gpu_timeout -> backoff -> recovered, 8K-style ring 7 -> ring 5 fallback pinned by golden_vk"
    requirement: RBE-02
    verification:
      - kind: integration
        ref: "ci_gate.sh on e3ef12b (native-verify 40346404234 attempt 2, flutter-plugin 40346404382): CI-GATE ok; `GOLDEN ok scenarios=8` on linux x64/arm64, macos-15, sanitizers"
        status: pass
    human_judgment: false
  - id: D3
    description: "Retire-on-resize: the retired old front stays alive until quarantine+1 acquisitions and is destroyed exactly once; teardown with a retired generation destroys each image once"
    requirement: RBE-06
    verification:
      - kind: other
        ref: "evidence/red-local-12-07.log (c452ccd, pre-fix): USE AFTER DESTROY + DOUBLE DESTROY serial=4"
        status: pass
      - kind: integration
        ref: "ci_gate.sh on e3ef12b: vk-retire-on-resize and vk-teardown-while-retired OK, including under ASan+UBSan (sanitizers job)"
        status: pass
    human_judgment: false
  - id: D4
    description: "Real plugin on the RTX 4060 after both product fixes"
    requirement: RBE-02
    verification:
      - kind: e2e
        ref: "flutter test integration_test/real_plugin_test.dart -d windows on f77378f and e3ef12b: All tests passed!, backend vulkan (gpu-next) on NVIDIA GeForce RTX 4060 Laptop GPU"
        status: pass
    human_judgment: false
  - id: D5
    description: "Golden freeze: 5 files hashed, sha256sum -c OK"
    verification:
      - kind: other
        ref: "sha256sum -c evidence/golden-freeze.sha256 (5 x OK); golden_freeze sha=a0d238d… in ci-runs.txt"
        status: pass
    human_judgment: false
  - id: D6
    description: "RBE-06 release boundary in Flutter unregistration (Windows unregister callback, Linux 1 s timer, macOS CVPixelBuffer refcount) is NOT covered here"
    requirement: RBE-06
    verification: []
    human_judgment: true
    rationale: "Flagged assumption kept verbatim from the plan: documented in 12-11, observed by the 12-12 soak; must not be marked covered by a backstop"

duration: 3h 0m (this continuation)
completed: 2026-10-26
status: complete
---

# Phase 12 Plan 07: Vulkan golden and two ring-lifetime fixes Summary

**What this plan delivered:**
- Real-device Vulkan golden (`video_renderer_golden_vk`, 8 scenarios), with a fake platform interop whose image registry is never freed. A second destroy or a use after destroy is therefore reported as an invariant instead of being undefined behaviour in the test.
- Two defects proved red locally and then fixed:
  - **Publish gate.** A Vulkan frame could become visible before its GPU work finished.
  - **Retire on resize.** The retired front image was destroyed right away and then destroyed again.
- Both green heads passed the CI gate, and the five golden files are now frozen.

## Performance

- **Duration:** about 3 h in this continuation (2026-10-26T14:21Z to 17:19Z). Most of it went to hosted CI: the linux x64 apt step stalled twice, and the second rerun took 49 min in apt.
- **Tasks:** 5 (publish-gate RED, publish-gate GREEN, Task 1, Task 2 RED+GREEN, Task 3)
- **Files modified:** 5 product/test files, 1 meson file, 7 evidence files

## Accomplishments

- **Harness** (`renderer_harness.h`):
  - `FakeVulkanInterop` creates real B8G8R8A8 device-local images on the device the renderer picked.
  - `FakeImages` is a process-wide registry that is never freed.
  - `FakeMpv` gets a Vulkan target with three signal modes: immediate, deferred and never. It also gets `SignalPending()` and `WaitNoted()`.
- **Golden scenarios** (`golden/vk.txt`, 8 total):
  - `vk-publish-gate`
  - `vk-reasons` (5 ADR 0004 cases)
  - `vk-ring-q2` and `vk-ring-q4`: 12 frames each, every render checked against a compositor quarantine model
  - `vk-gpu-timeout`: 1 s timeout, 100 ms backoff, automatic retry, `recovered`; `retry-ms 1100` within slack
  - `vk-ring-fallback`: the 6th CreateImage fails at ring 7, then ring 5 / quarantine 2
  - `vk-retire-on-resize`
  - `vk-teardown-while-retired`
- **Meson:** registers `video_renderer_golden_vk`. On macOS it puts the Homebrew loader libdir on `DYLD_FALLBACK_LIBRARY_PATH`, and CI shows it working (`DYLD_FALLBACK_LIBRARY_PATH=/opt/homebrew/Cellar/vulkan-loader/1.4.357.0/lib`, macos-15 OK).
- **Product fixes:**
  - `f77378f` (video_renderer.cc/.h, +37/−75): the publish gate now waits synchronously.
  - `e3ef12b` (vulkan_backend.cc): one code line plus a comment.

## Task Commits

1. `fe47cfe` docs: appended the local-only RED evidence authorization to push-authorization.txt.
2. **Publish-gate RED.** `f6df1fa` test (tests and golden only, not pushed alone). Local evidence is committed in `392828d`.
3. **Publish-gate GREEN.** `f77378f` fix. This head was pushed. CI gate OK (Task 1 tracer gate).
4. **Task 1 (tracer).** The harness, the probe, `vk-publish-gate` and meson landed in `f6df1fa`. The tracer feedback gate was re-run with auto/end-of-phase semantics: CI gate OK on `f77378f` before any expansion.
5. **Task 2 RED.** `c452ccd` test (local evidence in `321c35f`).
6. **Task 2 GREEN.** `e3ef12b` fix. Pushed, CI gate OK. Gate evidence and RTX 4060 runs are recorded in `a0d238d`.
7. **Task 3 freeze.** `2d639ab` chore.

Plus `c6493e1` from the previous executor: the 12-06 Task 2 gate record.

## TDD Gate Compliance

| Cycle | RED commit (tests only) | RED evidence (local, that exact commit) | GREEN commit | GREEN evidence |
|---|---|---|---|---|
| publish gate | f6df1fa | `GOLDEN invariant scenario=vk-publish-gate: frame 1 was published before its GPU work completed`; `swaps (7) != render calls (4)`; first mismatch at line 10, expected `acquire index=-1 64x36 serial=none`, actual `acquire index=0 64x36 serial=1` | f77378f | CI gate OK on f77378f; RTX 4060 real plugin passed |
| retire on resize | c452ccd | `USE AFTER DESTROY serial=4` (acquire and RetainFrame), `DOUBLE DESTROY serial=4` in both retire scenarios; mismatch at line 20, expected `destroy serial=5`, actual `destroy serial=4`; the other 6 scenarios OK | e3ef12b | CI gate OK on e3ef12b (all 8 scenarios OK on 4 Vulkan jobs, sanitizers included) |

- **Semantic assessment.** Both REDs fail on the planned assertions:
  - The publish-gate invariant and the destroy-count invariants are the behaviour under test.
  - There were no build, fixture or discovery failures. Builds were MSVC `/W4 /WX`, run on a tree clean under `native/` and `packages/`.
- **Classifier.** The `tdd-red-evidence` classifier was not run, because the golden output is none of its supported report formats (TAP, JUnit, go test, swift-testing, unittest).
- **Pushes.** RED commits reached origin only as ancestors of green heads.

## Decisions Made

See `key-decisions`. The user's words:
- Decisions 1/2: "决定 1    A（推荐）决定 2  a"
- RED evidence: "只在本地跑 golden 测试拿到红色结果作为证据，不推送"

## Deviations from Plan

**1. [User-authorized product change] Publish-gate defect fixed in video_renderer.cc/.h (Finding 1)**
- **Found during:** Task 1, by the exploratory local run on f303b3c.
- **Issue:** the end-of-RenderOnce publish block (`front_ = back`, swap counting, `FrameReady`) also ran for Vulkan, contradicting its own comment. 857ccc2 introduced it.
  - An unsignalled frame was acquirable at once.
  - The top-of-round gate then published it a second time.
  - Measured: `swaps (10) != render calls (6)` pre-plan, `(7) != (4)` in the final scenario.
- **Fix:** user decision 1 = A.
  - The wait moved to just after the Vulkan render call, including the probe accounting and the failure path.
  - The deferred gate and `pending_front_` were removed, and the comments explain why.
- **Diff size:** +37/−75. The diff was expected to be about 15 lines; it is larger mostly because the deferred block was deleted. This exceeds the plan's one-line product limit with user authorization.
- **Behaviour change against 12-04:** pipeline depth 2 → 1, so the render thread again blocks on each frame's GPU work. 12-08 must re-measure.
- **Test script:** the `vk-publish-gate` script differs from the plan text. It never calls `Sync` while the render thread is parked in the timeline wait; it waits on `WaitRenders` and `WaitFrameReady` instead.
- **Commits:** f6df1fa (RED), f77378f (GREEN).

**2. [User decision 2] windows-2025 x64 accepts golden_vk OK or SKIP**
- The Task 1 and Task 2 gates used `video_renderer_golden_vk +(OK|SKIP)` for `^windows \(windows-2025` only. The other three jobs stayed strict OK.
- Observed SKIP reason: `GOLDEN skip: software (sw) on cpu; vulkan/gpu-next unavailable: vkCreateInstance failed`. Accordingly the probe also skips on `vkCreateInstance failed`. That is a recorded deviation from the plan's two skip reasons.

**3. [User decision] RED evidence is local-only**
- This replaces Task 2's `red_commits=12-07,12-11` precondition and its `red sha=… run=…` line.
- `ci-runs.txt` has two `red_local sha=<40-hex> host=… log=… line=…` lines.
- Task 2's first verify was adapted to read the local log (PASS). As written in the plan, that verify (and grep for `^red sha=`) **will fail by design**; this deviation is the record of why.

**4. [Accepted] renderer_harness.h is 1120 lines, over the 800-line file guideline.** The user did not object. It is now frozen.

**5. [Rule 3 – harness] `FakeMpv::WaitNoted` added; `Note` now notifies.** `vk-gpu-timeout` must wait for `event gpu_timeout` while the render thread cannot observe a poke.

**6. [Plan text] Task 1's verify #1 product clause.** `git diff 3a5f450 HEAD -- vulkan_backend.cc` is empty is true at the Task 1 head f77378f. It is not true at the plan's HEAD, because Task 2's planned RED-branch fix changed that file.

**7. [Infra] CI interruptions, retried only for infrastructure causes.**
- The linux (ubuntu-24.04) apt step stalled on both pushes. It was cancelled after 20–22 min and rerun once with `CI_GATE_RERUN_INFRA=1`; `note` and `rerun` lines are in ci-runs.txt.
- Gate invocations also hit GitHub API 502/503 errors and were simply re-run.

**Total deviations:** 7 (3 user-authorized, 1 accepted, 1 harness helper, 1 plan-text artefact, 1 infra). **Impact:** one intended behaviour change (pipeline depth), which 12-08 re-measures. No golden expectation was fitted to a defect.

## Issues Encountered

**New unplanned finding (not fixed, needs a decision): use after destroy in the 8K ring fallback after a resize.**

- **How it was found:** an exploratory scratch scenario, not committed as a test. Log: `evidence/explore-12-07-fallback-after-resize.log`, run on HEAD with both fixes.
- **Repro:** latency 4 (ring 7), 64x36 frames, then `SetSize(32,18)` with the 6th CreateImage failing.
- **What happens:**
  1. `AllocateRing(7)` fails, and its failure path `FreeRing()` → `FreeRetired()` destroys the just-retired front (serial 4).
  2. The fallback `AllocateRing(5)` succeeds, but `video_renderer.cc` does not clear `retired_front_` on that branch. It does clear it on the non-fallback failure branch ("AllocateRing freed everything").
  3. AcquireFront then returns and RetainFrames the destroyed image: `USE AFTER DESTROY serial=4`.
- **History:** this predates 12-07. Before e3ef12b the same image was already destroyed one step earlier, by `DestroyAll(ring_)`.
- **Reach:** only on Windows (latency 4) when ring 7 does not fit after a resize.
- **Minor, cosmetic:** the fallback log line reads `allocation failed at ring 5, retried with a ring of 5`, because `ring_size_` is updated before it is logged.
- **Constraints on a fix:** the golden set is frozen, so a regression test would have to be a new file. Any fix touches product code. The decision is the user's.

## Known Stubs

None.

## Threat Flags

None. T-12-14 and T-12-15 were mitigated as planned. The sanitizer job ran all 8 Vulkan scenarios green.

## Flagged Assumption (kept from the plan)

This plan proves only the release boundaries the golden covers:
- the retired image survives until its countdown;
- it is destroyed exactly once;
- teardown with a retired generation destroys each image once.

The Flutter unregistration half is left to each platform's existing mechanism: the Windows unregister callback, the Linux 1 s timer plus populate cleanup, and macOS CVPixelBuffer refcounting. 12-11 documents it and the 12-12 soak observes it. It is **not** covered here, and a "backstop" must not mark it covered.

## Next Phase Readiness

- 12-08 can re-measure the RTX 4060 baseline on e3ef12b. The pipeline depth changed, so the 12-04 numbers are no longer the comparison point for the Vulkan path.
- 12-09 onward must keep `sha256sum -c evidence/golden-freeze.sha256` OK. 12-09's plan text still mentions `pending_front_` and the deferred gate, which no longer exist; its planner or executor must adapt.
- The fallback-after-resize use after destroy above is open.

## Self-Check: PASSED

- Files exist: video_renderer_golden_vk.cc, golden/vk.txt, golden-freeze.sha256, red-local-12-07-publish-gate.log, red-local-12-07.log, explore-12-07-fallback-after-resize.log.
- Commits on this branch: fe47cfe, f6df1fa, 392828d, f77378f, c452ccd, 321c35f, e3ef12b, a0d238d, 2d639ab.
- `sha256sum -c` gives 5 x OK.

---
*Phase: 12-renderbackend-seam*
*Completed: 2026-10-26*

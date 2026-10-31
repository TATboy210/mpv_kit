---
phase: 12-renderbackend-seam
plan: 09
subsystem: video-output
tags: [cpp17, render-backend, refactor, pure-move, vulkan, software, candidate-chain, golden-test, use-after-free, ci]

requires:
  - phase: 12-07
    provides: "golden_sw / golden_vk / golden_vk_fallback, frozen harness, publish-gate and retire fixes"
  - phase: 12-08
    provides: "post-fix pre-move RTX 4060 reference; go decision for the move"
provides:
  - "src/render_backend.h: Backend, RendererChoice, BackendCandidate, DefaultCandidates, WaitResult, TargetView, RenderBackend (shared deferred-release contract), CreateSoftwareBackend, CreateVulkanBackend, SanitizeReasonField"
  - "SoftwareBackend (video_renderer.cc) and VulkanRenderBackend (vulkan_backend.cc), both in anonymous namespaces; no new .cc file, no build-file change"
  - "VideoRenderer with no backend branches; Start is a loop over Interop::BackendCandidates(choice), with Interop::CreateBackend(api) as the platform hook (no platform overrides either)"
  - "Retire-twice fix (d63d655) with two new goldens: video_renderer_golden_vk_retire_twice and video_renderer_golden_sw_retire_twice"
  - "tools/constants_audit.sh (3afb2d1): CONSTANTS ok against 3a5f450 on every move commit"
affects: [12-10, 12-11, 12-12, 13, 14, 15]

actuals:
  tokens: 23300
  tasks: 4
  commits: 7
plan_head_before: aad75dcafb2d73c2805ca81d4278d2ad5dbf8dc1
plan_head_after: 0479f4f2b8252eb196c70ea43f2c66a30bd9bbe0

tech-stack:
  added: []
  patterns:
    - "Pure-move commits are checked four ways: constants audit, golden freeze sha256, all goldens, and a list of string literals added and removed"
    - "Start() behaviour is diffed between two builds with a scratch probe (36 cases: reason, create attempts, log lines, image lifetimes), because the goldens do not capture log lines"
    - "One backend instance per candidate api for the whole Start (one device initialisation per api); the api's backend is released before the next api is tried"

key-files:
  created:
    - packages/mpv_kit_video/src/render_backend.h
    - native/tests/video_renderer_golden_vk_retire_twice.cc
    - native/tests/video_renderer_golden_sw_retire_twice.cc
    - native/tests/golden/vk_retire_twice.txt
    - native/tests/golden/sw_retire_twice.txt
    - .planning/phases/12-renderbackend-seam/tools/constants_audit.sh
    - .planning/phases/12-renderbackend-seam/evidence/red-local-12-09-retire-twice.log
    - .planning/phases/12-renderbackend-seam/evidence/explore-12-09-resize-after-failed-render.log
  modified:
    - packages/mpv_kit_video/src/video_renderer.h
    - packages/mpv_kit_video/src/video_renderer.cc
    - packages/mpv_kit_video/src/vulkan_backend.cc
    - native/tests/meson.build
    - .planning/phases/12-renderbackend-seam/evidence/ci-runs.txt

key-decisions:
  - "Retire-twice use after destroy fixed before the move (user decision, verbatim \"a\"): new goldens RED locally, then `retired_front_ = Frame{};` at the top of RenderOnce's resize block"
  - "The software path of the same defect is covered by a sibling golden (video_renderer_golden_sw_retire_twice), cheap with the frozen harness"
  - "RenderBackend::Create returns the mpv_render_context_create result and sets *why; device_failed() marks a device that failed to initialise, so the engine can give every remaining candidate of that api the same trail"
  - "backend() returns the backend's frame_kind(), or kSoftware when no backend was created (as before the move)"
  - "Final hosted CI gate (Task 3 head 0479f4f) deferred by the user: \"做好推送即可，CI 验收不着急\""
  - "Only RBE-03 is marked complete. RBE-04 still needs the RTX 4060 4K 30-minute comparison (12-12); RBE-06 is shared with 12-11/12-12"

patterns-established:
  - "New regression goldens for later defects go into new files; the five frozen files stay byte-identical"

requirements-completed: [RBE-03]

coverage:
  - id: D1
    description: "Retire twice: after a resize whose first render failed, a second resize must not hand out the generation-before-last front (Vulkan: destroyed image + RetainFrame; software: freed pixels)"
    requirement: RBE-06
    verification:
      - kind: other
        ref: "evidence/red-local-12-09-retire-twice.log (149f0be, pre-fix): vk `USE AFTER DESTROY serial=1` (acquire and RetainFrame), sw `USE AFTER FREE`; both mismatches at the window acquire line"
        status: pass
      - kind: integration
        ref: "ci_gate.sh on d63d655 (native-verify 40396889363 attempt 2, flutter-plugin 40396889358): CI-GATE ok; both new goldens OK on linux x64/arm64, macos-15, sanitizers; sw OK and vk SKIP on both windows"
        status: pass
      - kind: e2e
        ref: "real_plugin_test on the RTX 4060 at d63d655: All tests passed!, vulkan (gpu-next) on NVIDIA GeForce RTX 4060 Laptop GPU"
        status: pass
    human_judgment: false
  - id: D2
    description: "Software path through RenderBackend, behaviour unchanged (Task 1)"
    requirement: RBE-03
    verification:
      - kind: integration
        ref: "ci_gate.sh on 9f50d46 (native-verify 40400348159, flutter-plugin 40400348149): CI-GATE ok, attempt 1; all 8 meson tests OK on linux x64/arm64, macos-15, sanitizers"
        status: pass
    human_judgment: false
  - id: D3
    description: "Vulkan path through RenderBackend; engine has no backend branches; render_vk.h only in vulkan_backend.cc; vulkan_backend.h unchanged (Task 2)"
    requirement: RBE-03
    verification:
      - kind: integration
        ref: "ci_gate.sh on a8fc38a (native-verify 40403080039 attempt 2, flutter-plugin 40403080073): CI-GATE ok; render_vk_smoke + _gpu and all 5 goldens OK on linux x64/arm64, macos-15, sanitizers; integration-test on 3 platforms success"
        status: pass
    human_judgment: false
  - id: D4
    description: "Candidate chain as data; Start output identical to Task 2 (Task 3)"
    requirement: RBE-04
    verification:
      - kind: other
        ref: "Local: golden freeze 5xOK, all 5 goldens OK, clang front end rc=0, CONSTANTS ok, flutter build windows --debug OK; scratch Start() probe output identical on a8fc38a and 0479f4f (36 cases); RTX 4060 real_plugin_test passed at 0479f4f"
        status: pass
      - kind: integration
        ref: "Hosted CI gate on 0479f4f: DEFERRED by the user (\"做好推送即可，CI 验收不着急\"); native-verify 40412604466 left running, the orchestrator runs the gate"
        status: deferred
    human_judgment: false
  - id: D5
    description: "RBE-04's RTX 4060 4K 30-minute comparison against the pre-move reference"
    requirement: RBE-04
    verification: []
    human_judgment: true
    rationale: "Flagged assumption kept from the plan: belongs to 12-12 and must not be marked covered by a backstop"

duration: 2h 27m (20:12Z to 22:40Z, including about 1h 40m of hosted CI waits)
completed: 2026-10-26
status: complete
---

# Phase 12 Plan 09: RenderBackend seam (pure move) and data-driven candidate chain Summary

**What this plan delivered:**
- First, one more ring-lifetime defect was proven red locally and fixed (user decision "a"). A resize that followed a resize without a frame handed out an image that had already been destroyed.
- Then both backends moved, behaviour unchanged, behind `RenderBackend` (`src/render_backend.h`):
  - `SoftwareBackend` lives in video_renderer.cc;
  - `VulkanRenderBackend` lives in vulkan_backend.cc.
- `VideoRenderer` now holds only the generic engine. `Start` walks a candidate chain that is data (`DefaultCandidates` / `Interop::BackendCandidates` / `Interop::CreateBackend`).

## Performance

- **Duration:** 2026-10-26T20:12Z to 22:40Z. About 1 h 40 min of that was hosted CI: two apt-mirror stalls, each cancelled after 20 min and rerun once. One rerun's apt step took about 41 min and then completed.
- **Tasks:** 4 (the retire-twice fix with RED and GREEN, then plan Tasks 1, 2 and 3)
- **Files:** 4 product files (one new), 5 test files (four new), 1 tool, evidence

## Task Commits

| Step | Commit | Content |
|---|---|---|
| (prior executor) | `3afb2d1` | `tools/constants_audit.sh` (plan Task 1 step 1, mutation-tested), exploration log of the defect |
| Retire-twice RED | `149f0be` | two new goldens, two golden files, meson registration (tests only) |
| RED evidence | `b816bf2` | `red-local-12-09-retire-twice.log`, two `red_local` lines |
| Retire-twice GREEN | `d63d655` | video_renderer.cc +4: reset `retired_front_` at the top of the resize block |
| Task 1 | `9f50d46` | `render_backend.h` + `SoftwareBackend`; `sw_buffers_`, `sw_retired_`, `StartSoftware` removed |
| Task 2 | `a8fc38a` | `VulkanRenderBackend`; `vulkan_`, `backend_`, `vulkan()` removed; `render_vk.h` moved |
| Task 3 | `0479f4f` | `BackendCandidate`, `DefaultCandidates`, Interop hooks, candidate loop |

All five product heads (d63d655, 9f50d46, a8fc38a, 0479f4f) were pushed to `origin/feat/mpv-master-upgrade`. RED commits reached origin only as ancestors of green heads.

## TDD Gate Compliance (retire-twice fix)

| RED commit (tests only) | RED evidence (local, that exact commit, tree clean) | GREEN commit | GREEN evidence |
|---|---|---|---|
| 149f0be | vk: `GOLDEN invariant scenario=vk-retire-twice: USE AFTER DESTROY serial=1` and `... serial=1 (RetainFrame)`; mismatch at line 37, expected `acquire index=-1 48x27 serial=none`, actual `acquire index=-2 64x36 serial=1 USE AFTER DESTROY`. sw: `USE AFTER FREE: retired 64x36 frame handed out ...`; mismatch at line 18, expected `acquire index=-1 48x27 frame=none`, actual `acquire index=-2 64x36 pixels=set`. golden_vk_fallback (1), golden_vk (8) and golden_sw (12) OK on the same build | d63d655 | Local: all five goldens OK three times, clang front end rc=0. CI gate OK on d63d655. RTX 4060 real plugin passed |

- **Semantic assessment.** Both REDs fail on the behaviour under test: the destroyed-image invariant, and the acquire line in the window between reallocation and publish. There were no build, fixture or discovery failures.
- **Classifier.** The `tdd-red-evidence` classifier was not run, because the golden output is not one of its formats (same as 12-07).
- **Golden files.** They encode correct behaviour. Each was generated from a trace with the fix applied and reviewed line by line against the unfixed trace; the only difference is the window acquire line. The fix was then reverted before the RED commit.
- **Test design:**
  - **vk:** the failing 32x18 render is held inside the fake while the second size is set, so no backoff timer is involved. The 48x27 frame's timeline value is deferred to open the publish window.
  - **sw:** five failures (100 + 200 + 400 + 800 ms) make the backoff 1600 ms, as in golden_sw's resize scenario. The window frame is never dereferenced on the defect.

## Literal move list (plan action 5 of Tasks 1 and 2)

**Task 1 (9f50d46)**
- `"bgr0"`, `"rgb0"` and `"mpv_kit: software backend failed: "` moved unchanged.
- `"software/sw unavailable: mpv_render_context_create: "` is now `"mpv_render_context_create: "` (in `SoftwareBackend::Create`'s why) plus `"software/sw unavailable: "` (in Start). The concatenation is identical.
- New: `"cpu"` (`device_name`), `"software"` (`wire_name`) and `"sw"` ×3 (the renderer argument, `RendererName` and one comment). None of them reached a reason yet: the head was still the literal `"software (sw) on cpu"`.
- New include: `"render_backend.h"`.

**Task 2 (a8fc38a)**
- `" unavailable: mpv_render_context_create: "` is now `" unavailable: "` plus `"mpv_render_context_create: "` (in `VulkanRenderBackend::Create`'s why). Identical concatenation.
- New: `"vulkan"` (`wire_name`, not used in reasons until Task 3).
- `"unknown renderer"` moved to vulkan_backend.cc; the count is unchanged.
- Include `"vulkan_backend.h"` dropped from video_renderer.cc.

**Task 3 (0479f4f)**
- The head is now composed as `wire_name() + " (" + RendererName() + ") on " + device_name()`. Software therefore still gives `software (sw) on cpu`, and Vulkan `vulkan (<renderer>) on <device>`.
- Trails are composed as `api + "/" + renderer + " unavailable: " + why`, so `vulkan/gpu-next`, `vulkan/gpu` and `software/sw` are spelled exactly as before.
- Removed: `"software (sw) on cpu"`, `"vulkan ("` and `"vulkan/"`×2, now composed from the chain.
- Added: `"gpu-next"`/`"gpu"` (in `DefaultCandidates`), and `"platform has no " + api + " backend"` (see deviation 5).

**Equivalence checks for each move commit:** `CONSTANTS ok`; golden freeze 5 × OK; golden_sw, golden_vk, golden_vk_fallback, golden_vk_retire_twice and golden_sw_retire_twice all OK.

**Task 3 Start probe.** A scratch probe (`build/golden-local/p1209/scratch/start_logs.cc`) covers 4 choices × 9 cases:
- Vulkan OK;
- no interop;
- interop reason with `;` and control characters;
- device not shareable;
- gpu-next fails;
- both renderers fail;
- everything fails;
- no device and software fails;
- no interop and software fails.

For each case it prints the reason, the create attempts, every log line, live images and frees. The output is byte-identical between a fresh build of the a8fc38a tree and 0479f4f (143 lines).

## Decisions Made

See `key-decisions`. The user's words, verbatim: "a" (fix the retire-twice defect first, with the test name as proposed) and "做好推送即可，CI 验收不着急" (push is enough; CI acceptance can wait).

## Deviations from Plan

**1. [User decision "a"] Retire-twice use after destroy fixed before the move**
- **Found during:** Task 1, by the prior executor's exploration (`evidence/explore-12-09-resize-after-failed-render.log`).
- **Issue:** RenderOnce's resize block refreshed `retired_front_` only when `front_ >= 0`. Suppose the previous resize never published a frame, because its render failed or timed out. Then `retired_front_` still named the generation before last.
  - `AllocateRing` starts with `FreeRetired()`, which destroyed that image.
  - `retired_countdown_` was −1, so nothing cleared `retired_front_`.
  - AcquireFront then returned the image and called RetainFrame on it.
  - The software path had the same stale pixels pointer.
- **Fix:** `retired_front_ = Frame{};` unconditionally at the top of the resize block, with a 3-line comment. No other product change.
- **Tests:** two new files, the vk golden plus a software sibling. The frozen harness is unchanged and the meson registration is new.
- **Commits:** 149f0be (RED), b816bf2 (evidence), d63d655 (GREEN).
- **12-08 reference:** the 12-08 pre-move reference is stale only for this edge path. That path needs a failed render followed by a second resize before a frame. None of the 12-08 runs reported render errors, so their numbers are unaffected.

**2. [Stale plan text, adapted as the orchestrator directed]**
- **Publish gate:** it is the current synchronous post-render `Wait(back)` behind `pipelined()`. The plan's `pending_front_` gate no longer exists (12-07). The `device lost` / `gpu timeout` mapping and the probe are identical.
- **Ring fallback:** de9dcc5's 8K fallback handling is kept verbatim. The retry goes through `AllocTargets(fallback_ring, w, h, -1, error)`, which matches de9dcc5's `nullptr`.
- **`backend()`:** returns `kSoftware` when no backend was created.
- **Gate expectations:**
  - windows-2025 golden_vk is `+(OK|SKIP)`;
  - golden_vk_fallback and both retire-twice goldens were added;
  - render_vk_smoke and `_gpu` are checked on every move head.

**3. [Interface detail] `RenderBackend::Create` returns `int`, and `device_failed()` reports a device that failed to initialise**
- The plan gave no return type.
- Returning mpv's error code keeps the engine's log line `mpv_kit: <renderer> unavailable: <error_string>` and the `software backend failed` line in the engine, unchanged.
- `FrameFor` is non-const, since a backend may hand out mutable ring state.
- `RendererChoice` moved to render_backend.h in Task 3, as the plan allows; `ParseRendererChoice` stays in video_renderer.cc.

**4. [Not wired] `BindThread` / `UnbindThread` exist with no-op defaults, but the engine does not call them yet**
- The plan's Task 1 action lists them only as interface methods, and the must-have only requires them to have no side effects for Vulkan and software, which they do not.
- Phase 15 (GL) must add the calls around Create, the render thread and Release. ARCHITECTURE.md §2 describes the placement.

**5. [Rule 2 – correctness] Task 3's candidate loop has a trail for an api nobody provides**
- The trail reads `<api>/<renderer> unavailable: platform has no <api> backend`.
- This prevents a null dereference if a platform lists an api without implementing `CreateBackend` for it.
- No Phase 12 chain names such an api, so the string cannot occur today, and every reachable reason is byte-identical (probe above).
- It is a new string, not a changed one, and ADR 0004's `why` vocabulary does not list it yet. 12-10 or 12-11 (ADR follow-up) should add it, or replace it when Phase 13 adds the first platform api.

**6. [Infra] Two apt-mirror stalls, each cancelled at 20 min and rerun once with `CI_GATE_RERUN_INFRA=1`**
- The `note` and `rerun` lines are in ci-runs.txt.
- **d63d655:** linux (ubuntu-24.04) `Install dependencies` stalled; the rerun went green.
- **a8fc38a:** `flutter-video-coverage` `Install libmpv runtime dependencies` stalled; the rerun's apt step took about 41 min and the run went green.
- No test failure was rerun.

**7. [User instruction] The final hosted CI gate (Task 3 head 0479f4f) is deferred**
- The user said "做好推送即可，CI 验收不着急".
- ci-runs.txt holds `gate plan=12-09 task=3 sha=0479f4f2b8252eb196c70ea43f2c66a30bd9bbe0 native-verify=40412604466 result=pending (deferred by user: ...)`.
- The plan's Task 3 CI verify is **deferred, not passed**.
- The hosted run was left running and the orchestrator runs the gate. The local poller was stopped only so it would not write to ci-runs.txt after this commit.

**8. [Local build env] MSVC LNK1163 in the example's plugin build after Task 2.** The cause was a stale incremental `vulkan_backend.obj`. Removing the plugin's `Debug` intermediates fixed it, and the rebuild was clean. No code change.

**Total deviations:** 8 (2 user-directed, 1 orchestrator-directed plan-text adaptation, 2 interface notes, 1 Rule 2, 1 infra, 1 local env). **Impact:** one intended behaviour fix (deviation 1). Everything else is a pure move, verified as above.

## Issues Encountered

- None beyond the deviations. No new unplanned defect was found during the move.

## Known Stubs

- None. `Interop::CreateBackend` returning nullptr and `BindThread`/`UnbindThread` being no-ops are documented extension points (Phases 14/15), not stubs that block this plan's goal.

## Threat Flags

None. T-12-18 (constants and reasons) is mitigated by the constants audit, golden freeze, goldens, literal list and Start probe. T-12-19 (teardown order) is covered: the destructor runs join, then removes the update callback, then `Release`, then resets the backend (device last). The teardown goldens, including the one with a retired generation, ran under ASan+UBSan on 9f50d46 and a8fc38a.

## Flagged Assumption (kept from the plan)

The RBE-04 edge probe is `unclassified / unresolved`. This plan proves only the "behaviour unchanged" that the goldens, the constants audit and CI cover. The RTX 4060 4K 30-minute comparison and the harness reruns belong to 12-12 and are **not** marked covered by a backstop.

## Next Phase Readiness

- 12-10 onward builds on `RenderBackend`. A platform backend is one `CreateBackend` case plus one candidate entry.
- Keep `sha256sum -c evidence/golden-freeze.sha256` OK. golden_vk_fallback and both retire-twice goldens must stay green.
- The deferred gate on 0479f4f must be confirmed before 12-12 compares against it.

## Self-Check: PASSED

- Files exist: render_backend.h, both retire-twice tests and goldens, red-local-12-09-retire-twice.log, constants_audit.sh.
- Commits 3afb2d1, 149f0be, b816bf2, d63d655, 9f50d46, a8fc38a and 0479f4f are ancestors of HEAD and of origin/feat/mpv-master-upgrade.
- `sha256sum -c` gives 5 × OK; `CONSTANTS ok`.

---
*Phase: 12-renderbackend-seam*
*Completed: 2026-10-26*

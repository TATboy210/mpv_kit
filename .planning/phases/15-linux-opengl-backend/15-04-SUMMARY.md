---
phase: 15-linux-opengl-backend
plan: 04
subsystem: native
tags: [linux, opengl, candidate-chain, runbound, render-backend, golden]

requires:
  - phase: 15-01
    provides: Linux GL/EGL bundle, ci_gate.sh
  - phase: 12
    provides: RenderBackend seam, candidate-chain engine, frozen golden harness
provides:
  - "linux_candidates.h: LinuxBackendCandidates(choice), decision A (header-only, not wired into the plugin)"
  - "video_renderer_linux_chain_test + golden/linux_chain.txt (10 scenarios, fake opengl backend)"
  - "RenderBackend::RunBound(fn): create-time mpv_render_* calls run at the backend's binding point"
  - "video_renderer_bind_test: every mpv_render_* call on a bound thread; local RED/GREEN evidence"
affects: [15-05, 15-06, 15-07]

actuals:
  tokens: 21000
  tasks: 3
  commits: 3
plan_head_before: 16765cb05764722ad4c73a3924df430229ec7795
plan_head_after: 01eee6f3e487449775df2e1b0c6a3d3084baa24a

key-files:
  created:
    - packages/mpv_kit_video/src/linux_candidates.h
    - native/tests/video_renderer_linux_chain_test.cc
    - native/tests/golden/linux_chain.txt
    - native/tests/video_renderer_bind_test.cc
    - .planning/phases/15-linux-opengl-backend/evidence/red-local-15-04-bind.log
    - .planning/phases/15-linux-opengl-backend/evidence/local-15-04-chain.log
    - .planning/phases/15-linux-opengl-backend/evidence/local-15-04-bind.log
    - .planning/phases/15-linux-opengl-backend/evidence/ci-runs-15-04.txt
  modified:
    - packages/mpv_kit_video/src/render_backend.h
    - packages/mpv_kit_video/src/video_renderer.cc
    - native/tests/meson.build
    - .planning/phases/15-linux-opengl-backend/evidence/decisions.txt

key-decisions:
  - "decision=linux-chain choice=A: auto vulkan/gpu-next, opengl/gpu, vulkan/gpu, software; gpu opengl/gpu, vulkan/gpu, software; gpu-next vulkan/gpu-next, software; software software."
  - "decision=sc3-interpretation choice=runbound: create-time calls run in RunBound with the context current; SC3 wording is not edited here (15-07 proposes the update)."

requirements-completed: []
requirements-partial: [GLX-03, GLX-04]  # engine seam and chain data verified on hosted CI (LINUX-CHAIN, BIND, AFFINITY ok); plugin wiring is 15-05/15-06 so the requirements stay open

ci-gate: passed 2026-10-28 (sha 091228a, runs native-verify 40627862148 / flutter-plugin 40627862039)
ci_gates_passed:
  - gate: "Task 2: --jobs-success ^linux ^macos ^windows ^sanitizers + LINUX-CHAIN ok on ubuntu-24.04, windows-2025, macos-15, sanitizers + video_renderer_golden_vk OK on ubuntu-24.04"
    result: "CI-GATE ok (golden_vk OK also on arm, macos-15, sanitizers)"
    sha: 091228abd70b22fbe2f425fdd1efb75eb8cfcb54
    runs: "native-verify 40627862148, flutter-plugin 40627862039"
  - gate: "Task 3: BIND ok on ubuntu-24.04, windows-2025, macos-15, sanitizers; AFFINITY ok sw (ubuntu-24.04); LINUX-CHAIN ok; integration-test ubuntu `vulkan (gpu-next) on llvmpipe`"
    result: "CI-GATE ok (the Linux default head is still vulkan gpu-next for the first controller; the sanitizer runs are green)"
    sha: 091228abd70b22fbe2f425fdd1efb75eb8cfcb54
    runs: "native-verify 40627862148, flutter-plugin 40627862039"

duration: about 45 min
completed: 2026-10-27
status: complete
---

# Phase 15 Plan 04: Linux candidate chain and the RunBound seam Summary

**The Linux chain is now data (decision A) locked by a 10-scenario portable golden with a fake OpenGL backend, and `RenderBackend::RunBound` makes create-time `mpv_render_*` calls run where a thread-affine backend has its context current, proven by a bind test that failed locally before the engine change; Vulkan and software behavior is unchanged.**

## Accomplishments

- **Chain data (Task 2):** `LinuxBackendCandidates` returns the four chains of decision A; opengl has only gpu (gpu-next over GL is GLX-F1). Nothing includes it yet, so the user-visible Linux chain is unchanged until 15-05. `linux_chain.txt` covers: opengl wins without Vulkan (`opengl (gpu) on fake-gl; vulkan/gpu-next unavailable: platform interop unavailable: ...`), GL device failure and GL create failure trails (then vulkan/gpu, software), gpu (opengl first, no trail), gpu-next (no opengl backend even asked for), software, forced `opengl` (excluded trail only; fails for a gpu-next request), `unknown renderer` when the query fails, and a real-Vulkan scenario where a failing vulkan/gpu-next create lets opengl/gpu win before vulkan/gpu.
- **RunBound (Task 3):** default `BindThread -> fn -> UnbindThread` in `render_backend.h` with the Threads header updated. `VideoRenderer::Start` runs each candidate's `Create` and, on success, `RendererName` and the first `set_update_callback` in one `RunBound` (the registration moved from after the loop into the winning branch); the never-started release in the destructor is one `RunBound`. No constant, reason text, log text or loop logic changed.
- **bind test:** a backend modelled on an OpenGL context (RunBound on its own thread, thread-local bound flag) delegating to the software backend; every one of the eight `mpv_render_*` entry points checks the flag. Asserts create/get_info/first callback on the RunBound thread, the rest on the render thread, RunBound unbinds before the render thread binds, pairs balanced, one free. RED (before the `video_renderer.cc` change): exit=1, `BIND violation` lines for create, get_info and set_update_callback, saved in `red-local-15-04-bind.log` (committed locally as `a654348`, never pushed).

## Task Commits

1. Task 2, chain data, golden and meson - `02ac6dd` (decisions.txt carries both user answers)
2. Task 3 RED, RunBound seam in the header, bind test, local RED log - `a654348`
3. Task 3 GREEN, `video_renderer.cc` through RunBound - `01eee6f`

## Verification (local, Windows MINGW64, RTX 4060, no libmpv)

- `build/phase15/goldens/build_all.bat` (cl `/W4 /WX`, gitignored): sw_hold_front, affinity (sw+vk), api (10), chain (5), linux_chain (`GOLDEN ok scenarios=10`, `LINUX-CHAIN ok`; the vk scenario ran on the host GPU), bind (`BIND ok`, 20 repeats rc=0), golden_sw/vk/vk_fallback/vk_retire_twice/sw_retire_twice all rc=0 with unchanged goldens; a corrupted copy of linux_chain.txt fails as expected. Logs: `local-15-04-chain.log`, `local-15-04-bind.log`.
- golden-freeze-14 manifest: 5 OK; `constants_audit.sh`: CONSTANTS ok; `RunBound(` count in `video_renderer.cc`: 2.
- `flutter analyze --fatal-infos` (example, packages/mpv_kit_video) clean; `flutter test` in packages/mpv_kit_video: 25 passed; `check_consistency.dart`: all invariants hold; `flutter build windows --debug` of the example builds (the plugin's `video_renderer.cc` and `render_backend.h` compile there too).
- Not runnable here: meson registrations, linux/macos/sanitizer runs, any CI job (hosted CI deferred 2026-10-27).

## Deviations from Plan

**1. [Process] Task 2 push/CI gate and Task 3 push/CI gate not run** (CI deferral 2026-10-27). `ci-runs-15-04.txt` has two `deferred` lines; no run ids invented. Task 3's precondition (Task 2 CI gate printed `CI-GATE ok`) is therefore only satisfied locally; the `sc3-interpretation choice=runbound` part holds.

**2. [Ordering] The `RunBound` virtual was added to `render_backend.h` before the RED run** (plan step 1 precedes step 4). Without it the bind test cannot compile; RED is a runtime failure with the engine unchanged, as required.

**3. [Implementation choice] The fake opengl backend passes the renderer name in `MPV_RENDER_PARAM_VULKAN_RENDERER`** (same parameter the Vulkan backend uses) so create attempts read `opengl/gpu`; the fake mpv keys on it. The real 15-05 backend decides how mpv receives it.

## Flagged assumptions

- The chain test fakes `RendererName` via `render_context_get_info` like the Vulkan backend; whether the real GL render API reports `gpu` through that parameter is a 15-02/15-05 matter (spike-gl.txt is a deferred placeholder).
- Linux default behavior after the `Start` change is unverified until the deferred CI gate (affinity test pins the same call order locally on sw and vk).

## Next plan

15-05 can start locally with respect to this plan: `RunBound` and `LinuxBackendCandidates` exist and are green. It still depends on the deferred 15-02/15-03 spike values (spike-gl.txt, spike-flutter-linux.txt D-*), which are placeholders; anything that reads them is blocked until those are filled from CI.

## Known Stubs

None.

## Threat Flags

None. T-15-11 (Vulkan/software unchanged: frozen goldens, affinity, constants audit green locally), T-15-12 (decision recorded verbatim, chain not wired into the plugin), T-15-13 (local RED with exit=1 and violation lines) are mitigated.

## Self-Check: PASSED

- Files present: linux_candidates.h, linux_chain_test.cc, golden/linux_chain.txt, bind_test.cc, three evidence logs, ci-runs-15-04.txt, this summary.
- Commits 02ac6dd, a654348, 01eee6f are ancestors of HEAD.

## CI backfill (2026-10-28)

The round-1 failure (`BIND violation` from std::thread::id reuse) is fixed by cd877c1; BIND ok, LINUX-CHAIN ok and AFFINITY ok sw are now on the hosted lines.
Evidence: `evidence/ci-runs-15-04.txt`. The gates were evaluated by this phase's unmodified `tools/ci_gate.sh` / `tools/release_gate.sh` against completed runs (PR runs at feat HEAD 091228a: native-verify 40627862148, flutter-plugin 40627862039; release.yml dispatch 40618740386 at b40cdff, valid for the linux bundle because b40cdff..091228a only touched the native-verify windows integration step, d3d11_backend.cpp WaitQuery flags, integration tests and notes). A gh shim served the cached logs; nothing was dispatched, rerun or pushed.

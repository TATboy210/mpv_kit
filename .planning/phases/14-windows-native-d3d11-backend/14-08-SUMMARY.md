---
phase: 14-windows-native-d3d11-backend
plan: 08
subsystem: native
tags: [d3d11, windows, device-lost, failure-injection, golden, render-backend]

requires:
  - phase: 14-07
    provides: D3D11 RenderBackend, D3D11Interop::CreateBackend, windows integration wiring
  - phase: 12
    provides: candidate-chain engine, device_lost event, frozen golden harness
provides:
  - "d3d11_backend.cpp: single RemovedReason() source, query removal errors mapped to kDeviceLost, debug-only MPV_KIT_D3D11_INJECT=create-fail|device-removed:<n>"
  - "example/integration_test/d3d11_device_lost_test.dart (D3D11-INJECT json line) and two native-verify windows runs"
  - "native/tests/video_renderer_chain_test.cc + golden/chain.txt (5 scenarios, registered in meson, all platforms and sanitizers)"
  - "API-neutral device-lost log, EventFn/deviceLost docs, ARCHITECTURE D3D11 notes"
affects: [14-09, 14-10, 14-11]

actuals:
  tokens: 10500
  tasks: 3
  commits: 4
plan_head_before: 29c09debf50065be146592a06db1a645bb43e37f
plan_head_after: 72752f566192bf731e1f9d8710387e09e8bf7959
# commits is measured: 29c09de..72752f5 = 4 (0419a4d injection + test, 8c38200 chain golden, a3a4070 log/docs, 72752f5 LF fix); the docs commit follows.

key-files:
  created:
    - example/integration_test/d3d11_device_lost_test.dart
    - native/tests/video_renderer_chain_test.cc
    - native/tests/golden/chain.txt
    - .planning/phases/14-windows-native-d3d11-backend/evidence/local-14-08-chain.log
  modified:
    - packages/mpv_kit_video/windows/d3d11_backend.cpp
    - packages/mpv_kit_video/src/video_renderer.cc
    - packages/mpv_kit_video/src/video_renderer.h
    - packages/mpv_kit_video/lib/src/video_controller.dart
    - native/tests/meson.build
    - .github/workflows/native-verify.yml
    - docs/ARCHITECTURE.md
    - .planning/phases/14-windows-native-d3d11-backend/evidence/ci-runs.txt

key-decisions:
  - "Injection replaces only the HRESULT source (device creation result and RemovedReason()); the Wait mapping is the real one. Simulated at the HRESULT layer, no real TDR induced."
  - "Both debug variable names exist only under #ifndef NDEBUG (release object file has zero MPV_KIT_D3D11 strings; the debug plugin DLL has the name); 14-10 re-checks the Release DLL."
  - "create-fail test accepts a vulkan head (machine with Vulkan, pre-switch chain) and then does not assert the d3d11 trails (report field trailsChecked=false); the hosted software case asserts both."

requirements-completed: []
requirements-partial: [D3D-07]  # code, chain golden (local MSVC) and docs done; no real-plugin injection run and no CI run of the chain golden on other platforms (ci-gate: deferred)

deferred_ci_gates:
  - "ci-gate: deferred. Task 1 tracer (scratch ci/14-lost, then feat): push ci/14-lost, `gh workflow run native-verify.yml --ref ci/14-lost` and flutter-plugin.yml, then `CI_GATE_BRANCH=ci/14-lost bash .planning/phases/14-windows-native-d3d11-backend/tools/ci_gate.sh --jobs-success '.' --log '^integration-test \\(windows' 'D3D11-INJECT \\{.*\"mode\":\"device-removed' --log '^integration-test \\(windows' 'D3D11-INJECT \\{.*\"recoveredWithSoftware\":true' --log '^integration-test \\(windows' 'D3D11-INJECT \\{.*d3d11/gpu-next unavailable: d3d11 device creation failed: 0x887A0004 \\(injected\\)'`; on green, the same without CI_GATE_BRANCH on feat. Unverified until then: the whole d3d11_device_lost_test.dart on WARP (exactly one deviceLost after frame 30, software recovery on the same Player, create-fail trails), a libmpv with patches 0010/0004 D3D11 is required. Expansion past the tracer was NOT gated on this (CI deferral)."
  - "ci-gate: deferred. Task 2 feat gate: `bash .planning/phases/14-windows-native-d3d11-backend/tools/ci_gate.sh --jobs-success '.' --log '^linux \\(ubuntu-24\\.04\\)' 'video_renderer_chain_test +OK' --log '^linux \\(ubuntu-24\\.04-arm\\)' 'video_renderer_chain_test +OK' --log '^macos \\(macos-15\\)' 'video_renderer_chain_test +OK' --log '^windows \\(windows-2025' 'video_renderer_chain_test +OK' --log '^sanitizers' 'video_renderer_chain_test +OK'` at feat HEAD after the push. Unverified: the meson registration (no local meson) and the test under linux/macos/sanitizers."
  - "ci-gate: deferred. Task 3 feat gate: `bash .planning/phases/14-windows-native-d3d11-backend/tools/ci_gate.sh --jobs-success '.' --log '^build \\(windows' 'tests passed\\.[[:space:]]*$'` at feat HEAD after the push."

duration: about 60 min
completed: 2026-10-27
status: complete
---

# Phase 14 Plan 08: D3D11 device loss and the renderer chain Summary

**D3D11 device removal now has one HRESULT source that debug builds can inject into (`MPV_KIT_D3D11_INJECT=device-removed:<n>|create-fail`, absent from release), a real-plugin test for both injections, and a platform-independent chain golden (5 scenarios) that fixes interleaved candidates, d3d11 device-failure trails, forced-API no-fallback and exactly-one `device_lost`. The golden and all earlier renderer tests pass under MSVC `/W4 /WX`; no injection run happened because no D3D11-capable libmpv exists locally (hosted CI deferred).**

## Accomplishments

- `d3d11_backend.cpp`: `RemovedReason()` is the only source for `Wait`'s device-removed check (real `GetDeviceRemovedReason()` or the injected `DXGI_ERROR_DEVICE_REMOVED` after n rendered frames); a query `GetData` returning `DEVICE_REMOVED/RESET/DRIVER_INTERNAL_ERROR` now maps directly to `kDeviceLost`; `create-fail` goes through `Fail()` so both d3d11 candidates carry `d3d11 device creation failed: 0x887A0004 (injected)`. Invalid injection values are logged and ignored. File header documents the switches and "simulated at the HRESULT layer".
- `d3d11_device_lost_test.dart`: `device-removed:<n>` asserts a d3d11 head, exactly one `deviceLost`, `isBroken`, no `render_error` for 2 s, clean dispose, a readable `pause` property, then a software controller on the same Player produces frames; `create-fail` asserts the trails and a software or Vulkan winner. Two sequential runs appended to the native-verify windows branch (no `MPV_KIT_VIDEO_API`).
- `video_renderer_chain_test.cc` + `golden/chain.txt`: fake `d3d11`/`vulkan` backends behind `Interop::CreateBackend`; scenarios post-switch device fail, gpu-next fails everywhere (interleaved order), pre-switch vulkan device fail, forced d3d11 (no fallback, all trails), device lost (one event, one draw, skips only, one free). Harness and frozen goldens untouched.
- Device-lost log now names the backend (`mpv_kit: d3d11 device lost; ...`); EventFn and `MpvVideoEventKind.deviceLost` docs are API-neutral; ARCHITECTURE documents the mapping, injection and golden.

## Task Commits

1. Task 1, injection seam + real-plugin test + CI wiring - `0419a4d` (line endings repaired in `72752f5`)
2. Task 2, chain golden + meson + local evidence - `8c38200`
3. Task 3, log, docs and ARCHITECTURE - `a3a4070`

## Verification (local)

- `cl /W4 /WX` of d3d11_backend.cpp and d3d11_interop.cpp, debug and `/DNDEBUG`: exit 0 each time; release object has no `MPV_KIT_D3D11` string.
- `build/phase14/goldens` (cl `/W4 /WX`, chain_test added): sw_hold_front, affinity, api, chain (`GOLDEN ok scenarios=5`, repeated 5x stable, a corrupted copy of the golden fails as expected), golden_sw/vk/fallback/retire_twice all rc=0; `ALL rc=0` in `evidence/local-14-08-chain.log`.
- `flutter analyze --fatal-infos` (example, packages/mpv_kit_video) clean; `flutter test` in packages/mpv_kit_video: 25 passed; `dart run tools/check_consistency.dart`: all invariants hold; `constants_audit.sh`: CONSTANTS ok; golden-freeze-14 manifest: 5 OK; `flutter build windows --debug` of the example builds (debug plugin DLL contains `MPV_KIT_D3D11_INJECT`).
- Not runnable here: any run of d3d11_device_lost_test.dart (no libmpv with 0010/0004), meson registration, linux/macos/sanitizer runs of the chain test, CI jobs.

## Acceptance items by status

| Item | Status |
|---|---|
| Injection seam (debug only), unified removal mapping, docs, log neutralisation | done (local) |
| chain_test on MSVC, 5 scenarios, frozen goldens unchanged | done (local) |
| WARP device-removed and create-fail real-plugin runs | ci-gate: deferred |
| chain_test OK on linux x2, macos-15, windows-2025, sanitizers; flutter-plugin test gate | ci-gate: deferred |
| Real TDR sequence (render_error before device_lost on real drivers) | unverified (flagged assumption); d3d11 -> Vulkan on RTX 4060 is 14-11 |

## Deviations from Plan

**1. [Process] Tracer verify, scratch/feat pushes and all CI gates not run** (CI deferral 2026-10-27). Task 1 tracer expansion continued without the end-to-end check; `ci-runs.txt` carries three `deferred` lines, no run IDs invented. Task 2/3 pushes not made.

**2. [Rule 1 - Bug, mine] CRLF written into d3d11_backend.cpp by the first edit** (Windows Python default newline). Found when the commit stat showed a whole-file rewrite; fixed in `72752f5` (LF, content identical). Because the commit was local and unpushed but a rebase would need a clean tree, the fix is a follow-up commit.

**3. [Implementation choice] `RendererName` of the fake backend returns the requested renderer** rather than reading `get_info`, so scenarios need no `SetInfoRenderer`.

**4. [Rule 2 - robustness] Query removal errors map to `kDeviceLost` explicitly** (plan item 3 names query errors; previously only reachable through `GetDeviceRemovedReason`).

## Known Stubs

None.

## Threat Flags

None. T-14-21 (post-loss path is skips only, golden pins one draw and one free), T-14-22 (every failed candidate has a trail, injected cause marked), T-14-31 (injection under `#ifndef NDEBUG`, release object checked locally) are mitigated in code; the Release DLL string check remains 14-10.

## Self-Check: PASSED

- Files present: d3d11_device_lost_test.dart, video_renderer_chain_test.cc, golden/chain.txt, local-14-08-chain.log, this summary.
- Commits 0419a4d, 8c38200, a3a4070, 72752f5 are ancestors of HEAD.

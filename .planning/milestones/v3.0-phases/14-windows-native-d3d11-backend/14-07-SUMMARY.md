---
phase: 14-windows-native-d3d11-backend
plan: 07
subsystem: native
tags: [d3d11, windows, render-backend, fence, kmt-shared-texture, flutter-plugin]

requires:
  - phase: 14-06
    provides: gpu-next D3D11 branch (patch 0004) and the D3D11 render API (0010)
  - phase: 14-02
    provides: ANGLE-free plugin audit, Phase 12 seam
provides:
  - "windows/d3d11_backend.{h,cpp}: D3D11 RenderBackend (own device on Flutter's adapter, KMT BGRA8 ring, ID3D11Fence or D3D11_QUERY_EVENT publish gate)"
  - "D3D11Interop: CreateBackend(\"d3d11\") and the pre-switch Windows chain (kWindowsApiOrder = vulkan, d3d11)"
  - "example/integration_test/d3d11_backend_test.dart and the two native-verify windows runs (fence path, MPV_KIT_D3D11_SYNC=query)"
  - "plugin log line: compositor pickup avg/over 120 frames"
affects: [14-08, 14-09, 14-10, 14-11]

actuals:
  tokens: 10500
  tasks: 3
  commits: 3
plan_head_before: 3e2430b5689cceca7e8644f812b8e738ed6c0567
plan_head_after: 2963f356975391d0b571917b2585013aa67a77e7
# commits is measured: 3e2430b..2963f35 = 3 (482d8b0 backend, 8e7f937 test + CI wiring, 2963f35 pickup log + docs); docs commit follows.

key-files:
  created:
    - packages/mpv_kit_video/windows/d3d11_backend.h
    - packages/mpv_kit_video/windows/d3d11_backend.cpp
    - example/integration_test/d3d11_backend_test.dart
    - .planning/phases/14-windows-native-d3d11-backend/evidence/local-14-07-real-plugin-d3d11.log
  modified:
    - packages/mpv_kit_video/windows/d3d11_interop.h
    - packages/mpv_kit_video/windows/d3d11_interop.cpp
    - packages/mpv_kit_video/windows/CMakeLists.txt
    - packages/mpv_kit_video/windows/mpv_kit_video_plugin.cpp
    - .github/workflows/native-verify.yml
    - README.md
    - packages/mpv_kit_video/README.md
    - docs/ARCHITECTURE.md
    - docs/adr/0004-render-backend-reporting.md
    - .planning/phases/14-windows-native-d3d11-backend/evidence/ci-runs.txt

key-decisions:
  - "frame_kind() stays Backend::kVulkan (shared GPU image class); no shared header or enum change. Dart maps wire name d3d11 to MpvVideoBackend.vulkan."
  - "Fence waits loop on GetCompletedValue with a 1000 ms deadline and reset the event before arming, so a stale auto-reset signal from an earlier timed-out wait cannot publish an unfinished frame."
  - "Windows chain is data (kWindowsApiOrder); 14-11 reorders one array. CompositorLatency() line untouched (quarantine 4)."

requirements-completed: []
requirements-partial: [D3D-06]  # code, MSVC compile, ANGLE-free audit and the WARP CI runs (fence + query paths) are done; the RTX 4060 tracer run (local hardware, 14-09) is still open

deferred_ci_gates:  # still open: local RTX 4060 hardware run (14-09); a d3d11-capable bundle exists now (libmpv-windows-x64 artifact of run 40618740386)
  - "ci-gate: deferred. Task 1 tracer, RTX 4060 local: fetch the libmpv-windows-x64 artifact of a release.yml run at feat HEAD (contains 0010 + 0004 D3D11 branch), then in example/ with MPV_KIT_LIBMPV_PATH=<dir>/libmpv-2.dll MPV_KIT_REQUIRE_LIBMPV=1: MPV_KIT_VIDEO_API=d3d11 flutter test integration_test/real_plugin_test.dart -d windows, then the same without MPV_KIT_VIDEO_API, both tee'd to evidence/local-14-07-real-plugin-d3d11.log. Verify: grep -Eq 'INTEGRATION \\{.*\"reason\":\"d3d11 \\(gpu-next\\) on NVIDIA GeForce RTX 4060' L && grep -Eq 'INTEGRATION \\{.*\"reason\":\"vulkan \\(gpu-next\\) on NVIDIA GeForce RTX 4060' L && test \"$(grep -cE 'tests passed\\.[[:space:]]*$' L)\" -ge 2. Expansion past the tracer was NOT gated on this (CI deferral)."

ci_gates_passed:
  - gate: "Task 2: --jobs-success . with D3D11-BACKEND (reason d3d11 (gpu-next) on ...), INTEGRATION auto-chain trail `d3d11 (gpu-next) on ...; vulkan/gpu-next unavailable: ...`, ANGLE-FREE mpv_kit_video_plugin.dll; syncEnv default and query on integration-test (windows)"
    result: "CI-GATE ok (WARP; both sync paths probe non-black: redTop 1.0 blueBottom 1.0, resize 640x360 and 320x180)"
    sha: 091228abd70b22fbe2f425fdd1efb75eb8cfcb54
    runs: "native-verify 40627862148, flutter-plugin 40627862039"
  - gate: "Task 3 feat gate: --jobs-success ."
    result: "CI-GATE ok"
    sha: 091228abd70b22fbe2f425fdd1efb75eb8cfcb54
    runs: "native-verify 40627862148, flutter-plugin 40627862039"

duration: about 40 min
completed: 2026-10-27
status: complete
---

# Phase 14 Plan 07: D3D11Backend in the Windows plugin Summary

**The Windows plugin now has a native D3D11 backend: own `ID3D11Device` on Flutter's adapter, mpv rendering through its D3D11 render API into a KMT-shared BGRA8 ring handed to `GpuSurfaceTexture`, with an `ID3D11Fence` (or `D3D11_QUERY_EVENT`) completion gate before publish. Everything compiles clean under MSVC `/W4 /WX` (debug and release plugin builds) and the plugin DLL stays ANGLE-free; no frame has been rendered through it yet because no D3D11-capable libmpv exists locally (hosted CI deferred).**

## Accomplishments

- `d3d11_backend.cpp`: device creation with the `VIDEO_SUPPORT` retry (logged), `ID3D11Multithread` protection, fence or query mode (`MPV_KIT_D3D11_SYNC=query` compiled only without `NDEBUG`; the release plugin DLL has zero occurrences of the string), 16384 texture cap, keep-slot retirement, wait bounded at 1000 ms with device-removed mapping, render failures leave the slot's ready value alone.
- `D3D11Interop`: keeps Flutter's adapter even when its own device fails, `CreateBackend("d3d11")`, `BackendCandidates` from `kWindowsApiOrder`: auto is vulkan/gpu-next, d3d11/gpu-next, vulkan/gpu, d3d11/gpu, software. `CompositorLatency()` unchanged (constants audit `CONSTANTS ok`).
- `d3d11_backend_test.dart`: reason prefix (`MPV_KIT_EXPECT_REASON_PREFIX`), red-over-blue `toImage` probe at 320x180 / 640x360 / 320x180, non-black right after each resize event, stable texture id, no device_lost/render_error/gpu_timeout, `D3D11-BACKEND {json}` with `syncEnv`. native-verify windows branch runs it twice (fence, forced query).
- Plugin: `compositor pickup avg/over 120 frames: ...ms max=...ms backend=<wire>` (measurement only, both backends). Docs: README, plugin README, ARCHITECTURE "D3D11 backend", ADR 0004 Decision 4/5.

## Task Commits

1. Task 1, backend + interop + CMake - `482d8b0`
2. Task 2, forced-d3d11 test + CI wiring + deferral evidence - `8e7f937`
3. Task 3, pickup latency log + docs - `2963f35`

## Verification (local)

- `cl /W4 /WX` of d3d11_backend.cpp and d3d11_interop.cpp, with and without `/DNDEBUG`: exit 0. `flutter build windows --debug` and `--release` of the example: built (plugin under Flutter's `/W4 /WX`).
- `pe_audit.py --forbid-angle` on debug and release `mpv_kit_video_plugin.dll`: ANGLE-FREE, PASS.
- `flutter analyze --fatal-infos` on example and packages/mpv_kit_video: no issues; `flutter test` in packages/mpv_kit_video: 25 passed. `dart run tools/check_consistency.dart`: all invariants hold. `constants_audit.sh`: CONSTANTS ok. Golden-freeze (golden-freeze-14.sha256): 5 OK. Task 3 grep gate: ok.
- Not runnable here: any run of the backend (no libmpv with 0010/0004 D3D11), the RTX 4060 forced-d3d11 and auto runs, the WARP runs, CI jobs.

## Acceptance items by status

| Item | Status |
|---|---|
| Backend, interop chain, CMake, pickup log, docs; MSVC compile; ANGLE-free; constants audit | done (local) |
| Forced d3d11 on RTX 4060 (reason head, auto stays vulkan), real_plugin soak on d3d11 | ci-gate: deferred |
| WARP forced-d3d11 test, fence and query paths, auto lands on d3d11 on the runner | ci-gate: deferred |
| flutter-plugin ANGLE-FREE line and PR CI green on feat | ci-gate: deferred |

## Deviations from Plan

**1. [Process] Tracer verify, scratch/feat pushes and all CI gates not run** (CI deferral 2026-10-27). Task 1 is a tracer whose end-to-end check could not run; expansion continued per the deferral instruction. `local-14-07-real-plugin-d3d11.log` holds the deferral note and the real local compile output only; `ci-runs.txt` carries a `deferred` line. No run IDs invented.

**2. [Implementation choice] `ID3D11Multithread` instead of `ID3D10Multithread`.** Same interface, declared in `d3d11_4.h`, so no `d3d10.h` include; behaviour identical.

**3. [Rule 2 - robustness] Fence wait re-checks the completed value in a loop** and resets the event before arming (see key-decisions); not in the plan text, no behaviour change on the success path.

No other deviations.

## Known Stubs

None.

## Threat Flags

None. T-14-17 (render-thread-only context, multithread protection), T-14-18 (own device, KMT only, plugin DLL ANGLE-free locally), T-14-19 (1000 ms bounds, removal mapped to device_lost) and T-14-20 (debug-only switch; release DLL string count 0) are mitigated in code.

## Self-Check: PASSED

- Files present: d3d11_backend.h/.cpp, d3d11_backend_test.dart, local-14-07 log, this summary.
- Commits 482d8b0, 8e7f937, 2963f35 are ancestors of HEAD.

## CI backfill (2026-10-28)

The deferred hosted gates were evaluated by this phase's unmodified `tools/ci_gate.sh` against completed runs (PR runs at feat HEAD 091228a: native-verify 40627862148, flutter-plugin 40627862039; release.yml dispatch 40618740386 at b40cdff, valid for the libmpv bundle because b40cdff..091228a only touched the native-verify windows integration step, d3d11_backend.cpp WaitQuery flags, integration tests and notes). A gh shim served the cached logs; nothing was dispatched, rerun or pushed. `--jobs-success .` on release.yml fails literally only on the tag-only `publish` job (skipped by design); all build jobs and every `--log` expectation held. D3D-06 stays partial: Task 2/3 gates passed (WARP, both sync paths) but the Task 1 RTX 4060 hardware gate has not run.
Evidence: `evidence/ci-runs.txt` (backfill block with the raw matched lines)

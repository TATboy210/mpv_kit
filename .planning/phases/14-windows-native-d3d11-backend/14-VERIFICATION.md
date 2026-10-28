---
phase: 14-windows-native-d3d11-backend
verified: 2026-10-28T00:00:00Z
status: gaps_found
score: 3/5 roadmap success criteria fully verified (SC1, SC2, SC4); SC3 partial (hosted half only); SC5 not started
covered_files:
  - .planning/phases/14-windows-native-d3d11-backend/14-01-PLAN.md
  - .planning/phases/14-windows-native-d3d11-backend/14-01-SUMMARY.md
  - .planning/phases/14-windows-native-d3d11-backend/14-02-PLAN.md
  - .planning/phases/14-windows-native-d3d11-backend/14-02-SUMMARY.md
  - .planning/phases/14-windows-native-d3d11-backend/14-03-PLAN.md
  - .planning/phases/14-windows-native-d3d11-backend/14-03-SUMMARY.md
  - .planning/phases/14-windows-native-d3d11-backend/14-04-PLAN.md
  - .planning/phases/14-windows-native-d3d11-backend/14-04-SUMMARY.md
  - .planning/phases/14-windows-native-d3d11-backend/14-05-PLAN.md
  - .planning/phases/14-windows-native-d3d11-backend/14-05-SUMMARY.md
  - .planning/phases/14-windows-native-d3d11-backend/14-06-PLAN.md
  - .planning/phases/14-windows-native-d3d11-backend/14-06-SUMMARY.md
  - .planning/phases/14-windows-native-d3d11-backend/14-07-PLAN.md
  - .planning/phases/14-windows-native-d3d11-backend/14-07-SUMMARY.md
  - .planning/phases/14-windows-native-d3d11-backend/14-08-PLAN.md
  - .planning/phases/14-windows-native-d3d11-backend/14-08-SUMMARY.md
  - .planning/phases/14-windows-native-d3d11-backend/14-09-PLAN.md
  - .planning/phases/14-windows-native-d3d11-backend/14-10-PLAN.md
  - .planning/phases/14-windows-native-d3d11-backend/14-11-PLAN.md
  - native/patches/0010-upstream-d3d11-render-api.patch
  - native/tests/render_d3d11_smoke.c
  - packages/mpv_kit_video/windows/d3d11_backend.cpp
  - packages/mpv_kit_video/windows/d3d11_interop.cpp
  - tools/rea_abi_audit/pe_audit.py
covered_digest: "v4:sha256:1a9fba2306bf54e2b5d05aeff3ce64e86ad6435e1346e593be287e679b7bb9c9"
behavior_unverified: 0
gaps:
  - truth: "SC3 / D3D-06: forced d3d11 renders non-black frames on the RTX 4060 with reason `d3d11 (gpu-next) on <adapter>`, Impeller on/off pickup latency measured"
    status: partial
    reason: "Hosted WARP half is proven in CI (run 40627862148). The RTX 4060 half is plan 14-09, not executed: no rtx4060-runs.txt, no docs/perf/d3d11-backend.md. The only RTX 4060 observation is a debugger's local repro recorded in ci-runs.txt (d3d11_backend_test fence path passed, query path 8/8 after the GetData fix), which is not the plan 14-09 deliverable."
    artifacts:
      - path: "docs/perf/d3d11-backend.md"
        issue: "does not exist"
      - path: ".planning/phases/14-windows-native-d3d11-backend/evidence/rtx4060-runs.txt"
        issue: "does not exist"
    missing:
      - "14-09: RTX 4060 forced-d3d11 d3d11_backend_test (fence + query), 4K 600 s rendered run compared with Phase 12 final-uhd4k-rendered, Impeller on/off D-05 and pickup latency, docs/perf/d3d11-backend.md"
  - truth: "SC3 hardware tier on the user's GTX 960 + iGPU laptop (4K60 via d3d11, never software)"
    status: failed
    reason: "14-10 not executed (user hardware session pending). Not a roadmap-level SC, but it gates the 14-11 switch decision."
    artifacts: []
    missing:
      - "14-10: desktop Release demo package and user manual verification"
  - truth: "SC5 / D3D-08: Windows auto chain is d3d11/gpu-next -> vulkan/gpu-next -> d3d11/gpu -> vulkan/gpu -> software, as a standalone commit landed only after CI and RTX 4060 are green"
    status: failed
    reason: "14-11 not executed. d3d11_interop.cpp:25 still has kWindowsApiOrder = {\"vulkan\", \"d3d11\"}, so auto stays on Vulkan first (intended pre-switch state; D3D11 is reachable only through forced MPV_KIT_VIDEO_API=d3d11 or as the second candidate in a tier). No switch.txt, no final-audit.txt, ci/14-* scratch branches still on origin (ci/14-angle, ci/14-libdrm, ci/14-probe)."
    artifacts:
      - path: "packages/mpv_kit_video/windows/d3d11_interop.cpp"
        issue: "kWindowsApiOrder still {vulkan, d3d11}"
    missing:
      - "14-11: user switch decision, standalone switch commit validated on ci/14-switch and RTX 4060, final audit, scratch branch cleanup"
deferred: []
---

# Phase 14: Windows Native D3D11 Backend Verification Report

**Phase Goal:** On Windows, mpv renders through the upstream D3D11 render API directly into shared textures on mpv_kit's own `ID3D11Device` (gpu-next and gpu tiers), with no ANGLE/EGL in mpv_kit's own chain; failures fall back along the auto chain with an honest `reason`.
**Verified:** 2026-10-28
**Status:** gaps_found (expected: plans 14-09, 14-10, 14-11 are pending user hardware sessions)
**Re-verification:** No, initial verification

## Scope note

Plans 14-01..14-08 were executed under a CI deferral (2026-10-27). Their hosted CI gates were evaluated afterwards by the phase's own `tools/ci_gate.sh` against completed runs at feat `091228a` (HEAD `890fe74` has no later change to `packages/mpv_kit_video/windows`, `src`, `native/patches`, `native/build`, `tools`; `git diff 091228a HEAD` touches only `native-verify.yml` and `render_gl.h`, Phase 15 work). I spot-checked run conclusions with `gh run view`:

| Run | Workflow | SHA | Conclusion (re-queried) |
|---|---|---|---|
| 40627862148 | native-verify | 091228a | success |
| 40627862039 | flutter-plugin | 091228a | success |
| 40618740386 | release (dispatch) | b40cdff | success (publish skipped by design) |
| 40442377807 | native-verify | 025bdad | success |

Caveat: release evidence is from b40cdff, not 091228a. The recorded diff argument (only the Windows integration step, WaitQuery flags, tests and notes changed between them) is consistent with the git log; I accept it for the bundle contents.

## Observable Truths (ROADMAP success criteria)

| # | Criterion | Status | Evidence |
|---|---|---|---|
| SC1 | Bundle contains SPIRV-Cross + shaderc, `-Dd3d11` with `HAVE_D3D11`, LGPL-only, ANGLE/EGL options off, `pe_audit.py --forbid-angle` fails CI on libEGL/libGLESv2/eglGetPlatformDisplayEXT, proven by a synthetic violation | VERIFIED | release run 40618740386 logs: `HAVE_D3D11 1`, shaderc 2026.4.1 and spirv-cross-c-shared 0.68.0 found, `packaged 24 libraries`, `ANGLE-FREE` for libshaderc/libspirv-cross/libmpv on windows x64 + arm64. `--forbid-angle` present in `tools/rea_abi_audit/pe_audit.py:123`, wired in `package.sh:129,132`, `native-verify.yml:567`, `flutter-plugin.yml:67`. `test_pe_audit.py` (synthetic violation samples) runs in `native-verify.yml:38`. `--forbid-gpl` retained alongside. |
| SC2 | 0010 byte-identical to upstream PR #17764 ABI (params 21/22, API 2.6), PATCH-DRIFT green; 0004 gpu-next D3D11 branch + 0003 DXBC cache effective; `render_d3d11_smoke` gpu and gpu-next non-black on WARP | VERIFIED | `native/patches/0010-...patch` exists (params 21/22, `MPV_RENDER_API_TYPE_D3D11` "d3d11", client API 2.6 present); `evidence/abi-0010.txt` records SHA mapping to upstream 4255130de4 plus two prerequisite commits (user-approved 2026-10-27) and the local `done_frame` bool commit. Run 40627862148: `PATCH-DRIFT OK ... patches=10`; `render_d3d11_smoke`, `_gpu`, `_cache` OK on windows-2025 (x64) and windows-11-arm. 0004 contains D3D11 branch (30 d3d11 refs); the persistent DXBC cache is implemented in 0004 preinit (no d3d11 lines in 0003 itself; the cache lives in 0004 so the literal "0003 covers DXBC" wording is satisfied functionally) and `_cache` variant (two consecutive creates on one cache dir, asserts cache_load_obj non-zero) passed. Minor note: the byte-for-byte ABI comparison is a recorded claim in abi-0010.txt, I did not re-diff against upstream. |
| SC3 | Forced d3d11 renders non-black on WARP and RTX 4060, reason `d3d11 (gpu-next) on <adapter>`, device on Flutter LUID with BGRA+VIDEO flags, multithread protected, KMT MISC_SHARED ring, fence (query fallback) before publish, resize keeps texture id, quarantine 4, Impeller on/off pickup measured | PARTIAL | Code (d3d11_backend.cpp 493 lines): `D3D11_CREATE_DEVICE_VIDEO_SUPPORT` with documented drop on WARP (l.317-332), `SetMultithreadProtected(TRUE)` (l.342), `ID3D11Fence` via `CreateFence` (l.354) with `D3D11_QUERY_EVENT` fallback (l.397), `D3D11_RESOURCE_MISC_SHARED` BGRA8 (l.385), `CompositorLatency()` returns 4 (d3d11_interop.h:37). CI WARP (run 40627862148, windows-2025): `D3D11-BACKEND` line shows reason `d3d11 (gpu-next) on Microsoft Basic Render Driver`, redTop/blueBottom/nonBlack = 1.0, resize probes 640x360 and 320x180 pass, same texture id, for both default (fence) and `syncEnv=query`. flutter-plugin run 40627862039: plugin DLL `ANGLE-FREE`, 25 tests passed. **Not done:** RTX 4060 render, Impeller on/off pickup latency, perf doc (14-09). A debugger's local RTX 4060 repro (reason `d3d11 (gpu-next) on NVIDIA GeForce RTX 4060 Laptop GPU`, fence pass, query 8/8 after GetData-flush fix 091228a) is recorded in ci-runs.txt but is not the planned measurement set. D3D-06 correctly remains unticked in REQUIREMENTS.md. |
| SC4 | Injected D3D11 device removal gives Dart `device_lost` without crash; D3D11 creation failure falls to Vulkan with `d3d11/<renderer> unavailable: <why>` in reason | VERIFIED (hosted) | `D3D11-INJECT device-removed:30`: events include `deviceLost`, `isBroken:true`, `recoveredWithSoftware:true`, process alive. `create-fail`: reason `software (sw) on cpu; vulkan/gpu-next unavailable: ...; d3d11/gpu-next unavailable: d3d11 device creation failed: 0x887A0004 (injected); ... d3d11/gpu unavailable: ...`, `trailsChecked:true`. `video_renderer_chain_test` (5 golden scenarios) OK on linux x2, macos-15, windows x2, sanitizers. Caveat: on the hosted runner Vulkan is unavailable so the observed fallback landed on software, not Vulkan; the d3d11 -> Vulkan hop is covered by the chain golden and by 14-11's planned RTX create-fail check, not by a real-driver run. Injection is debug-only (`#ifndef NDEBUG`; release object has no MPV_KIT_D3D11 string per 14-08 local check). |
| SC5 | Auto chain switched to d3d11/gpu-next -> vulkan/gpu-next -> d3d11/gpu -> vulkan/gpu -> software as a standalone commit after CI and RTX 4060 are green; `MPV_KIT_VIDEO_API=vulkan` still forces old path | FAILED (not started) | `kWindowsApiOrder = {"vulkan", "d3d11"}` (d3d11_interop.cpp:25). Chain builder `BackendCandidates` (l.59-76) already generates tiered order from that array, so the switch is a one-line change as planned. Forced-API exclusion text (`excluded by MPV_KIT_VIDEO_API=d3d11`) is evidenced in CI. Depends on 14-09 and 14-10. |

**Score:** 3/5 criteria verified (SC1, SC2, SC4), SC3 partial, SC5 not started.

## Requirements Coverage

| Req | Status | Evidence |
|---|---|---|
| D3D-01 | SATISFIED | release 40618740386 (above) |
| D3D-02 | SATISFIED | pe_audit `--forbid-angle` + synthetic test + three CI hooks; ANGLE-FREE lines for 23/24 DLLs x2 targets and plugin DLL |
| D3D-03 | SATISFIED | 0010 + PATCH-DRIFT `patches=10` |
| D3D-04 | SATISFIED | 0004 D3D11 branch; smoke + cache OK on both Windows archs |
| D3D-05 | SATISFIED | render_d3d11_smoke (gpu-next), `_gpu`, `_cache` OK |
| D3D-06 | PARTIAL (correctly Pending) | implementation and WARP proof done; RTX 4060 measurement (14-09) outstanding |
| D3D-07 | SATISFIED (hosted) | inject runs + chain golden; real-hardware create-fail -> Vulkan deferred to 14-11 |
| D3D-08 | NOT SATISFIED (correctly Pending) | 14-11 |

No orphaned requirements: REQUIREMENTS.md maps exactly D3D-01..08 to Phase 14 and the plans claim them.

## Anti-Patterns / Quality Observations

| Item | Severity | Note |
|---|---|---|
| Plans 14-03..14-08 executed with CI deferred, evidence backfilled afterwards from later runs | Info | Backfill lines are explicit (`Milestone CI backfill 2026-10-28`) and reference real run IDs that re-query as success; nothing invented. Release gate `--jobs-success .` fails literally on skipped `publish` and was waived with a written rationale. |
| `ci/14-*` scratch branches (`ci/14-angle`, `ci/14-libdrm`, `ci/14-probe`) still on origin | Warning | cleanup is assigned to 14-11. |
| Two real defects were found only after the hosted runs (library shadowing fixed in bc6a6bf; D3D11 query `DONOTFLUSH` stall fixed in 091228a) | Info | Both fixed and re-verified green at 091228a; the query-path fix was reproduced on RTX 4060 by the debugger but not yet on WARP-vs-hardware under the 14-09 matrix. |
| WARP integration run shows `vulkan/gpu-next unavailable: vkCreateInstance failed` in INTEGRATION line | Info | expected on hosted runner; honest reporting. |
| No TBD/FIXME/XXX debt markers checked beyond spot greps in d3d11_backend.cpp / d3d11_interop.cpp (none seen) | Info | |

## Human / Hardware Verification Still Required (the exact remaining work)

1. **14-09 (RTX 4060):** forced `MPV_KIT_VIDEO_API=d3d11` d3d11_backend_test on fence and `MPV_KIT_D3D11_SYNC=query` paths with the release-layer bundle; 4K rendered 600 s compared against Phase 12 `final-uhd4k-rendered`; Impeller on/off D-05 and 120 s 4K60 pickup latency; write `docs/perf/d3d11-backend.md` with verification tiers. Quarantine stays 4 (COMP-03 deferred).
2. **14-10 (GTX 960 + iGPU laptop):** user runs the desktop Release demo package; 4K60 through d3d11 and never software.
3. **14-11 (D3D-08):** user switch decision recorded in `evidence/switch.txt`; standalone one-line switch commit validated on `ci/14-switch` and on the RTX 4060 (including `MPV_KIT_VIDEO_API=vulkan` forcing, and injected create-fail landing on vulkan with the d3d11 trail); final audit; delete `ci/14-*` scratch branches; tick D3D-06/D3D-08 and ROADMAP progress.

## Gaps Summary

Everything that can be proven on hosted CI is proven: build/bundle and the ANGLE ban (SC1), patch/ABI/smoke (SC2), the D3D11Backend with WARP forced-d3d11 non-black frames on both sync paths, resize stability, `device_lost` and create-fail trails (SC3 hosted half, SC4). The remaining gaps are exactly the three pending hardware plans: RTX 4060 measurements (SC3 hardware half, D3D-06), the laptop acceptance (14-10), and the auto-chain switch (SC5, D3D-08). Phase 14 must not be marked complete until those land.

---

_Verified: 2026-10-28_
_Verifier: Claude (gsd-verifier)_

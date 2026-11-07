---
phase: 14-windows-native-d3d11-backend
verified: 2026-10-30T00:00:00Z
status: passed
score: 5/5 roadmap success criteria (4 verified, 1 accepted override: SC5 not met by user decision)
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
  - .planning/phases/14-windows-native-d3d11-backend/14-09-SUMMARY.md
  - .planning/phases/14-windows-native-d3d11-backend/14-10-PLAN.md
  - .planning/phases/14-windows-native-d3d11-backend/14-10-SUMMARY.md
  - .planning/phases/14-windows-native-d3d11-backend/14-11-PLAN.md
  - .planning/phases/14-windows-native-d3d11-backend/14-11-SUMMARY.md
  - example/windows/runner/main.cpp
  - native/patches/0010-upstream-d3d11-render-api.patch
  - native/tests/render_d3d11_smoke.c
  - packages/mpv_kit_video/lib/src/backend_api.dart
  - packages/mpv_kit_video/src/video_renderer.cc
  - packages/mpv_kit_video/src/video_renderer.h
  - packages/mpv_kit_video/windows/d3d11_backend.cpp
  - packages/mpv_kit_video/windows/d3d11_interop.cpp
  - tools/rea_abi_audit/pe_audit.py
covered_digest: "v4:sha256:5be0c4e9ed7d403dae988985ec4e8e19aff39bdbb09c45462e43b2f793f4a89d"
behavior_unverified: 0
overrides_applied: 1
overrides:
  - must_have: "SC5 / D3D-08: Windows auto chain is d3d11/gpu-next -> vulkan/gpu-next -> d3d11/gpu -> vulkan/gpu -> software, landed as a standalone commit after CI and RTX 4060 are green"
    reason: "User decided to keep Vulkan first (2026-10-29 via AskUserQuestion, confirmed 2026-10-30: 'keep Vulkan first, investigate why D3D11 is slow, then switch'). GTX 960M evidence: Vulkan about 0.5 percent effective drops vs D3D11 about 3.5 percent. kWindowsApiOrder unchanged; follow-up todo 2026-10-30-d3d11-slower-than-vulkan-on-maxwell-before-switch.md."
    accepted_by: "user (decision recorded verbatim in evidence/switch.txt)"
    accepted_at: "2026-10-29T00:00:00Z"
gaps: []
deferred:
  - truth: "Windows auto chain switched to D3D11 first (D3D-08 / SC5)"
    addressed_in: "follow-up todo (not a roadmap phase)"
    evidence: ".planning/todos/pending/2026-10-30-d3d11-slower-than-vulkan-on-maxwell-before-switch.md: done when D3D11 effective drops on the 960M are within about 1 percent of Vulkan, then the one-line switch is offered again"
---

# Phase 14: Windows Native D3D11 Backend Verification Report

**Phase Goal:** On Windows, mpv renders through the upstream D3D11 render API directly into shared textures on mpv_kit's own `ID3D11Device` (gpu-next and gpu tiers), with no ANGLE/EGL in mpv_kit's own chain; failures fall back along the auto chain with an honest `reason`.
**Verified:** 2026-10-30
**Status:** passed (SC5 carried as an accepted user-decision override; residual risks listed, none belongs to a roadmap success criterion)
**Re-verification:** Yes, supersedes the 2026-10-28 verification

## Previous verification

The 2026-10-28 report was `gaps_found` (3/5: SC1, SC2, SC4 verified, SC3 partial, SC5 not started) because plans 14-09, 14-10 and 14-11 had not run. They have since run: 14-09 closed the RTX 4060 half of SC3 and D3D-06, 14-10 produced the GTX 960M laptop evidence (and three quick tasks), 14-11 recorded the D3D-08 decision (keep) and closed the phase. All three earlier gaps are re-checked below; none remains open.

## Goal Achievement

### Observable Truths (ROADMAP success criteria)

| # | Criterion | Status | Evidence |
|---|---|---|---|
| SC1 | Bundle has SPIRV-Cross + shaderc, `-Dd3d11` / `HAVE_D3D11`, LGPL-only, ANGLE/EGL/WGL-GL options off, `pe_audit.py --forbid-angle` fails CI on libEGL/libGLESv2/eglGetPlatformDisplayEXT, proven by an injected violation sample | VERIFIED | `native/build/build.sh:61-70` Windows branch: `-Dd3d11=enabled -Dshaderc=enabled -Dspirv-cross=enabled`, `-Dgl=disabled -Degl=disabled`. `tools/rea_abi_audit/pe_audit.py:123` `--forbid-angle`; `test_pe_audit.py` carries the synthetic violation samples. Re-queried CI: native-verify 40911900598 windows x64 and arm64 print `pe_audit ... --forbid-gpl --forbid-angle` then `ANGLE-FREE prefix/bin/libmpv-2.dll`; flutter-plugin 40911900588 windows prints 2 `ANGLE-FREE ...mpv_kit_video_plugin.dll`. Release 40907471707 (6 build jobs success) packaged the bundle; 14-04 evidence (`ci-runs.txt`, release 40618740386) shows `HAVE_D3D11 1`, shaderc and spirv-cross-c-shared in the 24-library package. |
| SC2 | 0010 byte-identical ABI with upstream PR #17764 (params 21/22, client API 2.6), PATCH-DRIFT green, 0004 gpu-next D3D11 branch, DXBC persistent cache, `render_d3d11_smoke` gpu and gpu-next non-black on WARP | VERIFIED | `native/patches/0010-...patch`: `MPV_RENDER_PARAM_D3D11_INIT_PARAMS = 21`, `D3D11_FBO = 22`, `MPV_MAKE_VERSION(2, 6)`, `"d3d11"`. `evidence/abi-0010.txt`: `render_d3d11.h identical`, `client_api 2.6 identical`, `render.h identical` (cmp against upstream 4255130de4; recorded claim, I did not re-diff against upstream). native-verify 40911900598: patch-drift job `PATCH-DRIFT OK ... patches=10`; windows x64 (windows-2025) and arm64 (windows-11-arm) `render_d3d11_smoke`, `_gpu`, `_cache` all `OK`. The DXBC cache is realised in 0004 (not in 0003 text); the `_cache` variant (two creates on one cache dir) passes. Not a gap, wording only. |
| SC3 | Forced d3d11 renders non-black on WARP and RTX 4060 with reason `d3d11 (gpu-next) on <adapter>`; device on Flutter LUID, BGRA+VIDEO flags, multithread protected, non-SINGLETHREADED; KMT MISC_SHARED ring via `GpuSurfaceTexture`; fence (query fallback) completes before publish; resize keeps texture id without flicker; quarantine 4; Impeller on/off consumption latency measured, not re-parameterised | VERIFIED | Code: `d3d11_backend.cpp` BGRA|VIDEO_SUPPORT with documented retry-without on WARP, `SetMultithreadProtected(TRUE)`, `ID3D11Fence` Signal after render + `WaitFence` / `D3D11_QUERY_EVENT` `WaitQuery` fallback, `D3D11_RESOURCE_MISC_SHARED` BGRA8 slots, no UAV bind; plugin `GpuSurfaceTexture(kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle, ...)` at `mpv_kit_video_plugin.cpp:251`; `D3D11Interop::CompositorLatency() == 4`; `kMaxQuarantine = 4`. Hosted WARP (integration-test windows job of 40911900598): `D3D11-BACKEND` reason `d3d11 (gpu-next) on Microsoft Basic Render Driver`, probes 1.0, resize 640x360 and 320x180 all 1.0, same texture id, for default (fence) and `syncEnv:"query"`. RTX 4060 (14-09, release-run bundle 40812562348, manifest ok): fence and query both pass with reason `d3d11 (gpu-next) on NVIDIA GeForce RTX 4060 Laptop GPU`; 4K rendered 600 s attempt 2 frameDrop 0, decoder drops 0, voDelayed 0, renderErrors 0, deviceLost false, avsync +3.9 us vs Phase 12 (no threshold); D-05 on/off `failed/100 rounds` with the same pixel-probe-only signature as Phase 12 (`no-new-failure`); pickup avg 8.59 ms (Impeller on, 64 windows) / 8.55 ms (off, 65), render waits done 3.56 / 3.64 ms; Impeller identity on=1 off=0. Quarantine untouched, COMP-03 still deferred. Caveats in Residual Risks. |
| SC4 | Injected device removal gives `device_lost` without crash; D3D11 creation failure falls through the auto chain with `d3d11/<renderer> unavailable: <why>` in `reason` | VERIFIED (hosted + golden) | Re-queried CI log (windows integration job, 40911900598): `D3D11-INJECT device-removed:30` events `[active, deviceLost, idle, resize]`, `isBroken:true`, `recoveredWithSoftware:true`, process alive; `create-fail` reason `software (sw) on cpu; vulkan/gpu-next unavailable: vkCreateInstance failed; d3d11/gpu-next unavailable: d3d11 device creation failed: 0x887A0004 (injected); ... d3d11/gpu unavailable: ...`, `trailsChecked:true`. `video_renderer_chain_test` golden scenarios (pre- and post-switch orders, device-fail, forced-no-fallback, device-lost) are in native-verify (all 13 jobs success). Limit: the hosted runner has no Vulkan, so the real-driver hop d3d11 -> Vulkan was never run on hardware (14-11 Task 2 was skipped by the decision); it is covered by the chain golden only. Recorded under Residual Risks. |
| SC5 | Windows auto chain switched to d3d11/gpu-next first as a standalone commit after CI and RTX 4060 are green; `MPV_KIT_VIDEO_API=vulkan` still forces the old path | PASSED (override): not met by user decision | `d3d11_interop.cpp:25` `kWindowsApiOrder[] = {"vulkan", "d3d11"}`, so auto stays `vulkan/gpu-next, d3d11/gpu-next, vulkan/gpu, d3d11/gpu, software/sw`; no switch commit, no `ci/14-switch` (`git ls-remote origin` shows only feat/mpv-master-upgrade, main, portable-release). Decision verbatim in `evidence/switch.txt`; the second half (vulkan forcing and Phase 12 baseline behaviour) holds trivially because the chain is unchanged. The ROADMAP checkbox, ADR 0004 Decision 5, README and `docs/perf/d3d11-backend.md` all state the real order and the not-switched outcome; REQUIREMENTS D3D-08 stays `[ ]` with "Not switched (user decision: keep)". Follow-up todo exists with a measurable done-when. |

**Score:** 5/5 (SC1-SC4 verified, SC5 override). `behavior_unverified: 0`: the behaviour-dependent truths (fence-before-publish, device_lost, resize identity, quarantine) each have a passing test run (WARP CI, RTX 4060, chain golden), not just symbol presence.

### Final CI runs (re-queried with `gh run view`)

| Run | Workflow | headSha | Conclusion | Note |
|---|---|---|---|---|
| 40911900598 | native-verify | 0cfc04ed | success | all 13 jobs success incl. sanitizers, patch-drift, windows x64 + arm64, macos x2, linux x2, hwdec-samples, flutter-video-coverage, 3 integration-test jobs |
| 40911900588 | flutter-plugin | 0cfc04ed | success | linux, windows, macos build jobs success |
| 40911900656 | macos-route | 0cfc04ed | success | route-probe (macos-15) |
| 40907471707 | release (dispatch) | 83107759 (the docs commit 8310775) | success | 6 build jobs success, `publish` skipped by design (no tag) |

`git diff 8310775 0cfc04e` touches only `.planning/` (the post-8310775 commits `0cfc04e`, `55ed02f` are docs/todo), so the product code the release run built equals the code the final native-verify/flutter-plugin runs tested. Release run `publish: skipped` is by design, same as before. Housekeeping: `evidence/final-audit.txt` and `ci-runs.txt` still cite the earlier runs 40907376074 / 40907376176 / 40907376089 at 8310775; the three 409119005xx/656 runs on 0cfc04e are not recorded there (evidence is not wrong, just one commit older).

### Audit judgments requested

- **`api_freeze` audit: ACCEPTABLE.** `git diff 182a097 HEAD -- packages/mpv_kit/lib` is non-empty only because of `8bf1efb` (Phase 16-02, `hwdec_defaults.dart` + `player.dart` default hwdec list) and `dd75d28` (quick 261028-moj, `library.dart` `MpvLibrary.open` explicit path). `git log 182a097..HEAD --grep '(14-\|261029' -- packages/mpv_kit` is empty and `api_freeze_test.dart` has no commits since 182a097. `hwdec_defaults.dart` is not exported by `lib/mpv_kit.dart`; `library.dart` is exported but the change is behaviour, not surface. I ran `dart test test/api_freeze_test.dart`: `All tests passed!`. The literal plan command exits 1 for reasons outside Phase 14; recording `ok` with the explanation (as 14-11 did) is correct. Phase 14's own public-surface cost is nil: `MpvVideoBackend { vulkan, software }` still one occurrence, `backend_api.dart` is internal.
- **`constants` audit: ACCEPTABLE.** The 3 DRIFT lines are exactly the deliberate change of `0e792c8` (quick 261029-rcc): `kPresentTimeout{50}` removed, `ring_size_ = quarantine_count_ + 2 + kReadyDepth` (kReadyDepth 2; ring 5 -> 6 default, 7 -> 8 on Windows). I confirmed in code: `video_renderer.cc:307-310`, `video_renderer.h:238-245` `kMaxQuarantine = 4`, `kReadyDepth = 2`, `d3d11_interop.h:37` `CompositorLatency() { return 4; }`. User-approved (golden re-freeze `golden_refreeze: approved`; `sha256sum -c golden-freeze-14-rcc.sha256` re-run by me: 5/5 OK), RTX A/B passed (261029-rcc-AB.txt, effective drops 0), laptop package4 FIFO result recorded. Quarantine stays 4, so SC3's "isolation period stays 4" holds. Advisory only: the Phase 12 constants audit script itself still prints DRIFT by design; update its expected counts (Phase 17) so it stops being red-by-design.

### Requirements Coverage

| Req | Status | Evidence |
|---|---|---|
| D3D-01 | SATISFIED | SC1 |
| D3D-02 | SATISFIED | SC1 (`--forbid-angle`, synthetic test, three CI hooks, ANGLE-FREE on libmpv, plugin DLL, bundle libs) |
| D3D-03 | SATISFIED | SC2 |
| D3D-04 | SATISFIED | SC2 |
| D3D-05 | SATISFIED | SC2 (both variants plus `_cache`) |
| D3D-06 | SATISFIED | SC3; RTX 4060 half closed by 14-09 (REQUIREMENTS.md checkbox `[x]` matches) |
| D3D-07 | SATISFIED (hosted + golden) | SC4 |
| D3D-08 | NOT SWITCHED by user decision | SC5 override; REQUIREMENTS.md row correctly reads "Not switched (user decision: keep)", box unchecked |

No orphaned requirements: REQUIREMENTS.md maps exactly D3D-01..08 to Phase 14.

### Other 14-09..14-11 claims checked against code

- 14-11 HUD/startup label: `backend_api.dart` returns the first reason token for `{d3d11, opengl, vulkan, software}`, else the enum name; `MpvVideoBackend` enum untouched; used at `video_controller.dart:224`.
- 14-10 runner preference: `example/windows/runner/main.cpp` `ChooseGpuPreference()` uses `GetSystemPowerStatus`, high-performance only on AC with battery saver off, else NoPreference, logs the reason, applied through `project.set_gpu_preference(...)`.
- FIFO queue: `AcquireFront` pops `queued_` first and re-notifies; publish path counts `probe_superseded_` and calls `ReportSwaps(1)` then `interop_->FrameReady()`; fallback ring uses `ready_depth_ = 1`.
- macOS debug session `macos-fifo-black-reference.md`: root cause is a pre-existing single-capture screenshot oracle flake on macos-15 (pre-FIFO run 40827789016 on byte-identical code fails identically), not the FIFO; fix 196cedc is test-only (`routeStableCapture`), no product code or threshold change; user chose option A. Consistent with the later green runs (40906xxx/409119005xx native-verify macOS jobs success).
- Debt markers: no `TBD/FIXME/XXX` in the 44 source/CI/build files touched by 14-xx/261029 commits.
- Scratch cleanup: `ci/14-*` branches are gone from origin.

### Anti-Patterns Found

None blocking. No debt markers, no stubs in `d3d11_backend.cpp`, `d3d11_interop.cpp`, `backend_api.dart`.

## Residual Risks (accepted, non-blocking)

1. **Battery-power run never executed.** The power-aware preference (`ade3eea`, NoPreference on battery / saver) is untested on the GTX 960M laptop; user will re-test. It is outside D3D-01..08 and SC1-5, but it changes which GPU Flutter, and so the plugin, uses on hybrid laptops.
2. **Bundle pin.** `bundleTag = 'v0.1.0-dev.3'` still points at a bundle without the D3D11 backend; apps consuming `mpv_kit_libs` by pin do not get d3d11 until a bundle is published and pinned (todo `2026-10-27-pin-a-bundle-with-the-d3d11-backend.md`). All Windows evidence used the release-run artifact via `libmpv_bundle` user define.
3. **Linux/macOS `FrameReady` from the compositor thread** (FIFO re-notify, `0e792c8`) is verified by CI only (native-verify and flutter-plugin, sanitizers included), never on hardware.
4. **macOS hwdec screenshot oracle flake.** Pre-hardening record: 4 red of 6 attempts on byte-identical code (about 67 percent); after `196cedc` the check passed twice with absorbed bad captures, but the root mechanism (Apple Paravirtual + MoltenVK readback) is unproven and a bad window longer than about 1.2 s is not absorbed. Treat an occasional red macos-15 `integration-test` as a likely flake, not a Phase 14 regression; probability is not zero and one or two green draws are not a rate.
5. **Real-driver d3d11 -> Vulkan creation-failure hop** was never executed (hosted runner has no Vulkan; 14-11 Task 2 skipped). `docs/perf/d3d11-backend.md` line 46 still says it "is verified after 14-11" (stale); the Verification-tiers section correctly lists it as unverified. Fix the line 46 wording when convenient.
6. **D3D11 slower than Vulkan on Maxwell** (GTX 960M: about 3.5 percent vs about 0.5 percent effective drops, done 3-13 ms vs 0.05 ms). Reason for the keep decision; investigation todo is open. Laptop numbers are orchestrator-computed estimates from pasted logs, not durations the user reported.
7. **RTX 4K 600 s is a single passing run** (attempt 1 failed with 22 drops during Modern Standby and is kept in the ledger); D-05 outcome is `failed` in the Phase 12 pixel-probe class, judged `no-new-failure`, not a pass.
8. The HD-530-only case (Flutter forced onto the integrated GPU) still drops frames: documented GPU-capability limitation, 14-10 verdict `pass-with-drops-accepted` (user-authoritative).

## STATE.md progress (milestone v3.0, phases 12-17)

Actual SUMMARY files: 12 -> 12/12, 13 -> 6/6, 14 -> 11/11, 15 -> 7/7, 16 -> 6/6, 17 -> 0/5 (5 plans, 0 summaries). Totals: **total_plans 47, completed_plans 42, percent 89 (42/47)**; **total_phases 6, completed_phases 5** (12, 13, 14, 15, 16; 17 not started), phase-based 83 percent. `.planning/STATE.md` currently says completed_plans 39, completed_phases 4, percent 67 (and its body still shows `Progress: [█████░░░░░] 50%` and `Total plans completed: 36`, plus `status: executing` / `last_activity: 2026-10-28`), so it is stale by 3 plans and 1 phase. Correct values once Phase 14 is accepted: `completed_phases: 5`, `completed_plans: 42`, `percent: 89`. ROADMAP.md progress table is already correct (12/12, 6/6, 11/11, 7/7, 6/6, 0/TBD).

## Gaps Summary

No gaps. Every plan-level deliverable exists and is wired; SC1-SC4 are proven by re-queried CI logs, code and recorded hardware runs; SC5 is intentionally unmet under an explicit, verbatim user decision and carried as an override with a follow-up todo. Residual risks above are accepted-and-tracked, not blockers. If a stricter reading is wanted (battery run counted as a required human check), the status would be `human_needed` on that single item; I did not do so because it is attached to no roadmap SC or D3D requirement.

---

_Verified: 2026-10-30_
_Verifier: Claude (gsd-verifier)_

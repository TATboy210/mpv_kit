---
phase: 16-hardware-decode-zero-copy
verified: 2026-10-29T07:00:00Z
status: passed
score: 4/4 must-haves verified
covered_files:
  - ".planning/phases/16-hardware-decode-zero-copy/16-01-PLAN.md"
  - ".planning/phases/16-hardware-decode-zero-copy/16-01-SUMMARY.md"
  - ".planning/phases/16-hardware-decode-zero-copy/16-02-PLAN.md"
  - ".planning/phases/16-hardware-decode-zero-copy/16-02-SUMMARY.md"
  - ".planning/phases/16-hardware-decode-zero-copy/16-03-PLAN.md"
  - ".planning/phases/16-hardware-decode-zero-copy/16-03-SUMMARY.md"
  - ".planning/phases/16-hardware-decode-zero-copy/16-04-PLAN.md"
  - ".planning/phases/16-hardware-decode-zero-copy/16-04-SUMMARY.md"
  - ".planning/phases/16-hardware-decode-zero-copy/16-05-PLAN.md"
  - ".planning/phases/16-hardware-decode-zero-copy/16-05-SUMMARY.md"
  - ".planning/phases/16-hardware-decode-zero-copy/16-06-PLAN.md"
  - ".planning/phases/16-hardware-decode-zero-copy/16-06-SUMMARY.md"
  - "docs/adr/0006-hwdec-defaults.md"
  - "docs/perf/hwdec-zero-copy.md"
  - "example/integration_test/hwdec_probe.dart"
  - "example/integration_test/hwdec_zero_copy_test.dart"
  - "native/patches/0004-libmpv-gpu-next-render-backend-and-renderer-report.patch"
  - "native/tests/video_renderer_drm_params_test.cc"
  - "packages/mpv_kit/lib/src/player/hwdec_defaults.dart"
  - "packages/mpv_kit/lib/src/player/player.dart"
  - "packages/mpv_kit_video/src/drm_render_node.h"
covered_digest: "v4:sha256:144169f9468f37d36a43251b764da7aaef58e0a8c8a3ec6f2cf40715c8bd3b41"
behavior_unverified: 0
overrides_applied: 0
---

# Phase 16: Hardware-Decode Zero-Copy Verification Report

**Phase Goal:** hwdec is zero-copy-first on every native backend, defaults no longer silently select copy-back, and every test states whether it ran zero-copy, copy-back or software.
**Verified:** 2026-10-29
**Status:** passed (with warnings listed below; no BLOCKER)
**Re-verification:** No, initial verification

## Observable Truths (ROADMAP success criteria, SC3 in the 2026-10-29 user-approved wording, commit 94ed533)

| # | Criterion | Status | Evidence |
|---|-----------|--------|----------|
| 1 | Per-platform ordered zero-copy-first default list, documented as behavior change; explicit user `hwdec` wins | VERIFIED | `packages/mpv_kit/lib/src/player/hwdec_defaults.dart` (windows `vulkan,d3d11va,d3d11va-copy,auto-safe`, linux `vulkan,vaapi,auto-safe`, macos `videotoolbox,auto-safe`, other `auto-safe`) is wired in `player.dart:107` with `...options` last. It matches `decisions.txt` `hwdec-defaults choice=adopt`. `packages/mpv_kit/test/hwdec_defaults_test.dart` pins the lists, the order and the `auto-safe` tail. `player_test.dart:443` and `:450` cover "default is the per-platform list" and "yields to explicit user hwdec". Docs: ADR 0006, README section at line 197, CHANGELOG "Changed (behavior)". The decisive checks ran in CI: native-verify 40715501196 (`gh run view`: success, sha 8bf1efb) and 40798831729 (success, ad5c54b). |
| 2 | RTX 4060 + D3D11 backend: `hwdec-current=d3d11va`, 4K HEVC 10-bit correct, no green/black frames | VERIFIED (forced `MPV_KIT_VIDEO_API=d3d11`, user decision `hwd02-acceptance`) | `rtx4060-hwdec-runs.txt` `hwd02 ... attempt=2 api=d3d11 hwdecCurrent=d3d11va pixelformat=d3d11 hwPixelformat=p010 outcome_first=zero-copy outcome_end=zero-copy frameChecks=match,match,match flutterFrame=match playedToEnd=true hwdecStable=true drops 0/0/0 deviceLost=0`. Raw log `rtx-hwdec-d3d11-a2.log` exists. Bundle is release run 40812562348 (success, manifest=ok); samples come from run 40798831729 (success). The attempt-1 failure (test ready condition fixed at 640x360) is preserved and was fixed in test-only commit f644220. See warning W2. |
| 3 | Linux passes `MPV_RENDER_PARAM_DRM_DISPLAY_V2` (render node via EGL device or Vulkan physical device); GL (vo_gpu) and Vulkan gpu-next register it as a native resource (fake libmpv + drm smoke); no `/dev/dri` falls back to software without crashing; real vaapi load and zero-copy marked unverified | VERIFIED (under the reworded SC) | Code: `drm_render_node.h` exists. `vulkan_backend.cc:500,516` resolves via `OpenDrmRenderNode` and sets `params[4]=DRM_DISPLAY_V2`. `opengl_backend.cc:307` does the same. Patch 0004 registers `drm_params_v2` on the ra for gpu-next. `native/tests/video_renderer_drm_params_test.cc` is the fake-libmpv test. CI (run 40798831729, success): `RENDER_VK drm ok renderer=gpu-next native_resource=registered`, `RENDER_GL drm ok`, `DRM-PARAMS ok scenarios=4` on ubuntu x64/arm64/sanitizers, `CONFIG-VAAPI ok`. No-`/dev/dri` safe fallback shows in the ubuntu hevc-10bit rows (`outcome=software`, `playedToEnd=true`). Real vaapi load and zero-copy appear in `unverified.txt` (9 Linux items, none claimed verified). |
| 4 | Every soak/integration test prints and asserts `hwdec-current` and zero-copy yes/no; `hwdec=no` software decode passes on d3d11, opengl, vulkan and software | VERIFIED | `HWDEC` lines are wired into all eight lavfi tests (16-05; `ci-runs-16-05.txt`) plus `hwdec_zero_copy_test.dart` (asserts at lines ~614-655) and `hwdec_probe.dart` (classifier, 26 unit tests). Matrix in run 40798831729 (success): opengl, vulkan, software on ubuntu; d3d11 (WARP) and software on windows; vulkan and software on macos-15. All show `hwdec=no` as software. Scope A (user decision `hwd05-scope`) limits lavfi soaks to asserting software. See W1. |

**Score:** 4/4 criteria verified. No override was needed.

## Requirements Coverage

| Requirement | Status | Evidence |
|-------------|--------|----------|
| HWD-01 (ticked) | SATISFIED | See SC1. |
| HWD-02 (ticked) | SATISFIED, forced-d3d11 | See SC2. The auto chain still picks Vulkan until 14-11, so the default Windows route on RTX 4060 is not yet the D3D11 path (listed in `unverified.txt`). |
| HWD-03 (NOT ticked, REQUIREMENTS.md "Pending") | PARTIAL, intentional | The requirement text still demands "GL and Vulkan gpu-next can load vaapi interop". Only parameter passing, native-resource registration and safe fallback are proved. Real interop and zero-copy need Linux GPU hardware, which the project lacks. Correctly left Pending; not a goal gap, because SC3 was reworded with user approval. |
| HWD-05 (ticked) | SATISFIED (scope A) | See SC4. |
| Orphaned requirements | None | HWD-04 maps to Phase 13. |

## Anti-Patterns

No TBD/FIXME/XXX markers or stubs found in the checked phase files. Wiring was confirmed: the default list reaches `Player`, the DRM param reaches `mpv_render_context_create` params, and the 0004 patch registers the native resource.

## Warnings (none blocks the phase goal)

- **W1 (macOS videotoolbox screenshot flake).** native-verify run 40816828616 (f644220, current branch HEAD lineage) and 40800969371 (15f61ff, two attempts) are `failure`, confirmed with `gh run view`. The only red check is the macOS-15 `hwdec_zero_copy_test` videotoolbox screenshot comparison. The failing seek point varies run to run (frameDrops 19/35 on the VM), and ad5c54b (run 40798831729) was fully green. This does not undermine any SC. SC1 is proved by the list and option tests. SC2 is Windows/RTX only. SC3 is Linux only. SC4 requires `hwdec=no` software on each backend, and that leg is green everywhere; the flaky leg is the default-list hardware leg on macOS, which is HWD-04 territory (Phase 13) and not an SC4 requirement. It is still an open red on the branch. Phase 17's forced-backend CI matrix will inherit it unless the pending debug session fixes or quarantines it. Recorded in `decisions.txt` and `unverified.txt`.
- **W2 (SC2 evidence is local, not CI).** The RTX 4060 logs and ledger are the only proof of d3d11va zero-copy. Both sides are traceable: the bundle (run 40812562348) and samples (run 40798831729) are CI artifacts, and the raw logs are committed. It is not independently re-runnable by the verifier here. The ledger is internally consistent: the attempt-1 failure was recorded rather than hidden, and the forensics correction is recorded.
- **W3 (default Windows route not the verified one).** SC2 is accepted under forced d3d11. With `MPV_KIT_VIDEO_API` unset, auto selects Vulkan (`rtx-hwdec-auto.log`: vulkan hwdec zero-copy, information only). The d3d11va default path is unverified until 14-11.
- **W4 (stale bookkeeping).** ROADMAP.md Phase 16 header still reads "5/6 plans executed" while the progress table says 6/6 Complete. `16-06-SUMMARY.md` frontmatter says `status: awaiting-human-check` and `requirements-completed: []`, although `decisions.txt` records `phase16-close` on 2026-10-29. Cosmetic.
- **W5 (unverified inventory).** `unverified.txt` lists 18 items, all marked 未验证: real VA-API (GL and Vulkan), 10-bit dma-buf modifiers, real render-node resolution, hybrid GPU, NVIDIA, fd lifetime, AMD/Intel d3d11va, Windows arm64, 8K, Apple hardware, and others. The honesty of this list is itself a goal-aligned deliverable.

## Human Verification

No new items. The user closed the phase (`decision=phase16-close`) after reviewing the same evidence.

## Gaps Summary

No BLOCKER gaps. Phase 16 achieves its (reworded) goal. HWD-03 stays open by design until Linux GPU hardware exists. The macOS videotoolbox flake and 14-11 are carried forward as follow-ups.

---

_Verified: 2026-10-29_
_Verifier: Claude (gsd-verifier)_

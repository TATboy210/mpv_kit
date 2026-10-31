---
phase: 14-windows-native-d3d11-backend
plan: 06
subsystem: native
tags: [mpv, d3d11, gpu-next, libplacebo, patch-0004, smoke-test, shader-cache, warp]

requires:
  - phase: 14-05
    provides: patch 0010 (upstream D3D11 render API, libmpv_gpu_context_d3d11)
provides:
  - "native/tests/render_d3d11_smoke.c: headless D3D11 render API smoke (gpu / gpu-next / --cache-dir two-pass), red/blue orientation + non-black readback, renderer-mismatch failure, 77 only without any D3D11 device"
  - "Patch 0004 D3D11 branch: ra_d3d11 + pl_d3d11 on the host device, pl_d3d11_wrap of the host texture, VO-owned shader cache (DXBC), teardown VO -> pl_d3d11 -> ra"
  - "release.yml windows job step running the three smoke variants on the packaged bundle with the prefix hidden"
affects: [14-07, 14-08]

actuals:
  tokens: 15500
  tasks: 3
  commits: 3
plan_head_before: 4d0ea58ea25f4cc5644761cd5bc3e571d438a327
plan_head_after: e2809809527985437d0348a2a563f6f2c7117ea8
# commits is measured: 4d0ea58..e280980 = 3 (eb98e0e smoke gpu, be6240b 0004 D3D11 branch + cache smoke, e280980 release step).

key-files:
  created:
    - native/tests/render_d3d11_smoke.c
  modified:
    - native/tests/meson.build
    - native/patches/0004-libmpv-gpu-next-render-backend-and-renderer-report.patch
    - native/patches/UPSTREAM.md
    - native/mpv/video/out/vo_gpu_next.c
    - native/mpv/include/mpv/render_vk.h
    - packages/mpv_kit_video/src/include/mpv/render_vk.h
    - .github/workflows/release.yml
    - .planning/phases/14-windows-native-d3d11-backend/evidence/ci-runs.txt

key-decisions:
  - "D3D11 gpu-next uses the VO's own cache_init/pl_gpu_set_cache via a new priv->libmpv_vo_cache flag (Vulkan keeps the 0003 context cache); no cache code duplicated."
  - "pl_d3d11 is created from ra_d3d11_get_device(ra) (one device, as gpu_next/context.c); failure returns MPV_ERROR_UNSUPPORTED, no silent fallback."
  - "Public ABI of 0010 untouched; no new render parameter: MPV_RENDER_PARAM_VULKAN_RENDERER documents D3D11 use."

requirements-completed: [D3D-04, D3D-05]

ci_gates_passed:
  - gate: "Task 1 scratch variant: render_d3d11_smoke_gpu OK on windows-2025 and windows-11-arm, render_vk_smoke_gpu OK|SKIP on windows-2025 (SKIP, exit 77)"
    result: "CI-GATE ok"
    sha: 091228abd70b22fbe2f425fdd1efb75eb8cfcb54
    runs: "native-verify 40627862148, flutter-plugin 40627862039"
  - gate: "Task 2 feat gate: render_d3d11_smoke, _gpu, _cache OK on windows-2025; render_d3d11_smoke + _cache OK on windows-11-arm; render_vk_smoke OK and video_renderer_golden_vk OK on linux; PATCH-DRIFT OK patches=10"
    result: "CI-GATE ok (flagged assumptions settled: pl_d3d11 + ra_d3d11 coexist on WARP, hosted d3dcompiler runs the gpu-next shaders)"
    sha: 091228abd70b22fbe2f425fdd1efb75eb8cfcb54
    runs: "native-verify 40627862148, flutter-plugin 40627862039"
  - gate: "Task 3 release gate: [smoke] device line on both windows jobs"
    result: "matched `[smoke] device Microsoft Basic Render Driver (hardware bgra+video)`; six build jobs success, publish skipped"
    sha: b40cdff9262e32f884f4c71b31d3306a4fa37e49
    runs: "release.yml 40618740386"

duration: about 45 min
completed: 2026-10-27
status: complete
---

# Phase 14 Plan 06: D3D11 render smoke and gpu-next D3D11 path (patch 0004) Summary

**gpu-next now has a D3D11 branch in patch 0004 (same-device `ra_d3d11` + `pl_d3d11`, `pl_d3d11_wrap` host texture, VO-owned DXBC shader cache), with a new `render_d3d11_smoke` (gpu, gpu-next, cache) and a packaged-bundle step in release.yml. PATCH-DRIFT passes locally with `patches=10`; nothing has been compiled or run on Windows with mpv (hosted CI deferred).**

## Accomplishments

- `native/tests/render_d3d11_smoke.c`: device creation via hardware (BGRA+VIDEO), hardware (BGRA), WARP; 64x64 BGRA8 shared render target; lavfi red-over-blue; asserts active renderer equals requested, red top / blue bottom, non-black >= 99%; `--cache-dir=` runs two complete passes and checks files written, no new files in pass 2, and `cache_load_obj` with size > 0 in the pass 2 debug log. The file compiled clean locally with MSVC `/W4 /WX /std:c11` (compile only; cannot link or run without libmpv).
- 0004 regenerated from a scratch worktree (base b2c255c13 + 0001..0003, 0004-old, then the D3D11 change as one commit) and re-stacked with 0006..0010 and 0012: 0009 applied with offsets only, no rejects; the resulting tree is byte-identical to the vendored `native/mpv` (diff -rq clean) and `tools/check_patches.sh` prints `PATCH-DRIFT OK ... patches=10`.
- `render_vk.h` documents the renderer parameter for D3D11; plugin copy byte-identical (`cmp`). UPSTREAM.md updated (table row, 14-06 note).
- release.yml windows job: builds only `render_d3d11_smoke` against the prefix, hides the prefix, runs the three variants with PATH limited to the bundle and Windows dirs; exit 77 is a failure. `check_matrix.py` ok.

## Task Commits

1. Task 1, smoke gpu variant + meson - `eb98e0e`
2. Task 2, 0004 D3D11 branch, vendor/plugin sync, cache smoke, UPSTREAM.md - `be6240b`
3. Task 3, packaged-bundle smoke step + ci-runs deferral line - `e280980`

## Verification (local)

- `bash tools/check_patches.sh`: PATCH-DRIFT OK, patches=10.
- `cmp native/mpv/include/mpv/render_vk.h packages/mpv_kit_video/src/include/mpv/render_vk.h`; grep for `pl_d3d11_wrap` in 0004 and `ra_d3d11_get_device` in vo_gpu_next.c: pass.
- Golden-freeze (golden-freeze-14.sha256): 5 OK. `dart run tools/check_consistency.dart`: all invariants hold. `python tools/check_matrix.py`: ok. release.yml parses as YAML.
- Not runnable here: meson/libmpv build, any execution of the smoke, Vulkan smoke/goldens on Linux.

## Acceptance items by status

| Item | Status |
|---|---|
| 0004 D3D11 branch, PATCH-DRIFT `patches=10`, header sync, UPSTREAM.md | done (local) |
| smoke source, meson tests, release step, check_matrix | done (local) |
| gpu / gpu-next / cache OK on windows-2025 and windows-11-arm, bundle smoke, Vulkan paths unchanged | ci-gate: deferred |

## Deviations from Plan

**1. [Process] Scratch/feat pushes and all CI gates not run** (CI deferral 2026-10-27). ci-runs.txt carries a `deferred` line; no run IDs invented.

**2. [Process] Test registration order.** Task 1 registered only `render_d3d11_smoke_gpu`; `render_d3d11_smoke` and `render_d3d11_smoke_cache` were added in Task 2 as planned.

**3. [Implementation choice within plan] Renderability check.** `wrap_d3d11_fbo` rejects a host texture whose `pl_tex` is not renderable (no `D3D11_BIND_RENDER_TARGET`) with `MPV_ERROR_INVALID_PARAMETER`, mirroring the ra path in 0010. `vo_libmpv.c` was not changed (as the plan predicted); the 0004 `get_info` code is function-table based and already covers D3D11.

No other deviations.

## Known Stubs

None.

## Threat Flags

None. T-14-15 accepted (same cache trust model as 0003); T-14-16 mitigated in code (skip only when no device can be created, renderer-mismatch and orientation checks, release step treats 77 as failure).

## Self-Check: PASSED

- Files present: render_d3d11_smoke.c, 0004 patch with `pl_d3d11_wrap`, release.yml step.
- Commits eb98e0e, be6240b, e280980 are ancestors of HEAD.

## CI backfill (2026-10-28)

The deferred hosted gates were evaluated by this phase's unmodified `tools/ci_gate.sh` against completed runs (PR runs at feat HEAD 091228a: native-verify 40627862148, flutter-plugin 40627862039; release.yml dispatch 40618740386 at b40cdff, valid for the libmpv bundle because b40cdff..091228a only touched the native-verify windows integration step, d3d11_backend.cpp WaitQuery flags, integration tests and notes). A gh shim served the cached logs; nothing was dispatched, rerun or pushed. `--jobs-success .` on release.yml fails literally only on the tag-only `publish` job (skipped by design); all build jobs and every `--log` expectation held. D3D-04/D3D-05: on WARP (`Microsoft Basic Render Driver`) `render_d3d11_smoke` (gpu), `render_d3d11_smoke_gpu` (gpu-next) and `render_d3d11_smoke_cache` (shader cache) are OK on windows-2025 and windows-11-arm.
Evidence: `evidence/ci-runs.txt` (backfill block with the raw matched lines)

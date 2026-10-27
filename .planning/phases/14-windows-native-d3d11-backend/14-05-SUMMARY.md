---
phase: 14-windows-native-d3d11-backend
plan: 05
subsystem: native
tags: [mpv, d3d11, render-api, patch-0010, upstream-backport, client-api-2.6]

requires:
  - phase: 14-04
    provides: Windows bundle builds mpv with HAVE_D3D11
provides:
  - "native/patches/0010-upstream-d3d11-render-api.patch: six verbatim upstream commits (PR #17764 + 2 prerequisites) plus the done_frame bool adaptation"
  - "Vendor tree with MPV_RENDER_API_TYPE_D3D11, render_d3d11.h, client API 2.6; PATCH-DRIFT OK patches=10"
  - "Plugin headers render.h and render_d3d11.h byte-identical to native/mpv/include/mpv"
affects: [14-06, 14-07]

actuals:
  tokens: 14000
  tasks: 2
  commits: 2
plan_head_before: d10ec133a06535407863cbea238784c8334a8e37
plan_head_after: 32e78f3
# commits is measured: d10ec13..32e78f3 = 2 (4f4e49d patch + vendor + evidence, 32e78f3 plugin headers + UPSTREAM.md).

key-files:
  created:
    - native/patches/0010-upstream-d3d11-render-api.patch
    - native/mpv/include/mpv/render_d3d11.h
    - native/mpv/video/out/d3d11/libmpv_d3d11.c
    - packages/mpv_kit_video/src/include/mpv/render_d3d11.h
    - .planning/phases/14-windows-native-d3d11-backend/evidence/abi-0010.txt
  modified:
    - native/mpv (client.h, render.h, meson.build, client-api-changes.rst, d3d11/context.c, d3d11/ra_d3d11.c, gpu/d3d11_helpers.c/.h, gpu/error_diffusion.c, gpu/video.c, gpu/libmpv_gpu.c/.h)
    - native/patches/UPSTREAM.md
    - packages/mpv_kit_video/src/include/mpv/render.h
    - .planning/phases/14-windows-native-d3d11-backend/evidence/ci-runs.txt

key-decisions:
  - "User decision 2026-10-27 (option 1): include the two prerequisite upstream commits 44be29945 and d802fab36 verbatim in 0010 instead of advancing the vendor or hand-adapting 2a97b84b39."

requirements-completed: []
requirements-partial: [D3D-03]  # patch, vendor tree, ABI identity and PATCH-DRIFT done locally; two-layer Windows compile and feat/release CI are ci-gate: deferred

deferred_ci_gates:
  - "Task 1 scratch: push ci/14-0010 (0010 + vendor tree), `gh workflow run native-verify.yml --ref ci/14-0010` and `gh workflow run release.yml --ref ci/14-0010`, then `CI_GATE_BRANCH=ci/14-0010 bash .planning/phases/14-windows-native-d3d11-backend/tools/ci_gate.sh --jobs-success '.'` (patch-drift, both windows verify jobs, linux/macos/sanitizers) and the same with `--workflow release.yml`. First compile of libmpv_d3d11.c is unverified; if a compile fails fix only the adaptation, never the public headers."
  - "Task 2 PR gate on feat: `bash .planning/phases/14-windows-native-d3d11-backend/tools/ci_gate.sh --jobs-success '.' --log '^patch-drift' 'PATCH-DRIFT OK .*patches=10'`"
  - "Task 2 release gate on feat: after `gh workflow run release.yml --ref feat/mpv-master-upgrade`, `bash .planning/phases/14-windows-native-d3d11-backend/tools/ci_gate.sh --workflow release.yml --jobs-success '.'`, plus ABI audit / expected_symbols unchanged."

duration: about 40 min
completed: 2026-10-27
status: complete
---

# Phase 14 Plan 05: Upstream D3D11 render API backport (patch 0010) Summary

**Patch 0010 backports the upstream mpv D3D11 render API (client API 2.6, params 21/22) as six verbatim upstream commits plus a one-line `done_frame` bool adaptation; `render_d3d11.h` and `render.h` are byte-identical to upstream 4255130de4, and PATCH-DRIFT passes locally with `patches=10`. No Windows compile has run (hosted CI deferred).**

## Accomplishments

- Built 0010 in a scratch clone (`build/phase14/mpv-patchwork`, gitignored) on base b2c255c13 + 0001..0009 using `cherry-pick -x` in the order 44be29945, d802fab36, 5deaba46b, 0b3d2ab52, b1b03bd34, 4255130de4, then one local commit (`done_frame` returns bool, `return true;`).
- Applied it to `native/mpv` with `patch -p1`; `bash tools/check_patches.sh` prints `PATCH-DRIFT OK base=b2c255c13... patches=10` (0012 stacks on top unchanged).
- ABI (evidence/abi-0010.txt): `render_d3d11.h` identical (also verified through `gh api`), `render.h` identical, `MPV_CLIENT_API_VERSION` 2.6 identical, `MPV_RENDER_PARAM_D3D11_INIT_PARAMS=21`, `MPV_RENDER_PARAM_D3D11_FBO=22`. Per-file hunk record included.
- Conflicts, all resolved by keeping our semantics and adding upstream lines: `libmpv_gpu.h` (0001 vk extern), `meson.build` (0001/0006 header list), `client-api-changes.rst` (0001 mpv_kit block); `libmpv_gpu.c` auto-merged with both the d3d11 and vk entries.
- Plugin headers synced; UPSTREAM.md has the 0010 table row and a provenance section.

## Task Commits

1. Patch 0010, vendor tree, abi-0010.txt, ci-runs placeholder - `4f4e49d`
2. Plugin header sync and UPSTREAM.md - `32e78f3`

## Verification (local)

- `bash tools/check_patches.sh`: PATCH-DRIFT OK, patches=10.
- Plan grep chain for abi-0010.txt, `bool done_frame` and `libmpv_gpu_context_d3d11`: pass. `cmp` of both plugin headers vs vendor: pass.
- golden-freeze-14.sha256: 5 OK. `dart run tools/check_consistency.dart`: all invariants hold.
- Not runnable here (no mpv toolchain): any compile of the patched mpv.

## Acceptance items by status

| Item | Status |
|---|---|
| PATCH-DRIFT local `patches=10`, ABI comparisons, hunk record | done |
| Plugin header sync, UPSTREAM.md | done |
| scratch/feat native-verify, release windows jobs compile 0010, exported symbols unchanged | ci-gate: deferred |

## Deviations from Plan

**1. [Plan assumption realised - user decision] 6 commits, not 4.** The plan's must_have says 0010 carries 4 commits. `2a97b84b39` (b1b03bd34) needs the base to already contain `44be29945` and `d802fab36`; without them it conflicts in ra_d3d11.c and calls an undefined helper. The user chose to include both verbatim (option 1). The truth should read "6 upstream commits: 4 from PR #17764 plus 2 prerequisites". Both are internal-only; no public ABI change.

**2. [Rule 3] SHA/range mapping.** PR #17764 was rebase-merged, so the plan's SHAs are PR-head SHAs and `4255130de4^1..^2` does not exist. Master equivalents (patch-ids identical) were cherry-picked; the mapping is in abi-0010.txt and UPSTREAM.md.

**3. [Process] Extra path.** `video/out/gpu/d3d11_helpers.h` (from prerequisite 44be29945) is also modified; the vendor tree changes 15 paths, not 14.

**4. [Process] Scratch/feat pushes and CI gates not run** (CI deferral 2026-10-27); ci-runs.txt carries a `deferred` line, no invented run IDs.

## Known Stubs

None.

## Threat Flags

None. T-14-13/T-14-14 mitigated locally (official-repo commits via `cherry-pick -x`, byte comparison of public headers); the compile check remains deferred.

## Self-Check: PASSED

- Files present: 0010 patch, `render_d3d11.h` (vendor and plugin), `libmpv_d3d11.c`, abi-0010.txt.
- Commits 4f4e49d and 32e78f3 are ancestors of HEAD.

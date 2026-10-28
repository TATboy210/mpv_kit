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

requirements-completed: [D3D-03]

ci_gates_passed:
  - gate: "Task 1 scratch (ci/14-0010 native-verify + release): superseded by the feat PR run (patch-drift, both windows verify jobs, linux/macos/sanitizers all success) and the feat release dispatch; libmpv_d3d11.c compiled on both Windows targets"
    result: "CI-GATE ok --jobs-success . (PR) / release six build jobs success"
    sha: 091228abd70b22fbe2f425fdd1efb75eb8cfcb54 (PR), b40cdff9262e32f884f4c71b31d3306a4fa37e49 (release)
    runs: "native-verify 40627862148, flutter-plugin 40627862039; release.yml 40618740386"
  - gate: "Task 2 PR gate: --jobs-success . --log ^patch-drift PATCH-DRIFT OK .*patches=10"
    result: "CI-GATE ok (PATCH-DRIFT OK base=b2c255c13e8e37952dbac6c34da56a690560378b patches=10)"
    sha: 091228abd70b22fbe2f425fdd1efb75eb8cfcb54
    runs: "native-verify 40627862148, flutter-plugin 40627862039"
  - gate: "Task 2 release gate: release.yml jobs, ABI audit / expected_symbols unchanged"
    result: "six build jobs success, publish skipped; pe_audit in package.sh passed on every Windows DLL (libmpv-2.dll exports(mpv_*): 58 on both targets); tools/rea_abi_audit/expected_symbols.txt last changed in d5bbd20 (before Phase 14)"
    sha: b40cdff9262e32f884f4c71b31d3306a4fa37e49
    runs: "release.yml 40618740386"

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

## CI backfill (2026-10-28)

The deferred hosted gates were evaluated by this phase's unmodified `tools/ci_gate.sh` against completed runs (PR runs at feat HEAD 091228a: native-verify 40627862148, flutter-plugin 40627862039; release.yml dispatch 40618740386 at b40cdff, valid for the libmpv bundle because b40cdff..091228a only touched the native-verify windows integration step, d3d11_backend.cpp WaitQuery flags, integration tests and notes). A gh shim served the cached logs; nothing was dispatched, rerun or pushed. `--jobs-success .` on release.yml fails literally only on the tag-only `publish` job (skipped by design); all build jobs and every `--log` expectation held. D3D-03: PATCH-DRIFT OK with patches=10 on the PR run; libmpv-2.dll with the 0010 D3D11 render API built and audited on x64 and arm64 in the release run.
Evidence: `evidence/ci-runs.txt` (backfill block with the raw matched lines)

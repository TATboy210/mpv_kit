---
phase: 14-windows-native-d3d11-backend
plan: 04
subsystem: infra
tags: [windows, d3d11, spirv-cross, shaderc, libplacebo, deps-sh, build-sh, bundle]

requires:
  - phase: 14-03
    provides: ANGLE/GPL audit over every Windows bundle DLL (covers the new DLLs automatically)
provides:
  - "deps.sh Windows-only SPIRV-Cross (spirv-cross-c-shared) and shaderc_shared build from pinned sha256 sources"
  - "libplacebo -Dd3d11=enabled on Windows, disabled elsewhere; pinned patch count 16"
  - "libplacebo backports 0015 (82224764a9) + 0016 (c43baa7a0c), fuzz 0 on 7.360.1 + 14 patches"
  - "build.sh Windows mpv -Dd3d11/-Dshaderc/-Dspirv-cross enabled with config.h assertions"
  - "NOTICE paragraph and bundle-spike.txt with the user decision decision=shared"
affects: [14-05, 14-06, 14-07, 15-01]

actuals:
  tokens: 6000
  tasks: 3
  commits: 4
plan_head_before: 49343715ff2c8d6305496d9f8ea7b2c301881725
plan_head_after: ea17bcc92797a66663dc7eec61466d942c2f3702
# commits is measured: 4934371..ea17bcc = 4 (5f4bfae ci-runs record, 6b0665d libplacebo pair, 73ce42a bundle build, ea17bcc assertion wording).

key-files:
  created:
    - native/deps/libplacebo/0015-82224764a9.patch
    - native/deps/libplacebo/0016-c43baa7a0c.patch
    - .planning/phases/14-windows-native-d3d11-backend/evidence/bundle-spike.txt
  modified:
    - native/build/deps.sh
    - native/build/build.sh
    - native/deps/libplacebo/SHA256SUMS
    - native/patches/UPSTREAM.md
    - NOTICE
    - .planning/phases/14-windows-native-d3d11-backend/evidence/ci-runs.txt

key-decisions:
  - "Bundle composition decision=shared (user, 2026-10-27T10:05:00Z): shaderc_shared and spirv-cross-c-shared are separate DLLs. If shaderc does not build on glslang 16.6.0 the user-approved fallback is own-glslang."
  - "shaderc is installed into a staging directory and only its header, import library, DLL and shaderc.pc are copied into PREFIX, so the glslang that shaderc builds from the same sources cannot overwrite the optimizer-less glslang libplacebo links."
  - "shaderc tag v2026.4 (newest tag, confirmed with gh api); SPIRV-Tools of the SDK tag equals shaderc's own DEPS pin ef96ed76."

requirements-completed: []
requirements-partial: [D3D-01]  # code, pins, patches done locally; Windows build, bundle audit and feat gates are ci-gate: deferred

deferred_ci_gates:
  - "Task 1 spike (never run): scratch ci/14-bundle, `gh workflow run release.yml --ref ci/14-bundle`, wait with `CI_GATE_BRANCH=ci/14-bundle bash .planning/phases/14-windows-native-d3d11-backend/tools/ci_gate.sh --workflow release.yml --jobs-success '^windows \\('`; record `attempt n=<k> run=<id> target=<x64|arm64> ...`, `dlls`, `bundle_total`, `have_d3d11` lines in bundle-spike.txt. Open questions: shaderc on glslang 16.6.0, shaderc on CLANGARM64, DLL names/sizes."
  - "Task 3 release gate: `bash .planning/phases/14-windows-native-d3d11-backend/tools/ci_gate.sh --workflow release.yml --jobs-success '.' --log '^windows \\(windows-2025' '#define HAVE_D3D11 1' --log '^windows \\(windows-11-arm' '#define HAVE_D3D11 1' --log '^windows \\(windows-2025' 'ANGLE-FREE .*spirv-cross' --log '^windows \\(windows-11-arm' 'ANGLE-FREE .*spirv-cross'` on feat HEAD after `gh workflow run release.yml --ref feat/mpv-master-upgrade`."
  - "Task 3 PR gate: `bash .planning/phases/14-windows-native-d3d11-backend/tools/ci_gate.sh --jobs-success '.'` (native-verify and flutter-plugin; Linux deps cache rebuilds because the deps.sh hash changed, the Linux path is unchanged)."
  - "Task 3 step 5: download libmpv-windows-x64 / -arm64, check MANIFEST.txt lists every lib/*.dll including the two new ones, share/licenses has spirv-cross, shaderc, spirv-tools, spirv-headers; append `final target=<..> run=<id> dlls=<n> manifest_ok=<yes|no> licenses=<list>` to bundle-spike.txt."

duration: about 1h (no hosted CI waits)
completed: 2026-10-27
status: complete
---

# Phase 14 Plan 04: Windows D3D11 bundle dependencies Summary

**The Windows build now compiles SPIRV-Cross (`spirv-cross-c-shared`) and `shaderc_shared` from sha256-pinned official sources, turns on libplacebo `pl_d3d11` and mpv `-Dd3d11/-Dshaderc/-Dspirv-cross` there, and carries the 82224764a9 + c43baa7a0c libplacebo fixes as patches 0015/0016; none of it has been built on Windows yet (hosted CI deferred).**

## Accomplishments

- **deps.sh (Windows block after glslang):** SPIRV-Cross with `SPIRV_CROSS_SHARED=ON`, static/CLI/tests off (installs `spirv-cross-c-shared.pc`, the name mpv and libplacebo look up). shaderc v2026.4 built with `SHADERC_GLSLANG_DIR` pointing at the already fetched glslang 16.6.0 plus SPIRV-Tools and SPIRV-Headers of `vulkan-sdk-1.4.363.0`; tests, examples, executables, copyright check and `-Werror` off. Licenses for spirv-cross, shaderc, spirv-tools and spirv-headers go to `share/licenses/`. `cmake_build` gained an optional `cmake_dest` so shaderc can install into staging.
- **libplacebo:** `-Dd3d11` is `enabled` on Windows only (`placebo_d3d11`). Patches 0015 and 0016 were taken from upstream via `gh api`, stripped to the diff body like the other 14, and all 16 apply with `patch -p1 --batch --forward --fuzz=0` on the sha256-verified v7.360.1 tarball without regeneration. Pinned count is 16 in deps.sh and UPSTREAM.md.
- **build.sh:** `-Dshaderc/-Dspirv-cross=disabled` moved from the common meson line into the Linux and Darwin arms (same effective flags); MINGW arm enables `d3d11`, `shaderc`, `spirv-cross`. A Windows-only loop requires `HAVE_D3D11`, `HAVE_SHADERC`, `HAVE_SPIRV_CROSS` = 1 in `config.h`; the closing HAVE_ grep prints them.
- **Licensing gate unchanged:** `ffmpeg.sh` and the `package.sh` loop (`--forbid-gpl --forbid-angle` over every DLL) were not touched, so the new DLLs are audited and listed in MANIFEST.txt by construction (to be confirmed by CI).
- **Local pins:** all four new archives were downloaded into separate `build/phase14/dl/<name>/` directories (nothing executed there) and their sha256 written into deps.sh and bundle-spike.txt.

## Task Commits

1. Record feat release run 40498982368 at e8050dd = success (ci-runs.txt, as the user asked) - `5f4bfae`
2. libplacebo 0015/0016 backport pair, count 14 to 16, UPSTREAM.md - `6b0665d`
3. deps.sh/build.sh bundle composition, NOTICE, bundle-spike.txt - `73ce42a`
4. Literal HAVE_ names in the build.sh assertion comment (plan verify greps for `HAVE_SPIRV_CROSS`) - `ea17bcc`

Nothing was pushed; no scratch branch or workflow dispatch.

## Verification (local)

- `bash -n` on deps.sh and build.sh passes; the plan's Task 3 automated grep chain (count 16, SHA256SUMS entries, non-empty patches, `HAVE_SPIRV_CROSS`) passes.
- 16 libplacebo patches apply with fuzz 0 on v7.360.1 (sha256 `14c0a99f...dc39` matched).
- `tools/check_matrix.py` all targets present; `dart run tools/check_consistency.dart` all invariants hold; shared golden-freeze gate prints manifest `golden-freeze-14.sha256` with 5 OK.
- Constants audit: not applicable, no source constants were touched (build scripts, patches and notices only).

## Acceptance items by status

| Item | Status |
|---|---|
| libplacebo 16 patches at fuzz 0 locally | done |
| Pins, scripts, NOTICE, UPSTREAM.md, decision recorded | done |
| Task 1 two-architecture spike, glslang 16.6.0 compatibility, CLANGARM64 | ci-gate: deferred |
| `#define HAVE_D3D11 1` in Windows logs, DLL audit lines, MANIFEST and license check (`final` lines) | ci-gate: deferred |
| 16 patches applied in CI, Linux/macOS release and verify jobs unchanged, PR CI green | ci-gate: deferred |

## Deviations from Plan

**1. [Process] Task 1 spike not run; Task 2 answered up front.** Hosted CI is deferred by user decision (2026-10-27). The scratch spike code is the final code itself (no experimental branches written), and bundle-spike.txt records `blocked target=... reason=...` plus `unknown ci-gate: deferred` lines instead of invented attempt rows. Task 2 was answered `shared` before the spike with the instruction to confirm buildability at the final CI pass.

**2. [Rule 3 - design] shaderc staged install.** The plan said to cmake_build shaderc like the others. shaderc's install step would install its own copy of glslang (optimizer on) into PREFIX over the one libplacebo links statically, so it installs to `$work/shaderc-stage` and only shaderc's files are copied. Files: native/build/deps.sh. Commit: `73ce42a`.

**3. [Process] Commits on feat locally, unpushed.** The plan lands the final form on scratch first, then cherry-picks to feat. With CI deferred, the final form was committed directly on the local feat branch; the user's Task 2 answer exists, so the prohibition on landing before the answer is respected.

## Risks to watch at the CI pass

- shaderc v2026.4 against glslang 16.6.0 and SPIRV-Headers `vulkan-sdk-1.4.363.0` (shaderc DEPS pins e1b562a8 and 04fd3caa): a CMake or API mismatch means switching to `own-glslang`.
- `update_build_version.py` (shaderc `build-version` target) runs git on a non-git source tree; it is expected to degrade, not fail.
- Windows DLL file names (`libspirv-cross-c-shared.dll`, `libshaderc_shared.dll`) are assumed from mingw conventions; package.sh copies whatever ntldd resolves from the prefix.
- 15-01 edits the same build.sh lines (gl/egl move, per-platform feature list) and deps.sh patch count; merge serially, keep exactly one D3D11/SHADERC/SPIRV_CROSS assertion.

## Known Stubs

None.

## Threat Flags

None beyond the plan's register: T-14-09 (pinned sha256, official orgs, tags verified with `gh api`), T-14-10 and T-14-11 rely on unchanged package.sh gates (pending CI confirmation), T-14-SC (no package-manager installs; native-verify's existing MSYS2 shaderc/spirv-cross packages are verify-layer only and untouched).

## Self-Check: PASSED

- Files present: 0015/0016 patches, SHA256SUMS entries, deps.sh `spirv-cross-c-shared` block, build.sh `HAVE_SPIRV_CROSS`, bundle-spike.txt `decision=shared`, NOTICE paragraph.
- Commits 5f4bfae, 6b0665d, 73ce42a, ea17bcc are ancestors of HEAD.

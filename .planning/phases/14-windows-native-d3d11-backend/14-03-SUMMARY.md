---
phase: 14-windows-native-d3d11-backend
plan: 03
subsystem: infra
tags: [angle-ban, pe-audit, ci-gate, windows, build-sh, package-sh]

requires:
  - phase: 14-01
    provides: push authorization (green-plus-scratch) and the parameterised ci_gate.sh
provides:
  - "pe_audit.py --forbid-angle (import table plus ASCII/UTF-16LE byte scan)"
  - "test_pe_audit.py synthetic-PE regression test, run in patch-drift"
  - "ANGLE audit wired into native-verify (libmpv-2.dll), flutter-plugin (plugin DLL), package.sh (every bundle DLL)"
  - "build.sh Windows explicit ANGLE/EGL/WGL-GL off plus config.h assertion"
affects: [14-04, 15-01, 15-04]

actuals:
  tokens: 30000
  tasks: 2
  commits: 6
plan_head_before: fe7184623d1dd5e6ed5facaec46734cd65ad3b20
plan_head_after: e8050ddaedd09923717a070573543f3842be83fc
# commits is the measured count of fe71846..e8050dd. Plan-owned commits are 3
# (ffe2e09, 96792f2, 7d3967f); the other 3 (40caf5a, 2b9f6e2, e8050dd) belong
# to quick task 261027-or3 that unblocked Task 2.

key-files:
  created:
    - tools/rea_abi_audit/test_pe_audit.py
    - .planning/phases/14-windows-native-d3d11-backend/evidence/red-local-14-03-angle-sample.log
  modified:
    - tools/rea_abi_audit/pe_audit.py
    - .github/workflows/native-verify.yml
    - .github/workflows/flutter-plugin.yml
    - native/build/build.sh
    - native/build/package.sh
    - .planning/phases/14-windows-native-d3d11-backend/evidence/ci-runs.txt

key-decisions:
  - "Byte scan lower-cases the file once, so DLL names match case-insensitively in ASCII and UTF-16LE; eglGetPlatformDisplayEXT stays case-sensitive"
  - "build.sh does not repeat -Dgl/-Degl in the MINGW arm (the common line already has them); only the remaining ANGLE/WGL options were added, plus a Windows-only config.h assertion"

requirements-completed: [D3D-02]

ci_gates_passed:
  - gate: "Task 2 PR gate: --jobs-success ^patch-drift ^windows ^build + ANGLE-FREE libmpv-2.dll (both windows jobs) and mpv_kit_video_plugin.dll"
    result: "CI-GATE ok"
    sha: 091228abd70b22fbe2f425fdd1efb75eb8cfcb54
    runs: "native-verify 40627862148, flutter-plugin 40627862039"
  - gate: "Task 2 release gate on feat (windows/linux/macos jobs success, ANGLE-FREE on libmpv-2.dll x64+arm64 and libplacebo)"
    result: "CI-GATE ok (publish skipped by design)"
    sha: b40cdff9262e32f884f4c71b31d3306a4fa37e49
    runs: "release.yml 40618740386"

duration: about 3h (mostly hosted CI waits)
completed: 2026-10-27
status: complete
---

# Phase 14 Plan 03: ANGLE ban gate Summary

**`pe_audit.py --forbid-angle` now fails any DLL that imports libEGL/libGLESv2 or contains `eglGetPlatformDisplayEXT`/those names (ASCII or UTF-16LE), is proven red by synthetic PE samples, and runs on the verify-layer libmpv, the plugin DLL and every Windows bundle DLL, with the Windows build explicitly switching off ANGLE/EGL/WGL-GL.**

## Accomplishments

- `--forbid-angle` is independent of `--forbid-gpl`. All hits are printed (`ANGLE IMPORT:`, `ANGLE REFERENCE:`), any hit exits 1, a clean DLL prints `ANGLE-FREE <path>`.
- `test_pe_audit.py` builds minimal PE32+ samples and runs the audit through `python -I`: four violations (import libEGL, uppercase LIBGLESV2.DLL, ASCII symbol string, UTF-16LE libEGL.dll) exit 1; clean, no-import-directory and near-miss `libEGLfoo.dll` exit 0; the multi sample prints both line kinds. 7 tests pass locally and in the patch-drift job.
- Local red evidence: `evidence/red-local-14-03-angle-sample.log` (violation sample exit=1, clean sample exit=0). The red result was never pushed.
- native-verify windows: explicit `-Dgl/-Degl/-Degl-angle*/-Dgl-win32/-Dgl-dxinterop*=disabled` on the `Build libmpv` line only (shared `MESON_ARGS` untouched), `ABI audit` now `--forbid-gpl --forbid-angle`. flutter-plugin windows: new step audits `mpv_kit_video_plugin.dll` and fails if it is missing; `flutter_windows.dll` is deliberately not audited (ADR 0003).
- `build.sh` MINGW arm adds the explicit ANGLE/WGL options and a Windows-only config.h assertion (no `#define HAVE_<X> 1` for GL, EGL, EGL_ANGLE, EGL_ANGLE_LIB, EGL_ANGLE_WIN32, GL_WIN32, GL_DXINTEROP, GL_DXINTEROP_D3D9). `package.sh` MINGW arm loops over every `$out/lib/*.dll` with `--forbid-gpl --forbid-angle`, no exclusions.

## Task Commits

1. **Task 1: audit rule, test, CI wiring** - `ffe2e09`
2. **Task 2: build.sh / package.sh** - `96792f2`
3. Evidence record of the first failed release scratch run - `7d3967f`

## Verification

- Task 1 (green on feat): scratch `ci/14-angle` native-verify 40472831684 and flutter-plugin 40472837761 success; feat at ffe2e09 native-verify 40474430733 and flutter-plugin 40474430851 success, `CI-GATE ok`, with `ANGLE-FREE` for libmpv-2.dll on both windows jobs and for the plugin DLL.
- Task 2 on scratch: release.yml run 40476764990 at 96792f2 passed windows x64/arm64 (every bundle DLL printed `ANGLE-FREE`, 23 DLLs on x64) and macOS x2, but both Linux jobs failed. After quick task 261027-or3, release.yml run 40487416574 at 40caf5a (96792f2 is an ancestor) was 6/6 green, with `LIBDRM-FLOOR OK` on both linux jobs and `ANGLE-FREE` still printed on Windows.
- feat PR CI after the unblock: native-verify 40492260784 and flutter-plugin 40492260883 at 2b9f6e2 both succeeded.
- ci-gate: deferred (user decision 2026-10-27, run at milestone end). The feat release gate for Task 2 was not run to completion. release.yml was dispatched on feat at e8050dd (run 40498982368); it was not watched or polled and its result is not recorded here.

## Deviations from Plan

**1. [Blocker resolved externally] Linux release build failed at `meson setup`**
- **Found during:** Task 2 scratch dispatch (run 40476764990)
- **Issue:** `native/mpv/meson.build:1011` needs libdrm >= 2.4.114, ubuntu-24.04 has 2.4.113. Unrelated to 14-03's diff; release.yml had not run since before the mpv master rebase.
- **Fix:** none in this plan. Quick task 261027-or3 added patch `0012-drm-build-against-libdrm-2.4.113.patch` and a `LIBDRM-FLOOR` guard in release.yml (40caf5a, 2b9f6e2, e8050dd). This plan resumed afterwards.
- **Files modified by this plan:** none for the fix.

**2. [Process] Task 2 feat gate deferred**
- The user decided to defer all CI gating until every phase is done. The plan's Task 2 verify items 2 and 3 (release.yml gate on feat HEAD, `--jobs-success '.'`) are therefore pending, covered meanwhile by the scratch and PR runs cited above.

**3. [Rule 3] pe_audit docstring/test avoid NUL bytes** - the first edit contained literal NUL characters in a docstring and the `-text` gitattributes made the file binary to git; replaced with `<NUL>` text before committing. No behaviour change.

## Known Stubs

None.

## Threat Flags

None. T-14-06 and T-14-08 are mitigated as planned (regression samples including UTF-16LE, loop over every DLL, no allowlist, no new continue-on-error; `check_matrix.py` clean).

## Notes for later plans

- 15-01 moving `-Dgl/-Degl` into per-OS arms must keep the Windows config.h assertion (or its equivalent) and exactly one `-Dgl=disabled -Degl=disabled` in the MINGW arm.
- 14-04 adds new DLLs (SPIRV-Cross, shaderc); they are automatically covered by the package.sh loop.
- Milestone-end CI run must cover: release.yml on feat with `--jobs-success '^linux \('` and the `ANGLE-FREE` lines for libmpv-2.dll and libplacebo, plus `--jobs-success '.'` for native-verify and flutter-plugin.

## Self-Check: PASSED

- Files present: pe_audit.py (`--forbid-angle`), test_pe_audit.py, red-local-14-03-angle-sample.log, build.sh (`egl-angle-win32=disabled`), package.sh (`--forbid-angle`).
- Commits ffe2e09, 96792f2, 7d3967f are ancestors of HEAD.

## CI backfill (2026-10-28)

The deferred hosted gates were evaluated by this phase's unmodified `tools/ci_gate.sh` against completed runs (PR runs at feat HEAD 091228a: native-verify 40627862148, flutter-plugin 40627862039; release.yml dispatch 40618740386 at b40cdff, valid for the libmpv bundle because b40cdff..091228a only touched the native-verify windows integration step, d3d11_backend.cpp WaitQuery flags, integration tests and notes). A gh shim served the cached logs; nothing was dispatched, rerun or pushed. `--jobs-success .` on release.yml fails literally only on the tag-only `publish` job (skipped by design); all build jobs and every `--log` expectation held. D3D-02: release run 40618740386 printed `ANGLE-FREE` for every Windows bundle DLL (x64 and arm64, including libshaderc_shared.dll and libspirv-cross-c-shared.dll); the native-verify windows jobs print it for libmpv-2.dll and flutter-plugin build (windows) for mpv_kit_video_plugin.dll.
Evidence: `evidence/ci-runs.txt` (backfill block with the raw matched lines)

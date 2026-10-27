---
phase: 15-linux-opengl-backend
plan: 01
subsystem: infra
tags: [linux, opengl, egl, libmpv, build-sh, native-verify, release, render-gl-smoke]

requires:
  - phase: 14-04
    provides: build.sh Windows hunks (d3d11/shaderc/spirv-cross and ANGLE bans), kept untouched
provides:
  - "build.sh Linux arm: -Dgl=enabled -Degl=enabled -Dplain-gl=enabled -Degl-drm=disabled; per-platform required config.h features (Linux adds GL EGL)"
  - "native-verify linux x2 and sanitizers: explicit GL options, epoxy and Mesa EGL packages, CONFIG-GL ok assertion"
  - "release.yml linux: container GL deps, NEEDED audit rejecting X11/xcb/wayland, render_gl_smoke on the packaged bundle"
  - "native/tests/render_gl_smoke.c (gl and gles variants, surfaceless EGL, renderer must be gpu)"
  - "Phase 15 ci_gate.sh copy with CI_GATE_EVIDENCE override; push-authorization.txt and decisions.txt"
affects: [15-02, 15-03, 15-04, 15-05, 15-07]

actuals:
  tokens: 14000
  tasks: 3
  commits: 2
plan_head_before: 442226efa8b799a4aa75e4ccc1ac28b4d41c13dd
plan_head_after: 5c2b060
# commits is measured: 442226e..5c2b060 = 2 (f1ecca0 authorization + gate copy, 5c2b060 build/workflows/smoke test) plus the docs commit below.

key-files:
  created:
    - native/tests/render_gl_smoke.c
    - .planning/phases/15-linux-opengl-backend/tools/ci_gate.sh
    - .planning/phases/15-linux-opengl-backend/evidence/push-authorization.txt
    - .planning/phases/15-linux-opengl-backend/evidence/decisions.txt
    - .planning/phases/15-linux-opengl-backend/evidence/ci-runs.txt
  modified:
    - native/build/build.sh
    - .github/workflows/native-verify.yml
    - .github/workflows/release.yml
    - native/tests/meson.build

key-decisions:
  - "bundle-egl = adopt (user): libmpv.so.2 gets a NEEDED on host libEGL.so.1 (package.sh allowlist, never bundled); GLX-01 text is met as written."
  - "Push authorization = push-green-only+dispatch, effective only at the milestone-end CI pass; no push or dispatch happened during this plan."

requirements-completed: []
requirements-partial: [GLX-01, GLX-02]  # code and gates written locally; Linux build, smoke run and bundle audit are ci-gate: deferred

ci-gate: deferred
deferred_ci_gates:
  - "Task 3 CI gate (after pushing feat HEAD at milestone end): `bash .planning/phases/15-linux-opengl-backend/tools/ci_gate.sh --jobs-success '^linux \\(' --jobs-success '^sanitizers' --jobs-success '^build \\(' --log '^linux \\(ubuntu-24\\.04\\)' 'CONFIG-GL ok' --log '^linux \\(ubuntu-24\\.04\\)' 'RENDER_GL ok api=gl renderer=gpu ' --log '^linux \\(ubuntu-24\\.04\\)' 'RENDER_GL ok api=gles renderer=gpu ' --log '^linux \\(ubuntu-24\\.04-arm\\)' 'RENDER_GL (ok|SKIP)' --log '^sanitizers' 'RENDER_GL ok api=gl '`; then append the `render_gl platform=<x64|arm64> api=<gl|gles> line=<raw line>` records to evidence/ci-runs.txt."
  - "release.yml linux job on the feat ref (`gh workflow run release.yml --ref feat/mpv-master-upgrade`, covered by release_dispatch=yes): package.sh allowlist and ABI audit green with GL/EGL on, `NEEDED libEGL.so.1` printed, no libX11/libxcb/libwayland, `render_gl_smoke gl` on the packaged bundle exits 0 or 77."
  - "Ancestry check of the Task 3 fourth automated verify (authorization commit f1ecca0 must be an ancestor of the first ci-runs.txt `sha=` record) runs once a real record exists."

duration: about 40 min (no hosted CI waits)
completed: 2026-10-28
status: complete
---

# Phase 15 Plan 01: Linux OpenGL render API in the bundle Summary

**The Linux libmpv build now turns on mpv's upstream OpenGL render API (`-Dgl -Degl -Dplain-gl`, x11/wayland still off), asserts it in `config.h`, and a new surfaceless-EGL smoke test (`render_gl_smoke gl|gles`) is wired into native-verify and release; none of it has been built or run on Linux (hosted CI deferred).**

## Accomplishments

- **build.sh:** `-Dgl/-Degl` moved out of the shared `meson setup` line into each platform arm. Linux gets `-Dgl=enabled -Degl=enabled -Dplain-gl=enabled -Degl-drm=disabled` with a comment on why plain-gl is the only switch while x11/wayland are off; Darwin and MINGW keep `-Dgl=disabled -Degl=disabled`. The fixed `VULKAN LIBPLACEBO` loop became `$required_features` (Linux appends `GL EGL`); the closing grep also prints GL/EGL/X11/WAYLAND. The Phase 14 hunks (D3D11, shaderc, spirv-cross, ANGLE bans, config.h D3D assertions) are unchanged apart from one comment reword and the moved `-Dgl/-Degl` line.
- **native-verify.yml:** only `linux` and `sanitizers`: apt adds `libepoxy-dev libegl-mesa0 libgl1-mesa-dri`, the mpv `meson setup` adds the three GL options (global `MESON_ARGS` untouched), and a `CONFIG-GL ok` assertion checks `HAVE_GL`/`HAVE_EGL`.
- **release.yml (linux job only):** container apt adds `libegl-dev libepoxy-dev libegl-mesa0 libgl1-mesa-dri`; `Package and audit` prints `NEEDED <lib>` and fails on libX11/libxcb/libwayland; the packaged-bundle test also runs `render_gl_smoke gl` (exit 77 tolerated like render_vk_smoke).
- **render_gl_smoke.c + meson.build:** EGL_MESA_platform_surfaceless, `gl` (3.3 core, then default) or `gles` (3.0) context, 64x64 RGBA8 FBO, `MPV_RENDER_API_TYPE_OPENGL` with `ADVANCED_CONTROL`, renderer read back through `MPV_RENDER_PARAM_VULKAN_RENDERER` must be `gpu`, centre pixel must be red. Exit 0/1/77 with a `RENDER_GL SKIP:` line before every 77. Linux-only meson block with `render_gl_smoke` and `render_gl_smoke_gles`.
- **Evidence and tooling:** push-authorization.txt, decisions.txt and the ci_gate.sh copy (only line 2 and the `EVIDENCE=` line differ from Phase 12's; verified by sha256 of the remainder).

## Task Commits

1. Task 1/2 records, Phase 15 ci_gate copy - `f1ecca0`
2. Task 3 build.sh, workflows, render_gl_smoke, meson, ci-runs placeholders - `5c2b060`

Nothing was pushed; no workflow was dispatched.

## Local verification

- `bash -n` on build.sh and ci_gate.sh; `tools/check_matrix.py` ok (no new continue-on-error); `tools/check_patches.sh` ok (10 patches); both YAML files parse; golden-freeze manifest `golden-freeze-14.sha256` all OK.
- Plan grep gates pass: one Linux arm GL line, one `-Dgl=disabled -Degl=disabled` each in Darwin and MINGW, `render_gl_smoke_gles` in meson.build, `RENDER_GL ok` in the source, ci_gate copy identical modulo the two lines.
- Commits with `(15-01)` touch none of `packages/`, `native/patches/`, `package.sh`, `tools/rea_abi_audit/`.
- Not done (cannot be, locally): C compile of render_gl_smoke.c (no Linux/epoxy/meson toolchain here), meson configure, any Linux run. Evidence placeholders in ci-runs.txt read `deferred (CI deferral 2026-10-27)`.

## Deviations from Plan

None in behavior. Execution notes: checkpoints 1 and 2 were answered by the user before execution (recorded verbatim in evidence, with the milestone-end-only note); the render_gl_smoke link line also lists the `vulkan` dependency because `render_vk.h` (needed for the renderer query) includes `<vulkan/vulkan.h>`.

## Flagged assumptions (carried from the plan)

- GL behavior is proven only on llvmpipe (software GL); NVIDIA/AMD/Intel drivers stay unverified in this phase.
- The edge probe for GLX-01/GLX-02 stayed `unclassified / unresolved`; no backstop coverage is claimed.

## Known Stubs

None.

## Threat Flags

None beyond the plan's register (new apt packages are from the runner's Ubuntu archive; no new Actions or package-manager installs).

## Self-Check: PASSED

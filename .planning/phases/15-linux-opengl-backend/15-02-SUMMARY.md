---
phase: 15-linux-opengl-backend
plan: 02
subsystem: infra
tags: [linux, opengl, egl, eglimage, spike, render-gl-smoke, release-gate]

requires:
  - phase: 15-01
    provides: render_gl_smoke (render part), ci_gate.sh copy, push-authorization.txt
provides:
  - "render_gl_smoke handoff phase: private texture -> blit -> export texture -> EGLImage -> fence -> cross-thread GLES 2 import; FLIP_Y 0/1 row report"
  - "tools/release_gate.sh (dispatch release.yml on the branch ref, assert linux success / publish skipped / log lines)"
  - "evidence placeholders: spike-gl.txt, ci-runs-15-02.txt, release-runs.txt (all deferred)"
affects: [15-05]

actuals:
  tokens: 11000
  tasks: 3
  commits: 2
plan_head_before: 0206a4d
plan_head_after: 1949f2b

key-files:
  created:
    - .planning/phases/15-linux-opengl-backend/tools/release_gate.sh
    - .planning/phases/15-linux-opengl-backend/evidence/spike-gl.txt
    - .planning/phases/15-linux-opengl-backend/evidence/ci-runs-15-02.txt
    - .planning/phases/15-linux-opengl-backend/evidence/release-runs.txt
  modified:
    - native/tests/render_gl_smoke.c

key-decisions:
  - "Task 2 (D-GL-API / D-FLIP-MPV / D-SYNC and the hard-assertion switch) not started: it is defined as a function of CI log lines and none exist. spike-gl.txt carries deferred placeholders only, so 15-05 cannot silently read a guessed value."

requirements-completed: []
requirements-partial: [GLX-01, GLX-02, GLX-03]

ci-gate: deferred
deferred_ci_gates:
  - "Task 1 (after pushing HEAD at milestone end): `CI_GATE_EVIDENCE=.planning/phases/15-linux-opengl-backend/evidence/ci-runs-15-02.txt bash .planning/phases/15-linux-opengl-backend/tools/ci_gate.sh --jobs-success '^linux \\(' --jobs-success '^sanitizers' --log '^linux \\(ubuntu-24\\.04\\)' 'RENDER_GL ok api=gl renderer=gpu ' --log '^linux \\(ubuntu-24\\.04\\)' 'RENDER_GL ok api=gles renderer=gpu ' --log '^linux \\(ubuntu-24\\.04\\)' 'RENDER_GL ext api=gl ' --log '^linux \\(ubuntu-24\\.04\\)' 'RENDER_GL handoff api=gl flip_y=0 ' --log '^linux \\(ubuntu-24\\.04\\)' 'RENDER_GL handoff api=gl flip_y=1 ' --log '^linux \\(ubuntu-24\\.04\\)' 'RENDER_GL handoff api=gles flip_y=0 ' --log '^linux \\(ubuntu-24\\.04\\)' 'RENDER_GL handoff api=gles flip_y=1 '`; then append the raw `RENDER_GL ext` / `RENDER_GL handoff` lines (x64, arm64, sanitizers) to evidence/ci-runs-15-02.txt as `render_gl_handoff platform=<..> line=<..>`."
  - "Task 2 (after Task 1 evidence exists): write spike-gl.txt from those lines (D-GL-API, D-FLIP-MPV, D-SYNC, EXT-*, ARM64, SANITIZERS), turn the passing variants into hard assertions in render_gl_smoke.c (`RENDER_GL handoff ok api=<variant>`), push, run the plan's two verify commands (spike-gl.txt greps; ci_gate with `RENDER_GL handoff ok api=<first variant>`)."
  - "Task 3 (milestone end, release_dispatch=yes): `bash .planning/phases/15-linux-opengl-backend/tools/release_gate.sh --jobs-success '^linux \\(' --jobs-skipped '^publish' --log '^linux \\(.*linux-x64\\)' 'NEEDED libEGL\\.so\\.1' --log '^linux \\(.*linux-x64\\)' 'packaged [0-9]+ libraries into' --log '^linux \\(.*linux-x64\\)' 'requires GLIBC_2\\.(2[0-9]|3[0-5])([^0-9]|$)' --log '^linux \\(.*linux-x64\\)' 'RENDER_GL ok api=gl renderer=gpu ' --log '^linux \\(.*linux-arm64\\)' 'packaged [0-9]+ libraries into' --log '^linux \\(.*linux-arm64\\)' 'RENDER_GL (ok|SKIP)'`; then append the `release_line target=<..> line=<..>` records to evidence/release-runs.txt."

duration: about 25 min (no hosted CI waits)
completed: 2026-10-28
status: complete
---

# Phase 15 Plan 02: Handoff spike and release-layer proof Summary

**render_gl_smoke now replays the Linux OpenGLBackend's per-frame handoff on one EGL display (blit into an export texture, EGLImage from that texture only, EGL fence, GLES 2 import on another thread with an unshared context) and reports FLIP_Y orientation for a red-over-blue source; release_gate.sh is written. Nothing was compiled or run on Linux and no spike decision exists yet (hosted CI deferred).**

## Accomplishments

- **render_gl_smoke.c (Task 1, code only):** after the unchanged render part and its pixel verdict, a handoff phase prints `RENDER_GL ext api=... egl="..." consumer_oes_egl_image=... gl_version="..."` (the probe runs a GLES 2 consumer thread) and, for FLIP_Y 0 and 1, `RENDER_GL handoff api=... flip_y=... image=... sync=... import=... row0=... last=... fbo_row0=... fbo_last=...`. EGLImage source is only the export texture E; fence wait is bounded to 1 s, the consumer join to 10 s; handoff results never change the exit code except a hang or setup failure. The `RENDER_GL ok` line is unchanged. `fbo_row0/fbo_last` (P's own rows) are an addition to the plan's field list, for reference.
- **release_gate.sh (Task 3, script only):** `gh workflow run release.yml --ref feat/mpv-master-upgrade`, picks the dispatch run by headSha (target or proven descendant), records all job conclusions in release-runs.txt, supports `--jobs-success`, `--jobs-skipped`, `--log`; no tag, `gh release` or rerun.
- **Evidence:** ci-runs-15-02.txt, release-runs.txt, spike-gl.txt hold `deferred (CI deferral 2026-10-27)` placeholders only.

## Task Commits

1. Task 1 handoff phase + ci-runs-15-02 placeholders - `a64894f`
2. Task 3 release_gate.sh + release-runs / spike-gl placeholders - `1949f2b`

Nothing pushed; no workflow dispatched. Task 2 has no commit (see key-decisions).

## Local verification

- `bash -n release_gate.sh` ok; no CR bytes in either edited file; golden-freeze manifest `golden-freeze-14.sha256` all OK.
- Not possible locally: compiling render_gl_smoke.c (no Linux/epoxy/meson toolchain on this host), any run. The code was reviewed by eye for -Wpedantic/werror (declarations before `goto`, `_GNU_SOURCE` guard for `pthread_timedjoin_np`, no non-literal formats); a first Linux compile may still need small fixes.

## Deviations from Plan

None in behavior; Task 2 is not executable without CI evidence and is deferred as a unit. Execution note: the `fbo_row0`/`fbo_last` fields were added to the handoff line.

## Flagged assumptions

- llvmpipe/Mesa software only; NVIDIA/AMD/Intel drivers, Mesa Xe2 EGLImage black frame and Wayland EGL stay unverified (recorded in spike-gl.txt `UNVERIFIED=`).
- 15-05 depends on `D-GL-API=` / `D-FLIP-MPV=` lines that do not exist yet; its precondition will not be satisfiable until milestone-end CI produces them.

## Known Stubs

None (the evidence placeholders are intentional deferral records).

## Threat Flags

None.

## Self-Check: PASSED

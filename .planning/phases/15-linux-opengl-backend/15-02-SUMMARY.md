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

requirements-completed: [GLX-01, GLX-02]  # GLX-02 ticked 2026-10-28 after native-verify run 40632866758 (hard assertions green on x64, arm64, sanitizers)
requirements-partial: [GLX-03]  # GLX-03 needs 15-05..07

ci-gate: "pass 2026-10-28 - Task 1, Task 2 and Task 3 gates all passed (Task 2 hard assertions proven by native-verify run 40632866758 at 893b34f)"
deferred_ci_gates: []  # closed 2026-10-28: the one open gate (hard-assertion CI run) passed, see ci_gates_passed

ci_gates_passed:
  - gate: "Task 1: --jobs-success ^linux ^sanitizers + RENDER_GL ok gl/gles, RENDER_GL ext api=gl, RENDER_GL handoff api=gl|gles flip_y=0|1 (ubuntu-24.04)"
    result: "CI-GATE ok; all four handoff variants image=ok sync=ok import=ok on x64, arm64 and sanitizers"
    sha: 091228abd70b22fbe2f425fdd1efb75eb8cfcb54
    runs: "native-verify 40627862148, flutter-plugin 40627862039"
  - gate: "Task 3: release_gate.sh --jobs-success ^linux ^publish skipped, NEEDED libEGL.so.1, packaged N libraries, requires GLIBC_2.(2x|3[0-5]), RENDER_GL ok api=gl (x64), packaged + RENDER_GL (ok|SKIP) (arm64)"
    result: "RELEASE-GATE ok (release_runs.txt: publish:skipped, linux-x64 + linux-arm64 success, GLIBC_2.35)"
    sha: b40cdff9262e32f884f4c71b31d3306a4fa37e49
    runs: "release.yml 40618740386"
  - gate: "Task 2: hard handoff assertions (52b8a56) run on CI: --jobs-success ^linux ^sanitizers + --log ^linux (ubuntu-24.04) RENDER_GL handoff ok api=gl (and api=gles)"
    result: "`RENDER_GL handoff ok api=gl` and `api=gles` on linux (ubuntu-24.04), linux (ubuntu-24.04-arm) and sanitizers; jobs success"
    sha: 893b34f133de42bbf79bb3f54ce98e78a4eb60f9
    runs: "native-verify 40632866758"

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

## CI backfill (2026-10-28)

Spike values (from run 40627862148, llvmpipe only): D-GL-API=gl,gles; D-FLIP-MPV=row0-top-when-flip_y=0; D-SYNC=fence+client-wait ok. Both variants passed on x64, arm64 and sanitizers, so `native/tests/render_gl_smoke.c` now hard-asserts the row0-top round for both (`RENDER_GL handoff ok api=<variant>`). **That code change has not run on CI yet: it needs one more native-verify run** (15-02 Task 2 second automated check, and the GLX-02 tick).
Evidence: `evidence/ci-runs-15-02.txt, release-runs.txt, spike-gl.txt`. The gates were evaluated by this phase's unmodified `tools/ci_gate.sh` / `tools/release_gate.sh` against completed runs (PR runs at feat HEAD 091228a: native-verify 40627862148, flutter-plugin 40627862039; release.yml dispatch 40618740386 at b40cdff, valid for the linux bundle because b40cdff..091228a only touched the native-verify windows integration step, d3d11_backend.cpp WaitQuery flags, integration tests and notes). A gh shim served the cached logs; nothing was dispatched, rerun or pushed.

## Hard-assertion CI pass (2026-10-28)

native-verify run 40632866758 at sha 893b34f (success; linux x64, linux arm64 and sanitizers jobs success) contains the 52b8a56 change and prints `RENDER_GL handoff ok api=gl` and `RENDER_GL handoff ok api=gles` on all three, next to the unchanged `RENDER_GL ok ... pixel=254,0,0` lines. This closes the open gate above; 15-02 has no open gates. GLX-02 (render_gl_smoke renders non-black pixels on the ubuntu runner, EGL surfaceless plus llvmpipe) is ticked. Scope stays llvmpipe only; real GL drivers remain unverified. Raw lines: `evidence/ci-runs-15-02.txt`.

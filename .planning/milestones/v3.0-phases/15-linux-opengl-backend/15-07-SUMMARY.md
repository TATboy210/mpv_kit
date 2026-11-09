---
phase: 15-linux-opengl-backend
plan: 07
subsystem: docs
tags: [linux, opengl, docs, audit, release-gate, unverified]

requires:
  - phase: 15-06
    provides: Vulkan-unavailable proof, fresh-thread probe
provides:
  - "docs/ARCHITECTURE.md: RunBound row, create-time exception to the render-thread rule, Linux chain table, Linux OpenGL backend section with verification boundary"
  - "README.md / packages/mpv_kit_video/README.md: opengl on Linux, libEGL.so.1, llvmpipe-only note"
  - "evidence/unverified.txt (10 items), evidence/final-audit.txt (GLX-01..04 and SC1..SC4 mapped to run ids), release-runs.txt (release.yml at HEAD)"
affects: []

actuals:
  tokens: 14000
  tasks: 2
  commits: 2
plan_head_before: 7518641d09c131433eb51ffbbf7fce76d89ea9b0
plan_head_after: 5c26e10a363403c0d2387dad29331bb15d7c3055

key-files:
  modified:
    - README.md
    - packages/mpv_kit_video/README.md
    - docs/ARCHITECTURE.md
  created:
    - .planning/phases/15-linux-opengl-backend/evidence/unverified.txt
    - .planning/phases/15-linux-opengl-backend/evidence/final-audit.txt

key-decisions:
  - "Docs state the create-time exception explicitly (prohibition): every mpv_render_* call is on the render thread from the first frame on; create-time calls run in RunBound (helper thread for OpenGL)."
  - "GLX-04 ticked; GLX-03 left pending until the user approves the SC3 wording (its text puts the context on the render thread, which holds only after create)."

requirements-completed: [GLX-04]
requirements-partial: [GLX-03]

ci-gate: passed 2026-10-28 on sha e7bc162 (native-verify 40661093250, flutter-plugin 40661093368, macos-route 40661093429); release.yml run 40662838575 (linux-x64, linux-arm64 success, publish skipped)
status: complete
completed: 2026-10-28
---

# Phase 15 Plan 07: Docs, final audit and unverified list Summary

**Docs now match the code (Linux chain, `opengl` on Linux, `RunBound` thread rules, EGLImage handoff); one full CI gate on HEAD reproduces every Phase 15 key line, and the audit maps GLX-01..04 and SC1..SC4 to run ids with the llvmpipe-only boundary written down.**

## Accomplishments

- **Task 1 (e7bc162):** ARCHITECTURE gets the `RunBound` row, the Linux chain table (identical to `LinuxBackendCandidates`: auto = vulkan/gpu-next, opengl/gpu, vulkan/gpu, software; gpu = opengl/gpu, vulkan/gpu, software; gpuNext = vulkan/gpu-next, software; software = software), a "Linux OpenGL backend" section and the renderer x backend matrix. READMEs: `MPV_KIT_VIDEO_API=opengl` on Linux, libEGL.so.1 (bundle-egl=adopt), Troubleshooting note. Windows/macOS sections untouched except one added clause in the shared threading paragraph. Gate on e7bc162: `CI-GATE ok`; all key lines present (CONFIG-GL, RENDER_GL gl/gles, handoff, LINUX-CHAIN, BIND, forced opengl INTEGRATION and PROBE, Vulkan-unavailable PROBE, both SECOND-CONTROLLER lines). Negatives: `opengl (gpu-next)` 0, `EGL_BAD_ACCESS` 0, `Couldn't open` 0, native `mpv_kit:` lines 0.
- **Task 2 (5c26e10):** audits on HEAD pass (golden-freeze-14 all OK, `CHECK-MATRIX` ok, `CONSTANTS ok`). Build-relevant files changed since b40cdff, so release.yml was dispatched on the branch ref: run 40662838575, linux x64/arm64 success, publish skipped, `NEEDED libEGL.so.1`, `RENDER_GL ok`. final-audit.txt written.

## Requirements

- GLX-01, GLX-02: already ticked. GLX-04: **ticked** (chain proven by LINUX-CHAIN plus real-plugin defaults and the Vulkan-unavailable run; reason never says gpu-next).
- GLX-03: **not ticked.** All gates passed, but its text says the context is on the render thread and the implementation creates mpv's context in `RunBound` on a helper thread (EGL_BAD_ACCESS on the platform thread). Tick it once the user accepts the SC3/GLX-03 wording below; real drivers also remain unverified.

## Proposed SC3 wording (ROADMAP not edited; status pending-user-approval)

"GL context 建在 Flutter 的 EGLDisplay 上、不加入 Flutter share group；渲染线程启动之后的所有 mpv_render_* 调用都在渲染线程上，create 期的调用（mpv_render_context_create、_get_info、首次 _set_update_callback）在 RunBound 的线程上，且两处 mpv 的 context 均为当前；create/dispose 与 resize/dispose soak 中没有 epoxy abort 或 EGL_BAD_ACCESS。"

## Human check (a)-(c)

Pending; the orchestrator asks the user. Not answered by the executor. (b) is moot: D-PROBE=supported, SC2 is "证明" (llvmpipe/xvfb only).

## Deviations from Plan

1. **[Rule 3 - tool] release_gate.sh did not find its own run.** It dispatched run 40662838575 but `find_run` returned exit 4 (`RELEASE-GATE no run`; the local `dispatched_at` clock was ahead of GitHub's `createdAt`, and `RUN_SHA` is set inside a command substitution so it is lost). The gate was evaluated against the finished run with the dispatch line disabled in a scratch copy under /tmp (as done for run 40618740386): `RELEASE-GATE ok`. The record line's empty `sha=` was filled in by hand and the raw `release_line` lines were appended. The tool in the repo was not modified; a fix (compare createdAt with a margin, set RUN_SHA outside the substitution) is left for a later change.
2. **Process:** the first background gate invocation printed nothing and was restarted (no run was dispatched or rerun by it; it never reached the poll).
3. **Docs:** added a clause to the shared threading bullet in ARCHITECTURE (create-time exception) as the prohibition requires; this bullet is common to all platforms.

## Known Stubs

None.

## Self-Check: PASSED

e7bc162 and 5c26e10 are on the branch (e7bc162 pushed; 5c26e10 pushed with the bookkeeping commit); final-audit/unverified/ SUMMARY exist; no CR bytes.

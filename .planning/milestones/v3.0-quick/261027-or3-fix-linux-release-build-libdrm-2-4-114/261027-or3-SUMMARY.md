---
phase: quick-261027-or3
plan: 261027-or3
subsystem: native-build
tags: [libdrm, linux-release, patch-0012, release-ci]
status: complete
requirements: [D3D-02]
commits: 2
plan_head_before: 7d3967fd75cb851ba71c60f483852656f55b4b77
plan_head_after: 2b9f6e2067d7c498b6c83daeed54fde70614d1d8
actuals:
  tokens: 40000
  tasks: 3
  commits: 2
key-files:
  created:
    - native/patches/0012-drm-build-against-libdrm-2.4.113.patch
  modified:
    - native/mpv/meson.build
    - native/mpv/video/out/vo_drm.c
    - native/patches/UPSTREAM.md
    - .github/workflows/release.yml
    - .planning/phases/14-windows-native-d3d11-backend/14-05-PLAN.md
    - .planning/phases/14-windows-native-d3d11-backend/14-06-PLAN.md
    - .planning/phases/14-windows-native-d3d11-backend/14-11-PLAN.md
key-decisions:
  - "Patch number 0012 (0010 reserved for 14-05, 0011 for GLX-F1); count is 9 now, 10 after 14-05."
  - "libdrm is not upgraded in the prefix: libdrm.so.2 has no symbol versioning, so a newer build would leave plain undefined references on 2.4.113 hosts."
---

# Quick 261027-or3: Linux release build against libdrm 2.4.113

Patch 0012 lowers the vendored mpv libdrm floor to 2.4.113 and replaces the three 2.4.114-only dumb-buffer helpers in `vo_drm.c` with static `drmIoctl` shims. The Linux release jobs configure and build again in `ubuntu:22.04`, and a new release.yml guard proves `libmpv.so.2` needs nothing newer than the container libdrm.

## Commits (2)

| Task | Commit | Content |
|---|---|---|
| 1 | 40caf5a | meson.build floor 2.4.113, vo_drm.c shims, patch 0012, UPSTREAM.md record, release.yml LIBDRM-FLOOR step |
| 2 | 2b9f6e2 | PATCH-DRIFT expectations `patches=9` to `patches=10` in 14-05 (6 lines), 14-06 (5), 14-11 (2); 14-05 note; 14-06 replay list adds 0012 |

Task 3 made no commits; it pushed and gated.

## Evidence (all in ci-runs.txt, left uncommitted for the orchestrator)

| Run | Branch | Workflow | SHA | Result |
|---|---|---|---|---|
| 40487416574 | ci/14-libdrm | release.yml (dispatch) | 40caf5a | success; six build jobs success, publish skipped |
| 40490567457 | ci/14-libdrm | native-verify.yml (dispatch) | 2b9f6e2 | success |
| 40490573659 | ci/14-libdrm | flutter-plugin.yml (dispatch) | 2b9f6e2 | success |
| 40492260784 | feat/mpv-master-upgrade (PR #1) | native-verify.yml | 2b9f6e2 | success |
| 40492260883 | feat/mpv-master-upgrade (PR #1) | flutter-plugin.yml | 2b9f6e2 | success |

- Pushed SHA on feat: `2b9f6e2067d7c498b6c83daeed54fde70614d1d8`. The push was a fast-forward `ffe2e09..2b9f6e2` with no force. `origin/feat/mpv-master-upgrade` equals local HEAD and descends from ffe2e09. It carries the previously unpushed 96792f2 and 7d3967f.
- The release-green SHA 40caf5a is an ancestor of HEAD; only `.planning/` files (Task 2) differ after it.
- Both linux jobs in run 40487416574: `Run-time dependency libdrm found: YES 2.4.113`, `ldd -r exit code: 0`, libdrm.so.2 resolved to `/lib/{x86_64,aarch64}-linux-gnu/libdrm.so.2` (outside prefix), the three 2.4.114 helpers are absent from the import list (46 drm* imports, including `drmIoctl`), NEEDED keeps `libdrm.so.2` and `libva-drm.so.2`, and the final line is `LIBDRM-FLOOR OK libdrm=2.4.113 undefined_drm=0`. The Windows ANGLE-FREE line from 14-03 is also present.
- CI patch-drift reports `PATCH-DRIFT OK ... patches=9` on both ci/14-libdrm and feat. Locally: `PATCH-DRIFT OK base=b2c255c13e8e37952dbac6c34da56a690560378b patches=9`.
- release.yml was not dispatched on feat. The 14-03 executor re-runs its own feat gate (including the release dispatch) afterwards.
- `ci/14-libdrm` stays on origin until 14-11 deletes all `ci/14-*`.

## RESEARCH A1 answer

readelf -d of libmpv.so.2 on both architectures prints `FLAGS SYMBOLIC` only; there is no `BIND_NOW` or `FLAGS_1 NOW`. Binding is lazy, so on a libdrm lacking a symbol libmpv would load and abort at the first call rather than failing `dlopen`. The conclusion is unchanged: 0012 removes the references entirely and the guard catches any regression.

## Deviations from Plan

None. The plan executed as written. Notes:
- The first attempt to write the release.yml step through a Python heredoc turned `\n` inside `printf` into literal newlines. I reverted that file with `git checkout -- .github/workflows/release.yml` before any commit and applied the step with the Edit tool. The guard script was then extracted from the YAML and passed `bash -n`.
- During the feat gate the `sanitizers` job sat in `Install dependencies` for about 50 minutes (the earlier run took 2 minutes) and `flutter-video-coverage` took 35 minutes; both finished green without reruns. I judged this slow package mirrors, not a code issue. No infrastructure rerun was used.

## Follow-ups and notes

- Optional: add `-Ddrm=enabled` to the Linux job line only of native-verify.yml (not the shared `MESON_ARGS`), after one scratch run shows it configures. Out of scope here.
- Stale generated patch counts not edited: `.claude/CLAUDE.md:309` ("7 patches") and `.planning/codebase/CONCERNS.md` ("Eight downstream patches"). Archived milestones and docs/perf are historical. The next codebase mapping should refresh them. The inventory grep found no other live hard-coded count outside 14-05, 14-06 and 14-11.
- 0012 must be dropped on the first rebase after the release container ships libdrm >= 2.4.114 (recorded in UPSTREAM.md).

## Threat Flags

None. No new network endpoint, auth path or schema; the only new runtime surface is the `vo_drm.c` ioctl shims, which are equivalent to libdrm 2.4.114's own and sit on a VO that mpv_kit never selects.

## Self-Check: PASSED

- 0012 patch, UPSTREAM.md record, vo_drm.c shims, meson.build floor and release.yml guard all present in 40caf5a; the three plan files changed in 2b9f6e2 (exactly those three paths).
- `git merge-base --is-ancestor` holds for 40caf5a and 2b9f6e2 against HEAD; origin feat equals HEAD.
- `.planning/state.json` is byte-identical to the pre-execution backup (no gsd-tools call was made); no protected file was staged.

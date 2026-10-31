---
phase: 14-windows-native-d3d11-backend
plan: 11
subsystem: testing
tags: [d3d11, vulkan, auto-chain, hud-label, phase-close, ci-gate]

requires:
  - phase: 14-windows-native-d3d11-backend
    provides: 14-09 RTX 4060 evidence, 14-10 GTX 960M laptop evidence (FIFO package 0e792c8)
provides:
  - "D3D-08 decision recorded: keep Vulkan first on Windows auto (not-switched:keep), user reply verbatim in evidence/switch.txt"
  - "HUD backend field and controller startup log print the real graphics API (first token of reason)"
  - "Phase 14 close audit (evidence/final-audit.txt), all items ok, ci/14-* scratch branches deleted"
  - "Todo to publish and pin a bundle that contains the D3D11 backend"
affects: [17-fallback-hardening-uhd-regression]

status: complete
actuals:
  tokens: 7500
  tasks: 2
  commits: 2
plan_head_before: 6bb1b0aaf830c138c41b633f2d5e35b7e9955bb6
plan_head_after: 83107759319182b18c35c3d9dfc4b8d75b73125a

tech-stack:
  added: []
  patterns:
    - "Real graphics API is derived from the first token of MpvVideoController.reason; the frozen two-value enum is never extended"

key-files:
  created:
    - packages/mpv_kit_video/lib/src/backend_api.dart
    - packages/mpv_kit_video/test/backend_api_test.dart
    - .planning/phases/14-windows-native-d3d11-backend/evidence/switch.txt
    - .planning/phases/14-windows-native-d3d11-backend/evidence/final-audit.txt
    - .planning/todos/pending/2026-10-27-pin-a-bundle-with-the-d3d11-backend.md
  modified:
    - example/lib/hud.dart
    - example/test/hud_test.dart
    - packages/mpv_kit_video/lib/src/video_controller.dart
    - README.md
    - packages/mpv_kit_video/README.md
    - docs/adr/0004-render-backend-reporting.md
    - docs/perf/d3d11-backend.md
    - .planning/phases/14-windows-native-d3d11-backend/evidence/ci-runs.txt

key-decisions:
  - "D3D-08 decision=keep (user, 2026-10-29): Windows auto stays vulkan/gpu-next, d3d11/gpu-next, vulkan/gpu, d3d11/gpu, software; no switch commit, no ci/14-switch"
  - "Label fix is a separate small commit before the docs commit; MpvVideoBackend stays {vulkan, software}"

patterns-established:
  - "Phase-close audit: one key=ok|fail line per gate in final-audit.txt, with deliberate exceptions documented next to the line"

requirements-completed: []
requirements-decided:
  - "D3D-08: not-switched:keep (requirement left unchecked by design; the user chose not to switch)"

duration: ~1h30m (mostly hosted CI waits)
completed: 2026-10-29
---

# Phase 14 Plan 11: Windows auto chain decision and phase close Summary

**The user kept Vulkan first on Windows auto (D3D-08 not-switched:keep), the HUD and startup log now show the real graphics API (d3d11/vulkan/opengl/software), and the Phase 14 close audit is all ok with the ci/14-* scratch branches deleted.**

## Performance

- **Duration:** about 1h30m, most of it waiting for hosted CI and the release run
- **Tasks:** Task 1 decision (answered by the user before dispatch), Task 2 skipped by that decision, Task 3 executed, plus the user-approved label fix

## Accomplishments

- Task 1: the user answered the blocking-human decision "keep Vulkan first" and added the power-saving state as a second factor. Recorded verbatim in `evidence/switch.txt` with the GTX 960M basis (package4: auto/Vulkan about 0.5 percent effective drops, forced D3D11 about 3.5 percent). D3D-08 is not switched.
- Task 2 (switch commit, `ci/14-switch`, RTX post-switch checks): not executed, as the plan's precondition says for `keep`. No `rtx-post-switch.log` was created and `d3d11_interop.cpp` is untouched.
- Label fix (approved extra scope, commit `c4768c5`): `example/lib/hud.dart` `hudBackendLabel(reason, fallback)` and `packages/mpv_kit_video/lib/src/backend_api.dart` `backendApiName(reason, fallback)` return the first token of the reason when it is one of `d3d11`, `opengl`, `vulkan`, `software`, otherwise the enum name. The startup print is now `mpv_kit_video: d3d11 (d3d11 (gpu-next) on ...)` for a D3D11 backend. Tests: 2 new cases in `example/test/hud_test.dart`, 2 in the new `packages/mpv_kit_video/test/backend_api_test.dart`.
- Task 3: docs commit `8310775` (README, mpv_kit_video README, ADR 0004 Decision 5, `docs/perf/d3d11-backend.md` decision section and label follow-up), the pin-a-bundle todo, `final-audit.txt`, scratch cleanup.

## Verification

| Check | Result |
|---|---|
| `flutter analyze --fatal-infos` in `packages/mpv_kit_video` and `example` | No issues found |
| `flutter test` in `packages/mpv_kit_video` | 27 tests passed (startup lines show `mpv_kit_video: d3d11 (...)`, `opengl`, `vulkan`) |
| `flutter test` in `example` | 77 tests passed |
| Hosted CI at `8310775` | native-verify 40907376074, flutter-plugin 40907376176 and macos-route 40907376089 all success |
| release.yml dispatch on the same head | run 40907471707 success (6 build jobs success, publish skipped) |
| Close audit | see `evidence/final-audit.txt` (all ok) |

## Task Commits

1. **HUD / startup label fix** - `c4768c5` (fix)
2. **Task 3 docs, decision docs and todo** - `8310775` (docs)

The audit, evidence and planning-state updates ride in the follow-up docs commit that carries this summary.

## Decisions Made

- Keep Vulkan first on Windows auto (user decision, D3D-08 not switched). D3D11 stays as the second choice and as the forced `MPV_KIT_VIDEO_API=d3d11` path. A later switch is a one-line reorder of `kWindowsApiOrder` plus the documentation paragraphs.
- The label fix lives in one tiny internal helper per package instead of changing `MpvVideoBackend` (public API frozen, `enum_line` audit stays 1).

## Deviations from Plan

### Plan-directed adjustments (no auto-fix)

**1. Task 2 skipped by the user's decision.** Plan precondition for `keep`: no switch commit, no `ci/14-switch`, no `rtx-post-switch.log`, `d3d08=not-switched:keep`.

**2. Golden freeze manifest.** `golden-freeze-14-rcc.sha256` (user-approved re-freeze in quick 261029-rcc) was used instead of `golden-freeze-14.sha256`; 5 files OK.

**3. constants audit reports 3 DRIFT lines, recorded `constants=ok` per the orchestrator's rule.** They are the deliberate change of commit `0e792c8` (`kPresentTimeout{50}` removed, ring 5 to 6 as `quarantine_count_ + 2 + kReadyDepth`). `kMaxQuarantine = 4` and `D3D11Interop::CompositorLatency() = 4` are unchanged; every other audited constant matches. The audit script was not edited, so it keeps printing those 3 lines.

### Auto-fixed Issues

**4. [Rule 3 - Blocking] `api_freeze` literal command is not empty.** `git diff --quiet 182a097 HEAD -- packages/mpv_kit/lib packages/mpv_kit/test/api_freeze_test.dart` exits 1 because two Phase 16 commits sit in that range (`8bf1efb` hwdec defaults, `dd75d28` explicit libmpv path). No Phase 14 or quick 261029 commit touches those paths, `api_freeze_test.dart` is unchanged and passes. Recorded `api_freeze=ok` with this explanation rather than silently reinterpreting the command. A strict reading of the plan's wording would call this `fail`; flagged for the verifier.

**5. [Rule 1 - Bug] `dart format` reformatted whole files.** The first attempt formatted three files in the newer style (170 line diff for a label fix). Reverted those three files and reapplied only the intended edits by hand so the commit stays small. The new files are formatted.

**6. Release gate record has an empty `sha=` field** (gate quirk: `RUN_SHA` is assigned in a subshell). The run's `headSha` is `83107759319182b18c35c3d9dfc4b8d75b73125a`, stated in `final-audit.txt`; the evidence line was not rewritten.

## Authentication Gates

None.

## Known Stubs

None. The HUD `compositor` field is still the static `ANGLE (DxgiSharedHandle)` note that existed before this plan (unchanged, out of scope).

## Open Items

- Battery-power laptop run (power-aware GPU preference falling back to `NoPreference`) is still not done (unverified, user will re-test).
- The final `ci_final` gate ran on code head `8310775`; the later commits of this plan touch only `.planning/`.
- A bundle containing the D3D11 backend is not published or pinned (todo `2026-10-27-pin-a-bundle-with-the-d3d11-backend.md`); `bundleTag` stays `v0.1.0-dev.3`.
- Local tag created before quick 261029-rcc stays local (never pushed).

## Self-Check: PASSED

- FOUND: `packages/mpv_kit_video/lib/src/backend_api.dart`, `packages/mpv_kit_video/test/backend_api_test.dart`, `evidence/switch.txt`, `evidence/final-audit.txt`, the pin-a-bundle todo
- FOUND commits `c4768c5`, `8310775` (ancestors of HEAD, pushed to origin/feat/mpv-master-upgrade)
- `git ls-remote --heads origin 'ci/14-*'` is empty

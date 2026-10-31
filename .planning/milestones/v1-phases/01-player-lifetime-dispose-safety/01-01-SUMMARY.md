---
phase: 01-player-lifetime-dispose-safety
plan: 01
subsystem: lifetime
tags: [dispose, stream-closure, ffi, libmpv, teardown, tdd]

requires:
  - phase: none
    provides: "Existing Mpv/Player layers and libmpv-backed test harness"
provides:
  - "Exception-isolated Player.dispose that always reaches mpv_terminate_destroy"
  - "Every Player state stream (incl. position/decodeWarning) emits done"
  - "Mpv.dispose wakeup-callback ordering safe against use-after-free"
  - "Mpv.events and observeProperty streams close on dispose; late listen never enters native code"
  - "Regression tests: throwing dispose hook, Mpv stream closure, late observeProperty listen"
affects: [01-02, 01-03, phase-02-mpv-video-controller]

actuals:
  tokens: 2815
  tasks: 2
  commits: 3

tech-stack:
  added: []
  patterns:
    - "Per-stage teardown isolation: each dispose stage runs in its own guard, errors are collected and surfaced after every stage"
    - "Native teardown ordering: null callback while handle alive -> shutdown bridges -> destroy core -> close NativeCallable"

key-files:
  created: []
  modified:
    - packages/mpv_kit/lib/src/player/player.dart
    - packages/mpv_kit/lib/src/core/mpv.dart
    - packages/mpv_kit/test/player_test.dart
    - packages/mpv_kit/test/mpv_test.dart

key-decisions:
  - "A single collected dispose error is rethrown unchanged; multiple errors are aggregated into a StateError that lists each toString(), so the original hook error stays identity-comparable (same(sentinel))."
  - "position and decodeWarning are registered directly in _states instead of routing them through _bind, because their parsers are custom and neither is observed through the standard path."
  - "_dispatch delivers property values through a parameter-taking helper so the closed-controller guard does not trip the close_sinks lint with a controller-typed local."

patterns-established:
  - "Teardown isolation: no stage may skip a later one; errors surface only after the last stage."
  - "Late-delivery guards: closed StreamControllers are checked before add in both event and property dispatch paths."

requirements-completed: [STAB-01, STAB-02]

coverage:
  - id: D1
    description: "A throwing dispose hook leaves the native core destroyed, every Player state stream closed, the original error surfaced; a second dispose is harmless."
    requirement: STAB-02
    verification:
      - kind: unit
        ref: "packages/mpv_kit/test/player_test.dart#throwing dispose hook still destroys the core and closes all streams"
        status: pass
    human_judgment: false
  - id: D2
    description: "position and decodeWarning controllers are registered in _states and emit done on dispose."
    requirement: STAB-01
    verification:
      - kind: unit
        ref: "packages/mpv_kit/test/player_test.dart#throwing dispose hook still destroys the core and closes all streams"
        status: pass
    human_judgment: false
  - id: D3
    description: "Mpv.dispose orders setWakeupCallback(NULL) before core destruction and closes the NativeCallable after it."
    requirement: STAB-02
    verification:
      - kind: automated_ui
        ref: "awk ordering check over lib/src/core/mpv.dart (s=171 d=177 c=178)"
        status: pass
    human_judgment: false
  - id: D4
    description: "Mpv.events and observeProperty streams emit done on dispose; a stream listened to after dispose emits StateError without native access."
    requirement: STAB-01
    verification:
      - kind: unit
        ref: "packages/mpv_kit/test/mpv_test.dart#dispose closes Mpv.events and observer streams"
        status: pass
      - kind: unit
        ref: "packages/mpv_kit/test/mpv_test.dart#observeProperty stream listened after dispose fails without native access"
        status: pass
    human_judgment: false

duration: 6 min
completed: 2026-10-23
status: complete
plan_head_before: 59e9bdffdd8a49f27deda6a6067fb3507dd83639
plan_head_after: d2c6e8be70ecc9b792febba1324ea6e2cd64e5b2
commits: 3
---

# Phase 01 Plan 01: End-to-end exception-safe dispose Summary

**Player.dispose now destroys the native core and closes every state stream even when a hook throws, and both Mpv stream families close deterministically on dispose.**

## Performance

- **Duration:** 6 min
- **Started:** 2026-10-23T15:44:11Z
- **Completed:** 2026-10-23T15:50:11Z
- **Tasks:** 2 (3 commits: RED / GREEN for the tracer, one for task 2)
- **Files modified:** 4
- **Realized diff:** 147 insertions, 25 deletions (≈2815 tokens at chars/4 — the plan's 52,000-token estimate was high; the change stayed inside the two files the plan named)

## Accomplishments

- `Player.dispose()` is exception-isolated per stage: hooks → subscription cancels → `mpv.dispose()` → controller closes. A throwing hook no longer skips `mpv_terminate_destroy`, and the collected error is rethrown unchanged (single) or as an aggregated `StateError` (multiple) only after every stage ran.
- `position` and `decodeWarning` are now registered in `Player._states`, so `dispose()` and `ShutdownEvent` reach them and both streams emit `done`.
- `MpvState._set` ignores writes after its controller is closed, so a late `ShutdownEvent` cannot throw into the event loop.
- `Mpv.dispose()` nulls the wakeup callback while the handle is alive, shuts down stream bridges, destroys the core, and only then closes the `NativeCallable` — no callback can fire against a freed handle.
- `Mpv.observeProperty` refuses to enter native code when listened to after dispose (delivers `StateError`), and `_dispatch` skips values for already-closed observer controllers.
- New regression tests cover the throwing-hook path, both Mpv stream families, and late listening.

## Task Commits

Each task was committed atomically:

1. **Task 1 (tracer, TDD) RED: add failing test for throwing dispose hook** - `147b42f` (test)
2. **Task 1 (tracer, TDD) GREEN: exception-safe Player.dispose** - `636fdde` (feat)
3. **Task 2: close Mpv event and observer streams deterministically** - `d2c6e8b` (fix)

**Plan metadata:** this SUMMARY commit (docs: complete plan).

## TDD Gate Compliance

| Phase | Commit | Evidence |
|-------|--------|----------|
| RED | `147b42f` | Target test ran and failed on the planned assertion: `Expected: true / Actual: <false>` at `expect(p.mpv.isDisposed, isTrue)`; exit 1; summary "Some tests failed". Semantic assessment: the test executed, the failure is the absent behavior (core not destroyed when a hook throws), not a fixture/compile/zero-test fault. |
| GREEN | `636fdde` | Same target test passes; `dart analyze --fatal-infos` clean; awk ordering check passes (s=171 < d=177 < c=178). |
| REFACTOR | — | No separate refactor commit: the implementation was already minimal after GREEN. |

## Files Created/Modified

- `packages/mpv_kit/lib/src/player/player.dart` — `MpvState._set` closed-guard; `position`/`decodeWarning` registered in `_states`; staged, error-collecting `dispose()`; new `@visibleForTesting stateStreamsForTesting`.
- `packages/mpv_kit/lib/src/core/mpv.dart` — `Mpv.dispose` reorder (wakeup null before destroy, `_wakeup.close()` after destroy); observer-close snapshot; `observeProperty` disposed guard; `_dispatch`/`_addIfOpen` closed-controller guard.
- `packages/mpv_kit/test/player_test.dart` — `throwing dispose hook still destroys the core and closes all streams` (with a leak-guard teardown for failing assertions).
- `packages/mpv_kit/test/mpv_test.dart` — `dispose closes Mpv.events and observer streams`, `observeProperty stream listened after dispose fails without native access`.

## Decisions Made

- Single dispose error is rethrown **unchanged** (identity preserved) so callers can match the original hook error; only multiple errors become a `StateError`. The plan forbade masking the original error, and `same(sentinel)` in the test pins that.
- `position`/`decodeWarning` are added directly to `_states` rather than through `_bind`: their parsers are bespoke and `decodeWarning` has no mpv observation at all.
- The closed-controller delivery guard is factored into `_addIfOpen(controller, value)` so the analyzer's `close_sinks` lint (which flags controller-typed locals that are not closed) stays clean without an `// ignore:`.
- The tracer feedback gate ran in `end-of-phase` mode with automated-only verification: verify was re-run (pass) and execution continued without a synthesized checkpoint, per the precedence chain.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `Mpv.dispose` mutated `_observers` while iterating it**
- **Found during:** Task 1 (RED run teardown)
- **Issue:** `for (final c in _observers.values) unawaited(c.close());` — closing a controller synchronously runs its `onCancel`, which does `_observers.remove(id)`, producing `Concurrent modification during iteration: _Map len:33` inside the dispose path. Any `Mpv.dispose()` with active observers was affected.
- **Fix:** Snapshot the values (`.toList()`) before closing, then clear the map.
- **Files modified:** `packages/mpv_kit/lib/src/core/mpv.dart`
- **Verification:** The RED teardown reproduced it deterministically; both full suites plus the new tests pass afterwards.
- **Committed in:** `636fdde` (Task 1 GREEN)

**2. [Rule 1 - Bug] Analyzer `close_sinks` violation introduced by the guard local**
- **Found during:** Task 2 (`dart analyze --fatal-infos`)
- **Issue:** Binding the observer controller to a local (`final observer = _observers[...]`) then conditionally adding tripped `close_sinks` (the local is never closed in that function).
- **Fix:** Moved the guard into `static void _addIfOpen(StreamController<Object?>?, Object?)`; a parameter is not flagged.
- **Files modified:** `packages/mpv_kit/lib/src/core/mpv.dart`
- **Verification:** `dart analyze --fatal-infos` → "No issues found!".
- **Committed in:** `d2c6e8b` (Task 2)

---

**Total deviations:** 2 auto-fixed (2 Rule 1 bugs)
**Impact on plan:** Both were inside the teardown path this plan owns. No scope creep: no file outside the plan's four was touched, and no public surface was added beyond the planned `@visibleForTesting` seam.

## Issues Encountered

- None beyond the deviations above. The `MPV_KIT_LIBMPV_PATH` precondition held all run (D:/mpv_kit/bt/libmpv-2.dll loads, client API 2.x).

## User Setup Required

None - no external service configuration required.

## Known Stubs

None.

## Threat Flags

None — the changes close trust-boundary gaps (T-01-01 wakeup use-after-free, T-01-02 idempotent dispose, T-01-03 stream closure, T-01-04 hook isolation) and introduce no new surface.

## Verification Results

- `cd packages/mpv_kit && dart analyze --fatal-infos` → No issues found (exit 0).
- `dart test test/player_test.dart -n "throwing dispose hook"` → 1 passed (exit 0); full file 17/17 passed.
- `dart test test/mpv_test.dart` → 19/19 passed (includes both new tests).
- awk ordering check in `<verify>` → s=171, d=177, c=178 (exit 0).
- `git diff --name-only 59e9bdf..HEAD -- packages/` → exactly the four planned files.

## Next Phase Readiness

- The dispose path is now the stable foundation 01-02 (post-dispose `StateError` guards for the whole public `Mpv` surface) and 01-03 (1000-cycle create/dispose soak) build on.
- `Player.stateStreamsForTesting` is the seam 01-02's API-surface guard should enumerate.
- Note for 01-03: repeated create/dispose leaks are still unmeasured; this plan only proves single-dispose closure and exception safety.

---
*Phase: 01-player-lifetime-dispose-safety*
*Completed: 2026-10-23*

## Self-Check: PASSED

- All four modified files exist on disk.
- Commits `147b42f`, `636fdde`, `d2c6e8b` are ancestors of HEAD.
- `commits: 3` measured with `git rev-list --count 59e9bdf..HEAD`.

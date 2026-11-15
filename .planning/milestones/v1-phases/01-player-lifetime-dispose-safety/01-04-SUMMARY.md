---
phase: 01-player-lifetime-dispose-safety
plan: 04
subsystem: lifetime
tags: [dispose, reentrancy, stream-controller, stateerror, lifecycle, gap-closure, tdd]

requires:
  - phase: 01-player-lifetime-dispose-safety
    plan: 01
    provides: "Exception-isolated Player.dispose and deterministic Mpv stream closure on the ordinary path"
  - phase: 01-player-lifetime-dispose-safety
    plan: 02
    provides: "API-freeze test and the post-dispose StateError guard baseline"
provides:
  - "Dispatch-safe Mpv controller close helper (_closeIfOpen) used by both _events and every observer controller"
  - "Reentrant Mpv.dispose() from a synchronous events listener no longer throws and still delivers done"
  - "A Player.audioDevices first read after dispose returns an already-closed state"
  - "The EndFileEvent(error) branch can no longer add to a closed _errors controller"
affects: [phase-02-video-controller, phase-03-observability]

actuals:
  tokens: 1459
  tasks: 2
  commits: 4

tech-stack:
  added: []
  patterns:
    - "Dispatch-safe close: catch StateError from a sync-broadcast controller close and retry once in a microtask"
    - "TDD RED/GREEN commit pairs per task (test(...) then fix(...))"

key-files:
  created: []
  modified:
    - packages/mpv_kit/lib/src/core/mpv.dart
    - packages/mpv_kit/lib/src/player/player.dart
    - packages/mpv_kit/test/mpv_test.dart
    - packages/mpv_kit/test/player_test.dart

key-decisions:
  - "The close helper returns void and only retries once via scheduleMicrotask; dispose() stays synchronous and is not made to await the close."
  - "Only StateError is caught in _closeIfOpen; a broader catch would hide real controller bugs."
  - "audioDevices' _disposed branch closes the state with unawaited(state._close()) and still does not register it in _states, so no post-dispose read starts hotplug monitoring."
  - "The end-file error guard is an isClosed check rather than a try/catch around _errors.add, matching the LogMessageEvent branch."
  - "No new public member: _closeIfOpen is private static, and api_freeze_test.dart still passes."

patterns-established:
  - "Every controller close inside Mpv.dispose routes through one helper; a future controller added to teardown must use the same path."
  - "Lazily created Player states that escape after teardown must close themselves at creation."

requirements-completed: [STAB-01, STAB-02]

coverage:
  - id: D1
    description: "Mpv.dispose() re-entered from a synchronous Mpv.events listener does not throw, delivers done within 5 s, and isDisposed is true; a second dispose is a no-op."
    requirement: STAB-01
    verification:
      - kind: unit
        ref: "packages/mpv_kit/test/mpv_test.dart#dispose from a synchronous events listener closes events without throwing"
        status: pass
    human_judgment: false
  - id: D2
    description: "Mpv._events and every observer controller close through one dispatch-safe helper (_closeIfOpen)."
    requirement: STAB-01
    verification:
      - kind: other
        ref: "grep 'static void _closeIfOpen' && grep '_closeIfOpen(_events)' && grep '_closeIfOpen(c)' packages/mpv_kit/lib/src/core/mpv.dart"
        status: pass
    human_judgment: false
  - id: D3
    description: "A Player's first audioDevices read after dispose returns a state whose stream is already closed and whose value is empty, without registering a new stream."
    requirement: STAB-01
    verification:
      - kind: unit
        ref: "packages/mpv_kit/test/player_test.dart#audioDevices first read after dispose is already closed"
        status: pass
    human_judgment: false
  - id: D4
    description: "The EndFileEvent(reason: error) branch adds to _errors only while it is open."
    requirement: STAB-02
    verification:
      - kind: other
        ref: "grep '_errors.isClosed' packages/mpv_kit/lib/src/player/player.dart"
        status: pass
    human_judgment: true
    rationale: "The branch is unreachable under the current dispose order, so there is no runtime test; the source gate proves the guard exists but not its runtime behavior."
  - id: D5
    description: "The public API surface is unchanged."
    verification:
      - kind: unit
        ref: "packages/mpv_kit/test/api_freeze_test.dart#public API is frozen to the baseline plus the documented seams"
        status: pass
    human_judgment: false

duration: 3 min
completed: 2026-10-24
status: complete
plan_head_before: fce7cc05b8b1222950c09897a4d722df0f232875
plan_head_after: db9cb742fdfdcb074f342d75277b6e956cbf8abc
commits: 4
---

# Phase 01 Plan 04: Reentrant Dispose and Late-State Closure Summary

**Mpv.dispose() is now safe to re-enter from a synchronous events listener: one dispatch-safe close helper serves both the event and observer controllers, a first post-dispose `Player.audioDevices` read is already closed, and the end-file error branch can no longer add to a closed controller.**

## Performance

- **Duration:** 3 min
- **Started:** 2026-10-24T00:29:09Z
- **Completed:** 2026-10-24T00:32:34Z
- **Tasks:** 2 (4 commits: RED/GREEN per task)
- **Files modified:** 4
- **Realized diff:** 76 insertions, 10 deletions (≈1459 tokens at chars/4 — the plan's 46,000-token estimate was far high; both fixes are small, contained edits plus their regression tests)

## TDD Evidence

Both tasks are `tdd="true"`. Each RED was run before the production change and failed on the planned behavior, not on setup or discovery.

**Task 1 RED** — `dart test test/mpv_test.dart -n "dispose from a synchronous events listener"` (before `_closeIfOpen`): the target test failed with `TimeoutException after 0:00:05.000000: Future not completed`. `done` never completed because `_events.close()` threw `StateError` mid-dispatch and the controller stayed open. Commit `ec867fb` (test).
**Task 1 GREEN** — same command after the helper: `+1: All tests passed!`. Commit `a466cbd` (fix).

**Task 2 RED** — `dart test test/player_test.dart -n "audioDevices first read after dispose"` (before the branch close): the target test failed with the same bounded `TimeoutException` because the lazily created `MpvState` was never closed. Commit `5620f8f` (test).
**Task 2 GREEN** — same command after the change: `+1: All tests passed!`. Commit `db9cb74` (fix).

## Accomplishments

- `Mpv._closeIfOpen<T>` is the single close path for `dispose()`: it returns when the controller is already closed, otherwise closes it and, on the `StateError` Dart raises while a sync broadcast controller is firing, retries once in `scheduleMicrotask` after the dispatch unwinds. Both the `_observers` snapshot loop and `_events` route through it; teardown order is unchanged (wakeup nulled → bridges shut down → terminate/destroy → NativeCallable closed → bridges closed → pending futures failed → observers closed → events closed).
- The regression test drives `dispose()` from inside the first `Mpv.events` listener and asserts no error escapes, `done` arrives within 5 s, `isDisposed` is true, and a second `dispose()` is a no-op.
- `Player.audioDevices`' `_disposed` branch now closes its freshly created state before returning it, so a first post-dispose read emits `done` promptly; the state remains outside `_states`, proven by the unchanged `stateStreamsForTesting` length and by the absence of a `_bind` call.
- `Player._onEvent`'s `EndFileEvent(reason: EndFileReason.error)` branch is now guarded by `if (!_errors.isClosed)`, mirroring the `LogMessageEvent` branch, with the same `MpvPlaybackError` field values.
- No public surface changed: `api_freeze_test.dart` passes and `dart analyze --fatal-infos` reports no issues.

## Task Commits

Each task was committed atomically with its TDD pair:

1. **Task 1 (TDD) RED: failing reentrant-dispose regression** - `ec867fb` (test)
2. **Task 1 (TDD) GREEN: dispatch-safe controller closure** - `a466cbd` (fix)
3. **Task 2 (TDD) RED: failing post-dispose audioDevices test** - `5620f8f` (test)
4. **Task 2 (TDD) GREEN: close late state and guard end-file error** - `db9cb74` (fix)

**Plan metadata:** this SUMMARY commit (docs: complete plan).

## Files Created/Modified

- `packages/mpv_kit/lib/src/core/mpv.dart` — private static generic `_closeIfOpen<T>(StreamController<T>)`; `dispose()` routes the observer snapshot loop and the events close through it.
- `packages/mpv_kit/lib/src/player/player.dart` — `audioDevices`' `_disposed` branch calls `unawaited(state._close())`; the end-file error branch is guarded by `!_errors.isClosed`.
- `packages/mpv_kit/test/mpv_test.dart` — `dispose from a synchronous events listener closes events without throwing`.
- `packages/mpv_kit/test/player_test.dart` — `audioDevices first read after dispose is already closed`.

## Decisions Made

- **Synchronous dispose preserved.** The helper returns void and retries in a microtask instead of awaiting the close, keeping `Mpv.dispose()`'s synchronous contract.
- **Narrow catch.** Only `StateError` is caught — the specific error Dart raises for a close during dispatch; anything else still surfaces.
- **Single retry.** The microtask retry closes only when the controller is still open, matching the plan's "single close path allowed to retry".
- **Lazy state stays unregistered.** The post-dispose `audioDevices` state is closed in place rather than added to `_states`, so a post-dispose read cannot start audio-device hotplug monitoring.
- **Guard, not catch.** IN-04 is fixed with an `isClosed` check, consistent with the logs branch and avoiding a broad `try` around `_errors.add`.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None. `MPV_KIT_LIBMPV_PATH` resolved to the real local `D:/mpv_kit/bt/libmpv-2.dll` for every run; no test was skipped or capability-gated.

## Verification Results

- `dart test test/mpv_test.dart -n "dispose from a synchronous events listener"` → 1 passed after the fix; failed with the expected 5 s timeout before it.
- `dart test test/mpv_test.dart` → 22 passed (was 21), including `dispose closes Mpv.events and observer streams` and both late-listen tests.
- `dart test test/player_test.dart` → 18 passed (was 17), including the throwing-hook and disposal tests.
- `dart test test/player_test.dart -n "audioDevices first read after dispose"` → 1 passed after the fix; failed with the expected timeout before it.
- `dart analyze --fatal-infos` → "No issues found!".
- Source gates: `_closeIfOpen` declaration plus both call sites found; `unawaited(state._close())` and `_errors.isClosed` found.
- `dart test test/api_freeze_test.dart` → 1 passed; the public surface is unchanged.
- `git diff --stat fce7cc0..HEAD` → exactly the four planned files.

## Threat Flags

None — the plan implements the registered mitigations T-01-11 (dispatch-safe close + regression test), T-01-12 (post-dispose state closed), and T-01-13 (end-file error guard). No new network, auth, file-access, or schema surface was added.

## Known Stubs

None.

## Next Phase Readiness

- CR-01 (BLOCKER), IN-03 and IN-04 from `01-VERIFICATION.md` / `01-REVIEW.md` are closed; WR-01, WR-02, IN-02 and IN-05 remain deferred to plan 05 as agreed.
- Phase 2 (video controller lifecycle) inherits a teardown path that survives reentrant dispose from a listener, which is the same reentrancy shape a render-context dispose hook can hit.
- The regression tests are live-libmpv tests; no CI wiring change was needed because both files already run in the default suite.

---
*Phase: 01-player-lifetime-dispose-safety*
*Completed: 2026-10-24*

## Self-Check: PASSED

- All four changed files exist on disk.
- Commits `ec867fb`, `a466cbd`, `5620f8f`, `db9cb74` are ancestors of HEAD.
- `commits: 4` measured with `git rev-list --count fce7cc0..HEAD`.

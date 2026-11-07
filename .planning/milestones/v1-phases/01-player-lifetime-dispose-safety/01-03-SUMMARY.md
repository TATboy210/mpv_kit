---
phase: 01-player-lifetime-dispose-safety
plan: 03
subsystem: lifetime
tags: [failure-injection, dispose, stream-bridge, zone-errors, lifecycle, rss, soak, ci, testing]

requires:
  - phase: 01-player-lifetime-dispose-safety
    plan: 01
    provides: "Exception-safe dispose, deterministic stream closure, stateStreamsForTesting seam"
  - phase: 01-player-lifetime-dispose-safety
    plan: 02
    provides: "Post-dispose StateError guards and the API-freeze test"
provides:
  - "Failure-injection suite proving throwing listeners/hooks cannot break delivery or teardown"
  - "Throwing read/seek/close source coverage for all four StreamBridge close paths"
  - "_handleOpen's shutdown branch contains a throwing close, matching shutdown()"
  - "1000-cycle create/dispose soak asserting stream closure and a 64 MiB RSS bound"
  - "Tag-level lifecycle skip isolating the RSS soak; explicit CI invocation for both tags"
affects: [phase-02-video-controller, phase-03-observability]

actuals:
  tokens: 4976
  tasks: 3
  commits: 3

tech-stack:
  added: []
  patterns:
    - "Guarded-zone test helper: listener errors collected by runZonedGuarded, body assertion errors rethrown outside the zone"
    - "Capability-guarded skips: bridge tests skip only on an absent native patch, never on an absent library"
    - "Process-isolated soak: a skipped-by-default test tag is re-enabled only by an explicit --run-skipped invocation"

key-files:
  created:
    - packages/mpv_kit/test/failure_injection_test.dart
    - packages/mpv_kit/test/lifecycle_test.dart
  modified:
    - packages/mpv_kit/lib/src/core/stream_bridge.dart
    - packages/mpv_kit/dart_test.yaml
    - .github/workflows/native-verify.yml

key-decisions:
  - "No production listener counter was added: Dart's synchronous broadcast dispatch already routes a throwing listener to the zone error handler while controller.add returns normally, so the regression coverage is the deliverable, not a new seam."
  - "The guarded-zone helper drives a Completer from the body's completion and rethrows body errors outside the zone; awaiting runZonedGuarded's returned future is not usable because a throwing body leaves that future permanently incomplete."
  - "Bridge-dependent tests skip with an explicit MPV_KIT_STREAM_BRIDGE capability guard (missing patch 0006) and a clear reason; a missing libmpv still fails loudly."
  - "The lifecycle tag carries the default skip in dart_test.yaml, so plain dart test, the coverage step and every platform job leave the soak out; only 'dart test -t lifecycle --run-skipped' runs it, alone, in its own process."
  - "_handleOpen's shutdown branch wraps Future.sync(source.close) in catchError exactly like shutdown(); it is the only production change in this plan."

patterns-established:
  - "Failure-injection tests register listeners inside a guarded zone and await both the delivery signal and the escaped zone error, so ordering between observers cannot flake."
  - "A soak that measures process-wide RSS is excluded by test tag, not by per-command flags."

requirements-completed: [STAB-01, VERIFY-03]

coverage:
  - id: D1
    description: "A throwing observer, events listener or Player-state listener is reported as a zone error while every later listener still receives the value."
    requirement: VERIFY-03
    verification:
      - kind: unit
        ref: "packages/mpv_kit/test/failure_injection_test.dart#throwing observer listener does not stop another observer"
        status: pass
      - kind: unit
        ref: "packages/mpv_kit/test/failure_injection_test.dart#throwing events listener does not stop observers"
        status: pass
      - kind: unit
        ref: "packages/mpv_kit/test/failure_injection_test.dart#throwing Player state listener does not stop other listeners"
        status: pass
    human_judgment: false
  - id: D2
    description: "A throwing dispose hook does not skip later hooks or prevent the native core from being destroyed; the original error is surfaced."
    requirement: VERIFY-03
    verification:
      - kind: unit
        ref: "packages/mpv_kit/test/failure_injection_test.dart#throwing dispose hook does not skip later hooks or the core"
        status: pass
    human_judgment: false
  - id: D3
    description: "Throwing read/seek/close sources are contained: read reports MpvPlaybackError, seek/close leave dispose bounded, and no close error escapes the unawaited _handleOpen path."
    requirement: VERIFY-03
    verification:
      - kind: unit
        ref: "packages/mpv_kit/test/failure_injection_test.dart#a source whose read throws reports an MpvPlaybackError"
        status: unknown
      - kind: unit
        ref: "packages/mpv_kit/test/failure_injection_test.dart#a source whose seek throws leaves the open contained"
        status: unknown
      - kind: unit
        ref: "packages/mpv_kit/test/failure_injection_test.dart#a source whose close throws is contained on every close path"
        status: unknown
    human_judgment: true
    rationale: "The local libmpv is a stock build without patch 0006, so the three bridge tests skip under an explicit capability guard; CI runs the patched build and is their first execution."
  - id: D4
    description: "1000 create/dispose cycles close every Player state stream plus errors and logs, with RSS growth under 64 MiB measured in an isolated invocation."
    requirement: STAB-01
    verification:
      - kind: unit
        ref: "packages/mpv_kit/test/lifecycle_test.dart#1000 create/dispose cycles close every stream and keep RSS bounded (dart test -t lifecycle --run-skipped)"
        status: pass
    human_judgment: false
  - id: D5
    description: "The lifecycle soak is skipped by default and cannot share a process with another suite; both tags are invoked explicitly in the Linux CI Dart-tests step."
    requirement: STAB-01
    verification:
      - kind: other
        ref: "dart test test/lifecycle_test.dart --reporter json | grep '\"skipped\":true'"
        status: pass
      - kind: other
        ref: "grep -q 'dart test -t failure-injection' .github/workflows/native-verify.yml && grep -q 'dart test -t lifecycle --run-skipped' .github/workflows/native-verify.yml"
        status: pass
    human_judgment: false
  - id: D6
    description: "The default package suite gains no new failures: the only failures are the pre-existing environmental stream_bridge_test ones on stock local libmpv."
    verification:
      - kind: unit
        ref: "dart test (mpv_kit): 88 passed, 5 skipped, 5 failed — all 5 in stream_bridge_test.dart from the missing patch 0006"
        status: pass
    human_judgment: false

duration: 5 min
completed: 2026-10-23
status: complete
plan_head_before: efada2e29bb25a053760a1cbb9c5eeda5d114e7c
plan_head_after: 304b83d0571f8143c106e0ed78289762101c1bff
commits: 3
---

# Phase 01 Plan 03: Failure-Injection Coverage and the Isolated Soak Summary

**Throwing listeners, event listeners, state listeners and dispose hooks are proven not to break delivery or teardown; throwing stream I/O is failure-injected on every close path with `_handleOpen` hardened; and a 1000-cycle soak proves stream closure under a 64 MiB RSS tripwire, isolated by a default-skipped tag and wired into CI.**

## Performance

- **Duration:** 5 min
- **Started:** 2026-10-23T16:10:58Z
- **Completed:** 2026-10-23T16:15:44Z
- **Tasks:** 3
- **Files modified:** 5 (2 new tests, 1 production file, 1 test config, 1 CI workflow)
- **Realized diff:** 504 insertions, 1 deletion (≈4976 tokens at chars/4 — far below the plan's 58,000-token estimate; the work was test-authoring inside the planned files)

## Accomplishments

- `failure_injection_test.dart` proves Dart's synchronous broadcast controllers isolate a throwing listener: the error surfaces through the zone's error handler, `controller.add`/`_dispatch` keep draining, and the next listener still receives the value. No `_listenerErrors` counter or third `*ForTesting` seam was added, and the 01-02 `api_freeze_test.dart` still passes.
- A throwing dispose hook is covered end-to-end: the later hook runs, `mpv.isDisposed` is true, and the original sentinel is rethrown unchanged.
- Throwing `read`, `seek` and `close` sources are injected for the stream bridge. The throwing-`read` test expects an `MpvPlaybackError`; `seek`/`close` assert containment and a bounded dispose. The throwing-`close` test covers `_opClose`, the `shutdown()` sweep (also reached via `StreamBridge.close()`), and `_handleOpen`'s shutdown branch after `dispose()` began.
- `StreamBridge._handleOpen`'s shutdown branch now wraps `Future.sync(source.close)` in `catchError`, matching `shutdown()`; a throwing close can no longer escape through `unawaited(_handleOpen(...))`.
- `lifecycle_test.dart` runs 20 warm-up cycles, then 1000 create/dispose cycles, asserting `done` on every state stream plus `errors` and `logs`, and RSS growth below 64 MiB with the measured value in the failure reason. It passed locally in 9 s.
- `dart_test.yaml` declares `failure-injection` and a `lifecycle` tag with a default skip reason. `native-verify.yml` runs both tags explicitly; the soak uses `--run-skipped` in its own invocation.

## Task Commits

Each task was committed atomically:

1. **Task 1: Prove throwing listeners cannot break event delivery** - `fcbc08b` (test)
2. **Task 2: Failure-inject every stream-source I/O method** - `773f73a` (fix)
3. **Task 3: 1000-cycle soak and CI wiring** - `304b83d` (test)

**Plan metadata:** this SUMMARY commit (docs: complete plan).

## Files Created/Modified

- `packages/mpv_kit/test/failure_injection_test.dart` — `@Tags(['failure-injection'])`; `_guarded`/`_waitFor` helpers; four listener/hook tests; three throwing-source tests; `_ThrowingReadSource`, `_ThrowingSeekSource`, `_ThrowingCloseSource`; capability guard.
- `packages/mpv_kit/test/lifecycle_test.dart` — `@Tags(['lifecycle'])`, 5-minute timeout, `_cycle()` stream-closure assertion, and the 1000-cycle RSS test.
- `packages/mpv_kit/lib/src/core/stream_bridge.dart` — `_handleOpen`'s shutdown branch contains `source.close()` errors.
- `packages/mpv_kit/dart_test.yaml` — `failure-injection` and `lifecycle` tags; the latter skipped by default with an explicit reason.
- `.github/workflows/native-verify.yml` — explicit `dart test -t failure-injection` and `dart test -t lifecycle --run-skipped` in the Linux Dart-tests step, with the process-isolation rationale.

## Decisions Made

- **No production listener counter.** The plan's premise was confirmed: sync-broadcast dispatch already isolates listener exceptions, so tests capture the zone error and assert continued delivery instead of adding a seam that would always read zero.
- **Guarded-zone helper instead of awaiting `runZonedGuarded`'s return.** Empirically, when the guarded body throws, `runZonedGuarded<Future<void>>` returns a future that never completes (the error is consumed by the zone). The helper therefore drives a `Completer` from body completion and rethrows body errors outside the zone, so a failed expectation fails the test rather than hanging it.
- **Wait for both signals.** Each listener test waits for the value-delivery signal *and* the escaped sentinel, so observer ordering cannot make them flaky.
- **Capability-guarded skips.** Only a missing native patch (0006) skips; a missing library still throws `MpvLibraryNotFound`. Every skip prints its reason.
- **Tag-level skip is the isolation mechanism.** No `--exclude-tags` or `--concurrency=1` is used anywhere; `dart_test.yaml` is the single source of truth.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Literal `await runZonedGuarded(...)` would hang on a body failure**
- **Found during:** Task 1 (first draft of the guarded helper)
- **Issue:** The plan asked to await the future returned by `runZonedGuarded` so an assertion error inside the guarded body fails the test. A scratch check showed that when the body throws, the returned future never completes (the error is delivered to the zone's `onError` and the future is left incomplete), so a failed expectation inside the body would hang until the test timeout instead of reporting the assertion.
- **Fix:** The helper starts the body inside `runZonedGuarded`, completes a `Completer` from the body's own future (`then`/`onError`), awaits that completer with a 20 s timeout, and rethrows any body error outside the zone. Listener errors continue to go to the zone collector. This preserves the plan's intent while avoiding the hang.
- **Files modified:** `packages/mpv_kit/test/failure_injection_test.dart`
- **Verification:** Scratch reproduction confirmed the hang; the helper passes both routing cases (listener error collected, body assertion rethrown) and all four tests pass.
- **Committed in:** `fcbc08b` (Task 1)

---

**Total deviations:** 1 auto-fixed (1 Rule 3 blocking issue)
**Impact on plan:** Test-harness mechanics only; the injected assertions and the deliverable are exactly as specified. No production behavior changed beyond the planned `_handleOpen` hardening.

## Issues Encountered

- The local `bt/libmpv-2.dll` is a stock build without patch 0006, so `stream_bridge_test.dart` reports its five pre-existing `Unsupported operation` failures and the three new bridge-dependent tests skip with an explicit reason. This is environmental; CI builds the patched libmpv, where those tests execute for the first time.
- The lifecycle soak's local run completed in 9 s with RSS growth well under the 64 MiB bound.

## User Setup Required

None - no external service configuration required. The `MPV_KIT_LIBMPV_PATH` precondition held for every run (`D:/mpv_kit/bt/libmpv-2.dll`).

## Known Stubs

None.

## Threat Flags

None — this plan implements the registered mitigations T-01-07 (listener isolation proven), T-01-08 (all four close paths contained), T-01-09 (1000-cycle soak), and T-01-10 (CI tag invocations). No new network, auth, or file-access surface was introduced.

## Verification Results

- `cd packages/mpv_kit && dart analyze --fatal-infos` → "No issues found!" (exit 0).
- `dart test -t failure-injection test/failure_injection_test.dart` → 4 passed, 3 skipped with the capability reason (exit 0).
- `dart test test/api_freeze_test.dart` → 1 passed; no third `*ForTesting` member was added (exit 0).
- `dart test -t lifecycle test/lifecycle_test.dart --run-skipped` → 1 passed in 9 s (exit 0).
- `dart test test/lifecycle_test.dart --reporter json | grep '"skipped":true'` → one skipped event (exit 0).
- CI grep checks for both explicit tag invocations → exit 0.
- Full default `dart test` → 88 passed, 5 skipped, 5 failed; every failure is the known environmental `stream_bridge_test.dart` one (no new failures; 01-02's baseline was 84 passed / 1 skipped / 5 failed).
- `git diff --stat efada2e..HEAD` → exactly the five planned files.

## Next Phase Readiness

- Failure paths are now continuously verified in CI, so Phase 2 (video controller lifecycle) can build on a proven teardown and dispatch foundation.
- The API-freeze guard still passes, confirming this plan added no public surface.
- The lifecycle test's `stateStreamsForTesting` enumeration is the template for Phase 2's controller create/dispose soak.
- Note for Phase 3 (OBS-01): seek/read error *reporting* is still deferred; this plan only proves containment.

---

*Phase: 01-player-lifetime-dispose-safety*
*Completed: 2026-10-23*

## Self-Check: PASSED

- All five changed files exist on disk.
- Commits `fcbc08b`, `773f73a`, `304b83d` are ancestors of HEAD.
- `commits: 3` measured with `git rev-list --count efada2e..HEAD`.

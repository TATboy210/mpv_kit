---
phase: 01-player-lifetime-dispose-safety
plan: 05
subsystem: testing
tags: [failure-injection, stream-bridge, lifecycle, rss-soak, analyzer-exclude, review-ledger, gap-closure]

requires:
  - phase: 01-player-lifetime-dispose-safety
    plan: 01
    provides: "Exception-isolated Player.dispose and deterministic Mpv stream closure"
  - phase: 01-player-lifetime-dispose-safety
    plan: 03
    provides: "The failure-injection suite, the lifecycle soak, and the lifecycle tag default skip"
  - phase: 01-player-lifetime-dispose-safety
    plan: 04
    provides: "Reentrant dispose fix and the late-state closure that closed CR-01, IN-03, IN-04"
provides:
  - "Failure-injection read/seek tests that cannot pass unless their source method ran"
  - "A seekable in-memory WAV source that makes mpv's demuxer issue a real seek"
  - "A file-scoped lifecycle soak invocation and wording that claims only file-scoped loading"
  - "A configuration-level analyzer exclusion for the VM-only API-freeze test"
  - "A fully dispositioned review ledger: six fixed, four deferred, zero open"
affects: [phase-02-video-controller, phase-03-observability, phase-06-cross-platform]

actuals:
  tokens: 3157
  tasks: 3
  commits: 3

tech-stack:
  added: []
  patterns:
    - "Capability-gated failure tests assert an attempt counter before accepting the contained failure"
    - "In-memory RIFF/WAVE synthesis for a seekable stream source without filesystem I/O"
    - "Analyzer exclusions for VM-only tests live in analysis_options.yaml, never in source"

key-files:
  created: []
  modified:
    - packages/mpv_kit/test/failure_injection_test.dart
    - packages/mpv_kit/test/lifecycle_test.dart
    - packages/mpv_kit/dart_test.yaml
    - packages/mpv_kit/test/api_freeze_test.dart
    - packages/mpv_kit/analysis_options.yaml
    - .github/workflows/native-verify.yml
    - .planning/phases/01-player-lifetime-dispose-safety/01-REVIEW-DISPOSITION.md

key-decisions:
  - "The seek source serves a real in-memory WAV instead of an immediate EOF, so mpv's demuxer issues a seek only after reading container bytes."
  - "Both failure-injection tests assert their attempt counter before accepting containment; a green test can no longer skip the path under test."
  - "The CI soak names test/lifecycle_test.dart; the claimed guarantee is file-scoped loading, not a dedicated process or a solo run."
  - "The API-freeze test is excluded via analyzer.exclude rather than a source-level ignore; dart test still compiles it, so compile errors still fail."
  - "WR-01, WR-02, IN-02 and IN-05 stay deferred with an owner and trigger; none is implemented in this round."

patterns-established:
  - "Every capability-gated source-I/O failure test records how often the injected method ran and asserts it advanced."
  - "Process-wide measurements are only issued from a file-scoped invocation."

requirements-completed: [VERIFY-03, STAB-01]

coverage:
  - id: D1
    description: "The throwing-read test proves the bridge called read (readAttempts > 0) before accepting the MpvPlaybackError."
    requirement: VERIFY-03
    verification:
      - kind: other
        ref: "grep 'source.readAttempts' packages/mpv_kit/test/failure_injection_test.dart"
        status: pass
      - kind: unit
        ref: "packages/mpv_kit/test/failure_injection_test.dart#a source whose read throws reports an MpvPlaybackError"
        status: unknown
    human_judgment: true
    rationale: "The source-I/O test self-skips on the local stock libmpv (no patch 0006); the runtime assertion and the counter advance first execute on the patched CI build."
  - id: D2
    description: "The throwing-seek test serves a seekable in-memory WAV and proves the bridge attempted a seek (seekAttempts > 0)."
    requirement: VERIFY-03
    verification:
      - kind: other
        ref: "grep 'source.seekAttempts' && grep '_silentWavBytes' packages/mpv_kit/test/failure_injection_test.dart"
        status: pass
      - kind: unit
        ref: "packages/mpv_kit/test/failure_injection_test.dart#a source whose seek throws leaves the open contained"
        status: unknown
    human_judgment: true
    rationale: "Capability-gated locally for the same patch-0006 reason; CI is the first environment where the demuxer reads the WAV and _handleSeek runs."
  - id: D3
    description: "The CI soak is file-scoped, the default run still skips it, and no comment claims a dedicated process."
    requirement: STAB-01
    verification:
      - kind: unit
        ref: "dart test test/lifecycle_test.dart -t lifecycle --run-skipped -> 1 passed"
        status: pass
      - kind: other
        ref: "dart test test/lifecycle_test.dart --reporter json | grep -c '\"skipped\":true' -> 1"
        status: pass
    human_judgment: false
  - id: D4
    description: "The VM-only API-freeze test is excluded in analysis_options.yaml, carries no ignore_for_file, and still runs under dart test."
    verification:
      - kind: other
        ref: "grep 'test/api_freeze_test.dart' analysis_options.yaml; grep -c ignore_for_file test/api_freeze_test.dart -> 0"
        status: pass
      - kind: unit
        ref: "packages/mpv_kit/test/api_freeze_test.dart#public API is frozen to the baseline plus the documented seams"
        status: pass
      - kind: other
        ref: "cd packages/mpv_kit && dart analyze --fatal-infos -> No issues found!"
        status: pass
    human_judgment: false
  - id: D5
    description: "Every review finding is dispositioned: six fixed rows and four deferred rows, none open."
    verification:
      - kind: other
        ref: "ledger grep over CR-01 IN-03 IN-04 WR-03 WR-04 IN-01 = fixed and WR-01 WR-02 IN-02 IN-05 = deferred"
        status: pass
    human_judgment: false

duration: 4 min
completed: 2026-10-24
status: complete
plan_head_before: 4d34330a6b957d25fe1b8d4fa2c3649716d042ef
plan_head_after: 70db21fd408bfb248385cade760ad0805f714f03
commits: 3
---

# Phase 01 Plan 05: Verification Strength and Review Ledger Summary

**The phase's proof artifacts now match their claims: the read and seek failure-injection tests prove their source methods ran, the CI soak loads only its own file, the VM-only API-freeze test is excluded in configuration rather than by a six-diagnostic source ignore, and the review ledger has no `open` row left.**

## Performance

- **Duration:** 4 min
- **Started:** 2026-10-24T00:36:58Z
- **Completed:** 2026-10-24T00:40:25Z
- **Tasks:** 3
- **Files modified:** 7
- **Realized diff:** 126 insertions, 61 deletions (≈3157 tokens at chars/4 over the non-planning diff; the plan's 52,000-token estimate was far high)

## Accomplishments

- `_ThrowingReadSource` now counts reads, and the throwing-read test asserts `readAttempts > 0` before it accepts the reported `MpvPlaybackError`; a green test can no longer hide a path that never ran.
- `_ThrowingSeekSource` was rewritten as a seekable in-memory WAV source with `readAttempts`, `seekAttempts` and a position, fed by a new `_silentWavBytes()` helper. The seek test opens without `start`, waits for the demuxer to read, issues the seek, and waits for `seekAttempts > 0` before disposing.
- `.github/workflows/native-verify.yml` now runs `dart test test/lifecycle_test.dart -t lifecycle --run-skipped`; `dart_test.yaml` and the test header state only the file-scoped guarantee, replacing the inaccurate "own process" / "runs alone" claims. The tag default skip, 20 warm-up cycles, 1000 measured cycles, 5-minute timeout and 64 MiB bound are unchanged.
- `analysis_options.yaml` excludes `test/api_freeze_test.dart` under `analyzer.exclude`; the six-diagnostic `ignore_for_file` is gone while `dart test` still compiles and runs the reflection test.
- `01-REVIEW-DISPOSITION.md` now records six `fixed` findings and four `deferred` findings with a reason, cost and owner/trigger each; no row remains `open`.

## Task Commits

Each task was committed atomically:

1. **Task 1: Prove the read and seek failure-injection paths actually run** - `b9400a4` (test)
2. **Task 2: Scope the CI soak to one suite and correct the isolation wording** - `c05727f` (ci)
3. **Task 3: Move the VM-only analysis exclusion and disposition the review ledger** - `70db21f` (chore)

**Plan metadata:** this SUMMARY commit (docs: complete plan).

## Files Created/Modified

- `packages/mpv_kit/test/failure_injection_test.dart` — `readAttempts` on the read source; rewritten `_ThrowingSeekSource` with attempt counters and an in-memory WAV; new `_silentWavBytes`; assertions in both tests.
- `packages/mpv_kit/test/lifecycle_test.dart` — header names the file-scoped soak command and claims only file-scoped loading.
- `packages/mpv_kit/dart_test.yaml` — lifecycle skip reason names the file-scoped command.
- `packages/mpv_kit/analysis_options.yaml` — `analyzer.exclude: [test/api_freeze_test.dart]`.
- `packages/mpv_kit/test/api_freeze_test.dart` — file-level analyzer-ignore removed; header prose updated.
- `.github/workflows/native-verify.yml` — file-scoped lifecycle invocation and corrected comment.
- `.planning/phases/01-player-lifetime-dispose-safety/01-REVIEW-DISPOSITION.md` — six fixed rows, four deferred rows, reasons and owners.

## Decisions Made

- **Seekable data, not EOF.** The seek source serves a real RIFF/WAVE buffer so mpv's demuxer must read container bytes and will issue a seek; an empty read was the reason the old test could pass without `_handleSeek`.
- **Counters are the proof.** Both tests assert the injected method's counter advanced before accepting containment; this directly encodes the plan's transparency prohibition.
- **File-scoped isolation only.** The soak's process-wide RSS measurement is honest only when its suite is the sole loaded suite; the comments now claim exactly that and nothing more.
- **Configuration over source ignores.** A VM-only `dart:mirrors` test is a workspace-resolution problem, so it belongs in `analyzer.exclude`; `dart test` remains the compile gate.
- **Deferrals stay explicit.** WR-01, WR-02, IN-02 and IN-05 are recorded with an owner and trigger rather than silently dropped.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- The three stream-source tests are capability-gated on patch 0006, so the strengthened read/seek assertions cannot execute against the local stock libmpv; they self-skip with an explicit reason, and the source gates plus the suite's exit code are the local proof. The first real execution remains the patched CI build, as the plan anticipated.
- Because task 1 modifies only test code and its runtime path is capability-gated here, a conventional RED/GREEN production pair was not applicable; the RED equivalent is the source gate that would fail if a counter or assertion were missing.

## Verification Results

- `dart test -t failure-injection test/failure_injection_test.dart` → `+4 ~3: All tests passed!` (4 active, 3 explicit patch-0006 skips).
- Task 1 source gates → read/seek counters, both assertions, and `_silentWavBytes` present.
- `dart test test/lifecycle_test.dart -t lifecycle --run-skipped` → `+1: All tests passed!` (8 s); default invocation reports exactly one `"skipped":true`.
- Workflow, wording and over-claim gates → pass; no "in its own process" or "runs alone" remains in the three files.
- `dart analyze --fatal-infos` → "No issues found!".
- `dart test test/api_freeze_test.dart` → 1 passed; `ignore_for_file` count is 0.
- Ledger gate → six `fixed`, four `deferred`, zero `open`.
- Full `dart test` → 90 passed / 5 skipped / 5 failed; all five failures are the pre-existing `stream_bridge_test.dart` patch-0006 failures, matching the documented baseline with no new failure.

## Threat Flags

None — the plan implements the registered mitigations T-01-14 (attempt counters plus seekable source), T-01-15 (file-scoped soak invocation), T-01-16 (`analyzer.exclude`), and T-01-17 (fully dispositioned ledger). No package was installed and no new network, auth, file-access or schema surface was added.

## Known Stubs

None.

## Deferred Findings (recorded, not implemented)

- **WR-01** — a live sub-client handle can block `mpv_terminate_destroy`. Owner/trigger: Phase 2 decides whether it folds into STAB-04/STAB-05, otherwise a dedicated stability insertion on a reported `createClient()` hang.
- **WR-02** — `StreamBridge.shutdown()` may close a source with a read/seek in flight. Owner: Phase 3 (OBS-01), which owns the stream-source contract and error surfacing.
- **IN-02** — `_ensureAlive` guards members that do not touch the handle. Owner: Phase 3 observability, or an explicitly approved API-semantics change.
- **IN-05** — a concurrent second `Player.dispose()` does not await the first. Owner: Phase 2 (STAB-04/STAB-05), where controller dispose concurrency is in scope.

## Next Phase Readiness

- Phase 01's review ledger is closed: the six addressed findings are fixed, and the four deferred findings are visible with owners.
- The failure-injection suite is stronger but its stream-source assertions still need their first real run on the patched CI build; that remains the outstanding environment-limited check.
- No production symbol or public API changed; `dart analyze --fatal-infos` is clean and the default suite baseline is unchanged.

---

*Phase: 01-player-lifetime-dispose-safety*
*Completed: 2026-10-24*

## Self-Check: PASSED

- All seven changed files exist on disk.
- Commits `b9400a4`, `c05727f`, `70db21f` are ancestors of HEAD.
- `commits: 3` measured with `git rev-list --count 4d34330..HEAD`.

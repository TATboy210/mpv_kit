---
phase: 03-error-surfacing
plan: 01
subsystem: stream-bridge
tags: [error-surfacing, stream-source, observability]
requires:
  - phase: 02-02
    provides: "Player.errors contract ownership and the failure-injection harness"
provides:
  - "Stream-source open/read/seek/close failures surface on Player.errors with the original exception type and message embedded in MpvPlaybackError.message"
  - "Seek failures (including mpv's seekability probe) surface without ending playback; open/read keep ending playback with an explicit error"
  - "MpvStreamSource contract amended: close may arrive while open/read/seek is pending (WR-02 fixed-by-contract)"
affects: [03-02, phase-6-cross-platform-verification]
actuals:
  tokens: 62000
  tasks: 2
  commits: 1
tech-stack:
  added: []
  patterns:
    - "Report-and-continue: swallows keep their mpv-facing codes byte-for-byte while the original exception travels a side channel"
    - "Late-bound sink: Player installs Mpv.onSourceError in its constructor; bridges capture the field at register time"
key-files:
  created: []
  modified:
    - packages/mpv_kit/lib/src/core/stream_bridge.dart
    - packages/mpv_kit/lib/src/core/mpv.dart
    - packages/mpv_kit/lib/src/player/player.dart
    - packages/mpv_kit/test/failure_injection_test.dart
    - packages/mpv_kit/test/api_freeze_test.dart
key-decisions:
  - "Mpv.onSourceError is a public field (freeze baseline +1) rather than a Mpv.create parameter: Player.wrap must route too, and each Mpv carries its own sink for multi-player safety"
  - "A seek failure surfaces but does not end playback — mpv treats seeks as transiently failable; only open/read failures terminate playback"
  - "Source-level and playback-level entries coexist on Player.errors for open/read failures (two entries); correlation is intentionally left to the message text"
patterns-established:
  - "Probe-seek awareness: the demuxer's seekability probe consumes the first seek failure, so collectors must subscribe before open"
requirements-completed: [OBS-01]
coverage:
  - id: D1
    description: "Open failure surfaces original identity (StateError/open boom) + playback-level end-file entry"
    requirement: OBS-01
    verification:
      - kind: unit
        ref: "packages/mpv_kit/test/failure_injection_test.dart#a source whose open throws surfaces the original error on Player.errors"
        status: pass
    human_judgment: false
  - id: D2
    description: "Read failure surfaces original identity; playback ends with explicit error (Phase 1 semantics intact)"
    requirement: OBS-01
    verification:
      - kind: unit
        ref: "packages/mpv_kit/test/failure_injection_test.dart#a source whose read throws reports an MpvPlaybackError"
        status: pass
    human_judgment: false
  - id: D3
    description: "Seek failure surfaces original identity and does not end playback (no loadingFailed entry)"
    requirement: OBS-01
    verification:
      - kind: unit
        ref: "packages/mpv_kit/test/failure_injection_test.dart#a source whose seek throws leaves the open contained"
        status: pass
    human_judgment: false
  - id: D4
    description: "Close failures contained on every path; the shutdown-sweep failure stays observable before the errors stream closes"
    requirement: OBS-01
    verification:
      - kind: unit
        ref: "packages/mpv_kit/test/failure_injection_test.dart#a source whose close throws is contained on every close path + #a close failure during dispose is reported before the stream closes"
        status: pass
    human_judgment: false
duration: 26 min
completed: 2026-10-24
status: complete
plan_head_before: 06e5718
plan_head_after: 0b934f6
commits: 1
---

# Phase 03 Plan 01: Stream Source Error Surfacing Summary

**Stream source failures are now observable on `Player.errors` with the original exception identity; demuxer semantics are byte-for-byte unchanged; the WR-02 contract is written down.**

## Performance

- Duration: 26 min (RED → GREEN per task, one atomic commit)
- Tasks: 2/2; Commits: 1
- Token estimate 56000 vs realized ~62000

## Accomplishments

- `StreamBridge._report` helper routes all five swallow sites (open, read, seek×2 arms, opClose, shutdown sweep, open-in-flight close) through `onSourceError` with consumer-failure containment.
- `Mpv.onSourceError` public field (freeze baseline +1, documented); `Player` installs its sink in the constructor and maps reports to `MpvPlaybackError` (`stream source <op> failed: <runtimeType>: <error>`).
- `MpvStreamSource` doc contract amended (WR-02): concurrent close is legal; implementations own their future completion.
- 5 new/extended failure-injection tests (9 total in the suite, all passing).

## Task Commits

1. `0b934f6` — feat(player): stream source failures surface on Player.errors with original identity (OBS-01)

## TDD Gate Compliance

| Task | RED evidence | GREEN evidence |
|------|--------------|----------------|
| Report chain | `_TypeError`/missing entries; seek test timeout exposed the probe-seek ordering | `+9: All tests passed!` |
| Teardown reporting | close-failure entry absent before stream close | suite green |

## Files Created/Modified

- Modified: `stream_bridge.dart`, `mpv.dart`, `player.dart`, `failure_injection_test.dart`, `api_freeze_test.dart`.

## Decisions Made

- Public field over create-parameter (multi-player + `Player.wrap` routing; see key-decisions).
- Null opener results are not errors; only genuine throws report.

## Deviations from Plan

1. `[Rule 1 - Probe semantics]` Found during: task 1 GREEN. Issue: the read test assumed `errors.first` was the read entry, but the demuxer's seekability probe now surfaces first; the seek test initially subscribed after the explicit seek, missing the probe-seek report. Fix: collectors subscribe before `open`, wait for the specific entry. Verification: suite green. Committed in: `0b934f6`.

## Issues Encountered

- None.

## User Setup Required

- None.

## Known Stubs

- None.

## Threat Flags

- T-03-01…04 mitigated; T-03-SC not triggered.

## Verification Results

- `dart test` (mpv_kit, real libmpv) → 103 passed / 2 skipped at commit time.
- `dart analyze --fatal-infos` clean; `api_freeze_test` passes with the documented `onSourceError` baseline entry.

## Next Phase Readiness

- 03-02 extends the same `Player.errors` payload to observation/parse failures.

## Self-Check: PASSED

- Artifacts exist; commit `0b934f6` is an ancestor of HEAD; commit count measured.

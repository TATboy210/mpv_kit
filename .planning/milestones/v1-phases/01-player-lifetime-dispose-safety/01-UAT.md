---
status: complete
phase: 01-player-lifetime-dispose-safety
source: [01-VERIFICATION.md]
started: 2026-10-24T01:20:00Z
updated: 2026-10-24T02:05:00Z
---

## Current Test

[testing complete]

## Tests

### 1. Throwing-read stream source surfaces an MpvPlaybackError
expected: |
  `a source whose read throws reports an MpvPlaybackError` passes with `readAttempts > 0`,
  a non-empty `Player.errors` message, and dispose ≤ 10 s.
result: pass
evidence: |
  `PATH=/d/mpv_kit/bt:$PATH MPV_KIT_LIBMPV_PATH=D:/mpv_kit/bt/libmpv-2.dll dart test -t failure-injection test/failure_injection_test.dart`
  → `+7: All tests passed!` (previously 4 passed / 3 skipped).
  The original premise — that the local libmpv lacks patch 0006 — was wrong. `bt/libmpv-2.dll`
  exports `mpv_kit_stream_add` (`tools/rea_abi_audit/pe_audit.py --dump`). It was silently
  failing to load because its dependency DLLs are not on the process search path, and
  `MpvLibrary.open()` fell back to a stock library found on PATH.

### 2. Throwing-seek stream source leaves the open contained
expected: |
  `a source whose seek throws leaves the open contained` passes with `seekAttempts > 0`,
  no uncaught error, and dispose ≤ 10 s.
result: pass
evidence: |
  Same run as test 1 — the seek test reports passed rather than skipped.
  GC-IN-02 still stands as a weaker sub-claim: `seekAttempts` can be satisfied by mpv's
  post-probe refresh seek, so this proves containment and that `_handleSeek` ran, not that the
  explicit `player.seek()` reached the demuxer.

### 3. Throwing-close stream source is contained on every close path
expected: |
  `a source whose close throws is contained on every close path` passes: both zone-error lists
  are empty, `closeAttempts > 0`, dispose ≤ 10 s.
result: pass
evidence: |
  Same run as test 1 — the close-path test reports passed rather than skipped.

### 4. Both explicit commands execute their tests rather than silently skipping
expected: |
  `dart test -t failure-injection` and
  `dart test test/lifecycle_test.dart -t lifecycle --run-skipped` both exit 0, and the three
  stream-source tests report as passed rather than skipped; lifecycle reports `1 passed`.
result: pass
evidence: |
  Both commands were executed against the patched library:
  failure-injection → 7 passed / 0 skipped; lifecycle soak → `1 passed` (5–8 s).
  Full default suite with the same library resolves to **98 passed / 2 skipped / 0 failed**;
  the two remaining skips are by design (the `lifecycle` tag default, and
  `MPV_KIT_FORMAT_SAMPLES` being unset).
  Scope note: this is local evidence, not a CI observation. Observing the same commands on
  real CI runners belongs to Phase 6 (VERIFY-01 / VERIFY-02) and is not claimed here.

## Summary

total: 4
passed: 4
issues: 0
pending: 0
skipped: 0
blocked: 0

## Gaps

None. Two observations recorded outside the phase's must-haves:

- `MpvLibrary.open()` silently falls back to a platform-default library when the explicitly
  requested `MPV_KIT_LIBMPV_PATH` fails to load, so a caller cannot tell which libmpv it got.
  This is the "failure silently swallowed" class owned by Phase 3 (OBS-04), and it is what made
  three locally-runnable truths look environment-blocked for the whole phase.
- The phase's stated environment baseline ("5 pre-existing `stream_bridge_test.dart` failures
  caused by missing patch 0006") was incorrect. With the dependency search path fixed the full
  suite is green; no test is blocked by a missing patch on this machine.

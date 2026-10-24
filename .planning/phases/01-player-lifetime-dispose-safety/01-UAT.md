---
status: testing
phase: 01-player-lifetime-dispose-safety
source: [01-VERIFICATION.md]
started: 2026-10-24T01:20:00Z
updated: 2026-10-24T01:20:00Z
---

## Current Test

number: 1
name: Throwing-read stream source surfaces an MpvPlaybackError
expected: |
  4 listener/hook tests still pass; `a source whose read throws reports an MpvPlaybackError`
  passes with `readAttempts > 0`, `Player.errors` receives a non-empty message, and dispose
  completes within 10 s.
awaiting: user response

## Tests

### 1. Throwing-read stream source surfaces an MpvPlaybackError
expected: |
  On a patched libmpv (one exporting `mpv_kit_stream_add`), run
  `cd packages/mpv_kit && MPV_KIT_LIBMPV_PATH=<patched> dart test -t failure-injection test/failure_injection_test.dart`.
  The 4 listener/hook tests still pass; `a source whose read throws reports an MpvPlaybackError`
  passes with `readAttempts > 0`, a non-empty `Player.errors` message, and dispose ≤ 10 s.
why_human: |
  The local stock libmpv lacks native patch 0006, so the suite self-skips this test with an
  explicit reason. This is an environment limit, not a missing implementation.
result: [pending]

### 2. Throwing-seek stream source leaves the open contained
expected: |
  Same patched environment. `a source whose seek throws leaves the open contained` passes with
  `seekAttempts > 0`, no uncaught error, and dispose ≤ 10 s.
why_human: |
  Same environment gate. Additionally, GC-IN-02 notes that `seekAttempts` can be satisfied by
  mpv's post-probe refresh seek; to prove the *explicit* seek reached the demuxer, issue
  `player.mpv.command(['drop-buffers'])` first or use a WAV large enough that the target falls
  outside the 32 KiB lavf AVIO window, and await the seek future.
result: [pending]

### 3. Throwing-close stream source is contained on every close path
expected: |
  Same patched environment. `a source whose close throws is contained on every close path`
  passes: both zone-error lists are empty, `closeAttempts > 0`, dispose ≤ 10 s.
why_human: |
  Same environment gate. The four close-path call sites can only be exercised at runtime with
  the patched native library.
result: [pending]

### 4. CI runs both explicit tag invocations for real
expected: |
  In the Linux Dart-tests step of `.github/workflows/native-verify.yml`, observe the exit codes
  and reporter output of `dart test -t failure-injection` and
  `dart test test/lifecycle_test.dart -t lifecycle --run-skipped`. Both exit 0; the three
  stream-source failure-injection tests report as passed rather than skipped; lifecycle reports
  `1 passed`.
why_human: |
  CI is the first real execution environment for these environment-gated tests and cannot be
  reproduced locally. Note: `--run-skipped` is load-bearing — without it the lifecycle command
  reports "All tests skipped" and exits 0.
result: [pending]

## Summary

total: 4
passed: 0
issues: 0
pending: 4
skipped: 0
blocked: 0

## Gaps

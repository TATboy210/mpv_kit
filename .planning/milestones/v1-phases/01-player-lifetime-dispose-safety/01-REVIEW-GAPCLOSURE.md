---
phase: 01-player-lifetime-dispose-safety
reviewed: 2026-10-24T01:00:52Z
depth: standard
files_reviewed: 10
files_reviewed_list:
  - .github/workflows/native-verify.yml
  - packages/mpv_kit/analysis_options.yaml
  - packages/mpv_kit/dart_test.yaml
  - packages/mpv_kit/lib/src/core/mpv.dart
  - packages/mpv_kit/lib/src/player/player.dart
  - packages/mpv_kit/test/api_freeze_test.dart
  - packages/mpv_kit/test/failure_injection_test.dart
  - packages/mpv_kit/test/lifecycle_test.dart
  - packages/mpv_kit/test/mpv_test.dart
  - packages/mpv_kit/test/player_test.dart
findings:
  critical: 0
  warning: 2
  info: 4
  total: 6
status: issues_found
---

# Phase 01: Code Review Report (Gap Closure: plans 01-04 / 01-05)

**Reviewed:** 2026-10-24T01:00:52Z
**Depth:** standard
**Scope:** `bf98a54..HEAD` — the gap-closure changes from plans 01-04 and 01-05
**Files Reviewed:** 10
**Status:** issues_found

## Summary

The two production fixes in this range are correct and I could not break them:

- `Mpv._closeIfOpen` is a genuine fix. I reproduced the underlying Dart behaviour outside the
  project: a `StreamController.broadcast(sync: true)` whose listener calls `close()` throws
  `StateError("Cannot fire new event. Controller is already firing an event")` and leaves
  `isClosed == false`, and `done` is never delivered. The microtask retry then closes the
  controller and delivers `done`. The new regression test in `mpv_test.dart:300-322` is a real
  RED/GREEN test — the `done` completer can only complete through the retry branch, so the test
  cannot pass without exercising it. (Ran it locally: passes in ~40 ms.)
- The `Player.audioDevices` post-dispose branch closes the lazily created state in place and never
  registers it in `_states`, so there is no leak and no double close (a *pre*-dispose first read
  still goes through `_bind` and is closed exactly once by `dispose`). The new test
  (`player_test.dart:260-272`) exercises the branch: without the fix the `done` completer times
  out. (Ran it locally: passes.)
- The `_errors.isClosed` guard mirrors the adjacent `_logs` branch and cannot suppress errors
  during normal operation (the controller is closed only in `Player.dispose`, after `_subs` are
  cancelled). No ordering hole was found: `_dispatch` notifies `_observers` before `_events.add`,
  so a reentrant `dispose()` from an observer listener closes `_events` before the event is
  published, and the `if (!_events.isClosed)` check at `mpv.dart:664` already covers that path.
- No change weakens the patch-0006 capability gate: `_streamBridgeAvailable` and
  `_skipWithoutStreamBridge` are untouched, and both new assertions sit behind that gate.

Verification performed locally (not just read): `dart analyze --fatal-infos` in
`packages/mpv_kit` → clean; `api_freeze_test.dart` → pass; the two new RED/GREEN tests → pass;
`dart test -t failure-injection` → 4 passed / 3 expected patch-0006 skips; the file-scoped soak
command from CI (`dart test test/lifecycle_test.dart -t lifecycle --run-skipped`) → 1 passed in
8 s; and an instrumented mpv run to trace the seek path used by the new seek test (see IN-02).

The remaining findings are verification-strength and maintainability defects, not runtime bugs.

## Warnings

### WR-01: CI comment claims a skipped run fails the job; a skipped run actually exits 0

**File:** `.github/workflows/native-verify.yml:87-95`
**Issue:** The new comment ends with "A skipped or uncollected run exits non-zero and fails this
job instead of passing silently." Half of that is false, and it is the half the comment relies on:

```
$ dart test test/lifecycle_test.dart -t lifecycle
  Skip: RSS soak: run explicitly with dart test test/lifecycle_test.dart -t lifecycle --run-skipped
  00:00 +0 ~1: All tests skipped.
  EXIT=0
```

For comparison, an uncollected run does exit non-zero (wrong path → exit 1; non-matching tag →
exit 79), so only the "skipped" clause is wrong. The practical consequence: the soak's execution
today depends entirely on `--run-skipped` continuing to be present. If that flag is dropped in a
future edit — exactly the edit this comment is meant to protect against — CI stays green while the
soak never runs, and nothing in the job notices. That is the "passing silently" failure the
comment says cannot happen.
**Fix:** Either narrow the claim, or make the job enforce it, e.g.:

```yaml
dart test test/lifecycle_test.dart -t lifecycle --run-skipped --reporter=expanded \
  | tee soak.log
grep -q 'All tests passed' soak.log   # fails if the run was skipped or collected nothing
```

or simply reword to "an uncollected run exits non-zero; a skipped run exits 0, which is why
`--run-skipped` is required here."

### WR-02: The API-freeze test compares names only and skips every constructor, so signature changes are not detected

**File:** `packages/mpv_kit/test/api_freeze_test.dart:17-25` (`publicMembers`), `:164-186` (the test)
**Issue:** `publicMembers` returns `MirrorSystem.getName(declaration.simpleName)` and explicitly
drops constructors (`declaration is! MethodMirror || !declaration.isConstructor`). The baseline is
a `Set<String>`, so the freeze covers *names* only. Consequences:

- Constructor signatures are entirely outside the guard: `Mpv.create`, `Player` (the unnamed
  factory) and `Player.wrap` are all constructors and therefore appear in neither `_baseline` nor
  `_seams`. Reordering, renaming, or adding a required parameter to any of them passes the test.
- Method signatures are likewise unchecked: changing `Player.open(String url, …)` to
  `Player.open(Uri url, …)`, or adding a required parameter to `seek`, passes.

The header says "the reflected public surface of `Mpv` and `Player` must stay at the pre-phase
baseline", but the phase constraint is "no new/changed public members" — a changed member is not
detected. This weakness predates the gap closure (it is not introduced by 01-04/01-05), but the
gap closure is the last chance to fix it while the phase owns this file, and the only *static*
check on the file is now gone (see IN-03), so the runtime test is the sole enforcement point.
**Fix:** Reflect constructors and parameter/return type strings into the baseline, e.g. build the
key from the declaration plus its signature and include constructors:

```dart
String describe(DeclarationMirror d) {
  final name = MirrorSystem.getName(d.simpleName);
  if (d is MethodMirror) {
    final params = d.parameters.map((p) => MirrorSystem.getName(p.simpleName)).join(',');
    return '${d.isConstructor ? 'ctor:' : ''}$name($params)->${d.returnType}';
  }
  return name;
}
```

and rebaseline once. At minimum, add `Mpv.create`, `Player`, and `Player.wrap` signatures to an
explicit expectation.

## Info

### IN-01: The microtask retry in `_closeIfOpen` is itself unguarded if it ever finds a firing controller

**File:** `packages/mpv_kit/lib/src/core/mpv.dart:683-692`
**Issue:** The retry body calls `unawaited(controller.close())` with no `try`. If the retry ever runs
while the controller is still firing (only reachable if a caller/zone runs the scheduled callback
inline — e.g. a zone whose `scheduleMicrotask` executes synchronously — or if a future teardown path
calls `_closeIfOpen` re-entrantly from a second synchronous dispatch), the `StateError` becomes an
uncaught zone error and the controller stays open, so `done` is never delivered. That is exactly the
failure the helper exists to prevent, merely moved one tick later. Under the standard event loop the
scenario is unreachable, because microtasks drain only after the synchronous dispatch has unwound;
the doc comment ("retry once on the next microtask, after the dispatch has unwound") states that
assumption but the code does not enforce it.
**Fix:** Make the retry total, e.g.:

```dart
scheduleMicrotask(() {
  if (controller.isClosed) return;
  try {
    unawaited(controller.close());
  } on StateError {
    // Still firing: give up rather than leak an uncaught zone error.
  }
});
```

or assert/document the precondition explicitly.

### IN-02: The seek test's `seekAttempts` can be satisfied by mpv's startup refresh seek, not by the explicit seek

**File:** `packages/mpv_kit/test/failure_injection_test.dart:365-392`
**Issue:** The comment claims that because the test opens without `start`, "the seek is issued
explicitly after the demuxer has read the WAV, so the bridge's seek handler is provably reached."
Instrumenting mpv against an equivalent local WAV (trace log) shows the handler is reached earlier:
after `avformat_find_stream_info()` finishes (having consumed all 48,044 bytes),
mpv performs a startup refresh seek:

```
refresh seek to 0.000000
execute seek (to 0.000000 flags 32)
using bullshit libavformat PCM seek hack
seek request from 48044 to 44
seek done
```

That stream-level seek calls the source's `seek()` (which throws in `_ThrowingSeekSource`), so
`seekAttempts` is already > 0 by the time `player.seek(2 s)` is issued. The assertion therefore
proves the bridge's seek handler is reached and that its throw is contained — which is the test's
stated contract — but it does **not** prove the explicit user seek reached the demuxer; the explicit
seek can also be served from the 32 KiB lavf AVIO buffer (`native/mpv/demux/demux_lavf.c:70`) after
the refresh seek has refilled it. The test cannot distinguish the two paths, and the open's future
is fire-and-forget with `.catchError`, so a failed open is invisible.
**Fix:** If the explicit seek is what must be proven, force it past any buffer and assert its
outcome: capture the future (`final seek = player.seek(...); await seek;`), optionally
`player.mpv.command(['drop-buffers'])` first, and use a WAV large enough that 2 s is far outside the
32 KiB window (e.g. `_silentWavBytes(seconds: 60)` and seek to 30 s). Otherwise reword the comment
to claim only what is proven: the bridge's seek handler ran during the open and its throw was
contained.

### IN-03: `analyzer.exclude` disables analysis of the API-freeze test in every context, not just locally

**File:** `packages/mpv_kit/analysis_options.yaml:4-8`
**Issue:** The rationale is local-only ("a local `dart analyze` over the full Flutter workspace
cannot resolve `dart:mirrors`"), but `exclude` is unconditional. The old `ignore_for_file` was
narrower: in CI's Dart-only workspace (the workflow removes the Flutter members before
`dart pub get`), `dart:mirrors` resolves, so the file used to be type-checked there; now it is not
checked by `dart analyze --fatal-infos` anywhere. Only hard compile errors surface, via `dart test`.
Removing the broad ignore is the right call under the project convention, but the file that guards
the frozen public API now has the least static checking in the package.
**Fix:** Accept and state the trade-off explicitly, or keep the exclusion scoped to a local-only
options file. At minimum, update the comment to say "excluded in all analysis contexts; `dart test`
is the only compile gate."

### IN-04: The 3-second WAV synthesis is duplicated between two test files

**File:** `packages/mpv_kit/test/player_test.dart:24-48` (`_writeSilentWav`),
`packages/mpv_kit/test/failure_injection_test.dart:106-130` (`_silentWavBytes`)
**Issue:** The new `_silentWavBytes` re-implements the exact RIFF/WAVE header written by
`_writeSilentWav`; its own doc comment acknowledges it "mirrors `player_test.dart`'s
`_writeSilentWav` header shape". Two copies of a byte-layout writer will drift (the seek tests in
both files depend on this layout being seekable and index-free).
**Fix:** Extract one helper (e.g. `Uint8List silentWavBytes({int seconds = 3})` in a shared
`test/support/wav.dart`) and let `_writeSilentWav` write those bytes to disk.

---

_Reviewed: 2026-10-24T01:00:52Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_

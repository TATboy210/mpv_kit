---
phase: quick-261025-rkj
plan: 261025-rkj
type: execute
depends_on: []
files_modified:
  - packages/mpv_kit/lib/src/core/stream_bridge.dart
  - packages/mpv_kit/test/stream_bridge_test.dart
autonomous: true
---

# 261025-rkj: Dart stream bridge: every claimed request is answered; bounded open

Verified facts (stream_bridge.dart):
- `_onRequest` calls `_b.begin(request)` and then `data.cast<Utf8>().toDartString()`.
  Invalid UTF-8 throws after `begin`, so the request is never completed; and OPEN
  cannot be cancelled natively (stream is NULL), so `stop`/`loadfile` freeze
  until dispose.
- `_handleOpen` reads `source.size` outside `try`: a throwing getter leaves the
  request unanswered.
- Native `abandoned()` releases only PENDING requests on cancel. Dart begins
  every request, so a hung seek, read or open also blocks `stop`.

## Task 1 (RED): tests (reuse the existing stream-source test file/harness; create
`stream_bridge_test.dart` only if none exists)
- A source whose `size` getter throws: the load fails (END_FILE error) within the
  timeout and `onSourceError` is reported.
- An opener that never completes: after the open timeout the load fails, a
  following `loadfile` of a good source plays, and a late-arriving source is
  closed.
- Invalid UTF-8 URI: unit-test the decode helper directly (building raw bytes
  through mpv is impractical; note this).

## Task 2 (GREEN)
- Keep the existing order (`begin` first, see the invariant comment at
  ~238); decode the URI with `utf8.decode(bytes, allowMalformed: true)`
  (length via strlen), which cannot throw.
- `_handleOpen`: wrap the whole body (including `source.size`) in try/finally
  that completes `loadingFailed` and closes the source if nothing completed;
  race `_open(uri)` against a timer of `_openTimeout` (named constant, about 30 s,
  rationale: libmpv cannot cancel OPEN); a source arriving after the timeout is
  closed.
- SEEK is unchanged (stays begun). Dropped after review: un-begun SEEK lets
  a CLOSE run `source.close` concurrently with an in-flight `source.seek`,
  breaking the one-call-in-flight contract of `MpvStreamSource`.
- No public API change.

## Verify
- Locally `dart test` (stream tests) against bt/libmpv-2.dll;
  `dart analyze --fatal-infos`; CI full suite.
- Commits: the failing tests first, then `fix(mpv_kit): stream bridge always answers claimed requests`.

## Review revisions (2026-10-25, plan-checker pass; these are authoritative and supersede any conflicting text above)
- Test seam: the open timeout is
  `@visibleForTesting static Duration openTimeout = const Duration(seconds: 30);`
  on the internal `StreamBridge` (not exported by mpv_kit.dart:17-18, so no
  public API change). The timeout test sets it to ~300 ms and restores it in
  `tearDown`; otherwise the test would exceed the 10 s per-test timeouts.
- The new try/finally in `_handleOpen` must keep the `_shutdown` branch
  (~263-273) intact: when shut down, the finally completes nothing (native
  already released the request) and only closes a source that arrived.
- Residual risks to document (summary + doc comment): a hung READ still blocks
  `stop` (READ must stay begun for buffer lifetime); `stop` can wait up to the
  open timeout; a legitimately slow opener (network) longer than 30 s now fails
  with `loadingFailed`.

**Host facts:** this host is Windows (MSYS Git Bash, MSVC on PATH, no meson/ninja),
so libmpv and `native/tests` cannot be built locally; native build/tests run on
CI (`.github/workflows/native-verify.yml`, incl. the ASan/UBSan job). Dart
tests run locally with `MPV_KIT_LIBMPV_PATH=D:/mpv_kit/bt/libmpv-2.dll`
(mpv v0.41.0-689, an older local build without this branch's patches; tests
that need patched native behaviour must skip locally and run on CI).



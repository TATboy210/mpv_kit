# Single-Decode After Record — Phase 4 (PERF-01/PERF-04)

**Date:** 2026-10-24 · **Baseline:** [2026-10-24-baseline.md](2026-10-24-baseline.md) · **Code:** events.dart single `_prop` call + integerized `time-pos` throttle

## Decode micro-benchmark (200k iterations, JIT, 20k warm-up, same machine)

| Shape | Before (ns/op) | After (ns/op) | Δ |
|-------|----------------|---------------|---|
| `decode-double` (time-pos shape) | 169–175 | **102–113** | **−38%** (~1.6×) |
| `decode-map` (2-entry map) | 1768–1960 | **927–950** | **−49%** (~2×) |

The `time-pos` hot path (60 events/s at 60 fps) now runs one `readNode` + one name decode per event instead of two — the boxed double, name String and `(String, Object?)` record are no longer allocated twice.

## Position-listener allocations (source-level, not micro-benchable)

The `time-pos` listener previously allocated per event (60/s), *before* the throttle decided:

- `secondsToDuration(v)` → 1 Duration
- `DateTime.now()` → 1 DateTime
- `d - position._value` → 1 Duration
- `.abs()` → 1 Duration

Now the throttle path is allocation-free: microsecond integer comparison against a monotonic `Stopwatch`; the `Duration` is constructed only when the throttle actually emits (~10/s). Semantics preserved: unavailable property (idle) still resolves to position zero through the same throttle (NaN/Inf — which would have thrown the old `round()` — now normalize to zero, consistent with Phase 3's parse containment).

## Behavior gates

- mpv_kit suite: **112 passed / 2 skipped** (includes all position throttle/seek tests unchanged).
- `api_freeze_test.dart` passes — public API diff is empty (the counter is `@visibleForTesting`, auto-exempt).
- Counter test: one `propertyChange` decode → `propDecodesForTesting` delta == 1.

## Reproduce

```sh
cd D:/mpv_kit && dart run tools/bench_decode.dart
cd packages/mpv_kit && MPV_KIT_LIBMPV_PATH="D:/mpv_kit/.dart_tool/hooks_runner/shared/mpv_kit_libs/build/v0.1.0-dev.3/windows-x64/lib/libmpv-2.dll" PATH="$PATH:D:/mpv_kit/.dart_tool/hooks_runner/shared/mpv_kit_libs/build/v0.1.0-dev.3/windows-x64/lib" dart test
```

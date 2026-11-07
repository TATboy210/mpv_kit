# UHD Endurance Results — 4K PASS / 8K FAIL (commit-memory exhaustion)

**Machine:** Windows 11, x64, NVIDIA GeForce RTX 4060 Laptop GPU (8 GB), hybrid GPU laptop
**Date:** 2026-10-24
**libmpv:** mpv_kit_libs hook build v0.1.0-dev.3 (mpv v0.41.0-1113-gfd9265a905, patched 0001..0007, Vulkan enabled)
**Code state:** Phase 4 optimizations landed (`2785bd5` — single decode + integerized throttle)
**Source:** `av://lavfi:testsrc2=size=WxH:rate=30:duration=1800[out0];sine=frequency=440:sample_rate=48000:duration=1800[out1]`, ao=null (real-time pacing), video-sync=audio (Player default)

## Reproduce

```sh
LIB=D:/mpv_kit/.dart_tool/hooks_runner/shared/mpv_kit_libs/build/v0.1.0-dev.3/windows-x64/lib
cd example && MPV_KIT_BENCH_SIZE=3840x2160 MPV_KIT_BENCH_SECONDS=1800 MPV_KIT_BENCH_LABEL=4k \
  MPV_KIT_LIBMPV_PATH="$LIB/libmpv-2.dll" PATH="$PATH:$LIB" \
  flutter test integration_test/uhd_endurance_test.dart -d windows
# 8K: MPV_KIT_BENCH_SIZE=7680x4320 MPV_KIT_BENCH_LABEL=8k
```

## 4K (3840x2160 × 1800 s) — **PASS (all gates green)**

| Gate / metric | Value | Verdict |
|---------------|-------|---------|
| frame-drop-count (final) | **0** | ✓ |
| decoder-frame-drop-count (final) | **0** | ✓ |
| total-avsync-change (final) | **−0.0333 s** (one frame; constant after the first minute) | ✓ bounded |
| avsync (peak abs) | 4.74e-05 s (microsecond-scale) | ✓ |
| vo-delayed-frame-count (avg / max) | 0 / 0 | ✓ no backlog |
| display-sync-active | false (expected under video-sync=audio) | — |
| estimated-vf-fps (final) | 30.0 | ✓ real-time |
| renderErrors / deviceLost | 0 / false | ✓ |
| RSS (end) | 826 MB (stable class) | — |

30 minutes at 4K: no drops, no drift, no backlog. **PERF-03's 4K clause is met.**

## 8K (7680x4320) — **FAIL: reproducible process death (commit-memory exhaustion)**

| Attempt | Config | Outcome |
|---------|--------|---------|
| 1 | 8K × 1800 s | App process died ~25 s into playback (test listener vanished; "did not complete") |
| 2 | 8K × 1800 s | Same death, same window |
| 3 (probe) | 8K × 120 s | Same death ≤ 40 s — **reproducible, not transient** |

**Evidence:** Windows Error Reporting event 1001 `RADAR_PRE_LEAK_64` (commit-memory exhaustion diagnostic), P1 = `mpv_kit_example.exe`, TimeCreated 16:01:06 — inside attempt 1. No BENCH line is ever produced (the process dies before sampling completes); no Dart exception (a native commit failure kills the process).

**Per-frame arithmetic:** one 8K YUV420P frame ≈ 124 MiB system memory; mpv's queues (demuxer-max-bytes=400 MiB of *raw* lavfi output + decoder output queue + hwdec-extra-frames=6) plus the 633 MiB Vulkan/D3D11 ring (shared GPU memory counts toward process commit on a laptop) push the commit charge over the limit seconds into playback.

**Verdict:** the 8K endurance gate is **not met** — this is a stability finding (ungraceful commit exhaustion), not a flaky environment. PERF-03's 8K clause stays open; the 4K clause is delivered.

## Follow-up candidates (owned by a future insertion, not relaxed here)

1. Bound the raw-frame pipeline for UHD: scale `demuxer-max-bytes`/`demuxer-max-back-bytes` by frame size, or cap lavfi queueing.
2. Diagnose exactly which queue exhausts commit (vs `ProcessInfo.currentRss` + commit sampling per 10 s).
3. Ring shrink behavior at 8K (the OOM fallback targets the VRAM path; system-commit pressure is unhandled).
4. Graceful failure: a commit-pressure event to Dart (OBS-03 style) instead of process death.

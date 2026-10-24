---
phase: 04-measured-performance-uhd-endurance
plan: 01
subsystem: benchmarks
tags: [performance, baseline, integration-test]
requires:
  - phase: 02-03
    provides: "flutter-video-coverage CI job pattern and the example app as the real-machine vehicle"
provides:
  - "tools/bench_decode.dart: repeatable decode micro-benchmark, no libmpv, CI-runnable"
  - "example/integration_test/playback_bench_test.dart: real-machine playback/cycle/resize benchmark on the Vulkan path"
  - "docs/perf/2026-10-24-baseline.md: the BEFORE record every Phase 4 optimization is measured against"
affects: [04-02, 04-03]
actuals:
  tokens: 78000
  tasks: 2
  commits: 1
tech-stack:
  added:
    - "integration_test (sdk) as example dev dependency"
  patterns:
    - "Multi-stream lavfi graphs with [out0]/[out1] labels: video+audio sources without fixture files (audio makes avsync meaningful)"
    - "One testWidgets per integration file: sequential tests in a file hang the binding ('did not complete')"
    - "One render context per mpv handle: concurrent controller create on the same player fails with 'no usable render backend'"
key-files:
  created:
    - tools/bench_decode.dart
    - example/integration_test/playback_bench_test.dart
    - docs/perf/2026-10-24-baseline.md
  modified:
    - example/pubspec.yaml
key-decisions:
  - "The fresh mpv_kit_libs hook build (v0.1.0-dev.3, post-rebase) is the bench libmpv — the older bt/libmpv-2.dll (Oct 15, pre-rebase) silently falls back to software (its mpv_render_context_create reports 'operation not implemented' for gpu-next/gpu); recorded in the baseline doc"
  - "Resize sweeps run while PLAYING: a stopped-but-rendered state blocks the render thread's ring reallocation on unconsumed retired images (58 events when stopped vs 1 coalesced event while playing; the stopped state hung the sweep)"
  - "Measurement-only plan: no perf assertions that could flake CI; the endurance gates live in 04-03"
patterns-established:
  - "BENCH <name> {json} one-line report format for before/after comparison"
requirements-completed: [PERF-02]
coverage:
  - id: D1
    description: "Decode micro-benchmark runs anywhere (no libmpv) and prints stable ns/op for double and map shapes"
    requirement: PERF-02
    verification:
      - kind: automated
        ref: "dart run tools/bench_decode.dart — two consecutive runs within ±5% noise (double 169-175 ns/op, map 1768-1960 ns/op)"
        status: pass
    human_judgment: false
  - id: D2
    description: "Real-machine bench samples the avsync family on the Vulkan path (1080p30, drops 0, avsyncPeak 1.4e-05, delayed 0), 50 cycles RSS +45.1 MiB < 64 MiB, 100 resizes complete"
    requirement: PERF-02
    verification:
      - kind: automated
        ref: "flutter test integration_test -d windows — All tests passed; BENCH lines in docs/perf/2026-10-24-baseline.md"
        status: pass
    human_judgment: false
  - id: D3
    description: "BEFORE baseline recorded before any optimization (committed prior to the 04-02 optimization commit)"
    requirement: PERF-02
    verification:
      - kind: automated
        ref: "docs/perf/2026-10-24-baseline.md committed in eebf406; optimization landed in 2785bd5"
        status: pass
    human_judgment: false
duration: 58 min
completed: 2026-10-24
status: complete
plan_head_before: e4407ab
plan_head_after: eebf406
commits: 1
---

# Phase 04 Plan 01: Benchmark Harness + Baseline Summary

**Both repeatable benchmarks exist and the BEFORE baseline is committed before any optimization.**

## Performance

- Duration: 58 min (including the libmpv-version investigation below)
- Tasks: 2/2; Commits: 1
- Token estimate 52000 vs realized ~78000 (the render-path investigation)

## Accomplishments

- `tools/bench_decode.dart`: synthetic propertyChange events (Arena + writeNode), 200k decodes per shape, one `BENCH` line per shape; runs from the repo root via `dart run`.
- `example/integration_test/playback_bench_test.dart`: real Vulkan/gpu-next render on the 4060; metric sampling (avsync family, 500 ms cadence), 50 controller create/dispose cycles (RSS +45.1 MiB < 64 MiB), 100-resize sweep while playing (RSS +5.2 MiB).
- `docs/perf/2026-10-24-baseline.md`: machine identity, numbers, reproduction commands, and the finding that `bt/`'s old DLL cannot serve these benches.

## Task Commits

1. `eebf406` — bench: decode micro-benchmark + real-machine playback/cycle/resize benches; BEFORE baseline (PERF-02)

## TDD Gate Compliance

- N/A (measurement-only). Mechanical verification: both benches run clean; analyzer clean; production lib/ untouched.

## Files Created/Modified

- Created: `tools/bench_decode.dart`, `example/integration_test/playback_bench_test.dart`, `docs/perf/2026-10-24-baseline.md`.
- Modified: `example/pubspec.yaml` (integration_test dev dependency).

## Decisions Made

- See key-decisions: fresh hook-build libmpv; resize-while-playing; measurement-only.

## Deviations from Plan

1. `[Rule 1 - libmpv version]` Found during: first bench run. Issue: the plan's stated precondition (`bt/libmpv-2.dll`) silently falls back to software — its `mpv_render_context_create` reports `operation not implemented` for gpu-next/gpu (pre-rebase Oct 15 build; 6 vulkan strings vs 24 in the fresh hook build). Fix: benches run against the mpv_kit_libs hook build v0.1.0-dev.3 (Oct 23, post-rebase, Vulkan + libplacebo + bridge + full DLL closure); the baseline doc records this and warns against bt/. Committed in: `eebf406`.
2. `[Rule 1 - lavfi audio]` Found during: bench authoring. Issue: testsrc2 has no audio → avsync stayed null; the `video=…:audio=…` URL form is not supported (`unrecognized file format`). Fix: multi-stream graph with `[out0]/[out1]` labels (ffmpeg lavfi device labeling), probed standalone first. Committed in: `eebf406`.
3. `[Rule 1 - test isolation]` Found during: bench run. Issue: three sequential testWidgets in one integration file hang after the first completes ("did not complete"). Fix: one testWidgets, three sections. Committed in: `eebf406`.
4. `[Rule 1 - render context]` Found during: bench run. Issue: creating a second controller while the playback controller was alive fails (`no usable render backend`) — one render context per mpv handle. Fix: dispose before the cycles; resize got its own fresh controller. Committed in: `eebf406`.
5. `[Rule 1 - resize state]` Found during: bench run. Issue: resizing a stopped-but-rendered player hangs the sweep — the render thread's ring reallocation waits on unconsumed retired images (58 resize events when stopped vs 1 coalesced while playing). Fix: the sweep runs while playing (the real workload). Committed in: `eebf406`.

## Issues Encountered

- Relative `dart run ../tools/…` paths fail from packages/mpv_kit (Git Bash path quirk); the documented command runs from the repo root.

## User Setup Required

- None (bench libmpv is the hook build already on disk).

## Known Stubs

- None.

## Threat Flags

- T-04-01/02 mitigated (baseline committed before optimization; visibility documented); T-04-SC not triggered.

## Verification Results

- `dart run tools/bench_decode.dart` → stable double/map lines.
- `flutter test integration_test -d windows` → All tests passed; three BENCH lines.
- `flutter analyze --fatal-infos` clean (example + mpv_kit).

## Next Phase Readiness

- 04-02 optimizes against these exact numbers; the after-run reuses the same commands.

## Self-Check: PASSED

- Artifacts exist; commit `eebf406` is an ancestor of HEAD and predates `2785bd5` (the optimization); commit count measured.

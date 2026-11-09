---
phase: 09-8k-full-rate
plan: 01
subsystem: player
tags: [uhd, demuxer, auto-tune, performance]
requires:
  - phase: 07-01
    provides: "vendor advance; runtime-writable demuxer cache options confirmed"
  - phase: 04-01
    provides: "v1 option pack (400MiB/100MiB) and the 8K WER crash evidence"
provides:
  - "Player.demuxerQueueBudgetForTesting — documented frame-size formula, freeze-exempt seam"
  - "Runtime auto-tune: videoParams.stream -> budget -> demuxer-max-bytes/max-back-bytes setProperty, re-derived on every resolution change"
  - "User-first override detection: explicit user queue values permanently disable auto-tune for that Player"
affects: [09-02, 11-*]
actuals:
  tasks: 2
  commits: 1
tech-stack:
  added: []
  patterns:
    - "Pure static formula pinned by a unit matrix; the runtime path is a thin subscriber over it"
    - "Ours-or-default ownership check before writing options (idempotent, user-first, best-effort)"
key-files:
  created: []
  modified:
    - packages/mpv_kit/lib/src/player/player.dart
    - packages/mpv_kit/test/player_test.dart
    - packages/mpv_kit/test/api_freeze_test.dart (seam registration)
key-decisions:
  - "4K budget = byte-identical to v1 (400MiB/100MiB) — zero regression surface on the delivered tier"
  - "Giant-frame clause (frameBytes ≥ 32MiB → fwd ≤ 256MiB, back 64MiB) bounds 8K total commit: −180MiB vs v1"
  - "1080p keeps 64-frame budget ≈199MiB — still covers 1 s of 60 fps readahead (demuxer-readahead-secs default)"
  - "Tune failures are swallowed (best-effort), never thrown into the stream (T-09-02)"
patterns-established:
  - "Ours-or-default ownership check: only rewrite an option while its value still equals the pack default or our last applied value"
requirements-completed: [UHD-01]
coverage:
  - id: D1
    description: "Formula matrix 640x360 / 1080p / 4K (=v1) / 8K (giant clause) / degenerate dims"
    requirement: UHD-01
    verification:
      - kind: unit
        ref: "player_test.dart group 'demuxer queue budget formula' (green)"
        status: pass
    human_judgment: false
  - id: D2
    description: "Runtime auto-tune proven through real libmpv: apply, resolution-change retune, user-override precedence"
    requirement: UHD-01
    verification:
      - kind: integration
        ref: "player_test.dart group 'demuxer queue auto-tune (real libmpv)' (green)"
        status: pass
    human_judgment: false
  - id: D3
    description: "Three-tier short verification under the new budgets (v1 gates)"
    requirement: UHD-01
    verification:
      - kind: integration
        ref: "1080p bench playback+resize green (0 drops, avsync 19 µs, RSS flat); 4K 60 s green (RSS 756 MiB); 8K 60 s green (RSS 940 MiB) — docs/perf/2026-10-25-8k-full-rate.md"
        status: pass
    human_judgment: false
deviations:
  - "[Rule 1 - verification scope] playback_bench's controller cycles section fails on today's machine ('did not complete', no WER, no Dart exception). Bisected: reproduces with auto-tune disabled AND with v1 baseline code eebf406 in a clean worktree → pre-existing environment-level regression in the controller churn path, unrelated to UHD-01 (the endurance harness has no cycles section and passes everywhere). playback+resize legs (the UHD-relevant legs) are green. Recorded in docs/perf/2026-10-25-8k-full-rate.md; owned by Phase 10."
---

# 09-01 Summary: Budget formula + runtime auto-tune + three-tier verification

## Accomplishments

- Formula (`frameBytes=w·h·1.5; fwd=min(400MiB, 64×frameBytes); giant clause → min(fwd,256MiB); back=clamp(fwd/4, 32MiB, 100MiB)`) documented in player.dart, pinned by a unit matrix.
- Constructor subscribes `videoParams.stream → _autoTuneDemuxer`: applies on first params and on every resolution change; ownership check makes it idempotent and user-first; failures never throw into the stream.
- Integration tests through real libmpv (read-back apply / retune / user-first); freeze seam registered.
- Three-tier short verification all green (see coverage D3 + perf doc).

## Task Commits

1. `e9baee6` — perf(player): frame-size-derived demuxer queue budgets, runtime auto-tuned (UHD-01)

## TDD Gate Compliance

| RED | GREEN |
|-----|-------|
| missing static → matrix group compile-fails | formula + auto-tune implemented; suite 116 passed / 2 skipped; analyze clean; api_freeze green |

## Deviations from Plan

See `deviations` in frontmatter — the cycles-section environment hang (pre-existing, bisected, re-homed to Phase 10).

## Verification Results

- Unit + integration: player_test 116/2, analyze --fatal-infos clean, api_freeze green (commit e9baee6 evidence).
- 1080p bench: playback 0 drops / avsync 19 µs; resize 100/100, RSS −0.2 MiB (auto-tune active).
- 4K 60 s: all v1 gates green. 8K 60 s: all v1 gates green (v1 died ≤ 40 s at this tier).

## Self-Check: PASSED

- Commit is an ancestor of HEAD; perf doc records the numbers.

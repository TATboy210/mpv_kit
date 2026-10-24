---
phase: 01-player-lifetime-dispose-safety
review: 01-REVIEW.md
updated: 2026-10-24
---

# Phase 01 — Review Disposition

One row per finding. Default disposition is `open`; a triaged finding must be distinguishable from a forgotten one.

| Finding | Severity | Disposition | Notes |
|---|---|---|---|
| CR-01 | Critical | fixed | `mpv_test.dart` `dispose from a synchronous events listener closes events without throwing`; `Mpv._closeIfOpen` retries a mid-dispatch close in a microtask. |
| WR-01 | Warning | deferred | Behavioural-contract change: choose recursive child teardown or a documented caller contract, plus a native hang test. Phase 2 decides whether it folds into STAB-04/STAB-05; otherwise a dedicated stability insertion on a reported `createClient()` hang. |
| WR-02 | Warning | deferred | Behavioural-contract change: track in-flight calls or declare concurrent close legal. Phase 3 (OBS-01) owns the stream-source contract and error surfacing. |
| WR-03 | Warning | fixed | `failure_injection_test.dart` seek test waits for `seekAttempts > 0` against a seekable in-memory WAV; the read test asserts `readAttempts > 0`. |
| WR-04 | Warning | fixed | `native-verify.yml` runs `dart test test/lifecycle_test.dart -t lifecycle --run-skipped`; `dart_test.yaml` and the test header state only file-scoped loading. |
| IN-01 | Info | fixed | `analysis_options.yaml` excludes `test/api_freeze_test.dart`; the broad `ignore_for_file` is gone and `dart test` still compiles it. |
| IN-02 | Info | deferred | API-semantics change on frozen methods: rebaseline the post-dispose table and redefine the native-entry counter. Phase 3 observability, or an explicitly approved API-semantics change. |
| IN-03 | Info | fixed | `player_test.dart` `audioDevices first read after dispose is already closed`; the `_disposed` branch closes the lazily created state. |
| IN-04 | Info | fixed | `player.dart` guards the end-file error branch with `!_errors.isClosed`; a source gate stands in because the branch is currently unreachable. |
| IN-05 | Info | deferred | Behavioural-contract change: share one dispose future and define dual-caller error semantics. Phase 2 (STAB-04/STAB-05), where controller dispose concurrency is in scope. |

## Gap-closure review (2026-10-24)

Second review, of the `bf98a54..HEAD` diff produced by plans 01-04 and 01-05. Full report:
`01-REVIEW-GAPCLOSURE.md`. IDs are prefixed `GC-` because the reviewer restarts numbering per
report; without the prefix a fresh `CR-01` would inherit the remediation recorded above for the
original `CR-01`. The original table above keeps exactly one row per original finding.

| Finding | Severity | Disposition | Notes |
|---|---|---|---|
| GC-WR-01 | Warning | fixed | `native-verify.yml` claimed a skipped run fails the job; it exits 0. Comment now states `--run-skipped` is load-bearing and that only an uncollected suite fails. |
| GC-WR-02 | Warning | deferred | `api_freeze_test.dart` compares member names only and filters constructors, so `Mpv.create`, `Player`, `Player.wrap` and every signature change escape the freeze. Pre-existing, not introduced by this phase. Retarget when the freeze is next revised (Phase 5 build/provenance work is the nearest fit). |
| GC-IN-01 | Info | deferred | `Mpv._closeIfOpen`'s microtask retry is unguarded; a retry that still finds a firing controller would surface as an uncaught zone error and `done` would never arrive. Unreachable under the current call sites. |
| GC-IN-02 | Info | deferred | The seek test proves containment but not that the explicit seek reached the demuxer — mpv's post-probe refresh seek already increments `seekAttempts`, and the target lands inside the 32 KiB lavf AVIO window. Tighten when a patched-native runner exists (Phase 6). |
| GC-IN-03 | Info | fixed | `analysis_options.yaml` now states that `analyzer.exclude` also removes CI's static analysis for the file, leaving `dart test` compilation as the only backstop. |
| GC-IN-04 | Info | deferred | The RIFF/WAVE byte writer is duplicated between `player_test.dart` and `failure_injection_test.dart`; extract a shared test helper on the next touch. |


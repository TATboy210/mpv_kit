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

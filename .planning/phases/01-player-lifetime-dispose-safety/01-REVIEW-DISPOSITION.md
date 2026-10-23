---
phase: 01-player-lifetime-dispose-safety
review: 01-REVIEW.md
updated: 2026-10-24
---

# Phase 01 — Review Disposition

One row per finding. Default disposition is `open`; a triaged finding must be distinguishable from a forgotten one.

| Finding | Severity | Disposition | Notes |
|---|---|---|---|
| CR-01 | Critical | open | Reentrant `Mpv.dispose()` from a synchronous `Mpv.events` listener throws and `events` never closes. Reproduced by the reviewer with real libmpv. |
| WR-01 | Warning | open | A live sub-client handle blocks `mpv_terminate_destroy` on the Dart thread. |
| WR-02 | Warning | open | `StreamBridge.shutdown()` calls `source.close()` while a read/seek future may be in flight. |
| WR-03 | Warning | open | Seek failure-injection test does not prove `_handleSeek` ran. |
| WR-04 | Warning | open | `-t lifecycle` still loads all suites into one process; RSS isolation claim is inaccurate. |
| IN-01 | Info | open | Broad `ignore_for_file` in `api_freeze_test.dart`. |
| IN-02 | Info | open | `_ensureAlive` guards members that do not touch the handle. |
| IN-03 | Info | open | `audioDevices` after dispose returns a stream that never closes. |
| IN-04 | Info | open | `Player._onEvent` EndFile branch lacks an `isClosed` guard. |
| IN-05 | Info | open | Concurrent second `Player.dispose()` does not await the first. |

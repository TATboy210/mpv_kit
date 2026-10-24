---
phase: "01"
slug: "player-lifetime-dispose-safety"
status: verified
# threats_open = count of OPEN threats at or above workflow.security_block_on severity (the blocking gate)
threats_open: 0
asvs_level: 1
created: "2026-10-24"
---

# Phase 01 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.

Register authored at plan time across all five plans (`T-01-01` … `T-01-17`, plus the reserved `T-01-SC`). Verification ran at ASVS L1 (grep/source depth) per `workflow.security_asvs_level: 1`; every threat is `closed` with source evidence, so the L2/L3 auditor pass was not required.

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| Dart isolate -> libmpv FFI | Every public `Mpv` call crosses into native code that owns the handle lifetime | Handle pointers, property/command strings |
| native wakeup thread -> Dart isolate | `NativeCallable.listener` invokes `_onWakeup` after the handle may be under teardown | Event wakeup signals |
| user hook / listener -> teardown path | Application code runs synchronously inside `Player.dispose()` and event dispatch | Arbitrary caller code |
| application code -> `Mpv` | Any late timer, widget callback, or plugin event can call the wrapper after teardown | Caller arguments |
| `MpvStreamSource` -> `StreamBridge` | Host code crosses into the demuxer request path and may throw or never answer | Media bytes (untrusted host data) |
| CI invocation -> process-wide RSS measurement | A tag-only invocation can load other suites into the measurement process | Process memory statistics |
| analyzer configuration -> source file | An exclusion decides which diagnostics are reported | Static-analysis diagnostics |

---

## Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation | Status |
|-----------|----------|-----------|----------|-------------|------------|--------|
| T-01-01 | Tampering | `Mpv.dispose` / wakeup callback | high | mitigate | `mpv.dart:196` nulls the wakeup callback, `:202` destroys the core, `:203` closes the `NativeCallable` — in that order; `_onWakeup` exits on `_disposed` | closed |
| T-01-02 | Tampering | `Player.dispose` / `Mpv.dispose` | high | mitigate | Idempotent early return at `mpv.dart:189` and `player.dart:641`; hook list snapshotted and cleared before the loop | closed |
| T-01-03 | Denial of Service | `Player` state streams | high | mitigate | `position` / `decodeWarning` registered into `_states` at `player.dart:205-206`; every state closed in `dispose()` at `player.dart:668-670` | closed |
| T-01-04 | Tampering | `Player.dispose` hook loop | high | mitigate | `stage()` wrapper (`player.dart:643-654`) catches per stage, collects errors, runs every stage, then rethrows | closed |
| T-01-05 | Tampering | Public `Mpv` methods | critical | mitigate | 31 `_ensureAlive()` guards — one per public entry — throw `StateError` before any `bindings.*` call; the API-table test proves the native-entry counter stays flat | closed |
| T-01-06 | Tampering | `observeProperty` late listen | high | mitigate | `onListen` checks `_disposed` (`mpv.dart:467`) and delivers `StateError` without calling `bindings.observeProperty` | closed |
| T-01-07 | Denial of Service | `Mpv._dispatch` / `_onWakeup` | high | mitigate | Sync-broadcast dispatch isolates listener throws; `runZonedGuarded` in `failure_injection_test.dart:181` captures the zone error and asserts delivery continues | closed |
| T-01-08 | Denial of Service | `StreamBridge` read/seek/close | high | mitigate | `on Object` mapping to mpv error codes at `stream_bridge.dart:225/257/279`; all four close paths wrapped in `catchError`; dispose bounded at 10 s | closed |
| T-01-09 | Denial of Service | repeated create/dispose | high | mitigate | 1000-cycle soak asserts every stream closes and RSS stays under 64 MiB (`lifecycle_test.dart:63-72`); tag-skipped by default and run file-scoped. *The plan's "own process" wording was inaccurate and was corrected by 01-05 (WR-04); the file-scoped invocation is strictly stronger than the tag-only form it replaced.* | closed |
| T-01-10 | Tampering | CI test invocation | medium | mitigate | `failure-injection` and `lifecycle` tags declared; `native-verify.yml` invokes each explicitly, and a JSON-reporter skip check fails a soak that silently does not run | closed |
| T-01-11 | Denial of Service | `Mpv.dispose` re-entered from a synchronous `Mpv.events` listener | high | mitigate | `_closeIfOpen` (`mpv.dart:683`) catches the mid-dispatch `StateError` and retries in `scheduleMicrotask`; both `_observers` (`:216`) and `_events` (`:219`) route through it; regression test bounds `done` at 5 s | closed |
| T-01-12 | Denial of Service | `Player.audioDevices` first read after dispose | medium | mitigate | `_disposed` branch closes the fresh state with `unawaited(state._close())` (`player.dart:345-348`) and never registers it in `_states` | closed |
| T-01-13 | Tampering | `Player._onEvent` end-file error branch | low | mitigate | `if (!_errors.isClosed)` guard at `player.dart:724`, matching the `LogMessageEvent` branch | closed |
| T-01-14 | Tampering | `failure_injection_test.dart` seek/read path | medium | mitigate | `readAttempts` / `seekAttempts` counters assert both bridge handlers ran against a seekable in-memory WAV (`failure_injection_test.dart:47,74-94`) | closed |
| T-01-15 | Tampering | `native-verify.yml` lifecycle invocation and comments | medium | mitigate | File-scoped invocation `dart test test/lifecycle_test.dart -t lifecycle --run-skipped` (`native-verify.yml:95`); three comments claim only file-scoped loading | closed |
| T-01-16 | Tampering | `analysis_options.yaml` / `api_freeze_test.dart` | low | mitigate | VM-only exclusion moved to `analyzer.exclude`; zero `ignore_for_file` directives remain in the test, and it still compiles and runs under `dart test` | closed |
| T-01-17 | Repudiation | `01-REVIEW-DISPOSITION.md` | low | mitigate | Ten rows resolved — six `fixed`, four `deferred` with reason/cost/owner — zero `open` | closed |
| T-01-SC | Tampering | Package installs | high | mitigate | No package-manager install task in any of the five plans; no dependency added or changed (no `pubspec.yaml` edit in the phase diff) | closed |

*Status: open · closed · open — below high threshold (non-blocking)*
*Severity: critical > high > medium > low — only open threats at or above workflow.security_block_on count toward threats_open*
*Disposition: mitigate (implementation required) · accept (documented risk) · transfer (third-party)*

**Blocking threshold:** `workflow.security_block_on: high`. All high and critical threats are closed.

---

## Accepted Risks Log

No accepted risks.

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-10-24 | 18 | 18 | 0 | gsd-secure-phase (ASVS L1, source verification) |

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-10-24

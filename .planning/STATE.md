---
gsd_state_version: "1.0"
current_phase: 2
current_phase_name: Video Controller Lifecycle & Resize Safety
status: planning
stopped_at: Phase 01 complete, ready to plan Phase 2
last_updated: "2026-10-24T01:30:13.313Z"
last_activity: 2026-10-24
last_activity_desc: Phase 01 complete, transitioned to Phase 2
state_head: 72c5341ec9b7573fe690325c88e64643a79275fe
progress:
  total_phases: 6
  completed_phases: 1
  total_plans: 5
  completed_plans: 5
  percent: 17
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-10-24)

**Core value:** 以尽可能小的源码改动，换取可验证的稳定性与 4K/8K UHD 长时间满帧播放能力——不崩溃、不泄漏、不积压。
**Current focus:** Phase 2 — Video Controller Lifecycle & Resize Safety

## Current Position

Phase: 2 — Video Controller Lifecycle & Resize Safety
Plan: Not started
Status: Ready to plan
Last activity: 2026-10-24 — Phase 01 complete, transitioned to Phase 2

Progress: [██░░░░░░░░] 17%

## Performance Metrics

**Velocity:**
- Total plans completed: 5
- Average duration: -
- Total execution time: 0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01 | 5 | - | - |

**Recent Trend:**
- Last 5 plans: -
- Trend: Stable

*Updated after each plan completion*
**Per-Plan Metrics:**

| Plan | Duration | Tasks | Files |
|------|----------|-------|-------|
| Phase 01 P01 | 6 min | 2 tasks | 4 files |
| Phase 01 P02 | 8 min | 2 tasks | 3 files |
| Phase 01 P03 | 5 min | 3 tasks | 5 files |
| Phase 01 P04 (gap) | 3 min | 2 tasks | 4 files |
| Phase 01 P05 (gap) | 4 min | 3 tasks | 7 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [Milestone]: API 冻结，只做小改动大收益的稳定性/性能优化。
- [Roadmap]: 阶段按技术域划分，顺序为生命周期 → 可观测性 → 性能 → 构建 → 跨平台验证。
- [Roadmap]: 失败路径回归测试随 Phase 1/2 落地，真实插件 integration test 与六目标矩阵由 Phase 6 拥有。
- [Phase 01]: Single dispose error rethrows unchanged (identity preserved); multiple errors aggregate into one StateError after all teardown stages ran.
- [Phase 01]: position and decodeWarning register directly in Player._states instead of via _bind (custom parsers, no standard observation path).
- [Phase 01]: Public-entry liveness gate: _ensureAlive() throws StateError before any bindings.* call and increments _nativeEntries only past the check, so a flat counter proves no FFI after dispose.
- [Phase 01]: API freeze is pinned by dart:mirrors reflection to the pre-phase Mpv/Player surface plus exactly nativeEntriesForTesting and stateStreamsForTesting.
- [Phase 01]: No production listener counter was added: synchronous broadcast dispatch already isolates a throwing listener, and the failure-injection tests capture the zone error while proving delivery continues.
- [Phase 01]: Stream-bridge failure-injection tests skip only when native patch 0006 is absent (explicit capability guard with a reason); a missing libmpv still fails loudly.
- [Phase 01]: The 1000-cycle RSS soak is isolated by a default-skipped lifecycle tag and runs file-scoped via `dart test test/lifecycle_test.dart -t lifecycle --run-skipped`. (Corrected: earlier "own process" wording was wrong — a tag-only invocation still loads every suite.)
- [Phase 01]: _handleOpen's shutdown branch contains a throwing close with catchError, matching shutdown(), because _onRequest invokes it unawaited.
- [Phase 01 gap closure]: A synchronous broadcast controller cannot be closed mid-dispatch; every controller close in `Mpv.dispose` goes through `_closeIfOpen`, which retries once in a microtask.
- [Phase 01 gap closure]: Verification conclusions must separate "measured and passed" from "not run because of the environment". The phase wrongly classified 3 runnable stream-source tests as environment-blocked for the whole cycle.
- [Phase 01 gap closure]: The local `bt/libmpv-2.dll` DOES export `mpv_kit_stream_*`; on Windows its dependencies must be on PATH or `MpvLibrary.open()` silently falls back to a stock libmpv. Local full suite with that fix: 98 passed / 2 skipped / 0 failed.

### Pending Todos

None yet.

### Blockers/Concerns

- 真机验证目前只有 Windows x64（RTX 4060）；Linux/macOS 覆盖依赖 Phase 6 的 CI runner 与 lavapipe/MoltenVK 环境。
- 4K/8K 30 分钟指标（PERF-03）需要可用的真实 GPU runner，Phase 4 开始前需确认测试机。
- 本地跑 `mpv_kit` 测试需要 `PATH` 同时包含 `bt/`，否则 `MPV_KIT_LIBMPV_PATH` 会静默回落到 stock libmpv（见 PROJECT.md Context）。CI 若同样漏掉依赖搜索路径，会在不知情的情况下测错库。

## Deferred Items

Items acknowledged and deferred at milestone close, most recent first:

| Category | Item | Status | Deferred At | Milestone |
|----------|------|--------|-------------|-----------|
| *(none)* | | | | |

## Session Continuity

Last session: 2026-10-24T02:15:00Z
Stopped at: Phase 01 complete (verified 28/28), ready to plan Phase 2
Resume file: None

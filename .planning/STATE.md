---
gsd_state_version: "1.0"
current_phase: 3
current_phase_name: Error Surfacing
status: planning
stopped_at: Phase 02 complete, ready to plan Phase 3
last_updated: "2026-10-24T12:30:00.000Z"
last_activity: 2026-10-24
last_activity_desc: Phase 02 complete, transitioned to Phase 3
state_head: 39b7213942f640f48b2407f083ffa2d2eb8e9193
progress:
  total_phases: 6
  completed_phases: 2
  total_plans: 8
  completed_plans: 8
  percent: 33
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-10-24)

**Core value:** 以尽可能小的源码改动，换取可验证的稳定性与 4K/8K UHD 长时间满帧播放能力——不崩溃、不泄漏、不积压。
**Current focus:** Phase 3 — Error Surfacing

## Current Position

Phase: 3 — Error Surfacing
Plan: Not started
Status: Ready to plan
Last activity: 2026-10-24 — Phase 02 complete, transitioned to Phase 3

Progress: [███░░░░░░░] 33%

## Performance Metrics

**Velocity:**
- Total plans completed: 8
- Average duration: ~10 min
- Total execution time: ~1.7 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01 | 5 | - | - |
| 02 | 3 | ~47 min | ~16 min |

**Recent Trend:**
- Last 5 plans: 14 min, 9 min, 24 min(3 tasks), 9 min
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
| Phase 02 P01 | 14 min | 2 tasks | 2 files |
| Phase 02 P02 | 24 min | 3 tasks | 4 files |
| Phase 02 P03 | 9 min | 2 tasks | 1 file |

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
- [Phase 02]: create 响应的 backend 严格校验——garbage 抛 `PlatformException`,不静默降级 software;同仓库插件/Dar 对里其他值即协议断裂。
- [Phase 02]: 无 textureId 的畸形响应无法释放 native 上下文(无句柄),记录为可接受的协议断裂边界,不新增 wire 调用(API 冻结)。
- [Phase 02]: flutter_test 的 mock messenger 把 handler 的非 PlatformException 错误包装成 `PlatformException(code: 'error')`——用 mock 注入"原始 StateError 穿透通道"不可行;真实失败注入用 create 在途 dispose player 的竞态实现。
- [Phase 02]: 重入与并发 dispose 在调用时刻不可区分,teardown 进行中一律共享 future;完成后幂等成功;hook 内 await dispose 是文档化禁止模式(unawaited 重入安全)。
- [Phase 02]: 覆盖率任务消费 linux 构建的 libmpv 构件(prefix/lib + deps/lib,后者承载 dlopen 的 libplacebo/dav1d),不重复构建;运行库 ABI 用与构建一致的 apt -dev 列表,缺失时 dlopen 响亮失败而非静默 skip。
- [Phase 02]: 控制器 soak 测试不设 dart_test.yaml tag,进默认 suite——mock channel 下 100 轮很快,且 02-03 的 CI 覆盖率任务会执行它们。

### Pending Todos

None yet.

### Blockers/Concerns

- 真机验证目前只有 Windows x64（RTX 4060）；Linux/macOS 覆盖依赖 Phase 6 的 CI runner 与 lavapipe/MoltenVK 环境。
- 4K/8K 30 分钟指标（PERF-03）需要可用的真实 GPU runner，Phase 4 开始前需确认测试机。
- 本地跑 `mpv_kit` 测试需要 `PATH` 同时包含 `bt/`，否则 `MPV_KIT_LIBMPV_PATH` 会静默回落到 stock libmpv（见 PROJECT.md Context）。CI 若同样漏掉依赖搜索路径，会在不知情的情况下测错库。
- `flutter-video-coverage` 与 mpv_kit_libs 覆盖率门禁的首次真实 CI 运行待下一次 push;apt 运行库闭包如缺 DT_NEEDED 依赖会以 dlopen 失败响亮报错(非静默)。
- WR-01(createClient 挂起)经 Phase 2 triage 保持 deferred:不属控制器生命周期,缺复现;Phase 3(错误可观测性)或专门稳定性插入认领。

## Deferred Items

Items acknowledged and deferred at milestone close, most recent first:

| Category | Item | Status | Deferred At | Milestone |
|----------|------|--------|-------------|-----------|
| Visual | 重建控制器后首帧非黑帧(视觉属性) | owned by Phase 6 UAT/VERIFY-01 | 2026-10-24 (Phase 2 close) | current |
| Native evidence | 控制器 create/dispose 循环的 native 侧泄漏证据 | owned by Phase 6 real-plugin tests | 2026-10-24 (Phase 2 close) | current |

## Session Continuity

Last session: 2026-10-24T12:30:00Z
Stopped at: Phase 02 complete (12/12 must-haves, 2 deferred items owned by Phase 6), ready to plan Phase 3
Resume file: None

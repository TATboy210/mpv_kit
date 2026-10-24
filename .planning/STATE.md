---
gsd_state_version: "1.0"
current_phase: 4
current_phase_name: Measured Performance & UHD Endurance
status: planning
stopped_at: Phase 03 complete, ready to plan Phase 4
last_updated: "2026-10-24T15:00:00.000Z"
last_activity: 2026-10-24
last_activity_desc: Phase 03 complete, transitioned to Phase 4
state_head: 6c621ea2a4c971b73cb63b0571b278504ad66ba9
progress:
  total_phases: 6
  completed_phases: 3
  total_plans: 12
  completed_plans: 12
  percent: 50
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-10-24)

**Core value:** 以尽可能小的源码改动，换取可验证的稳定性与 4K/8K UHD 长时间满帧播放能力——不崩溃、不泄漏、不积压。
**Current focus:** Phase 4 — Measured Performance & UHD Endurance

## Current Position

Phase: 4 — Measured Performance & UHD Endurance
Plan: Not started
Status: Ready to plan
Last activity: 2026-10-24 — Phase 03 complete, transitioned to Phase 4

Progress: [█████░░░░░] 50%

## Performance Metrics

**Velocity:**
- Total plans completed: 12
- Average duration: ~14 min
- Total execution time: ~2.8 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01 | 5 | - | - |
| 02 | 3 | ~47 min | ~16 min |
| 03 | 4 | ~78 min | ~20 min |

**Recent Trend:**
- Last 5 plans: 9 min, 26 min, 12 min, 22 min, 18 min
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
| Phase 03 P01 | 26 min | 2 tasks | 5 files |
| Phase 03 P02 | 22 min | 1 task | 3 files |
| Phase 03 P03 | 12 min | 1 task | 6 files |
| Phase 03 P04 | 18 min | 2 tasks | 6 files |

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
- [Phase 03]: Mpv.onSourceError 是公共字段(freeze 基线 +1)而非 create 参数——Player.wrap 也要路由,且每个 Mpv 独立持有 sink 保证多 Player 安全。
- [Phase 03]: seek 失败上抛但不终止播放(mpv 语义允许瞬时失败);open/read 保持"播放以明确错误结束",源级与播放级条目共存于 Player.errors。
- [Phase 03]: Dart 同步控制器的用户监听器抛错直接进 zone、add() 正常返回——这是标准平台语义,mpv_kit 不吞;真正要钉的是排空存活与 Player 自身监听器的 containment。
- [Phase 03]: future.ignore() 必须布满全部 5 个错误完成点(含 commandAsync 等同步候选校验路径),只护 _complete 会漏。
- [Phase 03]: library_test 的回落测试必须拥有冷缓存(文件头注明顺序约束)——同 isolate 内其他 open() 先行会预热缓存使候选循环不跑。

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
| Native | Linux 运行期 GL 导入失败黑屏仅有 g_warning,无 Dart 事件(gl_interop.cc:296-321) | needs EventFn plumbing;超出 criterion 3 范围 | 2026-10-24 (Phase 3 close) | current |
| Visual | 重建控制器后首帧非黑帧(视觉属性) | owned by Phase 6 UAT/VERIFY-01 | 2026-10-24 (Phase 2 close) | current |
| Native evidence | 控制器 create/dispose 循环的 native 侧泄漏证据 | owned by Phase 6 real-plugin tests | 2026-10-24 (Phase 2 close) | current |

## Session Continuity

Last session: 2026-10-24T15:00:00Z
Stopped at: Phase 03 complete (13/14 must-haves, 1 defensive mechanism verified by source gate), ready to plan Phase 4
Resume file: None

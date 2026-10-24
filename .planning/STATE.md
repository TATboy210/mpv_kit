---
gsd_state_version: "1.0"
milestone: v2.0
current_phase: 10
current_phase_name: Composition Spike
status: executing
stopped_at: Completed 10-01-PLAN.md
last_updated: "2026-10-24T17:23:52.939Z"
last_activity: 2026-10-24
last_activity_desc: Phase 10 execution started
state_head: f1cd40def76d9c8fe4d187302821258bd0f9cbdc
progress:
  total_phases: 5
  completed_phases: 8
  total_plans: 8
  completed_plans: 24
  percent: 100
milestone_name: GPU-Next Optimization & Full-Rate UHD
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-10-24)

**Core value:** 以尽可能小的源码改动，换取可验证的稳定性与 4K/8K UHD 长时间满帧播放能力——不崩溃、不泄漏、不积压。
**Current focus:** Phase 10 — Composition Spike

## Current Position

Phase: 10 (Composition Spike) — EXECUTING
Plan: 2 of 3
Status: Ready to execute
Last activity: 2026-10-24 — Phase 10 execution started

## Performance Metrics

**Velocity:**
- Total plans completed: 24
- Average duration: ~15 min
- Total execution time: ~6 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01 | 5 | - | - |
| 02 | 3 | ~47 min | ~16 min |
| 03 | 4 | ~78 min | ~20 min |
| 04 | 3 | ~169 min | ~56 min (long runs) |
| 05 | 3 | ~135 min | ~45 min |
| 06 | 3 | ~67 min | ~22 min |
| 07 | 2 | ~135 min | ~68 min |
| 08 | 1 | ~35 min | ~35 min |

**Recent Trend:**
- Last 5 plans: 42 min, 40 min, 95 min, 35 min
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
| Phase 04 P01 | 58 min | 2 tasks | 4 files |
| Phase 04 P02 | 16 min | 2 tasks | 4 files |
| Phase 04 P03 | 95 min | 2 tasks | 2 files (long runs) |
| Phase 05 P01 | 75 min | 2 tasks | 5 files |
| Phase 05 P02 | 18 min | 1 task | 6 files |
| Phase 05 P03 | 42 min | 2 tasks | 12 files |
| Phase 06 P01 | 12 min | 1 task | 1 file |
| Phase 06 P02 | 35 min | 2 tasks | 4 files |
| Phase 06 P03 | 20 min | 1 task | 3 files |
| Phase 07 P01 | 40 min | 2 tasks | 5 files |
| Phase 07 P02 | 95 min | 2 tasks | 2 files |
| Phase 08 P01 | 35 min | 2 tasks | 5 files |
| Phase 10 P01 | 2h 10m | 2 tasks | 6 files |

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
- [Phase 04]: 基准 libmpv 必须是 hook 构建(v0.1.0-dev.3);bt/ 旧 DLL(预重基)render_context_create 报 not implemented → 静默落 software。
- [Phase 04]: lavfi 多流图用 [out0]/[out1] 标签(video=…:audio=… 形式报 unrecognized file format);音轨让 avsync 有意义,ao=null 实时配速。
- [Phase 04]: 集成测试文件内多个 testWidgets 会挂(第二个起 "did not complete")——一个 testWidgets 多 section;同一 mpv handle 同时只允许一个 render context。
- [Phase 04]: resize 扫描必须在播放中跑——停止但已渲染的状态下,渲染线程重分配会在未消费的退休图像上阻塞(停止态 58 个事件 vs 播放态 1 个合并事件)。
- [Phase 04]: 8K 提交内存耗尽崩溃(WER RADAR_PRE_LEAK_64)= 产品稳定性缺陷;8K YUV420P ≈124 MiB/帧,系统队列 + 633 MiB 共享内存环压爆提交额度;4K 不受影响。
- [Phase 05]: vendor 树并非 base+旧补丁——0004 的 5 个手工重排 hunk 仅存在于 vendor,io.c 模式改动与 wayland 旧快照无主;补丁集从 vendor 重生成(0004+0005 合并、0008 新增)使字节级 provenance 成立。
- [Phase 05]: git -c core.autocrlf=false clone 不持久——新仓库必须再 config 一次,否则后续 checkout 全树 CRLF 化(575k 行幻影 diff)。
- [Phase 05]: Git Bash 下 PATH 条目必须 POSIX 形式(/d/...);D:/... 不被转换导致依赖解析失败、MpvLibrary 静默回落(已写入 README)。

- [Phase 07]: 快照精确识别 = 多文件 blob 归因 + 正反双向全匹配走查 + 全树 diff 验证（b2c255c13e8e）；单向前向走查会停在最新探针匹配而漏掉真实提交。
- [Phase 07]: v1 vendoring 已把上游 io.c/wayland 两提交混入树中（0008 错误归因）——"vendor≠base+patches" 的疑点常是 base 标签错，不是补丁错；本次推进实为来源修正（新 vendor 与旧 vendor 仅 MPV_VERSION 一行差异）。
- [Phase 07]: lavfi 生成源仅支持前进/近终点 seek（精确落位），后退/归零为空操作——源属性；测试顺序 near-end 最后；MPV_KIT_SEEK_MEDIA 真实媒体双向覆盖。
- [Phase 07]: 宿主磁盘 100% 满的故障签名：进程无声死亡（无 WER）+ CMakeCache 截断 parse error + 增量构建 MSB8066；与提交耗尽（WER 有记录）可区分。
- [Phase 07]: 回归二进制 = dev.3（字节等同论证）；本地无 MSYS2/meson，新树构建依赖 CI。
- [Phase 08]: HUD 数据层/组件层分离（HudSnapshot.capture 是唯一触 mpv 的缝隙，测试用 fabricated 快照）；合成路径行静态至 Phase 11 接真实值；拖放白名单 isVideoPlayable 独立纯函数。
- [Phase 10]: Both surface types bind through ANGLE: DxgiSharedHandle uses EGL_D3D_TEXTURE_2D_SHARE_HANDLE_ANGLE (0x3200), D3d11Texture2D uses EGL_D3D_TEXTURE_ANGLE (0x33A3).
- [Phase 10]: The DXGI resource is owned by mpv_kit's own D3D11 device; ANGLE's in-PE Renderer11 device opens the KMT handle, so two D3D11 devices coexist in one process.
- [Phase 10]: No fence or keyed-mutex acquisition exists in the production or consumption paths; Impeller removes only Ganesh flush/submit/reset around the same ANGLE-bound GL texture.

### Pending Todos

None yet.

### Blockers/Concerns

- （已缓解）宿主磁盘回升 ~6.3GB：本地构建恢复；4K 复验可执行。
- 本地无 MSYS2/meson 工具链；新树构建依赖 CI（push 后六目标）或 dev.4 发布流（对外发布，需用户决定）。
- 新 CI 作业（patch-drift/pin-check/integration-test）首跑待 push。
- （v1 遗留）50-cycle Vulkan RSS 45.1 MiB 近门禁；8K 崩溃文档化（用户撤下 8K 分句）。

## Deferred Items

Items acknowledged and deferred at milestone close, most recent first:

| Category | Item | Status | Deferred At | Milestone |
|----------|------|--------|-------------|-----------|
| Documentation | 8K 提交内存耗尽进程死亡(可复现,WER 证据)——用户确认暂无 8K 测试条件,撤下 PERF-03 的 8K 分句;记录保留供将来支持 8K 时参考 | documented, no action planned | 2026-10-24 (user decision) | — |
| Native | Linux 运行期 GL 导入失败黑屏仅有 g_warning,无 Dart 事件(gl_interop.cc:296-321) | needs EventFn plumbing;超出 criterion 3 范围 | 2026-10-24 (Phase 3 close) | current |
| Visual | 重建控制器后首帧非黑帧(视觉属性) | owned by Phase 6 UAT/VERIFY-01 | 2026-10-24 (Phase 2 close) | current |
| Native evidence | 控制器 create/dispose 循环的 native 侧泄漏证据 | owned by Phase 6 real-plugin tests | 2026-10-24 (Phase 2 close) | current |

## Session Continuity

Last session: 2026-10-24T17:23:52.864Z
Stopped at: Completed 10-01-PLAN.md
Resume file: None

---
gsd_state_version: "1.0"
milestone: v3.0
milestone_name: 统一渲染生命周期与平台原生图形后端
current_phase: 12
current_phase_name: RenderBackend Seam
status: executing
stopped_at: Completed 12-01-PLAN.md
last_updated: "2026-10-26T06:13:52.395Z"
last_activity: 2026-10-26
last_activity_desc: Phase 12 execution started
state_head: fada55854cffe197b2fb2683fab39883e89d3f17
progress:
  total_phases: 6
  completed_phases: 0
  total_plans: 12
  completed_plans: 1
  percent: 0
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-10-26)

**Core value:** 以尽可能小的源码改动，换取可验证的稳定性与 4K/8K UHD 长时间满帧播放能力——不崩溃、不泄漏、不积压。
**Current focus:** Phase 12 — RenderBackend Seam

## Current Position

Phase: 12 (RenderBackend Seam) — EXECUTING
Plan: 2 of 12
Status: Ready to execute
Last activity: 2026-10-26 — Phase 12 execution started

Progress: [░░░░░░░░░░] 0%

## Performance Metrics

**Velocity:**
- Total plans completed: 25
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
| Phase 10 P02 | 7 min | 1 task | 4 files |
| Phase 10 P03 | 14 min | 2 tasks | 11 files |
| Phase 10 P07 | 10 min | 1 tasks | 7 files |
| Phase 12 P01 | 42 min | 3 tasks | 5 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [v3.0 Roadmap]: 阶段 12-17：12 RenderBackend 接缝（基线先行、纯重构）→ 13 macOS 路线 ADR → 14 Windows D3D11 ∥ 15 Linux OpenGL → 16 硬解零拷贝 → 17 回退加固 + UHD 回归；31/31 需求映射，无孤儿、无重复。
- [v3.0 Roadmap]: 硬约束——Windows 上 mpv_kit 自己的渲染链路禁止 ANGLE/EGL；D3D-02（Phase 14）把它变成 `pe_audit.py` CI 门禁，此后每个阶段都要保持为绿。
- [v3.0 Roadmap]: HWD-04（VideoToolbox 零拷贝）放在 Phase 13，使 macOS 成为完整切片；HWD-01/02/03/05 留在 Phase 16，HWD-05 是 Phase 17 CI 矩阵所用的断言基础。
- [v3.0 Roadmap]: auto 顺序「渲染器质量优先、图形 API 其次」；Windows auto 切到 D3D11 是 Phase 14 内的独立提交，CI 与 RTX 4060 均绿后才落地。
- [v3.0 Roadmap]: Phase 14/15/16 需要阶段研究（`--research-phase`）；12/13/17 为标准模式。
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
- [Phase 10]: The smoke pins the single local 3.47.8 SDK and gates identity before measuring (resolvedPath == MPV_KIT_LIBMPV_PATH, backend == vulkan); a mismatch is inconclusive, never an Impeller result.
- [Phase 10]: result=pass requires a supported non-black pixel probe (nonBlackRatio >= 0.01); a missing probe is inconclusive and a black frame is failed. Idle counts as a soak failure only after 500 ms of continuous texture mount.
- [Phase 10]: 10-03: Smoke classification is inconclusive (the 10-02 harness part-1 gate requires a resize event that only setSize produces), identity proven from the engine log; D-05 is unsettled and Phase 11 must settle it first.
- [Phase 10]: 10-03: ADR 0003 rejects the 'no ANGLE' slogan on 3.47.8; Phase 11 primary route is upstreaming the requirement, with the upgrade bypass as delivery vehicle and modified ANGLE as fallback.
- [Phase 10]: 10-07: soak abort is not-reproduced across soak-after-4k (5/5), soak (5/5) and a 25-round after-4k retry (all exit 0 with DIAG soak complete); Task 1 fails, Task 2 is not entered, and no speculative fix is applied
- [Phase 10]: 10-07: diag trace proven independently: writeAsStringSync flush:true, 25/25 and 5/5 round-end markers, 0 stage:complete lines in all diag logs, _classify untouched
- [Phase 12]: 12-01: Phase 12 push authorization is push-green-only (user, 2026-10-26); 12-07 Task 2 and 12-11 Task 1 RED commits must stop before push and ask the user
- [Phase 12]: 12-01: hosted CI gate is .planning/phases/12-renderbackend-seam/tools/ci_gate.sh; Flutter 3.47.8 prints 'N tests passed.' (no 'All tests passed!'), use 'tests passed\.[[:space:]]*$' for zero-skip success

### Pending Todos

None yet.

### Blockers/Concerns

- [v3.0] 唯一真机是 Windows x64 RTX 4060：硬解零拷贝、性能、4K 30 分钟、D-05 基线只能在本机证明；Linux GPU 与 macOS 硬件不可用，HWD-03/HWD-04 与 Linux 真驱动行为须如实标为「未验证」。
- [v3.0] 本地无 MSYS2/meson 工具链：Phase 14（SPIRV-Cross/shaderc/`-Dd3d11`、0010）与 Phase 15（`-Dgl -Degl`）的 bundle 改动只能经 CI 构建验证，规划时要把 CI 往返计入。
- [v3.0] D-05（10-05 soak 中止）仍未解释：Phase 12 第一个计划必须先修 harness 并在当前 Vulkan 路径取基线，不得假设中止已修复。
- （已缓解）宿主磁盘回升 ~6.3GB：本地构建恢复；4K 复验可执行。
- 新 CI 作业（patch-drift/pin-check/integration-test）首跑待 push。
- （v1 遗留）50-cycle Vulkan RSS 45.1 MiB 近门禁；8K 崩溃文档化。
- **v2.0 收尾遗留**：10-05 soak 中止未复现、未解释（3 次运行 5/5、5/5、25/25 均 exit 0）；D-05 未 settle；`10-VERIFICATION.md` 保持 `gaps_found`，ADR 0003 保持 `inconclusive`。

## Deferred Items

Items acknowledged and deferred at milestone close, most recent first:

| Category | Item | Status | Deferred At | Milestone |
|----------|------|--------|-------------|-----------|
| verification_gaps | 10/10-VERIFICATION.md | gaps_found (acknowledged, not resolved) | 2026-10-25 | v2.0 |
| Documentation | 8K 提交内存耗尽进程死亡(可复现,WER 证据)——用户确认暂无 8K 测试条件,撤下 PERF-03 的 8K 分句;记录保留供将来支持 8K 时参考 | documented, no action planned | 2026-10-24 (user decision) | — |
| Native | Linux 运行期 GL 导入失败黑屏仅有 g_warning,无 Dart 事件(gl_interop.cc:296-321) | needs EventFn plumbing;超出 criterion 3 范围 | 2026-10-24 (Phase 3 close) | current |
| Visual | 重建控制器后首帧非黑帧(视觉属性) | owned by Phase 6 UAT/VERIFY-01 | 2026-10-24 (Phase 2 close) | current |
| Native evidence | 控制器 create/dispose 循环的 native 侧泄漏证据 | owned by Phase 6 real-plugin tests | 2026-10-24 (Phase 2 close) | current |

### Quick Tasks Completed

| # | Description | Date | Commit | Directory |
|---|---|---|---|---|
| 261025-rkd | stream bridge cancel-after-close UAF, open leak, seek desync (0006) | 2026-10-25 | 5b58792 | .planning/quick\\261025-rkd-fix-0006-stream-bridge-native-bugs-in-native-mpv-stream-stre |
| 261025-rki | Mpv.dispose disposes child clients before terminating the core | 2026-10-25 | 609c6e9 | .planning/quick\\261025-rki-fix-dart-deadlock-when-the-main-mpv-is-disposed-while-child |
| 261025-rkj | stream bridge answers every claimed request; bounded open | 2026-10-25 | 7962c3f | .planning/quick\\261025-rkj-fix-dart-stream-bridge-requests-that-may-never-be-answered-p |
| 261025-rkm | hwdec-codecs default excludes ffv1 (mpv #18255) | 2026-10-25 | c126862 | .planning/quick\\261025-rkm-adjust-gpu-next-defaults-from-community-issues-without-publi |
| 261025-rke | propagate render target failures; validate render_vk; roll back timeline value | 2026-10-25 | ddbf2a8 | .planning/quick\\261025-rke-propagate-render-target-return-failures-and-validate-render |
| 261025-rkg | CoreAudio NULL guards (0007); WASAPI note vs upstream 4dfee61 | 2026-10-25 | ebf5a6e | .planning/quick\\261025-rkg-audio-patch-0007-fixes-add-null-guards-before-cfrelease-uid |
| 261025-rkl | 14 libplacebo backports onto v7.360.1 | 2026-10-25 | a7ba508 | .planning/quick\\261025-rkl-backport-libplacebo-fixes-onto-v7-360-1-in-native-build-deps |
| 261025-rkh | always use VK_QUEUE_FAMILY_EXTERNAL for shared images | 2026-10-25 | 12b5009 | .planning/quick\\261025-rkh-fix-unbalanced-vulkan-queue-family-ownership-transfer-on-eac |
| 261025-rkf | keep host ICC across option changes in gpu-next libmpv | 2026-10-25 | 13c130b | .planning/quick\\261025-rkf-fix-gpu-next-libmpv-state-bugs-in-vo-gpu-next-c-patch-0004-k |
| 261025-rkk | 0009 upstream backports (4 mpv commits) | 2026-10-25 | a2f7c0d | .planning/quick\\261025-rkk-add-native-patches-0009-upstream-backports-patch-with-upstre |

## Session Continuity

Last session: 2026-10-26T06:13:52.282Z
Stopped at: Completed 12-01-PLAN.md
Resume file: None
Archive: .planning/milestones/v2.0-ROADMAP.md · v2.0-REQUIREMENTS.md · v2.0-phases/

## Operator Next Steps

- Review the v3.0 roadmap (`.planning/ROADMAP.md`), then start Phase 12 with `/gsd-discuss-phase 12` (or `/gsd-plan-phase 12`)
- Phases 14/15/16 should be planned with `--research-phase`

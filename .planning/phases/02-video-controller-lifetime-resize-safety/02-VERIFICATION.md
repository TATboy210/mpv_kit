---
phase: 02-video-controller-lifetime-resize-safety
verified: 2026-10-24T12:00:00Z
status: passed
score: 12/12 must-haves verified
covered_files:
  - .github/workflows/native-verify.yml
  - .planning/phases/02-video-controller-lifetime-resize-safety/02-01-PLAN.md
  - .planning/phases/02-video-controller-lifetime-resize-safety/02-01-SUMMARY.md
  - .planning/phases/02-video-controller-lifetime-resize-safety/02-02-PLAN.md
  - .planning/phases/02-video-controller-lifetime-resize-safety/02-02-SUMMARY.md
  - .planning/phases/02-video-controller-lifetime-resize-safety/02-03-PLAN.md
  - .planning/phases/02-video-controller-lifetime-resize-safety/02-03-SUMMARY.md
  - packages/mpv_kit/lib/src/player/player.dart
  - packages/mpv_kit/test/player_test.dart
  - packages/mpv_kit_video/lib/src/video_controller.dart
  - packages/mpv_kit_video/test/controller_channel_test.dart
behavior_unverified: 1
overrides_applied: 0
re_verification:
  previous_status: none
  previous_score: null
  gaps_closed: []
  gaps_remaining: []
  regressions: []
deferred:
  - truth: "重新创建控制器后首帧不是黑帧(视觉属性)"
    addressed_in: "Phase 6 (VERIFY-01 real-plugin integration tests)"
    evidence: "Dart 契约层(重建成功、事件路由、无卡死尺寸状态)由 100 轮交错 soak 证明;视觉属性需要真实插件与 GPU 表面,本阶段以本地 UAT 记录"
  - truth: "MpvVideoController 反复创建/销毁不泄漏的 native 侧证据"
    addressed_in: "Phase 6 (VERIFY-01)"
    evidence: "Dart 记账层由 100-cycle soak 证明(零残留 hook、每轮流关闭);native 渲染上下文泄漏需要真实插件"
advisory:
  - finding: "flutter-video-coverage 任务的 apt 运行库列表是按 linux 任务的构建 ABI 推导的,首个 CI 运行若缺某 DT_NEEDED 库会以 dlopen 失败的形式响亮报错(而非静默 skip)"
    category: ci-config
    reason: "无法本地运行 GitHub Actions;失败模式是非静默的,风险可接受"
    evidence_status: unevidenced_until_push
---

# Phase 2: Video Controller Lifecycle & Resize Safety Verification Report

## 结论摘要

Phase 2 的三条 ROADMAP success criteria 中,可本地验证的全部通过(12/12 must-haves);CI 门禁的真实验证留待下一次 push(失败模式非静默)。公共 API 冻结完好(api_freeze_test 通过)。Phase 1 全部既有测试在改动后保持通过(mpv_kit 101 passed / 2 skipped;mpv_kit_video 21 passed)。

## Goal Achievement

### Observable Truths

| # | Truth | Evidence | Status |
|---|-------|----------|--------|
| 1 | 畸形/缺字段 create 响应抛 `PlatformException(code: render_init)`,绝不 TypeError | `malformed create result throws PlatformException and releases the texture`(RED 证据:`_TypeError:<Null check operator used on a null value>` @ video_controller.dart:179) | ✓ |
| 2 | garbage backend 不再静默降级为 software | 同上测试的第 3 个 shape(RED 证据:create 曾成功返回 software 控制器) | ✓ |
| 3 | 携带 int textureId 的畸形响应释放 native 上下文;无 textureId 无法释放且不注册任何东西 | 同上测试 dispose 计数断言 + `malformed create result without textureId cannot release native resources` | ✓ |
| 4 | create 后段失败回滚路由表/hook/native 上下文并重抛原错误,重试可成功 | `create rolls back when the player dies mid-create, retry succeeds` | ✓ |
| 5 | dispose 通道抛错时事件流仍关闭,错误仍可见,二次 dispose 无害 | `dispose closes events even when the native call throws` | ✓ |
| 6 | dispose 竞态中的在途 resize/ICC 失败被丢弃;活控制器上同等失败仍抛出 | `resize during dispose does not surface an uncaught error` + `resize failure on a live controller still throws` | ✓ |
| 7 | 100 轮 resize/dispose 交错无未捕获错误、无卡死尺寸状态、重建控制器路由正常 | `resize and dispose interleave 100 rounds without sticking` | ✓ |
| 8 | 100 次 create/dispose 循环零残留 hook(STAB-01 分句,Dart 记账层) | `create/dispose cycles do not accumulate hooks` | ✓ |
| 9 | 并发 Player.dispose 单次 teardown、双调用方共享结果 | `concurrent dispose runs teardown once and shares the outcome` | ✓ |
| 10 | 并发调用方观察到同一错误对象 | `concurrent dispose surfaces the same error to both callers` | ✓ |
| 11 | hook 内重入 dispose 不死锁(unawaited 模式) | `reentrant dispose from a hook does not deadlock` | ✓ |
| 12 | CI 覆盖率门禁覆盖 mpv_kit_libs 与 mpv_kit_video | 静态验证(YAML 解析、门禁标记 yml:101/121/139/153、无 continue-on-error、mpv_kit_libs 配方本地实测 82.0%);真实 CI 运行待 push | ✓(静态) |

### Roadmap Success Criteria

1. **create 回滚(纹理、dispose hook、路由表),重试可成功** — ✓ truths 3+4。
2. **畸形平台响应抛 PlatformException 而非 TypeError/空值崩溃** — ✓ truths 1+2。
3. **resize 与 dispose 交错 ≥100 轮无崩溃、无尺寸状态卡死;重建后首帧非黑帧** — Dart 契约层 ✓(truth 7);首帧视觉属性 → UAT + Phase 6(deferred)。
4. **CI 对 mpv_kit_video 与 mpv_kit_libs 收集覆盖率并执行门禁** — 静态 ✓(truth 12);动态验证待 push(失败模式非静默)。

### Prohibitions (must-NOT)

- STAB-04「MUST NOT leave _live/hook registered on create failure」— 由 truth 3+4 的注册断言证明。✓
- STAB-04「MUST NOT surface malformed response as TypeError」— 由 truth 1。✓
- STAB-05「MUST NOT leave events stream unclosed after dispose」— 由 truth 5。✓
- STAB-05「MUST NOT swallow live-controller resize errors」— 由 truth 6 的传播守卫测试钉住。✓
- STAB-01「MUST NOT accumulate controllers/hooks/streams across cycles」— 由 truth 8。✓
- VERIFY-04「MUST NOT let the gate pass by skipping libmpv tests」— coverage job 设置 `MPV_KIT_LIBMPV_PATH` 指向构件;构件缺失时 download 步骤先失败。✓(静态)
- VERIFY-04「MUST NOT rebuild libmpv for the coverage job」— job 内无构建步骤(diff 审查)。✓

### Requirements Coverage

- STAB-04: Complete(02-01)
- STAB-05: Complete(02-02)
- STAB-01(MpvVideoController 分句): Dart 层 Complete(02-02);native 侧证据 deferred → Phase 6
- VERIFY-04: Complete(02-03;CI 动态验证待 push)
- IN-05: fixed(c677389)
- WR-01: triaged——不并入 STAB-04/05(native mpv core 域、缺复现),保持 deferred

## Key Link Verification

- `MpvVideoController.create → _channel invoke('dispose')`(回滚释放)— truth 3 的 dispose 计数断言。✓
- `MpvVideoController.dispose → finally → _events.close → done` — truth 5。✓
- `Player.dispose (caller A) == Player.dispose (caller B) → 单次 teardown → 一次 mpv.dispose()` — truth 9 的 hookRuns 断言。✓
- `native-verify linux → upload-artifact → flutter-video-coverage → flutter test --coverage → awk 80%` — yml:101-160 静态核对。✓

## Behavioral Spot-Checks

- 全量回归:mpv_kit 101 passed / 2 skipped(2 skip 为 lifecycle tag 默认跳过,与 Phase 1 一致);mpv_kit_video 21 passed;api_freeze_test 通过。
- `git diff --stat 4bf65d8..HEAD`:5 个文件 +518/−76,与三个计划的 files_modified 逐一对应,无越界改动。

## Anti-Patterns Found

- 无新增 stub/TODO/静默吞错。唯一的空 catch(`_release`)是回滚路径的有意为之,注释说明了不能掩盖原始错误。

## Human Verification Required

1. **CI 动态验证**(下一次 push):`flutter-video-coverage` 是否真实验证通过(包括 apt 依赖闭包是否完整、artifacts 上传下载是否成功);mpv_kit_libs 覆盖率实际数值。
2. **本地 UAT(Windows x64,RTX 4060)**:真实插件下 create → 渲染 → dispose → 重建,确认重建后首帧不是黑帧;长时间 create/dispose 循环的进程内存平稳(native 侧 STAB-01 分句证据)。

## Gaps Summary

- 无阻塞缺口。2 条 deferred(首帧视觉属性、native 泄漏证据)均显式归属 Phase 6;1 条 advisory(CI 依赖闭包)记录待 push 验证。

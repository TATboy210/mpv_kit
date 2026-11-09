---
phase: 03-error-surfacing
verified: 2026-10-24T15:00:00Z
status: passed
score: 13/14 must-haves verified
covered_files:
  - .planning/phases/03-error-surfacing/03-01-PLAN.md
  - .planning/phases/03-error-surfacing/03-01-SUMMARY.md
  - .planning/phases/03-error-surfacing/03-02-PLAN.md
  - .planning/phases/03-error-surfacing/03-02-SUMMARY.md
  - .planning/phases/03-error-surfacing/03-03-PLAN.md
  - .planning/phases/03-error-surfacing/03-03-SUMMARY.md
  - .planning/phases/03-error-surfacing/03-04-PLAN.md
  - .planning/phases/03-error-surfacing/03-04-SUMMARY.md
  - packages/mpv_kit/lib/src/core/stream_bridge.dart
  - packages/mpv_kit/lib/src/core/mpv.dart
  - packages/mpv_kit/lib/src/player/player.dart
  - packages/mpv_kit/lib/src/ffi/library.dart
  - packages/mpv_kit/lib/src/core/events.dart
  - packages/mpv_kit_video/lib/src/video_controller.dart
  - packages/mpv_kit_video/windows/d3d11_interop.h
  - packages/mpv_kit_video/windows/d3d11_interop.cpp
  - packages/mpv_kit_video/macos/Classes/metal_interop.h
  - packages/mpv_kit_video/macos/Classes/metal_interop.mm
  - packages/mpv_kit_video/src/video_renderer.h
  - packages/mpv_kit_video/src/video_renderer.cc
  - packages/mpv_kit/test/failure_injection_test.dart
  - packages/mpv_kit/test/mpv_test.dart
  - packages/mpv_kit/test/library_test.dart
  - packages/mpv_kit/test/api_freeze_test.dart
behavior_unverified: 1
overrides_applied: 0
re_verification:
  previous_status: none
  previous_score: null
  gaps_closed: []
  gaps_remaining: []
  regressions: []
deferred:
  - truth: "Linux 运行期 GL 导入失败(gl_interop.cc:296-321 黑屏仅 g_warning)的 Dart 侧事件"
    addressed_in: "Later insertion (needs an EventFn plumbed into GLInterop); outside criterion 3's create-time/device-failure scope"
    evidence: "CONCERNS.md retains the entry; create-time probe reasons on Linux already flow via gl_reason_"
  - truth: "真实设备失败(D3D11CreateDevice 失败/无 Metal 设备)下的 reason 文案"
    addressed_in: "Local UAT (Windows RTX 4060) + Phase 6 real-plugin tests"
    evidence: "Windows 原生编译通过;失败路径无法在 CI 强制"
advisory:
  - finding: "Player._bind 的 onError/解析捕获路径是防御性的——Player 的全部绑定属性名都有效,mpv 对未知属性名的 observe 也返回成功,触发不可达"
    category: test-coverage
    reason: "机制已接线并由源级审查确认;raw 层的排空存活测试证明其所喂的泵不会中断"
    evidence_status: mechanism_verified_trigger_defensive
---

# Phase 3: Error Surfacing Verification Report

## 结论摘要

Phase 3 的四条 ROADMAP success criteria 全部达成:可本地验证的 13/14 must-haves 通过测试/编译证明;1 条(Player._bind 触发路径)为防御性机制,以源级审查 + 排空存活测试证明。OBS-01~04 全部 Complete,WR-02 与 IN-02 关闭。公共 API 冻结完好(api_freeze 通过,含 3 个文档化接缝:onSourceError 基线条目、ignoredOptionsForTesting seam、既有两个 ForTesting)。

## Goal Achievement

### Observable Truths

| # | Truth | Evidence | Status |
|---|-------|----------|--------|
| 1 | open 失败:Player.errors 收到原始身份(类型+消息),播放以明确错误结束 | `a source whose open throws surfaces the original error on Player.errors` | ✓ |
| 2 | read 失败:同上(Phase 1 语义不变) | `a source whose read throws reports an MpvPlaybackError` | ✓ |
| 3 | seek 失败(含探测 seek):上抛原始身份且不终止播放 | `a source whose seek throws leaves the open contained` | ✓ |
| 4 | close 失败:全路径包含 + 可观测 | close 系列两个测试 | ✓ |
| 5 | 桥的 mpv 侧错误码与 demuxer 语义不变 | Phase 1 失败注入套件全部原样通过 | ✓ |
| 6 | 排空存活:坏事件/抛错监听器后,后续事件继续派发 | `a throwing observer listener does not abort the drain` | ✓ |
| 7 | 被弃 reply future 不产生未处理异步错误(5 个完成点全布防) | `an abandoned async command error does not become an unhandled error` | ✓ |
| 8 | errorString/eventName dispose 后可用 | `errorString and eventName work after dispose (IN-02)` | ✓ |
| 9 | Windows 回退原因诚实化(HRESULT 等 3 路径) | 源级标记 + Windows 原生编译通过 | ✓ |
| 10 | macOS 无 Metal 原因;Linux 探测原因既有流转复核确认 | 源级审查 | ✓ |
| 11 | CreateImage null 设备守卫 | grep `if (!device_) return false` | ✓ |
| 12 | 未知选项记录 + create 不抛;invalid value 仍响亮 | `an unknown option at create is recorded…` + `an invalid option value still fails create loudly` | ✓ |
| 13 | 库解析回落可观测(resolvedPath/lastOpenAttempts/警告) | library_test 3 项 | ✓ |
| 14 | Player._bind 的观察/解析失败路由 Player.errors | 机制接线源级审查;触发防御性不可达 | ✓(机制) |

### Roadmap Success Criteria

1. **流源 open/read/seek 失败出现在 Player.errors,保留原始异常类型与消息,播放侧以明确错误结束** — ✓ truths 1-3(open/read 以错误结束;seek 按语义不结束,已文档化)。
2. **属性观察失败或解析失败出现在 Player.errors,测试中不再出现未捕获异步错误** — ✓ truths 6-8、14(未捕获仅剩用户自己监听器抛错的 Dart 标准行为,已钉住并文档化)。
3. **Vulkan→software 回退与 D3D11 设备失败产生带可读 reason 的事件** — ✓ truths 9-11(既有 reason→softwareFallback 事件通道携带诚实文案)。
4. **不支持的选项或拼写错误会被记录/暴露,同时 create 保持向后兼容** — ✓ truths 12-13。

### Prohibitions (must-NOT)

- OBS-01「MUST NOT change demuxer-facing codes」— Phase 1 套件原样通过。✓
- OBS-01「MUST NOT introduce uncaught async errors while reporting」— `_report` 消费者守卫 + 注入套件全绿。✓
- OBS-02「MUST NOT abort the drain」— 排空存活测试。✓
- OBS-02「MUST NOT fabricate state values」— 解析失败保持旧值(实现审查 + 设计注释)。✓
- OBS-03「MUST NOT change backend selection」— 仅 reason 字符串;example 编译 + Dart 套件回归。✓
- OBS-04「MUST NOT make create throw for optionNotFound / not swallow invalid values」— 两个专项测试。✓
- VERIFY「api freeze」— 通过;新增面:onSourceError(基线)、ignoredOptionsForTesting(seam)、MpvLibrary 静态(枚举外)、Mpv.create 签名(枚举豁免)。均已文档化。✓

## Key Link Verification

- `StreamBridge._report → onSourceError → Mpv.onSourceError → Player._reportSourceError → Player.errors` — truths 1-4。✓
- `_onWakeup containment → observer.addError → Player._bind onError → Player.errors` — truth 6/14。✓
- `interopReason() → backend_reason_ → create response → softwareFallback 事件` — truths 9-10(Windows 编译 + 通道既有验证)。✓
- `optionNotFound swallow → ignoredOptionsForTesting + developer.log` — truth 12。✓

## Behavioral Spot-Checks

- 全量:mpv_kit 111 passed / 2 skipped;mpv_kit_video 21 passed;双包 analyzer 零输出;api_freeze 通过。
- `git diff 06e5718..6c621ea`:13 个文件,与四个计划 files_modified 一致,无越界。

## Anti-Patterns Found

- 一处 `// ignore: close_sinks`(mpv.dart 解码路径局部)——误报,注释说明控制器生命周期归属;无新增 stub/TODO。

## Human Verification Required

1. 本地 UAT(Windows x64,RTX 4060):真实设备失败/无 Vulkan 环境下的回退 reason 文案;真实插件下流源错误到 UI 的端到端可见性。
2. Phase 6:Linux/macOS 真实 runner 上的相同验证。

## Gaps Summary

- 无阻塞缺口。2 条 deferred(Linux GL 运行期导入、真实设备失败文案)显式归属后续;1 条 advisory(Player._bind 触发防御性)记录在案。

---
phase: 01-player-lifetime-dispose-safety
verified: 2026-10-24T01:28:42Z
status: passed
score: 28/28 must-haves verified
covered_files:
  - .github/workflows/native-verify.yml
  - .planning/phases/01-player-lifetime-dispose-safety/01-01-PLAN.md
  - .planning/phases/01-player-lifetime-dispose-safety/01-01-SUMMARY.md
  - .planning/phases/01-player-lifetime-dispose-safety/01-02-PLAN.md
  - .planning/phases/01-player-lifetime-dispose-safety/01-02-SUMMARY.md
  - .planning/phases/01-player-lifetime-dispose-safety/01-03-PLAN.md
  - .planning/phases/01-player-lifetime-dispose-safety/01-03-SUMMARY.md
  - .planning/phases/01-player-lifetime-dispose-safety/01-04-PLAN.md
  - .planning/phases/01-player-lifetime-dispose-safety/01-04-SUMMARY.md
  - .planning/phases/01-player-lifetime-dispose-safety/01-05-PLAN.md
  - .planning/phases/01-player-lifetime-dispose-safety/01-05-SUMMARY.md
  - packages/mpv_kit/analysis_options.yaml
  - packages/mpv_kit/dart_test.yaml
  - packages/mpv_kit/lib/src/core/mpv.dart
  - packages/mpv_kit/lib/src/core/stream_bridge.dart
  - packages/mpv_kit/lib/src/player/player.dart
  - packages/mpv_kit/test/api_freeze_test.dart
  - packages/mpv_kit/test/failure_injection_test.dart
  - packages/mpv_kit/test/lifecycle_test.dart
  - packages/mpv_kit/test/mpv_test.dart
  - packages/mpv_kit/test/player_test.dart
covered_digest: "v3:sha256:99ef5c5b7dbb5e8ea54efb76910996d17f954d30a50885bd339246e1699bb6a3"
behavior_unverified: 0
overrides_applied: 0
re_verification:
  previous_status: human_needed
  previous_score: 19/23
  gaps_closed:
    - "read/seek/close 流源失败注入真值：在可解析依赖的 patched libmpv 上实际执行并全部通过（7 passed / 0 skipped）"
    - "failure-injection 与 lifecycle 两条显式 CI 调用真值：本地复跑命令证明可稳定通过，CI 接线静态确认"
  gaps_remaining: []
  regressions: []
deferred:
  - truth: "STAB-01 中“MpvVideoController 反复创建/销毁不泄漏”的分句"
    addressed_in: "Phase 2"
    evidence: "ROADMAP Phase 2 需求 STAB-04（create 失败回滚）与 STAB-05（resize/dispose 并发）；本阶段五个 PLAN 均未修改 packages/mpv_kit_video/。"
  - truth: "MpvLibrary.open() 在显式 MPV_KIT_LIBMPV_PATH 加载失败时静默回退到平台默认库，调用方无法得知实际加载的是哪一个 libmpv"
    addressed_in: "Phase 3"
    evidence: "ROADMAP Phase 3 需求 OBS-04（不支持的选项或失败不再完全静默）。packages/mpv_kit/lib/src/ffi/library.dart:52-68 按候选顺序尝试，显式路径失败后继续尝试 defaultNames，只有全部候选失败才抛 MpvLibraryNotFound。这是可观测性缺陷，不属于本阶段 must-have，不阻塞本阶段。"
advisory:
  - finding: "Mpv._closeIfOpen 的 microtask 重试本身没有再包 try/on StateError（GC-IN-01 / 评审 IN-01）"
    category: other
    reason: "标准事件循环下 microtask 只在同步派发退栈后运行，当前调用点不可达；只有同步执行 microtask 的自定义 zone 或第二条重入派发才可能触发。本轮回归测试与 1000 次 soak 均通过，无运行时复现证据。已记录为 deferred，不阻塞本阶段。"
    evidence_status: "none provided"
---

# Phase 1: Player Lifetime & Dispose Safety Verification Report

**Phase Goal:** `Player` 在反复创建/销毁与异常 teardown 下都不泄漏、不崩溃，dispose 之后的调用可预测地失败。
**Verified:** 2026-10-24T01:28:42Z
**Status:** passed
**Re-verification:** Yes — 在更正上一版的环境前提后重新完整验证

## 结论摘要

- **上一版的核心环境前提是错的，本轮已更正。** `bt/libmpv-2.dll` 并非 stock 构建：`python -I tools/rea_abi_audit/pe_audit.py --dump bt/libmpv-2.dll` 列出了真实导出 `mpv_kit_stream_add`、`mpv_kit_stream_begin`、`mpv_kit_stream_complete`、`mpv_kit_stream_shutdown`。它此前“加载失败”是因为依赖 DLL（avcodec/avformat/…）不在 Windows 进程搜索路径，`MpvLibrary.open()` 吞掉失败后退回到 PATH 上的 stock `libmpv-2.dll`，于是 `providesSymbol` 为 false、测试自我 skip。
- **依赖可解析后，全部环境门控测试真实执行并通过。**
  - `PATH=/d/mpv_kit/bt:$PATH MPV_KIT_LIBMPV_PATH=D:/mpv_kit/bt/libmpv-2.dll dart test -t failure-injection test/failure_injection_test.dart` → **7 passed，0 skipped**。
  - `dart test`（默认全量） → **98 passed，2 skipped，0 failed**。两个 skip 均为设计行为：`lifecycle` tag 默认 skip，以及 `MPV_KIT_FORMAT_SAMPLES` 未设置。
  - `dart test test/lifecycle_test.dart -t lifecycle --run-skipped` → **1 passed（5 s）**。
  - `dart test test/api_freeze_test.dart` → **1 passed**。
- **上一版记录的“5 个 `stream_bridge_test.dart` 既有失败”基线不再成立**：本次全量运行 0 failed，该说法已废弃，不作为回归基线。
- **阶段目标在真实 libmpv 上成立。** 1000 次 create/dispose 后所有状态流收到 `done`、RSS 增量受 64 MiB 约束；抛错的 dispose hook 不阻止核心销毁；从同步 `Mpv.events` 监听器内重入 `dispose()` 不再抛错；dispose 后 31 个公共 `Mpv` 入口全部抛 `StateError` 且 native-entry 计数不增长；read/seek/close 三类异常流源均被兜住且 10 秒内完成 dispose。
- **公共 API 未变化。** `api_freeze_test.dart` 通过；直接比对 `59e9bdf..HEAD` 的 lib diff，除两个 `@visibleForTesting` seam（`Mpv.nativeEntriesForTesting`、`Player.stateStreamsForTesting`）外，只有表达式体改为块体以插入 `_ensureAlive()`/守卫，签名未变。
- **无 BLOCKER、无 STUB、无 NOT_WIRED 关键链接、无债务标记。** `01-SECURITY.md` 的 `threats_open: 0` 与本轮证据一致。

## 环境前提更正（上一版错误）

| 项 | 上一版结论 | 本轮实测 |
|---|---|---|
| 本地 libmpv 是否含 patch 0006 | “stock，缺 `mpv_kit_stream_add`” | **错误。** `pe_audit.py --dump bt/libmpv-2.dll` 列出四个 `mpv_kit_stream_*` 导出 |
| 为何测试 self-skip | “环境限制，patched 不可用” | `MpvLibrary.open()` 在显式 DLL 因依赖不在搜索路径而加载失败后，静默回退到 PATH 上的 stock 库 |
| failure-injection | 4 passed / 3 skipped | **7 passed / 0 skipped** |
| 全量默认套件 | 90 passed / 5 skipped / 5 failed | **98 passed / 2 skipped / 0 failed** |
| lifecycle soak | 1 passed | **1 passed（5 s）** |

因此，上一版标记为 `⚠️ PRESENT_BEHAVIOR_UNVERIFIED` 的四条真值，本轮按实际观测证据重新分类为 `✓ VERIFIED`。

## Goal Achievement

### Observable Truths

| # | Truth | 来源 | Status | Evidence |
|---|-------|------|--------|----------|
| 1 | 抛错的 dispose hook 不阻止 `Player.dispose()` 到达 `mpv.dispose()`（`mpv_terminate_destroy`） | 01-01 / SC2 | ✓ VERIFIED | `player_test.dart` throwing-hook 测试通过；`player.dart:655-665` 的 `stage()` 逐阶段隔离后无条件执行 `mpv.dispose()` |
| 2 | 每个 Player 状态流（含 `position`、`decodeWarning`）在 dispose 时发出 `done` | 01-01 / SC1 | ✓ VERIFIED | `player.dart:204-206` 登记；`:670-672` 逐条关闭；throwing-hook 测试与 1000 次 soak 均观察到 `done` |
| 3 | `Player.dispose()` 在全部 teardown 步骤跑完后暴露 hook 错误；第二次 dispose 正常 | 01-01 / SC2 | ✓ VERIFIED | 测试断言 `throwsA(same(sentinel))`、`mpv.isDisposed`、再次 `dispose()` 无异常（`player_test.dart:236-258`） |
| 4 | `Mpv.dispose()` 在终止前置空 wakeup 回调，核心销毁后才关闭 `NativeCallable` | 01-01 | ✓ VERIFIED | `mpv.dart:196` null callback → `:202` terminate/destroy → `:203` `_wakeup.close()`；顺序正确 |
| 5 | `Mpv.events` 与每个 `observeProperty` 流在 dispose 时发出 `done`；dispose 后监听的流不进入 native | 01-01 | ✓ VERIFIED | `mpv_test.dart` 的 events/observer 关闭测试与 late-listen 测试通过；`mpv.dart:464-488`、`:215-219` |
| 6 | dispose 后每个能触达 native 的公共 `Mpv` 方法抛 `StateError` | 01-02 / SC3 | ✓ VERIFIED | `mpv_test.dart:223-277` 的 31 条调用表全部 `throwsStateError` |
| 7 | 被拒绝的 post-dispose 调用不增加 native-entry 计数，证明未进入 FFI | 01-02 / SC3 | ✓ VERIFIED | 同一测试先证明 live 调用使计数增长，再断言整表调用后计数不变（`mpv_test.dart:228-282`） |
| 8 | dispose 前创建、dispose 后监听的 `observeProperty` 流以 `StateError` 失败且不进入 native | 01-02 | ✓ VERIFIED | `mpv_test.dart:283-298`，监听前后 `nativeEntriesForTesting` 不变 |
| 9 | 相同方法在 live handle 上的既有行为不变 | 01-02 | ✓ VERIFIED | 全量 `dart test` 98 passed；live `getProperty` 使计数器增长 |
| 10 | 公共 API 冻结为 pre-phase baseline + 两个带注解的测试 seam | 01-02 | ✓ VERIFIED | `api_freeze_test.dart` 1/1 passed；`git diff 59e9bdf..HEAD -- packages/mpv_kit/lib` 显示仅新增 `nativeEntriesForTesting` 与 `stateStreamsForTesting`，其余为表达式体→块体 |
| 11 | 抛错的 observer/events/Player-state 监听器不中断投递，后一个监听器仍收到值，异常以 zone error 出现 | 01-03 / SC4 | ✓ VERIFIED | failure-injection 三条监听器测试通过（`runZonedGuarded` 收集器） |
| 12 | 抛错的 dispose hook 不阻止后续 hook 运行或核心销毁 | 01-03 / SC2 | ✓ VERIFIED | `failure_injection_test.dart` 的 `throwing dispose hook does not skip later hooks or the core` 通过 |
| 13 | 抛错 read 的流源经 `Player.errors` 暴露 `MpvPlaybackError`，10 s 内 dispose；计数器必须先前进 | 01-03 / 01-05 / SC4 | ✓ VERIFIED | patched 环境实际执行：`readAttempts > 0`，`playbackError.message` 非空，dispose ≤10 s，zone errors 为空 |
| 14 | 抛错 seek 的流源使 open 干净完成/失败，10 s 内 dispose；`seekAttempts > 0` | 01-03 / 01-05 / SC4 | ✓ VERIFIED | patched 环境实际执行：先等待 demuxer 读取，再显式 `seek(2 s)`，`seekAttempts > 0`，无未捕获错误 |
| 15 | 抛错 close 的流源在四条路径上被兜住，不逃逸为未处理异步错误，dispose 不挂起 | 01-03 / SC4 | ✓ VERIFIED | patched 环境实际执行：`_opClose`、`shutdown()`/`StreamBridge.close()`、`_handleOpen` shutdown 分支全部覆盖；两个 zone-error 列表为空，`closeAttempts > 0` |
| 16 | 1000 次 create/dispose 后每个 Player 状态流收到 `done`，进程 RSS 有界；RSS 窗口来自隔离的调用 | 01-03 / SC1 | ✓ VERIFIED | `lifecycle_test.dart` 显式运行 1 passed（5 s）；20 次预热后做 1000 次循环，断言 RSS 增量 < 64 MiB 与 `isDisposed` |
| 17 | lifecycle soak 默认被 tag skip、只由显式 `--run-skipped` 运行；两个 tag 在 CI 显式调用 | 01-03 | ✓ VERIFIED | 全量运行 JSON 恰有 lifecycle tag 的 `skip:true`；显式运行 1 passed；`native-verify.yml:97-98` 两条调用命中 |
| 18 | 从同步 `Mpv.events` 监听器内重入 `Mpv.dispose()` 不抛错、5 s 内收到 `done`、`isDisposed` 为 true | 01-04 | ✓ VERIFIED | `mpv_test.dart:300-322` 回归测试通过；独立运行时 `done` completer 只能经 retry 分支完成 |
| 19 | `_events` 与全部 observer 控制器经同一 dispatch-safe helper 关闭，派发中的 close 在退栈后重试 | 01-04 | ✓ VERIFIED | `mpv.dart:215-217`（observers）与 `:219`（events）均调用 `_closeIfOpen`；`:683-692` 实现 |
| 20 | 普通关闭保证仍成立：events/observer 流发 `done`，第二次 dispose 是 no-op | 01-04 | ✓ VERIFIED | `mpv_test.dart` 的 `dispose closes Mpv.events and observer streams`、`dispose is idempotent` 通过 |
| 21 | dispose 后首次读取 `audioDevices` 得到已关闭、值为空且未登记进 `_states` 的状态；API 不变 | 01-04 | ✓ VERIFIED | `player_test.dart:260-272` 通过；`player.dart:343-357` 的 `_disposed` 分支 `unawaited(state._close())` 且不注册 |
| 22 | `Player._onEvent` 的 `EndFileEvent(reason: error)` 仅在 `_errors` 未关闭时写入 | 01-04 | ✓ VERIFIED（源码不变量） | `player.dart:721-732` 的 `if (!_errors.isClosed)`，与相邻 `_logs` 分支一致；当前 dispose 顺序下该分支运行时不可达，故以源码门禁为证 |
| 23 | read 失败注入测试在接受 `MpvPlaybackError` 前证明 `readAttempts > 0` | 01-05 | ✓ VERIFIED | `failure_injection_test.dart:354-358`；patched 环境实际执行通过 |
| 24 | seek 失败注入测试证明 `_handleSeek` 运行（`seekAttempts > 0`），源提供合法内存 WAV | 01-05 | ✓ VERIFIED | `failure_injection_test.dart:365-392`；`_silentWavBytes` + 显式 seek + `seekAttempts > 0`，实际执行通过 |
| 25 | CI 的 lifecycle 调用点名 `test/lifecycle_test.dart`，措辞只声明文件级隔离 | 01-05 | ✓ VERIFIED | `native-verify.yml:98`；`dart_test.yaml`、`lifecycle_test.dart` 头注释一致 |
| 26 | 默认 `dart test` 仍经 tag 默认跳过 soak，显式文件级调用仍执行 | 01-05 | ✓ VERIFIED | 全量运行 2 skip（lifecycle + format matrix）；显式运行 1 passed |
| 27 | `api_freeze_test.dart` 无文件级 analyzer-ignore；VM-only 排除在 `analysis_options.yaml`；测试仍编译并运行 | 01-05 | ✓ VERIFIED | `grep ignore_for_file` = 0；`analysis_options.yaml:4-11` 的 `analyzer.exclude`；`api_freeze_test.dart` 1/1 passed |
| 28 | 每条评审发现均已处置：六个 fixed、四个 deferred（含理由与 owner）、零 open | 01-05 | ✓ VERIFIED | `01-REVIEW-DISPOSITION.md` 主表 + gap-closure 表；无 `open` 行 |

**Score:** 28/28 truths verified（0 present-behavior-unverified；0 failed）

### Roadmap Success Criteria

| SC | 内容 | Status | Evidence |
|----|------|--------|----------|
| SC1 | ≥1000 次 create/dispose 后所有状态流收到 `done`，native 句柄与进程内存平稳 | ✓ VERIFIED | truth 2、16；soak 1 passed，RSS < 64 MiB |
| SC2 | 任一 dispose hook 抛错时仍完成 `mpv_terminate_destroy`、关闭全部流、错误可见、再次 dispose 无副作用 | ✓ VERIFIED | truth 1、3、12、20 |
| SC3 | dispose 后任意 `Mpv` 公共方法抛 `StateError`，且证明未进入 native | ✓ VERIFIED | truth 6、7 |
| SC4 | 失败注入回归测试进入 CI：抛错 hook/listener 与异常流源稳定复现并通过 | ✓ VERIFIED | truth 11-15、17、23、24；本地 7/7 通过 + `native-verify.yml:97-98` 显式调用 |

### Prohibitions (must-NOT)

计划中的 prohibitions 均声明为 `verification: null`，未指定 `test`/`judgment` 层级；本轮逐条以实际代码与已执行测试核对，全部未被违反：

| Prohibition | Status | Evidence |
|---|---|---|
| dispose 失败不得以崩溃/挂起方式暴露，也不得掩盖 hook 原始错误 | ✓ NOT VIOLATED | `throwsA(same(sentinel))`；进程未挂起；后续阶段继续执行 |
| dispose 后不得留下未关闭的 state/observer 流（含非标准绑定路径） | ✓ NOT VIOLATED | 1000 次 soak 对 35 条 seam 流 + errors/logs 断言 `done` |
| 任一步骤或监听器异常不得跳过 native 核心销毁 | ✓ NOT VIOLATED | throwing-hook 与 reentrant-dispose 测试均断言 `isDisposed` |
| 不得让公共调用触达已销毁的 `mpv_handle`，含 dispose 前创建的 observer 流 | ✓ NOT VIOLATED | 31 调用表 + late-listen + native-entry 计数 |
| 不得以其他失败类别替代原始崩溃；post-dispose 必须是可捕获的 `StateError`，不是静默 no-op | ✓ NOT VIOLATED | 全部 `throwsStateError` |
| libmpv 不可用时不得让 failure-injection 静默 skip | ✓ NOT VIOLATED | 顶层 `MpvLibrary.open()` 在库不可用时抛错 → 文件加载失败 → job 失败；patch 缺失时才显式 skip |
| 不得把进程级 RSS 阈值 soak 放进共享进程窗口 | ✓ NOT VIOLATED | `lifecycle` tag 默认 skip；CI 文件级调用只加载该文件 |
| 重入 dispose 时不得留下 `Mpv.events`/observer 流未关闭 | ✓ NOT VIOLATED | truth 18/19 |
| 派发期间的 close 不得以异常逃逸或跳过后续 teardown | ✓ NOT VIOLATED | `_closeIfOpen` + 回归测试 |
| 不得为修复生命周期而改变公共 API 或新增公开成员 | ✓ NOT VIOLATED | api-freeze + 直接 diff |
| 失败注入测试不得在未证明被测路径执行时通过 | ✓ NOT VIOLATED | read/seek 均先断言计数器 |
| 不得让评审发现与“被遗忘”不可区分 | ✓ NOT VIOLATED | 六 fixed、四 deferred、零 open |

### Deferred Items

| # | Item | Addressed In | Evidence |
|---|------|-------------|----------|
| 1 | STAB-01 的 `MpvVideoController` 反复 create/dispose 不泄漏分句 | Phase 2 | ROADMAP Phase 2 需求 STAB-04/STAB-05；本阶段未修改 `packages/mpv_kit_video/` |
| 2 | `MpvLibrary.open()` 在显式 `MPV_KIT_LIBMPV_PATH` 失败时静默回退到平台默认库 | Phase 3 (OBS-04) | `library.dart:52-68` 按候选顺序回落；失败不可见。可观测性缺陷，不属于本阶段 must-have，不阻塞本阶段 |

### Advisory (New Scope, Unevidenced)

| # | Finding | Category | Why Advisory |
|---|---------|----------|--------------|
| 1 | `Mpv._closeIfOpen` 的 microtask retry 未再包 `try/on StateError`（GC-IN-01 / IN-01） | other | 标准事件循环下 retry 在同步派发退栈后运行，当前调用点不可达；无运行时复现证据。已记录 deferred |

## Required Artifacts

| Artifact | Expected | Status | Details |
| -------- | -------- | ------ | ------- |
| `packages/mpv_kit/lib/src/core/mpv.dart` | dispose 顺序、dispatch-safe 关闭助手、`_ensureAlive` 全入口守卫、late-listen 守卫 | ✓ VERIFIED | 734 行；`dispose` `:188-220`；`_closeIfOpen` `:683-692`；`_ensureAlive` `:628-631`；`observeProperty.onListen` `:464-488`；经 barrel 导出 |
| `packages/mpv_kit/lib/src/player/player.dart` | 异常隔离 dispose、状态流登记、惰性 `audioDevices` 关闭、end-file 守卫 | ✓ VERIFIED | 760 行；`audioDevices` `_disposed` 分支 `:345-349`；`_states` 关闭 `:670-672`；`_errors.isClosed` `:724` |
| `packages/mpv_kit/lib/src/core/stream_bridge.dart` | shutdown 分支与四条 close 路径错误兜底 | ✓ VERIFIED | 285 行；`shutdown()` `:176-184`；`close()` `:187-190`；`_opClose` `:201-205`；`_handleOpen` `:228-235`；`_handleRead/_handleSeek` `on Object` 映射 |
| `packages/mpv_kit/test/mpv_test.dart` | 重入 dispose 回归、post-dispose 守卫、流关闭、late listen | ✓ VERIFIED | 331 行；22 passed |
| `packages/mpv_kit/test/player_test.dart` | throwing-hook、post-dispose `audioDevices` | ✓ VERIFIED | 282 行；18 passed |
| `packages/mpv_kit/test/failure_injection_test.dart` | 监听器/hook/流源失败注入，含计数器证明 | ✓ VERIFIED | 468 行；patched 环境 7 passed / 0 skipped |
| `packages/mpv_kit/test/lifecycle_test.dart` | 1000-cycle soak、文件级调用说明 | ✓ VERIFIED | 76 行；显式运行 1 passed（5 s）；默认 1 skipped |
| `packages/mpv_kit/test/api_freeze_test.dart` | API 冻结（名字级） | ✓ VERIFIED | 186 行；0 个 `ignore_for_file`；1/1 passed（已知名字级限制见 GC-WR-02） |
| `packages/mpv_kit/analysis_options.yaml` | VM-only 测试的配置级排除 | ✓ VERIFIED | `analyzer.exclude: [test/api_freeze_test.dart]`，注释说明全上下文生效 |
| `packages/mpv_kit/dart_test.yaml` | lifecycle tag 默认 skip 与文件级命令 | ✓ VERIFIED | 9 行；skip 文案与 CI 命令一致 |
| `.github/workflows/native-verify.yml` | 两个显式 tag 调用、文件级 soak | ✓ VERIFIED | `:97` failure-injection；`:98` 文件级 lifecycle `--run-skipped`；CI 构建含 patch 0006 的 `native/mpv` |

## Key Link Verification

| From | To | Via | Status | Details |
| ---- | -- | --- | ------ | ------- |
| `Player.dispose` | `Mpv.dispose` → `bindings.terminateDestroy` | 顺序调用 | ✓ WIRED | `player.dart:663-665` → `mpv.dart:202`；测试断言 `isDisposed` |
| `Player._states` | `MpvState._close` → `StreamController.close` | 逐条 stage | ✓ WIRED | `player.dart:670-672`；soak 与测试观察到 `done` |
| `Mpv._onWakeup` → `_dispatch` → `_events.add` | listener → `Mpv.dispose` → `_closeIfOpen(_events)` → microtask retry → `done` | 重入链 | ✓ WIRED | `mpv.dart:636-665`、`:683-692`；回归测试通过 |
| `Mpv.dispose` observer 快照循环 | `_closeIfOpen(c)` | snapshot + helper | ✓ WIRED | `mpv.dart:215-217` |
| 公共入口 | `_ensureAlive` → `_disposed` → `StateError` | 首句守卫 | ✓ WIRED | 31 个方法；调用表证明无 native 进入 |
| `observeProperty.onListen` | `_disposed` 检查 → 禁止 native | onListen 分支 | ✓ WIRED | `mpv.dart:464-471`；late-listen 测试 |
| `Player.audioDevices` 惰性初始化 | `_disposed` 分支 → `unawaited(state._close())` → `done` | 首次读取 | ✓ WIRED | `player.dart:343-357`；目标测试通过 |
| `Player._onEvent` `EndFileEvent(error)` | `!_errors.isClosed` → `_errors.add` | isClosed 守卫 | ✓ WIRED（源码） | `player.dart:721-732`；运行时不可达 |
| `StreamBridge._handleRead/_handleSeek` | 映射 mpv 错误码 | `on Object` / `on UnsupportedError` | ✓ WIRED | `stream_bridge.dart:246-284`；read/seek 失败注入实际执行通过 |
| 四处 `source.close()` | 错误兜底 | `catchError` / `await Future.sync(...).catchError` | ✓ WIRED | `:181`、`:203`、`:233`，`close()`→`shutdown()` `:188`；close 失败注入实际执行通过 |
| `dart_test.yaml` lifecycle skip | CI 文件级 `--run-skipped` | tag 默认 + 显式调用 | ✓ WIRED | 默认 1 次 skip；显式 1 passed；CI 两条命中 |
| CI 构建 `native/mpv` | `mpv_kit_stream_add` 等符号 | vendored patched tree + patch 0006 | ✓ WIRED | `native/mpv/player/stream_bridge.c`、`native/patches/0006-...patch`；CI 直接构建 `native/mpv` |

## Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
| -------- | ------------- | ------ | ------------------ | ------ |
| `mpv.dart` | `_events` / `_observers` | `bindings.waitEvent` → `MpvEventData.decode` | 是（真实 libmpv 测试观察到 PropertyChange/EndFile 等事件） | ✓ FLOWING |
| `player.dart` | 各 `MpvState` | `mpv.observeProperty(...)` 订阅回调 | 是（`pause/volume/...` round-trip、1000-cycle soak 通过） | ✓ FLOWING |
| `stream_bridge.dart` | 流源 read/seek/close | 原生 demuxer 请求回调 | 是（patched libmpv 上 read/seek/close 失败注入实际执行） | ✓ FLOWING |

## Behavioral Spot-Checks

| Behavior | Command | Result | Status |
| -------- | ------- | ------ | ------ |
| 静态分析干净 | `cd packages/mpv_kit && dart analyze --fatal-infos` | `No issues found!` | ✓ PASS |
| DLL 导出确认 | `python -I tools/rea_abi_audit/pe_audit.py --dump bt/libmpv-2.dll` | 列出 `mpv_kit_stream_add/begin/complete/shutdown` | ✓ PASS |
| 异常流源失败注入 | `PATH=/d/mpv_kit/bt:$PATH MPV_KIT_LIBMPV_PATH=D:/mpv_kit/bt/libmpv-2.dll dart test -t failure-injection test/failure_injection_test.dart` | 7 passed，0 skipped | ✓ PASS |
| 全量默认套件 | 同一环境 `dart test` | 98 passed，2 skipped，0 failed | ✓ PASS |
| 1000-cycle soak | 同一环境 `dart test test/lifecycle_test.dart -t lifecycle --run-skipped` | 1 passed（5 s） | ✓ PASS |
| API 冻结 | 同一环境 `dart test test/api_freeze_test.dart` | 1 passed | ✓ PASS |
| 重入 dispose 回归 | 同一环境 `dart test test/mpv_test.dart -n "dispose from a synchronous events listener"` | 1 passed | ✓ PASS |
| 默认 skip 来源 | `dart test --reporter json` 中 `skipped:true` | lifecycle tag（RSS soak）与 `format matrix`（`MPV_KIT_FORMAT_SAMPLES` 未设置） | ✓ PASS（均为设计行为） |
| 公共 API 直接比对 | `git diff 59e9bdf..HEAD -- packages/mpv_kit/lib` | 仅新增两个 `@visibleForTesting` seam；其余为表达式体→块体 | ✓ PASS |

## Probe Execution

未发现 `scripts/*/tests/probe-*.sh`，PLAN/SUMMARY 也未声明 probe 脚本；本阶段不是迁移/工具化阶段。N/A。

## Test Quality Audit

| Test File | Linked Req | Active | Skipped | Circular | Assertion Level | Verdict |
| --------- | ---------- | ------ | ------- | -------- | --------------- | ------- |
| `player_test.dart` | STAB-01, STAB-02 | 18 | 0 | 否 | Behavioral（核心销毁 + `done` + 错误 identity + 惰性状态关闭） | ✓ |
| `mpv_test.dart` | STAB-01, STAB-03 | 22 | 0 | 否 | Behavioral（31 调用表 + native 计数 + 重入 dispose + late listen） | ✓ |
| `api_freeze_test.dart` | API 冻结 | 1 | 0 | 否 | Value（名字集合相等；构造函数/签名未覆盖，GC-WR-02） | ✓（有已知限制，已由直接 diff 补偿） |
| `failure_injection_test.dart` | VERIFY-03 | 7 | 0（patched 环境） | 否 | Behavioral；read/seek 有计数器证明，seek 的“显式 seek”受 GC-IN-02 限制 | ✓ |
| `lifecycle_test.dart` | STAB-01 | 1（显式运行时） | 1（默认 tag） | 否 | Behavioral（`done` + RSS 上限） | ✓ |

- 硬禁用测试（`test.skip`/`xit`/`describe.skip`）：0。
- 循环测试：0。
- 债务标记（`TBD`/`FIXME`/`XXX`/`TODO`/`HACK`）在本阶段改动文件中：0。
- 能力门控 skip（`markTestSkipped`）仅在 patch 0006 缺失时触发；本轮 patched 环境 0 skip。

## Requirements Coverage

| Requirement | Source Plan | 描述 | Status | Evidence |
| ----------- | ----------- | ---- | ------ | -------- |
| STAB-01 | 01-01, 01-03, 01-04, 01-05 | 反复创建/销毁 Player 不泄漏，events/状态流正确关闭 | ✓ SATISFIED（Phase 1 范围） | 1000-cycle soak；状态流 + errors/logs 全部 `done`；重入 dispose 修复并测试；`MpvVideoController` 分句按 Scope note 推迟到 Phase 2（见 Deferred） |
| STAB-02 | 01-01, 01-04 | 抛错 hook 仍完成核心销毁且可重复调用 | ✓ SATISFIED | throwing-hook 测试 + failure-injection hook 测试；`same(sentinel)`；重入 dispose 关闭错误被兜住 |
| STAB-03 | 01-02 | dispose 后公共方法抛 `StateError`，无 native use-after-free | ✓ SATISFIED | 31 调用表全部抛 `StateError`；native-entry 计数平坦；late-listen 测试通过 |
| VERIFY-03 | 01-03, 01-05 | 关键失败路径有回归测试（失败注入、抛错监听器/hook、异常流源） | ✓ SATISFIED | patched 环境 7 passed / 0 skipped；read/seek 计数器证明；CI `native-verify.yml:97` 显式执行 |

**Orphaned requirements:** 无。Phase 1 的 4 个 ID 均出现在至少一个 PLAN 的 `requirements` 字段中，并在 `REQUIREMENTS.md` 映射到 Phase 1。

## Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
| ---- | ---- | ------- | -------- | ------ |
| `packages/mpv_kit/lib/src/core/mpv.dart` | 688-690 | microtask retry 未再包 `try/on StateError`（GC-IN-01 / IN-01） | ℹ️ INFO | 当前调用点不可达；记录为 deferred/advisory |
| `packages/mpv_kit/test/failure_injection_test.dart` | 365-392 | `seekAttempts` 可能由启动 refresh seek 满足（GC-IN-02） | ℹ️ INFO | 不影响“抛错被兜住”契约；测试已无法区分显式用户 seek，但 must-have 只要求证明 `_handleSeek` 运行 |
| `packages/mpv_kit/test/api_freeze_test.dart` | 17-25, 164-186 | API-freeze 只比较名字、排除构造函数（GC-WR-02） | ℹ️ INFO | 预存在缺陷；本阶段通过直接 diff 证明无公共 API 变化 |
| `packages/mpv_kit/test/player_test.dart` / `failure_injection_test.dart` | 24-48 / 106-130 | WAV 字节写入器重复（GC-IN-04） | ℹ️ INFO | 可维护性；记录为 deferred |

**Debt markers:** 本阶段改动文件中无 `TBD`/`FIXME`/`XXX`/`TODO`/`HACK`。
**Stub classification:** 无 stub；两处 `return null`（`mpv.dart:389`、`:403`）是 `tryGetProperty`/`getPropertyString` 的合法可空语义。
**Skip classification:** 两个 skip 均为设计行为（lifecycle tag 默认、`MPV_KIT_FORMAT_SAMPLES` 未设置），不是能力门控漏跑。

## Human Verification Required

无。上一版列为人工验证的四项（read/seek/close 流源失败注入与显式 CI 调用）已在可解析依赖的 patched libmpv 上实际执行并通过。CI runner 上的实际执行观察属于 Phase 6（VERIFY-01 / VERIFY-02）范围，不是本阶段 must-have 的未验证项；本阶段只要求两条显式调用进入 CI，该接线已静态确认。

## Gaps Summary

本阶段没有未关闭的 BLOCKER、FAILED 真值、MISSING/STUB 工件或 NOT_WIRED 关键链接。

核心目标在真实 patched libmpv 上成立：1000 次 create/dispose 后所有状态流收到 `done` 且 RSS 有界；抛错的 dispose hook 不阻止 `mpv_terminate_destroy`；从同步 `Mpv.events` 监听器内重入 `dispose()` 不再抛错且仍投递 `done`；dispose 后 31 个公共 `Mpv` 入口全部抛 `StateError` 且未进入 native；read/seek/close 三类异常流源均被兜住并在 10 秒内完成 dispose。公共 API 未变化，静态分析干净，`01-SECURITY.md` 的 18 条威胁全部 closed（`threats_open: 0`）。

上一版的 `human_needed` 完全由错误的环境前提造成；更正后四条行为真值均获得实际执行证据。剩余评审发现只有四个已记录 owner/trigger 的 deferred 项，以及两条不可达的 INFO/advisory，不构成阶段阻断。`MpvLibrary.open()` 的静默回退是真实的可观测性缺陷，已明确记录为 Phase 3 (OBS-04) 的 deferred 项，不阻塞本阶段。

---

_Verified: 2026-10-24T01:28:42Z_
_Verifier: Claude (gsd-verifier)_

---
phase: 01-player-lifetime-dispose-safety
verified: 2026-10-23T16:46:01Z
status: gaps_found
score: 11/16 must-haves verified
covered_files:
  - .github/workflows/native-verify.yml
  - .planning/phases/01-player-lifetime-dispose-safety/01-01-PLAN.md
  - .planning/phases/01-player-lifetime-dispose-safety/01-01-SUMMARY.md
  - .planning/phases/01-player-lifetime-dispose-safety/01-02-PLAN.md
  - .planning/phases/01-player-lifetime-dispose-safety/01-02-SUMMARY.md
  - .planning/phases/01-player-lifetime-dispose-safety/01-03-PLAN.md
  - .planning/phases/01-player-lifetime-dispose-safety/01-03-SUMMARY.md
  - packages/mpv_kit/dart_test.yaml
  - packages/mpv_kit/lib/src/core/mpv.dart
  - packages/mpv_kit/lib/src/core/stream_bridge.dart
  - packages/mpv_kit/lib/src/player/player.dart
  - packages/mpv_kit/test/api_freeze_test.dart
  - packages/mpv_kit/test/failure_injection_test.dart
  - packages/mpv_kit/test/lifecycle_test.dart
  - packages/mpv_kit/test/mpv_test.dart
  - packages/mpv_kit/test/player_test.dart
covered_digest: "v3:sha256:4a975a37797ba4b1d9de188da79c78344bd44c9d7624156e03655755b8ae453b"
behavior_unverified: 4
overrides_applied: 0
gaps:
  - truth: "Mpv.events 与每个 observeProperty 流在 Mpv 被 dispose 时发出 done；dispose 后再监听的流不进入 native 代码"
    status: failed
    reason: "从同步 Mpv.events 监听器内重入调用 Mpv.dispose() 时，dispose() 在仍处于派发中的同步广播控制器上执行 _events.close()，Dart 抛出 `Bad state: Cannot fire new event. Controller is already firing an event`；异常从 dispose() 同步逃逸，_events 因 close() 抛错而保持未关闭，且 _disposed 已置 true，第二次 dispose() 直接返回，events 永远不会收到 done。已用真实 libmpv 独立复现（见下方 Behavioral Spot-Checks）。"
    artifacts:
      - path: "packages/mpv_kit/lib/src/core/mpv.dart"
        issue: "dispose() 第 219 行 `unawaited(_events.close())` 在同步派发重入时抛错；抛错后没有补偿关闭，而幂等早退（第 189 行）又阻止再次关闭。"
    missing:
      - "派发安全的关闭助手：捕获 close() 的 StateError，并在 scheduleMicrotask 中重试关闭；_events 与 _observers 统一走该助手"
      - "回归测试：在 mpv.events 的监听器内调用 mpv.dispose()，断言不抛异常、5 秒内收到 done、mpv.isDisposed 为 true"
deferred:
  - truth: "STAB-01 中“MpvVideoController 反复创建/销毁不泄漏”的分句"
    addressed_in: "Phase 2"
    evidence: "ROADMAP.md Phase 2 需求 STAB-04（create 失败回滚）与 STAB-05（resize/dispose 并发）负责控制器生命周期；01-01/01-03-PLAN 的 Scope note 明确将该分句推迟到 Phase 2，Phase 1 不修改 packages/mpv_kit_video/。"
behavior_unverified_items:
  - truth: "抛错 read 的流源经 Player.errors 暴露 MpvPlaybackError，且 10 秒内 dispose 完成"
    test: "在 patched libmpv（patch 0006）上运行 `dart test -t failure-injection test/failure_injection_test.dart`"
    expected: "`a source whose read throws reports an MpvPlaybackError` 通过：Player.errors 收到非空 message，dispose ≤10s"
    why_human: "本地 stock libmpv 不导出 mpv_kit_stream_add，测试按能力显式 markTestSkipped（输出含明确原因）；代码路径（_handleRead 的 on Object → mpv 错误码 → EndFileEvent(error) → Player._errors）静态存在但未被本地执行"
  - truth: "抛错 seek 的流源使 open 干净完成或失败，且 10 秒内 dispose 完成"
    test: "同上，在 patched libmpv 上运行 failure-injection 套件"
    expected: "`a source whose seek throws leaves the open contained` 通过：无挂起、无未捕获错误，dispose ≤10s"
    why_human: "本地能力门控跳过；此外该测试不统计 seek 调用次数，无法证明 _handleSeek 的 on Object 分支真的被执行（WR-03）"
  - truth: "抛错 close 的流源在全部四个 close 路径上被兜住，不逃逸为未处理异步错误，dispose 不挂起"
    test: "同上，在 patched libmpv 上运行 failure-injection 套件"
    expected: "`a source whose close throws is contained on every close path` 通过：四个 closeAttempts > 0，两个 zone error 列表均为空，dispose ≤10s"
    why_human: "本地能力门控跳过；生产代码已在 _handleOpen shutdown 分支加入 catchError（stream_bridge.dart:233），但四个路径未在本地实际执行"
  - truth: "失败注入回归测试在 CI 中稳定复现并通过（含异常流源）"
    test: "CI Linux job 的 `dart test -t failure-injection` 与 `dart test -t lifecycle --run-skipped`"
    expected: "两个显式 tag 调用均以 0 退出，无 skip 冒充通过"
    why_human: "本地 patched libmpv 不可用；CI 是三个流源测试的首次真实执行环境，本次验证无法读取 CI 运行结果"
---

# Phase 1: Player Lifetime & Dispose Safety Verification Report

**Phase Goal:** `Player` 在反复创建/销毁与异常 teardown 下都不泄漏、不崩溃，dispose 之后的调用可预测地失败。
**Verified:** 2026-10-23T16:46:01Z
**Status:** gaps_found
**Re-verification:** No — initial verification

## 结论摘要

- 绝大多数主张成立：1000 次 create/dispose soak 通过；抛错 dispose hook 仍销毁核心并关闭全部状态流，原始错误按 identity 原样抛出；31 个公共 `Mpv` 入口在 dispose 后抛 `StateError`，native 计数保持平坦；抛错监听器被同步广播隔离且投递继续；API 冻结通过。
- **发现一个 BLOCKER**：独立复现了评审 CR-01 —— 从同步 `Mpv.events` 监听器内重入调用 `Mpv.dispose()` 会同步抛出 `Bad state: Cannot fire new event. Controller is already firing an event`，`events` 永远收不到 `done`。这直接违反 01-01 的 must-have 第 5 条以及 STAB-01 “events 正确关闭” 的主张。
- 三条流源失败注入真值（read/seek/close）因本地 stock libmpv 缺少 patch 0006 而按显式能力检查 skip，标记为 behavior-unverified；按任务说明记录为环境限制，不计为自动 gap，但需在 CI patched 构建上确认真实通过。
- 另有 5 条 WARNING（子客户端 hang、`source.close` 与在途 read/seek 的契约冲突、seek 测试证明力、soak 隔离措辞、`audioDevices` 惰性状态）与 5 条 INFO，均为非阻塞记录。

## Goal Achievement

### Observable Truths

| # | Truth | 来源 | Status | Evidence |
|---|-------|------|--------|----------|
| 1 | 连续 1000 次 create/dispose 后所有状态流收到 done，native 句柄销毁、进程内存有界 | ROADMAP SC1 / 01-03 C6 | ✓ VERIFIED | `dart test -t lifecycle test/lifecycle_test.dart --run-skipped` → 1 passed（8s）；`_cycle()` 断言 `mpv.isDisposed` 且 35 条 seam 流 + errors/logs 全部 done；RSS 增量 < 64 MiB |
| 2 | 任一 dispose hook 抛错时仍完成 `mpv_terminate_destroy`、关闭全部流、错误可见、再次 dispose 无副作用、后续 hook 仍运行 | ROADMAP SC2 / 01-01 A1,A3 / 01-03 C2 | ✓ VERIFIED | `player_test.dart -n "throwing dispose hook"` 1 passed；`failure_injection_test.dart#throwing dispose hook...` passed；`same(sentinel)` 保持原始错误 identity；第二次 `dispose()` 正常完成 |
| 3 | 每个 Player 状态流（含 `position`、`decodeWarning`）在 dispose 时发出 done | 01-01 A2 | ✓ VERIFIED | `player.dart:204-206` 将两者登记进 `_states`；目标测试对两条流各挂 done completer 并在 5s 内完成；soak 枚举 35 条 seam 流全部 done |
| 4 | `Mpv.dispose()` 在终止前置空 wakeup 回调，在核心销毁后才关闭 NativeCallable | 01-01 A4 | ✓ VERIFIED | awk 顺序检查 s=196 < d=202 < c=203；`mpv.dart:196/202/203` 与声明一致 |
| 5 | `Mpv.events` 与每个 `observeProperty` 流在 dispose 时发出 done；dispose 后监听的流不进入 native | 01-01 A5 | ✗ FAILED | 常规路径通过（`mpv_test` 两个 dispose 流测试通过）；但重入 dispose 路径下 `events` 永不 done（见下方行为抽检），且 dispose 同步抛错 |
| 6 | dispose 后调用任意公共 `Mpv` 方法抛 `StateError` | ROADMAP SC3 / 01-02 B1 | ✓ VERIFIED | `mpv_test.dart -n "post-dispose guard"` 通过；31 条调用表全部 `throwsStateError` |
| 7 | 被拒绝的 post-dispose 调用不增加 native-entry 计数 | 01-02 B2 | ✓ VERIFIED | 同一测试先证明 live `getProperty` 使计数增长，再断言整张表调用后计数不变 |
| 8 | dispose 前创建、dispose 后监听的 `observeProperty` 流以 `StateError` 失败且不进入 native | 01-02 B3 | ✓ VERIFIED | 两个 late-listen 测试通过；监听前后 `nativeEntriesForTesting` 不变 |
| 9 | 相同方法在 live handle 上的既有行为不变 | 01-02 B4 | ✓ VERIFIED | `mpv_test.dart` 21/21、`api_surface_test.dart` 9/9、`player_test.dart` 17/17 全部通过 |
| 10 | 公共 API 冻结为 pre-phase baseline + 两个带注解的测试 seam | 01-02 B5 | ✓ VERIFIED | `api_freeze_test.dart` 1/1 passed；`@visibleForTesting` 的 `nativeEntriesForTesting` / `stateStreamsForTesting` grep 均命中 |
| 11 | 抛错的 observer/events/Player-state 监听器不中断投递，错误以 zone error 出现 | 01-03 C1 / ROADMAP SC4 | ✓ VERIFIED | failure-injection 三个监听器测试通过：第二个监听器仍收到值，`same(sentinel)` 出现在 `runZonedGuarded` 收集器中 |
| 12 | 抛错 read 的流源经 `Player.errors` 暴露 `MpvPlaybackError`，10s 内 dispose | 01-03 C3 | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | 测试存在且带 tag，但本地 stock libmpv 无 patch 0006 → 显式 skip；静态链路 `_handleRead` catch → mpv 错误码 → `EndFileEvent(error)` → `_errors` 存在 |
| 13 | 抛错 seek 的流源使 open 干净完成/失败，10s 内 dispose | 01-03 C4 | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | 本地能力门控 skip；测试未统计 seek 次数，不能证明 `_handleSeek` 分支被执行（WR-03） |
| 14 | 抛错 close 的流源在四条路径上被兜住，不逃逸为未处理异步错误 | 01-03 C5 | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | 本地能力门控 skip；四处 close 调用点均已有 `on Object`/`catchError`（含 `stream_bridge.dart:233`），但未在本地执行 |
| 15 | lifecycle soak 默认被 tag skip，仅由显式 `dart test -t lifecycle --run-skipped` 运行；两个 tag 在 CI 显式调用 | 01-03 C7 | ✓ VERIFIED | `dart test test/lifecycle_test.dart --reporter json` 出现 1 次 `"skipped":true`；CI grep 两个调用均命中 |
| 16 | 失败注入回归套件进入 CI（含异常流源） | ROADMAP SC4 / VERIFY-03 | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | 监听器/hook 4 条本地通过；3 条异常流源本地 skip，CI 为首次执行环境 |

**Score:** 11/16 truths verified（4 present, behavior-unverified；1 failed）

### Deferred Items

| # | Item | Addressed In | Evidence |
|---|------|-------------|----------|
| 1 | STAB-01 的 `MpvVideoController` 反复 create/dispose 不泄漏分句 | Phase 2 | ROADMAP Phase 2 需求 STAB-04 / STAB-05；01-01、01-03 PLAN 的 Scope note 明确推迟，Phase 1 不修改 `packages/mpv_kit_video/` |

### Required Artifacts

| Artifact | Expected | Status | Details |
| -------- | -------- | ------ | ------- |
| `packages/mpv_kit/lib/src/player/player.dart` | 异常隔离 dispose、状态流登记、`stateStreamsForTesting` | ✓ VERIFIED | 751 行；`_states` 含 position/decodeWarning；`dispose()` 分阶段收集错误；经 `lib/mpv_kit.dart:26` 导出 |
| `packages/mpv_kit/lib/src/core/mpv.dart` | dispose 顺序、`_ensureAlive` 全入口守卫、流关闭 | ✓ VERIFIED | 715 行；31 个公共入口首句 `_ensureAlive()`；`_dispatch`/`observeProperty` 关闭守卫；经 `lib/mpv_kit.dart:15` 导出 |
| `packages/mpv_kit/lib/src/core/stream_bridge.dart` | shutdown 分支的 throwing close 兜底 | ✓ VERIFIED | 285 行；`_handleOpen` 的 `Future.sync(source.close).catchError` 位于 `:233`；四处 close 路径均有兜底 |
| `packages/mpv_kit/test/player_test.dart` | throwing-hook 回归测试 | ✓ VERIFIED | 268 行；目标测试 1 passed |
| `packages/mpv_kit/test/mpv_test.dart` | dispose/流关闭/post-dispose 守卫测试 | ✓ VERIFIED | 307 行；21/21 passed |
| `packages/mpv_kit/test/api_freeze_test.dart` | mirrors API 冻结 | ✓ VERIFIED | 188 行；1/1 passed；仅两个 seam |
| `packages/mpv_kit/test/failure_injection_test.dart` | 监听器/hook/流源失败注入 | ✓ VERIFIED | 408 行；tagged；4 passed，3 capability-skipped（明确原因） |
| `packages/mpv_kit/test/lifecycle_test.dart` | 1000-cycle soak | ✓ VERIFIED | 76 行；tagged lifecycle；`--run-skipped` 1 passed |
| `packages/mpv_kit/dart_test.yaml` | 两个 tag 与 lifecycle 默认 skip | ✓ VERIFIED | `failure-injection` 未 skip；`lifecycle` 带 skip 原因 |
| `.github/workflows/native-verify.yml` | 两个显式 tag 调用 | ✓ VERIFIED | `dart test -t failure-injection` 与 `dart test -t lifecycle --run-skipped` 均在 Linux Dart-tests 步骤 |

### Key Link Verification

| From | To | Via | Status | Details |
| ---- | -- | --- | ------ | ------- |
| `Player.dispose` | `Mpv.dispose` → `bindings.terminateDestroy` | 顺序调用 | ✓ WIRED | `player.dart:658-660` → `mpv.dart:202` |
| `Player._states` | `MpvState._close` → `StreamController.close` | 逐条 stage | ✓ WIRED | `player.dart:665-667` → `player.dart:41`；soak 证明 done |
| `Mpv._observers` | close on dispose | snapshot 后逐条 close | ✓ WIRED | `mpv.dart:215-218`；observer 重入 dispose 探针也收到 events done |
| `Mpv._events` | close on dispose | `unawaited(_events.close())` | ✗ NOT_WIRED（重入路径） | `mpv.dart:219`；从 events 监听器内重入 dispose 时抛错且不关闭 |
| 公共入口 | `_ensureAlive` → `_disposed` → `StateError` | 首句守卫 | ✓ WIRED | 31 个方法均以 `_ensureAlive()` 开头；调用表证明无 native 进入 |
| `observeProperty.onListen` | `_disposed` 检查 → 禁止 native | onListen 分支 | ✓ WIRED | `mpv.dart:467-473`；late-listen 测试通过 |
| `_onWakeup` | `_dispatch` → 同步广播投递 → 继续排空 | zone 隔离 | ✓ WIRED | failure-injection 三个监听器测试通过 |
| `StreamBridge._handleRead/_handleSeek` | 映射 mpv 错误码 | `on Object` | ✓ WIRED（静态） | `:256-259`、`:274-281`；运行时未本地执行 |
| 四处 `source.close()` | 错误兜底 | `catchError`/`on Object` | ✓ WIRED（静态） | `:181`、`:203`、`:233`、`:280` 邻近路径；运行时未本地执行 |
| `dart_test.yaml` lifecycle skip | CI 显式 `--run-skipped` | tag 默认 skip + CI | ✓ WIRED | JSON skip 事件 1 次；CI grep 命中（隔离措辞见 W-04） |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
| -------- | ------------- | ------ | ------------------ | ------ |
| `mpv.dart` | `_events` / `_observers` | `bindings.waitEvent` → `MpvEventData.decode` | 是（live libmpv 测试观察到 PropertyChange/EndFile 等事件） | ✓ FLOWING |
| `player.dart` | 各 `MpvState` | `mpv.observeProperty(...)` 订阅回调 | 是（`pause/volume/...` round-trip 测试通过） | ✓ FLOWING |
| `stream_bridge.dart` | 流源 read/seek/close | 原生 demuxer 请求回调 | 是（设计如此；本地 stock libmpv 无法执行） | ✓ FLOWING（运行时环境受限） |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
| -------- | ------- | ------ | ------ |
| 静态分析干净 | `dart analyze --fatal-infos` | No issues found! | ✓ PASS |
| throwing-hook 目标测试 | `dart test test/player_test.dart -n "throwing dispose hook"` | 1 passed | ✓ PASS |
| 完整 `mpv_test` | `dart test test/mpv_test.dart` | 21 passed | ✓ PASS |
| API 冻结 | `dart test test/api_freeze_test.dart` | 1 passed | ✓ PASS |
| 原有行为套件 | `dart test test/api_surface_test.dart` | 9 passed | ✓ PASS |
| failure-injection | `dart test -t failure-injection test/failure_injection_test.dart` | 4 passed，3 skipped（patch 0006） | ✓ PASS（含环境门控） |
| 默认 lifecycle skip | `dart test test/lifecycle_test.dart --reporter json \| grep -c '"skipped":true'` | 1 | ✓ PASS |
| 1000-cycle soak | `dart test -t lifecycle test/lifecycle_test.dart --run-skipped` | 1 passed（8s） | ✓ PASS |
| 全量默认套件 | `dart test` | 88 passed，5 skipped，5 failed | ✓ 记录（5 failed 全为 stock libmpv 缺 patch 0006 的 `stream_bridge_test.dart`，环境限制） |
| wakeup/destroy/close 顺序 | awk 顺序检查 | s=196 d=202 c=203 | ✓ PASS |
| CI 显式 tag 调用 | grep `native-verify.yml` | 两条均命中 | ✓ PASS |
| **重入 dispose（CR-01）** | 临时探针（真实 libmpv，运行后删除） | `escaped=Bad state: Cannot fire new event. Controller is already firing an event`；`isDisposed=true`；`eventsDone=false`；第二次 dispose 不抛但 `eventsDone` 仍为 false | ✗ **FAIL** |
| **audioDevices dispose 后首次访问（IN-03）** | 临时探针（真实 libmpv，运行后删除） | `disposed=true done=false`（dispose 前初始化则 done=true） | ✗ FAIL（WARNING） |

### Probe Execution

未发现 `scripts/*/tests/probe-*.sh`，PLAN/SUMMARY 也未声明 probe 脚本；本阶段不是迁移/工具化阶段。N/A。

### Test Quality Audit

| Test File | Linked Req | Active | Skipped | Circular | Assertion Level | Verdict |
| --------- | ---------- | ------ | ------- | -------- | --------------- | ------- |
| `player_test.dart` | STAB-02 | 17 | 0 | 否 | Behavioral（核心销毁 + done + 错误 identity） | ✓ |
| `mpv_test.dart` | STAB-03 | 21 | 0 | 否 | Behavioral（31 调用表 + native 计数） | ✓ |
| `api_freeze_test.dart` | B5 / API 冻结 | 1 | 0 | 否 | Value（集合相等） | ✓ |
| `failure_injection_test.dart` | VERIFY-03 | 4 | 3（能力门控） | 否 | Behavioral；seek 路径证明力不足 | ⚠️ WARNING（WR-03） |
| `lifecycle_test.dart` | STAB-01 | 1（默认 tag skip） | 0（执行时） | 否 | Behavioral（done + RSS 上限） | ✓ |

- 硬禁用测试（`test.skip`/`xit`/`describe.skip`）：0。
- 循环测试：0。
- 断言不足：1（seek 测试不统计 `seekAttempts`，无法证明 `_handleSeek` 被执行）→ WARNING。
- 三个流源测试是各自失败路径的唯一证明，但 skip 是显式能力门控且 CI 会执行，因此记为 WARNING（环境），不是 BLOCKER。

### Decision Coverage

N/A — 本阶段没有 `01-*-CONTEXT.md`，决策覆盖门禁跳过。

### Requirements Coverage

| Requirement | Source Plan | 描述 | Status | Evidence |
| ----------- | ----------- | ---- | ------ | -------- |
| STAB-01 | 01-01, 01-03 | 反复创建/销毁不泄漏，events/状态流正确关闭 | ✓ SATISFIED（phase 范围） | 1000-cycle soak 通过；35 条状态流 + errors/logs 全部 done；`MpvVideoController` 分句按 Scope note 推迟到 Phase 2（见 Deferred） |
| STAB-02 | 01-01 | 抛错 hook 仍完成核心销毁且可重复调用 | ✓ SATISFIED | throwing-hook 目标测试 + failure-injection hook 测试；`same(sentinel)`；第二次 dispose 正常 |
| STAB-03 | 01-02 | dispose 后公共方法抛 `StateError`，无 native use-after-free | ✓ SATISFIED | 31 调用表全部抛 `StateError`；native-entry 计数平坦；late-listen 测试通过 |
| VERIFY-03 | 01-03 | 关键失败路径有回归测试（失败注入、抛错监听器/hook、异常流源） | ✓ SATISFIED（异常流源需 CI 确认） | 监听器/hook 4 条本地通过；3 条异常流源带 tag 且 CI 显式调用，本地因 patch 0006 缺失 skip（见 behavior-unverified） |

**Orphaned requirements:** 无。Phase 1 的 4 个 ID 均出现在至少一个 PLAN 的 `requirements` 字段中，并在 REQUIREMENTS.md 映射到 Phase 1。

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
| ---- | ---- | ------- | -------- | ------ |
| `packages/mpv_kit/lib/src/core/mpv.dart` | 219 | 同步广播控制器在派发中 `close()` 无兜底 | 🛑 BLOCKER（= CR-01 / gap 1） | 重入 dispose 时抛错且 events 永不 done |
| `packages/mpv_kit/lib/src/player/player.dart` | 343-352 | dispose 后首次访问 `audioDevices` 返回永不关闭的惰性状态 | ⚠️ WARNING（IN-03） | 已在真实 libmpv 探针中复现 `done=false` |
| `packages/mpv_kit/lib/src/core/stream_bridge.dart` | 176-184 | `shutdown()` 在 read/seek 在途时调用 `source.close()` | ⚠️ WARNING（WR-02） | 违反 `MpvStreamSource` “同一时刻只有一个调用”文档契约 |
| `packages/mpv_kit/test/failure_injection_test.dart` | 298-332 | seek 测试不统计 seek 次数 | ⚠️ WARNING（WR-03） | 不能证明 `_handleSeek` 映射路径被执行 |
| `.github/workflows/native-verify.yml` | 87-94 | `-t lifecycle` 仍加载全部 suite 到同一进程 | ⚠️ WARNING（WR-04） | “own process / runs alone” 表述不准确；RSS 窗口可能含其他 suite 加载分配 |
| `packages/mpv_kit/test/api_freeze_test.dart` | 10 | 宽泛 `ignore_for_file`（6 类诊断） | ℹ️ INFO（IN-01） | 可能掩盖真实拼写/类型错误 |
| `packages/mpv_kit/lib/src/core/mpv.dart` | 606-616 | `errorString`/`eventName` 不触碰句柄却被守卫 | ℹ️ INFO（IN-02） | 冻结 API 上的 dispose 后语义变化；计数器语义略模糊 |
| `packages/mpv_kit/lib/src/player/player.dart` | 714-733 | EndFile error 分支缺 `_errors.isClosed` | ℹ️ INFO（IN-04） | 当前顺序下不可达；未来调整顺序可能抛入事件排空 |
| `packages/mpv_kit/lib/src/player/player.dart` | 635-674 | 并发第二次 `dispose()` 不等待第一次 | ℹ️ INFO（IN-05） | 幂等成立，但不保证“清理完成”语义 |
| `packages/mpv_kit/lib/src/core/mpv.dart` | 155-171, 188-220 | 存活子客户端未被 owner dispose 递归销毁 | ⚠️ WARNING（WR-01） | `mp_shutdown_clients` 会在 `num_clients` 上等待；Dart 线程被 join 阻塞时子句柄无法 dispose，可能 hang（原生证据：`native/mpv/player/client.c:543-578`） |

**Debt markers:** 本阶段改动文件中无 `TBD`/`FIXME`/`XXX`。
**Stub classification:** 无 stub（所有实现均为真实逻辑，非占位返回）。

### 环境受限验证（Patched libmpv / CI）

本阶段为库/基础设施层，无用户可见 UI，因此下列条目不是人工 UAT，而是需在 patched libmpv（patch 0006）环境中执行的行为验证：

1. **抛错 read 源** — 测试：`dart test -t failure-injection test/failure_injection_test.dart`；期望：`a source whose read throws reports an MpvPlaybackError` 通过，dispose ≤10s。
2. **抛错 seek 源** — 同上；期望：open 干净完成/失败、无未捕获错误、dispose ≤10s。建议先加 `seekAttempts` 断言以证明路径被执行（WR-03）。
3. **抛错 close 源** — 同上；期望：四条 close 路径均被兜住、两个 zone error 列表为空、dispose ≤10s。
4. **CI 两个显式 tag** — 期望：Linux job 的 `dart test -t failure-injection` 与 `dart test -t lifecycle --run-skipped` 均 0 退出，且不出现 skip 冒充通过。

### Gaps Summary

本阶段的核心生命周期保证大部分已在真实 libmpv 上验证：1000 次 create/dispose 不增长、状态流全部关闭；抛错 hook 不再跳过核心销毁；post-dispose 的 31 个 `Mpv` 入口全部转为可捕获的 `StateError` 且不进入 native；API 冻结与 CI tag 接线均成立。

但存在一个必须修复的 BLOCKER：`Mpv.dispose()` 的 `_events.close()` 不是“派发中安全”的。从同步 `Mpv.events` 监听器内重入调用 `Mpv.dispose()` 时，Dart 拒绝在控制器正在派发时 `close()`，dispose 同步抛错，`events` 永远不关闭；由于 `_disposed` 已置 true，第二次 `dispose()` 也无法补救。这违反 01-01 must-have 第 5 条（events 必须发出 done）与 STAB-01（events 正确关闭），也与阶段目标中的“异常 teardown 不泄漏”相冲突。修复方向已在 gap 的 `missing` 中给出：派发安全的关闭助手 + 重入回归测试。

其余 warning（子客户端 hang、close 并发契约、seek 测试证明力、soak 隔离措辞、audioDevices 惰性状态）不单独构成 must-have 失败，但建议在后续阶段或本轮 gap 修复时一并处理。

---

_Verified: 2026-10-23T16:46:01Z_
_Verifier: Claude (gsd-verifier)_

---
phase: 01-player-lifetime-dispose-safety
verified: 2026-10-24T01:09:43Z
status: human_needed
score: 19/23 must-haves verified
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
  - .planning/phases/01-player-lifetime-dispose-safety/01-REVIEW-DISPOSITION.md
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
covered_digest: "v3:sha256:ce5011ccaad1cec542b605668de66a13c2fc94a09dff92cd308e048993069efd"
behavior_unverified: 4
overrides_applied: 0
re_verification:
  previous_status: gaps_found
  previous_score: 11/16
  gaps_closed:
    - "Mpv.events 与每个 observeProperty 流在 Mpv 被 dispose 时发出 done；dispose 后再监听的流不进入 native 代码（含从同步 Mpv.events 监听器内重入 dispose 的路径）"
  gaps_remaining: []
  regressions: []
deferred:
  - truth: "STAB-01 中“MpvVideoController 反复创建/销毁不泄漏”的分句"
    addressed_in: "Phase 2"
    evidence: "ROADMAP.md Phase 2 需求 STAB-04（create 失败回滚）与 STAB-05（resize/dispose 并发）负责控制器生命周期；01-01/01-03/01-04/01-05 PLAN 均未修改 packages/mpv_kit_video/。"
advisory:
  - finding: "Mpv._closeIfOpen 的 microtask 重试本身没有 try/on StateError 兜底；若重试时控制器仍在派发，会变成未捕获 zone error 且 done 仍不投递。"
    category: other
    reason: "GC-IN-01，01-REVIEW-DISPOSITION.md 记录为 deferred。标准事件循环下 retry 在同步派发退栈后才运行，当前调用点不可达；本次独立探针也确认 retry 在派发结束后执行。无运行时证据表明可触发，故为非阻塞记录。"
    evidence_status: "none provided"
behavior_unverified_items:
  - truth: "抛错 read 的流源经 Player.errors 暴露 MpvPlaybackError，且 10 秒内 dispose 完成"
    test: "在 patched libmpv（patch 0006）上运行 `dart test -t failure-injection test/failure_injection_test.dart`"
    expected: "`a source whose read throws reports an MpvPlaybackError` 通过：readAttempts > 0，Player.errors 收到非空 message，dispose ≤10s"
    why_human: "本地 stock libmpv 不导出 mpv_kit_stream_add，测试按能力显式 markTestSkipped（输出含明确原因）；代码路径（_handleRead 的 on Object → mpv 错误码 → EndFileEvent(error) → Player._errors）静态存在但未被本地执行，CI patched 构建是首次真实执行环境"
  - truth: "抛错 seek 的流源使 open 干净完成或失败，且 10 秒内 dispose 完成"
    test: "同上，在 patched libmpv 上运行 failure-injection 套件"
    expected: "`a source whose seek throws leaves the open contained` 通过：seekAttempts > 0，无挂起、无未捕获错误，dispose ≤10s"
    why_human: "本地能力门控跳过；01-05 已用可取样的内存 WAV 与 seekAttempts 证明 _handleSeek 会被调用，但 GC-IN-02 指出 seekAttempts 可能由 mpv 启动时的 refresh seek 满足，测试不能区分显式 seek 是否到达 demuxer（不影响“抛错被兜住”这一契约）"
  - truth: "抛错 close 的流源在全部四个 close 路径上被兜住，不逃逸为未处理异步错误，dispose 不挂起"
    test: "同上，在 patched libmpv 上运行 failure-injection 套件"
    expected: "`a source whose close throws is contained on every close path` 通过：closeAttempts > 0，两个 zone error 列表均为空，dispose ≤10s"
    why_human: "本地能力门控跳过；生产代码四条路径（shutdown 扫描、_opClose、StreamBridge.close、_handleOpen 的 shutdown 分支）均已 catchError/on Object 兜底，但未在本地实际执行"
  - truth: "失败注入回归测试在 CI 中稳定复现并通过（含异常流源）"
    test: "CI Linux job 的 `dart test -t failure-injection` 与 `dart test test/lifecycle_test.dart -t lifecycle --run-skipped`"
    expected: "两个显式 tag 调用均以 0 退出；3 条流源测试真实执行而非 skip"
    why_human: "本地 patched libmpv 不可用；CI 是三个流源测试的首次真实执行环境，本次验证无法读取 CI 运行结果"
human_verification:
  - test: "在 patched libmpv（导出 mpv_kit_stream_add）上运行 `cd packages/mpv_kit && MPV_KIT_LIBMPV_PATH=<patched> dart test -t failure-injection test/failure_injection_test.dart`"
    expected: "4 条监听器/hook 测试与此前一致通过；`a source whose read throws reports an MpvPlaybackError` 通过且 readAttempts > 0，Player.errors 非空，dispose ≤10s。"
    why_human: "本地 stock libmpv 缺 patch 0006，测试显式 skip；环境限制，不是代码缺失。"
  - test: "同一 patched 环境下运行 seek 测试"
    expected: "`a source whose seek throws leaves the open contained` 通过，seekAttempts > 0，无未捕获错误，dispose ≤10s。"
    why_human: "同上；另外 GC-IN-02 提示 seekAttempts 可能由启动 refresh seek 满足，若要证明显式 seek，请按该条建议先 `drop-buffers` 或用更大的 WAV 并 await seek future。"
  - test: "同一 patched 环境下运行 close 测试"
    expected: "`a source whose close throws is contained on every close path` 通过：两个 zone error 列表为空，closeAttempts > 0，dispose ≤10s。"
    why_human: "同上；四条 close 路径的运行时覆盖只能在 patched 环境执行。"
  - test: "在 CI（.github/workflows/native-verify.yml 的 Linux Dart-tests 步骤）观察 `dart test -t failure-injection` 与 `dart test test/lifecycle_test.dart -t lifecycle --run-skipped` 的实际退出码与 reporter 输出"
    expected: "两条命令均 0 退出，且 failure-injection 的 3 条流源测试显示为通过而非 skip；lifecycle 显示 1 passed。"
    why_human: "CI 是这些环境门控测试的首次真实执行环境，本地无法代跑。"
---

# Phase 1: Player Lifetime & Dispose Safety Verification Report

**Phase Goal:** `Player` 在反复创建/销毁与异常 teardown 下都不泄漏、不崩溃，dispose 之后的调用可预测地失败。
**Verified:** 2026-10-24T01:09:43Z
**Status:** human_needed
**Re-verification:** Yes — gap closure（plans 01-04 / 01-05）后的完整重验

## 结论摘要

- **上一轮唯一的 BLOCKER 已独立确认修复。** 从同步 `Mpv.events` 监听器内重入调用 `Mpv.dispose()` 不再抛错，`events` 在 5 秒内收到 `done`，`isDisposed` 为 true，第二次 `dispose()` 是无异常 no-op。`Mpv._closeIfOpen` 是 `_events` 与全部 observer 控制器的唯一关闭路径（`mpv.dart:215-219`, `:683-692`）。
- **修复机制独立复现。** 我在仓库外写了最小探针：`StreamController.broadcast(sync: true)` 在派发中调用 `close()` 会同步抛 `StateError`；有 microtask retry 时 `isClosed=true` 且 `done` 投递，无 retry 时 `isClosed=false` 且 `done` 永不投递。因此新回归测试确实依赖 retry 分支，不是“碰巧通过”。
- **两个相邻生命周期缺口也已闭环。** dispose 后首次读取 `Player.audioDevices` 返回已关闭的空状态且不登记进 `_states`（测试通过）；`EndFileEvent(error)` 分支由 `!_errors.isClosed` 守卫（源码确认，当前 dispose 顺序下运行时不可达）。
- **公共 API 未被改动。** 除两个带 `@visibleForTesting` 的 seam 外，我直接比对了 `59e9bdf..HEAD` 的 lib diff：所有出现的方法签名与删除行一一对应（只是为插入 `_ensureAlive()` 而把表达式体改为块体），没有签名或公开成员变化。
- **4 条流源失败注入真值仍是环境受限的行为未验证项**（read/seek/close + CI 首次执行）。本地 stock libmpv 缺 patch 0006，测试以明确原因 self-skip；01-05 已把它们强化为“计数器必须先前进”的真证明。它们不是静默通过，而是需要 patched 环境/CI 的人工确认，因此本轮状态为 `human_needed`，不是 `passed`。
- 全量 `dart test` 仍为 **90 passed / 5 skipped / 5 failed**，5 个失败全部是 `stream_bridge_test.dart` 缺 patch 0006 的既有环境基线，与本轮改动无关，不计为回归。

## Goal Achievement

### Observable Truths

| # | Truth | 来源 | Status | Evidence |
|---|-------|------|--------|----------|
| 1 | 连续 1000 次 create/dispose 后所有状态流收到 done，native 句柄销毁、进程内存有界 | ROADMAP SC1 / 01-03 | ✓ VERIFIED | 独立运行 `dart test test/lifecycle_test.dart -t lifecycle --run-skipped` → 1 passed（8s）；`_cycle()` 断言 `mpv.isDisposed`、35 条 seam 流 + errors/logs 全部 done、RSS 增量 < 64 MiB |
| 2 | 任一 dispose hook 抛错时仍完成 `mpv_terminate_destroy`、关闭全部流、错误可见、再次 dispose 无副作用、后续 hook 仍运行 | ROADMAP SC2 / 01-01 / 01-03 | ✓ VERIFIED | `player_test.dart` throwing-hook 测试通过（`same(sentinel)`、position/decodeWarning done、第二次 dispose 正常）；`failure_injection_test.dart` 证明第二个 hook 仍运行且核心已销毁 |
| 3 | 每个 Player 状态流（含 `position`、`decodeWarning`）在 dispose 时发出 done | 01-01 | ✓ VERIFIED | `player.dart:204-206` 登记进 `_states`；`player.dart:668-672` 逐条关闭；目标测试 5s 内完成 |
| 4 | `Mpv.dispose()` 在终止前置空 wakeup 回调，在核心销毁后才关闭 NativeCallable | 01-01 | ✓ VERIFIED | `mpv.dart:196`（null wakeup）→ `:202`（terminate/destroy）→ `:203`（`_wakeup.close()`），顺序正确 |
| 5 | `Mpv.events` 与每个 `observeProperty` 流在 dispose 时发出 done；dispose 后监听的流不进入 native；**包括从同步 events 监听器内重入 dispose** | 01-01 / STAB-01 / 01-04 | ✓ VERIFIED | 新测试 `dispose from a synchronous events listener closes events without throwing` 独立运行通过；普通路径 `dispose closes Mpv.events and observer streams` 通过；独立探针确认 retry 是 done 投递的必要条件 |
| 6 | dispose 后调用任意公共 `Mpv` 方法抛 `StateError` | ROADMAP SC3 / 01-02 | ✓ VERIFIED | `mpv_test.dart` 31 条调用表全部 `throwsStateError` |
| 7 | 被拒绝的 post-dispose 调用不增加 native-entry 计数 | 01-02 | ✓ VERIFIED | 同一测试先证明 live `getProperty` 使计数增长，再断言整张表调用后计数不变 |
| 8 | dispose 前创建、dispose 后监听的 `observeProperty` 流以 `StateError` 失败且不进入 native | 01-02 | ✓ VERIFIED | 两个 late-listen 测试通过；监听前后 `nativeEntriesForTesting` 不变 |
| 9 | 相同方法在 live handle 上的既有行为不变 | 01-02 | ✓ VERIFIED | `mpv_test` 22、`player_test` 18、`api_freeze_test` 1，共 41 条独立运行全通过 |
| 10 | 公共 API 冻结为 pre-phase baseline + 两个带注解的测试 seam | 01-02 | ✓ VERIFIED | `api_freeze_test.dart` 1/1 passed；`59e9bdf..HEAD` lib diff 直接比对：无签名/公开成员变化，仅新增两个 `@visibleForTesting` seam（见下方 GC-WR-02 说明） |
| 11 | 抛错的 observer/events/Player-state 监听器不中断投递，错误以 zone error 出现 | 01-03 / SC4 | ✓ VERIFIED | failure-injection 三条监听器测试通过：第二个监听器仍收到值，`same(sentinel)` 出现在 `runZonedGuarded` 收集器中 |
| 12 | 抛错 read 的流源经 `Player.errors` 暴露 `MpvPlaybackError`，10s 内 dispose；01-05 要求 `readAttempts > 0` | 01-03 / 01-05 | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | 测试存在、断言计数器、带 tag；本地 stock libmpv 无 patch 0006 → 显式 skip。静态链路完整 |
| 13 | 抛错 seek 的流源使 open 干净完成/失败，10s 内 dispose；01-05 要求 `seekAttempts > 0` 的可 seek WAV | 01-03 / 01-05 | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | 本地能力门控 skip；`_silentWavBytes` 与 `seekAttempts > 0` 断言存在；GC-IN-02 提示不能区分显式 seek |
| 14 | 抛错 close 的流源在四条路径上被兜住，不逃逸为未处理异步错误 | 01-03 | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | 本地能力门控 skip；四条 close 调用点均有 `on Object`/`catchError`（`stream_bridge.dart:181/203/233`，`close()` 经 `shutdown()`） |
| 15 | lifecycle soak 默认被 tag skip，仅由显式文件级 `dart test test/lifecycle_test.dart -t lifecycle --run-skipped` 运行；两个 tag 在 CI 显式调用 | 01-03 / 01-05 | ✓ VERIFIED | 默认运行 JSON 中恰有 1 次 `"skipped":true`；显式运行 1 passed；`native-verify.yml:97-98` 两条调用命中 |
| 16 | 失败注入回归套件进入 CI（含异常流源） | ROADMAP SC4 / VERIFY-03 | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | 监听器/hook 4 条本地通过；3 条异常流源本地 skip，CI 为首次执行环境 |
| 17 | `Mpv._closeIfOpen` 是 `_events` 与全部 observer 控制器的唯一派发安全关闭路径，遇 `StateError` 在 microtask 重试一次 | 01-04 | ✓ VERIFIED | `mpv.dart:215-217`（observers）与 `:219`（events）均调用；`:683-692` 实现；独立探针证明 retry 必要且有效 |
| 18 | dispose 后首次读取 `audioDevices` 得到已关闭、值为空且未登记进 `_states` 的状态 | 01-04 | ✓ VERIFIED | 新测试通过；`player.dart:343-357` 的 `_disposed` 分支 `unawaited(state._close())`；`stateStreamsForTesting.length` 不变 |
| 19 | `Player._onEvent` 的 `EndFileEvent(reason: error)` 仅在 `_errors` 未关闭时写入 | 01-04 | ✓ VERIFIED（源码不变量） | `player.dart:721-732` 的 `if (!_errors.isClosed)`；当前 dispose 顺序下分支不可达，故无运行时测试，plan 明确以源码门禁为证 |
| 20 | read 失败注入测试在接受 `MpvPlaybackError` 前证明 `readAttempts > 0` | 01-05 | ✓ VERIFIED（静态；运行受门控） | `failure_injection_test.dart:354-358`；计数器在 `read()` 内自增。运行时执行与 #12 同一环境限制 |
| 21 | seek 失败注入测试证明 `seekAttempts > 0`，源提供合法内存 WAV 使 demuxer 真实发起 seek | 01-05 | ✓ VERIFIED（静态；运行受门控） | `_ThrowingSeekSource` + `_silentWavBytes` + `:383-388` 断言；GC-IN-02 限制了“显式 seek”这一更强主张 |
| 22 | `api_freeze_test.dart` 无文件级 analyzer-ignore；VM-only 排除位于 `analysis_options.yaml`；测试仍编译并运行 | 01-05 | ✓ VERIFIED | `grep -c ignore_for_file` = 0；`analysis_options.yaml:10-11` 的 `analyzer.exclude`；`api_freeze_test.dart` 1/1 passed；`dart analyze --fatal-infos` clean |
| 23 | 每条评审发现均已处置：六个 fixed、四个 deferred（含理由与 owner）、零 open | 01-05 | ✓ VERIFIED | `01-REVIEW-DISPOSITION.md` 主表 + gap-closure 表；无 `open` 行 |

**Score:** 19/23 truths verified（4 present, behavior-unverified；0 failed）

### Deferred Items

| # | Item | Addressed In | Evidence |
|---|------|-------------|----------|
| 1 | STAB-01 的 `MpvVideoController` 反复 create/dispose 不泄漏分句 | Phase 2 | ROADMAP Phase 2 需求 STAB-04 / STAB-05；本阶段所有 plan 均未修改 `packages/mpv_kit_video/` |

### Advisory (New Scope, Unevidenced)

| # | Finding | Category | Why Advisory |
|---|---------|----------|--------------|
| 1 | `Mpv._closeIfOpen` 的 microtask retry 未再包 `try/on StateError`（GC-IN-01） | other | 新引入范围；仅在“第二次同步派发重入”或同步执行 microtask 的 zone 下可触发，当前调用点不可达。已记录 deferred，无运行时复现证据 |

## Gap-Closure Review 判定（GC-*）

第一轮评审 `01-REVIEW.md` 与第二轮 `01-REVIEW-GAPCLOSURE.md` 按独立 ID 空间处理。逐条判断是否应计入阶段 must-have：

| Finding | Disposition | 是否推翻 must-have | 理由 |
|---|---|---|---|
| GC-WR-01 CI 注释称 skipped 运行会失败 | fixed | 否 | 注释已改为准确表述（`native-verify.yml:93-96` 明确 `--run-skipped` 是 load-bearing，只有未收集的 suite 才非零退出）。 |
| GC-WR-02 API-freeze 只比较名字、排除构造函数 | deferred | **否** | 这是冻结测试的检测强度缺陷，不表示公共 API 实际发生了变化。我直接比较 `59e9bdf..HEAD` 的 lib diff：所有签名与删除行一致，唯一新增公开成员是两个 `@visibleForTesting` seam。故 must-have #10 由独立证据成立；该缺陷留给 Phase 5 重新基线化。 |
| GC-IN-01 microtask retry 未兜底 | deferred | 否 | 当前调用点不可达；独立探针确认 retry 在派发退栈后运行。记录为 advisory。 |
| GC-IN-02 seekAttempts 可能由启动 refresh seek 满足 | deferred | 否 | 01-05 的真值只要求证明 `_handleSeek` 运行且抛错被兜住，启动 refresh seek 已满足该字面主张；它不声称“显式用户 seek 到达 demuxer”。不构成 must-have 失败，但注释措辞强于证据，已在人工验证项中提示。 |
| GC-IN-03 analyzer.exclude 在所有上下文生效 | fixed | 否 | 注释已明确“在 EVERY context 生效，只有 `dart test` 编译是兜底”（`analysis_options.yaml:4-9`）。 |
| GC-IN-04 WAV 字节写入器重复 | deferred | 否 | 纯可维护性问题，不影响任何行为真值。 |

**额外核查（非评审条目）：** `01-SECURITY.md` 的 T-01-10 证据写着“a JSON-reporter skip check fails a soak that silently does not run”，但 `native-verify.yml` 中并不存在 JSON reporter 或 skip 计数检查（`grep` 仅命中说明性注释）。实际保护是 `--run-skipped` 的存在；威胁在实践上仍被缓解，但该行证据描述不准确，属文档准确性问题，不影响阶段 must-have。

## Required Artifacts

| Artifact | Expected | Status | Details |
| -------- | -------- | ------ | ------- |
| `packages/mpv_kit/lib/src/core/mpv.dart` | dispose 顺序、派发安全关闭助手、`_ensureAlive` 全入口守卫 | ✓ VERIFIED | 734 行；`_closeIfOpen` 于 `:683`；observers/events 均经其关闭；31 个公共入口首句 `_ensureAlive()`；经 barrel 导出 |
| `packages/mpv_kit/lib/src/player/player.dart` | 异常隔离 dispose、状态流登记、惰性 `audioDevices` 关闭、end-file 守卫 | ✓ VERIFIED | 760 行；`audioDevices` 的 `_disposed` 分支 `:345-349`；end-file `isClosed` 守卫 `:724`；`_states` 关闭 `:668-672` |
| `packages/mpv_kit/lib/src/core/stream_bridge.dart` | shutdown 分支与四条 close 路径的错误兜底 | ✓ VERIFIED | 285 行；`:181`、`:203`、`:233` 均有 `catchError`/`on Object`；`close()` 委托 `shutdown()` |
| `packages/mpv_kit/test/mpv_test.dart` | 重入 dispose 回归测试、post-dispose 守卫、流关闭 | ✓ VERIFIED | 331 行；22 passed；新测试 `:300-322` |
| `packages/mpv_kit/test/player_test.dart` | throwing-hook、post-dispose `audioDevices` | ✓ VERIFIED | 282 行；18 passed；新测试 `:260-272` |
| `packages/mpv_kit/test/failure_injection_test.dart` | 监听器/hook/流源失败注入，含计数器证明 | ✓ VERIFIED | 468 行；4 passed，3 条能力门控 skip（明确原因） |
| `packages/mpv_kit/test/lifecycle_test.dart` | 1000-cycle soak、文件级调用说明 | ✓ VERIFIED | 76 行；显式运行 1 passed（8s）；默认 1 skipped |
| `packages/mpv_kit/test/api_freeze_test.dart` | API 冻结（名字级） | ✓ VERIFIED | 186 行；0 个 `ignore_for_file`；1/1 passed |
| `packages/mpv_kit/analysis_options.yaml` | VM-only 测试的配置级排除 | ✓ VERIFIED | `analyzer.exclude: [test/api_freeze_test.dart]`，注释说明全上下文生效 |
| `packages/mpv_kit/dart_test.yaml` | lifecycle tag 默认 skip 与文件级命令 | ✓ VERIFIED | 9 行；skip 文案与 CI 命令一致 |
| `.github/workflows/native-verify.yml` | 两个显式 tag 调用、文件级 soak | ✓ VERIFIED | `:97` failure-injection；`:98` 文件级 lifecycle `--run-skipped` |

## Key Link Verification

| From | To | Via | Status | Details |
| ---- | -- | --- | ------ | ------- |
| `Player.dispose` | `Mpv.dispose` → `bindings.terminateDestroy` | 顺序调用 | ✓ WIRED | `player.dart:663-665` → `mpv.dart:202` |
| `Player._states` | `MpvState._close` → `StreamController.close` | 逐条 stage | ✓ WIRED | `player.dart:670-672` → `:41`；两个测试与 soak 证明 done |
| `Mpv._onWakeup` → `_dispatch` → `_events.add` | listener → `Mpv.dispose` → `_closeIfOpen(_events)` → `scheduleMicrotask` retry → done | 重入链 | ✓ WIRED | `mpv.dart:636-664`、`:683-692`；新测试 + 独立探针 |
| `Mpv.dispose` observer 快照循环 | `_closeIfOpen(c)` | snapshot + helper | ✓ WIRED | `mpv.dart:215-217` |
| 公共入口 | `_ensureAlive` → `_disposed` → `StateError` | 首句守卫 | ✓ WIRED | 31 个方法；调用表证明无 native 进入 |
| `observeProperty.onListen` | `_disposed` 检查 → 禁止 native | onListen 分支 | ✓ WIRED | `mpv.dart:464-471`；late-listen 测试 |
| `Player.audioDevices` 惰性初始化 | `_disposed` 分支 → `unawaited(state._close())` → done | 首次读取 | ✓ WIRED | `player.dart:343-357`；目标测试 |
| `Player._onEvent` `EndFileEvent(error)` | `!_errors.isClosed` → `_errors.add` | isClosed 守卫 | ✓ WIRED（源码） | `player.dart:721-732`；运行时不可达 |
| `StreamBridge._handleRead/_handleSeek` | 映射 mpv 错误码 | `on Object` | ✓ WIRED（静态） | `stream_bridge.dart:255-259`、`:273-281`；运行受 patch 0006 门控 |
| 四处 `source.close()` | 错误兜底 | `catchError`/`on Object` | ✓ WIRED（静态） | `:181`、`:203`、`:233`，`close()`→`shutdown()` `:188` |
| `dart_test.yaml` lifecycle skip | CI 文件级 `--run-skipped` | tag 默认 + 显式调用 | ✓ WIRED | 默认 JSON 1 次 skip；显式 1 passed；CI 两条命中 |

## Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
| -------- | ------------- | ------ | ------------------ | ------ |
| `mpv.dart` | `_events` / `_observers` | `bindings.waitEvent` → `MpvEventData.decode` | 是（live libmpv 测试观察到 PropertyChange/EndFile 等事件） | ✓ FLOWING |
| `player.dart` | 各 `MpvState` | `mpv.observeProperty(...)` 订阅回调 | 是（`pause/volume/...` round-trip 测试通过） | ✓ FLOWING |
| `stream_bridge.dart` | 流源 read/seek/close | 原生 demuxer 请求回调 | 设计上为真；本地 stock libmpv 无法执行 | ✓ FLOWING（运行时环境受限） |

## Behavioral Spot-Checks

| Behavior | Command | Result | Status |
| -------- | ------- | ------ | ------ |
| 静态分析干净 | `cd packages/mpv_kit && dart analyze --fatal-infos` | `No issues found!` | ✓ PASS |
| 重入 dispose 回归 | `dart test test/mpv_test.dart -n "dispose from a synchronous events listener"` | 1 passed | ✓ PASS |
| post-dispose `audioDevices` | `dart test test/player_test.dart -n "audioDevices first read after dispose"` | 1 passed | ✓ PASS |
| mpv/player/api 三个套件 | `dart test test/mpv_test.dart test/player_test.dart test/api_freeze_test.dart` | 41 passed | ✓ PASS |
| failure-injection | `dart test -t failure-injection test/failure_injection_test.dart` | 4 passed，3 skipped（patch 0006，明确原因） | ✓ PASS（含环境门控） |
| 默认 lifecycle skip | `dart test test/lifecycle_test.dart --reporter json \| grep -c '"skipped":true'` | 1 | ✓ PASS |
| 1000-cycle soak | `dart test test/lifecycle_test.dart -t lifecycle --run-skipped` | 1 passed（8s） | ✓ PASS |
| 全量默认套件 | `dart test` | 90 passed，5 skipped，5 failed | ✓ 记录（5 failed 全为 `stream_bridge_test.dart` 缺 patch 0006，既有环境基线） |
| 底层关闭语义探针 | 仓库外最小 `dart` 探针：有/无 microtask retry | retry=true → `isClosed=true`, done 投递；retry=false → `isClosed=false`, done 不投递；两者均捕获到同步 `StateError` | ✓ PASS（证明 retry 是必要条件） |
| 公共 API 直接比对 | `git diff 59e9bdf..HEAD -- packages/mpv_kit/lib` | 方法签名与删除行一致；仅新增两个 `@visibleForTesting` seam | ✓ PASS |

## Probe Execution

未发现 `scripts/*/tests/probe-*.sh`，PLAN/SUMMARY 也未声明 probe 脚本；本阶段不是迁移/工具化阶段。N/A。

## Test Quality Audit

| Test File | Linked Req | Active | Skipped | Circular | Assertion Level | Verdict |
| --------- | ---------- | ------ | ------- | -------- | --------------- | ------- |
| `player_test.dart` | STAB-02, STAB-01 | 18 | 0 | 否 | Behavioral（核心销毁 + done + 错误 identity + 惰性状态关闭） | ✓ |
| `mpv_test.dart` | STAB-03, STAB-01 | 22 | 0 | 否 | Behavioral（31 调用表 + native 计数 + 重入 dispose） | ✓ |
| `api_freeze_test.dart` | API 冻结 | 1 | 0 | 否 | Value（名字集合相等；构造函数/签名未覆盖，GC-WR-02） | ✓（有已知限制） |
| `failure_injection_test.dart` | VERIFY-03 | 4 | 3（能力门控） | 否 | Behavioral；read/seek 有计数器证明，seek 的“显式 seek”不可区分（GC-IN-02） | ⚠️ 环境受限 |
| `lifecycle_test.dart` | STAB-01 | 1（默认 tag skip） | 0（执行时） | 否 | Behavioral（done + RSS 上限） | ✓ |

- 硬禁用测试（`test.skip`/`xit`/`describe.skip`）：0。
- 循环测试：0。
- 债务标记（`TBD`/`FIXME`/`XXX`/`TODO`/`HACK`）在本阶段改动文件中：0。
- 三条流源测试是各自失败路径的唯一证明，skip 是显式能力门控且 CI 会执行，因此记为环境受限而非 BLOCKER。

## Requirements Coverage

| Requirement | Source Plan | 描述 | Status | Evidence |
| ----------- | ----------- | ---- | ------ | -------- |
| STAB-01 | 01-01, 01-03, 01-04, 01-05 | 反复创建/销毁 Player 不泄漏，events/状态流正确关闭 | ✓ SATISFIED（Phase 1 范围） | 1000-cycle soak；35 条 seam 流 + errors/logs 全部 done；重入 dispose 修复并测试；`MpvVideoController` 分句按 Scope note 推迟到 Phase 2（见 Deferred） |
| STAB-02 | 01-01, 01-04 | 抛错 hook 仍完成核心销毁且可重复调用 | ✓ SATISFIED | throwing-hook 测试 + failure-injection hook 测试；`same(sentinel)`；重入 dispose 关闭错误被兜住，不再逃逸 |
| STAB-03 | 01-02 | dispose 后公共方法抛 `StateError`，无 native use-after-free | ✓ SATISFIED | 31 调用表全部抛 `StateError`；native-entry 计数平坦；late-listen 测试通过 |
| VERIFY-03 | 01-03, 01-05 | 关键失败路径有回归测试（失败注入、抛错监听器/hook、异常流源） | ✓ SATISFIED（异常流源待 CI 确认） | 监听器/hook 4 条本地通过；3 条异常流源带 tag、CI 显式调用、read/seek 有计数器证明，本地因 patch 0006 skip（见 behavior-unverified） |

**Orphaned requirements:** 无。Phase 1 的 4 个 ID 均出现在至少一个 PLAN 的 `requirements` 字段中，并在 REQUIREMENTS.md 映射到 Phase 1。

## Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
| ---- | ---- | ------- | -------- | ------ |
| `packages/mpv_kit/lib/src/core/mpv.dart` | 688-690 | microtask retry 未再包 `try/on StateError`（GC-IN-01） | ℹ️ INFO | 当前调用点不可达；记录为 deferred/advisory |
| `packages/mpv_kit/test/failure_injection_test.dart` | 373-386 | `seekAttempts` 可能由启动 refresh seek 满足（GC-IN-02） | ℹ️ INFO | 不影响“抛错被兜住”契约，但不能证明显式 seek；记录为 deferred |
| `packages/mpv_kit/test/api_freeze_test.dart` | 17-25, 164-186 | API-freeze 只比较名字、排除构造函数（GC-WR-02） | ℹ️ INFO | 预存在缺陷；本阶段通过直接 diff 证明无公共 API 变化 |
| `packages/mpv_kit/test/player_test.dart` / `failure_injection_test.dart` | 24-48 / 106-130 | WAV 字节写入器重复（GC-IN-04） | ℹ️ INFO | 可维护性；记录为 deferred |
| `.planning/phases/.../01-SECURITY.md` | T-01-10 行 | 声称存在 JSON-reporter skip 检查，实际 CI 无此检查 | ℹ️ INFO | 文档证据不准确；实际保护是 `--run-skipped` 的存在 |

**Debt markers:** 本阶段改动文件中无 `TBD`/`FIXME`/`XXX`/`TODO`/`HACK`。
**Stub classification:** 无 stub；两处 `return null` 是 `tryGetProperty`/`getPropertyString` 的合法可空语义。

## Human Verification Required

本阶段为库/基础设施层，无用户可见 UI；以下不是人工 UAT，而是需要在 patched libmpv（patch 0006）或 CI 环境执行的行为验证：

### 1. 抛错 read 源

**Test:** 在导出 `mpv_kit_stream_add` 的 libmpv 上运行 `cd packages/mpv_kit && dart test -t failure-injection test/failure_injection_test.dart`
**Expected:** `a source whose read throws reports an MpvPlaybackError` 通过：`readAttempts > 0`，`Player.errors` 收到非空 message，dispose ≤10s。
**Why human:** 本地 stock libmpv 缺 patch 0006，测试按能力显式 skip；代码链路静态存在但本地未执行。

### 2. 抛错 seek 源

**Test:** 同一 patched 环境运行 seek 测试
**Expected:** `a source whose seek throws leaves the open contained` 通过：`seekAttempts > 0`、无挂起、无未捕获错误、dispose ≤10s。
**Why human:** 同上；GC-IN-02 提示若要证明显式 seek，需先 `drop-buffers` 或用更大 WAV 并 await seek future。

### 3. 抛错 close 源

**Test:** 同一 patched 环境运行 close 测试
**Expected:** `a source whose close throws is contained on every close path` 通过：两个 zone error 列表为空，`closeAttempts > 0`，dispose ≤10s。
**Why human:** 同上；四条 close 路径的运行时覆盖只能在 patched 环境执行。

### 4. CI 首次真实执行

**Test:** 观察 `native-verify.yml` Linux Dart-tests 步骤的 `dart test -t failure-injection` 与 `dart test test/lifecycle_test.dart -t lifecycle --run-skipped`
**Expected:** 两条命令 0 退出；failure-injection 的 3 条流源测试显示为通过而非 skip；lifecycle 显示 1 passed。
**Why human:** CI 是这些环境门控测试的首次真实执行环境，本地无法代跑。

## Gaps Summary

上一轮的唯一 BLOCKER 已独立确认关闭：`Mpv.dispose()` 从同步 `Mpv.events` 监听器内重入时不再抛错，`events` 仍收到 `done`，第二次 dispose 为无异常 no-op；`_closeIfOpen` 作为单一派发安全关闭路径同时覆盖 `_events` 与全部 observer。配套的 `audioDevices` 惰性状态关闭与 end-file 错误守卫也已核实。核心阶段目标（反复创建/销毁不泄漏、异常 teardown 不崩溃、dispose 后调用可预测失败）在真实 libmpv 上成立。

没有新的 FAILED 真值、MISSING/STUB 工件或 NOT_WIRED 关键链接，因此不构成 `gaps_found`。剩余 4 条行为未验证项全部是 stream-source 失败注入的环境限制（本地缺 native patch 0006，CI 才是首次执行环境），已诚实记录并路由为人工验证，故状态为 `human_needed` 而非 `passed`。六条 gap-closure 评审发现中，GC-WR-01/GC-IN-03 已修复，其余为预存在或不可达的低风险项且均有 owner/trigger；其中 GC-WR-02 的冻结测试强度缺陷已由本轮的直接 diff 核查补偿，不推翻任何阶段 must-have。

---

_Verified: 2026-10-24T01:09:43Z_
_Verifier: Claude (gsd-verifier)_

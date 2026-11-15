---
phase: 01-player-lifetime-dispose-safety
reviewed: 2026-10-24T00:00:00Z
depth: standard
files_reviewed: 10
files_reviewed_list:
  - .github/workflows/native-verify.yml
  - packages/mpv_kit/dart_test.yaml
  - packages/mpv_kit/lib/src/core/mpv.dart
  - packages/mpv_kit/lib/src/core/stream_bridge.dart
  - packages/mpv_kit/lib/src/player/player.dart
  - packages/mpv_kit/test/api_freeze_test.dart
  - packages/mpv_kit/test/failure_injection_test.dart
  - packages/mpv_kit/test/lifecycle_test.dart
  - packages/mpv_kit/test/mpv_test.dart
  - packages/mpv_kit/test/player_test.dart
findings:
  critical: 1
  warning: 4
  info: 5
  total: 10
status: issues_found
---

# Phase 01: Code Review Report

**Reviewed:** 2026-10-24
**Depth:** standard
**Files Reviewed:** 10
**Status:** issues_found

## Summary

本阶段把 `Player`/`Mpv` 的 dispose 路径改成了分阶段、错误收集式的清理，并为 `Mpv` 的 31 个公共入口加上了 `_ensureAlive()` 存活门禁；原生侧的顺序（先置空 wakeup 回调 → 关闭 stream bridge → 销毁句柄 → 关闭 `NativeCallable`）是正确的，`position`/`decodeWarning` 也已登记进 `_states`。新增的 failure-injection、lifecycle soak 与 API-freeze 测试总体有效，本地实测 `mpv_test`/`player_test`/`api_freeze_test`/lifecycle soak 全部通过（`dart analyze --fatal-infos` 干净）。

但对抗性复核发现一个可复现的严重缺口：**从 `Mpv.events` 监听器内同步调用 `Mpv.dispose()` 会直接抛出 `StateError`，且 `Mpv.events` 永远不再发出 `done`**——这正是 `CONCERNS.md` 里 “Reentrant disposal from event listeners” 一项，计划把它列入了 `read_first` 却没有修复也没有测试；它与本阶段宣称的 “Mpv.events 在 dispose 后必然发出 done / dispose 不抛异常” 直接矛盾（本报告已用真实 libmpv 复现，见 CR-01）。此外还有若干测试证明力不足与子客户端生命周期未覆盖的问题。

说明：本地 stock libmpv 缺少 patch 0006，三个 stream-bridge 失败注入测试按显式能力检查 skip；这是任务说明中明确排除的预期行为，不计为缺陷。

## Critical Issues

### CR-01: 从 `Mpv.events` 监听器内调用 `Mpv.dispose()` 会抛异常且 `events` 永不关闭

**File:** `packages/mpv_kit/lib/src/core/mpv.dart:188-220`（关键行 `219` 的 `_events.close()`）
**Issue:**
`Mpv._events` 是 `StreamController<MpvEventData>.broadcast(sync: true)`（`mpv.dart:105`）。`_dispatch()` 在同步广播派发过程中调用监听器；如果监听器同步调用 `Mpv.dispose()`，dispose 会在派发尚未结束时执行到 `unawaited(_events.close())`。Dart 对 “正在派发中的同步广播控制器” 调用 `close()` 会抛：

```
Bad state: Cannot fire new event. Controller is already firing an event
```

该异常从 `Mpv.dispose()` 同步抛给监听器调用方；更糟的是 `close()` 在抛错前没有把 `_state` 置为 closed，而 `dispose()` 已经执行了 `_disposed = true`，因此第二次 `dispose()` 直接 early-return，`Mpv.events` **永远不会 close、永远收不到 `done`**。实测（真实 libmpv，临时探针，运行后已删除）：

```
first dispose THREW SYNCHRONOUSLY: Bad state: Cannot fire new event. Controller is already firing an event
events done delivered after failed dispose: false
```

这条路径正是 `.planning/codebase/CONCERNS.md:425-434` 记录的 “Reentrant disposal from event listeners”，也是 01-03 任务 `read_first` 中引用过的小节；本阶段既未修复也未添加回归测试。它违反 STAB-01（dispose 后事件流必须发出 done）与 STAB-02（dispose 不得以异常方式失败）。注意：`Player.dispose()` 因为在关闭任何控制器之前有 `await`，不会触发该问题；问题只出现在低层 `Mpv` 公共 API（包括应用直接 `player.mpv.events.listen(...)` 后调用 `player.mpv.dispose()` 的写法）。`_observers` 的 close 循环目前不会抛（`observeProperty` 用的是单订阅 sync 控制器），但同样缺乏异常防护。

**Fix:**
把控制器关闭做成“派发中安全”的：先尝试 close，捕获 `StateError` 后推迟到微任务重试；`_observers` 与 `_events` 都走同一个 helper：

```dart
/// Closes [c] even when a listener re-entered `dispose()` from inside a
/// synchronous broadcast dispatch (closing while firing throws).
static void _closeIfOpen<T>(StreamController<T> c) {
  if (c.isClosed) return;
  try {
    unawaited(c.close());
  } on StateError {
    // Our own dispatch is still on the stack: close on the next turn.
    scheduleMicrotask(() {
      if (!c.isClosed) unawaited(c.close());
    });
  }
}
```

```dart
for (final c in _observers.values.toList()) {
  _closeIfOpen(c);
}
_observers.clear();
_closeIfOpen(_events);
```

并补一条回归测试（`mpv_test.dart`，放在 `post-dispose guard` 组内）：在 `mpv.events` 的监听器里调用 `mpv.dispose()`，断言不抛、5 秒内收到 `done`、`mpv.isDisposed` 为 true。

## Warnings

### WR-01: 存活的子客户端会让 `mpv_terminate_destroy` 永久阻塞，新守卫也覆盖不到子句柄

**File:** `packages/mpv_kit/lib/src/core/mpv.dart:155-171`（`createClient`）、`188-220`（`dispose`）
**Issue:**
`createClient()` 返回 `owner: false` 的 `Mpv`，它持有独立句柄与独立的 `_disposed` 标志。原生侧 `mp_destroy_client()` → `mp_shutdown_clients()`（`native/mpv/player/client.c:543-578`）会 `while (clients->num_clients ...)` 等待**所有**句柄被销毁，并向子客户端广播 `SHUTDOWN`；而 `mpv_terminate_destroy` 在核心线程 join 期间阻塞调用线程。由于调用线程就是 Dart isolate 线程，子客户端的 wakeup 回调无法被处理，`child.dispose()` 也永远排不上——只要用户创建过 `createClient()`（尤其 `weak: true`）而忘记先 dispose 子句柄，`Player.dispose()`/`Mpv.dispose()` 就会永久挂起。这是既有设计问题（非本阶段引入），但本阶段的 “dispose 不得 hang / 销毁后任何公共入口安全” 表述没有覆盖它，且新的 `_ensureAlive` 对父核心已终止的子实例无法生效（子实例 `_disposed == false`）。
**Fix:**
至少把契约写进 `Mpv.dispose()`/`createClient()` 的文档（“子句柄必须在其父句柄 dispose 之前销毁，否则 `mpv_terminate_destroy` 会阻塞”），并建议在 `Mpv` 内维护子实例集合，在 owner 的 `dispose()` 中先递归 dispose 子实例（对外 API 不变，仅内部登记）。同时补一条测试：创建 `weak: true` 子客户端后直接 dispose 父实例，断言在超时内完成（当前会挂起，可加 `.timeout` 先暴露问题）。

### WR-02: `StreamBridge.shutdown()` 在 `read()`/`seek()` 尚未完成时调用 `source.close()`，违反 `MpvStreamSource` 的“同时只有一个调用”契约

**File:** `packages/mpv_kit/lib/src/core/stream_bridge.dart:176-184`（`shutdown`）、`246-284`（`_handleRead`/`_handleSeek`）
**Issue:**
`MpvStreamSource` 的文档（`stream_bridge.dart:23-25`）承诺 “mpv 对每个 stream 一次只调用一个方法，因此实现无需加锁；close 只调用一次，之后不再有其它调用”。但 `shutdown()` 会直接对 `_sources` 里的每个 source 调 `close()`，而此时 `_handleRead`/`_handleSeek` 可能正 `await source.read(...)`/`source.seek(...)`（Dart 单 isolate 下，被挂起的 future 不会阻止同步 close）。新增的失败注入测试 `_ThrowingCloseSource(blockReads: true)`（`failure_injection_test.dart:361-369`）正是在刻意制造 “read pending 时 close” 的场景。对按文档实现、在 `read` 里使用文件句柄/缓冲区的用户源码，这会变成 close-after-free 式的竞态；同时被放弃的 read future 永远不会完成（每个这样的 source 泄漏一个挂起的异步栈）。
**Fix:**
二选一：(a) 在 `StreamBridge` 里跟踪每个 stream 的在途调用，`shutdown()` 等其结束后再 close（或对 close 使用 `Future` 编排）；(b) 保持现状但在 `MpvStreamSource` 文档中明确声明 “shutdown/dispose 时 `close()` 可能不可重入地与一个未完成的 `read`/`seek` 并发调用，实现必须容忍”，并说明 pending future 可能永不完成。无论哪种，都应让测试注释引用该契约。

### WR-03: seek 失败注入测试无法证明 `_handleSeek` 真正被执行

**File:** `packages/mpv_kit/test/failure_injection_test.dart:298-332`
**Issue:**
`_ThrowingSeekSource.read` 立即返回空字节（EOF），且 `open`/`seek` 两侧都用 `on Object` 吞掉失败，也不统计 `seek` 调用次数。只要 mpv 在 EOF 后根本没走到 seek（或 `start` 选项被忽略），测试仍然绿——它只能证明“没有挂起/没有未捕获异常”，不能证明计划要求的 “`_handleSeek` 的 `on Object` 映射路径被覆盖”。该测试在本地因缺少 patch 0006 被 skip，CI 是它第一次真正执行，因此这个证明力缺口风险更高。
**Fix:**
在 `_ThrowingSeekSource` 上加 `int seekAttempts = 0;`，`seek()` 里自增后抛错；测试结束前 `expect(source.seekAttempts, greaterThan(0))`（或用 `_waitFor` 等待它 > 0）。同理可给 `_ThrowingReadSource` 加 `readAttempts` 并在断言 `MpvPlaybackError` 之前先确认 read 路径确实被执行。

### WR-04: “soak 在独立进程中独自运行” 的隔离结论不成立，RSS 观测窗口仍与其它 suite 的加载重叠

**File:** `.github/workflows/native-verify.yml:87-94`、`packages/mpv_kit/dart_test.yaml:4-8`、`packages/mpv_kit/test/lifecycle_test.dart:1-14`
**Issue:**
CI 使用 `dart test -t lifecycle --run-skipped`（无文件参数）。实测该命令会加载 `test/` 下**所有** suite（输出中同时出现 `api_freeze_test.dart`、`api_surface_test.dart`、`audio_devices_test.dart`、`failure_injection_test.dart`、`format_matrix_test.dart`、`lifecycle_test.dart` 的 loading 行），它们与 lifecycle 测试处于同一 runner 进程；`ProcessInfo.currentRss` 是进程级指标。当前本地运行里其它 suite 在 soak 开始前已加载完毕，所以结果稳定，但 `dart_test.yaml`/SUMMARY 里 “runs alone, in its own process” 的表述并不准确，慢速 CI runner 上其它 suite 的加载/初始化分配可能落进测量窗口，让 64 MiB 泄漏阈值出现假阳性（或掩盖真实增量）。
**Fix:**
把 CI 的显式调用改成只加载该 suite：`dart test test/lifecycle_test.dart -t lifecycle --run-skipped`（本地已验证单文件可运行），并把 `dart_test.yaml`/注释改为“按测试选择隔离（同进程仅加载其它 suite，不执行其测试）”，不要宣称独立进程。

## Info

### IN-01: `api_freeze_test.dart` 的宽泛 `ignore_for_file` 违反项目约定，可能掩盖真实错误

**File:** `packages/mpv_kit/test/api_freeze_test.dart:5-10`
**Issue:**
该行一次性屏蔽 `uri_does_not_exist, undefined_function, undefined_identifier, undefined_name, type_test_with_undefined_name, unchecked_use_of_nullable_value`。项目惯例是手写代码不使用 ignore 指令；而 CI 的 Dart-only workspace 能正常解析 `dart:mirrors`，这里真正需要的只是本地 Flutter workspace 的解析差异。范围过宽会在该文件出现真实拼写/类型错误时把错误一起吞掉（测试仍可能因为镜像断言失败，但诊断信息会失真）。
**Fix:**
优先在 `analysis_options.yaml` 中对该测试文件使用 `analyzer: exclude:` 或单独的分析配置，而不是在源码里 ignore；若保留，至少收窄到 `uri_does_not_exist` 及其直接级联错误，并在 CI 侧确认无 `unnecessary_ignore` 诊断。

### IN-02: `errorString`/`eventName` 被 `_ensureAlive` 守卫，但它们并不触碰句柄

**File:** `packages/mpv_kit/lib/src/core/mpv.dart:606-616`
**Issue:**
`bindings.errorString(code)` / `bindings.eventName(eventId)` 是 libmpv 的纯查表函数，不需要 `handle`。加上守卫后，dispose 后调用这两个方法从“可用”变成了抛 `StateError`，属于冻结 API 上的语义变化，且没有对应的原生安全收益；同时它们会把 `_nativeEntries` 计为一次 “native entry”，让该计数器的语义（“进入 native 边界”）变得模糊（`observeProperty` 的 onListen 还会二次计数）。
**Fix:**
要么不加守卫（保持原行为），要么把计数器改成真正包住 `bindings.*` 调用的私有 helper，并调整 `nativeEntriesForTesting` 的文档措辞。

### IN-03: `audioDevices` 在 dispose 之后首次访问会返回一个永远不会 close 的状态流

**File:** `packages/mpv_kit/lib/src/player/player.dart:343-352`
**Issue:**
`audioDevices` 是惰性字段：`if (_disposed) return state;` 分支跳过了 `_bind`，因此该 `MpvState` 不会进入 `_states`。若在 `Player.dispose()` 开始后（此时 `_disposed` 已为 true）首次访问并监听它，该流永远不会收到 `done`，与 “所有状态流在 dispose 后关闭” 的相位不变量存在一个惰性扫描遗漏。
**Fix:**
在该分支里直接关闭新 state 的 controller（或在 `_disposed` 时返回一个已关闭的 state），并在文档/测试中注明 `stateStreamsForTesting` 不包含未初始化的惰性状态。

### IN-04: `Player._onEvent` 的 EndFile 分支缺少 `_errors.isClosed` 守卫，与 `_logs` 分支不一致

**File:** `packages/mpv_kit/lib/src/player/player.dart:714-733`
**Issue:**
`LogMessageEvent` 分支有 `if (!_logs.isClosed)`，而 `EndFileEvent(reason: error)` 分支直接 `_errors.add(...)`。正常 dispose 顺序（先取消 `_subs` 再 close `_errors`）下不可达，但一旦未来调整顺序或在事件派发/关闭之间引入重入，就会把 `Bad state: Cannot add new events after calling close` 抛进 `unawaited` 的事件排空路径。
**Fix:**
统一为 `if (!_errors.isClosed) _errors.add(...)`，并考虑在 `dispose()` 里用一个统一的 `_closeIfOpen` helper（见 CR-01）覆盖 `_errors`/`_logs`。

### IN-05: 并发/重复调用 `Player.dispose()` 时，第二次调用不会等待第一次完成

**File:** `packages/mpv_kit/lib/src/player/player.dart:635-674`
**Issue:**
`dispose()` 以 `if (_disposed) return;` 开头，因此第一次 dispose 在 `await` 某个 hook/订阅取消期间，第二次 `dispose()` 会立即返回一个已完成的 future。调用方如果 `await player.dispose()` 期待“清理完成”，可能看到 `player.mpv.isDisposed == false` 或仍有未关闭的状态流。现有测试只在第一次完全结束后再调用第二次，因此没有覆盖这个语义。
**Fix:**
缓存进行中的 dispose future（如 `Future<void>? _disposeFuture; Future<void> dispose() => _disposeFuture ??= _dispose();`），让并发调用共享同一个完成信号；或在文档中明确“第二次调用只保证幂等，不保证等待”。

---

**本地验证记录（供复现）：**
- `dart analyze --fatal-infos` → No issues found。
- `dart test test/mpv_test.dart test/player_test.dart test/api_freeze_test.dart` → 39/39 passed。
- `dart test -t failure-injection test/failure_injection_test.dart` → 4 passed，3 skipped（显式 patch-0006 能力检查，非缺陷）。
- `dart test -t lifecycle --run-skipped` → 1 passed（9 s）。
- CR-01 / WR-04 的证据来自临时探针测试，运行后已删除，未留在工作区。

---

_Reviewed: 2026-10-24_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_

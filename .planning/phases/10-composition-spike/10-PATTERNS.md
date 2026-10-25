# Phase 10: Composition Spike（GAP CLOSURE / `--gaps`）- Pattern Map

**Mapped:** 2026-10-25
**Files analyzed:** 3（1 个 Dart 实现文件 + 2 个文档），另有 6 个可再生成的 evidence 产物
**Analogs found:** 3 / 3 主文件均有强匹配；WR-02 一个子项无同构先例

本文件只服务于「收口」而非新阶段：**不新建源码文件**，只修 `impeller_smoke_test.dart` 的三个缺陷（CR-01 / CR-02 / WR-02），并同步两份文档（WR-06 / WR-07 / IN-02 / IN-03），再重跑两种开关。

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `example/integration_test/impeller_smoke_test.dart`（改：报告通道、就绪门、像素切片） | test（integration harness） | event-driven（原生 `MpvVideoEvent` 流）+ request-response（`setSize` method channel）+ console output（BENCH 行） | `example/integration_test/playback_bench_test.dart` + `uhd_endurance_test.dart` + `real_plugin_test.dart` | exact（同目录、同 binding、同 BENCH 约定） |
| `docs/adr/0003-windows-composition-path.md`（改：Phase 11 前置补 reporting-channel、evidence 路径、行号） | documentation（ADR） | 叙述性证据，无运行时数据流 | 同文件既有结构（`verdict:`/`identity:` 头、Evidence 表、Q1–Q5 表） | role-match（自参照；改动必须保持既有 gate 键） |
| `docs/reverse-engineering/03-flutter-windows-texture-consumption.md`（改：evidence 路径、Q1 状态、行号） | documentation（REA 报告） | 叙述性证据，无运行时数据流 | 同文件既有结构 + `docs/reverse-engineering/02-flutter-windows-external-texture.md` | role-match |
| `.planning/phases/10-composition-spike/evidence/impeller-*.log` / `impeller-bench.txt`（重跑后重写） | test evidence artifact | file-I/O | 现有同名文件（本阶段已提交的两次运行） | exact（同名覆盖） |

> 三个主文件均已 `git ls-files` 确认是 **tracked source**（非 `.gsd/capabilities/` 之类的同步镜像），可以安全作为 analog。

---

## Pattern Assignments

### 1. `example/integration_test/impeller_smoke_test.dart`（test, event-driven + console output）

**Analogs:** `example/integration_test/playback_bench_test.dart`、`uhd_endurance_test.dart`、`real_plugin_test.dart`

三份 sibling harness 共享同一套「integration test 即驱动 + `print` 即报告通道 + 一个 `testWidgets` + `runAsync` 包住真实等待」的结构。当前文件唯一偏离这套结构的点就是报告通道（CR-01）。

#### 1a. CR-01 —— 报告通道（改用 `print`）

**Analog:** `playback_bench_test.dart:15-17`

```dart
// Printing is the report channel (integration tests have no console logger):
// ignore_for_file: avoid_print
@TestOn('windows')
library;
```

`uhd_endurance_test.dart:25-26` 与 `real_plugin_test.dart:14-15` 是同一条约定的另两处副本：

```dart
// Printing is the report channel:
// ignore_for_file: avoid_print
```

调用点（全部是 `print`，不是 `stdout`）：

```dart
// playback_bench_test.dart:113
print('BENCH playback ${jsonEncode({
      'metrics': r,
      'videoSize':
          '${player.videoParams.value?.width}x${player.videoParams.value?.height}',
    })}');

// uhd_endurance_test.dart:156
print('BENCH uhd ${jsonEncode(result)}');

// real_plugin_test.dart:81
print('INTEGRATION ${jsonEncode({
      'backend': controller.backend.name,
      'reason': controller.reason,
      ...
    })}');
```

**当前实现（缺陷所在）** — `impeller_smoke_test.dart:51-54`：

```dart
/// One BENCH line on stdout. Integration tests have no console logger.
void _emitBench(Map<String, Object?> payload) {
  stdout.writeln('BENCH impeller ${jsonEncode(payload)}');
}
```

**要照抄的形状：**

```dart
/// One BENCH line on stdout. Integration tests have no console logger.
void _emitBench(Map<String, Object?> payload) {
  print('BENCH impeller ${jsonEncode(payload)}');
}
```

并在 library 指令上方补上与 sibling 完全一致的抑制注释（`example/` 下使用 `package:flutter_lints/flutter.yaml`，`avoid_print` 必须显式豁免；该目录三份 harness 都用同一句）：

```dart
// Printing is the report channel:
// ignore_for_file: avoid_print
@TestOn('windows')
library;
```

**注意（不要顺手改坏）：**
- `dart:io` 仍然要保留——`Platform.version`、`Platform.environment`、`ProcessInfo.currentRss` 都在用它；只是不再需要 `stdout`。
- `debugPrint` 虽也可达（`video_controller.dart:210` 的 `mpv_kit_video: ...` 行在日志里出现过），但它会按行截断/加前缀并做节流；BENCH JSON 必须原样单行可解析，所以选 `print`，与三份 sibling 一致。
- 收口验收标准：**preflight 行必须在任何工作负载之前出现在采集日志里**（`grep -c BENCH <log>` ≥ 1），这是 WR-06 之外最容易再次误判成「渲染器失败」的地方。

#### 1b. CR-02 —— part-1 就绪门必须可满足

**Analog（可满足的门长什么样）:** `real_plugin_test.dart:55-79`

```dart
// Readiness 1: the decoder reports the requested size.
var paramsReady = false;
// Readiness 2: the VO produced frames (fps estimate exists) — this is
// the "rendered a frame" proof; it requires the render context to
// actually consume and present decoded frames.
var framesFlowing = false;
final deadline = DateTime.now().add(const Duration(seconds: 30));
while (DateTime.now().isBefore(deadline) &&
    !(paramsReady && framesFlowing)) {
  await Future<void>.delayed(const Duration(milliseconds: 200));
  final vp = player.videoParams.value;
  if (vp?.width == 640 && vp?.height == 360) paramsReady = true;
  if (player.mpv.tryGetProperty('estimated-vf-fps') != null) {
    framesFlowing = true;
  }
}
```

`uhd_endurance_test.dart:76-85` 是同一形状的极简版（只等 `videoParams` 尺寸），可用于第二段的 4K 尺寸确认。

**当前实现（缺陷所在）** — `impeller_smoke_test.dart:217-235`：

```dart
final resizeBaseline = _resizeEvents;
final part1Ready = await _waitUntil(() {
  final params = player.videoParams.value;
  final fps = player.mpv.tryGetProperty('estimated-vf-fps');
  return params?.width == 1920 &&
      params?.height == 1080 &&
      fps is num &&
      fps > 0 &&
      _resizeEvents > resizeBaseline;
}, timeout: const Duration(seconds: 30));
```

前三个条件会成立（实测日志里就是 `params=1920x1080 fps=30`），第四个永远不成立，因为 `resize` 只能由 native `SetSize` 驱动（见下文「Native contract」）。

**要照抄的形状（最小改动，仍然保留 resize 证据）：** 在取基线之前先显式设置一次尺寸，并把「等视频就绪」与「等 resize 到达」拆成两步：

```dart
// Wait until the source is actually decoded (real_plugin_test.dart:55-70).
await _waitUntil(() {
  final params = player.videoParams.value;
  return params?.width == 1920 && params?.height == 1080;
}, timeout: const Duration(seconds: 30));

// The renderer's width_/height_ start at 0 and only SetSize writes them
// (video_renderer.cc:166-176); `resize` is emitted after the ring is
// (re)allocated (video_renderer.cc:500-541). So the baseline must be taken
// BEFORE the first setSize, not after playback starts.
final resizeBaseline = _resizeEvents;
await controller.setSize(1920, 1080);
final part1Ready = await _waitUntil(() {
  final fps = player.mpv.tryGetProperty('estimated-vf-fps');
  return fps is num && fps > 0 && _resizeEvents > resizeBaseline;
}, timeout: const Duration(seconds: 30));
```

**为什么顺序是这样（native 依据，planner 必须写进 action 的理由）：**
- `MpvVideoController.setSize`（`video_controller.dart:392-413`）对 `_size` 去重且首次调用必然放行（初始 `_size` 为 null），并在 `_disposed` 或尺寸 ≤ 0 时静默返回；控制器存活时的 channel 失败会 rethrow。
- 必须**先** `player.open(...)` 再 `setSize`：`RenderOnce` 进入前要求 `sized && visible && !backing_off`（`video_renderer.cc:335,357`），在有视频前调用虽然也会 `Emit("resize")`（emit 发生在 render 之前），但随后的 `mpv_render_context_render` 可能记一条 `renderError` 并污染计数。
- `resizeBaseline` 要在 `setSize` **之前**取；否则 `_resizeEvents > resizeBaseline` 会被自己的这次 resize 满足得太晚（或旧计数掩盖新计数）。
- 替代方案（verification 也给过）：把门改成 `estimated-vf-fps > 0` + 首个已合成帧，不依赖 resize。两者二选一即可；本文推荐上面的「先 setSize 再等」方案，因为它同时给出了 ring 已分配的正面证据。

#### 1c. 事件计数与 disposal 顺序（不要改坏的部分）

**Analog:** `playback_bench_test.dart:122-150`

```dart
final events = <MpvVideoEventKind>[];
final sub = controller.events
    .listen((e) => events.add(e.kind), onError: (Object _) {});
...
player.stop();
// One render context per mpv handle: free it before the cycles create
// their own controllers.
await controller.dispose();
```

**当前实现已有正确的等价物** —— `impeller_smoke_test.dart:352-356`（`_watch`）、`:481-504`（`_disposeQuietly`，controller 先于 player）。保持不变。

**一处需要 planner 明确的反差：** `playback_bench_test.dart` 在 create/dispose 循环前调了 `player.stop()`，因为它测的是纯控制器循环；part 3 要求**持续播放**，所以**不要**照抄那句 `player.stop()`。要复用的是循环体的形状（create → dispose → 再 create），不是它的停止动作。

**计数契约（现有代码已正确，仅作为改动时的护栏）：**
- `_onEvent`（`:358-382`）把 `resize` 的 message（`"WxH"`，见 `video_controller.dart:84,102-104`）用于 4K 判定；
- `renderErrors` / `deviceLost` / `idleSoak` 是 `_classify`（`:411-429`）的输入，`pass` 要求 `partsOk && rounds == 100 && seconds >= 30 && !_deviceLost && _renderErrors < 10 && _idleSoak == 0 && nonBlack`；
- part 3 的 soak 期间 `_setTexture(null)` 会让窗口短暂隐藏，`visible == false` 时 `RenderOnce` 被跳过，所以**soak 阶段的 `resizeEvents` 可以是 0 且不影响判定**（判定只用 `rounds`/`seconds`）。不要给 soak 再加 resize 门。

#### 1d. WR-02 —— 像素缓冲区切片

**当前实现（缺陷所在）** — `impeller_smoke_test.dart:453-470`：

```dart
final bytes = await image.toByteData(
  format: ui.ImageByteFormat.rawRgba,
);
if (bytes == null) {
  return {'supported': false, 'reason': 'toByteData returned null'};
}
final data = bytes.buffer.asUint8List();
final pixels = image.width * image.height;
var nonBlack = 0;
for (var i = 0; i + 3 < data.length; i += 4) {
  if (data[i] > 8 || data[i + 1] > 8 || data[i + 2] > 8) nonBlack++;
}
```

`ByteData.buffer` 返回的是**整个底层 buffer**；忽略 `offsetInBytes` / `lengthInBytes` 时，`data` 可能包含无关内存，`nonBlackRatio` 因此可能伪造出 `pass`。

**修正形状（stdlib API，无仓内同构先例）：**

```dart
final data = bytes.buffer.asUint8List(
  bytes.offsetInBytes,
  bytes.lengthInBytes,
);
final pixels = image.width * image.height;
if (data.length < pixels * 4) {
  return {
    'supported': false,
    'reason': 'short pixel buffer: ${data.length} < ${pixels * 4}',
  };
}
```

仓内现有 `asUint8List()` 用法（`packages/mpv_kit/test/player_test.dart:47`、`packages/mpv_kit/test/failure_injection_test.dart:134`）都是「整块即全部」的场景，**不可照抄**——它们是本缺陷的错误先例，不要作为 pattern 引用。

#### 1e. 失败路径（保持 CR-01 修复后的可达性）

**当前实现** — `impeller_smoke_test.dart:150-164`：

```dart
await tester.runAsync(() async {
  try {
    await _execute(mpvKitPath);
  } on Object catch (error) {
    _emitBench({
      'stage': _stage,
      'result': 'inconclusive',
      'error': '${error.runtimeType}: $error',
      'parts': _parts,
      ..._details,
    });
    await _disposeQuietly();
    rethrow;
  }
});
```

这个 `try` 结构本身是对的（失败必留 `result=inconclusive`、 cleanup 不掩盖原错、`rethrow` 让测试真红）。但 IN-06 指出 `preflight`（`:118-124`）与 `pumpWidget`（`:129-148`）在 `try` 之外。收口时**最小**做法是把 preflight 的 emit 移到 `try` 内、并把 `runAsync` 的整个函数体纳入 `try`；不要为此重构文件结构。改完后 `_emitBench` 用 `print`，这些行才会真正落在采集日志里。

---

## 2. Native contract —— 让 part-1 门可满足的依据

> 这一节是 CR-02 的根因，planner 应把它作为 action 的「why」引用（引用时使用下列精确行号；verification 的 IN-03 已指出 ADR 里的 `166-179` / `499` 是漂移值）。

**`VideoRenderer::SetSize` 是 `width_`/`height_` 的唯一写入者** — `packages/mpv_kit_video/src/video_renderer.cc:166-176`：

```cpp
void VideoRenderer::SetSize(int width, int height) {
  if (width <= 0 || height <= 0) return;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    if (width == width_ && height == height_) return;
    width_ = width;
    height_ = height;
    resize_pending_ = true;
  }
  cv_.notify_one();
}
```

**渲染线程被唤醒后才可能进 `RenderOnce`** — `video_renderer.cc:318`：

```cpp
      resized = resize_pending_.exchange(false);
```

**进入条件是 `sized && visible && !backing_off`** — `video_renderer.cc:335` / `:357`：

```cpp
      sized = width_ > 0 && height_ > 0;
...
    if (sized && visible && !backing_off) {
      std::string error;
      OnRenderResult(RenderOnce(&error), error);
```

（`resized` 会强制 `idle_ = false`，`video_renderer.cc:342-346`，所以 resize 之后 `visible` 为真。）

**`resize` 只在 ring (re)allocation 成功后发出** — `video_renderer.cc:478` / `:500-541`：

```cpp
    if (w != ring_w_ || h != ring_h_) {
      // Old images are about to be retired; their last frame stays on
      ...
      if (!failed_before_render) {
        ring_w_ = w;
        ring_h_ = h;
      }
    }
    if (failed_before_render) {
      SkipFrame();  // mpv still waits for this frame to be consumed
      return RenderResult::kFailed;
    }
    Emit("resize", std::to_string(w) + "x" + std::to_string(h));
```

`Emit` 本身是纯转发 — `video_renderer.cc:162-164`。

**由此得到的三条硬结论：**
1. 初始 `ring_w_ = ring_h_ = 0`（`video_renderer.h:218`），所以**第一次非零 `setSize` 必然改变 `w != ring_w_`**，只要 ring 分配成功就会 `Emit("resize", "WxH")`。part 1 之前一次 `setSize` 就足以让现有门可满足。
2. 不调 `setSize` 时 `width_/height_` 恒为 0 → `sized == false` → 走 `SkipFrame`，永远不会有 resize，也不会有真实渲染。这正是两次运行 `resizeEvents=0` 的原因。
3. `resize` 的 payload 是 `"<w>x<h>"`（无空格），与 `MpvVideoEvent.message` 的文档一致（`video_controller.dart:84,102-104`），所以 `_onEvent` 里的 `event.message == '3840x2160'` 判据是成立的，part 2 不需要改。

**Dart 侧 API 事实**（`packages/mpv_kit_video/lib/src/video_controller.dart`）：
- `setSize` 定义 `:392-413`：`_disposed` / `width <= 0` / `height <= 0` 静默返回；`_size == (width, height)` 去重；首次调用放行。
- `_size` 初值 `(int, int)? _size;`（`:360`，未初始化 → null），因此新控制器的第一次 `setSize` 一定到达 native。
- `textureId`（`:346`）、`backend`（`:349`）、`reason`（`:353`）是 harness 身份门用到的只读字段。
- `MpvVideo` 走的是同一条路（`mpv_video.dart:53-65` 的 `_requestSize` → `unawaited(widget.controller.setSize(w, h))`）；harness 刻意不用 `MpvVideo`（`impeller_smoke_test.dart:126-128` 注释），所以必须自己调 `setSize`。

---

### 3. `docs/adr/0003-windows-composition-path.md`（documentation, ADR）

**Analog:** 同文件既有结构（改动必须是**外科式**的，因为下游 gate 直接 grep 这些行）。

#### 3a. 必须保留的头部键（plan 10-02 的 gate 依赖它们）

`docs/adr/0003-windows-composition-path.md:1-8`：

```
# ADR 0003 — Windows composition path after the 3.47.8 Impeller spike

verdict: inconclusive
engine-renderer: Impeller (GLES-over-ANGLE, OpenGLESSDF) when --enable-impeller; the --no-enable-impeller control shows no Impeller line
identity: proven

Status: accepted (evidence recorded 2026-10-25; D-05 not exercised — see Context)
```

收口后若重跑成功，`verdict:` 行要改成重跑得到的真实分类，并且**必须与 `evidence/impeller-bench.txt` 的 `classification:` 一致**（verification 的 truth #22 要求两者一致）。`engine-renderer:` 与 `identity:` 两行保持不动（identity 由引擎日志行证明，与 harness 修复无关）。

#### 3b. WR-07 —— Phase 11 前置补上 reporting-channel

**当前** — `:233-236`：

```markdown
**Immediate Phase 11 precondition:** settle D-05 with a corrected harness
(call `setSize` before the part-1 gate, or gate part 1 on
`estimated-vf-fps > 0` plus a first rendered frame). Until then, no
composition change is approved on the basis of "Impeller works".
```

**改为（两项并列，缺一不可）：**

```markdown
**Immediate Phase 11 precondition:** settle D-05 with a corrected harness.
Two harness defects must both be fixed, and a run may only be scheduled once
both are:
1. the part-1 readiness gate must be satisfiable by calling
   `controller.setSize(...)` before the gate (or by gating part 1 on
   `estimated-vf-fps > 0` plus a first rendered frame) — `VideoRenderer::SetSize`
   is the only writer of `width_`/`height_` (`video_renderer.cc:166-176`) and
   `resize` is emitted after a successful ring (re)allocation (`:500-541`);
2. the report channel must reach the captured console: `_emitBench` writes
   `stdout.writeln`, which `flutter test -d windows` does not forward, whereas
   the sibling harnesses use `print` (`playback_bench_test.dart:15-17`).
   Prove a `BENCH` preflight line appears in the log before any workload.
Until then, no composition change is approved on the basis of "Impeller works".
```

#### 3c. WR-06 + IN-03 —— evidence 路径与行号

**现有引用一律是裸 `evidence/...`**（`:69-72`、`:124-125`、`:301`、`:316-324`），从 `docs/adr/` 解析会落到不存在的 `docs/adr/evidence/`。本仓文档的主导风格是**仓库根相对路径**（见同文件 `:11-12` 的 `docs/reverse-engineering/...`、`:9` 的 `.planning/research/SUMMARY.md`），所以统一改成：

```markdown
`.planning/phases/10-composition-spike/evidence/impeller-bench.txt`
```

即：把每一处 `evidence/<name>` 替换为 `.planning/phases/10-composition-spike/evidence/<name>`，例如 `:124-125` 改为：

```markdown
codes and switch values are in
`.planning/phases/10-composition-spike/evidence/impeller-bench.txt`; logs are
`.planning/phases/10-composition-spike/evidence/impeller-on.log` and
`.planning/phases/10-composition-spike/evidence/impeller-off.log`.
```

同时修正行号漂移（IN-03，以源码实测为准）：
- `:131` `video_renderer.cc:166-179` → `:166-176`；
- `:132` `(:499` → `:500`（条件判断实际在 `:478` 与 `:500`，emit 在 `:541`）。

#### 3d. 保持不变的证据纪律（改动时不要放松）

- `## Renderer identity` 的 `identity-guard: unproven => inconclusive (never 不可行)`（`:61`）——这正是「harness 缺陷不能记成渲染器失败」的制度化表述，收口后仍然成立。
- `## Research Open Questions` 的 Q1–Q5 表（`:297-305`）：Q1 已答「no」，重跑后若 `flutter test` 仍不转发引擎行，**不要**把 Q1 改回 open；identity 仍由 `flutter-run` fallback 提供（`evidence/impeller-run-*.log`）。
- `## Evidence` 里静态 REA 与运行时 smoke 的两条证据流必须继续分开陈述（verification truth #22 / research Pitfall 13）。

---

### 4. `docs/reverse-engineering/03-flutter-windows-texture-consumption.md`（documentation, REA 报告）

**Analog:** 同文件既有结构（`:574` 已正确使用 `docs/reverse-engineering/02-...` 这种根相对路径）。

#### 4a. WR-06 —— 两处失效路径

- `:17`：

```markdown
export, including the complete pseudocode, is
`../.planning/phases/10-composition-spike/evidence/decompilation.txt`.
```
→ `../.planning/...` 从 `docs/reverse-engineering/` 解析成 `docs/.planning/...`。改为根相对：
```markdown
export, including the complete pseudocode, is
`.planning/phases/10-composition-spike/evidence/decompilation.txt`.
```

- `:555-561` 的 `## 8. Sources and reproducibility` 列表：`evidence/engine-3.47.8.sha256.txt`、`evidence/engine-3.47.8.imports.txt`、`evidence/engine-3.47.8.anchors.txt`、`evidence/decompilation.txt`、`tools/DumpTargets.py` 全部前缀 `.planning/phases/10-composition-spike/`（`tools/DumpTargets.py` 实际位于 `.planning/phases/10-composition-spike/tools/DumpTargets.py`，verification 已核实该文件存在、9,962 B）。

#### 4b. IN-02 —— Q1 状态与 ADR 矛盾

`03-...md:546` 现在是：

```markdown
| Whether `flutter test -d windows` forwards the engine log line | **Open**, owned by plan 10-03 (smoke). |
```

改为与 ADR `:301` 一致的结论：

```markdown
| Whether `flutter test -d windows` forwards the engine log line | **Answered: no.** Neither test log contains an engine line; identity was established through the `flutter-run` fallback. |
```

#### 4c. 语言与格式纪律

- 两份文档正文是**英文**，新增/改写段落也用英文；不要翻译既有中文（本仓 CLAUDE.md 的 Comments 条款）。
- 表格、`### Path A/B/C`、`#### Allocation` / `#### Fence semantics` / `#### Device ownership` 四级标题是 plan 的结构 gate（verification truth #5），不得增删或改名。
- 文档内不写 TODO/FIXME（仓库约定，且 verification 统计为 0）。

---

## Shared Patterns

### 报告通道（BENCH / INTEGRATION 行）
**Source:** `example/integration_test/playback_bench_test.dart:15-17`（约定）、`:113`（调用）
**Apply to:** `impeller_smoke_test.dart` 的全部 `_emitBench` 调用（preflight / soak-start / soak-progress / complete / 失败行）

```dart
// Printing is the report channel (integration tests have no console logger):
// ignore_for_file: avoid_print
```

- 一行一条、`<TAG> <name> {json}`、单行可解析；
- 失败路径也发一行（`result: inconclusive`），绝不沉默；
- `stdout.writeln` 在本平台不可达，禁止再引入。

### Integration harness 骨架
**Source:** `playback_bench_test.dart:99-105`、`uhd_endurance_test.dart:35-46`、`real_plugin_test.dart:25-30`
**Apply to:** 保持 `impeller_smoke_test.dart:63-70` 现有骨架不变

```dart
final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

testWidgets('...', (tester) async {
  await tester.runAsync(() async { ... });
});
```

一个文件一个 `testWidgets`（`playback_bench_test.dart:10-13` 明确记录：顺序多个会把 binding 留在后续测试 hang 的状态）。

### 播放/渲染就绪判定
**Source:** `real_plugin_test.dart:55-79`（params + `estimated-vf-fps`）、`uhd_endurance_test.dart:76-85`（params 尺寸）
**Apply to:** part 1 与 part 2 的就绪门

`estimated-vf-fps` 是「VO 真的消费并呈现了帧」的既有证据；`videoParams` 是「解码器报出了目标尺寸」的证据。不要用 `MpvVideoEventKind.active` 或 process 存活代替。

### 资源生命周期
**Source:** `playback_bench_test.dart:141-150`（stop → controller.dispose → 再 create）、`impeller_smoke_test.dart:481-504`（`_disposeQuietly`）
**Apply to:** part 1→2、part 3 的 100 轮

- 控制器先于 player 释放（`docs/ARCHITECTURE.md:76-90`）；
- 每轮 unmount texture → `_nextFrame()` → 再 dispose，避免合成器还持有引用；
- part 3 保持播放（与 `playback_bench` 的 `player.stop()` **相反**）。

### 文档证据路径
**Source:** `docs/adr/0003-windows-composition-path.md:11-12`、`docs/reverse-engineering/03-...md:574`
**Apply to:** 两份文档里所有 evidence / tool 引用

统一用**仓库根相对**的反引号路径：`.planning/phases/10-composition-spike/evidence/<file>`。禁止 `evidence/<file>`（相对当前文档目录）与 `../.planning/...`（层级算错）。

---

## No Analog Found

| File / 子项 | Role | Data Flow | Reason |
|---|---|---|---|
| `_probePixels` 的 `ByteData` 切片（WR-02） | test helper | transform | 仓内两处 `asUint8List()`（`player_test.dart:47`、`failure_injection_test.dart:134`）都是整块使用，没有 offset/length 感知的先例；按 Dart SDK `ByteData.buffer` 语义（`asUint8List(offsetInBytes, lengthInBytes)`）直接修 |
| 「harness 缺陷 ⇒ `inconclusive`」的四桶分类 | test classification | n/a | 本仓唯一实现就是本文件 `_classify`（`:411-429`）；无其他 analog，改动时以 ADR `identity-guard` 与 verification 的 CR-01/CR-02 口径为准 |

---

## 收口验收（planner 应写进 PLAN 的 gate）

1. `cd example && dart analyze --fatal-infos` → `No issues found!`（当前基线已是 0 issue）。
2. `grep -c 'BENCH impeller' <captured log>` 在 on/off 两次运行中均 **≥ 1**（preflight 必现），完整运行应出现 `stage: preflight` 与 `stage: complete`。
3. `stage: complete` 行包含 `parts.{oneFrame,uhd4k,soak} == "ok"`、`rounds == 100`、`seconds >= 30`、`pixelProbe.supported == true` 且 `nonBlackRatio` 为数值。
4. `video_renderer.cc` 行号引用为 `:166-176`、`:500`/`:541`（不是 `:166-179`/`:499`）。
5. 两份文档内不存在裸 `evidence/` 或 `../.planning/` 前缀；`grep -n 'Open, owned by plan 10-03'` 为 0。
6. `docs/adr/0003-...md` 的 `verdict:` 与 `evidence/impeller-bench.txt` 的 `classification:` 一致。
7. 公共 API 与 `packages/` 源码零改动（Phase 10 约束）。

---

## Metadata

**Analog search scope:** `example/integration_test/`、`packages/mpv_kit_video/lib/src/`、`packages/mpv_kit_video/src/`、`packages/mpv_kit/test/`、`docs/adr/`、`docs/reverse-engineering/`
**Files scanned:** 11（3 harness、1 被测文件、2 native、1 controller、2 文档、2 测试）
**Tracked-source check:** 全部经 `git ls-files` 确认 tracked；未引用任何 `.gsd/capabilities/` 同步镜像
**Pattern extraction date:** 2026-10-25
**Language note:** PATTERNS.md 为中文叙述；被修改文件的正文/注释语言按各自文件既有语言（harness 与两份文档均为英文）

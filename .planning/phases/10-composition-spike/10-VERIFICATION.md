---
phase: 10-composition-spike
verified: 2026-10-24T18:15:35Z
status: gaps_found
score: 18/22 must-haves verified
covered_files:
  - ".github/workflows/flutter-plugin.yml"
  - ".planning/phases/10-composition-spike/10-01-PLAN.md"
  - ".planning/phases/10-composition-spike/10-01-SUMMARY.md"
  - ".planning/phases/10-composition-spike/10-02-PLAN.md"
  - ".planning/phases/10-composition-spike/10-02-SUMMARY.md"
  - ".planning/phases/10-composition-spike/10-03-PLAN.md"
  - ".planning/phases/10-composition-spike/10-03-SUMMARY.md"
  - "docs/adr/0003-windows-composition-path.md"
  - "docs/reverse-engineering/03-flutter-windows-texture-consumption.md"
  - "example/integration_test/impeller_smoke_test.dart"
covered_digest: "v3:sha256:c2d2825bcff429354b849af67805d05284bf4dbfdd51100091f93d8e325c045e"
behavior_unverified: 1
overrides_applied: 0
decision_coverage:
  honored: 7
  total: 7
  not_honored: []
gaps:
  - truth: "一个 testWidgets 内执行 D-04 的三段工作负载（最小链路 / 一次 4K 帧 / 30 秒 + 100 轮 resize-dispose 交错）"
    status: failed
    reason: "part-1 readiness 谓词要求 resize 事件，但 part 1 之前没有任何地方调用 setSize。VideoRenderer::SetSize 是 width_/height_ 的唯一写入者（packages/mpv_kit_video/src/video_renderer.cc:166-176），resize 只在 w/h 与 ring 不同时发出（:478 / :500 / :541），初始两侧均为 0。两次运行都在 30 s 后以 resizeEvents=0 超时，因此 part 2/3、像素探针与 D-05 从未执行。"
    artifacts:
      - path: "example/integration_test/impeller_smoke_test.dart"
        issue: "part-1 就绪门（:218-226）不可满足：在它之前没有 controller.setSize(...)。"
      - path: ".planning/phases/10-composition-spike/evidence/impeller-on.log"
        issue: "两次运行均记录 'part 1 readiness timeout ... resizeEvents=0'。"
    missing:
      - "在 part-1 门之前调用 controller.setSize(1920, 1080)（先取 resize 基线），或改为以 estimated-vf-fps > 0 + 首个已合成帧为门。"
      - "修复后重跑 --enable-impeller / --no-enable-impeller 两次，记录 rounds、seconds、pixelProbe 与 result。"
  - truth: "harness 产生 preflight / soak-start / complete 三条 BENCH 行；harness 侧失败产生 inconclusive 行而不是沉默"
    status: failed
    reason: "_emitBench 使用 stdout.writeln；flutter test -d windows 不转发该通道。preflight 行在 pumpWidget 之前无条件写出，但四份已提交日志中 BENCH 计数均为 0，而同进程的 debugPrint 输出（mpv_kit_video: vulkan ...）与 engine IMPORTANT 行都在日志中；同目录的 playback_bench_test.dart / uhd_endurance_test.dart 使用 print() 且其 BENCH 行可达。"
    artifacts:
      - path: "example/integration_test/impeller_smoke_test.dart"
        issue: "_emitBench（:52-54）写入 stdout，所有 BENCH 结果行（含失败时的 inconclusive 行）在采集日志中丢失。"
      - path: ".planning/phases/10-composition-spike/evidence/impeller-on.log"
        issue: "BENCH 行数 = 0；impeller-off.log / impeller-run-on.log / impeller-run-off.log 同为 0。"
    missing:
      - "改用 print()/debugPrint()（与 playback_bench_test.dart 一致），或用环境变量指定文件路径并以 flush/close 落盘。"
      - "在任何工作负载之前证明 preflight 的 BENCH 行出现在采集日志中。"
  - truth: "ROADMAP SC2：Impeller 冒烟记录 create→渲染一帧→dispose 的结果（成功/崩溃，对照 flutter#191468 与 #191017）"
    status: failed
    reason: "两次运行都在 harness 自身的 part-1 门中止，既没有渲染一帧，也没有 dispose 后的结果。记录到的是 harness 缺陷（inconclusive），不是 success 或 crash；D-05 因此未被证实也未被证伪，ROADMAP 的冒烟交付物缺失。ADR 的诚实记录值得肯定，但不能把未执行的负载算作已完成。"
    artifacts:
      - path: ".planning/phases/10-composition-spike/evidence/impeller-bench.txt"
        issue: "classification: inconclusive，nonBlackRatio: unsupported，根本没有渲染层面的结果。"
      - path: "docs/adr/0003-windows-composition-path.md"
        issue: "verdict: inconclusive；仅把重跑列为 Phase 11 前置，未在本阶段完成冒烟。"
    missing:
      - "修复上述两个 harness 缺陷后重跑，产出真正执行过 create→至少一帧→dispose 的 BENCH complete 行与非黑证据。"
      - "把 reporting-channel 修复补进 ADR 的 Phase 11 前置（当前只提到 setSize 门，见 WR-07）。"
behavior_unverified_items:
  - truth: "idle 只在纹理持续挂载 >= 500 ms 时计入 idleSoak；卸载/切换窗口内的 idle 记入 idleDuringUnmount"
    test: "让纹理连续挂载超过 500 ms，再卸载并继续播放，观察 idle 事件落在哪个桶。"
    expected: "正常轮次 idleSoak 保持 0；卸载窗口内的 idle 计入 idleDuringUnmount，不进入渲染器失败判据。"
    why_human: "工作负载从未执行（part-1 门），因此没有任何运行真正触发该分类器；WR-05 还指出正常轮次的挂载窗约 250-350 ms，达不到 500 ms，指标在常规情况下为空。"
---

# Phase 10: Composition Spike 验证报告

**Phase Goal:** 以证据决定合成路径：REA 逆向本机 flutter_windows.dll（3.47.8）的外部纹理消费实现 + Impeller 开关冒烟。
**Verified:** 2026-10-24T18:15:35Z
**Status:** gaps_found
**Re-verification:** No — initial verification

## Goal Achievement

结论先行：**REA 与决策文档质量很高，且可复现；Impeller 冒烟这一半没有执行。** 两次运行都在 harness 自己的 part-1 门中止，而该门不可满足（CR-02）；同时 harness 的唯一结果通道在采集日志中不可见（CR-01）。记录的 `inconclusive` 本身是**诚实且证据充分**的——日志、栈、退出码、崩溃取证都支持它；但“如实记录无法测量”不等于“完成了冒烟”。ROADMAP SC2 要求记录 create→渲染一帧→dispose 的结果，本阶段没有做到。

### Observable Truths

| #   | Truth   | Status     | Evidence       |
| --- | ------- | ---------- | -------------- |
| 1 | SC1：REA 报告给出两种表面类型在 3.47.8 中的实际绑定路径，且证据落盘 `docs/reverse-engineering/` | ✓ VERIFIED | `03-flutter-windows-texture-consumption.md` 含 Path A/B/C、两种 EGL 枚举、每路径 Allocation/Fence/Device 三节；`evidence/decompilation.txt` 有真实反编译伪代码 |
| 2 | SC2：Impeller 冒烟记录 create→渲染一帧→dispose 的结果（成功/崩溃） | ✗ FAILED | 两次运行均在 part-1 门超时（`resizeEvents=0`），未渲染任何帧；`impeller-bench.txt` 为 `nonBlackRatio: unsupported` |
| 3 | SC3：决策文档给出路径、依据、回退条件、quarantine 假设，或不可行时的版本条件 | ✓ VERIFIED | `docs/adr/0003-windows-composition-path.md` 含 `verdict: inconclusive`、路线、回退契约、quarantine 假设、D-06 条件 |
| 4 | 3.47.8 工件以 sha256/尺寸钉死，并给出可复现取证步骤 | ✓ VERIFIED | 本机实测 `sha256sum` = `9a3a09ca…b7d170`、尺寸 46,636,544 B、PDB 278,859,776 B，与 evidence 一致；ephemeral 副本被记录并排除 |
| 5 | 三条路径各有伪代码，且每条路径都有 Allocation / Fence semantics / Device ownership | ✓ VERIFIED | 标题计数：Path A/B/C 各 1；三个四级标题各 3 |
| 6 | Path B 同时点名 `EGL_D3D_TEXTURE_ANGLE` 与 `EGL_D3D_TEXTURE_2D_SHARE_HANDLE_ANGLE` | ✓ VERIFIED | 文档 :209-240 与 :247-251；decompilation 含 `SurfaceD3D` / `SwapChain11` |
| 7 | 逐路径回答“经不经 ANGLE / 谁拥有 DXGI 设备 / fence 语义”，并回答 keyed-mutex 未决项 | ✓ VERIFIED | `Keyed-mutex answer:` 1 处；`IDXGIKeyedMutex` 4 处；结论附 RVA 与证据边界 |
| 8 | “ANGLE 编译进本 PE”写成对 fence/设备归属的含义，而非重新判定链接方式 | ✓ VERIFIED | imports 证据明确 `libEGL.dll: ABSENT` / `libGLESv2.dll: ABSENT` / `ANGLE EGL/GLES: compiled into this PE` |
| 9 | Impeller 与 Skia 的消费差异有二进制/源码证据 | ✓ VERIFIED | 文档含 `flushAndSubmit`/`resetContext` 差异表、`GL_RGBA8` 悬崖、reactor cleanup 生命周期 |
| 10 | 唯一使用本机 3.47.8 构建与运行；CI `FLUTTER_VERSION` 同步为 3.47.8 | ✓ VERIFIED | `sdk-3.47.8.txt`；`.github/workflows/flutter-plugin.yml:17` 恰为 `FLUTTER_VERSION: 3.47.8`，且 Phase 10 只改了此行 |
| 11 | 开工前有显式磁盘闸门（status / avail_bytes / threshold / run-gate） | ✓ VERIFIED | `disk-gate.txt`：`status: ok`、`avail_bytes: 8183160832`、`threshold_bytes: 5905580032`、`run-gate: ... status=ok` |
| 12 | harness 在测量前断言 `MpvLibrary.resolvedPath` 与 `MPV_KIT_LIBMPV_PATH` 相等且 backend 为 vulkan | ✓ VERIFIED | harness :188-206；栈显示异常发生在 :229（说明身份门已通过），`impeller-bench.txt` 记录 `resolvedLibmpv` 与 `mpvBackend: vulkan` |
| 13 | 一个 testWidgets 内执行 D-04 三段（或给出不可运行的确切原因） | ✗ FAILED | “确切原因”是 phase 自己的 harness 缺陷（CR-02），不是环境不可运行；三段的代码存在但永远不可达 |
| 14 | 产生 preflight / soak-start / complete 三条 BENCH 行；harness 失败产生 inconclusive 行而不是沉默 | ✗ FAILED | 四份日志 `grep -c BENCH` 均为 0；preflight 在 pumpWidget 前无条件写出却仍缺席；失败时仅测试框架栈可见 |
| 15 | `result=pass` 必须同时包含非黑合成帧断言 | ✓ VERIFIED | `_classify` 要求 `probeSupported && ratio >= 0.01`（harness :411-429）；探针不可用则 `inconclusive` |
| 16 | idle 只在纹理持续挂载 >= 500 ms 时计入 idleSoak | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | 分类器代码存在（:388-398），但工作负载从未执行，没有任何运行触发它；另见 WR-05 |
| 17 | 公共 API 不变；`dart analyze --fatal-infos` 干净；新文件无 analyzer 抑制注释 | ✓ VERIFIED | 实测 `dart analyze --fatal-infos` = `No issues found!`（exit 0）；`ignore` 计数 0；`packages/` 无 Phase 10 改动 |
| 18 | 两次运行使用 3.47.8 debug 构建，开关值/命令行/退出码记录 | ✓ VERIFIED | `*.meta` 与 `impeller-bench.txt` 有命令、switch、exit_code、起止时间；窗口“可见”仅被断言、未被记录（警告） |
| 19 | Impeller 身份由引擎日志行证明，对照运行不含该行 | ✓ VERIFIED | on/run-on 各 1 条 `Using the Impeller rendering backend` + `OpenGLESSDF`；off/run-off 均 0 |
| 20 | 每次运行同时记录 classification 与 identity；identity 未证实则 ADR 只能写 inconclusive | ✓ VERIFIED | `impeller-bench.txt`：`classification: inconclusive` / `identity: proven`；ADR 有 `identity-guard` 行 |
| 21 | `Only support GL_RGBA8 format now` 在任一日志出现即 failed | ✓ VERIFIED | 扫描结果 `rgba8_on: 0`、`rgba8_off: 0`；两份日志实测 0 |
| 22 | ADR 回答“更短/更便宜”，记录 D-05 桶、回退、quarantine、Phase 11 路线，并映射 Q1-Q5 | ✓ VERIFIED | 所需章节与 `| Q1 `…`| Q5 ` 五行齐备；verdict 与分类文件一致 |

**Score:** 18/22 truths verified (1 present, behavior-unverified)

### Required Artifacts

| Artifact | Expected    | Status | Details |
| -------- | ----------- | ------ | ------- |
| `docs/reverse-engineering/03-flutter-windows-texture-consumption.md` | 三路径伪代码报告 | ✓ VERIFIED | 582 行；所有 plan 字符串/结构门通过；证据路径引用失效（WR-06） |
| `.planning/phases/10-composition-spike/evidence/engine-3.47.8.sha256.txt` | 工件钉死 | ✓ VERIFIED | 哈希/尺寸与真实 DLL 一致；含 ephemeral 排除 |
| `.planning/phases/10-composition-spike/evidence/engine-3.47.8.imports.txt` | 导入表与 ANGLE 结论 | ✓ VERIFIED | 24 regular + 2 delay-load；`compiled into this PE` |
| `.planning/phases/10-composition-spike/evidence/engine-3.47.8.anchors.txt` | 锚点计数 | ✓ VERIFIED | 实测 1/2/1/1/4/1 与文件一致 |
| `.planning/phases/10-composition-spike/evidence/decompilation.txt` | Ghidra 导出 | ✓ VERIFIED | 183,749 B；含 26 个目标函数、RVA、调用图、伪代码 |
| `.planning/phases/10-composition-spike/tools/DumpTargets.py` | 可复跑脚本 | ✓ VERIFIED | 9,962 B；按符号定位、导出 RVA/伪代码 |
| `example/integration_test/impeller_smoke_test.dart` | D-04 harness | ✗ DEFECTIVE | 结构完整、analyze 干净，但 part-1 门不可满足且 BENCH 通道失效 |
| `.planning/phases/10-composition-spike/evidence/sdk-3.47.8.txt` | SDK 身份 | ✓ VERIFIED | 版本/revision/DLL 哈希/PDB 尺寸齐备 |
| `.planning/phases/10-composition-spike/evidence/disk-gate.txt` | 磁盘闸门 | ✓ VERIFIED | 两次 gate 数字与阈值齐备 |
| `evidence/impeller-on.log` / `impeller-off.log` | 两次运行日志 | ✓ VERIFIED | 控制台完整，但 BENCH 行 0 |
| `evidence/impeller-run-on.log` / `impeller-run-off.log` | identity fallback | ✓ VERIFIED | 正例含引擎行，对照 0 |
| `evidence/impeller-bench.txt` | 四桶分类 | ✓ VERIFIED | 字段格式全通过；`nonBlackRatio: unsupported` |
| `docs/adr/0003-windows-composition-path.md` | 决策文档 | ✓ VERIFIED | ADR 门全通过 |
| `.github/workflows/flutter-plugin.yml` | CI 版本锁 | ✓ VERIFIED | 3.47.8 恰 1 处；同文件存在 Phase 10 之前就有的 POSIX 路径缺陷（CR-03，警告） |

### Key Link Verification

| From | To  | Via | Status | Details |
| ---- | --- | --- | ------ | ------- |
| `d3d11_interop.cpp` 设备/KMT handle | `ExternalTextureD3d::CreateOrUpdateTexture` | 报告对齐表 + 反编译调用点 | ✓ WIRED | `eglBindTexImage`/`CreateSurfaceFromHandle` 在导出中；源码行号实测吻合 |
| 报告 provenance | `evidence/*.txt` | 路径引用 | ⚠️ PARTIAL | 报告写 `../.planning/...`（解析到不存在的 `docs/.planning/`）与 `evidence/...`（`docs/` 下不存在）；仅 `.planning/phases/10-composition-spike/evidence/` 有文件（WR-06） |
| `MPV_KIT_LIBMPV_PATH` | `MpvLibrary.resolvedPath` | harness 断言 | ✓ WIRED | 代码存在且身份门实际通过 |
| `resolvedLibmpv` | BENCH complete 行 | `_emitBench` | ✗ NOT_WIRED | complete 行从未产生；通道失效（CR-01） |
| SDK/engine revision | CI `FLUTTER_VERSION` | 3.47.8 | ✓ WIRED | 本地证据与 CI 一致 |
| `pixelProbe.nonBlackRatio` | `result=pass` / ADR verdict | `_classify` | ⚠️ PARTIAL | 判定代码存在，但探针从未执行；ADR 以 `unsupported` 记录 |
| 引擎日志行 | `identity` | `flutter-run` fallback | ✓ WIRED | 正例 1 / 对照 0；来源在日志中标注 |
| 03 号报告 ANGLE/设备/fence | ADR 路线 | ADR Evidence 表 | ✓ WIRED | ADR 逐条引用 RVA 与结论 |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
| -------- | ------------- | ------ | ------------------ | ------ |
| `_probePixels()` → `_pixelProbe` → `_classify`/BENCH | `nonBlackRatio` | `RenderRepaintBoundary.toImage` → `toByteData` → 像素扫描 | 否（part 2 从未到达） | ✗ DISCONNECTED |
| `_onEvent` → 计数桶 → complete 行 | `resizeEvents` / `idleSoak` / `renderErrors` | 原生 `MpvVideoEvent` 流 | 部分（resize 为 0；complete 行未发出） | ⚠️ STATIC |
| 分类文件 → ADR verdict | `classification` / `identity` | 两份日志 + BENCH | 是（日志真实存在） | ✓ FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
| -------- | ------- | ------ | ------ |
| 工件哈希/尺寸 | `sha256sum` + `stat -c %s` | `9a3a09ca…b7d170` / 46,636,544 / PDB 278,859,776 | ✓ PASS |
| 锚点计数 | `grep -a -o -F <anchor> \| wc -l` | 1/2/1/1/4/1；`ExternalTextureD3d`=0 | ✓ PASS |
| 03 报告结构门 | 标题与必需字符串计数 | 全通过 | ✓ PASS |
| ADR 结构门 | verdict/identity-guard/Q1-Q5 | 全通过 | ✓ PASS |
| identity 日志行 | `grep -a -c` | on=1, off=0, run-on=1, run-off=0 | ✓ PASS |
| BENCH 行可达性 | `grep -c BENCH` 四份日志 | 0 / 0 / 0 / 0 | ✗ FAIL |
| part-1 门可满足性 | 源码 + 原生 `SetSize`/`resize` 语义 | 不可满足 | ✗ FAIL |
| 静态分析 | `cd example && dart analyze --fatal-infos` | `No issues found!` (exit 0) | ✓ PASS |

### Probe Execution

无 `scripts/*/tests/probe-*.sh`，本阶段也不声明 shell 探针；`pixelProbe` 是 Dart 内探针，因 part 2 未到达而从未执行（见 Data-Flow Trace）。

### Test Quality Audit

| Test File | Linked Req | Active | Skipped | Circular | Assertion Level | Verdict |
|-----------|-----------|--------|---------|----------|-----------------|---------|
| `example/integration_test/impeller_smoke_test.dart` | COMP-01 | 1 | 0 | No | Status/tautological（`:343-347` 的 `expect` 不可能失败）+ 行为断言不可达 | INSUFFICIENT |

**Disabled tests on requirements:** 0
**Circular patterns detected:** 0
**Insufficient assertions:** 1 → WARNING；但因为它是 COMP-01 冒烟部分的唯一证据且不可达，已按 BLOCKER 计入 gaps。

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
| ----------- | ---------- | ----------- | ------ | -------- |
| COMP-01 | 10-01, 10-02, 10-03 | REA 逆向 3.47.8 纹理消费路径 + Impeller 开关冒烟 + 决策记录 | ✗ BLOCKED | REA（SC1）与决策（SC3）完成；冒烟（SC2）未执行：part-1 门不可满足 + BENCH 通道失效 |

未被任何 plan 声明的本阶段需求：无。REQUIREMENTS.md 只把 COMP-01 映射到 Phase 10，三份 plan 都声明了它。

### Decision Coverage

All trackable CONTEXT.md decisions are honored by shipped artifacts. (7/7)

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
| ---- | ---- | ------- | -------- | ------ |
| `example/integration_test/impeller_smoke_test.dart` | 52-54 | `stdout.writeln` 结果通道在 `flutter test -d windows` 中丢失 | 🛑 BLOCKER (CR-01) | 所有 BENCH 证据（含失败时的 inconclusive）不可达；与实测 0 行一致 |
| `example/integration_test/impeller_smoke_test.dart` | 218-226 | part-1 门要求 resize，但之前没有 `setSize` | 🛑 BLOCKER (CR-02) | D-04 负载永远不可达；两次运行均 30 s 超时 |
| `example/integration_test/impeller_smoke_test.dart` | 459 | `bytes.buffer.asUint8List()` 忽略 offset/length | ⚠️ WARNING (WR-02) | 像素比例可能来自无关内存，足以伪造 pass |
| `example/integration_test/impeller_smoke_test.dart` | 445-477 | 探针无对照标记 | ⚠️ WARNING (WR-03) | 黑帧与“探针看不见纹理”不可区分 |
| `example/integration_test/impeller_smoke_test.dart` | 272-314 | soak 仅按墙钟计 30 s，未验证播放推进 | ⚠️ WARNING (WR-04) | 卡死的 mpv 也能满足 rounds/seconds |
| `example/integration_test/impeller_smoke_test.dart` | 284-306, 388-398 | idle 指标在常规轮次为空、top-up 时又不公平 | ⚠️ WARNING (WR-05) | idleSoak==0 不是有效证据 |
| `docs/reverse-engineering/03-flutter-windows-texture-consumption.md`；`docs/adr/0003-windows-composition-path.md` | 多处 | evidence 相对路径不解析 | ⚠️ WARNING (WR-06) | 可复现性受损；读者按路径找不到文件 |
| `docs/adr/0003-windows-composition-path.md` | 233-236 | Phase 11 前置只提 setSize 门，未提 reporting channel | ⚠️ WARNING (WR-07) | 按此修复后仍会得到 inconclusive |
| `.github/workflows/flutter-plugin.yml` | 51-60 | Windows runner 把 MSYS `/d/...` 写入 GITHUB_ENV/GITHUB_PATH | ⚠️ WARNING (CR-03，Phase 10 之前引入) | 实测 `pwd` = `/d/mpv_kit`、`node path.resolve` = `D:\d\...`；消费步骤在 pwsh 下会解析错盘 |
| `.github/workflows/flutter-plugin.yml` | 53-55 | `find ... | head -1` 会先选到 dev.2 bundle | ⚠️ WARNING (WR-01) | 本机实测 `.dart_tool/.../v0.1.0-dev.2/...` 排在 dev.3 之前 |
| `.claude/CLAUDE.md` | 40 | 仍写 `FLUTTER_VERSION: 3.47.6` | ℹ️ INFO (IN-08) | 文档与 CI 脱节 |
| `.github/workflows/flutter-plugin.yml` | 33,40 | Actions 使用可移动 major tag | ℹ️ INFO (IN-09) | 供应链加固建议 |

**Review 其余 Info 级发现的核对（均已在源码/文档中复核为真）：**

| 发现 | 核对结果 |
| ---- | -------- |
| IN-01 最终 `expect` 是同义反复 | 真：`_classify` 只返回 `pass/inconclusive/failed`，`:343-347` 不可能失败 |
| IN-02 doc 03 仍把 Q1 列为 Open | 真：`03-...md:546` 写 “Open, owned by plan 10-03”，与 ADR 的 “Answered: no” 矛盾 |
| IN-03 行号引用漂移 | 真：`SetSize` 为 `166-176`（非 179），resize 条件在 `478/500`、emit 在 `541`（非 499） |
| IN-04 500 ms 常量仅靠注释同步 | 真：harness `:44` 复制 `video_renderer.h:171`，无编译期/测试断言 |
| IN-05 探针采样 720p 而非 4K | 真：`RepaintBoundary` 包裹 `SizedBox(width: 1280, height: 720)`，part 2 只把渲染目标设为 4K |
| IN-06 try/catch 未覆盖 preflight/pumpWidget | 真：`try` 从 `:151` 开始，`pumpWidget`（`:129`）与 preflight `_emitBench`（`:118`）在它之外 |
| IN-07 ADR 顶层 `identity: proven` 仅适用于 fallback pair | 真：正文 `:63-77` 明说来源是 `flutter-run`，而两个冒烟运行的 transport 未解析 |

Debt markers：Phase 10 修改的文件中 `TBD`/`FIXME`/`XXX` 计数为 0。

### Human Verification Required

本阶段是 spike/证据阶段，无用户界面；以下为 VALIDATION 中保留的人工核对（不作为状态驱动项）：

1. **伪代码保真度抽检**
   **Test:** 把 `docs/reverse-engineering/03-...md` 的三处标注与 `evidence/decompilation.txt` 中对应 RVA 的伪代码逐点对照。
   **Expected:** 文档结论能从导出伪代码回溯，尤其是 `0xecb660`（keyed mutex QueryInterface）与 `0xeb484`（Impeller 分支）。
   **Why human:** 自动化门只证明结构与字符串存在，伪代码解释是否正确是判断问题。

2. **keyed-mutex 证据边界复核**
   **Test:** 复核报告声明的边界：`SwapChain11::reset/present/swapRect` 未逐指令审计。
   **Expected:** 结论不被扩大为“ANGLE 主动从不获取 keyed mutex”。
   **Why human:** 反编译导出只覆盖被列出的目标函数。

### Gaps Summary

Phase 10 的 REA 部分**实打实完成**：本机 DLL 的 sha256/尺寸/锚点全部可复现，反编译导出包含注册、生产、消费三层的真实伪代码，两份证据文档的必需结构与数值门全部通过。ADR 的方向性结论（Impeller 仍是 GLES-over-ANGLE；无 fence；quarantine=4 只是继承假设）也与证据一致。

失败集中在冒烟这一半，且不是“环境不允许”，而是 **phase 自己交付的 harness 有两个确定性缺陷**：

1. **CR-02 —— part-1 门不可满足。** `VideoRenderer::SetSize` 是 `width_`/`height_` 的唯一写入者，`resize` 只在 w/h 与 ring 不同时发出；part 1 之前没有任何 `setSize`。因此 100% 的运行都会在 30 s 后以 `resizeEvents=0` 中止，part 2/3、4K 帧、像素探针和 D-05 永远不可达。
2. **CR-01 —— 结果通道失效。** `_emitBench` 走 `stdout.writeln`，而 `flutter test -d windows` 不转发它；preflight 行在 `pumpWidget` 之前无条件写出却在四份日志中一次都没有出现，同进程的 `debugPrint` 与引擎日志却在。即便 CR-02 修好，`complete`/`pass` 证据仍会全部丢失。

因此：
- `inconclusive` 这个分类**是诚实的**，日志与崩溃取证支持“不是渲染器失败、也不是 crash”；ADR 没有把它写成“Impeller 不可行”，这一点做对了。
- 但“无法测量”不等于“完成冒烟”。ROADMAP SC2 要的是 create→渲染一帧→dispose 的结果记录，而本阶段一帧都没有渲染；`D-05` 既未证实也未证伪。评审把这称为“the pair exercises nothing”，与代码和日志一致。
- ADR 的 Phase 11 前置还漏了 reporting-channel 修复（WR-07），照做会重复本阶段结果。

**建议的最小收口（不做大范围重写）：**
1. 在 part-1 门之前 `controller.setSize(1920, 1080)`（先取 resize 基线），或改门为 `estimated-vf-fps > 0` + 首个已合成帧。
2. `_emitBench` 改用 `print()`/`debugPrint()`（与同目录 harness 一致），或环境变量指定文件并 flush/close。
3. 重跑两种开关，落盘带 `preflight`/`complete` BENCH 行、`nonBlackRatio` 与 `result` 的证据。
4. 把 reporting-channel 修复补进 ADR 的 Phase 11 前置。
5. 顺手修 WR-02（`asUint8List(offset, length)`）与 ADR/报告中的 evidence 路径（WR-06）。

---

_Verified: 2026-10-24T18:15:35Z_
_Verifier: Claude (gsd-verifier)_

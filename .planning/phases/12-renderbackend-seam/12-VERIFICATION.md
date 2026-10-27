---
phase: 12-renderbackend-seam
verified: 2026-10-27T08:00:00Z
status: human_needed
score: 4/5 must-haves verified
covered_files:
  - ".planning/phases/12-renderbackend-seam/12-01-PLAN.md"
  - ".planning/phases/12-renderbackend-seam/12-01-SUMMARY.md"
  - ".planning/phases/12-renderbackend-seam/12-02-PLAN.md"
  - ".planning/phases/12-renderbackend-seam/12-02-SUMMARY.md"
  - ".planning/phases/12-renderbackend-seam/12-03-PLAN.md"
  - ".planning/phases/12-renderbackend-seam/12-03-SUMMARY.md"
  - ".planning/phases/12-renderbackend-seam/12-04-PLAN.md"
  - ".planning/phases/12-renderbackend-seam/12-04-SUMMARY.md"
  - ".planning/phases/12-renderbackend-seam/12-05-PLAN.md"
  - ".planning/phases/12-renderbackend-seam/12-05-SUMMARY.md"
  - ".planning/phases/12-renderbackend-seam/12-06-PLAN.md"
  - ".planning/phases/12-renderbackend-seam/12-06-SUMMARY.md"
  - ".planning/phases/12-renderbackend-seam/12-07-PLAN.md"
  - ".planning/phases/12-renderbackend-seam/12-07-SUMMARY.md"
  - ".planning/phases/12-renderbackend-seam/12-08-PLAN.md"
  - ".planning/phases/12-renderbackend-seam/12-08-SUMMARY.md"
  - ".planning/phases/12-renderbackend-seam/12-09-PLAN.md"
  - ".planning/phases/12-renderbackend-seam/12-09-SUMMARY.md"
  - ".planning/phases/12-renderbackend-seam/12-10-PLAN.md"
  - ".planning/phases/12-renderbackend-seam/12-10-SUMMARY.md"
  - ".planning/phases/12-renderbackend-seam/12-11-PLAN.md"
  - ".planning/phases/12-renderbackend-seam/12-11-SUMMARY.md"
  - ".planning/phases/12-renderbackend-seam/12-12-PLAN.md"
  - ".planning/phases/12-renderbackend-seam/12-12-SUMMARY.md"
  - "docs/adr/0004-render-backend-reporting.md"
  - "native/tests/video_renderer_affinity_test.cc"
  - "native/tests/video_renderer_api_test.cc"
  - "native/tests/video_renderer_sw_hold_front_test.cc"
  - "packages/mpv_kit_video/lib/src/video_controller.dart"
  - "packages/mpv_kit_video/src/render_backend.h"
  - "packages/mpv_kit_video/src/video_renderer.cc"
  - "packages/mpv_kit_video/src/video_renderer.h"
  - "packages/mpv_kit_video/src/vulkan_backend.cc"
covered_digest: "v4:sha256:fc11cac5bfb1161b3dc220af7e57ac85ae3b2502f70121d4870c305752cc9bd2"
behavior_unverified: 0
overrides_applied: 0
re_verification: false
gaps: []
deferred:
  - truth: "第二个控制器首帧停滞（resize-front 第 2 轮超时；d05 part 2 像素探针读到 before-first-frame）的根因"
    addressed_in: "待办（用户决定）"
    evidence: ".planning/todos/pending/2026-10-27-diagnose-second-controller-first-frame-stall-in-resize-front.md；后续 Phase 13-17 的目标/成功标准中没有一条点名这个问题，所以不是「后续阶段已覆盖」，只是用户明确推迟"
human_verification:
  - test: "决定 SC1 的「part 2 像素探针读到 nonBlackRatio 0.0 的原因」是否算已交付"
    expected: "要么接受「探针本身可信（三方对照证明 toImage 能看到外部纹理，1266x683 表面已解释），d05 在第二个控制器上读到 0.0 属于带数据记录的既有失败、已转待办」；要么要求在 Phase 12 内查明根因"
    why_human: "ROADMAP SC1 写的是「要修的是……part 2 像素探针读到 0.0 的原因」。重构前后 d05 仍判 failed（仅像素探针项），根因未查明。这是范围判断，不是代码事实"
  - test: "决定是否需要一次「真正渲染」的 4K 30 分钟（经 RenderBackend 的 Vulkan 路径）"
    expected: "RTX 4060 上 MPV_KIT_BENCH_RENDER=1 MPV_KIT_BENCH_SIZE=3840x2160 MPV_KIT_BENCH_SECONDS=1800 跑完，drops 0、renderErrors 0、deviceLost false，与 Phase 4 同量级"
    why_human: "Phase 4 的 30 分钟命令从不调用 setSize，不渲染（docs/perf/renderbackend-seam-regression.md 第 76 行自己写明）；经搬迁后渲染路径的最长真机记录是 600 s（rendered 4K）。字面 SC3 已满足，但「行为逐项一致」在 30 分钟渲染时长上没有真机数据。另外 30 分钟那次运行中出现过两次 Modern Standby（58 s 与 19 s，原因未查明），用户已批准不重跑"
  - test: "在 CR-01 修复提交 025bdad 之后，决定是否在 RTX 4060 上重跑回归"
    expected: "4K 与六组 harness 的真机运行都在 d04ab96（代码树与 c3edb9e 相同）上完成；025bdad 之后只补跑了 real_plugin_test（通过）。025bdad 只改软件路径与注释，Vulkan 路径未动，托管 CI 15 个 job 全绿"
    why_human: "是否接受「改动只触及软件路径，因此不需要真机重跑」是风险判断"
---

# Phase 12: RenderBackend Seam 验证报告

**阶段目标：** 现有 Vulkan 与软件渲染运行在统一的 `RenderBackend` 生命周期之后，行为与重构前基线逐项一致；之后任何平台后端都只需新增一个候选项即可接入或回滚。
**验证时间：** 2026-10-27
**状态：** human_needed
**重新验证：** 否，首次验证

## 结论

目标的代码层面已经达成，我没有找到 BLOCKER。`RenderBackend` 接缝真实存在并接在渲染器上，两个现有后端都走它，常量审计与冻结 golden 在我这里重跑为绿，Dart 侧 wire 名校验测试在本机重跑通过，托管 CI 在 HEAD 之前一个提交（`025bdad`）上全绿，我用 `gh run view` 独立确认了两个 run 的结论与 SHA。

不能判 `passed` 的原因有两点，都属于范围判断而不是代码缺陷：SC1 里「像素探针读到 0.0 的原因」没有查明；SC3 的「4K 30 分钟」用的是 Phase 4 的不渲染命令，渲染路径的真机记录只有 600 s。这两项已列入 `human_verification`。

SUMMARY 对这两点都如实写了（12-12 SUMMARY 的 Decisions / Carried forward 段与 `docs/perf/renderbackend-seam-regression.md` 的 Verification tiers），没有夸大。

## 目标达成情况

### 可观察真相（ROADMAP 成功标准，合同）

| # | 真相 | 状态 | 证据 |
|---|------|------|------|
| 1 | 第一个搬迁提交之前，soak harness 已修好并在 Vulkan 路径上落盘基线（D-05 30 s、100 轮 resize/dispose、100 次 create/dispose，Impeller 开/关，含 renderer 行）；两处悬空问题（part 2 探针 0.0 的原因、10-05 soak 窗口中止）被处理 | ? UNCERTAIN（部分达成，转人工决定） | 见下方 SC1 分析 |
| 2 | fake libmpv golden 在任何搬迁前先通过，并在每个搬迁提交后不改一行继续通过，覆盖回退、退避、隔离期、retire-on-resize、发布门控 | ✓ VERIFIED | `shasum -a 256 -c evidence/golden-freeze.sha256` 在本机 5/5 OK；`git log` 显示冻结的 `renderer_harness.h`、`video_renderer_golden_sw.cc`、`video_renderer_golden_vk.cc`、`golden/sw.txt`、`golden/vk.txt` 自冻结提交 `2d639ab` 起零改动（`git diff --stat 2d639ab HEAD` 只出现新增文件 `api_override.txt`、`sw_retire_twice.txt`、`vk_fallback.txt`、`vk_retire_twice.txt`）；12-07/12-09/12-10/12-11/CR-01 的 RED 证据日志齐全（`red-local-*.log`） |
| 3 | Vulkan 与软件后端经 `RenderBackend` 运行，`FrameReady` 留在平台侧；搬迁无任何常量或 reason 字符串改动；smoke、三平台真实插件测试全绿；RTX 4060 4K 30 分钟与 Phase 4 基线持平，同一 harness 重跑不出现新失败 | ✓ VERIFIED（带说明） | 接口 `render_backend.h` 含 `Create / AllocTargets / FrameFor / Render / Wait / BindThread·UnbindThread / Release`，Destroy 是析构；`FrameReady` 仍在 `Interop`（`video_renderer.h`）。`tools/constants_audit.sh` 本机重跑 `CONSTANTS ok`（15 项对比 `3a5f450`）。CI `025bdad` 上 native-verify 40442377807 与 flutter-plugin 40442377813 均 success。RTX 4060 的 4K 30 分钟与 Phase 4 逐项 `same`（`final-runs.txt`）。说明见 human_verification 第 2、3 项 |
| 4 | `report_swap` 与 `mpv_render_context_free` 只在渲染线程且后端已绑定时执行，光栅线程不再调用；所有后端共用延迟释放契约；create/dispose 与 resize/dispose soak 无崩溃，sanitizer 下 golden 无 use-after-free | ✓ VERIFIED | 见下方「线程亲和与释放契约」 |
| 5 | Dart 严格校验私有 wire 名；公共枚举与 API-freeze 不变；reason 符合语法并写入 ADR；`MPV_KIT_VIDEO_API=vulkan\|software` 只尝试该 API，不新增 Dart 公共 API | ✓ VERIFIED | 见下方「wire 名、reason 与环境变量」 |

**得分：** 4/5 真相已验证；1 项（SC1）转人工决定。`behavior_unverified: 0`，因为 SC4 这个行为依赖型真相有通过的行为测试（`video_renderer_affinity_test`、`video_renderer_sw_hold_front_test`、`*_retire_twice` golden，CI 上 sanitizers job 通过）。

### SC1 分析（UNCERTAIN）

我逐条对照了 SC1 的文字：

- **基线已落盘：** `docs/perf/renderbackend-seam-baseline.md` 记录了六组运行（d05、cycles、resize-front 各开/关 Impeller），含 SHA、命令、起止时间、退出码、BENCH/DIAG 原文、引擎 renderer 身份行（开 1 行、关 0 行）。`baseline-runs.txt` 追加式，无编辑或删除。attempt 1 与 attempt 2 中被用户判为无效的运行都保留并写明原因。✓
- **10-05 soak 窗口中止：** 基线中 d05 在 `round=1 step=dispose-begin` 处中止、resize-front 在 `set-size-640-done` 处中止（退出码 79，无崩溃取证）。12-07 把根因定位为 `AllocateRing` 退役槽双重销毁，用先红后绿修复（`red-local-12-07.log`：`DOUBLE DESTROY serial=4`；修复提交 `e3ef12b`），搬迁后 d05 100/100 轮完成、cycles 100/100、0 失败。✓
- **part 2 像素探针 0.0 的原因：** 12-02 的三方对照（`probe-control.txt`）证明 `RepaintBoundary.toImage` 在 Impeller 开/关下都能看到外部纹理（`texture-visible`，texture 区域 `nonBlackRatio` 1.0），并解释了 1266x683 表面（1280x720 被 1265.33x682.67 的逻辑视图夹紧，dpr 1.5）。part 2 加了首帧就绪门，通过规则一字未改。✓（探针本身可信）
- **未达成的部分：** 就绪门加上之后，d05 part 2 仍读到 `nonBlackRatio 0.0`、`probeTiming before-first-frame`、`fpsAtProbe null`，`longestMountMs` 约 32.1 s；resize-front 第 2 轮在新建的第二个控制器上等不到 1280x720 的 resize/`estimated-vf-fps`，30 s 超时。这在重构前（12-04）、修复后（12-08）、搬迁后（12-12）、Impeller 开与关下都一样。也就是说「探针读到 0.0」的症状仍在，真正的根因（第二个控制器是否收到被呈现的帧）没有查明。
- **这是否算缺口：** 调用方说明该项是用户明确推迟的、不属于 Phase 12 must-have。但 ROADMAP SC1 的字面是「要修的是……part 2 像素探针读到 0.0 的原因」。我不替用户做这个范围判断，所以标 UNCERTAIN 并交给人工，而不是 FAILED。它也不是 Step 9b 意义上的「后续阶段已覆盖」：Phase 13-17 的目标里没有点名它。

### 线程亲和与释放契约（SC4 / RBE-05 / RBE-06）

我读了 `video_renderer.cc` 全文：

- `mpv_render_context_report_swap` 在整个原生目录里只出现在 `VideoRenderer::ReportSwaps`（第 531-534 行），该函数先 `AssertRenderThread()`。`AcquireFront()`（光栅线程）只做 `swaps_to_report_++`，不调用 libmpv（第 455-505 行）。
- `mpv_render_context_free` 只出现在 `SoftwareBackend::Release` 与 `VulkanRenderBackend::Release`。调用点：`RenderLoop` 结尾（第 645-653 行，渲染线程、后端已 `BindThread()`、先摘更新回调再 Release，最后 `UnbindThread()`）；以及析构函数里仅当渲染线程从未启动时的兜底分支（第 288-298 行），该分支自己绑定后端再释放，不会在渲染线程运行后被走到（线程已 join，且 `render_ctx_` 在线程内置空）。
- 后端 context 绑定：`RenderLoop` 开头 `render_backend_->BindThread()`。Vulkan 与软件的 `BindThread` 是空操作，所以「已绑定」在当前后端上是按构造成立的，没有可断言的状态（Nyquist 缺口 ①，已在 `12-VALIDATION.md` 登记，用户推迟）。
- `AssertRenderThread` 使用 `assert`，但 `video_renderer_affinity_test` 读 fake libmpv 的调用日志（每条带线程 id）判断，注释写明「不依赖渲染器的调试断言」，所以 release 构建下断言被编译掉也不影响该测试的证明力。
- 延迟释放：`SoftwareBackend` 保留整代旧缓冲区外加再前一代（`older_`），`FreeRetired` 释放两代；Vulkan 只保留 `keep_slot` 并在下次 `AllocateRing` 先 `FreeRetired`。CR-01（软件路径释放了最近一次 `AcquireFront()` 交出的像素）已在 `025bdad` 修复：红灯提交 `2b15969`、本地红灯证据 `red-local-12-review-cr01.log`、绿灯 CI（`gh run view` 已确认 SHA `025bdad` 且 success）。WR-01（契约文字与实现不符）同一提交已修。
- 残余：`CR-01-R1`（三代之前的帧仍可能被提前释放，需要改接缝才能精确覆盖）与 `CR-01-R2`（两代旧缓冲区多持有到下一次 resize）。两项由用户决定推迟（`12-REVIEW-DISPOSITION.md`）。R1 是软件路径上的一个已知 use-after-free 窗口，需要连续多次 resize 与提前取帧同时满足，我把它记为 WARNING，不构成 SC4 失败，因为 SC4 的文字范围是「create/dispose 与 resize/dispose soak 无崩溃、sanitizer 下 golden 无 use-after-free」，这些都已满足。

### wire 名、reason 与环境变量（SC5 / RBE-07 / RBE-08）

- `video_controller.dart`：`_gpuWireNames = {'d3d11','opengl','vulkan'}`，精确匹配；其他值（含大小写不同、空串、`metal`）进入 `render_init` 分支，带 int `textureId` 时先 `_release` 再抛 `PlatformException`。公共枚举仍为 `enum MpvVideoBackend { vulkan, software }`（`final-audit.txt` 的 enum_line 与 dart_surface 审计，我复读了源码确认）。
- `git diff 3a5f450 HEAD -- packages/mpv_kit/lib packages/mpv_kit/test/api_freeze_test.dart` 为空，公共 API 冻结成立。
- 本机重跑 `flutter test test/controller_channel_test.dart test/video_controller_test.dart`：25 项全部通过，包含「create maps every private GPU wire name to MpvVideoBackend.vulkan」「unknown backend wire names still throw render_init and release the texture」「concurrent creates validate their own responses independently」。
- 三个平台插件（`windows/mpv_kit_video_plugin.cpp`、`linux/mpv_kit_video_plugin.cc`、`macos/Classes/MpvKitVideoPlugin.mm`）都用 `VideoRenderer::wire_name()` 输出 `backend` 字段。
- reason 语法：`Start()` 中 head 为 `<wire> (<renderer>) on <device>`，trail 为 `<api>/<renderer> unavailable: <why>`，由 `JoinTrails` 以 `"; "` 连接；`SanitizeReasonField` 把 `;` 换成 `,`、控制字符换成空格。CI 上三平台的真实 reason 行见 `ci-runs.txt`（例如 Windows 托管 runner：`software (sw) on cpu; vulkan/gpu-next unavailable: vkCreateInstance failed; vulkan/gpu unavailable: vkCreateInstance failed`）；RTX 4060 上为 `vulkan (gpu-next) on NVIDIA GeForce RTX 4060 Laptop GPU`。ADR 0004 存在且包含 Decision 1-5（枚举冻结、wire 名、reason 语法、`MPV_KIT_VIDEO_API`、候选链）。
- `MPV_KIT_VIDEO_API`：`ParseForcedApi` 校验 `^[a-z0-9-]{1,16}$`，不合法值匹配不到任何候选，回显把非法字符换成 `?` 并截到 16 字符；`ForcedAllows` 排除被强制 API 之外的候选以及 gpu-next/gpu 请求的软件兜底，所以强制运行不会回退；被排除的候选不构造后端。Dart 公共 API 没有新增（dart_surface 审计：唯一新增常量是私有的 `_gpuWireNames`）。`video_renderer_api_test` 在 CI（linux、macos-15、windows-2025、sanitizers）上 OK。

### 「新增一个候选项即可接入或回滚」（目标后半句）

`Interop::BackendCandidates(choice)`（默认 `DefaultCandidates`）与 `Interop::CreateBackend(api)` 是接缝：平台只需在候选列表里加一项并在 `CreateBackend` 里返回自己的 `RenderBackend`，引擎的帧环、隔离期、退避、swap、ICC、事件都不用动；删掉这一项即回滚。`Start()` 的候选循环是数据驱动的（`VideoRenderer::NewBackend` 先问平台、再用内置的 software/vulkan）。✓

### 必需产物

| 产物 | 预期 | 状态 | 细节 |
|------|------|------|------|
| `packages/mpv_kit_video/src/render_backend.h` | 接口、`BackendCandidate`、`DefaultCandidates`、契约文档 | ✓ VERIFIED | 166 行，契约文字在 `025bdad` 后与两个后端的真实行为一致 |
| `packages/mpv_kit_video/src/video_renderer.cc` | 通用引擎 + `SoftwareBackend` + 候选循环 + 强制 API | ✓ VERIFIED | 858 行，已通读；`Start`、`RenderLoop`、`RenderOnce` 与计划描述一致 |
| `packages/mpv_kit_video/src/vulkan_backend.cc` | `VulkanRenderBackend` | ✓ VERIFIED | 577 行；`Create/AllocTargets/FrameFor/Render/Wait/Release` 都在 |
| `packages/mpv_kit_video/lib/src/video_controller.dart` | wire 名集合与映射 | ✓ VERIFIED | 见上 |
| `native/tests/*`（5 个 golden + api + affinity + sw_hold_front） | 测试 | ✓ VERIFIED | 在 `meson.build` 注册；CI 上 OK |
| `docs/adr/0004-render-backend-reporting.md` | ADR | ✓ VERIFIED | 存在并含 5 项决定 |
| `docs/perf/renderbackend-seam-baseline.md`、`renderbackend-seam-regression.md` | 基线与回归文档 | ✓ VERIFIED | 存在；回归文档含 `## Verification tiers`，Linux 真 GPU 与 macOS 真机明确写「未验证」 |
| `evidence/ci-runs.txt`、`final-runs.txt`、`golden-freeze.sha256`、`tools/ci_gate.sh`、`tools/constants_audit.sh` | 证据与门 | ✓ VERIFIED | 全部存在，追加式 |

### 关键连接

| 从 | 到 | 经由 | 状态 | 细节 |
|----|----|------|------|------|
| `VideoRenderer::Start` | `RenderBackend::Create` | 候选循环 + `NewBackend` | WIRED | `video_renderer.cc` 第 323-366 行 |
| `RenderLoop` | `RenderBackend::BindThread/Release/UnbindThread` | 线程开头与结尾 | WIRED | 第 545、651-653 行 |
| `RenderOnce` | `AllocTargets / FrameFor / Wait / Render / FreeRetired` | `render_backend_->` | WIRED | 第 698-855 行 |
| `Interop::FrameReady/RetainFrame` | 平台插件 | 保留在平台侧 | WIRED | `interop_->FrameReady()`（第 642、854 行） |
| 平台插件 `create` 响应 | Dart `_gpuWireNames` | `wire_name()` | WIRED | 三个插件各一处 |

### 数据流追踪（Level 4）

本阶段是纯重构加上报，没有新增向 UI 渲染动态数据的组件。`reason` 与 `backend` 由 `Start()` 的真实候选循环产生，并在 CI 三平台的真实插件测试里以非空、符合语法的值回读（`ci-runs.txt` 的 `integration platform=` 行），数据确实流动，不是静态返回。

### 行为抽查

| 行为 | 命令 | 结果 | 状态 |
|------|------|------|------|
| golden 冻结文件未变 | `shasum -a 256 -c evidence/golden-freeze.sha256` | 5/5 OK | ✓ PASS |
| 常量未变 | `bash tools/constants_audit.sh` | `CONSTANTS ok`，rc 0 | ✓ PASS |
| Dart wire 名与枚举冻结 | `flutter test test/controller_channel_test.dart test/video_controller_test.dart` | 25 项全过 | ✓ PASS |
| 公共 API 冻结 | `git diff 3a5f450 HEAD -- packages/mpv_kit/lib packages/mpv_kit/test/api_freeze_test.dart` | 空 | ✓ PASS |
| 托管 CI 全绿（HEAD 前一提交） | `gh run view 40442377807 / 40442377813` | 均 success，headSha `025bdad` | ✓ PASS |
| 原生 golden / affinity / hold_front 测试 | 本机没有 meson/ninja，也没有配置好的 MSVC 环境 | 未重跑；依赖 CI 记录（`ci-runs.txt` 的 12-12 followup 行）与上面 `gh run view` 的 success 结论 | ? SKIP（已由 CI 证据覆盖） |
| 真机 RTX 4060 运行 | 不允许重跑 | 依赖 `evidence/final-runs.txt` 与回归文档 | ? SKIP |

### 探针执行

本阶段没有 `scripts/*/tests/probe-*.sh` 形式的探针，PLAN 也没有声明这类探针。Step 7c 不适用。

### 需求覆盖

12 份 PLAN 的 frontmatter `requirements:` 合并后覆盖 RBE-01 至 RBE-08 全部 8 个 ID，`REQUIREMENTS.md` 里 Phase 12 映射的 8 个 ID 没有孤立项。

| 需求 | 来源计划 | 说明 | 状态 | 证据 |
|------|----------|------|------|------|
| RBE-01 | 12-02、12-04、12-08、12-12 | 修好 soak harness 并记录基线 | ? NEEDS HUMAN | 基线、harness 模式、中止根因修复都在；探针 0.0 症状仍在、根因未查明（见 SC1）。`REQUIREMENTS.md` 已勾为 Complete，建议人工确认是否维持 |
| RBE-02 | 12-01、12-05、12-07 | fake libmpv golden，先于搬迁 | ✓ SATISFIED | golden 冻结 5/5；RED 先行证据 |
| RBE-03 | 12-09 | 抽出 `RenderBackend` 接口 | ✓ SATISFIED | `render_backend.h` 与 `video_renderer.cc` |
| RBE-04 | 12-01、12-09、12-12 | 搬迁不改常量与 reason，4K 30 分钟持平 | ✓ SATISFIED | `CONSTANTS ok`；Phase 4 命令逐项 `same`；渲染变体 600 s 为 0 drops（见 human_verification 第 2 项的说明） |
| RBE-05 | 12-11、12-12 | `report_swap`、`render_context_free` 仅渲染线程 | ✓ SATISFIED | 代码核对 + `video_renderer_affinity_test`（RED 先行 `red-local-12-11-affinity.log`） |
| RBE-06 | 12-07、12-08、12-09、12-11 | 共享延迟释放契约，dispose 无 use-after-free | ✓ SATISFIED | retire 场景 golden、sanitizer job、CR-01 修复；残余 CR-01-R1/R2 已推迟 |
| RBE-07 | 12-03、12-06、12-10 | wire 名严格校验、reason 语法、ADR | ✓ SATISFIED | Dart 测试本机重跑通过；ADR 0004；reason 在 golden 与 CI 中验证 |
| RBE-08 | 12-03、12-10 | `MPV_KIT_VIDEO_API` 强制 API | ✓ SATISFIED | `video_renderer_api_test`；README 与 ADR 记载；无 Dart 公共 API 新增。CI 上没有「真实插件 + `MPV_KIT_VIDEO_API`」的运行（Nyquist 缺口 ③，已推迟） |

### 反模式扫描

对 `3a5f450..HEAD` 中改动的 `packages/`、`native/tests/`、`example/integration_test/`、`.github/` 文件扫描 `TBD/FIXME/XXX`：无匹配，债务标记门禁通过。

| 文件 | 行 | 模式 | 严重度 | 影响 |
|------|----|------|--------|------|
| `packages/mpv_kit_video/src/video_renderer.cc` | 363、669 | 通用引擎日志里写死 "Vulkan"（评审 IN-02） | ℹ️ 信息 | 只影响日志措辞；Phase 14/15 加后端前应改。已在后续待办 |
| `packages/mpv_kit_video/src/video_renderer.cc` | 184-201 | `SoftwareBackend::AllocTargets` 可能抛 `bad_alloc`，发生在渲染线程（评审 WR-05） | ⚠️ 警告 | 极端内存压力下才触发；已推迟 |
| `packages/mpv_kit_video/src/video_renderer.cc` | 374 | `std::thread` 构造失败时 `std::system_error` 逸出（评审 WR-06） | ⚠️ 警告 | 已推迟，析构函数里有对应的兜底释放分支 |

没有阻断目标的 stub、空实现或硬编码空数据。

### 已知推迟项（用户决定，不计入缺口）

来自 `.planning/todos/pending/`：第二控制器首帧停滞、代码评审 WARN/INFO 后续（WR-02 至 WR-06、IN-01 至 IN-06、UI-W1 至 UI-W3、CR-01-R1/R2）、Nyquist 缺口 ①至⑤、macOS `vk-gpu-timeout` golden 抖动。`12-VALIDATION.md` 的 `nyquist_compliant: false` 与此一致。我没有把它们当作失败。

### 需要人工确认

#### 1. SC1「像素探针 0.0 的原因」是否算交付

**测试：** 阅读 `.planning/todos/pending/2026-10-27-diagnose-second-controller-first-frame-stall-in-resize-front.md` 与 `docs/perf/renderbackend-seam-baseline.md`，决定是接受现状还是要求在本阶段内查明。
**预期：** 明确的接受或要求补查。
**为什么需要人工：** ROADMAP 字面要求「修」这一项，而代码与证据只能证明探针可信、症状不是本阶段引入。范围判断属于用户。

#### 2. 渲染路径 30 分钟真机数据

**测试：** 在 RTX 4060 上 `MPV_KIT_BENCH_RENDER=1 MPV_KIT_BENCH_SIZE=3840x2160 MPV_KIT_BENCH_SECONDS=1800 MPV_KIT_BENCH_LABEL=4k-rendered`，用 `example/integration_test/uhd_endurance_test.dart`，按 `docs/perf/renderbackend-seam-baseline.md` 的 Reproduce 步骤与 12-12 的运行前门禁。
**预期：** drops 0、vo-delayed 0、renderErrors 0、deviceLost false。
**为什么需要人工：** 需要真机与较长时间，本会话不能执行；且 Phase 4 的 30 分钟命令不渲染。

#### 3. CR-01 修复之后的真机回归范围

**测试：** 决定是否需要在 `025bdad` 之后重跑六组 harness 与 4K。
**预期：** 若接受「只改软件路径」，则无需重跑；否则按 12-12 的门禁重跑。
**为什么需要人工：** 风险判断。

### 缺口摘要

没有 FAILED 的真相，没有缺失或 stub 的产物，没有断开的关键连接，没有 BLOCKER。`gaps: []`。

`REQUIREMENTS.md` 已把 RBE-01 勾为 Complete，而本报告对 RBE-01 的判断是「需要人工确认」，原因是 SC1 的第二个悬空问题只被部分处理。如果用户接受人工确认项 1 的「接受现状」，则该勾选成立。

---

_验证时间：2026-10-27_
_验证者：Claude (gsd-verifier)_

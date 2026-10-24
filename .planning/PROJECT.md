# mpv_kit

## What This Is

libmpv 的 Dart/Flutter 绑定工程：`mpv_kit` 提供纯 Dart FFI 的完整客户端 API 与高层 `Player`，`mpv_kit_video` 通过 Vulkan 把 mpv 画面零拷贝渲染到 Flutter 纹理，`mpv_kit_libs` 以构建钩子分发 sha256 校验过的 LGPL libmpv。面向需要在 Windows、Linux、macOS 的 x64 与 arm64 上做高质量本地播放的 Flutter 应用。

## Core Value

以尽可能小的源码改动，换取可验证的稳定性与 4K/8K UHD 长时间满帧播放能力——不崩溃、不泄漏、不积压。

## Requirements

### Validated

<!-- 现有代码已经提供并被依赖的能力（来自 .planning/codebase/ 映射）。 -->

- ✓ 纯 Dart FFI 封装的 libmpv 客户端 API：typed events、`mpv_node` 转换、异步回复、子客户端、属性观察 — existing
- ✓ 高层 `Player` 与 `MpvState<T>`，每个状态对应一个 `mpv_observe_property` — existing
- ✓ 从 mpv 文档与运行期选项表生成的属性/命令/选项目录与 typed `MpvOptions` — existing
- ✓ Flutter 插件零拷贝 Vulkan 渲染：Windows D3D11 共享纹理、Linux GL memory object、macOS IOSurface/MoltenVK，自动软件回退 — existing
- ✓ 自定义流协议桥（patch 0006），Dart 异步应答 mpv demuxer 线程 — existing
- ✓ LGPL 预构建 libmpv 的下载、sha256/MANIFEST 校验与原生资产打包钩子 — existing
- ✓ 七项下游补丁（Vulkan render backend、Vulkan hwdec、shader cache、gpu-next Vulkan、renderer 上报、stream bridge、音频设备枚举修复） — existing
- ✓ 六目标 CI 构建、ABI 审计、ASan/UBSan 与 80% 行覆盖率门禁（Linux） — existing
- ✓ `Player`/`Mpv` 的 dispose 在 hook 抛错、重入调用、重复调用下仍完成核心销毁并关闭全部流；1000 次 create/dispose soak 通过 — Phase 1
- ✓ dispose 后 31 个公共 `Mpv` 入口抛 `StateError` 且不进入 native；API 冻结由反射测试约束 — Phase 1
- ✓ 失败注入回归套件（抛错监听器/dispose hook/流源 read·seek·close）、1000-cycle soak 与 CI tag 接线 — Phase 1
- ✓ `MpvVideoController.create` 原子化：畸形/新版本插件响应抛 `PlatformException(code: render_init)`（绝不 TypeError、绝不静默降级 software），携带 textureId 时释放 native 上下文，后续步骤失败回滚路由表/hook/native 上下文并可重试 — Phase 2
- ✓ 控制器 dispose 异常安全：native 通道抛错时事件流仍关闭（监听器收到 done）且错误可见；dispose 竞态中的在途 resize/ICC 失败被丢弃，活控制器上同等失败仍抛出 — Phase 2
- ✓ 100 轮 resize/dispose 交错与 100 次 create/dispose 循环 soak：Dart 记账层零泄漏（STAB-01 分句），并发 `Player.dispose` 单次 teardown、双调用方共享同一结果（IN-05 关闭） — Phase 2
- ✓ 三个 Dart 包全部纳入 80% 行覆盖率门禁；`flutter-video-coverage` 任务用 linux 任务构建的 libmpv 构件跑通 channel 测试（单一构建来源） — Phase 2

### Active

<!-- 本里程碑要达成的目标；全部保持公共 API 不变。 -->

- [ ] 让错误可见：不再静默吞掉流源、属性观察与原生回退失败
- [ ] `MpvLibrary.open()` 在显式 `MPV_KIT_LIBMPV_PATH` 加载失败时静默回退到平台默认库，调用方无法得知实际加载的是哪份 libmpv — 2026-10-24 在 Phase 1 收尾时发现（归 OBS-04）
- [ ] 修复每个属性事件重复解码等热路径浪费，并以基准数据证明收益
- [ ] 建立可复现的性能/稳定性验证（create/dispose 循环、resize、长时播放）
- [ ] 六目标（Windows/Linux/macOS × x64/arm64）构建与冒烟一致、可复现
- [ ] 4K/8K UHD 长时间播放：`delayed≈0`、`avdiff` 有界、无帧积压
- [ ] 补丁与构建单一来源，README/ADR 与实际 vendor 版本一致

### Out of Scope

- **移动端（Android/iOS/web）** — 本阶段明确不做；渲染互操作与 bundle 目标都未覆盖。
- **新增或破坏性公共 API** — 本里程碑 API 冻结，所有改动必须向后兼容。
- **版本发布节点、CHANGELOG、pub 发布流程** — 用户明确不着急，专注源码健康度。
- **新功能（display-sync/vsync 回报、HDR、播放列表、字幕等）** — 暂缓到后续里程碑。
- **大规模渲染架构重写** — 违反"小改动大收益"原则；只做有数据支撑的局部优化。

## Context

- 仓库当前在 `feat/mpv-master-upgrade` 分支，已把 vendored mpv 从 0.41.0 重基到 `v0.41.0-1113-gfd9265a905` 并重做七项补丁；首方改动仅 14 个文件（+899/−70）。
- 代码库映射位于 `.planning/codebase/`（STACK、ARCHITECTURE、STRUCTURE、CONVENTIONS、TESTING、INTEGRATIONS、CONCERNS），缺陷与脆弱点以 `CONCERNS.md` 为准。
- 现有文档：`docs/ARCHITECTURE.md`、`docs/ARCHITECTURE-diagrams.md`、`docs/adr/0001`、`docs/adr/0002`、`docs/reverse-engineering/`。
- 真机验证目前只有 Windows x64（RTX 4060）；Linux/macOS 仅编译与 lavapipe/MoltenVK 冒烟。
- 本地 `bt/` 下的 `libmpv-2.dll` **带 patch 0006**（导出 `mpv_kit_stream_*`）。Windows 没有 rpath，直接把它设为 `MPV_KIT_LIBMPV_PATH` 会因依赖 DLL 不在搜索路径而静默回落到 PATH 上的 stock 库；要跑流源测试必须同时把 `bt/` 加进 PATH。Phase 1 曾因此错误地把 3 条可执行测试记为「环境受限」。
- 已知问题集中在：`Player.dispose` 非异常安全、`Mpv` 方法在 dispose 后仍可调用、属性事件重复解码、`MpvVideoController.create` 解析失败无回滚、流源错误被吞、`bt/` 38MB DLL 入库、`pubspec.lock` 被忽略、SDK 约束不一致。
- 探索阶段曾误判"Linux/macOS `create` 必然失败"与"系统 libmpv 不支持 `gpu-shader-cache-dir`"；经源码复核均为误报，现状可用但缺少测试与可读错误。

## Constraints

- **Compatibility**: Windows 10+、macOS 12+（实际 bundle 目前需 macOS 15）、Linux glibc 2.35+；x64 与 arm64 六个桌面目标。
- **API**: 公共 API 冻结，不新增、不破坏。
- **Change size**: 每项改动尽量小、可独立回滚；拒绝大范围重写。
- **Platform**: 不做移动端与 web。
- **License**: libmpv/FFmpeg 保持 LGPL，禁止 GPL/nonfree 依赖进入 bundle。
- **Verification**: 真实插件行为必须在 CI runner 上验证；mock channel 不能替代。

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| 本里程碑只优化现有源码，不加新功能 | 用户要求"基于原先源码尽可能小改动大收益" | — Pending |
| 公共 API 冻结 | 降低回归面，避免与优化工作纠缠 | — Pending |
| 不设发布节点 | 用户明确版本发布不着急 | — Pending |
| 只覆盖六个桌面目标 | 移动端渲染与 bundle 工作量大，且不在当前目标内 | — Pending |
| 性能改动必须先有基准数据 | 防止"优化"退化为重构 | — Pending |
| 生命周期不变量用「失败注入 + soak」固化，而不是只写文档 | 退出码与流关闭是可观测证据 | ✓ Phase 1 |
| 同步广播控制器的关闭必须走一个派发安全的助手 | 在监听器内重入 dispose 是真实可达路径 | ✓ Phase 1 |
| 验证结论必须区分「测过且通过」与「因环境没跑」 | Phase 1 曾把可执行测试误判为环境受限，导致 4 条真值长期悬空 | ✓ Phase 1 |
| create 响应的 backend 字段严格校验（garbage 抛错而非静默 software 降级） | 同仓库插件/Dart 对里任何其他值都是协议断裂,STAB-04 要求它可见 | ✓ Phase 2 |
| 重入 dispose 与并发 dispose 在调用时刻不可区分,一律共享 in-flight future;hook 内 await dispose 列为禁止模式 | 死锁不可恢复,而早返回语义可恢复;unawaited 重入模式(Phase 1 固化)不受影响 | ✓ Phase 2 |
| 覆盖率任务消费 linux 构建的 libmpv 构件,不重复构建 | 单一构建来源(BUILD-01 方向);构件缺失时 download 步骤先响亮失败 | ✓ Phase 2 |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-10-24 after Phase 2*

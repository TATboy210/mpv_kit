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

### Active

<!-- 本里程碑要达成的目标；全部保持公共 API 不变。 -->

- [ ] 消除 dispose/事件/创建失败路径上的崩溃与原生资源泄漏
- [ ] 让错误可见：不再静默吞掉流源、属性观察与原生回退失败
- [ ] 修复每个属性事件重复解码等热路径浪费，并以基准数据证明收益
- [ ] 建立可复现的性能/稳定性验证（create/dispose 循环、resize、长时播放）
- [ ] 六目标（Windows/Linux/macOS × x64/arm64）构建与冒烟一致、可复现
- [ ] 4K/8K UHD 长时间播放：`delayed≈0`、`avdiff` 有界、无帧积压
- [ ] 补丁与构建单一来源，README/ADR 与实际 vendor 版本一致
- [ ] 为关键失败路径补充回归测试（真实插件、失败注入）

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
*Last updated: 2026-10-23 after initialization*

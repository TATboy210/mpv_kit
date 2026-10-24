# Phase 10: Composition Spike - Context

**Gathered:** 2026-10-24
**Status:** Ready for planning

<domain>
## Phase Boundary

用证据而非推测决定合成路径。本阶段交付三样东西：

1. **REA 逆向报告** — 本机 `flutter_windows.dll`（Flutter 3.47.6）如何消费外部纹理：两种表面类型（`DxgiSharedHandle` / `D3d11Texture2D`）的实际绑定路径、是否经 ANGLE、fence 语义、DXGI 设备归属；证据（符号、地址、反汇编/伪代码）落盘 `docs/reverse-engineering/`。
2. **Impeller 冒烟** — 示例应用在 Impeller 下 `create → 渲一帧 → dispose` 的结果记录，对照 flutter#191468 / PR #191017。
3. **决策文档** — 选定路径、依据、回退条件、quarantine 预算假设；若结论是「3.47.6 不可行」，记录所需 Flutter 版本与升级条件。

**不做**：实现原生合成路径（Phase 11 的 COMP-02/COMP-03）；不做移动端；不改公共 API。

> **前提更正（2026-10-24，来自 `10-RESEARCH.md`）：** 本 CONTEXT.md 成稿时沿用了里程碑研究的说法「真正的绕过是 Impeller」。调研推翻了它：3.47.6 的 Windows Impeller 是 **GLES-over-ANGLE**，`impeller/renderer/backend/` 只有 gles/metal/vulkan，`EmbedderExternalTextureGL::ResolveTextureImpeller` 消费的仍是 ANGLE 绑定的 GL 纹理。启用 Impeller 去掉的是 Skia/Ganesh 与每次 resolve 的 `flushAndSubmit()`，**并未移除外部纹理交接中的 ANGLE**。
>
> 因此 Phase 10 的决策文档必须回答的是：**还能不能更短、更便宜**，而不是「能不能无 ANGLE」。Phase 11 的目标已据此在 `ROADMAP.md` 重写为「缩短渲染链路（升级绕过 / 上推 issue / 自改 ANGLE）」。

</domain>

<decisions>
## Implementation Decisions

### REA 取证深度
- **D-01:** 对纹理消费路径做**逐路径反编译到伪代码**，而不是只做符号级定位。报告要能逐点落到 allocation / fence / 设备归属，使 Phase 11 可以直接照着实现。 — **Reversibility:** reversible — 只是文档深度，多做的取证不会约束后续设计。
- **D-02 (superseded 2026-10-24):** ~~取证对象固定为 Flutter 3.47.6~~ → **目标版本改为 Flutter 3.47.8**（用户决定，3.47.8 已发布）。取证对象是 3.47.8 的 `flutter_windows.dll`；CI 的 `FLUTTER_VERSION: 3.47.6` 需同步升级。**REV-1:** `10-RESEARCH.md` 中 3.47.6 的下载 URL、DLL sha256、SDK sha256、锚点字符串计数与源码结论全部作废，必须按 3.47.8 重新取证后才能据以规划。 — **Reversibility:** costly — 已写好的两份计划与一次调研建立在此版本上，改版需要重跑调研并重写计划。

### Impeller 冒烟范围
- **D-03 (superseded 2026-10-24):** ~~冒烟只测 3.47.6~~ → 冒烟**只测 3.47.8**，仍不做多版本对照。若失败，报告记录「升级到哪个版本可能修好、前置条件是什么」，但不代为验证。 — **Reversibility:** reversible。
- **D-04:** 冒烟内容合并为同一次运行的三段（这是 D-03 的 Impeller 范围与 D-06 的判定门槛调和后的结果，不是两个独立任务）：
  1. `create → 渲一帧 → dispose`（最小链路）
  2. 一次 4K 帧
  3. 30 秒连续播放 + 100 轮 resize/dispose 交错

  被明确排除的是「N 分钟稳定性」与「完整 gpu-next→gpu→software 回退矩阵在 Impeller 下的一致性」——那两项留给 Phase 11。

### 「可行」的判定门槛
- **D-05:** 判定 Impeller 路径可行的门槛是：**30 秒连续播放 + 100 轮 resize/dispose 交错不崩**。单帧成功不构成可行。 — **Reversibility:** costly — 这个门槛直接决定 Phase 11 是被正式批准还是缩为记录性收口；一旦按「可行」批准，Phase 11 的排期与范围随之锁定，改判需要重走一次决策。
- **D-06:** 若门槛未过，Phase 10 仍算完成：产出「不可行」的证据与所需版本/条件，Phase 11 依此缩为记录性收口（ROADMAP 已允许）。

### Claude's Discretion
- **回退契约与 quarantine 预算**（用户本轮未选择讨论）：运行时 Impeller 路径失败时是静默回退 ANGLE + 发事件，还是显式报错；以及是否在 spike 内实测 compositor 延迟以替换 `quarantine=4`。这两项归属 Phase 11（其成功标准已要求 `backend`/`reason`/HUD 上报与延迟参数化），本阶段不锁定，planner 不应把它们写成 Phase 10 的交付物。

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### 既有逆向与架构
- `docs/reverse-engineering/02-flutter-windows-external-texture.md` — 已有的 3.47.6 外部纹理分析（本阶段是它的深化与实证）
- `docs/reverse-engineering/01-libmpv-render-pipeline.md` — 渲染侧现状：自有 Vulkan 后端，合成侧当前经 ANGLE
- `docs/ARCHITECTURE.md` — 渲染线程、frame ring、quarantine、无跨 API fence 的设计约束
- `docs/adr/0001-vulkan-render-backend.md` — 为什么渲染侧是 Vulkan 而非 ANGLE

### 里程碑与研究依据
- `.planning/research/SUMMARY.md` — v2 核心结论：两种表面类型都经 ANGLE；真正绕过是 Impeller；#191468 崩溃史
- `.planning/ROADMAP.md` §Phase 10 / §Phase 11 — 本阶段成功标准与下游依赖
- `https://github.com/flutter/flutter/issues/191468` — Impeller DXGI shared-handle 外部纹理崩溃
- PR #191017 — 修复提交（在 main，3.47.6 未验证）

### 待实证的本机实现
- `packages/mpv_kit_video/windows/d3d11_interop.cpp` / `.h` — 当前共享纹理创建与 fence/quarantine 的调用点
- `packages/mpv_kit_video/src/video_renderer.h` — `CompositorLatency()` 与 quarantine 预算（现在硬编码 4）
- `.github/workflows/flutter-plugin.yml:17` — `FLUTTER_VERSION: 3.47.6`（版本锁的证据）

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `d3d11_interop.cpp` 已有两条表面类型的具体创建代码——REA 报告可以直接引用这些调用点，把「引擎侧怎么消费」与「我们怎么生产」对齐。
- `video_renderer.h` 的 `CompositorLatency()` 是 quarantine 预算的唯一抽象点，Phase 11 的参数化只需改这里。

### Established Patterns
- 证据落盘遵循 `docs/reverse-engineering/` 的既有两篇：问题陈述 → 反汇编/符号证据 → 结论与未决项。
- 诚实 reason 基建（v1 Phase 3）已在渲染回退路径上存在，Phase 11 复用它上报实际路径。

### Integration Points
- Impeller 开关在示例应用侧（`example/`），不涉及公开 API。
- 决策文档的输出位置与命名需与 `docs/reverse-engineering/` 既有编号衔接（下一篇为 03）。

</code_context>

<specifics>
## Specific Ideas

- 报告必须能让读者回答三个具体问题：**经不经 ANGLE**、**谁拥有 DXGI 设备**、**fence 语义是什么**。这三问是 v2 研究的原始驱动。
- 冒烟结果要能与 #191468 的崩溃特征对照，因此崩溃时要记录：有无 WER、崩溃点、是否发生在 shared-handle 纹理的 acquire 阶段。

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 10-Composition Spike*
*Context gathered: 2026-10-24*

# Roadmap: mpv_kit — milestone v2.0

**Milestone:** v2.0 GPU-Next Optimization & Full-Rate UHD（阶段编号自 7 继续；v1 的阶段 1-6 已归档于 `.planning/milestones/v1-phases/`，其成功标准与验证记录以归档为准）

## Overview

研究驱动（见 `.planning/research/SUMMARY.md`）：先把 vendor 树推进到 mpv-master 新点并重放补丁（PATCH-DRIFT 门禁机械验证），锁定 gpu-next 上游演化；同时把 8K 提交内存耗尽的修复落在 Player 选项包推导层；早做调试 HUD 为后续一切提供观测面板；拖拽播放补齐调试体验；合成路径以 spike 先行——REA 逆向引擎二进制实证 + Impeller 冒烟；依证据在「升级引擎绕过 / 上推 Flutter issue / 自改 ANGLE」之间选路，目标是**缩短渲染链路**而非承诺无 ANGLE，并保留运行时回退；最后以 4K/8K 满血验收收口。v1 的五道 CI 门禁与三平台 integration test 全程把关。

## Phases

- [x] **Phase 7: mpv-master Vendor Advance & gpu-next Regression** - vendor 推进到快照点，补丁重放门禁通过，新基线回归全绿 (completed 2026-10-24; 4K 30-min re-verify environment-blocked: host disk 100%)
- [x] **Phase 8: Debug HUD & Drag-and-Drop** - 可切换调试 overlay（五组属性+事件流+合成路径）与拖拽播放 (completed 2026-10-25; drag gesture itself left as 30 s manual UAT)
- [ ] **Phase 9: 8K Full-Rate** - demuxer 队列按帧尺寸推导，8K 30 分钟门禁通过
- [ ] **Phase 10: Composition Spike** - REA 实证引擎纹理消费路径 + Impeller 冒烟，决策落盘
- [ ] **Phase 11: Native Composition Path** - 依证据选路缩短渲染链路（升级绕过 / 上推 issue / 自改 ANGLE），带 ANGLE 回退与延迟预算参数化

## Phase Details

### Phase 7: mpv-master Vendor Advance & gpu-next Regression

**Goal**: vendor 树推进到用户提供的 mpv-master 快照（或更新点），补丁 0001..0008 重放后与 vendor 字节级一致；新基线上 gpu-next 无回归。
**Depends on**: Nothing (first phase of v2)
**Requirements**: REBASE-01, REBASE-02
**Success Criteria** (what must be TRUE):
  1. `native/mpv/MPV_VERSION` 指向新基线；`bash tools/check_patches.sh` 输出 PATCH-DRIFT OK（新 base + 重放后的补丁集，含 UPSTREAM.md 记录的任何手工重排）。
  2. 一致性门禁（CONSISTENCY）通过——README/ARCHITECTURE/ADR 的版本提及与 MPV_VERSION 联动更新。
  3. 新基线回归：seek 后画面恢复显式测试（mpv#17258 类）、4K 基准对照（对比 docs/perf 基线无退步）、六目标 CI + 三平台 integration test 全绿。

**Plans:** 2/2 executed

Plans:
- [x] 07-01-PLAN.md — Snapshot identified as exactly b2c255c13e8e (blob walk + full-tree diff=0); vendor advanced; patches replayed (0001..0007 zero rejects, 0008 -> version stamp); PATCH-DRIFT OK at the new base. The advance doubles as a provenance correction: v1's 0008 deltas were the two separating upstream commits, already in the old tree.
- [x] 07-02-PLAN.md — Build source recorded (dev.3 byte-identical justification); seek_recovery_test green (RED-proven; lavfi forward-only semantics pinned, MPV_KIT_SEEK_MEDIA hook); suites/api_freeze/decode-bench green; 4K 30-min blocked by host disk 100% (not a code regression — same binary passed the same day; evidence in docs/perf/2026-10-24-vendor-advance-regression.md)

### Phase 8: Debug HUD & Drag-and-Drop

**Goal**: example 应用成为调试面板——五组属性 overlay + 事件流 + 合成路径展示；拖拽视频即播。
**Depends on**: Phase 7（HUD 在最终 vendor 点上开发与验证；合成路径字段在 11 前显示 ANGLE 占位）
**Requirements**: HUD-01, HUD-02, DND-01
**Success Criteria** (what must be TRUE):
  1. 可切换 overlay 实时显示同步（avsync 族）/缓存（demuxer-cache-state）/解码（hwdec/params）/渲染（backend/reason/事件）/音频五组，1s 轮询不触生产热路径。
  2. 拖拽视频文件到窗口播放首个视频；非视频忽略且 HUD 提示；播放器交互不冲突。
  3. HUD 显示当前合成路径（ANGLE 阶段为实际后端+reason；11 完成后含 compositor 信息）。

**Plans:** 1/1 executed

Plans:
- [x] 08-01-PLAN.md — hud.dart (HudSnapshot 1 Hz capture / HudEventLog 8-ring / DebugHud five-group panel / isVideoPlayable allowlist), main.dart rewiring (F9/H toggle, DropTarget, transient notice), desktop_drop ^0.7.1, 6 widget tests green, Windows build compiles, smoke on real mp4 + lavfi (Vulkan path logs + screenshot).

### Phase 9: 8K Full-Rate

**Goal**: 8K 连续 30 分钟满帧：零丢帧、avdiff 有界、无积压、无提交内存耗尽；且不伤 1080p/4K 吞吐。
**Depends on**: Phase 8（HUD 提供验收观测面板）
**Requirements**: UHD-01, UHD-02
**Success Criteria** (what must be TRUE):
  1. Player demuxer 队列选项按帧尺寸推导（公式文档化并有单测）；1080p/4K 基准与 v1 基线对照无退步。
  2. 8K 7680x4320 × 1800s：UHD endurance 门禁全绿（此前崩溃于 ≤40s）。
  3. 验收记录落盘 docs/perf（机器/分辨率/指标终值，复用 v1 报告格式）。

**Plans**: TBD

### Phase 10: Composition Spike

**Goal**: 以证据决定合成路径：REA 逆向本机 flutter_windows.dll（3.47.8）的外部纹理消费实现 + Impeller 开关冒烟。
**Depends on**: Phase 7（在最终 vendor 点上做渲染实验）
**Requirements**: COMP-01
**Success Criteria** (what must be TRUE):
  1. REA 报告：两种表面类型在 3.47.8 二进制中的实际绑定路径（ANGLE 与否、fence 语义、设备归属），证据（反汇编/符号）落盘 docs/reverse-engineering/。
  2. Impeller 冒烟：示例应用开启 Impeller 后 create→渲染一帧→dispose 的结果记录（成功/崩溃，对照 flutter#191468 与 #191017）。
  3. 决策文档：选定的路径、依据、回退条件、quarantine 预算假设；若结论是"3.47.8 不可行"，记录所需 Flutter 版本与升级条件，Phase 11 依此调整（允许缩为记录性收口）。

**Plans:** 3/6 plans executed

Plans:
**Wave 1**
- [x] 10-01-PLAN.md — 钉死本机 3.47.8 引擎工件（sha256/PDB/锚点/导入表），逐路径反编译注册、ANGLE 绑定、Impeller/Skia 消费，落盘 03 号逆向报告。
- [x] 10-02-PLAN.md — 钉死 3.47.8 SDK 与 CI 版本锁，写单 testWidgets 的 D-04 三段 harness（含非黑断言与 idle 分类），analyze 干净。
- [ ] 10-04-PLAN.md — 收口 gap：报告通道改 `print` 并端到端证明 preflight BENCH 可达；part-1 就绪门改为 setSize + resize 证据；像素切片与失败上报补齐（CR-01/CR-02/WR-02/IN-06）。

**Wave 2** *(blocked on Wave 1 completion)*
- [x] 10-03-PLAN.md — Impeller 与 `--no-enable-impeller` 对照双运行，带 identity 的四桶分类，落盘 ADR 0003 决策。
- [ ] 10-05-PLAN.md — 在修好的 harness 上重跑 `--enable-impeller` / `--no-enable-impeller`，独立推导四桶分类并重写 `impeller-bench.txt` 与日志。

**Wave 3** *(blocked on Wave 2 completion)*
- [ ] 10-06-PLAN.md — 依分类文件更新 ADR `verdict` 与 Runtime smoke，补 reporting-channel 前置（WR-07）、evidence 路径（WR-06）、行号（IN-03）与 03 号报告 Q1（IN-02）。

### Phase 11: Native Composition Path

**Goal**: **缩短播放器渲染链路**，以可度量的合成开销与 4K 支撑为准，而不是以「无 ANGLE」这种在 3.47.6 上无法验证的口号。按 Phase 10 的证据选路线，三条并行候选：① 能绕过就绕过（升级到提供 Vulkan/D3D 后端的引擎版本）；② 绕不过就把本项目的 4K 外部纹理合成需求与复现整理成 Flutter GitHub issue 上推；③ 仍不行则自行修改 ANGLE 相关路径以提升效率、支撑 4K。保留运行时回退 ANGLE 路径。

> **前提更正（2026-10-24，Phase 10 调研）：** 3.47.6 的 Windows Impeller 是 GLES-over-ANGLE，`impeller/renderer/backend/` 只有 gles/metal/vulkan；`EmbedderExternalTextureGL::ResolveTextureImpeller` 消费的仍是 ANGLE 绑定的 GL 纹理。因此「启用 Impeller = 整链路无 ANGLE」不成立，本阶段目标据此重写。证据见 `.planning/phases/10-composition-spike/10-RESEARCH.md`。

**Depends on**: Phase 10（证据与决策）
**Requirements**: COMP-02, COMP-03
**Success Criteria** (what must be TRUE):
  1. 依 Phase 10 的证据选定路线并记录理由；实施后每条路径探测失败可自动回退 ANGLE，`backend`/`reason`/HUD 上报实际路径（Phase 3 诚实 reason 基建）。
  2. **可度量收口**：选定路线在 4K 下产生可复现的合成开销改善（前后基准对比），或明确记录该路线被证伪并说明剩余开销来自哪里——不接受「感觉更快」。
  3. 每条路径的 compositor 延迟预算以基准实测并参数化（替换拍脑袋的 quarantine=4）；100 轮 resize/dispose 交错 soak 无 use-after-release、无黑帧。
  4. 4K/8K 满血验收：4K 30 分钟门禁复绿；8K 达标（Phase 9 绿后 compositor 变更必须复验）；三平台 CI 全绿。

**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 7 → 8 → 9 → 10 → 11

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 7. mpv-master Vendor Advance & gpu-next Regression | 2/2 | Complete | 2026-10-24 |
| 8. Debug HUD & Drag-and-Drop | 1/1 | Complete | 2026-10-25 |
| 9. 8K Full-Rate | 0/TBD | Not started | - |
| 10. Composition Spike | 3/3 | In Progress | - |
| 11. Native Composition Path | 0/TBD | Not started | - |

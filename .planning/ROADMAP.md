# Roadmap: mpv_kit — milestone v2.0

**Milestone:** v2.0 GPU-Next Optimization & Full-Rate UHD（阶段编号自 7 继续；v1 的阶段 1-6 已归档于 `.planning/milestones/v1-phases/`，其成功标准与验证记录以归档为准）

## Overview

研究驱动（见 `.planning/research/SUMMARY.md`）：先把 vendor 树推进到 mpv-master 新点并重放补丁（PATCH-DRIFT 门禁机械验证），锁定 gpu-next 上游演化；同时把 8K 提交内存耗尽的修复落在 Player 选项包推导层；早做调试 HUD 为后续一切提供观测面板；拖拽播放补齐调试体验；合成路径（ANGLE 绕过）以 spike 先行——REA 逆向引擎二进制实证 + Impeller 冒烟，依证据实施原生路径并保留运行时回退；最后以 4K/8K 满血验收收口。v1 的五道 CI 门禁与三平台 integration test 全程把关。

## Phases

- [x] **Phase 7: mpv-master Vendor Advance & gpu-next Regression** - vendor 推进到快照点，补丁重放门禁通过，新基线回归全绿 (completed 2026-10-24; 4K 30-min re-verify environment-blocked: host disk 100%)
- [ ] **Phase 8: Debug HUD & Drag-and-Drop** - 可切换调试 overlay（五组属性+事件流+合成路径）与拖拽播放
- [ ] **Phase 9: 8K Full-Rate** - demuxer 队列按帧尺寸推导，8K 30 分钟门禁通过
- [ ] **Phase 10: Composition Spike** - REA 实证引擎纹理消费路径 + Impeller 冒烟，决策落盘
- [ ] **Phase 11: Native Composition Path** - 依 spike 实施原生合成（ANGLE 回退），延迟预算实测参数化

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

**Plans**: TBD

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

**Goal**: 以证据决定合成路径：REA 逆向本机 flutter_windows.dll（3.47.6）的外部纹理消费实现 + Impeller 开关冒烟。
**Depends on**: Phase 7（在最终 vendor 点上做渲染实验）
**Requirements**: COMP-01
**Success Criteria** (what must be TRUE):
  1. REA 报告：两种表面类型在 3.47.6 二进制中的实际绑定路径（ANGLE 与否、fence 语义、设备归属），证据（反汇编/符号）落盘 docs/reverse-engineering/。
  2. Impeller 冒烟：示例应用开启 Impeller 后 create→渲染一帧→dispose 的结果记录（成功/崩溃，对照 flutter#191468 与 #191017）。
  3. 决策文档：选定的路径、依据、回退条件、quarantine 预算假设；若结论是"3.47.6 不可行"，记录所需 Flutter 版本与升级条件，Phase 11 依此调整（允许缩为记录性收口）。

**Plans**: TBD

### Phase 11: Native Composition Path

**Goal**: 依 spike 结论实施原生合成路径，整链路（mpv Vulkan 后端 + 原生合成）无 ANGLE；保留运行时回退。
**Depends on**: Phase 10（证据与决策）
**Requirements**: COMP-02, COMP-03
**Success Criteria** (what must be TRUE):
  1. 原生路径按 spike 决策实施；探测失败时自动回退 ANGLE 路径，`backend`/`reason`/HUD 上报实际路径（Phase 3 诚实 reason 基建）。
  2. 每条路径的 compositor 延迟预算以基准实测并参数化（替换拍脑袋的 quarantine=4）；100 轮 resize/dispose 交错 soak 无 use-after-release、无黑帧。
  3. 4K/8K 满血验收：4K 30 分钟门禁复绿；8K 达标（Phase 9 绿后 compositor 变更必须复验）；三平台 CI 全绿。

**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 7 → 8 → 9 → 10 → 11

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 7. mpv-master Vendor Advance & gpu-next Regression | 2/2 | Complete | 2026-10-24 |
| 8. Debug HUD & Drag-and-Drop | 0/TBD | Not started | - |
| 9. 8K Full-Rate | 0/TBD | Not started | - |
| 10. Composition Spike | 0/TBD | Not started | - |
| 11. Native Composition Path | 0/TBD | Not started | - |

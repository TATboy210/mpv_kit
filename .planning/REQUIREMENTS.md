# Requirements: mpv_kit

**Milestone:** v2.0 GPU-Next Optimization & Full-Rate UHD
**Defined:** 2026-10-24
**Core Value:** 以尽可能小的源码改动，换取可验证的稳定性与 4K/8K UHD 长时间满帧播放能力——不崩溃、不泄漏、不积压。
**Research:** .planning/research/SUMMARY.md（ANGLE 绕过路径、gpu-next 社区反馈、mpv-master 快照、HUD/拖拽盘点）

## Milestone v1.0 (completed 2026-10-24)

21/21 需求全部交付（STAB-01..05、OBS-01..04、PERF-01..04、BUILD-01..04、VERIFY-01..04），证据在 `.planning/milestones/v1-phases/` 与 docs/perf。公共 API 冻结由 api_freeze_test 钉死；五道 CI 门禁（patch-drift/consistency/pins/matrix/coverage）与三平台 integration test 常态运行。

## v2 Requirements

本里程碑范围。基线：v1 的全部门禁与测试保持绿色；公共 API 兼容优先（新增只读诊断字段需在计划中显式列出）。

### mpv-master Advance & gpu-next Regression (REBASE)

- [x] **REBASE-01**: vendor 树推进到用户提供的 mpv-master 快照（或更新点），补丁 0001..0008 重放后 PATCH-DRIFT 门禁字节级通过；MPV_VERSION/README/一致性检查联动更新
- [x] **REBASE-02**: 新基线上 gpu-next 回归验证——seek 后画面恢复（mpv#17258 类）、帧节奏（4K 基准对照）、六目标 CI + 三平台 integration test 全绿

### Native Composition (COMP)

- [ ] **COMP-01**: 合成路径 spike 报告——REA 逆向本机 flutter_windows.dll（3.47.6）的纹理消费路径 + Impeller 开关冒烟；决策记录（哪条路径、证据、回退条件）
- [ ] **COMP-02**: 依 spike 结论实施原生合成路径（带 ANGLE 运行时回退），`backend`/`reason` 上报实际合成路径，HUD 可见
- [ ] **COMP-03**: 每条合成路径的 compositor 延迟预算实测并参数化（quarantine），100 轮交错 soak 无 use-after-release、无黑帧

### 8K Full-Rate (UHD)

- [ ] **UHD-01**: Player 的 demuxer 队列选项按帧尺寸推导（公式文档化）；1080p/4K/8K 三档回归基准同时通过（不伤低分辨率吞吐）
- [ ] **UHD-02**: 8K 7680x4320 连续 30 分钟通过 v1 门禁（零丢帧、avdiff 有界、无积压、无提交内存耗尽）

### Debug HUD (HUD)

- [ ] **HUD-01**: example 可切换调试 overlay——同步/缓存/解码/渲染/音频五组属性（stats.lua 同源集合，已对目录核对）+ 控制器事件流实时叠加
- [ ] **HUD-02**: HUD 显示实际合成路径与后端信息（backend/reason/compositor）

### Drag-and-Drop (DND)

- [ ] **DND-01**: 拖拽视频文件到 example 窗口即播放首个视频（desktop_drop）；非视频文件忽略并 HUD 提示；与播放器手势不冲突

## Deferred（未来里程碑）

### Playback Features（继承 v1-v2）
- **FEAT-01**: 渲染桥向 mpv 回报 vsync/显示相位（`video-sync=display-*` 可用）
- **FEAT-02**: HDR swapchain 提示与 tone-map 路径
- **FEAT-03**: 播放列表、字幕与音轨的更高层 API
- **FEAT-04**: 多文件拖入生成播放列表（DND-01 只取首个，留扩展点）

### Renderer Compatibility（继承 v1-v2）
- **GPU-01..03**: 旧 GPU 的 Vulkan 1.2 设备支持、可诊断的能力协商、真实回退链验证

### Platform
- **PLAT-01/02**: Android 垂直切片、iOS 可行性（不变）

## Out of Scope

| 项 | 理由 |
|----|------|
| 破坏性公共 API 变更 | 兼容优先；只读诊断新增须计划内显式声明 |
| DirectComposition 子窗口合成（STACK 选项 C） | 失去 widget 合成；仅作记录不实施 |
| 移动端/web | 不变 |
| MPO/HAGS 显示栈问题的"修复" | 环境属系统层；以 HUD 观测 + 文档应对（mpv#15196 教训） |
| 大规模重构渲染环/队列架构 | 沿用 v1"小改动大收益"原则；8K 修复限定在选项包推导层 |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| REBASE-01 | Phase 7 | Complete |
| REBASE-02 | Phase 7 | Complete (4K re-verify env-blocked, documented) |
| HUD-01 | Phase 8 | Pending |
| HUD-02 | Phase 8 | Pending |
| DND-01 | Phase 8 | Pending |
| UHD-01 | Phase 9 | Pending |
| UHD-02 | Phase 9 | Pending |
| COMP-01 | Phase 10 | Pending |
| COMP-02 | Phase 11 | Pending |
| COMP-03 | Phase 11 | Pending |

**Coverage:** v2 requirements 10/10 mapped; unmapped 0。

---
*Requirements defined: 2026-10-24 (milestone v2.0, research-driven)*

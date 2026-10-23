# Requirements: mpv_kit

**Defined:** 2026-10-23
**Core Value:** 以尽可能小的源码改动，换取可验证的稳定性与 4K/8K UHD 长时间满帧播放能力——不崩溃、不泄漏、不积压。

## v1 Requirements

本里程碑的提交范围。每条都保持公共 API 不变，并可在六个桌面目标（Windows/Linux/macOS × x64/arm64）上验证。

### Stability & Lifetime (STAB)

- [x] **STAB-01**: 反复创建/销毁 `Player` 与 `MpvVideoController` 不泄漏原生资源，`events`/状态流正确关闭
- [x] **STAB-02**: 任一 dispose hook 抛错时 `Player.dispose()` 仍完成 `mpv` 核心销毁，且可重复调用
- [x] **STAB-03**: `Mpv` 公共方法在 dispose 后调用抛出明确 `StateError`，不触发 native use-after-free
- [ ] **STAB-04**: `MpvVideoController.create` 解析失败或后续步骤抛错时回滚纹理、dispose hook 与路由表，重试可成功
- [ ] **STAB-05**: resize 与 dispose 并发时无崩溃、无黑帧、无尺寸状态卡死

### Observability (OBS)

- [ ] **OBS-01**: 流源 open/read/seek 失败经 `Player.errors` 暴露，并保留原始异常信息
- [ ] **OBS-02**: 属性观察失败进入 `Player.errors`，不产生未捕获异步错误
- [ ] **OBS-03**: Vulkan→software 回退与 D3D11 设备失败给出可读 `reason` 与对应事件
- [ ] **OBS-04**: 不支持的选项或拼写错误不再完全静默（保持向后兼容地记录或暴露）

### Performance (PERF)

- [ ] **PERF-01**: 每个属性事件只解码一次 `mpv_node`（消除 `time-pos` 热路径的重复解码）
- [ ] **PERF-02**: 存在可重复运行的基准（`delayed`、`avdiff`、掉帧、create/dispose 循环、resize）
- [ ] **PERF-03**: 4K/8K UHD 连续播放 30 分钟无帧积压（`delayed≈0`、`avdiff` 有界）
- [ ] **PERF-04**: 减少事件/状态热路径分配，且不改变公共 API

### Build & Provenance (BUILD)

- [ ] **BUILD-01**: 补丁单一来源，CI 能检测 vendor 树与 `native/patches/` 的漂移
- [ ] **BUILD-02**: 六个桌面目标的 bundle 可由当前树可复现重建，并通过 sha256/MANIFEST 校验
- [ ] **BUILD-03**: 文档与版本一致（vendor commit、macOS 部署目标、SDK 约束）
- [ ] **BUILD-04**: 仓库卫生（`bt/` 不再跟踪、`pubspec.lock` 策略明确）

### Cross-platform Verification (VERIFY)

- [ ] **VERIFY-01**: 真实插件 integration test 在 Windows/Linux/macOS CI 跑通（create、渲染一帧、dispose）
- [ ] **VERIFY-02**: 六目标（x64/arm64 × 三 OS）构建与冒烟全部通过
- [x] **VERIFY-03**: 关键失败路径有回归测试（失败注入、抛错监听器/dispose hook、异常流源）
- [ ] **VERIFY-04**: 覆盖率门禁覆盖 `mpv_kit_video` 与 `mpv_kit_libs`

## v2 Requirements

Deferred to a future milestone. Tracked but not in the current roadmap.

### Playback Features

- **FEAT-01**: 渲染桥向 mpv 回报 vsync/显示相位，使 `video-sync=display-*` 可用
- **FEAT-02**: HDR swapchain 提示与正确的 tone-map 路径
- **FEAT-03**: 播放列表、字幕与音轨的更高层 API

### Renderer Compatibility

- **GPU-01**: Vulkan 1.2 设备（NVIDIA Maxwell/Pascal 如 GTX 960、AMD GCN 如 Polaris/Vega）可用 gpu-next 渲染，不再因 `apiVersion < 1.3` 门槛直接落到 software
- **GPU-02**: 设备能力协商可诊断——`PickDevice` 按所需扩展 + timeline semaphore 选择，失败原因包含设备名与缺失项；`vkCreateDevice` 失败时以最小 feature 集重试
- **GPU-03**: 在旧 GPU 上验证 `gpu-next → gpu(gl_video Vulkan context) → software` 的真实回退链，并记录各档的 `backend`/`reason`

### Platform

- **PLAT-01**: Android 垂直切片（libmpv 交叉编译 + Flutter 纹理）
- **PLAT-02**: iOS 可行性评估与 ADR

## Out of Scope

Explicitly excluded from this milestone. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| 新增或破坏性公共 API | 本里程碑 API 冻结，降低回归面 |
| 版本发布、CHANGELOG、pub 发布流程 | 用户明确不着急，专注源码健康度 |
| 大规模渲染架构重写 | 违反"小改动大收益"原则，只做有数据支撑的局部优化 |
| Android/iOS/web 支持 | 渲染互操作与 bundle 目标均未覆盖，非当前目标 |

## Traceability

Which phases cover which requirements. Populated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| STAB-01 | Phase 1 | Complete |
| STAB-02 | Phase 1 | Complete |
| STAB-03 | Phase 1 | Complete |
| STAB-04 | Phase 2 | Pending |
| STAB-05 | Phase 2 | Pending |
| OBS-01 | Phase 3 | Pending |
| OBS-02 | Phase 3 | Pending |
| OBS-03 | Phase 3 | Pending |
| OBS-04 | Phase 3 | Pending |
| PERF-01 | Phase 4 | Pending |
| PERF-02 | Phase 4 | Pending |
| PERF-03 | Phase 4 | Pending |
| PERF-04 | Phase 4 | Pending |
| BUILD-01 | Phase 5 | Pending |
| BUILD-02 | Phase 5 | Pending |
| BUILD-03 | Phase 5 | Pending |
| BUILD-04 | Phase 5 | Pending |
| VERIFY-01 | Phase 6 | Pending |
| VERIFY-02 | Phase 6 | Pending |
| VERIFY-03 | Phase 1 | Complete |
| VERIFY-04 | Phase 2 | Pending |

**Coverage:**
- v1 requirements: 21 total
- Mapped to phases: 21
- Unmapped: 0

---
*Requirements defined: 2026-10-23*
*Last updated: 2026-10-23 after roadmap creation (traceability filled)*

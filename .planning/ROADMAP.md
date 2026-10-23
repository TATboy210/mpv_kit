# Roadmap: mpv_kit

## Overview

本里程碑只做现有源码的稳定性与性能优化，公共 API 冻结。路线按技术域推进：先把 `Player` 与 `MpvVideoController` 的生命周期修到可反复 create/dispose 而不泄漏、不崩溃；再让原本被静默吞掉的失败可见；然后用可重复基准驱动热路径优化并验证 4K/8K UHD 长时播放；接着收敛补丁/bundle/文档的单一事实来源；最后用真实插件 integration test 与六目标矩阵把这些保证固化在 CI 上。每个阶段都包含可独立回滚的小改动，且每阶段自带验证手段。

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Player Lifetime & Dispose Safety** - 反复创建销毁不泄漏，dispose 异常安全，dispose 后调用明确报错
- [ ] **Phase 2: Video Controller Lifecycle & Resize Safety** - create 失败可回滚，resize/dispose 并发不崩溃，覆盖率门禁覆盖插件
- [ ] **Phase 3: Error Surfacing** - 流源、属性观察、渲染回退与选项错误不再静默
- [ ] **Phase 4: Measured Performance & UHD Endurance** - 属性事件单次解码，基准可重复，4K/8K 长播无积压
- [ ] **Phase 5: Build Provenance & Repository Hygiene** - 补丁/版本/bundle 单一来源，仓库卫生可执行
- [ ] **Phase 6: Cross-Platform Verification** - 真实插件 integration test 与六目标矩阵在 CI 常态运行

## Phase Details

### Phase 1: Player Lifetime & Dispose Safety

**Goal**: `Player` 在反复创建/销毁与异常 teardown 下都不泄漏、不崩溃，dispose 之后的调用可预测地失败。
**Depends on**: Nothing (first phase)
**Requirements**: STAB-01, STAB-02, STAB-03, VERIFY-03
**Success Criteria** (what must be TRUE):
  1. 连续创建并销毁 `Player`（≥1000 次）后，`position`、`decodeWarning` 等所有状态流都收到 `done`，native 句柄与进程内存保持平稳（无单调增长）。
  2. 任一 dispose hook 抛错时，`Player.dispose()` 仍完成 `mpv_terminate_destroy` 并关闭全部流，且错误可见；再次调用 dispose 无副作用。
  3. dispose 后调用任意 `Mpv` 公共方法抛出 `StateError`，测试同时证明没有进入 native 调用（无 use-after-free）。
  4. 失败注入回归测试进入 CI：抛错的 dispose hook/listener 与异常流源都能稳定复现并通过。

**Plans:** 1/3 plans executed

Plans:
**Wave 1**
- [x] 01-01-PLAN.md — Exception-safe `Player.dispose`, state/event stream closure, and dispose ordering

**Wave 2** *(blocked on Wave 1 completion)*
- [ ] 01-02-PLAN.md — Post-dispose `StateError` guard on every public `Mpv` method

**Wave 3** *(blocked on Wave 2 completion)*
- [ ] 01-03-PLAN.md — Failure-injection suite, 1000-cycle soak, and CI wiring

### Phase 2: Video Controller Lifecycle & Resize Safety

**Goal**: `MpvVideoController` 的创建是原子的，resize 与 dispose 并发时不崩溃、不残留坏状态。
**Depends on**: Phase 1
**Requirements**: STAB-04, STAB-05, VERIFY-04
**Success Criteria** (what must be TRUE):
  1. `create` 在平台返回畸形/缺字段或后续步骤抛错时，回滚 texture、dispose hook 与路由表，随后重试 create 成功。
  2. 畸形平台响应抛 `PlatformException`，而不是 `TypeError` 或空值崩溃。
  3. resize 与 dispose 交错执行（≥100 轮）无崩溃、无尺寸状态卡死；重新创建控制器后首帧不是黑帧。
  4. CI 对 `mpv_kit_video` 与 `mpv_kit_libs` 收集覆盖率并执行门禁，低于阈值即失败。

**Plans**: TBD

### Phase 3: Error Surfacing

**Goal**: 失败不再被静默吞掉——流源、属性观察、渲染回退与选项错误都可观测，并保留原始信息。
**Depends on**: Phase 2
**Requirements**: OBS-01, OBS-02, OBS-03, OBS-04
**Success Criteria** (what must be TRUE):
  1. 流源 open/read/seek 失败出现在 `Player.errors`，保留原始异常类型与消息，播放侧以明确错误结束。
  2. 属性观察失败或解析失败出现在 `Player.errors`，测试中不再出现未捕获异步错误。
  3. Vulkan→software 回退与 D3D11 设备创建失败产生带可读 `reason` 的事件（Windows/Linux/macOS）。
  4. 不支持的选项或拼写错误会被记录/暴露，同时 create 保持向后兼容（不抛错）。

**Plans**: TBD

### Phase 4: Measured Performance & UHD Endurance

**Goal**: 用可重复基准量化热路径收益，并证明 4K/8K UHD 长时间播放没有帧积压。
**Depends on**: Phase 3
**Requirements**: PERF-01, PERF-02, PERF-03, PERF-04
**Success Criteria** (what must be TRUE):
  1. 可重复运行的基准存在，输出 `delayed`、`avdiff`、掉帧、create/dispose 循环与 resize 数据，并留下改动前的基线记录。
  2. 每个属性事件只解码一次 `mpv_node`（测试断言单次解码），`time-pos` 热路径有改动前后的分配/CPU 对比数据。
  3. 4K 与 8K 连续播放 30 分钟：`delayed≈0`、`avdiff` 有界、无帧积压。
  4. 公共 API 无变化（API diff 为空），事件/状态热路径分配下降且行为不变。

**Plans**: TBD

### Phase 5: Build Provenance & Repository Hygiene

**Goal**: 补丁、bundle 与文档只有一个事实来源，CI 能发现漂移。
**Depends on**: Phase 4
**Requirements**: BUILD-01, BUILD-02, BUILD-03, BUILD-04
**Success Criteria** (what must be TRUE):
  1. CI 在干净树上应用 `native/patches/0001..0007`，vendor 树与补丁不一致时任务失败。
  2. 六个桌面目标的 bundle 可由当前树重建，并通过 sha256/MANIFEST 校验。
  3. README、ADR 与版本常量同 `native/mpv/MPV_VERSION`、macOS 部署目标、SDK 下限一致，并有一致性检查。
  4. `bt/` 不再被跟踪（保留文档化的替代方式），`pubspec.lock` 策略明确并被执行。

**Plans**: TBD

### Phase 6: Cross-Platform Verification

**Goal**: 真实插件路径与六目标矩阵在 CI 中真实运行，而不是被 skip。
**Depends on**: Phase 5
**Requirements**: VERIFY-01, VERIFY-02
**Success Criteria** (what must be TRUE):
  1. 真实插件 integration test（create → 渲染一帧 → dispose）在有真实 libmpv 的 Windows/Linux/macOS CI runner 上执行并通过，不再 skip。
  2. 六目标矩阵（Windows/Linux/macOS × x64/arm64）构建与冒烟全部通过，受支持目标没有 `continue-on-error`。
  3. 集成测试失败会阻断合并，且因缺少 libmpv 而跳过的测试改为显式失败或真实运行。

**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5 → 6

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Player Lifetime & Dispose Safety | 1/3 | In Progress | - |
| 2. Video Controller Lifecycle & Resize Safety | 0/TBD | Not started | - |
| 3. Error Surfacing | 0/TBD | Not started | - |
| 4. Measured Performance & UHD Endurance | 0/TBD | Not started | - |
| 5. Build Provenance & Repository Hygiene | 0/TBD | Not started | - |
| 6. Cross-Platform Verification | 0/TBD | Not started | - |

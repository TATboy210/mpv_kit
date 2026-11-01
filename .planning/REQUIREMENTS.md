# Requirements: mpv_kit

**Defined:** 2026-11-01
**Milestone:** v3.1 依赖内存、体积与 API 优化（0.1.0-dev.5）
**Core Value:** 以尽可能小的源码改动，换取可验证的稳定性与 4K/8K UHD 长时间满帧播放能力——不崩溃、不泄漏、不积压。

**里程碑约束：**
- 不改 `mpv_kit_video` 原生渲染代码与渲染生命周期。
- 不改 Windows shaderc/SPIRV-Cross/D3D11、libplacebo 图形选项、MoltenVK 与 Vulkan loader。
- 保留 FFmpeg 网络协议；不禁用 decoder/demuxer/BSF；不使用 `-Os`/`--enable-small`。
- 公共 API 只增不破。
- MEM-* 每一项都必须先由 BASE-* 的测量证实问题存在才实施；未被证实的项标记为 `not-confirmed` 并关闭，不改代码。

## v3.1 Requirements

### Baseline（只测量，不改产品代码）

- [ ] **BASE-01**: 维护者能看到 dev.4 六个目标 bundle 的逐库体积明细（解包与压缩），以及 FFmpeg 等库是否仍含可剥离符号/段的检查结果
- [ ] **BASE-02**: 维护者能看到 4K 与 8K 本地播放各 30 分钟的 RSS/commit 曲线，以及 `demuxer-donate-buffer=no` 与软件解码 `vd-lavc-threads` 取不同值时的对照数据
- [ ] **BASE-03**: 维护者能看到 60 秒播放期间 `videoParams`/`audioParams`/`trackList` 等状态的发射次数与重复值比例
- [ ] **BASE-04**: 维护者能看到上游 mpv 泄漏修复（#16619、#17737、#16260 等）在 vendored 树中是否已包含，以及 `bindings.dart` 中是否有触发这些泄漏的调用路径
- [ ] **BASE-05**: `BASELINE.md` 对每个候选问题给出 confirmed / not-confirmed 结论，作为后续阶段的准入依据

### Memory（Dart 层与默认选项，不触碰渲染）

- [ ] **MEM-01**: `MpvVideoParams`、`MpvAudioParams`、`MpvTrack`、播放列表与章节模型具备值相等语义，`MpvState` 对等值列表不再重复发射（需 BASE-03 证实）
- [ ] **MEM-02**: 软件解码且分辨率超过 4K 时，`Player` 自动限制 `vd-lavc-threads`；用户显式设置过该值则不再干预（需 BASE-02 证实）
- [ ] **MEM-03**: UHD-01 的 demuxer 预算把 `demuxer-donate-buffer` 纳入计算，8K 播放的 commit 峰值低于基线（需 BASE-02 证实）
- [ ] **MEM-04**: 基线核对出缺失的上游 mpv 泄漏修复，以 verbatim backport 补丁加入 `native/patches/`，`UPSTREAM.md` 同步更新，PATCH-DRIFT 通过（需 BASE-04 证实）

### Size（构建与分发，不改图形后端选项）

- [ ] **SIZE-01**: `package.sh` 对 bundle 闭包内所有库统一 strip（macOS 在 codesign 之前）；meson/cmake 依赖与 FFmpeg 启用 LTO，Linux 加 `--gc-sections`；smoke 测试与 UHD 基准无性能回退
- [ ] **SIZE-02**: mpv 构建显式设置 `-Dcplugins=disabled` 与 `-Dbuild-date=false`；发布归档改用 `gzip -9`，hook 仍能校验并解压
- [ ] **SIZE-03**: 构建钩子安装新 bundle tag 成功后，删除共享缓存中其他 tag 的目录，并有对应测试
- [ ] **SIZE-04**: dev.5 每个目标的解包与压缩体积不大于 dev.4，体积对比写入 `docs/perf/`

### API（只增不破）

- [ ] **API-01**: 应用能通过 `Player.demuxerCacheState` 懒观测 demuxer 缓存状态（`fwBytes`、`totalBytes`、`cacheEnd`、`seekableRanges`、`rawInputRate`），不访问时不注册 observer
- [ ] **API-02**: 应用能在构造 `Player` 时用 `autoTuneDemuxer: false` 关闭 UHD-01 自动调参；默认值为 `true`，行为不变
- [ ] **API-03**: 应用能通过 `Player.eventQueueOverflows` 流获知 mpv 客户端事件队列溢出
- [ ] **API-04**: 所有新增 API 都有 `///` 文档、单元测试、真实 libmpv 测试和 CHANGELOG 条目；现有公共签名零变化

### Release

- [ ] **REL-01**: 三个包与 example 的版本及依赖约束更新为 `0.1.0-dev.5`，CHANGELOG 记录本里程碑改动
- [ ] **REL-02**: 用户批准后发布 GitHub Release `v0.1.0-dev.5`（六个 LGPL bundle），用 `tools/pin_bundles.dart` 把 `bundles.dart` 钉到 dev.5，托管 CI 全绿
- [ ] **REL-03**: 用户批准后将三个包的 0.1.0-dev.5 发布到 pub.dev，消费者路径验证通过

## Future Requirements

- **SIZE-F1**: FFmpeg `--disable-filters` 加 mpv 实际依赖的 filter 白名单（风险最高，本里程碑未选；需完整格式矩阵覆盖后再议）
- **SIZE-F2**: 在仅本地播放的前提下禁用网络协议和 Linux OpenSSL（用户决定保留网络）
- **MEM-F1**: 8K 7680x4320 × 30 分钟门禁（UHD-02，延续自 v2.0）

## Out of Scope

| 项目 | 原因 |
|------|------|
| mpv_kit_video 原生渲染代码、渲染生命周期 | 用户明确要求保持不变 |
| 移除 Windows shaderc/SPIRV-Cross（约 10 MiB） | 属于 D3D11 图形后端依赖，用户决定保持不变 |
| `-Os` / `--enable-small` | 可能影响 4K/8K 满帧解码性能 |
| 禁用 decoder/demuxer/BSF | 损害本地播放格式覆盖；部分 decoder 依赖 BSF |
| 禁用 libavdevice/lavfi | 测试依赖 `av://lavfi` 测试源 |
| 破坏性 API 变更 | 只增不破 |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| (filled by roadmap) | | |

**Coverage:**
- v3.1 requirements: 20 total
- Mapped to phases: 0（等待 roadmap）

---
*Requirements defined: 2026-11-01*
*Last updated: 2026-11-01 after initial definition*

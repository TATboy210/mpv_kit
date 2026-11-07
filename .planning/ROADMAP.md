# Roadmap: mpv_kit

## Milestones

- ✅ **v1.0 Driver-Stability Baseline** — Phases 1-6 (archived 2026-10-24; 21/21 requirements delivered)
- ✅ **v2.0 GPU-Next Optimization & Full-Rate UHD** — Phases 7-11 (closed 2026-10-25; 6/10 requirements delivered, 4 deferred)
- ✅ **v3.0 统一渲染生命周期与平台原生图形后端** — Phases 12-17.1 (shipped 2026-10-31; 29/31 requirements delivered; GitHub Release v0.1.0-dev.4, pub.dev 0.1.0-dev.4)
- ⛔ **v3.1 依赖内存、体积与 API 优化** — Phases 18-22（**已被 v0.1.1 取代，2026-11-07；不执行**；保留为历史）
- ✅ **v0.1.1 简化与低内存** — Phases P0-P5 (shipped 2026-11-07; GitHub Release `v0.1.1`; pub.dev 0.1.1; 详见 `.planning/v0.1.1/PLAN.md`)

## ✅ v0.1.1 简化与低内存（已发布 2026-11-07）

**Milestone Goal:** 在不破坏现有公共 API 与零拷贝渲染路径的前提下，先测量、后删除/合并冗余，降低 1080p 运行内存与 bundle 体积，发布 0.1.1。

**Hard gate:** example 应用 + 本地 1080p + 默认硬解 + 稳定播放 10 分钟的 Windows Working Set **必须 < 250 MB**；超标不发布。

**Phases:**
- **P0 基线与测量** — 只测量：example 1080p Working Set 构成、事件重复率、六目标 bundle 体积（产品代码 diff = 0）
- **P1 前端去冗** — 模型值相等/去重、昂贵状态懒观察、内部重复分配清理
- **P2 后端等价简化** — release 剔除诊断探针、合并重复实现；仅按 P0 证据调整帧环
- **P3 构建体积** — Linux/macOS strip 复核、LTO/gc-sections、六目标 ≤ dev.10
- **P4 API/文档/CHANGELOG** — 零新增 API，记录 250 MB 结果与已知风险
- **P5 发布 0.1.1** — 发布前一次 CI、GitHub Release + pin、pub.dev（逐次批准）

**Canonical plan:** `.planning/v0.1.1/PLAN.md`

**Closeout:** 1080p example Working Set 294.1 → 234.0 MiB (gate 250); Linux bundles −6.5/−6.8 MiB, macOS −0.47 MiB; PR 17/17; tag release run `42353713357`; pin commit `55f2556`.

## Phases

<details>
<summary>✅ v1.0 Driver-Stability Baseline (Phases 1-6) — ARCHIVED 2026-10-24</summary>

Phase details, success criteria and verification records live in
`.planning/milestones/v1-phases/`.

</details>

<details>
<summary>✅ v2.0 GPU-Next Optimization & Full-Rate UHD (Phases 7-11) — CLOSED 2026-10-25</summary>

Closed by user decision as a simple close-out: incomplete phases were recorded
as not delivered rather than driven to green. Delivery is partial and is stated
as such below — no phase was rewritten to look complete.

- [x] Phase 7: mpv-master Vendor Advance & gpu-next Regression (2/2 plans) — completed 2026-10-24
- [x] Phase 8: Debug HUD & Drag-and-Drop (1/1 plan) — completed 2026-10-25
- [ ] Phase 9: 8K Full-Rate (1/2 plans) — UHD-01 delivered (frame-size-derived demuxer budgets + runtime auto-tune); UHD-02 unproven (8K survived 60 s with all v1 gates green, but no 30-minute run)
- [ ] Phase 10: Composition Spike (6/9 plans) — REA report 03 and ADR 0003 landed; ADR verdict stays `inconclusive`, D-05 never exercised; 10-08/10-09 not executed, 10-06 (ADR final verdict) never written
- [ ] Phase 11: Native Composition Path (0 plans) — not started; COMP-02/COMP-03 deferred

Full phase details: `.planning/milestones/v2.0-ROADMAP.md`
Requirements archive: `.planning/milestones/v2.0-REQUIREMENTS.md`

</details>

<details>
<summary>✅ v3.0 统一渲染生命周期与平台原生图形后端 (Phases 12-17.1) — SHIPPED 2026-10-31</summary>

Closeout type `override_closeout`: every phase completed and passed its
verifier; five reports later went stale when follow-up commits touched covered
files and were not re-run (user decision). D3D-08 was not switched (user kept
Vulkan first on Windows) and HWD-03 has no real Linux GPU evidence.

- [x] Phase 12: RenderBackend Seam (12/12 plans) — completed 2026-10-27
- [x] Phase 13: macOS Metal Route Decision (6/6 plans) — completed 2026-10-28
- [x] Phase 14: Windows Native D3D11 Backend (11/11 plans) — completed 2026-10-29 (D3D-08 not switched)
- [x] Phase 15: Linux OpenGL Backend (7/7 plans) — completed 2026-10-28
- [x] Phase 16: Hardware-Decode Zero-Copy (6/6 plans) — completed 2026-10-29
- [x] Phase 17: Fallback Hardening & UHD Regression (5/5 plans) — completed 2026-10-30
- [x] Phase 17.1: Release and pin a libmpv bundle with the D3D11 and OpenGL backends (INSERTED, 7/7 plans) — completed 2026-10-31

Full phase details: `.planning/milestones/v3.0-ROADMAP.md`
Requirements archive: `.planning/milestones/v3.0-REQUIREMENTS.md`
Milestone audit: `.planning/milestones/v3.0-MILESTONE-AUDIT.md`
Phase directories: `.planning/milestones/v3.0-phases/`; quick tasks: `.planning/milestones/v3.0-quick/`

</details>

## ⛔ v3.1 依赖内存、体积与 API 优化（已被 v0.1.1 取代，2026-11-07）

> **SUPERSEDED — do not execute.** v0.1.1 取代本里程碑；保留此节仅作历史参考。当前计划见 `.planning/v0.1.1/PLAN.md`。

**Milestone Goal:** 在渲染生命周期与平台原生图形后端代码不变的前提下，先测量验证、再降低依赖栈（libmpv / FFmpeg / libplacebo 等）的运行内存与 bundle 体积，并以只增不破方式补充依赖功能 API，发布 0.1.0-dev.5。

**概览：** 先测量、后修复。Phase 18 只产出数据与结论（`BASELINE.md`），不改任何产品代码；Phase 19 的每一项内存优化都以 Phase 18 的 confirmed 结论为准入，not-confirmed 的项关闭且不改代码。Phase 20（构建体积）与 Phase 21（依赖功能 API）各自只依赖 Phase 18，彼此以及与 Phase 19 都没有依赖关系。Phase 22 在 19–21 全部完成后发布，且每个对外发布动作都要用户逐次明确批准。

**里程碑约束（对每个阶段都成立）：**
- 不改 `mpv_kit_video` 原生渲染代码与渲染生命周期；不改 Windows shaderc / SPIRV-Cross / D3D11、libplacebo 图形选项、MoltenVK 与 Vulkan loader。
- 保留 FFmpeg 网络协议；不禁用 decoder / demuxer / BSF；不使用 `-Os` / `--enable-small`；不禁用 libavdevice / lavfi。
- 公共 API 只增不破；LGPL-only 的 bundle 不变（`pe_audit.py --forbid-gpl` 与 `--forbid-angle` 继续为绿）。
- FFmpeg filter 白名单是 `SIZE-F1`（Future），**不在本里程碑**。

**验证分层：**
- **本机 Windows x64（RTX 4060）** 是唯一真机：4K/8K 内存曲线（RSS / commit）与 UHD 回归只能在这里证明；Linux / macOS 真机不可用，相关内存数据须如实写成「未测量」，不得推断。
- **体积与符号检查**对下载的 dev.4 release 资产与 dev.5 候选构件做静态分析，不需要目标机器。
- **hosted CI**（native-verify、sanitizers、flutter-plugin、release.yml 的 `workflow_dispatch` 构建）证明构建、smoke 测试、覆盖率门禁与 ABI 审计；mock channel 不能替代真实插件行为。

**Phase Numbering:** 接续 v3.0（止于 Phase 17.1），v3.1 从 Phase 18 开始；小数阶段（如 19.1）为计划后的紧急插入。

- [ ] **Phase 18: 基线与问题验证** - 只测量：dev.4 逐库体积、4K/8K 内存曲线、Dart 重复发射、上游泄漏修复核对，产出 `BASELINE.md` 的 confirmed / not-confirmed 结论
- [ ] **Phase 19: Dart 层内存优化** - 仅对被基线证实的问题做最小改动：模型值相等去重、软件解码线程上限、donate-buffer 纳入预算、缺失上游修复 backport
- [ ] **Phase 20: 构建体积优化** - 统一 strip、LTO / gc-sections、mpv 显式选项、`gzip -9`、hook 旧 tag 缓存清理；每个目标体积不大于 dev.4
- [ ] **Phase 21: 依赖功能 API 增补** - `Player.demuxerCacheState`、`autoTuneDemuxer` 开关、`Player.eventQueueOverflows`，只增不破
- [ ] **Phase 22: 发布 0.1.0-dev.5** - 版本与 CHANGELOG、GitHub Release 与 bundle pin、pub.dev 发布，每个对外动作需用户明确批准

**执行顺序：** 18 → {19, 20, 21} → 22。19、20、21 之间没有依赖。19 与 21 都会改 `player.dart` / `models.dart`，且 API-02 的开关包住 MEM-03 改动的 `_autoTuneDemuxer`，串行时先 19 后 21 以避免冲突；20 只动构建脚本与 hook，与 Dart 代码没有文件重叠，可在任意位置。22 需要 19–21 全部完成。

### Phase 18: 基线与问题验证

**Goal**: 在改动任何依赖构建或 Dart 层之前，维护者手里已有 dev.4 的体积、内存与事件重复发射的实测数据和上游泄漏修复核对结果，并且每个候选问题都有 confirmed / not-confirmed 结论，作为后续阶段的准入依据。
**Depends on**: Nothing（v3.1 首个阶段；基于 v3.0 收尾时的代码树与 dev.4 release 资产）
**Requirements**: BASE-01, BASE-02, BASE-03, BASE-04, BASE-05
**Success Criteria** (what must be TRUE):
  1. 维护者在 `BASELINE.md` 里能看到 dev.4 六个目标 bundle 的逐库体积表（解包 MiB 与压缩 MiB），以及对 FFmpeg 等库是否仍带 `.symtab` / 可剥离段的检查结论。
  2. 4K 与 8K 本地播放各 30 分钟的 RSS / commit 曲线已落盘 `docs/perf/`，并附 `demuxer-donate-buffer=no` 与软件解码 `vd-lavc-threads` 默认值 / 8 的对照数据；任何因环境无法测量的项明确写成「未测量」及原因，不用推测填空。
  3. 维护者能看到 60 秒播放期间 `videoParams`、`audioParams`、`trackList` 等状态的发射次数与重复值比例（数字，不是印象）；所用测量脚本是一次性的，不进入产品代码。
  4. 对 mpv #16619、#17737、#16260 等上游泄漏修复，`BASELINE.md` 逐项写明在 vendored 树中「已包含 / 缺失」，以及 `bindings.dart` 里是否存在会触发该泄漏的调用路径（例如以 NULL result 调用 `mpv_command_node`）。
  5. `BASELINE.md` 对 MEM-01..04 对应的每个候选问题（值相等去重、`vd-lavc-threads`、`demuxer-donate-buffer`、上游 backport）都给出 confirmed / not-confirmed 结论并指向证据；无法测量的项记为 not-confirmed（原因：未测量）。本阶段 diff 不含 `packages/*/lib`、`native/patches/`、构建脚本或 workflow 的产品改动。

**验证分层**: 本机 Windows x64 跑 4K/8K 30 分钟曲线与对照；体积与符号检查静态对 dev.4 release 资产进行；上游核对在 `native/mpv/` 与 `bindings.dart` 上用源码检索完成。
**阶段注意**:
  - 既往 4K/8K 30 分钟数据（`docs/perf/2026-10-24-uhd-endurance.md`）用的是 lavfi 合成源，原始帧直接进入 demuxer 队列、不经解码器；`vd-lavc-threads` 对照因此需要真实编码样本，取样与测量方法留给 plan-phase 决定。
  - 本阶段的 8K 30 分钟只是基线数据采集，没有通过 / 失败门禁，不等于关闭 `MEM-F1`（UHD-02 的 8K 门禁，Future）。
  - 压缩体积的归档只在 `release.yml` 的 `publish` job（仅 tag 触发）里生成；基线用 dev.4 release 资产自身的压缩大小。
**Plans**: TBD

### Phase 19: Dart 层内存优化

**Goal**: 只对 `BASELINE.md` 标为 confirmed 的内存问题做最小改动，使 Dart 层不再重复发射等值状态、超 4K 软件解码与 8K 的 demuxer 预算受控、缺失的上游泄漏修复以 verbatim 补丁带入；not-confirmed 的项关闭且零代码改动。
**Depends on**: Phase 18（每一项都以其基线结论为准入）
**Requirements**: MEM-01, MEM-02, MEM-03, MEM-04
**Success Criteria** (what must be TRUE):
  1. 每个 MEM 项的实施或关闭都对应 `BASELINE.md` 的结论：confirmed 的项有改动与验证；not-confirmed 的项在阶段验证里明确记为「已关闭、未改代码」，仓库里不留半成品；本阶段 diff 不触碰 `mpv_kit_video` 的原生渲染代码。
  2. （MEM-01，若 confirmed）应用监听 `videoParams`、`audioParams`、`trackList`、播放列表、章节时，等值更新不再产生第二次发射；用 Phase 18 同一 60 秒测量脚本重跑，重复发射比例相对基线明显下降；模型的 `==` / `hashCode` / `toString` 有单元测试，API-freeze 反射测试仍绿。
  3. （MEM-02，若 confirmed）软件解码且分辨率超过 4K 时，`Player` 把 `vd-lavc-threads` 限制到基线选定的值，RSS 低于基线对照；4K 及以下、硬件解码、或用户显式设置过该值时不干预，三种情形各有测试。
  4. （MEM-03，若 confirmed）UHD-01 的 demuxer 预算把 `demuxer-donate-buffer` 计入，8K 播放的 commit 峰值低于 Phase 18 基线，对比写入 `docs/perf/`；预算公式矩阵的单元测试覆盖这一项。
  5. （MEM-04，若有缺失）缺失的上游泄漏修复以 verbatim backport 补丁进入 `native/patches/`，`UPSTREAM.md` 同步更新，PATCH-DRIFT 门禁（`tools/check_patches.sh`）通过；若基线显示均已包含，则记录为已关闭、不新增补丁。

**验证分层**: `dart test`（`packages/mpv_kit`）与 CI 覆盖率门禁（不低于 80%）；`lifecycle` 测试（`-t lifecycle --run-skipped`）；本机 Windows x64 重跑 Phase 18 的 4K/8K 对照；补丁改动另走 native-verify 与 sanitizers。
**Plans**: TBD

### Phase 20: 构建体积优化

**Goal**: dev.5 候选 bundle 在六个目标上的解包与压缩体积都不大于 dev.4，同时图形后端依赖、网络协议与 decoder / demuxer / BSF 不变；hook 的本地缓存不再无限堆积旧 tag。
**Depends on**: Phase 18（用其 dev.4 体积基线与 strip 检查结论作为对比与准入）
**Requirements**: SIZE-01, SIZE-02, SIZE-03, SIZE-04
**Success Criteria** (what must be TRUE):
  1. dev.5 候选 bundle（`release.yml` 的 `workflow_dispatch` 构建，不打 tag）闭包内的所有库都已 strip（macOS 在 codesign 之前），用 Phase 18 同一检查重跑不再发现可剥离符号；启用 LTO（Linux 另加 `--gc-sections`）后，smoke 测试与 4K UHD 基准相对基线无性能回退。
  2. 构建配置里显式出现 `-Dcplugins=disabled` 与 `-Dbuild-date=false`；发布归档改用 `gzip -9`，`mpv_kit_libs` 的 hook 仍能校验 sha256 并解压该归档（有测试）。
  3. 安装新 bundle tag 成功后，共享缓存里其他 tag 的目录被删除，仅保留当前 tag；安装失败时不删除旧缓存；有对应的 `bundle_test.dart` 测试。
  4. 六个目标每个的解包与压缩体积均不大于 dev.4，对比表写入 `docs/perf/`；`pe_audit.py --forbid-gpl` / `--forbid-angle`、全部 Dart 测试、`format_matrix_test` 与 native `meson test` 保持绿；Windows shaderc / SPIRV-Cross、libplacebo 图形选项、MoltenVK 的构建配置 diff 为空。

**验证分层**: hosted CI 构建六个目标的候选构件并跑 smoke / ABI 审计；压缩体积用与 `publish` job 相同的归档命令对候选构件打包得到（`publish` job 仅 tag 触发，不为量体积而打 tag）；UHD 性能无回退在本机 Windows x64 上复核。
**阶段注意**: 每一项改动独立提交、单独测量收益、可单独回滚；LTO 若造成性能回退或构建不稳，该项回退而不拖累其他项。
**Plans**: TBD

### Phase 21: 依赖功能 API 增补

**Goal**: 应用能观测 demuxer 缓存状态、能关闭 UHD-01 自动调参、能获知 mpv 客户端事件队列溢出，且所有现有公共签名零变化。
**Depends on**: Phase 18（基线完成后再动产品代码；与 Phase 19/20 没有依赖关系，文件上与 19 有重叠，见执行顺序）
**Requirements**: API-01, API-02, API-03, API-04
**Success Criteria** (what must be TRUE):
  1. 应用读取 `Player.demuxerCacheState` 能得到 `fwBytes`、`totalBytes`、`cacheEnd`、`seekableRanges`、`rawInputRate`，真实 libmpv 播放时数值随缓存变化；从不访问它时，不会为它注册 mpv observer。
  2. 以 `Player(autoTuneDemuxer: false)` 构造时，UHD-01 不再修改 demuxer 选项；不传或传 `true` 时行为与 dev.4 逐项一致（既有 UHD-01 测试不改动即通过）。
  3. 订阅 `Player.eventQueueOverflows` 的应用，在真实 libmpv 的客户端事件队列溢出时收到通知；没有订阅者时溢出不报错、不泄漏。
  4. 每个新增公共符号都有 `///` 文档、单元测试、真实 libmpv 测试与 CHANGELOG 条目；API-freeze 反射测试对既有签名零变化（只多出新增条目），新增类型从 barrel 导出。

**验证分层**: `dart test`（`packages/mpv_kit`，含真实 libmpv 测试）与 CI 覆盖率门禁（不低于 80%）；真实 libmpv 测试须在 CI runner 上跑，mock 不能替代。
**Plans**: TBD

### Phase 22: 发布 0.1.0-dev.5

**Goal**: 三个包以 0.1.0-dev.5 到达消费者：版本一致、LGPL bundle 发布并钉住、pub.dev 发布；每个对外发布动作先获用户明确批准。
**Depends on**: Phase 19, Phase 20, Phase 21
**Requirements**: REL-01, REL-02, REL-03
**Success Criteria** (what must be TRUE):
  1. 三个包与 example 的版本及互相依赖约束全部为 `0.1.0-dev.5`（`tools/check_consistency.dart` 通过），各包 CHANGELOG 覆盖本里程碑的改动（内存、体积、新增 API）。
  2. 用户明确批准后，GitHub Release `v0.1.0-dev.5` 含六个 LGPL bundle，`SHA256SUMS` 与归档、API digest 一致；`bundles.dart` 由 `tools/pin_bundles.dart` 钉到 dev.5（不手改生成数据）；pin 新鲜度检查与托管 CI（native-verify、flutter-plugin、macos-route）在钉后的 SHA 上全绿。
  3. 用户另行明确批准后，三个包的 0.1.0-dev.5 发布到 pub.dev（先 dry-run）；pub.dev 消费者路径验证通过：只依赖已发布的包，构建时取回并校验钉住的 dev.5 bundle。
  4. 未获批准的发布动作（打 tag、创建 Release、推送 pin、`pub publish`）一个都没有发生；每次批准都有记录。

**发布门禁**: 批准本路线图不等于批准任何发布。tag 只打在经托管 CI 全绿的候选上并需用户明确 go；pin 推送与 pub.dev 发布各自需要单独确认。顺序是 REL-01 → REL-02 → REL-03：pub 发布的源码必须已含钉到 dev.5 的 `bundles.dart`，否则 pub 消费者取不到 dev.5 bundle，所以 pin 提交先于 pub 发布。
**Plans**: TBD

## Progress

**Execution Order:**
18 → {19, 20, 21} → 22（小数阶段按数值顺序插入其间）

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 18. 基线与问题验证 | v3.1 | 0/TBD | Not started | - |
| 19. Dart 层内存优化 | v3.1 | 0/TBD | Not started | - |
| 20. 构建体积优化 | v3.1 | 0/TBD | Not started | - |
| 21. 依赖功能 API 增补 | v3.1 | 0/TBD | Not started | - |
| 22. 发布 0.1.0-dev.5 | v3.1 | 0/TBD | Not started | - |

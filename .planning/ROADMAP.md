# Roadmap: mpv_kit

## Milestones

- ✅ **v1.0 Driver-Stability Baseline** — Phases 1-6 (archived 2026-10-24; 21/21 requirements delivered)
- ✅ **v2.0 GPU-Next Optimization & Full-Rate UHD** — Phases 7-11 (closed 2026-10-25; 6/10 requirements delivered, 4 deferred)
- 🚧 **v3.0 统一渲染生命周期与平台原生图形后端** — Phases 12-17 (in progress, started 2026-10-26; 0/31 requirements delivered)

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

## 🚧 v3.0 统一渲染生命周期与平台原生图形后端

**Milestone Goal:** 把渲染链路收敛到统一的 `RenderBackend` 生命周期接口；各平台使用适合自身生态的图形后端，并尽量做到硬件解码零拷贝；Flutter 只需拿到可采样纹理、可靠的帧通知与确定的资源释放。

> **硬约束（用户原话）：** Windows 不做 ANGLE 路线，读 media_kit 的渲染代码但是不能用 ANGLE，绝对不能用。
>
> 范围是 mpv_kit 自己的渲染链路与 bundle。Phase 14 的 D3D-02 把它固化为 CI 门禁：`pe_audit.py` 发现任何 bundle DLL 导入 `libEGL.dll`/`libGLESv2.dll` 或引用 `eglGetPlatformDisplayEXT` 即失败。门禁落地后，之后每个阶段都必须保持它为绿。Flutter 引擎内部用 ANGLE 消费我们的 DXGI 句柄不在控制范围内（ADR 0003），也不能拿来当作缩小隔离期或省掉生产端 fence 的理由。

**概览：** 研究驱动（`.planning/research/SUMMARY.md`）。先在现有 Vulkan 路径上取基线，并用 fake libmpv golden 测试锁住 `VideoRenderer` 状态机，再把 Vulkan 与软件后端纯搬迁到 `RenderBackend` 之后（Phase 12，后续每个阶段的独立回滚点）。macOS 路线以 ADR 先定案（13）。Windows D3D11（14）与 Linux OpenGL（15）是两个互不重叠的新后端，可以并行。硬件解码零拷贝在后端就绪后单独处理，把托管 CI 无法证明的部分隔离出来（16）。最后用故障注入、强制后端的 CI 矩阵与 UHD 长时门禁收口（17）。auto 回退顺序一律「渲染器质量优先、图形 API 其次」；公共 API 冻结，真实后端只经私有 wire 名与 `reason` 上报；每个新后端都是候选列表里的一项，删掉这一项即可回滚。

**验证分层（全里程碑通用）：**
- **hosted CI** 只能证明渲染路径：Windows runner 无 GPU，Flutter 适配器为 WARP；Linux 为 xvfb + Mesa llvmpipe/lavapipe；macOS 为 Apple Silicon VM（Metal 经 MoltenVK）。这些任务一律 `hwdec=no`，加非黑像素探针。
- **本机 RTX 4060（Windows x64）** 是唯一真机：硬解零拷贝、性能对照、4K 30 分钟与 D-05 基线只能在这里证明。
- **无硬件可用：** Linux GPU（NVIDIA/AMD/Intel）与 macOS 真机。相关结论必须写成「未验证」，不得写成通过。

**Phase Numbering:** 接续 v2.0（止于 Phase 11），v3.0 从 Phase 12 开始；小数阶段（如 14.1）为计划后的紧急插入。

- [x] **Phase 12: RenderBackend Seam** - 基线先行的纯重构：Vulkan/软件后端迁到统一生命周期接口，行为逐项不变 (completed 2026-10-27)
- [ ] **Phase 13: macOS Metal Route Decision** - ADR 定案 MoltenVK→IOSurface 路线，如实上报 Metal 承载，验证 VideoToolbox 零拷贝
- [ ] **Phase 14: Windows Native D3D11 Backend** - 上游 D3D11 render API + gpu-next D3D11 分支，链路无 ANGLE/EGL 并由 CI 门禁固化
- [ ] **Phase 15: Linux OpenGL Backend** - 上游 OpenGL render API + 独立 EGL context + EGLImage 导出，作为 Vulkan gpu-next 之后的档位
- [ ] **Phase 16: Hardware-Decode Zero-Copy** - 跨后端 hwdec 默认列表、d3d11va 真零拷贝、vaapi DRM display，每个测试断言是否零拷贝
- [ ] **Phase 17: Fallback Hardening & UHD Regression** - 故障注入、强制后端 CI 矩阵、硬解守卫，以及每个后端的 4K 30 分钟与 100 轮 soak

**执行顺序：** 12 → {13, 14, 15} → 16 → 17。13 体量小，可以先做；14 与 15 没有文件重叠，可以并行（串行时 14 在前：未知最多，也是唯一有真机验证的平台）；16 需要 13/14/15 的后端就绪；17 收口。

### Phase 12: RenderBackend Seam

**Goal**: 现有 Vulkan 与软件渲染运行在统一的 `RenderBackend` 生命周期之后，行为与重构前基线逐项一致；之后任何平台后端都只需新增一个候选项即可接入或回滚。
**Depends on**: Nothing（v3.0 首个阶段；基于 v2.0 收尾时的代码树）
**Requirements**: RBE-01, RBE-02, RBE-03, RBE-04, RBE-05, RBE-06, RBE-07, RBE-08
**Success Criteria** (what must be TRUE):
  1. 第一个搬迁提交之前，soak harness（`example/integration_test/impeller_smoke_test.dart`）已修好，并在当前 Vulkan 路径上跑出基线、落盘 `docs/perf/`。10-04 已修 part-1 的 setSize 门与 BENCH 通道；这里要修的是 v2.0 仍悬空的两处：part 2 像素探针读到 `nonBlackRatio: 0.0`（1266x683 表面）的原因，以及 10-05 soak 窗口中止。基线包括：D-05 30 s、100 轮 resize/dispose、100 次 create/dispose，Impeller 开/关各一组，每组带引擎 renderer 行；若 D-05 中止复现，按数据记录，不重跑到绿。
  2. 基于 fake libmpv（`MpvApi` 函数表）的 `VideoRenderer` golden 测试在任何代码搬迁前先通过，并在每个搬迁提交后不改一行继续通过，覆盖回退、退避 100 ms→5 s、隔离期轮转、retire-on-resize 与发布门控。
  3. Vulkan 与软件后端经 `RenderBackend`（Create / AllocTargets / FrameFor / Render / Wait / BindThread·UnbindThread / Release / Destroy）运行，`FrameReady` 留在平台侧；搬迁 diff 中没有任何常量（ring 5/7、quarantine 2/4、50 ms present 超时、退避）或 reason 字符串改动；`render_vk_smoke`（gpu-next 与 gpu）、Phase 2/3 套件与三平台真实插件测试全绿；RTX 4060 上 4K 30 分钟与 Phase 4 基线持平，用同一 harness 重跑基线不出现新失败。
  4. 调试断言证明 `report_swap` 与 `mpv_render_context_free` 只在渲染线程（后端 context 已绑定）上执行，光栅线程不再调用；所有后端共用同一延迟释放契约（Flutter 注销完成且出隔离期后才释放纹理），create/dispose 与 resize/dispose soak 中无光栅线程崩溃，sanitizer 任务下的 golden 测试无 use-after-free。
  5. Dart 侧严格校验私有 wire 名 `d3d11`/`opengl`/`vulkan`/`software`（其他值仍抛 `PlatformException(code: render_init)`），公共 `MpvVideoBackend` 枚举与 API-freeze 反射测试不变；`reason` 符合 `<api> (<renderer>) on <device>[; <api>/<renderer> unavailable: <why>]*`，该决定写入 ADR；设置原生环境变量 `MPV_KIT_VIDEO_API=vulkan|software` 时只尝试该 API，不新增任何 Dart 公共 API。

**验证分层**: hosted CI — golden 测试（三平台 + sanitizer 任务）、`render_vk_smoke`、三平台真实插件 integration test、API-freeze 与 wire 校验测试；RTX 4060 — D-05 基线（Impeller 开/关，固定 3.47.8 SDK）与 4K 30 分钟对照 Phase 4 基线。
**Research**: 标准模式（研究已完整映射代码），无需阶段研究。
**Plans:** 12/12 plans complete（9 waves）

Plans:
**Wave 1**
- [x] 12-01-PLAN.md — 推送授权检查点 + 恢复 hosted CI 验证层（pin 检查路径、hook-bundle 定位；integration-test 首跑）+ `ci_gate.sh`
- [x] 12-02-PLAN.md — soak harness 修复：探针三方对照、resize-front 复现器、100 次 create/dispose 段、真正渲染的 4K 变体

**Wave 2** *(blocked on Wave 1 completion)*
- [x] 12-03-PLAN.md — Dart 私有 wire 名严格校验 + 枚举冻结守卫 + ADR 0004（reason 语法、MPV_KIT_VIDEO_API）+ README
- [x] 12-04-PLAN.md — RTX 4060 重构前基线（D-05 / cycles / resize-front × Impeller 开关）+ 人工确认
- [x] 12-05-PLAN.md — fake-libmpv golden 工装 + 软件路径 golden（三平台 + sanitizer）

**Wave 3** *(blocked on Wave 2 completion)*
- [x] 12-06-PLAN.md — 原生 reason 语法（先于搬迁）

**Wave 4** *(blocked on Wave 3 completion)*
- [x] 12-07-PLAN.md — Vulkan 路径 golden + AllocateRing 退役槽双重销毁先红后绿修复 + golden 冻结

**Wave 5** *(blocked on Wave 4 completion)*
- [x] 12-08-PLAN.md — RTX 4060 修复后、搬迁前参照 + 人工确认

**Wave 6** *(blocked on Wave 5 completion)*
- [x] 12-09-PLAN.md — RenderBackend 纯搬迁（SoftwareBackend → VulkanRenderBackend → 候选链数据化）

**Wave 7** *(blocked on Wave 6 completion)*
- [x] 12-10-PLAN.md — 插件 wire_name 出口 + 原生 MPV_KIT_VIDEO_API 严格开关

**Wave 8** *(blocked on Wave 7 completion)*
- [x] 12-11-PLAN.md — report_swap / render_context_free 渲染线程亲和性 + 释放契约文档 + 真实插件 soak 段

**Wave 9** *(blocked on Wave 8 completion)*
- [x] 12-12-PLAN.md — 收口：最终 CI 全量门与审计、RTX 4060 4K 30 分钟与 harness 对照 + 人工确认

### Phase 13: macOS Metal Route Decision

**Goal**: macOS 的 Metal 承载路线由 ADR 定案；现有 MoltenVK→IOSurface 路径以 `RenderBackend` 形式运行并如实上报；VideoToolbox 零拷贝要么得到验证，要么留下不可达的证据。
**Depends on**: Phase 12（需要 `RenderBackend` 与 reason 语法）
**Requirements**: MAC-01, MAC-02, HWD-04
**Success Criteria** (what must be TRUE):
  1. ADR 比较 MoltenVK→IOSurface、CGL+IOSurface、自写 Metal 后端三条路线（成本、可用渲染器 gpu-next/gpu、弃用风险），给出决定，并写明重新评估的触发条件（例如 libplacebo 合入 Metal `pl_gpu`）。
  2. macOS runner 上真实插件测试经 `RenderBackend` 通过，非黑像素探针结果与 Phase 12 之前一致，`reason` 标明实际 Metal 承载（形如 `vulkan (gpu-next) on <device> via MoltenVK`）。
  3. VideoToolbox 在 MoltenVK 路径上：`hwdec-current=videotoolbox` 且无 copy-back，8-bit 与 P010/10-bit 样本都没有绿帧或黑帧；如果托管 VM 无法硬解，验证记录写出具体的不可达证据并标为未验证，不写成通过。

**验证分层**: hosted macOS runner（Apple Silicon VM，Metal 可用）证明渲染路径与 reason；VideoToolbox 在 VM 内能否硬解未经证实，项目也没有本地 macOS 硬件，HWD-04 允许以证据收口；RTX 4060 不涉及。
**Research**: 标准模式（三条路线已在研究中比较），无需阶段研究。
**Plans:** 6/6 plans executed（5 waves）

Plans:
**Wave 1**
- [x] 13-01-PLAN.md — 推送授权检查点 + macOS reason 写出实际承载驱动（`via MoltenVK`）+ Phase 13 CI 门
- [x] 13-02-PLAN.md — ADR 0005（`Status: proposed`）三路线比较与决定（逐格来源记录、重新评估触发条件）+ ADR 0004 的 `via <carrier>` 语法补充

**Wave 2** *(blocked on Wave 1 completion)*
- [x] 13-03-PLAN.md — `macos-route` workflow：真实插件像素探针（toImage + 插件 IOSurface 诊断探针两个通道），HEAD 与 Phase 12 之前插件（3a5f450）同条件一致性判定，输出 SC2 结论行

**Wave 3** *(blocked on Wave 2 completion)*
- [x] 13-04-PLAN.md — VideoToolbox 零拷贝探针：H.264 8-bit、HEVC 8-bit、HEVC 10-bit（P010）对照软件解码，带证据的结论

**Wave 4** *(blocked on Wave 3 completion)*
- [x] 13-05-PLAN.md — 验证记录、ADR 0005 验证节、最终 HEAD 全量门与阶段审计

**Wave 5** *(blocked on Wave 4 completion)*
- [x] 13-06-PLAN.md — 用户决策检查点（路线、HWD-04 分类、SC2 像素结论）；仅在 accept 后 ADR 0005 改为 accepted

### Phase 14: Windows Native D3D11 Backend

**Goal**: Windows 上 mpv 通过上游 D3D11 render API 直接渲染进 mpv_kit 自有 `ID3D11Device` 的共享纹理（gpu-next 与 gpu 两档），mpv_kit 自身链路全程不经 ANGLE/EGL；失败时按 auto 链回退并如实上报。
**Depends on**: Phase 12（与 Phase 15 互相独立，可并行）
**Requirements**: D3D-01, D3D-02, D3D-03, D3D-04, D3D-05, D3D-06, D3D-07, D3D-08
**Success Criteria** (what must be TRUE):
  1. Windows bundle 含 SPIRV-Cross（共享 DLL，列入 MANIFEST、ABI 审计与许可证）与 shaderc，libplacebo 与 mpv 以 `-Dd3d11` 构建且 `config.h` 中 `HAVE_D3D11` 生效，许可证门禁仍为 LGPL-only；ANGLE/EGL/WGL-GL 构建选项全部显式关闭，`pe_audit.py` 新规则对导入 `libEGL.dll`/`libGLESv2.dll` 或引用 `eglGetPlatformDisplayEXT` 的 bundle DLL 让 CI 失败，并用一个故意注入的违规样本证明这条规则会变红。
  2. `0010-upstream-d3d11-render-api.patch` 与上游 PR #17764 的 ABI 逐字节一致（params 21/22、client API 2.6），兼容 0001/0004 的 `done_frame` bool 签名，PATCH-DRIFT 门禁绿；0004 的 gpu-next D3D11 分支（`ra_d3d11` 与 `pl_d3d11` 共用设备、`pl_d3d11_wrap` 宿主纹理）与 0003 覆盖 DXBC 的持久 shader cache 生效（第二次启动命中缓存）；`render_d3d11_smoke` 在 windows runner（WARP）上 gpu 与 gpu-next 两种变体都渲染出非黑像素。
  3. `MPV_KIT_VIDEO_API=d3d11` 时，windows runner（WARP）与 RTX 4060 上的真实插件测试都渲染出非黑帧，`reason` 为 `d3d11 (gpu-next) on <adapter>`；设备建在 Flutter 适配器 LUID 上（`BGRA_SUPPORT|VIDEO_SUPPORT`、多线程保护、非 SINGLETHREADED），KMT `MISC_SHARED` 纹理环经 `GpuSurfaceTexture` 交付，每帧在 `ID3D11Fence`（回落 `D3D11_QUERY_EVENT`）完成后才发布；resize 不换 texture id、不闪黑；隔离期保持 4，Impeller 开/关下的消费延迟只测量、不重新参数化（COMP-03 仍延后）。
  4. 注入 D3D11 设备移除时 Dart 收到 `device_lost` 事件且进程不崩溃；D3D11 创建失败时自动落到 Vulkan，`reason` 写明 `d3d11/<renderer> unavailable: <why>`。
  5. Windows auto 链改为 d3d11/gpu-next → vulkan/gpu-next → d3d11/gpu → vulkan/gpu → software，以独立、可单独回滚的提交落地，且只在 CI 与 RTX 4060 均绿之后合入；`MPV_KIT_VIDEO_API=vulkan` 仍能强制旧路径，结果与 Phase 12 基线一致。

**阶段内顺序**: 构建与 ANGLE 禁令门禁（D3D-01/02）→ 0010 backport + 0004 gpu-next D3D11 分支 + smoke（D3D-03/04/05）→ `D3D11Backend` 与设备丢失/回退（D3D-06/07）→ auto 链切换提交（D3D-08）。构建计划必须先于渲染计划。
**验证分层**: hosted windows runner（无 GPU，Flutter 适配器为 WARP）证明构建、PE 审计、PATCH-DRIFT、两种 smoke 变体与强制 d3d11 的真实插件测试；RTX 4060 证明真实适配器上的渲染与性能，并作为 auto 链切换的前提。
**Research**: 需要阶段研究（`/gsd-plan-phase 14 --research-phase`）：shaderc 能否基于固定的 glslang 16.6.0 构建、MSYS2 CLANGARM64 上的 shaderc/SPIRV-Cross、WARP 上的 `ID3D11Device5` fence 与 `VIDEO_SUPPORT`、BGRA8 typed UAV、0004 与 0010 的 hunk 冲突、D3D11 最大 2D 纹理尺寸（查微软资源限制，不凭记忆）。（用户选择跳过阶段研究直接规划：这些未知项已写成 14-01 / 14-04 / 14-05 的实测 spike 任务，结论门控后续任务。）
**Plans:** 8/11 plans executed（10 waves）

Plans:
**Wave 1**
- [x] 14-01-PLAN.md — 推送授权检查点（feat 只推绿 + `ci/14-` scratch）+ 参数化 `ci_gate.sh` + D3D11 能力探针（RTX 4060 / WARP / hosted runner 实测 fence、VIDEO_SUPPORT、typed UAV、纹理上限）

**Wave 2** *(blocked on Wave 1 completion)*
- [x] 14-02-PLAN.md — PickDevice reason 拆分（独立提交）+ 与 Phase 12 golden 冻结冲突的用户裁决
- [x] 14-03-PLAN.md — ANGLE/EGL 禁令：`pe_audit.py --forbid-angle` + 合成违规样本 + 三处 CI 接入 + build.sh 显式关闭（D3D-02）

**Wave 3** *(blocked on Wave 2 completion)*
- [x] 14-04-PLAN.md — Windows bundle：SPIRV-Cross + shaderc（glslang 16.6.0 / CLANGARM64 实测）+ libplacebo/mpv `-Dd3d11` + 回补对 + bundle 组成裁决（D3D-01）

**Wave 4** *(blocked on Wave 3 completion)*
- [x] 14-05-PLAN.md — `0010-upstream-d3d11-render-api.patch`（上游 4 提交 backport，ABI 逐字节比对，done_frame bool）+ PATCH-DRIFT（D3D-03）

**Wave 5** *(blocked on Wave 4 completion)*
- [x] 14-06-PLAN.md — `render_d3d11_smoke`（gpu / gpu-next / cache，WARP）+ 0004 gpu-next D3D11 分支 + DXBC 持久缓存 + 打包 bundle 冒烟（D3D-04/05）

**Wave 6** *(blocked on Wave 5 completion)*
- [x] 14-07-PLAN.md — `D3D11Backend`（Flutter 适配器、KMT 纹理环、fence/query 发布门控）+ 切换前候选链 + 强制 d3d11 真实插件测试 + 取帧延迟测量（D3D-06）

**Wave 7** *(blocked on Wave 6 completion)*
- [x] 14-08-PLAN.md — 设备移除 → `device_lost`、创建失败 → 带原因回退：调试注入 + 真实插件测试 + chain golden（D3D-07）

**Wave 8** *(blocked on Wave 7 completion)*
- [ ] 14-09-PLAN.md — RTX 4060：强制 d3d11 功能、4K 600 s 对照 Phase 12、Impeller 开/关 D-05 与取帧延迟 + `docs/perf/d3d11-backend.md`

**Wave 9** *(blocked on Wave 8 completion)*
- [ ] 14-10-PLAN.md — GTX 960 + 核显笔记本验收：桌面 Release 演示包 + 用户人工验证（4K60 经 d3d11，绝不 software）

**Wave 10** *(blocked on Wave 9 completion)*
- [ ] 14-11-PLAN.md — auto 链切换决策检查点 + 独立切换提交（scratch CI 与 RTX 4060 先绿）+ 收口审计 + scratch 清理（D3D-08）

### Phase 15: Linux OpenGL Backend

**Goal**: Linux 上 mpv 经上游 OpenGL render API 在渲染线程的独立 EGL context 中渲染，画面经独立导出纹理与 `EGLImage` 交给 `FlTextureGL`，作为 Vulkan gpu-next 之后的渲染档位，并如实上报实际渲染器。
**Depends on**: Phase 12（与 Phase 14 互相独立，可并行）
**Requirements**: GLX-01, GLX-02, GLX-03, GLX-04
**Success Criteria** (what must be TRUE):
  1. Linux bundle 以 mpv `-Dgl -Degl -Dplain-gl` 构建（x11/wayland 仍关闭），使用上游 `MPV_RENDER_API_TYPE_OPENGL`，系统库 allowlist 与 ABI 审计绿；`render_gl_smoke` 在 ubuntu runner（EGL surfaceless + llvmpipe）上渲染出非黑像素。
  2. `MPV_KIT_VIDEO_API=opengl` 时，ubuntu runner（xvfb + llvmpipe）上的真实插件测试渲染出非黑帧：mpv 渲染到私有纹理，再 blit 到独立导出纹理交给 `FlTextureGL`，`EGLSync` 完成后才发布；`populate` 回调内不发生 mpv 渲染；resize 不换 texture id。
  3. GL context 建在 Flutter 的 `EGLDisplay` 上、不加入 Flutter share group；渲染线程启动之后的所有 `mpv_render_*` 调用都在渲染线程上，create 期的调用（`mpv_render_context_create`、`_get_info`、首次 `_set_update_callback`）在 `RunBound` 的线程上，且两处 mpv 的 context 均为当前；create/dispose 与 resize/dispose soak 中没有 epoxy abort 或 `EGL_BAD_ACCESS`。（措辞经用户 2026-10-28 批准更新，sc3-interpretation=runbound）
  4. Linux auto 链为 vulkan/gpu-next → opengl/gpu → vulkan/gpu → software；由 vo_gpu 服务时 `reason` 写 `opengl (gpu) on <device>`，从不冒称 gpu-next；Vulkan 不可用时自动落到 GL，并在 `reason` 中写明原因。

**验证分层**: hosted ubuntu runner（xvfb + Mesa llvmpipe）证明全部渲染路径；项目没有 Linux GPU 硬件，NVIDIA/AMD/Intel 真驱动行为（包括 Mesa Xe2 的 EGLImage 黑帧问题）在验证记录中明确标为未验证；RTX 4060 不涉及。
**Research**: 需要阶段研究（`/gsd-plan-phase 15 --research-phase`）：Flutter 3.47 Linux 光栅线程身份、EGL 与 GLX 下的 `EGL_BAD_ACCESS`、FLIP_Y、隔离 context 用 GLES 还是桌面 GL。gpu-next over GL（patch 0011，GLX-F1）不在本阶段核心范围。用户选择跳过阶段研究直接规划：上述未知由 15-02（原生交接 spike）与 15-03（Flutter Linux spike）在早期取证，结论门控 15-05。
**Plans:** 7/7 plans executed（5 waves）

Plans:
**Wave 1**
- [x] 15-01-PLAN.md — 推送/dispatch 授权与 bundle 组成检查点 + Linux libmpv 打开 GL/EGL/plain-gl + render_gl_smoke 示踪（gl/gles）

**Wave 2** *(blocked on Wave 1 completion)*
- [x] 15-02-PLAN.md — 原生交接 spike（私有纹理 → blit → EGLImage → fence → 跨线程 GLES 2 导入、FLIP_Y、context API）+ release.yml 发布层证明
- [x] 15-03-PLAN.md — Flutter Linux spike：挂载纹理的像素/方向探针 + ProbeGl 第二控制器失败诊断 + 3.47.8 嵌入层源码事实
- [x] 15-04-PLAN.md — Linux 链决策检查点 + `LinuxBackendCandidates` golden + `RenderBackend::RunBound` 接缝（本地先红后绿）

**Wave 3** *(blocked on Wave 2 completion)*
- [x] 15-05-PLAN.md — OpenGLBackend 示踪（强制 opengl 真实插件）+ 链接入 + 硬断言探针

**Wave 4** *(blocked on Wave 3 completion)*
- [x] 15-06-PLAN.md — Vulkan 不可用时 auto 落到 OpenGL 的证明 + 探测移到新线程（第二控制器一致）

**Wave 5** *(blocked on Wave 4 completion)*
- [x] 15-07-PLAN.md — 文档、未验证清单、最终全量 CI 门与审计、需求到证据映射 + 阶段末人工检查

### Phase 16: Hardware-Decode Zero-Copy

**Goal**: 硬件解码在每个原生后端上优先走零拷贝，默认值不再静默选中 copy-back；每次测试都能说清当前是零拷贝、copy-back 还是软件解码。
**Depends on**: Phase 13, Phase 14, Phase 15（零拷贝依赖各后端的 `ra`；macOS 的结论来自 13）
**Requirements**: HWD-01, HWD-02, HWD-03, HWD-05
**Success Criteria** (what must be TRUE):
  1. `Player` 默认 hwdec 改为按平台扩展的跨后端有序列表，零拷贝候选在前（如 `vulkan,d3d11va,d3d11va-copy,auto-safe`），作为行为变更写入文档；测试证明用户显式设置的 `hwdec` 选项仍然优先。
  2. RTX 4060 + D3D11 后端：`hwdec-current=d3d11va`（不是 `d3d11va-copy`），4K HEVC 10-bit 样本播放画面正确，没有绿帧或黑帧。
  3. Linux 宿主向 mpv 传入 `MPV_RENDER_PARAM_DRM_DISPLAY_V2`（render node 与 EGL 设备匹配），GL 与 Vulkan gpu-next 后端都能加载 vaapi interop（日志可见）；没有 `/dev/dri` 的 runner 上安全回落到软件解码且不崩溃；真实 vaapi 零拷贝因无硬件标为未验证。
  4. 每个 soak/集成测试都输出并断言 `hwdec-current` 与零拷贝是/否；`hwdec=no` 的软件解码路径在 d3d11、opengl、vulkan、software 每个后端上都通过。

**验证分层**: hosted runner 没有硬件解码器（ubuntu 无 `/dev/dri`，WARP 无视频解码），只能证明回退、软件解码与断言接线；RTX 4060 证明 d3d11va 零拷贝；vaapi 无硬件，如实标为未验证；nvdec 明确延后（HWD-F1）。
**Research**: 需要阶段研究（`/gsd-plan-phase 16 --research-phase`）：混合 GPU 上的 vaapi render node 选择、P010 dma-buf modifier、Vulkan gpu-next 侧 vaapi 所需的 0004 native-resource 补充、`d3d11va-zero-copy` 的取舍（8K 门禁本身仍延后）。
**Plans**: TBD

### Phase 17: Fallback Hardening & UHD Regression

**Goal**: auto 回退的每一级都被强制演练过并留下带原因的事件；每个后端都在 CI 与 RTX 4060 上通过真实插件、硬解与 UHD 长时门禁。
**Depends on**: Phase 14, Phase 15, Phase 16
**Requirements**: VER-01, VER-02, VER-03, VER-04
**Success Criteria** (what must be TRUE):
  1. fake 后端故障注入（device lost、超时风暴、目标分配失败）时渲染切到 auto 链的下一候选，每次回退都发出带原因的事件；一路落到 software 时，`reason` 记录完整的回退链。
  2. 每个平台的 CI 矩阵用 `MPV_KIT_VIDEO_API` 强制每个可用后端（Windows d3d11/vulkan/software，Linux vulkan/opengl/software，macOS vulkan/software）跑真实插件 integration test，hosted runner 上 `hwdec=no` + 非黑像素探针全绿；D3D-02 的 ANGLE 禁令门禁仍在矩阵中且为绿。
  3. RTX 4060 上的硬解层在 `MPV_KIT_REQUIRE_HWDEC` 守卫下运行：没有可用硬解，或 `hwdec-current` 不是期望的零拷贝值时，测试响亮失败而不是静默 skip。
  4. RTX 4060 上 D3D11 与 Vulkan 后端各自 4K 30 分钟零丢帧、无积压；100 轮 resize/dispose soak 在 RTX 4060 的 d3d11/vulkan/software 后端上通过，专用显存曲线平稳、没有单调增长；opengl 后端的同一 soak 在 ubuntu runner（llvmpipe）上通过、进程内存平稳，由于没有 Linux GPU，真实显存曲线标为未验证。

**验证分层**: hosted CI 证明故障注入与强制后端矩阵；RTX 4060 证明硬解层与 UHD 长时门禁。8K 30 分钟（UHD-02）与合成延迟预算参数化（COMP-03）仍延后，不在本阶段验收。
**Research**: 标准模式，无需阶段研究。
**Plans**: TBD

## Progress

**Execution Order:**
12 → {13, 14, 15} → 16 → 17（14 与 15 可并行；串行时 14 在前）

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 12. RenderBackend Seam | v3.0 | 12/12 | Complete    | 2026-10-27 |
| 13. macOS Metal Route Decision | v3.0 | 6/6 | In Progress | - |
| 14. Windows Native D3D11 Backend | v3.0 | 8/11 | In Progress | - |
| 15. Linux OpenGL Backend | v3.0 | 7/7 | In Progress | - |
| 16. Hardware-Decode Zero-Copy | v3.0 | 0/TBD | Not started | - |
| 17. Fallback Hardening & UHD Regression | v3.0 | 0/TBD | Not started | - |

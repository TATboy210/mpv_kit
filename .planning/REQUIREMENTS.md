# Requirements: mpv_kit — v3.0 统一渲染生命周期与平台原生图形后端

**Defined:** 2026-10-26
**Core Value:** 以尽可能小的源码改动，换取可验证的稳定性与 4K/8K UHD 长时间满帧播放能力——不崩溃、不泄漏、不积压。

**硬约束（用户原话）：** Windows 不做 ANGLE 路线，读 media_kit 的渲染代码但是不能用 ANGLE，绝对不能用。
（范围：mpv_kit 自己的渲染链路与 bundle；Flutter 引擎内部用 ANGLE 消费 DXGI 句柄不在控制范围内，见 ADR 0003。）

**已定决策（2026-10-26）：** 后端上报保持 `MpvVideoBackend` 枚举不变、真实 API 写入 `reason`；上游 D3D11 render API 以 backport 补丁 0010 引入；auto 顺序按渲染器质量优先、图形 API 其次；打包 shaderc + 共享 SPIRV-Cross；Linux GL 用独立导出纹理 + blit；VA 显示用 `DRM_DISPLAY_V2`；gpu-next over GL（0011）不在核心范围；nvdec 明确延后；`Player` hwdec 默认值调整记为行为变更。详见 `.planning/research/SUMMARY.md`。

## v3.0 Requirements

### 渲染生命周期接口（RBE）

- [x] **RBE-01**: 重构前在现有 Vulkan 路径上修好 soak harness 并记录基线（D-05 30 s、100 轮 resize/dispose、100 次 create/dispose，Impeller 开/关，含 renderer 行），后续回归均与之对比
- [x] **RBE-02**: `VideoRenderer` 状态机有基于 fake libmpv（`MpvApi` 函数表）的 golden 测试，覆盖回退、退避、隔离期、retire-on-resize、发布门控，且在任何代码搬迁前先通过
- [x] **RBE-03**: 抽出 `RenderBackend` 接口（Create / AllocTargets / FrameFor / Render / Wait / BindThread·UnbindThread / Release / Destroy），帧环、隔离期、退避、swap、ICC、display-fps、事件留在通用引擎；`FrameReady` 留在平台侧
- [x] **RBE-04**: 现有 Vulkan 与软件后端迁移到该接口，搬迁提交不改任何常量（ring 5/7、quarantine 2/4、50 ms present 超时、100 ms→5 s 退避）与 reason 字符串，RTX 4060 4K 30 分钟与 Phase 4 基线持平
- [x] **RBE-05**: `report_swap` 与 `mpv_render_context_free` 只在渲染线程（且后端 context 已绑定）上调用，不再从光栅线程调用
- [x] **RBE-06**: 所有后端共享同一延迟释放契约：纹理在 Flutter 注销完成且出隔离期之后才释放，dispose 期间无 use-after-free
- [x] **RBE-07**: 后端上报：公共 `MpvVideoBackend` 枚举不变，私有 wire 名（d3d11/opengl/vulkan/software）严格校验，`reason` 采用 `<api> (<renderer>) on <device>[; <api>/<renderer> unavailable: <why>]*` 语法，ADR 记录该决定
- [x] **RBE-08**: 原生环境变量 `MPV_KIT_VIDEO_API` 可强制指定图形 API（供 CI 分别验证各后端），不新增 Dart 公共 API

### Windows 原生 D3D11（D3D）

- [x] **D3D-01**: Windows bundle 构建加入 SPIRV-Cross（共享 DLL，列入 MANIFEST/ABI 审计/许可证）与 shaderc，libplacebo 与 mpv 打开 `-Dd3d11`，`HAVE_D3D11` 生效，仍为 LGPL-only
- [x] **D3D-02**: 构建显式关闭全部 ANGLE/EGL/WGL-GL 选项，`pe_audit.py` 新规则：任何 bundle DLL 导入 `libEGL.dll`/`libGLESv2.dll` 或引用 `eglGetPlatformDisplayEXT` 即 CI 失败
- [x] **D3D-03**: 上游 D3D11 render API（PR #17764 的 4 个提交）以 `0010-upstream-d3d11-render-api.patch` 引入，ABI 与上游逐字节一致（params 21/22、client API 2.6），与 0001/0004 的 `done_frame` bool 签名兼容，PATCH-DRIFT 门禁绿
- [x] **D3D-04**: patch 0004 增加 gpu-next D3D11 分支（`ra_d3d11` + `pl_d3d11` 同一设备、`pl_d3d11_wrap` 宿主纹理），0003 持久化 shader cache 覆盖 DXBC
- [x] **D3D-05**: 新的 `render_d3d11_smoke` 原生测试在 windows runner（WARP）上渲染出非黑像素，gpu 与 gpu-next 两种变体
- [ ] **D3D-06**: `D3D11Backend`：每控制器独立 `ID3D11Device`（Flutter 适配器 LUID、`BGRA_SUPPORT|VIDEO_SUPPORT`、多线程保护、非 SINGLETHREADED），KMT `MISC_SHARED` 共享纹理环交给 `GpuSurfaceTexture`，渲染后 `ID3D11Fence`（回落 `D3D11_QUERY_EVENT`）完成后才发布，隔离期保持 4
- [x] **D3D-07**: D3D11 设备移除映射为 `device_lost` 事件；创建失败按 auto 链回退到 Vulkan 并在 `reason` 中说明
- [ ] **D3D-08**: Windows auto 链改为 d3d11/gpu-next → vulkan/gpu-next → d3d11/gpu → vulkan/gpu → software，作为独立提交，在 CI 与 RTX 4060 验证通过后落地

### Linux OpenGL（GLX）

- [x] **GLX-01**: Linux bundle 打开 mpv `-Dgl -Degl -Dplain-gl`（x11/wayland 仍关闭），使用上游 `MPV_RENDER_API_TYPE_OPENGL`
- [x] **GLX-02**: 新的 `render_gl_smoke` 原生测试在 ubuntu runner（EGL surfaceless + llvmpipe）上渲染出非黑像素
- [ ] **GLX-03**: `OpenGLBackend`：渲染线程上独立 EGL context（Flutter 的 `EGLDisplay`、不入 Flutter share group），mpv 渲染到私有纹理再 blit 到独立导出纹理，`EGLImage` 交给 `FlTextureGL`，`EGLSync` 完成后才发布；populate 回调内不渲染
- [ ] **GLX-04**: Linux auto 链为 vulkan/gpu-next → opengl/gpu → vulkan/gpu → software，`reason` 在 vo_gpu 服务时如实写 `gpu`

### macOS（MAC）

- [x] **MAC-01**: ADR 比较 MoltenVK→IOSurface / CGL+IOSurface / 自写 Metal 后端（成本、渲染器能力、弃用风险），给出决定与重新评估触发条件
- [x] **MAC-02**: macOS 路径以 `RenderBackend` 形式运行且行为不变，`reason` 标明实际 Metal 承载（如 `via MoltenVK`）

### 硬件解码零拷贝（HWD）

- [ ] **HWD-01**: `Player` 默认 hwdec 改为跨后端有序列表（零拷贝候选在前，如 `vulkan,d3d11va,d3d11va-copy,auto-safe` 按平台扩展），记为行为变更并文档化，用户 `hwdec` 选项仍优先
- [ ] **HWD-02**: Windows D3D11 后端下 d3d11va 真零拷贝：RTX 4060 上 `hwdec-current=d3d11va`（非 `-copy`），4K HEVC 10-bit 播放正确
- [ ] **HWD-03**: Linux 宿主向 mpv 传 `MPV_RENDER_PARAM_DRM_DISPLAY_V2`（与 EGL 设备匹配的 render node），GL 与 Vulkan gpu-next 后端均可加载 vaapi interop；无硬件处如实标为未验证
- [x] **HWD-04**: macOS VideoToolbox 在 MoltenVK 路径上零拷贝（含 P010/10-bit），或给出不可达的证据
- [ ] **HWD-05**: 每个 soak/集成测试记录并断言 `hwdec-current` 与零拷贝是/否，软件解码路径在每个后端上同样通过

### 回退与验证（VER）

- [ ] **VER-01**: fake 后端故障注入：device lost、超时风暴、目标分配失败时按 auto 链切到下一候选，每次回退都发出带原因的事件
- [ ] **VER-02**: CI 矩阵在每个平台用 `MPV_KIT_VIDEO_API` 强制每个可用后端跑真实插件 integration test（hosted runner：`hwdec=no` + 非黑像素探针）
- [ ] **VER-03**: 硬解层用 `MPV_KIT_REQUIRE_HWDEC` 守卫在 RTX 4060 上响亮失败而非静默 skip
- [ ] **VER-04**: D3D11 与 Vulkan 后端各自 4K 30 分钟零丢帧/无积压，以及每后端 100 轮 resize/dispose soak 且显存曲线平稳

## Future Requirements

- **GLX-F1**: gpu-next over GL（下游补丁 0011），让 Linux GL 真正排第一
- **HWD-F1**: nvdec（nv-codec-headers，LGPL 安全开关）与 CUDA–GL/GLES 互操作验证
- **RBE-F1**: device lost 后原地重建（当前为停止渲染 + 事件）
- **MAC-F1**: libplacebo 合入 Metal `pl_gpu` 后的原生 Metal 后端
- **Linux Vulkan 扩展**：在 GL 起步之后让 Linux 原生 Vulkan 与 GL 并列选择（现有 Vulkan 路径已可用，作为回退）
- v2.0 遗留：**UHD-02**（8K 30 分钟）、**COMP-02**（原生合成路径）、**COMP-03**（compositor 延迟预算参数化）——用户 2026-10-26 决定继续延后；D3D11 隔离期只测量、不重新参数化

## Out of Scope

| Feature | Reason |
|---------|--------|
| Windows ANGLE / EGL / WGL-GL 渲染路线 | 用户明确禁止（"绝对不能用"）；D3D-02 以 CI 门禁固化 |
| 自定义下游 `render_d3d11.h` ABI | 与上游 PR #17764 冲突，下次 rebase 必然撞车 |
| 新增 `MpvVideoBackend` 枚举值或其他公共 API | 公共 API 冻结；真实后端经 `reason` 上报 |
| macOS CGL 后端、`--wid` 窗口嵌入 | 已弃用 / 不符合 Flutter 纹理模型 |
| 在 Flutter 合成回调内渲染、resize 时重新注册纹理、全局单渲染线程 | 社区（media_kit/fvp）已证明的反模式 |
| copy-back hwdec 作为静默默认、`hwdec=auto-unsafe` | 违背零拷贝目标 / 稳定性风险 |
| GPL/nonfree 依赖（cuda-nvcc、libnpp 等） | LGPL-only 约束 |
| 移动端与 web | 项目范围外 |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| RBE-01 | Phase 12 | Complete |
| RBE-02 | Phase 12 | Complete |
| RBE-03 | Phase 12 | Complete |
| RBE-04 | Phase 12 | Complete |
| RBE-05 | Phase 12 | Complete |
| RBE-06 | Phase 12 | Complete |
| RBE-07 | Phase 12 | Complete |
| RBE-08 | Phase 12 | Complete |
| D3D-01 | Phase 14 | Complete |
| D3D-02 | Phase 14 | Complete |
| D3D-03 | Phase 14 | Complete |
| D3D-04 | Phase 14 | Complete |
| D3D-05 | Phase 14 | Complete |
| D3D-06 | Phase 14 | Pending |
| D3D-07 | Phase 14 | Complete |
| D3D-08 | Phase 14 | Pending |
| GLX-01 | Phase 15 | Complete |
| GLX-02 | Phase 15 | Complete |
| GLX-03 | Phase 15 | Pending |
| GLX-04 | Phase 15 | Pending |
| MAC-01 | Phase 13 | Complete |
| MAC-02 | Phase 13 | Complete |
| HWD-01 | Phase 16 | Pending |
| HWD-02 | Phase 16 | Pending |
| HWD-03 | Phase 16 | Pending |
| HWD-04 | Phase 13 | Complete |
| HWD-05 | Phase 16 | Pending |
| VER-01 | Phase 17 | Pending |
| VER-02 | Phase 17 | Pending |
| VER-03 | Phase 17 | Pending |
| VER-04 | Phase 17 | Pending |

**Coverage:**
- v3.0 requirements: 31 total
- Mapped to phases: 31
- Unmapped: 0 ✓
- 分布：Phase 12 = 8（RBE）· Phase 13 = 3（MAC-01/02、HWD-04）· Phase 14 = 8（D3D）· Phase 15 = 4（GLX）· Phase 16 = 4（HWD-01/02/03/05）· Phase 17 = 4（VER）

---
*Requirements defined: 2026-10-26*
*Last updated: 2026-10-26 after v3.0 roadmap creation (traceability filled)*

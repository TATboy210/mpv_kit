# Phase 16: Hardware-Decode Zero-Copy - Research

**Researched:** 2026-10-28
**Domain:** mpv hwdec 选择与 interop（d3d11va / vaapi / vulkan / videotoolbox）在 libmpv 渲染 API 三条后端（D3D11、OpenGL、Vulkan）上的零拷贝接线与测试断言
**Confidence:** MEDIUM（mpv 源码侧结论 HIGH，来自本仓库 vendored `native/mpv` 通读；真机与 Linux 驱动侧结论 LOW/ASSUMED，本阶段本来就无法在 hosted CI 证明）

<user_constraints>
## User Constraints (from CONTEXT.md)

本阶段没有 CONTEXT.md（`.planning/phases/16-hardware-decode-zero-copy/` 此前不存在；`config.json` 中 `workflow.research=false`，用户选择直接进入规划）。约束来自 ROADMAP.md Phase 16 与 REQUIREMENTS.md，按锁定决策处理：

### Locked Decisions
- Player 默认 hwdec 改为按平台扩展的跨后端有序列表，零拷贝候选在前，作为行为变更写入文档；用户显式 `hwdec` 仍优先（HWD-01、SC1）。
- RTX 4060 + D3D11 后端：`hwdec-current=d3d11va`（不是 `d3d11va-copy`），4K HEVC 10-bit 样本画面正确，无绿帧/黑帧（HWD-02、SC2）。
- Linux 宿主向 mpv 传 `MPV_RENDER_PARAM_DRM_DISPLAY_V2`，render node 与 EGL 设备匹配；GL 与 Vulkan gpu-next 后端都能加载 vaapi interop（日志可见）；无 `/dev/dri` 的 runner 安全回落软解不崩溃；真实 vaapi 零拷贝因无硬件标为未验证（HWD-03、SC3）。
- 每个 soak/集成测试输出并断言 `hwdec-current` 与零拷贝是/否；`hwdec=no` 软解路径在 d3d11、opengl、vulkan、software 每个后端都通过（HWD-05、SC4）。
- 公共 API 冻结（CLAUDE.md Constraints）；改动要小、可独立回滚；LGPL-only，禁止 GPL/nonfree 依赖进 bundle。
- 阶段验证分层：hosted runner 只证明回退、软解与断言接线；RTX 4060 证明 d3d11va 零拷贝；vaapi 无硬件如实标未验证。

### Claude's Discretion
- 各平台默认列表的具体顺序与措辞（SC1 只给了示例 `vulkan,d3d11va,d3d11va-copy,auto-safe`）。
- `d3d11va-zero-copy` 是否开启的取舍（ROADMAP Research 行点名要研究，8K 门禁本身延后）。
- Linux render node 的解析方式、native-resource 补丁的放置位置、断言助手的形状、plan 分波。

### Deferred Ideas (OUT OF SCOPE)
- HWD-F1：nvdec（nv-codec-headers）与 CUDA-GL/GLES 互操作。
- 8K 30 分钟（UHD-02）、合成延迟预算参数化（COMP-03）。
- GLX-F1：gpu-next over GL（补丁 0011）。HWD-04（macOS VideoToolbox）已在 Phase 13 完成，仅其"默认列表"遗留结论由本阶段接手。
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| HWD-01 | `Player` 默认 hwdec 跨后端有序列表，用户选项仍优先 | 第 1 节：mpv 的列表语义（缺 interop 的条目被跳过，`-copy` 与 `auto-safe` 才会 copy-back）；Player 默认值位于 `player.dart:101`；用户覆盖靠 `...options` 展开顺序 |
| HWD-02 | D3D11 后端 d3d11va 真零拷贝，RTX 4060 4K HEVC 10-bit | 第 2 节：同一 `ID3D11Device`、`d3d11va-zero-copy` 的两种含义、P010 格式表；`hwdec-current` 不区分 GPU copy 与解码表面直采 |
| HWD-03 | Linux 传 `MPV_RENDER_PARAM_DRM_DISPLAY_V2`，GL 与 Vulkan gpu-next 加载 vaapi interop | 第 3 节：`hwdec_vaapi.c:63-70` 只读 `render_fd`；`libmpv_gpu.c:32-91` 只给 `vo_gpu` 加 native resource，gpu-next 缺（需补 0004）；build.sh 现状已具备 `-Dvaapi -Ddrm`，`dmabuf_interop_gl` 不需要 `egl-drm` |
| HWD-05 | 每个 soak/集成测试记录并断言 `hwdec-current` 与零拷贝是/否，软解路径在每个后端通过 | 第 4 节：可用属性、零拷贝判定规则表、hosted 能证明的范围；现有测试几乎都用 lavfi 源，根本不会走 hwdec，必须加真实编码样本 |
</phase_requirements>

## Summary

本阶段的核心发现有四条，都来自通读 vendored mpv 源码与本仓库证据，而非假设。第一，mpv 的 `hwdec` 列表是"按序尝试"：非 copy 条目若在当前 ra 上没有 interop（没有注册 `hw_device`），会被跳过（`vd_lavc.c:590` 的 "Could not create device." 后 `continue`），不会静默 copy-back；真正会 copy-back 的是 `-copy` 条目（它们用独立设备，永远能创建，`vd_lavc.c:470-479`）与 `auto-safe`/`auto`（白名单里包含各 `-copy`，`vd_lavc.c:272-291`）。所以列表里零拷贝名字必须全部排在任何 `-copy` 之前。第二，Phase 13 记录的"macOS 默认列表选了软解"是测试脚手架的假象：default 行把字面串 `"[no]"`（Dart `List.toString()`）当成 hwdec 值传入，日志明文是 `Setting option 'hwdec' = '[no]'` 与 `Unsupported hwdec: [no]`（`.planning/phases/13-macos-metal-route-decision/evidence/route-runs.txt:34-36`），并没有测到 Player 的默认列表；HWD-01 的 macOS 列表需要用修正后的探针重测。第三，Vulkan gpu-next 的 libmpv 路径（补丁 0004，`vo_gpu_next.c:3142-3235`）从不注册 native resource，只有 `vo_gpu` 路径（`libmpv_gpu.c:80-91`）会；因此 HWD-03 的"Vulkan gpu-next 加载 vaapi interop"需要补 0004（约 15 行），否则 `create_drm_va_display` 取不到 `drm_params_v2`，vaapi 初始化必然失败。第四，`hwdec-current=d3d11va` 不能证明"没有拷贝"：默认 `d3d11va-zero-copy=no` 时 mpv 做一次 GPU-to-GPU 拷贝到着色器资源再采样（`hwdec_d3d11va.c:204-270`），仍属零 CPU 往返；`hwdec-current` 在两种模式下都是 `d3d11va`。要把"是否零拷贝"变成可断言的事实，必须把 `hwdec-current`、`video-params/pixelformat`（硬件帧为 `d3d11`/`vaapi`/`vulkan`/`videotoolbox`，拷回后为 `nv12` 等软格式）与 `options/d3d11va-zero-copy` 一起记录。

构建侧基本已就绪：Linux 的 `build.sh:32` 已开 `-Dvaapi=enabled -Ddrm=enabled`，`HAVE_VAAPI 1` 在发布 run 日志中可见；`dmabuf_interop_gl` 的编译条件是 `features['egl'] and drm.found()`（`meson.build:1543`），**不依赖** `egl-drm`，所以保持 `-Degl-drm=disabled` 即可；bundle 已 NEEDED `libva.so.2`/`libva-drm.so.2`/`libdrm.so.2`/`libEGL.so.1`（`15-.../evidence/release-runs.txt:22-26`），package.sh 的 system 白名单已覆盖它们，本阶段不新增系统库。Windows 的 `-Dd3d11=enabled` 已使 `hwdec_d3d11va.c` 编入（`meson.build:1466-1468`）。LGPL 约束无新增风险。

**Primary recommendation:** 分三层推进——Wave 0 先造"能说清零拷贝/拷回/软解"的断言助手并跑 hosted 探针（含修正后的 macOS default 行），Wave 1 做 Dart 默认列表与 0004 的 native-resource 补充，Wave 2 做 Linux render node 解析与 DRM_DISPLAY_V2 传递，RTX 4060 与真机项并入 Phase 14-09 的同一次硬件会话；默认列表与 `d3d11va-zero-copy` 默认值是用户检查点。

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| hwdec 默认列表（用户可覆盖） | Dart `Player`（`packages/mpv_kit`） | README/ADR 文档 | mpv 选项在 `mpv_initialize` 前由 `Player` 工厂注入；`...options` 最后展开保证用户优先（`player.dart:101-122`） |
| 零拷贝 interop 装载与选择 | libmpv（vd_lavc + `ra_hwdec`） | — | 全在 mpv 内部；宿主只提供 ra 与 native resource，不碰解码 |
| 同一 D3D11 设备供解码与渲染 | 原生插件 `D3D11Backend`（`d3d11_backend.cpp`） | mpv `hwdec_d3d11va` | 插件创建设备并带 `VIDEO_SUPPORT`、`SetMultithreadProtected(TRUE)`；mpv 在该设备上建 FFmpeg `D3D11VA` 设备 |
| DRM render node 解析与 fd 生命周期 | 原生插件（Linux，GlInterop/OpenGLBackend/VulkanContext） | mpv `hwdec_vaapi` | 只有宿主知道 Flutter 的 EGLDisplay/所选 Vulkan 物理设备；mpv 只消费 `render_fd` |
| native resource 注册（gpu-next 路径） | 补丁 0004（`vo_gpu_next.c` 的 `libmpv_init`） | `libmpv_gpu.c` 的映射表 | `vo_gpu` 路径已有；gpu-next 路径缺失 |
| "是否零拷贝"的可观测事实 | mpv 属性（`hwdec-current`、`video-params/*`、`hwdec-interop`） | 集成测试助手（Dart） | 属性是唯一权威；测试只做分类与断言 |
| 软解回退 | libmpv（`hwdec-software-fallback=3`） | `Player.decodeWarning` | 失败帧计数到 3 后换下一方法（`vd_lavc.c:174`、`1214-1215`） |
| 构建开关与 LGPL 门禁 | `native/build/build.sh`、`ffmpeg.sh`、`package.sh` | CI 的 ABI/许可审计 | 现状已具备，只需把 `VAAPI`/`DMABUF_INTEROP_GL` 加入必需特征检查 |

## Standard Stack

本阶段**不引入任何新外部包**（没有 npm/pip/pub 新依赖；Package Legitimacy Gate 不适用）。

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| mpv（vendored） | 0.41.0-1115 (`native/mpv`) [VERIFIED: native/patches/UPSTREAM.md:3] | hwdec 选择、interop、render API | 本项目既定基座，补丁以 provenance gate 管理 |
| FFmpeg | 8.1.3，LGPL，`--enable-vulkan`、Linux `--enable-vaapi`、Win `--enable-d3d11va --enable-dxva2`、mac `--enable-videotoolbox` [VERIFIED: native/build/ffmpeg.sh:9,44,49,86 and native/build/build.sh:28] | 实际硬件解码器 | 已固定 sha256，许可门禁在位 |
| libplacebo | 7.360.1 + 16 个回补 [VERIFIED: native/patches/UPSTREAM.md "libplacebo backports"] | gpu-next 渲染、`PL_HANDLE_DMA_BUF` 导入、`pl_d3d11_wrap` | 本项目既定 |
| `package:test` / `flutter_test` / `integration_test` | 既有 | Dart 单测与真实插件测试 | 既有测试栈 |
| meson test（`native/tests`） | 既有 | 原生冒烟（`render_gl_smoke`、`render_vk_smoke`、`render_d3d11_smoke`、golden） | 既有 |

### Supporting
| Tool | Purpose | When to Use |
|------|---------|-------------|
| `ffmpeg` CLI（仅用于生成样本） | 生成 h264/hevc 8/10-bit 样本（GPL 编码器只造测试媒体） | hosted 每平台一步 `Generate hwdec samples`（仿 `macos-route.yml:43-70`）；本机目前没有 ffmpeg（见 Environment Availability） |
| `gh` | 查 CI run | 既有流程 |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| 按平台一个静态列表 | 控制器在知道后端后再 `setProperty('hwdec', ...)` | 需要跟踪"用户是否显式设置过"，引入状态与竞态；而列表语义本身已能跳过无 interop 的条目，静态列表足够 |
| `Player` 里写平台分支（`dart:io Platform`） | 原生侧注入 | 原生侧注入要新增 wire/API，违反 API 冻结；`mpv_kit` 本身是纯 Dart FFI，已使用 `dart:io` |
| 补 0004 注册 native resource | 在 Dart 侧 `setProperty('vaapi-device')` | `vaapi-device` 只管 `vaapi-copy`（`options.rst:1623-1624`），对零拷贝 vaapi 无效 |

**Installation:** 无。
**Version verification:** 无新包；FFmpeg/libplacebo/mpv 版本取自仓库脚本与 UPSTREAM.md（已读）。

## Package Legitimacy Audit

本阶段不安装外部包：无需运行 `package-legitimacy check`。表格留空如下，供计划检查器识别。

| Package | Registry | Age | Downloads | Source Repo | Verdict | Disposition |
|---------|----------|-----|-----------|-------------|---------|-------------|
| （无） | — | — | — | — | — | — |

**Packages removed due to [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

## Architecture Patterns

### System Architecture Diagram

```
Player(options)                       Dart: 平台默认 hwdec 列表 + ...options（用户值最后，赢）
   │ mpv_initialize 前注入 hwdec / hwdec-codecs / hwdec-extra-frames
   ▼
mpv core ── vd_lavc.select_and_set_hwdec ── 逐项试 hwdec 列表 ─────────────────────┐
   │   非 copy 条目：hwdec_devices_get_by_imgfmt_and_type(...)                      │
   │      有 interop 注册的 device → 采用；没有 → "Could not create device." → 下一项│
   │   *-copy 条目：独立设备，总能建 → 采用（CPU 拷回，必须排在零拷贝之后）          │
   │   auto-safe：白名单，非 copy 先、copy 后                                        │
   ▼                                                                                │
MpvVideoController ── 后端链（Phase 12-15）──► RenderBackend::Create ─────────────┘
   │                                              │ mpv_render_context_create(params…)
   │   Windows d3d11: D3D11_INIT_PARAMS(设备)      ▼
   │   Linux  opengl: OPENGL_INIT_PARAMS ────► libmpv_gpu.c / vo_gpu_next.c(0004)
   │   Linux  vulkan: VULKAN_INIT_PARAMS            │ native resource: drm_params_v2 ← DRM_DISPLAY_V2
   │   macOS  vulkan: (MoltenVK)                    │ gl_video_init_hwdecs / ra_hwdec_ctx_init(load_all)
   │                                                ▼
   │                                       ra_hwdec 驱动逐个 init：d3d11va(ra_d3d11) / vaapi(egl 或 pl dmabuf)
   │                                                 / vulkan(ra_vk) / videotoolbox(vt_pl)；失败的驱动静默不注册
   ▼
渲染线程：mapper_map(解码帧) → ra 纹理 → gpu/gpu-next 着色 → 宿主共享目标
   ▲
   └── 可观测：hwdec-current / hwdec-interop / video-params/{pixelformat,hw-pixelformat} / options/d3d11va-zero-copy
```

### Recommended Project Structure
```
packages/mpv_kit/lib/src/player/player.dart      # 平台默认 hwdec 列表（私有常量 + 文档）
packages/mpv_kit/test/player_test.dart           # 默认列表与用户覆盖的测试
packages/mpv_kit_video/src/drm_render_node.{h,cc}  # (新) Linux 专用：EGL 设备/Vulkan 物理设备 → render node fd
packages/mpv_kit_video/linux/opengl_backend.cc   # Create 参数里加 DRM_DISPLAY_V2
packages/mpv_kit_video/src/vulkan_backend.cc     # Create 参数里加 DRM_DISPLAY_V2（经 Interop 钩子，默认 -1）
native/patches/0004-...                          # gpu-next libmpv_init 注册 native resource
native/build/build.sh                            # required_features 增加 VAAPI DMABUF_INTEROP_GL（Linux）
example/integration_test/hwdec_probe.dart        # (新) 读取属性 + 分类 + 打印 HWDEC {json}
example/test/hwdec_probe_test.dart               # (新) 分类规则的纯单测（可在任意宿主跑）
docs/adr/0006-hwdec-defaults.md                  # (新) 默认列表决策与行为变更
```

### Pattern 1: 平台默认列表 + 用户选项最后展开
**What:** 保持 `Player` 工厂现有结构：默认 map 先写，`...options` 最后展开（用户值覆盖）。
**When to use:** HWD-01。
**Example:**
```dart
// Source: packages/mpv_kit/lib/src/player/player.dart:99-122（现有结构，已读）
final mpv = Mpv.create(
  libraryPath: libraryPath,
  options: {
    'vo': 'libmpv',
    'hwdec': _defaultHwdec(),   // 新：按 Platform 选列表；原值 'vulkan,d3d11va-copy,auto-safe'
    'hwdec-codecs': 'h264,vc1,hevc,vp8,vp9,av1,prores,prores_raw,dpx,apv',
    // ... 其余默认 ...
    ...options,                 // 用户值最后，赢
  },
);
```
推荐列表（零拷贝名在前，`-copy` 与 `auto-safe` 在后；缺 interop 的条目被 mpv 自动跳过，所以同一列表对该平台所有后端安全）：

| 平台 | 推荐 `hwdec` | 依据 |
|------|--------------|------|
| Windows | `vulkan,d3d11va,d3d11va-copy,auto-safe` | Vulkan 后端：`vulkan`（Vulkan Video）零拷贝，不可用（GTX 960 级）时 `d3d11va` 无 interop 被跳过，落 `d3d11va-copy`；D3D11 后端：`vulkan` 被跳过（`hwdec_vulkan.c:64-65` 在非 Vulkan ra 上返回 0 但不注册设备），`d3d11va` 零拷贝 |
| Linux | `vulkan,vaapi,auto-safe` | Vulkan 后端：`vulkan` 然后 `vaapi`（pl dmabuf）；GL 后端：`vulkan` 跳过，`vaapi`（EGL dmabuf）；尾部 `auto-safe` 含 `vaapi-copy` 兜底 |
| macOS | `videotoolbox,auto-safe` | MoltenVK 没有 Vulkan Video；`vulkan` 条目在 mac 上会注册设备（`hwdecInterop` 为 `videotoolbox,vulkan`）但 FFmpeg 解码初始化会失败，白白多一轮 fallback；显式 `videotoolbox` 在前，需用修正探针重测（见 Pitfall 2） |

### Pattern 2: 三态零拷贝判定（断言助手）
**What:** 一个纯函数把四个事实归类为 `zero-copy` / `copy-back` / `software` / `unexpected`，复用 Phase 13 的 `routeHwdecOutcome` 思路（`example/integration_test/macos_route_probe.dart:314-361`，已读），但去掉 videotoolbox 硬编码。
**Example:**
```dart
// 规则（hwdec-current 取 method_name，copy 变体带 "-copy" 后缀：vd_lavc.c:323）
//   zero-copy : hwdec-current ∈ {d3d11va, vaapi, vulkan, videotoolbox, drm}
//               且 video-params/pixelformat == 对应硬件格式名（d3d11/vaapi/vulkan/videotoolbox）
//               且 video-params/hw-pixelformat 非空（nv12/p010…）
//   copy-back : hwdec-current 以 "-copy" 结尾，pixelformat 为软格式（nv12/yuv420p10…）
//   software  : hwdec-current == "no"（属性不可用则为 unavailable，测试须先等它非空）
// 额外记录（不参与三态）：options/d3d11va-zero-copy（解码表面直采 vs 一次 GPU 拷贝）
```

### Anti-Patterns to Avoid
- **只看 `hwdec-current` 就宣称零拷贝：** `d3d11va` 默认含一次 GPU 拷贝，`vaapi`/`vulkan` 帧映射失败也先显示方法名；必须带 `pixelformat`。
- **把 `auto-safe` 当零拷贝保证：** 它的白名单含 `d3d11va-copy`、`vaapi-copy`、`videotoolbox-copy` 等（`vd_lavc.c:285-291`），interop 缺失时会静默 copy-back。
- **用 lavfi 源测 hwdec：** `testsrc2` 是原始视频，永远 `hwdec-current=no`。现有 `real_plugin_test`、`d3d11_backend_test`、`uhd_endurance_test` 等都用 lavfi（`real_plugin_test.dart:119-122`），要断言零拷贝必须打开真实编码样本。
- **把宿主的 `Platform` 判断写进原生/Dart 公共 API：** API 冻结；平台分支只放私有函数。

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| hwdec 优先级与回退 | 自己的解码器选择/回退状态机 | mpv 列表语义 + `hwdec-software-fallback`（默认 3） | `vd_lavc.c:503-650`、`1214-1215` 已处理 attempted 去重、失败后换下一方法 |
| dma-buf 导入（GL） | 手写 EGLImage 导入 | `dmabuf_interop_gl.c`（含 NV12/P010 平面拆分、modifier 属性） | 已处理 R8/GR88/R16/GR1616 映射，`dmabuf_interop_gl.c:226-250` |
| dma-buf 导入（Vulkan） | 手写 `VkImage` 导入 | `dmabuf_interop_pl.c` → libplacebo `PL_HANDLE_DMA_BUF` | 含 AMD size==0 的 lseek 处理（`dmabuf_interop_pl.c:44-60`） |
| VADisplay 创建 | 自己 `vaGetDisplayDRM` | 传 `render_fd`，让 `hwdec_vaapi.c` 做 | `hwdec_vaapi.c:63-70` |
| D3D11 解码设备 | 自己 `av_hwdevice_ctx_create(D3D11VA)` | `hwdec_d3d11va` 用 `d3d11_wrap_device_ref(ra 的设备)` | 保证解码与渲染同设备（`hwdec_d3d11va.c:111-116, 142-146`） |
| render node 枚举 | 解析 `/dev/dri` 命名猜测 | EGL_EXT_device_drm_render_node / VK_EXT_physical_device_drm | 设备名不可靠（renderD128 不一定是目标 GPU） |
| 零拷贝断言 | 各测试各写一套字符串比较 | 一个共享助手 + 一份单测 | HWD-05 要求每个测试一致输出 |

**Key insight:** 本阶段 90% 是"接线与证据"，几乎没有该手写的解码/导入代码；真正要写的代码是（a）Dart 默认列表，（b）0004 的 ~15 行 native-resource 注册，（c）Linux render node 解析（约 100 行），（d）断言助手。

## Findings by Research Question

### 1. 默认 hwdec 列表：各 hwdec 与后端的零拷贝对应、列表跳过语义、用户优先

**1.1 hwdec ↔ ra 对应（源码确认）**

| mpv hwdec | 需要的 ra | 在本项目后端上 | 证据 |
|-----------|-----------|----------------|------|
| `d3d11va` | `ra_is_d3d11(ra)`；无则 `init` 返回 -1 | 仅 D3D11 后端（`ra_d3d11`，来自 `libmpv_gpu_context_d3d11`）；Vulkan 后端上不可用 | `hwdec_d3d11va.c:111-112` `if (!ra_is_d3d11(hw->ra_ctx->ra)) return -1;` |
| `vulkan`（Vulkan Video） | libplacebo Vulkan ra（`ra_vk_ctx_get`） | Vulkan 后端；D3D11/GL 后端上"加载成功但不注册设备" | `hwdec_vulkan.c:64-65` `"This is not a libplacebo vulkan gpu api context."` 后 `return 0` |
| `vaapi` | dmabuf interop：`dmabuf_interop_gl_init`（ra_gl，需当前 EGL context）→ `dmabuf_interop_pl_init`（ra_pl，需 `PL_HANDLE_DMA_BUF`）；再需 VADisplay | GL 后端（vo_gpu）与 Vulkan 后端（gpu 与 gpu-next） | `hwdec_vaapi.c:121-130, 172-186`；`dmabuf_interop_gl.c:394-402`；`dmabuf_interop_pl.c:100-112` |
| `videotoolbox`（非 copy） | `hwdec_vt_pl`（Vulkan/MoltenVK + `PL_HANDLE_MTL_TEX`） | macOS Vulkan 后端（Phase 13 hosted 已证） | `13-VERIFICATION.md` SC3 |
| `drm`（`hwdec_drmprime`） | 任一 dmabuf interop；设备路径取 `drm_params_v2.render_fd`，否则默认 `/dev/dri/renderD128` | Linux；在 `auto-safe` 白名单内，排在 `vaapi` 之后 | `hwdec_drmprime.c:100-117`；`vd_lavc.c:279` |

**1.2 列表如何选择（`vd_lavc.c:503-650`，已读）**
- 逐个列表项；对非 `auto*` 的名字，只考虑 `method_name`/`name` 匹配的条目；已尝试过的 `name` 跳过（`552-561`）。
- 非 copy 且带 `lavc_device` 的条目：`hwdec_create_dev` 先 `hwdec_devices_request_for_img_fmt`，再 `hwdec_devices_get_by_imgfmt_and_type`；拿不到 → `MP_VERBOSE "Could not create device."` + `continue`（`587-592`）。即**缺 interop 时跳到下一项，不会 copy-back**。
- `-copy` 条目（`copying==true`）走 `fns->create_dev` 独立创建设备（`470-479`）。Windows 的独立设备用 `D3D_DRIVER_TYPE_HARDWARE` + 默认适配器（`video/d3d.c:176-199`），不是 Flutter 的适配器——混合 GPU 笔记本上 `d3d11va-copy` 可能解在另一块卡上（风险，非本阶段改动对象）。
- 名字完全不识别时只 `MP_WARN "Unsupported hwdec"`（`631-632`），然后继续下一项。
- 选定后若运行期映射/解码失败，`hwdec_fail_count` 累计到 `hwdec-software-fallback`（默认 3，`vd_lavc.c:174`）后 `force_fallback` 进入下一方法（`1214-1215`）。
- `auto-safe`（含 `auto`、`yes`、`""`）= 白名单，非 copy 优先排序（`hwdec_compare`，`vd_lavc.c:294-316`），**随后才是 copy**；因此尾部的 `auto-safe` 本身就是"最后兜底的 copy-back"，要在文档里这样标注。
- 注意 libmpv 是 `load_all_by_default=true`：所有 interop 在渲染上下文创建时就加载（`libmpv_gpu.c:97`、`vo_gpu_next.c:2620`），`probing=true`（`gpu/hwdec.c` `load_hwdecs_all`），这会让 vaapi 在 `va_guess_if_emulated`（VDPAU 包装）时拒绝（`hwdec_vaapi.c:198`）。

**1.3 用户显式 `hwdec` 仍优先**：默认 map 先写、`...options` 最后（`player.dart:101-122`），Dart map 后值覆盖前值；运行期 `setHardwareDecoding(mode)` 直接 `setPropertyString('hwdec', mode)`（`player.dart:676`）。要写的测试：`Player(options: {'hwdec': 'no'})` 后读 `hwdec` 属性等于 `no`（`api_surface_test.dart:199` 已有 `anyOf('no', ['no'])` 的读取写法可参照），与现有 `an explicit hwdec-codecs option overrides the default`（`player_test.dart:431-437`）同构。平台分支用私有函数 + `@visibleForTesting` 的可注入参数（仿 `defaultShaderCacheDir({String? os, ...})`，CLAUDE.md Conventions），使三平台列表在任一宿主上可测。

**1.4 现状错误文档**：`README.md:196` 写 `Player()` sets `hwdec=auto-safe`，`README.md:45` 注释同；`docs/ARCHITECTURE-diagrams.md:41,79,397` 写 `vulkan,auto-safe`；实际默认是 `vulkan,d3d11va-copy,auto-safe`（`player.dart:101`）。HWD-01 的文档任务应一次性修正这些，并在 ADR 记行为变更（Linux GL 路径从"尾部 `vaapi-copy` 拷回"变为"`vaapi` 零拷贝，失败后落 `vaapi-copy`"）。

### 2. Windows：d3d11va 在 D3D11 后端上的零拷贝

**2.1 是否支持、同设备**：支持，且设备是同一个。`libmpv_d3d11.c:30-48` 从 `MPV_RENDER_PARAM_D3D11_INIT_PARAMS` 取宿主设备并建 `ra_d3d11`；`hwdec_d3d11va.c:114-116` 取 `ra_d3d11_get_device(ra)`，`142-146` 用 `d3d11_wrap_device_ref(p->device)` 把**这个设备**交给 FFmpeg D3D11VA（`d3d.c:155-170` 的 `av_hwdevice_ctx_alloc` + 直接塞 `hwctx->device`）。gpu-next 路径（0004，`vo_gpu_next.c:3198-3207`）用 `ra_d3d11_get_device` 建 `pl_d3d11`，解码帧在 `hwdec_get_tex` 里经 `ra_d3d11_get_raw_tex` + `pl_d3d11_wrap` 包装（`vo_gpu_next.c:781-795`）。`vo_gpu`（gpu 渲染器）直接用 `ra_d3d11` 纹理。两条渲染器路径都在同一设备上、都不经 CPU。
- 前置条件都已满足：设备带 `D3D11_CREATE_DEVICE_VIDEO_SUPPORT`（`d3d11_backend.cpp:317-332`，WARP/Basic Render Driver 上无该标志重试）、`SetMultithreadProtected(TRUE)`（`d3d11_backend.cpp:338-343`；`hwdec_d3d11va.c:127-133` 也会再设一次）。
- 解码在 mpv 的解码线程，渲染在渲染线程，靠 multithread 保护串行化（`d3d11_backend.cpp` 文件头线程规则，14-07-PLAN.md:134）。

**2.2 `d3d11va-zero-copy` 的真实含义（纠正 ROADMAP 的措辞风险）**
- 默认 `no`（`hwdec_d3d11va.c:68-77`，`.defaults = {0}`）：`mapper_init` 建一个与视频同尺寸的 `copy_tex`（BIND_SHADER_RESOURCE），`mapper_map` 用 `CopySubresourceRegion1(..., D3D11_COPY_DISCARD)` 从解码表面数组切片做 **GPU-to-GPU 拷贝**，随后立即 `mp_image_unrefp(&mapper->src)` 归还解码表面（`hwdec_d3d11va.c:204-270`）。这仍是"没有 CPU 往返"的零拷贝（相对 `d3d11va-copy` 的系统内存拷回），但多一次显存拷贝。
- `yes`：直接把解码纹理数组切片包成 SRV 采样（`hwdec_d3d11va.c:271-282`），省一次拷贝与功耗；代价（官方文档，`DOCS/man/options.rst:6495-6505`）：底部/右边缘因 padding 可能采样错、可能触发驱动 bug（D3D11 技术上不允许采样解码表面）；另一个工程代价是解码池表面被 VO 帧队列占用更久，需要 `hwdec-extra-frames`（Player 已固定 6，`player.dart:116`）足够，否则池耗尽（`vd_lavc.c:1003-1004` 的 `initial_pool_size`）。
- 两种模式下 `hwdec-current` 都是 `d3d11va`；区分只能靠读 `options/d3d11va-zero-copy`（MpvOptions 已生成 `d3d11vaZeroCopy`，`generated/options.dart:1345`）。
- **推荐**：Player 不设置 `d3d11va-zero-copy`（保持默认 no）。理由：默认路径满足"非 copy-back"，4K HEVC 10-bit 的 GPU 拷贝在 RTX 4060 上成本很低（4K P010 约 25 MB/帧量级的片上带宽，ASSUMED 未测）；`yes` 的 padding 边缘风险直接威胁 SC2"无绿帧/黑帧"。把 `yes` 作为 RTX 会话里的对照实验（同样本、同 harness 各跑一次，记录画面与丢帧），数据证明有显著收益再升级为用户决策。8K 门禁延后，不在本阶段验收。

**2.3 P010 / 10-bit**：`d3d11_formats[]` 含 `AV_PIX_FMT_P010 → DXGI_FORMAT_P010 {"r16","rg16"}`（`hwdec_d3d11va.c:35-37`），`init` 对每个格式做 `CheckFormatSupport(... TEXTURE2D)`，只登记设备支持的（`hwdec_d3d11va.c:135-141`）。P010 的 10 位样本占 16 位字的高 10 位，低 6 位为 0 [CITED: learn.microsoft.com/windows/win32/medfound/10-bit-and-16-bit-yuv-video-formats]，所以以 R16_UNORM/R16G16_UNORM 平面视图采样后必须按 `p010` 的位深做缩放，这部分由 mpv 的 `mp_image_params`/着色器处理，宿主无需介入。Intel 驱动有 HEVC 黑名单（`video/d3d.c:94-100`：Intel 0x8086 的 20.19.15.4284–5172 段），仅影响 Intel iGPU，不影响 RTX 4060（`d3d11_is_codec_allowed` 会在选中前拒绝并告警，`vd_lavc.c:593-600`）。
- "已知绿/黑帧"来源（按可能性）：(1) zero-copy=yes 的边缘 padding；(2) 解码池耗尽导致取帧失败；(3) 色彩空间/范围误判（与 hwdec 无关，需与 `hwdec=no` 软解参考帧对比，沿用 Phase 13 的 reference + screenshot 对比方法）。判定 SC2 应复用 Phase 13 做法：同一样本先 `hwdec=no` 出参考截图，再 `hwdec=d3d11va`，用 VO 截图与 Flutter `toImage` 两通道对比（`macos_route_test.dart` 的 `_runSample`，已读）。

**2.4 hosted 上的 WARP**：Basic Render Driver 创建 `VIDEO_SUPPORT` 设备失败（0x887A0004，`14-01-SUMMARY.md:114`），插件去标志重试；此时 `hwdec_d3d11va` 的 `init` 仍可能成功注册（只做 CheckFormatSupport），但 FFmpeg 解码初始化会失败 → `force_fallback` → 下一项 → 最终软解。`d3d11va-copy` 的独立设备创建（`D3D11_CREATE_DEVICE_VIDEO_SUPPORT` + 硬件类型，`d3d.c:176-199`）也会失败 → 条目被跳过。**结论：hosted 能证明"默认列表在 WARP 上落软解且不崩"，不能证明解码**。这条需要一次 hosted 探针确认（Wave 0 spike），因为 `d3d11va` 条目是否在 WARP 上被选中后再失败、失败耗时多少，源码层面无法确定（`hwdec_fail_count`=3 的路径）。

**2.5 依赖与顺序**：Phase 14 还有 14-09（RTX 4060 测量）、14-10、14-11（auto 链切换）未执行（`14-VERIFICATION.md` frontmatter）。`kWindowsApiOrder` 仍是 `{"vulkan","d3d11"}`（`d3d11_interop.cpp:25`）。所以 Phase 16 的 RTX 会话必须用 `MPV_KIT_VIDEO_API=d3d11` 强制 D3D11 后端；不要等 14-11。建议把 Phase 16 的 RTX 项并入 14-09 的同一次硬件会话（同样本、同机器状态），避免多次会话成本。

### 3. Linux vaapi：DRM_DISPLAY_V2、render node 选择、两条后端

**3.1 参数语义**：`MPV_RENDER_PARAM_DRM_DISPLAY_V2 = 16`，类型 `struct mpv_opengl_drm_params_v2*`（`render.h:347-352`，宿主副本在 `packages/mpv_kit_video/src/include/mpv/render.h:350-352`）。结构体（`render_gl.h:171-199`，已读）：`int fd`（DRM fd，无效置 -1）、`int crtc_id`、`int connector_id`、`struct _drmModeAtomicReq **atomic_request_ptr`、`int render_fd`（"DRM render node. Used for VAAPI interop. Set to -1 if invalid"）。
- vaapi 只读 `render_fd`：`hwdec_vaapi.c:63-70` `if (!params || params->render_fd == -1) return NULL; return vaGetDisplayDRM(params->render_fd);`。因为 `build.sh` 关了 x11/wayland（`build.sh:32`，`-Dx11=disabled -Dwayland=disabled`），**DRM 是唯一的 VADisplay 来源**（`hwdec_vaapi.c:73-87` 的 `create_native_cbs` 只剩 `drm`）。
- 宿主应传：`fd=-1, crtc_id=0, connector_id=0, atomic_request_ptr=NULL, render_fd=<打开的 render node>`。`drmprime-overlay` 驱动要真实 `fd`/crtc（`hwdec_drmprime_overlay.c:262-273`），传 `fd=-1` 会让它初始化失败并被跳过（`drm_atomic_create_context` 失败），无副作用。
- libmpv 如何传给 hwdec_vaapi：`libmpv_gpu.c:32-49` 的 `native_resource_map[MPV_RENDER_PARAM_DRM_DISPLAY_V2] = {.name="drm_params_v2", .size=sizeof(mpv_opengl_drm_params_v2)}`；`init` 在 `fns->init` 之后、`gl_video_init_hwdecs` 之前遍历 params，对有 size 的条目 `talloc_memdup` 结构体，再 `ra_add_native_resource(ra, "drm_params_v2", data)`（`libmpv_gpu.c:80-97`）。所以**结构体会被拷贝（宿主栈上变量即可），但 `render_fd` 本身不会被 dup**：宿主必须在 `mpv_render_context_free` 之后才关 fd。

**3.2 关键缺口：Vulkan gpu-next 路径不注册 native resource**。`libmpv_gpu.c` 的循环只服务 `vo_gpu` 的 render_backend（GL 与 Vulkan 的 `gpu` 渲染器）。补丁 0004 的 gpu-next 后端 `libmpv_init`（`vo_gpu_next.c:3142-3235`）自己调用 `fns->init`，然后直接 `preinit(vo)`；`preinit` 在 `vo_gpu_next.c:2620` 对 `libmpv` 用 `load_all=true` 初始化所有 hwdec，这发生在任何 `ra_add_native_resource` 之前（grep：`vo_gpu_next.c` 与 `libmpv_vk.c` 中没有 `native_resource`/`drm_params` 出现）。结果：`create_drm_va_display` 取到 `params==NULL` → "Could not create a VA display." → vaapi 加载失败。
- **补丁要点**（放进 0004，保持下游补丁集 provenance gate：重新生成 0004 后 `tools/check_patches.sh` 须字节一致，`UPSTREAM.md` provenance gate 一节）：在 `libmpv_init` 的 `preinit(vo)` 之前，对 `p->ra_ctx->ra` 重复 `libmpv_gpu.c` 那段注册逻辑。最小实现是把 `native_resource_map` 与注册循环提成 `libmpv_gpu.h` 里的一个函数（例如 `libmpv_gpu_add_native_resources(struct ra *ra, void *talloc_ctx, mpv_render_param *params)`），`libmpv_gpu.c:init` 与 `vo_gpu_next.c:libmpv_init` 共用；talloc 父对象用 `lp`（`vo_gpu_next.c` 的 `libmpv_priv`）保证随上下文释放。约 15–25 行，不改 ABI。
- GL 后端无此缺口：Linux GL 只跑 `gpu` 渲染器（`opengl_backend.cc:Create` 拒绝 `gpu-next`，"opengl serves only the gpu renderer"，已读）。

**3.3 GL 路径的前置条件（vaapi interop 能否加载）**
- `dmabuf_interop_gl_init`（`dmabuf_interop_gl.c:394-423`）要求：`ra_is_gl`、**当前线程有 EGL context**（`eglGetCurrentContext()`）、EGL 扩展 `EGL_EXT_image_dma_buf_import` 与 `EGL_KHR_image_base`、GL 扩展 `GL_EXT_EGL_image_storage`（桌面 GL）或 `GL_OES_EGL_image`（ES）、`MPGL_CAP_TEX_RG`；`EGL_EXT_image_dma_buf_import_modifiers` 存在时才传 modifier（`use_modifiers`，`:417-418`）。
- Phase 15 的 `RenderBackend::RunBound`（`render_backend.h:127-129`、`opengl_backend.cc:187-214`）正好保证 `mpv_render_context_create` 与首次 `set_update_callback` 在"mpv 的 EGL context 当前"的线程上执行，所以 `eglGetCurrentContext()` 非空；这是 interop 能加载的前提，不要改动 RunBound 的约定。
- `dmabuf_interop_gl.c:366-388` 里 map 时用 `eglGetCurrentDisplay()`（渲染线程已 `eglMakeCurrent(display_, ...)`，`opengl_backend.cc:BindThread`），即 Flutter 的 EGLDisplay。**dma-buf 来源 GPU 必须与该 EGLDisplay 背后的 GPU 相同**，否则 `eglCreateImageKHR` 失败，日志 "Failed to import surface in EGL"，运行期映射失败 → 3 帧后 fallback。
- `build.sh` 现状：`-Dgl=enabled -Degl=enabled -Dplain-gl=enabled -Degl-drm=disabled`（`build.sh:42`），注释已写"builds dmabuf_interop_gl for the later vaapi zero-copy path"。`meson.build:1543` `features += {'dmabuf-interop-gl': features['egl'] and drm.found()}`，不依赖 `egl-drm`（后者要 gbm，`meson.build:1296-1298`）。**用户任务描述里"dmabuf_interop_gl 需要 egl+drm、egl-drm 被关"的前半句成立（需要 egl + libdrm），后半句不构成障碍。** 目前发布日志只打印了 `HAVE_VAAPI 1`、`HAVE_EGL 1`、`HAVE_GL 1`（`/tmp` 日志取自 release run 40662838575 linux-x64 job，Build 步骤），没有直接看到 `HAVE_DMABUF_INTEROP_GL`，因为 `build.sh:139` 的 `HAVE_` grep 列表不含它——属推断，应在 Wave 0 把 `VAAPI`、`VAAPI_DRM`、`DMABUF_INTEROP_GL` 加入 `required_features` 并让 CI 证实。

**3.4 Vulkan 路径的前置条件**
- `dmabuf_interop_pl_init`（`dmabuf_interop_pl.c:100-112`）要求 `ra_pl_get(ra)` 非空且 `gpu->import_caps.tex & PL_HANDLE_DMA_BUF`。libplacebo 7.360.1 的 `vk_tex_handle_caps` 在无 `GetImageDrmFormatModifierPropertiesEXT`（即设备没启用 `VK_EXT_image_drm_format_modifier`）时直接放弃 dma-buf（`src/vulkan/gpu.c:315-320`，已取 raw 源码核对）。
- 本项目 Vulkan 后端已把所需扩展列入可选设备扩展：`VK_EXT_EXTERNAL_MEMORY_DMA_BUF`、`VK_KHR_EXTERNAL_MEMORY_FD`、`VK_EXT_PHYSICAL_DEVICE_DRM`、`VK_EXT_IMAGE_DRM_FORMAT_MODIFIER`（`vulkan_backend.cc:41-48`），设备支持即启用。所以 Vulkan 侧**不需要新增设备扩展**，只缺 native resource（见 3.2）。
- P010：`dmabuf_interop_pl.c` 按平面导入（`R16`/`RG16` 格式，各自带 `drm_format_mod` 与 offset/pitch，`:44-76`）；任一平面导入失败即整帧失败。

**3.5 render node 选择（混合 GPU）**
- GL 后端：宿主在 `OpenGLBackend` 里已持有 `display_`（Flutter 的 EGLDisplay，`opengl_backend.cc:EnsureDevice`）。解析顺序建议：
  1. `eglQueryDisplayAttribEXT(display_, EGL_DEVICE_EXT, &dev)`（`EGL_EXT_device_query`）→ 若设备扩展含 `EGL_EXT_device_drm_render_node`，`eglQueryDeviceStringEXT(dev, EGL_DRM_RENDER_NODE_FILE_EXT)`（token `0x3377`，无 render node 时返回 NULL）[CITED: registry.khronos.org/EGL/extensions/EXT/EGL_EXT_device_drm_render_node.txt]。
  2. 回退：用 Phase 15 已有的 GL 设备 UUID（`gl_interop.cc:125-135` 的 `GL_DEVICE_UUID_EXT`）匹配 Vulkan 物理设备 UUID（`gl_interop.cc:274-282` 已在 `AcceptDevice` 用），再取该物理设备的 DRM 属性。
  3. 都没有 → 不传参数（vaapi 被跳过，软解/`vaapi-copy`）。
- Vulkan 后端：选定物理设备后链 `VkPhysicalDeviceDrmPropertiesEXT`（`VK_EXT_physical_device_drm`），读 `hasRender/renderMajor/renderMinor` [CITED: docs.vulkan.org/refpages/latest/refpages/source/VkPhysicalDeviceDrmPropertiesEXT.html]，用 `makedev` 与 `/dev/dri/renderD*` 的 `st_rdev` 比对得到路径。`PickDevice` 已经用 GL 设备 UUID 对齐 Vulkan 设备（`gl_interop.cc:274-282`），所以 GL 与 Vulkan 两条路径理论上指向同一块 GPU；Wave 2 应在 spike 里让两种解析互相校验并把不一致写进 reason 日志。
- llvmpipe / 软件设备：Mesa 的软件设备对 `EGL_DRM_RENDER_NODE_FILE_EXT` 返回 NULL（Mesa 提交说明：软件设备不使用 render node）[CITED: mail-archive.com/mesa-commit@lists.freedesktop.org/msg119475.html，经 WebSearch 转述，LOW]。没有 `/dev/dri` 的 runner 上 `open` 必然失败。两种情况都按"不传 DRM_DISPLAY_V2"处理，mpv 侧 vaapi 因无 VADisplay 被跳过（`hwdec_vaapi.c:182-186` "Could not create a VA display."）。
- 混合 GPU 陷阱：(1) 默认 render node `renderD128` 不一定是 Flutter 渲染的 GPU；`drm` hwdec 与 `vaapi-copy` 在没有 `render_fd`/`vaapi-device` 时都回退到 `/dev/dri/renderD128`（`hwdec_drmprime.c:109-111`、`vaapi.c:45`），这两条在 `auto-safe` 尾部，仍可能在错误的 GPU 上解码（已有行为，非本阶段引入）；(2) Flutter 的 EGLDisplay 受 `DRI_PRIME`/`__NV_PRIME_RENDER_OFFLOAD` 等环境影响，宿主必须从 display 反查而不是猜；(3) NVIDIA 专有驱动上 VA-API 要靠第三方 `nvidia-vaapi-driver`，且 EGL render-node 扩展支持版本未验证（ASSUMED）——这类机器上 vaapi 很可能不可用，由 mpv 失败后回落。
- fd 生命周期：每个控制器各开各的 `open(path, O_RDWR|O_CLOEXEC)`，在后端 `Release`（`mpv_render_context_free` 之后）关闭；`libmpv_gpu.c` 不 dup（见 3.1）。多控制器各持一个 fd，互不影响。

**3.6 safe fallback（无 `/dev/dri` 或 llvmpipe）**：没有 fd 时不传参数；传了无效 fd 时 `vaGetDisplayDRM` 返回 NULL 或 `va_initialize` 失败（`hwdec_vaapi.c:188-197`），驱动 `init` 返回 -1，`ra_hwdec_load_driver` 只打 verbose "Loading failed."（`gpu/hwdec.c`）。**重要的顺序细节**：`init` 先跑 interop 检查（`:172-186`）再建 VADisplay，所以在 hosted llvmpipe 上，若 EGL/Vulkan 驱动本身不支持 dma-buf 导入，日志里根本不会出现 "Trying to open a drm VA display"，只有 "VAAPI hwdec only works with OpenGL or Vulkan backends."。因此"日志可见 vaapi interop 加载"（SC3）在 hosted 上**不能作为通过条件**——是否出现取决于 llvmpipe/lavapipe 对 `EGL_EXT_image_dma_buf_import`、`VK_EXT_image_drm_format_modifier` 的支持（ASSUMED，无法源码确认）。可靠的 hosted 证明改为：fake-`MpvApi` golden 断言传入 `render_context_create` 的 params 含 DRM_DISPLAY_V2（render_fd 来自可注入的 resolver），加上真实 libmpv 下"不传参数、有 h264 样本、默认列表 → 软解不崩"。

### 4. CI 能证明什么与断言手段

**4.1 mpv 属性（本版本，已读源码）**
| 属性 | 含义 | 证据 |
|------|------|------|
| `hwdec-current` | 当前硬解方法的 `method_name`（带 `-copy` 后缀的是拷回变体）；软解为 `no`；无解码器时不可用（`VDCTRL_GET_HWDEC` 在 `hwdec_notified` 前返回 FALSE） | `command.c:2423-2437`；`vd_lavc.c:1444-1449`；`input.rst:2844-2847` |
| `hwdec-interop` | 已加载的 interop 驱动名，逗号分隔；VO 打开前不可用 | `command.c:2439-2449`；`input.rst:2849-2861`。macOS 实测 `videotoolbox,vulkan`（`route-runs.txt` ROUTE-HWDEC 行） |
| `video-params/pixelformat` | 帧格式名；硬件帧为硬件格式名，拷回后为软格式 | `input.rst:2874-2876`；Phase 13 证据：`videotoolbox` |
| `video-params/hw-pixelformat` | 硬件帧的底层格式（`nv12`/`p010`），非硬件帧不可用 | `command.c:2567-2568` `.unavailable = !p->hw_subfmt`；`input.rst:2877-2879` |
| `options/d3d11va-zero-copy` | 当前 d3d11va 模式 | `hwdec_d3d11va.c:70`；MpvOptions `d3d11vaZeroCopy` |
- 硬件格式名里 `videotoolbox`、`vaapi` 是 mpv 自定义名（`img_format.c:115-120`）；`d3d11`、`vulkan` 来自 FFmpeg 的 pix_fmt 名，**未在源码里读到字符串**（[ASSUMED]），Wave 0 的首批 CI 行要把实际字符串记下来再固化到分类规则。

**4.2 判定规则**：见 Pattern 2。助手应输出一行 `HWDEC {json}`：`{backend, reason, hwdec, hwdecCurrent, hwdecInterop, pixelformat, hwPixelformat, outcome, d3d11vaZeroCopy?}`，格式沿用 `ROUTE-HWDEC`。每个现有集成测试在"首帧就绪"处调用助手（必须先等 `hwdec-current` 非空，Phase 13 的 `_runSample` 轮询逻辑可借用），并断言：`hwdec=no` 的测试 → outcome 必为 `software`；带 `MPV_KIT_REQUIRE_HWDEC` 的硬件层 → 期望值固定（该守卫本身属 Phase 17 VER-03，这里只定义助手接口）。

**4.3 hosted 能/不能证明**
| 层 | 能证明 | 不能证明 |
|----|--------|----------|
| ubuntu-24.04（xvfb + llvmpipe/lavapipe，无 `/dev/dri`） | 助手分类与断言接线；`hwdec=no` 软解在 opengl/vulkan/software 后端；默认列表落软解且不崩（需真实编码样本）；resolver 对无设备/软件设备返回"无"；fake-MpvApi 下 DRM_DISPLAY_V2 参数传递；`build.sh` 必需特征 | vaapi 零拷贝；dma-buf modifier；混合 GPU |
| windows-2025 / windows-11-arm（WARP/Basic Render Driver，无视频解码） | `hwdec-interop` 是否含 `d3d11va`（interop 加载，假设 `CheckFormatSupport(NV12)` 在 WARP 通过，ASSUMED）；默认列表在 WARP 上落软解不崩；`hwdec=no` 在 d3d11/vulkan/software | d3d11va 实际解码与零拷贝 |
| macos-15（Apple Silicon VM，有 VideoToolbox） | Phase 13 已证显式 `videotoolbox` 零拷贝（8-bit/P010）；修正后的默认列表行可重测 | Apple 真机、4K |
| RTX 4060 本机 | d3d11va 零拷贝、4K HEVC 10-bit 画面、`d3d11va-zero-copy` 对照 | Linux vaapi、其他厂商 |
| 无硬件 | — | 真实 vaapi 零拷贝：如实标"未验证"，沿用 Phase 15 `evidence/unverified.txt` 的格式 |

**4.4 现有测试的盲点（HWD-05 范围）**：`real_plugin_test.dart:102`、`seek_recovery_test.dart:42`、`uhd_endurance_test.dart:81`、`playback_bench_test.dart:41`、`impeller_smoke_test.dart:270` 都传 `'hwdec': 'auto-safe'`；`d3d11_backend_test.dart:252`、`d3d11_device_lost_test.dart:127`、`texture_probe_test.dart:243` 传 `'hwdec': 'no'`。除 macOS route 测试外没有任何真实编码样本，所以"断言 hwdec-current"对这些 lavfi 测试只能断言 `no`。对 soak/UHD 测试，HWD-05 的现实读法是：输出并断言 `hwdec-current`（lavfi 下为 `no`），并为硬件层另加带真实样本的测试；这点需在规划时与用户确认（见 Open Questions 1）。

### 5. LGPL 与依赖

- FFmpeg 配置门禁在位：任何 `CONFIG_GPL/NONFREE/VERSION3` 为 1 即拒绝构建（`ffmpeg.sh:90-95`）。`--enable-vaapi`（libva，MIT）、`--enable-d3d11va/--enable-dxva2`（Windows 系统 API）、`--enable-videotoolbox`（系统框架）、`--enable-vulkan` 都不引入 GPL。mpv `-Dgpl=false`（`build.sh` meson 行）保持。
- 无新增系统库：Linux 发布产物已 NEEDED `libva.so.2`、`libva-drm.so.2`、`libdrm.so.2`、`libEGL.so.1`、`libvulkan.so.1`（`.planning/phases/15-linux-opengl-backend/evidence/release-runs.txt:22-26`），均在 `package.sh:45` 的 system 白名单正则内（`libdrm|libva|libva-[a-z0-9]+|libEGL|libvulkan`），按"宿主库、不打包"处理。**注意**：这意味着 libmpv 现在已硬依赖宿主装有 `libva.so.2`/`libva-drm.so.2`（并非本阶段新增，但应在 README 的 Linux 系统要求里说明；若宿主缺 libva，`libmpv.so` 加载就会失败——属已存在风险，非本阶段引入，登记为 Open Question 3）。
- Windows `d3d11va` 只用系统 `d3d11.dll`/`dxgi.dll`/`d3d11_4`；`pe_audit.py --forbid-gpl --forbid-angle` 门禁不变。nvdec（HWD-F1）明确不做：`ffmpeg.sh` 没有 nv-codec-headers，Linux 上 `nvdec-copy` 在 `auto-safe` 尾部会因 FFmpeg 无 nvdec hwaccel 而不出现，无需处理。

## Common Pitfalls

### Pitfall 1: 以为 `hwdec-current=d3d11va` 就是"没有拷贝"
**What goes wrong:** SC2 通过，但实际每帧多一次 GPU 拷贝；或相反，把 `d3d11va-zero-copy=yes` 的 padding 采样误差当成"正确画面"。
**Why it happens:** `hwdec-current` 取 `method_name`，两种模式相同（`vd_lavc.c:1447`、`hwdec_d3d11va.c:204`）。
**How to avoid:** 助手同时记录 `options/d3d11va-zero-copy`；SC2 的验收文字改为"零 CPU 往返（`d3d11va`，非 `-copy`）"，并在 `docs/perf/hwdec-zero-copy.md` 里写清默认含一次 GPU 拷贝。
**Warning signs:** 报告里只有 `hwdec-current` 一栏。

### Pitfall 2: Phase 13 的 macOS "默认列表选软解"是脚手架假象
**What goes wrong:** HWD-01 按"默认不选 videotoolbox"设计 macOS 列表，或相反地忽略真实风险。
**Why it happens:** `macos_route_test.dart:687` 在 pixel 段之后读 `player.hwdec`；pixel 段已经以 per-file 选项 `hwdec=no` 打开过文件（`macos_route_test.dart:355`），属性读到 `['no']`，`'$value'` 变成 `"[no]"`，再作为 hwdec 值喂回（`:737-745`）。证据：`route-runs.txt:34` "Setting option 'hwdec' = '[no]'"，`:35` "vd: Unsupported hwdec: [no]"，而同次运行 `ROUTE-IDENTITY.defaultHwdec` 是 `["vulkan","d3d11va-copy","auto-safe"]`（`:12`）。
**How to avoid:** Wave 0 修正探针（读取 `player` 创建时的默认值，或直接以逗号 join 列表属性），在 macos-route.yml 重跑 default 行；macOS 列表在重测前不固化。注意 macOS 上 `vulkan` 条目会因 `hwdecInterop` 含 `vulkan`（`route-runs.txt` ROUTE-HWDEC 行）而被选中再解码失败，重测要观察"换下一方法"的耗时与日志。
**Warning signs:** 日志里出现带方括号的 hwdec 名。

### Pitfall 3: gpu-next 路径没有 native resource，vaapi 永远建不出 VADisplay
**What goes wrong:** 宿主按文档传了 DRM_DISPLAY_V2，GL 路径（vo_gpu）有效，Vulkan gpu-next 路径无效，日志 "Could not create a VA display."
**Why it happens:** 见 3.2。`libmpv_gpu.c` 的注册循环不会被 gpu-next 的 `libmpv_init` 调用。
**How to avoid:** 补 0004；golden 里以 Vulkan gpu-next 为主断言；真机日志检查"Using a VA display"相关行（真机项，未验证）。
**Warning signs:** `hwdec-interop` 不含 `vaapi` 而 GL 路径含。

### Pitfall 4: interop 检查早于 VADisplay 创建，hosted 日志不能当证据
**What goes wrong:** 在 llvmpipe runner 上因没看到 vaapi 日志而误判宿主没传参数，或因看到 "using libplacebo dmabuf interop" 误判为"vaapi 可用"。
**Why it happens:** `hwdec_vaapi.c:172-186` 的顺序。
**How to avoid:** 参数传递用 fake-MpvApi golden 证明；真实 libmpv 只断言"不崩 + 软解"；SC3 的"日志可见"只在有硬件的会话里要求，hosted 记录实际行但不作门禁。

### Pitfall 5: 样本问题——lavfi 永不触发 hwdec；本机没有 ffmpeg
**What goes wrong:** 测试全绿但从未走过 hwdec；RTX 会话临时找不到 4K HEVC 10-bit 样本。
**How to avoid:** hosted 每平台加 `Generate hwdec samples` 步骤（仿 `macos-route.yml:43-70`，GPL 编码器只造样本，不进 bundle）；RTX 会话样本用同一命令生成 4096x2160 或 3840x2160 `libx265 -pix_fmt yuv420p10le -profile:v main10`（x265 4K 编码慢，样本时长取 10–20 s；`-preset ultrafast` 即可，只要是合法 Main10 码流）。本机 `command -v ffmpeg` 无输出（见 Environment Availability），需用户安装或在 CI 上生成后下载；这是一个需提前告知用户的前置项。

### Pitfall 6: 默认列表里 `vulkan` 在非 Vulkan 后端上的无害性被误解
**What goes wrong:** 担心 D3D11/GL 后端的 `vulkan` 条目会"成功加载但没设备"而卡住。
**Why it happens:** `hwdec_vulkan.c:64-65` 返回 0。
**How to avoid:** 这在 mpv 里是设计行为：`hwdec_devices_add` 没被调用，`hwdec_create_dev` 返回 NULL，列表继续。测试里 `hwdec-interop` 不会出现 `vulkan`，用它作为"interop 没装"的信号。

### Pitfall 7: 运行期映射失败不会立刻回落
**What goes wrong:** vaapi 选中但 `eglCreateImageKHR` 失败（混合 GPU、modifier 不被支持），画面卡/黑 3 帧后才换方法；P010 的 `R16/GR1616` 在缺 `GL_EXT_texture_norm16`（GLES）时直接 `return false`。
**How to avoid:** 保持 `hwdec-software-fallback` 默认 3；尾部保留 `auto-safe`（含 `vaapi-copy`）；Linux 真机验证清单里列 P010、Xe2（Phase 15 已登记的 EGLImage 黑帧）。
**Warning signs:** 日志 "Failed to import surface in EGL"、"mapping VAAPI EGL image failed"。

### Pitfall 8: 补丁集 provenance gate
**What goes wrong:** 改了 `vo_gpu_next.c` 的 libmpv 段但没重生成 0004，`patch-drift` CI 失败。
**How to avoid:** 修改 vendored 树后按 UPSTREAM.md 的流程重生成 0004 并跑 `bash tools/check_patches.sh`；0004 已是"合并补丁"，只扩它，不新增补丁号。

## Code Examples

### 默认列表与覆盖测试（形状）
```dart
// Source: 现有结构 packages/mpv_kit/lib/src/player/player.dart:98-122 与
//         packages/mpv_kit/test/player_test.dart:431-437（已读）
@visibleForTesting
static String defaultHwdecFor(String os) => switch (os) {
  'windows' => 'vulkan,d3d11va,d3d11va-copy,auto-safe',
  'linux'   => 'vulkan,vaapi,auto-safe',
  'macos'   => 'videotoolbox,auto-safe', // 待修正探针重测后固化
  _         => 'auto-safe',
};
// test: Player(options: {'vo':'null','ao':'null','hwdec':'no'}) → hwdec 属性为 ['no']/'no'
// test: 各 os 的列表中，所有 *-copy 与 auto-safe 的下标都大于所有零拷贝名的下标
```

### Linux：native resource 参数（宿主侧，GL 与 Vulkan Create 共用）
```cpp
// Source: 结构体 packages/mpv_kit_video/src/include/mpv/render_gl.h:171-199（已读）
// 参数枚举 render.h:350-352；注册语义 native/mpv/video/out/gpu/libmpv_gpu.c:32-49,80-91
mpv_opengl_drm_params_v2 drm{};
drm.fd = -1;                 // 不做 KMS 显示：drmprime-overlay 会因此被跳过
drm.crtc_id = 0;
drm.connector_id = 0;
drm.atomic_request_ptr = nullptr;
drm.render_fd = render_fd;   // 宿主 open 的 render node；mpv 会 memdup 结构体但不 dup fd
// 仅当 render_fd >= 0 时才把 {MPV_RENDER_PARAM_DRM_DISPLAY_V2, &drm} 放进 params 数组
```

### 0004 补丁形状（gpu-next 注册 native resource）
```c
// Source: 现有 native/mpv/video/out/gpu/libmpv_gpu.c:80-91 的逻辑；
// 目标位置 native/mpv/video/out/vo_gpu_next.c libmpv_init()，preinit(vo) 之前
//   libmpv_gpu_add_native_resources(p->ra_ctx->ra, lp, params);
// 其中该函数从 libmpv_gpu.c 抽出（native_resource_map + talloc_memdup + ra_add_native_resource）
```

### 断言行格式（沿用 ROUTE-HWDEC）
```
HWDEC {"backend":"d3d11","reason":"d3d11 (gpu-next) on NVIDIA GeForce RTX 4060 Laptop GPU",
       "hwdec":"vulkan,d3d11va,d3d11va-copy,auto-safe","hwdecCurrent":"d3d11va",
       "hwdecInterop":"d3d11va,vulkan","pixelformat":"d3d11","hwPixelformat":"p010",
       "outcome":"zero-copy","d3d11vaZeroCopy":false}
// 注意：上例 hwdecInterop 与 pixelformat 字符串是预期形状，未经实测（见 Assumptions A2）
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Player 默认 `vulkan,d3d11va-copy,auto-safe`（全平台一份） | 按平台有序列表，零拷贝名在前 | 本阶段 | Linux GL 路径 vaapi 从 copy-back 变零拷贝；macOS 去掉无效的 `vulkan`；Windows D3D11 后端得到 `d3d11va` |
| Linux 只有 `vaapi-copy`（auto-safe 尾部） | `vaapi` 零拷贝 + 失败回落 `vaapi-copy` | 本阶段 | 真机未验证，hosted 只证明回退 |
| mpv 窗口版 VO 用 `x11`/`wayland` VADisplay | libmpv 嵌入只能经 `DRM_DISPLAY_V2.render_fd` | mpv 现状 | 宿主必须自己解析 render node |
| `d3d11va-zero-copy` 默认 no（上游） | 沿用 | — | 保持默认，作对照 |

**Deprecated/outdated:**
- `MPV_RENDER_PARAM_DRM_DISPLAY`（v1）：`render.h:337-340` 标注 "Deprecated. Not supported"，只用 V2。
- README/ARCHITECTURE-diagrams 中 `hwdec=auto-safe` / `vulkan,auto-safe` 的描述已过时（`README.md:45,196`）。

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | llvmpipe(EGL)/lavapipe 是否支持 `EGL_EXT_image_dma_buf_import`、`VK_EXT_image_drm_format_modifier`，决定 hosted 日志里是否出现 vaapi interop 行 | 3.6、Pitfall 4 | 低：已把 hosted 通过条件改成 fake-MpvApi golden，不依赖该日志 |
| A2 | `video-params/pixelformat` 对 d3d11va/vulkan 硬件帧的字符串分别是 `d3d11`、`vulkan`（FFmpeg pix_fmt 名） | 4.1、Pattern 2 | 中：分类规则写错会让断言误判；Wave 0 首批 CI 行记录实际字符串后再固化 |
| A3 | WARP 上 `hwdec_d3d11va` 的 `init` 能通过（`CheckFormatSupport(NV12, TEXTURE2D)`），因此 `hwdec-interop` 含 `d3d11va` | 2.4、4.3 | 低：只影响 hosted 上"interop 已加载"这一条可选断言 |
| A4 | 在 RTX 4060 上 4K P010 的 GPU 拷贝成本可忽略，故默认 `d3d11va-zero-copy=no` 足够 | 2.2 | 中：若 4K60 下 GPU 拷贝导致掉帧，需转用 `yes`（用户检查点） |
| A5 | NVIDIA 专有驱动对 `EGL_EXT_device_drm_render_node` 的支持版本、nvidia-vaapi-driver 路径上的 vaapi 可用性 | 3.5 | 低：无硬件，已标未验证，失败回落 `vaapi-copy`/软解 |
| A6 | Mesa 软件设备对 `EGL_DRM_RENDER_NODE_FILE_EXT` 返回 NULL（来源为 WebSearch 转述的提交说明） | 3.5 | 低：resolver 对 NULL 与失败同样处理 |
| A7 | macOS 上带 `vulkan` 的列表会白白多一轮 FFmpeg Vulkan 初始化失败（`hwdecInterop` 含 `vulkan` 是已读证据，"解码初始化会失败"是推断） | Pattern 1 表、Pitfall 2 | 低：去掉 `vulkan` 本身无害；重测时验证 |
| A8 | Linux 宿主缺 `libva.so.2` 时 libmpv 加载失败（NEEDED 已见，加载行为是推断） | 5 | 中：已存在风险，需文档化；不由本阶段引入 |
| A9 | 4K x265 样本在 CI/本机生成的耗时可接受（`-preset ultrafast`，10–20 s） | Pitfall 5 | 低 |

## Open Questions

1. **HWD-05 对 lavfi soak/UHD 测试的落地口径**
   - What we know: 这些测试的源是 lavfi 原始视频，`hwdec-current` 恒为 `no`；真实硬解需要编码样本。
   - What's unclear: 用户是否接受"soak 测试只输出并断言 `no`/`software`，硬件层另有带样本的 4K 测试"，还是要求把 soak 改成真实样本。
   - Recommendation: 采用前者；在 16-0x 计划里明确写成口径，并作为用户检查点之一（改 soak 数据源会影响 Phase 4/12 基线可比性）。

2. **默认列表是否包含显式 `vaapi`（Linux）与是否删掉 macOS 的 `vulkan`**
   - What we know: 机制上安全（缺 interop 跳过）；Linux 真机行为未验证；macOS default 行证据已被证伪（Pitfall 2）。
   - What's unclear: 真实 Linux GPU 上 `vaapi` 默认开启后失败时的体验（3 帧黑/卡后回落）。
   - Recommendation: 一票性的行为变更，必须用户确认（见"检查点"）。

3. **libmpv 对宿主 `libva.so.2` 的硬依赖**
   - What we know: 发布产物 NEEDED `libva-drm.so.2`/`libva.so.2`（Phase 15 证据）。
   - What's unclear: 它对没有 libva 的最小 Linux 宿主意味着加载失败，是否要 `dlopen` 化或写入系统要求。
   - Recommendation: 本阶段只在 README 系统要求与 ADR 里记录，不改构建；若用户要求"无 libva 也能起"，另立项。

4. **混合 GPU 笔记本上 `d3d11va-copy` 的默认适配器问题**
   - What we know: `d3d11_create_standalone` 用默认适配器（`video/d3d.c:176-199`），不是 Flutter 的。
   - What's unclear: GTX 960 + iGPU 验收机上是否出现（Phase 14 todo）。
   - Recommendation: 记录，不在本阶段修；14-10 的硬件会话里顺带观察 `hwdec-current` 与 GPU 引擎占用。

5. **`d3d11va-zero-copy=yes` 是否进入 Player 默认**
   - Recommendation: 否（见 2.2）；RTX 对照实验出数据后再提给用户。

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| flutter / dart | Dart 与集成测试 | ✓ | `/d/flutter/bin`（版本未探测，STATE 记录固定 3.47.8） | — |
| gh | 查询 CI run | ✓ | `/c/Program Files/GitHub CLI/gh` | — |
| ffmpeg / ffprobe | 生成 hwdec 样本（本机 RTX 会话） | ✗ | — | 在 CI 上生成后下载；或用户安装 ffmpeg；hosted 每平台用包管理器安装（macOS 已有 `brew install ffmpeg` 先例） |
| meson / ninja | 本机原生构建 | ✗ | — | 依赖 CI（STATE 已记录"本地无 MSYS2/meson，新树构建依赖 CI"） |
| `/dev/dri`（Linux GPU） | vaapi 真机验证 | ✗（本机与 hosted 均无） | — | 标"未验证"，沿用 Phase 15 的 unverified 清单格式 |
| RTX 4060（Windows） | HWD-02 | ✓（本机，Phase 12/14 已用） | — | — |
| Apple 真机 | 无需（HWD-04 已完成） | ✗ | — | 不适用 |

**Missing dependencies with no fallback:** 无阻塞项（Linux 真机验证按设计标未验证）。
**Missing dependencies with fallback:** ffmpeg（本机缺，见 Pitfall 5）、meson（CI）。

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | `package:test` 1.31.1（`packages/mpv_kit/test`）；`flutter_test` + `integration_test`（`example/`）；meson test + 自写 C/C++ 冒烟与 golden（`native/tests/meson.build`）；Python 脚本（`tools/check_route_probe.py` 风格） |
| Config file | `packages/mpv_kit/dart_test.yaml`（tag `format` 默认排除）；`example/pubspec.yaml` |
| Quick run command | `cd packages/mpv_kit && dart test test/player_test.dart`；`cd example && flutter test test/hwdec_probe_test.dart`（新） |
| Full suite command | CI：native-verify.yml / flutter-plugin.yml / macos-route.yml（既有）；本机 RTX：`cd example && MPV_KIT_VIDEO_API=d3d11 flutter test integration_test/<hwdec 测试>.dart -d windows`（新） |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| HWD-01 | 三平台默认列表零拷贝名先于 `-copy`/`auto-safe`；用户 `hwdec` 覆盖优先 | unit（真实 libmpv，`vo=null`） | `cd packages/mpv_kit && dart test test/player_test.dart -n "hwdec"` | ✅ 文件在；❌ 用例 Wave 0 |
| HWD-01 | 文档与 ADR 与代码一致 | 文本检查（grep 脚本） | `bash tools/check_hwdec_docs.sh`（新，可选） | ❌ Wave 0 |
| HWD-02 | D3D11 后端 `hwdec-current=d3d11va`、`pixelformat=d3d11`、非 `-copy`；4K HEVC 10-bit 画面与软解参考一致 | integration（RTX 4060，强制 d3d11） | `cd example && MPV_KIT_VIDEO_API=d3d11 flutter test integration_test/hwdec_zero_copy_test.dart -d windows`（新） | ❌ Wave 0/3 |
| HWD-03 | 传入 `render_context_create` 的 params 含 DRM_DISPLAY_V2（resolver 可注入）；无设备时不传 | native golden（fake MpvApi） | `meson test -C <native/tests build> video_renderer_drm_params_test`（新，仿 `video_renderer_api_test.cc`） | ❌ Wave 0/2 |
| HWD-03 | gpu-next 路径注册 native resource（0004） | native smoke / patch-drift | `bash tools/check_patches.sh`；`render_vk_smoke` 增加一个"传 DRM 参数不崩"变体 | ✅ 脚本在；❌ 变体 Wave 2 |
| HWD-03 | 无 `/dev/dri` 默认列表软解不崩（opengl 与 vulkan 强制后端） | integration（ubuntu xvfb，真实 h264 样本） | `MPV_KIT_VIDEO_API=opengl xvfb-run -a flutter test integration_test/hwdec_zero_copy_test.dart -d linux`（新） | ❌ Wave 1 |
| HWD-05 | 分类规则（zero-copy/copy-back/software/unexpected）纯函数 | unit（任意宿主） | `cd example && flutter test test/hwdec_probe_test.dart` | ❌ Wave 0 |
| HWD-05 | 每个后端 `hwdec=no` 软解 outcome==software | integration（hosted 三平台 × 强制后端） | 复用 `real_plugin_test.dart`/`d3d11_backend_test.dart`/`texture_probe_test.dart` + 助手 | ✅ 文件在；❌ 接线 Wave 1 |
| HWD-05 | macOS default 行重测（修正后） | integration（macos-15） | `macos-route.yml` 现有 job | ✅ 工作流在；❌ 探针修正 Wave 0 |

### Sampling Rate
- **Per task commit:** `dart test test/player_test.dart` 与 `flutter test test/hwdec_probe_test.dart`（秒级，无需 GPU）。
- **Per wave merge:** hosted CI（native-verify + flutter-plugin + macos-route）按 Phase 14/15 的 scratch 分支流程；本阶段沿用"push-green-only"授权约定，需在 16-01 做授权检查点。
- **Phase gate:** hosted 全绿 + RTX 4060 会话证据（`docs/perf/hwdec-zero-copy.md`）+ Linux 未验证清单经用户确认，再 `/gsd-verify-work`。

### Wave 0 Gaps
- [ ] `example/integration_test/hwdec_probe.dart` + `example/test/hwdec_probe_test.dart` — 分类规则与 `HWDEC {json}` 格式（HWD-05）
- [ ] 修正 `example/integration_test/macos_route_test.dart` 的 default 行取值（HWD-01 macOS）
- [ ] hosted 每平台 `Generate hwdec samples` 步骤（h264/hevc 8-bit/10-bit，640x360）
- [ ] `native/tests/video_renderer_drm_params_test.cc`（HWD-03 参数传递）
- [ ] `build.sh` 必需特征增加 `VAAPI`、`DMABUF_INTEROP_GL`（Linux）并让 CI 证实
- [ ] `packages/mpv_kit/test/player_test.dart` 新增默认列表/覆盖用例
- 框架安装：无新增

## Security Domain

### Applicable ASVS Categories
| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | — |
| V3 Session Management | no | — |
| V4 Access Control | yes（窄） | 宿主以 `O_RDWR|O_CLOEXEC` 打开 `/dev/dri/renderD*`：只打开 render node（不是 primary node，无 KMS 特权），路径来自 EGL/Vulkan 反查，不接受外部输入 |
| V5 Input Validation | yes | 环境变量/路径（若 resolver 读 `/dev/dri`）做白名单匹配（只接受 `/dev/dri/renderD[0-9]+`）；Dart 侧列表是常量 |
| V6 Cryptography | no | 沿用既有 sha256 bundle 校验，本阶段不动 |
| V7 Error handling / logging | yes | 失败信息进 reason/日志，沿用 `SanitizeReasonField`；不泄漏路径以外的敏感信息 |

### Known Threat Patterns for 本阶段技术栈
| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| 文件描述符泄漏（render node fd 不关） | 资源耗尽/信息泄露 | 每控制器一个 fd，`Release` 里在 `mpv_render_context_free` 之后关闭；`O_CLOEXEC`；soak（100 轮 create/dispose）里统计 `/proc/self/fd` 数量不增长（Linux 可测，hosted 上 resolver 无设备则 vacuous，需用注入的假 fd 测） |
| 路径遍历/符号链接（render node 路径来自设备枚举） | 篡改 | 只信 `makedev` 比对得到的 `/dev/dri/renderD*`；不解析用户给的路径 |
| 不可信媒体触发驱动解码器缺陷 | 拒绝服务/EoP | 沿用 mpv/FFmpeg 的 codec 白名单（`hwdec-codecs`）与 `d3d11_codec_blocklist`；`hwdec-software-fallback` 回落；不引入新解码路径 |
| 在错误 GPU 上解码/导入（混合 GPU） | 信息泄露（跨设备显存） | render node 与 EGL/Vulkan 设备匹配；不匹配则不传参数 |

## Plan Breakdown Recommendation

推荐 5 个计划、4 个 wave（与 Phase 14/15 一致：先 spike 后实现，hosted CI 授权检查点在最前）。

**Wave 1（无行为变更，造证据与工装）**
- **16-01 授权与 hosted 工装**：push 授权检查点（沿用 Phase 13-15 的 push-green-only 约定）；断言助手 `hwdec_probe.dart` + 单测；`Generate hwdec samples` 步骤；`build.sh` 必需特征；修正 macOS default 行探针。
- **16-02 hosted 探针（spike）**：scratch 分支上跑：(a) macOS 修正后的 default 行（决定 macOS 列表）；(b) Windows WARP forced-d3d11 + 真实 HEVC 样本 + 默认列表 → 实际 outcome、日志、`hwdec-interop`、`pixelformat` 字符串（固化 A2）；(c) Linux 强制 opengl/vulkan 下记录 resolver 在 runner 上的输出与 vaapi/interop 日志行（仅记录，不设门）。

**Wave 2（行为变更，每项可独立回滚）**
- **16-03 HWD-01 默认列表**：`player.dart` 平台列表 + 单测 + README/ARCHITECTURE-diagrams/ADR 0006；**用户检查点**（列表内容）。
- **16-04 HWD-03 Linux**：0004 补 native resource（先红后绿的 fake-MpvApi golden 与 `render_vk_smoke` 变体）→ `drm_render_node` resolver → GL 与 Vulkan `Create` 传 DRM_DISPLAY_V2 → fd 生命周期测试；未验证清单写入 `evidence/unverified.txt`。16-03 与 16-04 文件无重叠，可并行。

**Wave 3（接线全覆盖）**
- **16-05 HWD-05 接线**：把助手接入所有现有集成测试（lavfi 测试断言 `no`/`software`；带样本的新测试 `hwdec_zero_copy_test.dart` 覆盖 d3d11/opengl/vulkan/software 的 `hwdec=no` 与默认列表），hosted 三平台矩阵。

**Wave 4（硬件会话与收口）**
- **16-06 RTX 4060 会话 + 文档**：并入 14-09 同一次会话：`MPV_KIT_VIDEO_API=d3d11` 4K HEVC 10-bit，记录 `hwdec-current`/`pixelformat`/`d3d11va-zero-copy` 对照（no 与 yes 各一次）、画面与软解参考对比、丢帧；写 `docs/perf/hwdec-zero-copy.md` 的 `## Verification tiers`；最终审计与未验证清单用户确认。

**一票性/需用户检查点的决定**
1. 各平台默认 hwdec 列表（公开行为变更；Linux 真机未验证仍默认开启 `vaapi`）。
2. `d3d11va-zero-copy` 默认值（建议保持 no；yes 仅在 RTX 数据支持时提议）。
3. HWD-05 对 lavfi soak 测试的口径（Open Question 1）。
4. 修改补丁 0004（共享补丁，需重生成并过 provenance gate）——属实现细节，但建议在 16-04 计划里以检查点形式让用户知晓。
5. SC3 措辞：hosted 上"日志可见 vaapi interop"不能作门禁（Pitfall 4），建议像 Phase 15 的 SC3 一样请用户批准措辞调整（参考 `15-VERIFICATION.md` 的 `decision=sc3-wording`）。
6. 14-11（Windows auto 链切到 D3D11）未完成：HWD-02 的验收用强制 `MPV_KIT_VIDEO_API=d3d11`，需用户确认这一口径。

## Risks

| 风险 | 影响 | 缓解 |
|------|------|------|
| R1 vaapi 真机未验证，默认开启后失败体验差 | Linux 用户 3 帧卡顿后回落 | 尾部 `auto-safe` 含 `vaapi-copy`；未验证清单；ADR 写明 |
| R2 Phase 14 的 14-09..14-11 未执行 | HWD-02 的 RTX 会话与 auto 切换交织 | 强制 d3d11 后端；与 14-09 合并会话 |
| R3 `hwdec-current` 不区分 GPU copy 与直采 | 验收措辞与事实不符 | 助手额外记录 `d3d11va-zero-copy`，验收文字改为"零 CPU 往返" |
| R4 macOS 默认行证据被证伪 | macOS 列表可能错 | Wave 1 重测后再固化；在此之前列表标注待定 |
| R5 现有测试几乎都不触发 hwdec | HWD-05 流于形式 | 样本生成 + 新测试；口径由用户确认 |
| R6 gpu-next 缺 native resource | HWD-03 Vulkan 一半不成立 | 补 0004 |
| R7 本机无 ffmpeg/meson | RTX 会话样本与本地构建受阻 | 样本由 CI 生成或用户安装 ffmpeg；原生构建依赖 CI |
| R8 libva 硬依赖 | 无 libva 宿主无法加载 libmpv | 文档化，作为 Open Question |

## Sources

### Primary (HIGH confidence)
- 本仓库源码与证据（本会话逐文件 Read/grep）：`native/mpv/video/decode/vd_lavc.c`、`video/out/gpu/hwdec.c`、`libmpv_gpu.c`、`vo_gpu_next.c`、`hwdec/hwdec_vaapi.c`、`dmabuf_interop_gl.c`、`dmabuf_interop_pl.c`、`hwdec_vulkan.c`、`hwdec_drmprime*.c`、`d3d11/hwdec_d3d11va.c`、`d3d11/libmpv_d3d11.c`、`video/d3d.c`、`player/command.c`、`include/mpv/render*.h`、`DOCS/man/options.rst`、`DOCS/man/input.rst`、`meson.build`；`native/build/{build,ffmpeg,package}.sh`；`native/patches/UPSTREAM.md`；`packages/mpv_kit/lib/src/player/player.dart`；`packages/mpv_kit_video/{src,windows,linux}/*`；`example/integration_test/*`。
- `.planning/phases/13-*/13-VERIFICATION.md`、`docs/perf/macos-route-verification.md`、`evidence/route-runs.txt`；`14-VERIFICATION.md`、`14-01-SUMMARY.md`；`15-VERIFICATION.md`、`15-.../evidence/{unverified,decisions,release-runs}.txt`。
- libplacebo v7.360.1 `src/vulkan/gpu.c`（`gh`/curl 取 raw 源，核对 dma-buf 能力门槛）。

### Secondary (MEDIUM confidence)
- [EGL_EXT_device_drm_render_node（Khronos Registry）](https://registry.khronos.org/EGL/extensions/EXT/EGL_EXT_device_drm_render_node.txt)：token `0x3377`、无 render node 返回 NULL、依赖 `EGL_EXT_device_query`。
- [VkPhysicalDeviceDrmPropertiesEXT（Vulkan 文档）](https://docs.vulkan.org/refpages/latest/refpages/source/VkPhysicalDeviceDrmPropertiesEXT.html)：`hasRender/renderMajor/renderMinor`，需 `VK_EXT_physical_device_drm`。
- [10-bit and 16-bit YUV Video Formats（Microsoft Learn）](https://learn.microsoft.com/en-us/windows/win32/medfound/10-bit-and-16-bit-yuv-video-formats)：P010 布局与低 6 位为 0。

### Tertiary (LOW confidence)
- [Mesa commit: egl: add support for EGL_EXT_device_drm_render_node](https://mail-archive.com/mesa-commit@lists.freedesktop.org/msg119475.html)：经 WebSearch 转述（软件设备返回 NULL），未打开原文核对。

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — 无新增依赖，版本取自仓库脚本。
- Architecture / mpv 行为: HIGH — 全部结论来自通读 vendored 源码并给出行号。
- Linux 真机行为、混合 GPU、NVIDIA: LOW — 无硬件，已按设计标未验证。
- Pitfalls: MEDIUM — 源码推导为主；Pitfall 2 为对 Phase 13 证据的重新解读，需 Wave 1 重测确认。

**Research date:** 2026-10-28
**Valid until:** 2026-11-27（mpv/libplacebo 基座固定在 vendored 树；若重基到含 `libmpv` native-resource 改动的新 mpv，需复核 3.2）

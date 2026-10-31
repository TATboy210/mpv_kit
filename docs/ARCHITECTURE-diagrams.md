# mpv_kit 架构图集(Architecture Diagrams)

> 基线:mpv **v0.41.0-1113-gfd9265a905**(vendored 于 `native/mpv`)+ 7 个下游补丁
> 生成:2026-10-22 / 更新:2026-10-23
>
> **维护指引**:升级 vendored mpv 基线或重放补丁时,对照
> `native/patches/UPSTREAM.md` 的 rebase 台账更新 §2.4;渲染链路如有
> 帧环/隔离参数调整同步 §1.3;其余图仅在上游模块重组时需要动。
> 行数数据来自当时快照,作量级参考而非精确契约。

---

# 第一部分:mpv_kit(仓库根)

## 1.1 仓库顶层地图

```
D:\mpv_kit\
│
├── packages/                      ← 三个 Dart/Flutter 包(pub.dev 发布物)
│   ├── mpv_kit/                   ← 纯 Dart FFI:libmpv client API 完整绑定
│   ├── mpv_kit_video/             ← Flutter 插件:C++ 渲染桥 + 平台 interop
│   └── mpv_kit_libs/              ← native-assets build hook:下载/校验 libmpv bundle
│
├── native/                        ← C 层世界(补丁 + 构建 + 冒烟)
│   ├── mpv/                       ← vendored mpv 0.41.0-1113 源码树 + 7 补丁(836+ 文件)
│   ├── patches/                   ← 7 个 .patch 存档 + UPSTREAM.md(上游关系台账)
│   ├── build/                     ← build.sh / deps.sh / ffmpeg.sh / package.sh(LGPL 管线)
│   ├── tests/                     ← render_vk_smoke.c、stream_bridge_test.c(C 冒烟)
│   └── out/                       ← 本地构建产物(gitignore)
│
├── (bt/ retired)                  ← 旧预编译 DLL 目录已从仓库移除;本地测试用 mpv_kit_libs
│                                    hook bundle 或 MPV_KIT_LIBMPV_PATH(见 README)
├── tools/                         ← bundle_report.sh / gen_catalog.dart / gen_options.dart /
│                                    pin_bundles.dart / make_format_samples.sh /
│                                    rea_abi_audit/(54 符号清单 PE 审计)
├── docs/                          ← ARCHITECTURE.md、MIGRATING_FROM_MEDIA_KIT.md、
│                                    adr/0001-vulkan-render-backend.md、adr/0002-lgpl-self-built-binaries.md、
│                                    reverse-engineering/01-libmpv-render-pipeline.md、
│                                    reverse-engineering/02-flutter-windows-external-texture.md
├── example/                       ← 三平台示例 app(hwdec 用 Player 默认,见 ADR 0006)
└── .github/workflows/             ← native-verify.yml(六目标编译+冒烟+ABI+Dart 测试+ASan/UBSan)
                                     release.yml(LGPL 依赖栈出包) flutter-plugin.yml(示例编译)
```

## 1.2 三包依赖与分层关系

```
┌─────────────────────────────────────────────────────────────────────┐
│                        宿主 app(simple_player)                       │
└──────────────────────────────────┬──────────────────────────────────┘
                                   │ import
                                   ▼
┌─────────────────────────────────────────────────────────────────────┐
│  mpv_kit_video  (0.1.0-dev.4)  Flutter 插件层                        │
│  ┌──────────────────────────┐  ┌────────────────────────────────┐  │
│  │ lib/src/                 │  │ 平台原生(C++/ObjC++)            │  │
│  │  mpv_video.dart  (118)   │  │  windows/: d3d11_interop.cpp(155)│  │
│  │  video_controller.dart   │  │           mpv_kit_video_plugin.cpp│  │
│  │    (338)                 │  │  linux/: gl_interop.cc           │  │
│  │  re-export mpv_kit 全 API│  │  macos/: metal_interop.mm + MoltenVK│
│  └──────────┬───────────────┘  │  src/(共享): video_renderer.cc(573)│
│             │                  │          vulkan_backend.cc (392)  │
│             │                  │          mpv_api.h               │  │
└─────────────┼──────────────────┴───────────────┬────────────────┘  │
              │ 依赖                              │ FFI 调用           │
              ▼                                  │ (54 符号)          │
┌─────────────────────────────────┐              │                    │
│  mpv_kit  (0.1.0-dev.4)         │              │                    │
│  纯 Dart,无 Flutter 依赖        │              │                    │
│  lib/src/                       │              │                    │
│   ffi/bindings.dart   (858)─────┼──────────────┘                    │
│   ffi/library.dart    ( 91)     │  动态加载 libmpv-2.dll            │
│   core/mpv.dart       (581)     │                                   │
│   core/events.dart    (352)     │                                   │
│   core/stream_bridge.dart (280) │←── 对应 native 补丁 0006          │
│   core/node.dart      (135)     │   mpv_node ↔ Dart 转换            │
│   core/errors.dart    ( 61)     │                                   │
│   player/player.dart            │   typed Player(按平台 hwdec 列表, │
│   player/models.dart            │     零拷贝优先,ADR 0006)          │
│   generated/catalog.dart (4346) │   mpv 属性/命令/选项全目录(生成)  │
│   generated/options.dart (7617) │                                   │
└─────────────┬───────────────────┘                                   │
              │ 构建期依赖(native-assets hook)                        │
              ▼                                                       │
┌─────────────────────────────────┐                                   │
│  mpv_kit_libs  (0.1.0-dev.4)    │                                   │
│  hook/build.dart (85)           │   build 钩子:按目标下载 bundle     │
│  lib/src/bundles.dart (26)──────┼──→ pin GitHub Release (sha256×6)  │
│  lib/src/bundle.dart (173)      │   解包+校验                       │
│  lib/src/tar.dart (124)         │                                   │
└─────────────────────────────────┘                                   │
                                                                      │
                    libmpv-2.dll(bt/ 或下载 bundle)◀──────────────────┘
```

## 1.3 mpv_kit_video 的 Windows 渲染链路(核心细节)

```
  Dart 侧                          C++ 侧(插件)                          GPU 侧
───────────                ─────────────────────────────              ─────────────
MpvVideoController
  │ setSize(物理像素,        ┌────────────────────────────┐
  │  cap 在视频尺寸内)        │   VideoRenderer (573 行)    │
  │ setIccProfile ──────────▶│  专用渲染线程 RenderLoop     │
  │ syncDisplayRefreshRate ──│  mpv update callback 只置    │
  ▼                          │  flag + signal,不干活       │
MpvVideo widget              └──────────┬─────────────────┘
  │ CompositorLatency()=4               │ RenderOnce() 每帧:
  ▼                                     ▼
┌──────────────────────────────────────────────────────────────────┐
│ 1. PickBackBuffer()  从 7 槽帧环挑一个非 front 槽                  │
│ 2. resize?  → VulkanBackend.AllocateRing(7×33MB@4K≈232MB 显存)    │
│    (旧代 retire,等合成端读完再释放)                                │
│ 3. WaitImage(slot)  ◀── CPU 等 timeline semaphore                 │
│    (上一消费者用完该槽;1s 超时)                【同步税 ①】        │
│ 4. 填 mpv_vulkan_image{queue_family=VK_QUEUE_FAMILY_EXTERNAL,     │
│    layout=GENERAL, signal=timeline+NextSignalValue}               │
│ 5. api_.render_context_render(MPV_RENDER_PARAM_VULKAN_IMAGE)      │
│    ──▶ mpv 内部 pl_vulkan_wrap 该 VkImage 为渲染目标               │
│    ──▶ gpu-next 完成全部渲染(色彩管理/缩放/OSD/字幕)              │
│ 6. WaitImage(slot)  ◀── CPU 等 GPU 画完                           │
│    (Flutter 合成端无 fence,不能交回未完成图)   【同步税 ②】        │
│ 7. FrameReady() → front_ 指针推进                                 │
│    (探针:每 120 帧输出 ①②的均值/max,2026-10-22 新增)            │
└──────────────────────────┬───────────────────────────────────────┘
                           ▼
┌──────────────────────────────────────────────────────────────────┐
│  D3D11Interop::CreateImage()  (windows/d3d11_interop.cpp, 155 行) │
│  • 按 LUID 匹配 Flutter 的 DXGI adapter(AcceptDevice)            │
│  • CreateTexture2D: DXGI_FORMAT_B8G8R8A8_UNORM                    │
│    + D3D11_RESOURCE_MISC_SHARED(legacy KMT 句柄)                  │
│  • vkImportMemoryWin32HandleInfoKHR + dedicated allocation        │
│    → 同一块显存导入为 VkImage                                      │
│  ★ 一帧数据只有一份 GPU 显存:零 CopyResource、零 Map/memcpy       │
└──────────────────────────┬───────────────────────────────────────┘
                           ▼
┌──────────────────────────────────────────────────────────────────┐
│  mpv_kit_video_plugin.cpp Describe()(raster 线程)                 │
│  AcquireFront() → FlutterDesktopGpuSurfaceDescriptor{             │
│      handle = KMT 句柄, format = BGRA8888 } + release_callback    │
│  → flutter_windows.dll ExternalTextureD3d(已被 Ghidra 逆向证实):   │
│    经 ANGLE EGL_D3D_TEXTURE_2D_SHARE_HANDLE_ANGLE 绑定,           │
│    绑定后立即调 release_callback(无 fence/keyed mutex)             │
│  → 合成器直接采样共享纹理上屏                                      │
└──────────────────────────────────────────────────────────────────┘

  软件 fallback:MPV_RENDER_API_TYPE_SW,每帧 CPU 全量 RGBA + 补 alpha
  (4K 下 33MB/帧 CPU 写,仅诊断/兜底)
```

---

# 第二部分:mpv 源码树(0.41.0-1113,vendored 于 `native/mpv`)

## 2.1 全模块地图(目录 → 文件数/代码行;★ = mpv_kit 补丁触碰)

```
native/mpv\  (v0.41.0-1113-gfd9265a905, LGPL 构建, ~142k 行 C)
│
├── player/                      23 files   25.0k   播放器核心
│   ├── playloop.c               (1384)      主循环:每 tick 查状态/触发重绘
│   ├── loadfile.c               (2332)      装载状态机:open/seek/切换
│   ├── video.c                  (1352)      视频定时/display-sync 音频补偿
│   ├── audio.c                              音频定时
│   ├── command.c                            属性/命令实现(所有 mpv_property)
│   ├── client.c                             libmpv client API 后端(mpv_handle)
│   ├── configfiles.c                        配置装载
│   ├── scripting.c / lua/ / javascript/    脚本引擎(mpv_kit 构建禁用)
│   └── stream_bridge.c ★0006 新增           Dart 异步流桥(player 侧)
│
├── demux/                       36 files   19.9k   解封装层
│   ├── demux.c                  (4991)      缓存/线程/回滞(master 新增
│   │                                         --demuxer-hysteresis-bytes)
│   ├── packet_pool.c            (164) ★新   包池 GC(master 新增:热保留16+
│   │                                         pop 顺带释放 64,治大 cache 停顿)
│   ├── demux_lavf.c                         FFmpeg 封装对接
│   ├── demux_mkv.c                          Matroska(seek 纠偏已合)
│   └── demux_timeline.c / demux_playlist.c / ebml.c …
│
├── stream/                      32 files   11.9k   I/O 源层
│   ├── stream_cb.c              (106)★      用户自定义流协议(Dart 侧经此)
│   ├── stream_file.c / stream_memory.c / stream_curl.c(master 新增,已禁)
│   └── network.c/h ★新                     master 新增网络层
│
├── video/
│   ├── decode/
│   │   └── vd_lavc.c            (1554)      硬解调度:master 池 auto 计算
│   │                                         (vo_get_num_frame_refs+3)、
│   │                                         seek 等关键帧≤96、驱动黑名单
│   ├── filter/                              vf 链(vf_d3d11vpp/vf_amf★新…)
│   └── out/                     54 files   31.6k   视频输出(见 2.3 详图)
│
├── audio/
│   ├── out/                     32 files   13.3k   ao_wasapi★0007 / ao_alsa /
│   │                                         ao_pulse / ao_pipewire…
│   ├── decode/  filter/                     ad_lavc、af_scaletempo…
│   └── aframe.c / format.c
│
├── sub/                         22 files    8.0k   字幕(libass/sd_lavc/sd_sbr★新)
├── filters/                     31 files   10.0k   通用 filter 框架
│   └── f_output_chain.c / f_lavfi.c / f_autoconvert.c
│
├── common/                      24 files    5.7k   公共(av_log 对接、全局结构)
├── options/                     17 files   10.8k   选项系统(m_option/m_config)
├── input/                       15 files    5.8k   输入(keybind/cmd 解析)
├── misc/                        36 files    5.6k   杂项(bstr/mp_uuid/…)
├── osdep/                       53 files    8.6k   平台抽象(win32/ pthread/timer)
├── ta/                           5 files    1.1k   talloc 内存池(mpv 万物之根)
├── include/mpv/                  6 files    3.5k   【对外 API 头】
│   ├── client.h                             mpv_handle/属性/命令 API
│   ├── render.h                             render API 类型/参数
│   ├── render_gl.h                          GL render API
│   ├── render_vk.h ★0001 新增(493 行补丁)  MPV_RENDER_API_TYPE_VULKAN
│   │                                         + VULKAN_INIT_PARAMS/IMAGE/
│   │                                         RENDERER(0x6d6b0001..3)
│   ├── stream_cb.h                          stream 协议注册 API
│   └── stream_bridge.h ★0006 新增           异步流桥公开头
│
├── meson.build ★0001/0006 修改              依赖与源列表(PL>=7.360.1 硬要求)
└── test/                        29 files    5.2k   mpv 自测(mpv_kit 构建禁用)
```

## 2.2 播放主数据流(文件→像素)

```
  文件/URL/Dart 流协议
        │
        ▼
┌──────────────┐   packet    ┌──────────────┐  mp_image  ┌──────────────┐
│  demux 层     │───────────▶│  decoder 层   │───────────▶│  filter 链    │
│  demux.c      │            │  vd_lavc.c    │            │  vf_* (sw)    │
│  cache 线程   │            │  hwdec 分派:  │            │  f_output_chain│
│  hysteresis   │            │  vulkan★0002  │            └──────┬───────┘
│  packet_pool  │            │  d3d11va      │                   │
│  GC ★新       │            └──────────────┘                   ▼
└──────────────┘                                        ┌──────────────┐
        ▲                                               │  vo.c (1549)  │
        │ loadfile.c 装载状态机                          │  VO 调度中枢   │
        └──────────────────────────────────────────────│  request_redraw│
                                                       │  vo_set_queue_ │
                                                       │  params(req+N)│
                                                       └──────┬───────┘
                                                              │ vo_driver
                                    ┌─────────────────────────┴─────┐
                                    ▼                               ▼
                          ┌──────────────────┐          ┌─────────────────────┐
                          │ vo_gpu (旧 gl_video)│        │ vo_gpu_next (3320)   │
                          │ mpv_kit 可选回落   │          │ libplacebo 渲染器    │
                          └──────────────────┘          │  pl_queue  帧队列    │
                                                         │  pl_renderer 渲染   │
                                                         │  (缩放/色彩/HDR/TM) │
                                                         └─────────┬───────────┘
                                                                   ▼
                                                         ┌─────────────────────┐
                                                         │ 输出后端 ra_ctx:     │
                                                         │  vulkan/context_win  │
                                                         │  d3d11/ (mpv_kit 禁) │
                                                         │  opengl/angle (禁)   │
                                                         └─────────┬───────────┘
                                                                   ▼
                                                          swapchain / render 目标
```

## 2.3 渲染子系统分解(video/out 内部)

```
video/out\
├── vo.c (1549)              VO 生命周期/帧调度/重绘节流(vsync 精确间隔)
│                              vo_get_num_frame_refs() ← master 新增,喂 vd_lavc 池
├── vo_gpu_next.c ★0004/0005 (3320 行)  ★★ mpv_kit 主渲染器 ★★
│   ├── struct priv {
│   │     libmpv: bool + libmpv_target(pl_swapchain_frame)
│   │     req_frames: int            ← 0004 新增字段
│   │     hwdec slots(master 重构)… }
│   ├── update_overlays()   ← 0004: !vo->osd 早退守卫
│   ├── apply_target_options() ← 0004: sw 空守卫(dither 探测)
│   ├── set_colorspace_hint() ← 0004: p->libmpv → return false
│   ├── draw_frame()        ← 0004: target_hint 强制 false;libmpv 分支
│   │                          swframe=p->libmpv_target(免 swapchain)
│   ├── update_render_options() ← 0004: p->req_frames 记录 + libmpv 跳过
│   ├── preinit/uninit      ← 0004: libmpv 时跳过 gpu_ctx_create,
│   │                          hwdec 全量装载,shader cache 免重复挂
│   └── 【尾部 261 行】render_backend_gpu_next 实现 ← 0004
│       libmpv_init → 拿宿主 VkDevice → libmpv_gpu_context_vk.init
│       libmpv_render → wrap_fbo(MPV_RENDER_PARAM_VULKAN_IMAGE)
│                      → 填 libmpv_target(SDR sRGB/BT.709)
│                      → draw_frame(私有 vo) → done_frame
│       libmpv_update_external → 转发 osd + vo_set_queue_params(req, 2req-1)
│
├── vo_libmpv.c ★0004/0005 (779)      render API 宿主
│   ├── mpv_render_context_create → render_backends[] 选择:
│   │     render_backend_gpu_next ★0004(HAVE_VULKAN)
│   │     render_backend_gpu      (0001 的 GL 链)
│   │     render_backend_sw
│   ├── MPV_RENDER_PARAM_VULKAN_RENDERER get_info ★0005(报活跃渲染器)
│   └── master 重构: ctx->renderer->driver_caps(与补丁已融合)
│
├── gpu/
│   ├── libmpv_gpu.c/h ★0001            GL 渲染后端的 context 抽象
│   └── …(mpv_kit 构建下 gl=disabled,此目录多半不编)
│
├── vulkan/ ★★ mpv_kit 的主战场
│   ├── context.c (650) ★0001
│   │   ra_vk_ctx_init_external/uninit_external ← 0001 新增:
│   │     marker swapchain(vulkan_external_swapchain,不呈现,
│   │     只让 ra_vk_ctx_get() 找到 mpvk_ctx)
│   ├── context_win.c                        Win32 surface + preferred_ref_luma
│   ├── libmpv_vk.c ★0001/0002/0003 (361)
│   │   init(): pl_vulkan_import(宿主 VkDevice+queue)
│   │           0002: imported_extensions 拷贝进 mpvk_ctx
│   │           0003: pl_cache 持久化 shader 编译缓存挂到 gpu
│   ├── common.h ★0002   mpvk_ctx += imported_extensions/num
│   └── context_display/wayland/mac.c …(其他平台)
│
├── hwdec/
│   ├── hwdec_vulkan.c ★0002 (421)     Vulkan Video 硬解映射
│   │   vulkan_init(): 给 FFmpeg AVVulkanDeviceContext 传
│   │     真实 device extensions(导入设备时 libplacebo 不填,
│   │     不修→Vulkan Video 静默回退 *-copy,4K 直接不可用)
│   └── hwdec_d3d11va.c 等(master 已扩格式:4:2:2/10-12bit)
│
├── d3d11/ (mpv_kit 构建禁用 d3d11=disabled)
├── opengl/ / placebo/ (ra_pl.c:ra↔libplacebo 桥,mpv_kit 依赖)
├── libmpv.h ★0004   extern render_backend_gpu_next
├── libmpv_sw.c             软渲染 render backend(兜底)
└── vo.c 层公用: aspect.c / dither.c / filter_kernels.c / dr_helper.c…
```

## 2.4 mpv_kit 7 补丁注入点全景(谁的改动打在谁的哪里)

```
补丁      大小    落点文件                              注入内容
─────────────────────────────────────────────────────────────────────────────
0001     493 行  include/mpv/render_vk.h(新增)         VULKAN render API 头
                 video/out/vulkan/libmpv_vk.c           pl_vulkan_import 宿主设备
                 video/out/vulkan/context.c(+.h)        ra_vk_ctx_init_external
                 video/out/gpu/libmpv_gpu.c(+.h)        libmpv_gpu_context_vk
                 meson.build                             源列表/render_vk.h 安装
                 DOCS/client-api-changes.rst
─────────────────────────────────────────────────────────────────────────────
0002      49 行  video/out/hwdec/hwdec_vulkan.c         FFmpeg hwctx 传真实
                 video/out/vulkan/common.h               device extensions
                 video/out/vulkan/libmpv_vk.c           (无此补丁 4K 直接不可用:
                                                         Vulkan Video 静默回退
                                                         *-copy,每帧 12MB 拷贝)
─────────────────────────────────────────────────────────────────────────────
0003     161 行  video/out/vulkan/libmpv_vk.c           pl_cache 持久化
                                                         shader 缓存
                                                         (首帧 SPIR-V 编译 0.4s
                                                         → cache 命中 0 掉帧)
─────────────────────────────────────────────────────────────────────────────
0004     539 行  include/mpv/render_vk.h                VULKAN_RENDERER 参数
                 video/out/libmpv.h                     extern gpu_next backend
                 video/out/vo_gpu_next.c                VO 侧 libmpv 模式(13
                 video/out/vo_libmpv.c                    hunks,8 原样+5 手工
                 meson.build                              rebase 到 master 重构)
                 ※ 核心意义:gpu-next 成为 render API 默认渲染器
─────────────────────────────────────────────────────────────────────────────
0005      50 行  video/out/vo_libmpv.c                  get_info 报活跃渲染器
                 (依赖 0004)
─────────────────────────────────────────────────────────────────────────────
0006     412 行  include/mpv/stream_bridge.h(新增)      Dart 异步流桥:
                 player/stream_bridge.c(新增)            stream_cb 无法同步应答
                 meson.build                              时的异步 completions
                 ※ Dart 侧对应 core/stream_bridge.dart(280 行)
─────────────────────────────────────────────────────────────────────────────
0007     147 行  audio/out/ao_wasapi.c(+.h)             ① WASAPI COM 对象线程
                 audio/out/ao_wasapi_changenotify.c        亲和(CoIncrementMTA
                 meson.build                               Usage + 线程检查
                                                           CoUninitialize)
                                                         ② macOS cocoa=disabled
                                                           时 cfstr_get_cstr
                                                           NULL 调用修复
─────────────────────────────────────────────────────────────────────────────
基线本身(0.41.0-1113)带来的 4K 收益(非补丁,随上游获得):
  packet_pool GC / hwdec-extra-frames=auto / seek 等关键帧≤96 /
  demuxer-hysteresis-bytes / mkv seek 纠偏 / wasapi 重试修复 /
  display-sync 音频低通+自适应 slew / d3d11va 格式扩展
```

## 2.5 两条链路合流:一帧 4K 的完整旅程(端到端)

```
 .mkv 4K HEVC 文件(D:/media/xxx.mkv)
   │
   │ Dart: Player.open(path)
   ▼
 mpv_kit (Dart)          mpv (C, 0.41.0-1113)                    GPU (RTX 4060)
 ─────────────          ─────────────────────                   ──────────────
 stream_bridge?──┐
 (仅 Dart 流协议) │
                 ▼
        loadfile.c 装载 ──▶ demux.c(cache 线程+hysteresis)
                                │ packet(packet_pool GC 管理)
                                ▼
                          vd_lavc.c:hwdec=按平台列表(ADR 0006)
                                │ Vulkan Video (hwdec_vulkan.c ★0002)
                                │ 解码面直接是 VkImage(零拷贝)
                                ▼
                          vo.c ──▶ vo_gpu_next.c ★0004
                                │   pl_queue(等 req=2*req-1 帧窗口)
                                │   pl_renderer:
                                │     色彩转换(BT.2020→BT.709)
                                │     缩放(spline36)→ 3840×2160
                                │     HDR→SDR tone-mapping
                                │     目标 = libmpv_target
                                │       (wrap_fbo 包出来的 pl_tex ★0001)
                                ▼
                          渲染目标 = mpv_kit 帧环里的 VkImage
                                │ (同一块显存也是 D3D11 纹理
                                │  — d3d11_interop KMT 共享)
                                ▼
        mpv_render_context_render ◀── RenderOnce 步骤 5
                                │
   步骤 6:WaitImage(等 GPU 完成)【同步税②】
   步骤 7:FrameReady → AcquireFront
                                │
                                ▼
        plugin.cpp Describe(KMT 句柄)──▶ flutter_windows.dll
                                │  ANGLE 采样共享纹理(无 fence,
                                │  立即 release,Ghidra 逆向证实)
                                ▼
                          合成器上屏(DXGI)
```

---

## 规模总结

mpv_kit 自有代码 ≈ Dart 13.9k 行 + C++/ObjC 渲染桥 ≈ 1.5k 行 + 7 补丁 1.85k 行;
mpv 基线 ≈ 142k 行 C。mpv_kit 实际依赖并激活的渲染面 =
`vo.c → vo_gpu_next.c → ra_pl.c → vulkan/{context,libmpv_vk}.c → hwdec_vulkan.c`,
其余(vo_gpu/gl/d3d11/opengl、discnav、脚本引擎等)在 LGPL 构建里被显式禁用。

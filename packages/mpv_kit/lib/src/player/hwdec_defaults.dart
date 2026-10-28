/// 按平台的默认 hwdec 列表（库内部，不从 `lib/mpv_kit.dart` 导出）。
///
/// mpv 的列表语义（native/mpv/video/decode/vd_lavc.c）：
/// - 列表按序尝试。非 `-copy` 条目在当前渲染器（ra）上没有 interop 时
///   会因 "Could not create device." 被跳过并继续下一项，不会拷回；
/// - `-copy` 条目用独立的解码设备，总能建成，所以一旦排在零拷贝条目
///   之前就会抢先选中并把帧拷回系统内存——它们必须排在零拷贝条目之后；
/// - `auto-safe` 是白名单，内部把非 copy 条目排在 copy 之前
///   （vd_lavc.c 271-316 行），因此适合做兜底，必须是最后一项。
///
/// `d3d11va-zero-copy` 保持 mpv 默认（no）：`d3d11va` 每帧做一次显存内
/// GPU 拷贝（零 CPU 往返）；设为 yes 虽省一次拷贝，但底部/右边缘可能
/// 因 padding 采样错并触发驱动问题（mpv options.rst），会直接威胁
/// "无绿帧/黑帧"，故不在 Player 默认值中设置，见 ADR 0006。
///
/// 用户经 `Player(options: {'hwdec': ...})` 覆盖，用户值始终优先。
library;

import 'dart:io' show Platform;

/// [operatingSystem]（`Platform.operatingSystem` 的取值）对应的默认列表。
///
/// 未知平台返回 `auto-safe`。
String defaultHwdecFor(String operatingSystem) => switch (operatingSystem) {
  // vulkan：Vulkan 后端上走 Vulkan Video 零拷贝；d3d11va：D3D11 后端
  // 上零拷贝，Vulkan 后端上无 interop 被跳过；d3d11va-copy：拷回兜底
  // （老卡如 GTX 960 在 Vulkan 后端上落到这里）；auto-safe：最后兜底。
  'windows' => 'vulkan,d3d11va,d3d11va-copy,auto-safe',
  // vulkan：Vulkan 后端上 Vulkan Video；vaapi：GL 后端经 EGL dma-buf、
  // Vulkan 后端经 libplacebo dma-buf（真实硬件未验证）；auto-safe 内含
  // vaapi-copy，作为失败后的拷回兜底。
  'linux' => 'vulkan,vaapi,auto-safe',
  // videotoolbox：Metal 路径零拷贝；MoltenVK 没有 Vulkan Video，故不
  // 再把 vulkan 放在首位（会注册 interop 却解不了码，白白多一轮回落）。
  'macos' => 'videotoolbox,auto-safe',
  // 其他平台：只用 mpv 的保守白名单。
  _ => 'auto-safe',
};

/// 当前进程所在平台的默认 hwdec 列表。
String platformDefaultHwdec() => defaultHwdecFor(Platform.operatingSystem);

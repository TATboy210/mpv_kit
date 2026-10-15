/// mpv_kit_video — Flutter 视频输出（Vulkan 零拷贝 + 软件回退）。
///
/// The single dependency an app needs: it re-exports the mpv_kit API and
/// pulls in mpv_kit_libs, which bundles libmpv. Dependency chain:
///
///     app -> mpv_kit_video -> mpv_kit (Dart FFI) -> libmpv
///                          -> mpv_kit_libs (build hook: bundles libmpv)
library;

export 'package:mpv_kit/mpv_kit.dart';

export 'src/mpv_video.dart';
export 'src/video_controller.dart';

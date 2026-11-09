//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <desktop_drop/desktop_drop_plugin.h>
#include <flutter_video_thumbnail_plus/flutter_video_thumbnail_plus_plugin_c_api.h>
#include <mpv_kit_video/mpv_kit_video_plugin_c_api.h>

void RegisterPlugins(flutter::PluginRegistry* registry) {
  DesktopDropPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("DesktopDropPlugin"));
  FlutterVideoThumbnailPlusPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("FlutterVideoThumbnailPlusPluginCApi"));
  MpvKitVideoPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("MpvKitVideoPluginCApi"));
}

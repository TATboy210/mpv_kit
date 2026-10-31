//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <desktop_drop/desktop_drop_plugin.h>
#include <mpv_kit_video/mpv_kit_video_plugin_c_api.h>

void RegisterPlugins(flutter::PluginRegistry* registry) {
  DesktopDropPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("DesktopDropPlugin"));
  MpvKitVideoPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("MpvKitVideoPluginCApi"));
}

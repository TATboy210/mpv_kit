//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <desktop_drop/desktop_drop_plugin.h>
#include <mpv_kit_video/mpv_kit_video_plugin.h>

void fl_register_plugins(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) desktop_drop_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "DesktopDropPlugin");
  desktop_drop_plugin_register_with_registrar(desktop_drop_registrar);
  g_autoptr(FlPluginRegistrar) mpv_kit_video_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "MpvKitVideoPlugin");
  mpv_kit_video_plugin_register_with_registrar(mpv_kit_video_registrar);
}

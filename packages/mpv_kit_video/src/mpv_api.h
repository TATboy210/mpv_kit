// mpv render API function table, filled from symbol addresses that the Dart
// side resolved in its already-loaded libmpv. The plugin never loads libmpv
// itself, so there is exactly one copy of the library in the process.
#pragma once

#include <cstdint>

#include <mpv/render.h>

namespace mpv_kit {

struct MpvApi {
  int (*render_context_create)(mpv_render_context**, mpv_handle*,
                               mpv_render_param*) = nullptr;
  void (*render_context_set_update_callback)(mpv_render_context*,
                                             mpv_render_update_fn,
                                             void*) = nullptr;
  uint64_t (*render_context_update)(mpv_render_context*) = nullptr;
  int (*render_context_render)(mpv_render_context*,
                               mpv_render_param*) = nullptr;
  void (*render_context_report_swap)(mpv_render_context*) = nullptr;
  void (*render_context_free)(mpv_render_context*) = nullptr;
  const char* (*error_string)(int) = nullptr;

  // Order must match MpvVideoController._symbols on the Dart side.
  static constexpr int kSymbolCount = 7;

  /// Builds the table from raw addresses; false if any is null.
  bool Load(const int64_t* addresses, int count) {
    if (count != kSymbolCount) return false;
    void** slots[] = {
        reinterpret_cast<void**>(&render_context_create),
        reinterpret_cast<void**>(&render_context_set_update_callback),
        reinterpret_cast<void**>(&render_context_update),
        reinterpret_cast<void**>(&render_context_render),
        reinterpret_cast<void**>(&render_context_report_swap),
        reinterpret_cast<void**>(&render_context_free),
        reinterpret_cast<void**>(&error_string),
    };
    for (int i = 0; i < kSymbolCount; i++) {
      if (addresses[i] == 0) return false;
      *slots[i] = reinterpret_cast<void*>(static_cast<intptr_t>(addresses[i]));
    }
    return true;
  }
};

}  // namespace mpv_kit

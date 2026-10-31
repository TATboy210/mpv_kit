// Windows native D3D11 render backend (Phase 14, D3D-06): mpv renders through
// its own D3D11 render API (MPV_RENDER_API_TYPE_D3D11) straight into a ring of
// BGRA8 textures that carry a legacy (KMT) shared handle, and the plugin hands
// those to Flutter through GpuSurfaceTexture (DxgiSharedHandle). No Vulkan, no
// ANGLE, no EGL on mpv_kit's side of the chain.
//
// Threads follow render_backend.h: Create on the platform/start thread;
// Render, Wait, AllocTargets, FreeRetired and Release on the render thread.
// The immediate context is used on the render thread only (plus mpv's d3d11va
// decode thread, serialised by the device's multithread protection); the
// raster thread only reads the shared handle cached in the platform object.
#pragma once

#include <dxgi.h>

#include <memory>

#include "../src/render_backend.h"

namespace mpv_kit {

/// A D3D11 backend with its own ID3D11Device on [adapter] (Flutter's
/// rendering adapter, so the KMT handles stay on one adapter). The device is
/// created by the first Create(); a null adapter makes that Create fail with
/// device_failed(). [adapter] is only used during that call.
std::unique_ptr<RenderBackend> CreateD3D11Backend(IDXGIAdapter* adapter);

}  // namespace mpv_kit

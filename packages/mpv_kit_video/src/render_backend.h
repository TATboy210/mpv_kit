// Graphics-API half of a VideoRenderer: the device, the mpv render context
// and the ring of render targets for one API (Vulkan, software, ...).
// VideoRenderer keeps everything that is the same for every API: the
// render thread, ring bookkeeping (front, in use, quarantine), the publish
// gate, backoff, swaps, idle, ICC and events. The platform's Interop still
// delivers FrameReady and RetainFrame.
//
// Threads: Render, Wait, AllocTargets and FreeRetired run on the render
// thread, between BindThread and UnbindThread, and so does Release, just
// before the render thread exits; FrameFor runs with the renderer lock held
// (AcquireFront and RenderOnce). Create of every candidate, and for the
// winner RendererName and the first set_update_callback, run before the
// render thread starts inside RunBound (the destructor releases a context
// the render thread never owned inside RunBound too), the destructor after
// the render thread was joined. A backend with thread affinity overrides
// RunBound so those create-time calls run on a thread where its context is
// current; Vulkan and software keep the caller's thread. Each VideoRenderer
// owns its own backend instance.
#pragma once

#include <cstdint>
#include <functional>
#include <memory>
#include <string>
#include <vector>

#include "mpv_api.h"

namespace mpv_kit {

/// What a frame handed to the platform texture carries: a shared GPU image
/// (Frame::platform) or CPU pixels (Frame::pixels).
enum class Backend { kVulkan, kSoftware };

/// Renderer requested by the API user. Every choice except kSoftware falls
/// back to the software backend when Vulkan cannot be used.
enum class RendererChoice {
  kAuto,     // gpu-next, then gpu
  kGpuNext,  // libplacebo's renderer only
  kGpu,      // mpv's older gl_video renderer only
  kSoftware, // MPV_RENDER_API_TYPE_SW
};

/// One entry of the candidate chain VideoRenderer::Start tries in order
/// (docs/adr/0004-render-backend-reporting.md, Decision 5): a graphics API
/// ("vulkan", "software", or a platform backend's wire name) and the mpv
/// renderer on it ("gpu-next", "gpu", "sw").
struct BackendCandidate {
  const char* api;
  const char* renderer;
};

/// The chain for [choice] without platform backends:
///   kAuto     vulkan/gpu-next, vulkan/gpu, software/sw
///   kGpuNext  vulkan/gpu-next, software/sw
///   kGpu      vulkan/gpu, software/sw
///   kSoftware software/sw
std::vector<BackendCandidate> DefaultCandidates(RendererChoice choice);

/// GPU completion of one render target.
enum class WaitResult { kOk, kTimeout, kDeviceLost };

/// What the platform texture needs for one ring slot: exactly one of the
/// two is set.
struct TargetView {
  void* platform = nullptr;         // SharedImage::platform (GPU backends)
  const uint8_t* pixels = nullptr;  // tightly packed, stride = width*4
};

/// One graphics API behind a VideoRenderer.
///
/// Deferred-release contract, shared by every backend:
///   * Render never writes into the front, in-use or quarantined slot: the
///     engine picks the slot.
///   * AllocTargets retires the old generation and builds a new one. What
///     survives in retirement, and until when, is the backend's choice:
///       - Vulkan keeps only [keep_slot]'s target; every other old target
///         is released once its last GPU work has completed. Its next
///         AllocTargets first releases that survivor (AllocateRing calls
///         FreeRetired). The engine never hands a survivor out after the
///         following reallocation (it resets its retired front first), and
///         an image the compositor still holds is kept alive by the
///         platform reference (last point below).
///       - Software keeps the whole old generation, and the one retired
///         before it, for one more reallocation: CPU pixels have no
///         platform reference, and the frame of the last AcquireFront()
///         may lie in either. Its next AllocTargets frees the older one.
///     A backend whose targets have no platform reference must keep a
///     target alive while it may back the frame of the last AcquireFront()
///     (valid until the next AcquireFront(), video_renderer.h).
///   * FreeRetired releases every retired target. The engine calls it once
///     the first new-size frame was published and the compositor took
///     quarantine+1 further frames.
///   * Release frees the render context (with the thread bound) before the
///     device; the destructor then frees the remaining targets and finally
///     the device.
///   * A platform object the compositor still holds is kept alive by the
///     platform's own reference (COM AddRef, CVPixelBufferRetain, the GL
///     graveyard) until the platform has unregistered it.
class RenderBackend {
 public:
  virtual ~RenderBackend() = default;

  /// API name in reasons and on the method channel ("vulkan", "software").
  virtual const char* wire_name() const = 0;
  /// What FrameFor hands out.
  virtual Backend frame_kind() const = 0;
  /// True: a rendered frame may only be published after Wait(slot) (GPU).
  /// False: it is complete when Render returns (software).
  virtual bool pipelined() const = 0;

  /// Thread affinity (an OpenGL context must be current). Vulkan and
  /// software have none: no-ops.
  virtual bool BindThread() { return true; }
  virtual void UnbindThread() {}

  /// Runs [fn], the create-time calls (Create, RendererName and the first
  /// set_update_callback of the winning candidate; every failed candidate's
  /// Create; the never-started render thread's release in the destructor),
  /// where the backend can make them: on a thread with its context current.
  /// The default runs [fn] on the caller's thread between BindThread and
  /// UnbindThread, which for Vulkan and software are no-ops, so their
  /// calling thread and order are unchanged. A backend with thread affinity
  /// (OpenGL, Phase 15) may run [fn] on a thread of its own with its
  /// context current, but must unbind that thread before returning: the
  /// render thread then binds the same context in RenderLoop, and a context
  /// is current on one thread at a time. RunBound returns after [fn] did;
  /// a failure inside [fn] is recorded by [fn] itself.
  virtual void RunBound(const std::function<void()>& fn) {
    const bool bound = BindThread();
    fn();
    if (bound) UnbindThread();
  }

  /// Creates the device on the first call, then the render context for
  /// [renderer] ("gpu-next", "gpu", "sw") into *out. Returns the result of
  /// mpv_render_context_create (>= 0: success). A negative value with
  /// device_failed() true means the device could not be initialised and
  /// mpv was not asked. On failure *why is the reason trail's text and
  /// *out is null.
  virtual int Create(const MpvApi& api, mpv_handle* handle,
                     const char* renderer, mpv_render_context** out,
                     std::string* why) = 0;
  /// The device failed to initialise: every later Create fails the same way.
  virtual bool device_failed() const { return false; }
  /// Device for the reason head ("NVIDIA GeForce RTX 4060", "cpu").
  virtual std::string device_name() const = 0;
  /// Renderer mpv really built for [ctx] ("gpu-next", "gpu", "sw").
  virtual std::string RendererName(const MpvApi& api,
                                   mpv_render_context* ctx) const = 0;

  /// (Re)allocates [count] targets of [width]x[height]; only [keep_slot]
  /// (-1: none) of the old generation survives into retirement. False with
  /// *error set when allocation failed; then nothing is allocated.
  virtual bool AllocTargets(int count, int width, int height, int keep_slot,
                            std::string* error) = 0;
  /// Releases the retired generation. A no-op without one.
  virtual void FreeRetired() = 0;
  /// The platform object or pixels of ring [slot].
  virtual TargetView FrameFor(int slot) = 0;

  /// Renders mpv's frame into ring [slot] ([width]x[height]); returns the
  /// mpv_render_context_render result.
  virtual int Render(const MpvApi& api, mpv_render_context* ctx, int slot,
                     int width, int height) = 0;
  /// Waits until the GPU work of the last render into [slot] has completed
  /// (bounded). Always kOk when not pipelined().
  virtual WaitResult Wait(int slot) = 0;

  /// Frees [ctx]; precedes the destructor (the device outlives mpv's
  /// objects on it).
  virtual void Release(const MpvApi& api, mpv_render_context* ctx) = 0;
};

/// MPV_RENDER_API_TYPE_SW into CPU buffers; [bgra] picks the pixel order
/// (Interop::SoftwareIsBgra).
std::unique_ptr<RenderBackend> CreateSoftwareBackend(bool bgra);

class VulkanInterop;  // vulkan_backend.h

/// MPV_RENDER_API_TYPE_VULKAN into images shared zero-copy with the
/// platform compositor through [interop] (vulkan_backend.cc).
std::unique_ptr<RenderBackend> CreateVulkanBackend(VulkanInterop* interop);

/// Makes a driver/mpv-supplied string safe inside a reason field
/// (docs/adr/0004-render-backend-reporting.md): `;` would split a trail and
/// control characters would break the one-line form.
std::string SanitizeReasonField(std::string s);

}  // namespace mpv_kit

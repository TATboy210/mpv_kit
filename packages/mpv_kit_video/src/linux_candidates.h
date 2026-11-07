// The Linux candidate chain as data (Phase 15, GLX-04).
//
// Header-only and platform-free on purpose: the portable chain test
// (native/tests/video_renderer_linux_chain_test.cc) compiles it on every
// platform, and the Linux GlInterop returns it from
// Interop::BackendCandidates (gl_interop.h).
#pragma once

#include <vector>

#include "render_backend.h"

namespace mpv_kit {

/// The chain of the Linux plugin for [choice], in the order
/// VideoRenderer::Start tries it (docs/adr/0004-render-backend-reporting.md,
/// Decision 5: renderer quality first, API second, software last). The
/// order was chosen by the user at the 15-04 checkpoint
/// (`decision=linux-chain choice=A` in
/// .planning/phases/15-linux-opengl-backend/evidence/decisions.txt):
///   kAuto     vulkan/gpu-next, opengl/gpu, vulkan/gpu, software/sw
///   kGpu      opengl/gpu, vulkan/gpu, software/sw
///   kGpuNext  vulkan/gpu-next, software/sw
///   kSoftware software/sw
/// OpenGL has no gpu-next entry: upstream's GL render API is served by
/// vo_gpu only (gpu-next over GL is GLX-F1, out of scope). Rolling the
/// OpenGL backend back means deleting the two "opengl" lines. The only
/// evidence for the OpenGL entries is llvmpipe; real GL drivers are
/// unverified.
inline std::vector<BackendCandidate> LinuxBackendCandidates(
    RendererChoice choice) {
  std::vector<BackendCandidate> chain;
  if (choice != RendererChoice::kSoftware) {
    if (choice != RendererChoice::kGpu) chain.push_back({"vulkan", "gpu-next"});
    if (choice != RendererChoice::kGpuNext) {
      chain.push_back({"opengl", "gpu"});
      chain.push_back({"vulkan", "gpu"});
    }
  }
  chain.push_back({"software", "sw"});
  return chain;
}

}  // namespace mpv_kit

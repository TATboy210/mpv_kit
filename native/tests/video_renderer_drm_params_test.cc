// Test of the DRM render node hand-over to mpv (Phase 16, HWD-03): the host
// resolves a render node, passes it as MPV_RENDER_PARAM_DRM_DISPLAY_V2 and
// closes it only after the render context is freed (drm_render_node.h,
// vulkan_backend.cc).
//
// What it proves:
//   * DRM-RESOLVE: the resolution helpers. IsRenderNodePath accepts only
//     `/dev/dri/renderD<digits>`; FillDrmDisplayParams writes fd=-1, crtc=0,
//     connector=0, atomic_request_ptr=NULL and the given render_fd; on Linux
//     RenderNodePathForDevnum matches renderD* character devices by device
//     number (a temporary directory of symlinks to /dev/null, no root
//     needed) and returns nothing for a missing directory or no match, and
//     OpenRenderNode refuses every path outside the allowlist.
//   * DRM-PARAMS: the real VulkanRenderBackend (vulkan_backend.cc) through
//     the fake libmpv of renderer_harness.h, with a fake Vulkan interop that
//     hands out an fd for /dev/null (or -1):
//       drm-fd           the gpu-next create carries DRM_DISPLAY_V2 with the
//                        render_fd and the fixed fd/crtc/connector/atomic
//                        fields; the fd is requested once.
//       drm-fd-fallback  gpu-next fails, the gpu create carries the same fd;
//                        still one OpenDrmRenderNode call.
//       drm-none         the interop has no node: no create carries the
//                        parameter, nothing is closed.
//       drm-close        the fd is closed exactly once, still open when it is
//                        closed, and after the last render_context_free.
//
// The helper cases run everywhere (the Linux-only ones are compiled on Linux
// only); the DRM-PARAMS scenarios need golden_vk's Vulkan 1.3 device
// (lavapipe, MoltenVK or a GPU) and are skipped on their own without one.
// A separate binary because the golden set is frozen (evidence of phase 12
// and 14); the harness is only read.
//
// usage: video_renderer_drm_params_test
//
// Output: `DRM-RESOLVE ok cases=<n>`, then `DRM-PARAMS ok scenarios=<n>` or
// `DRM-PARAMS vk scenarios skipped: <why>`; on a failure `DRM-RESOLVE
// mismatch ...` or `DRM-PARAMS mismatch ...`. Exit codes: 0 pass, 1 failure.

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <exception>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

#if defined(_WIN32)
#include <fcntl.h>
#include <io.h>
#include <share.h>
#else
#include <fcntl.h>
#include <unistd.h>
#endif

#if defined(__linux__)
#include <sys/stat.h>
#include <sys/sysmacros.h>
#include <sys/types.h>
#endif

#include "drm_render_node.h"
#include "renderer_harness.h"

namespace {

using mpv_kit::RendererChoice;
using mpv_kit::VideoRenderer;

constexpr const char* kApiVariable = "MPV_KIT_VIDEO_API";
// Any mpv error code: the fake returns it from the failing gpu-next create.
constexpr int kCreateError = MPV_ERROR_UNSUPPORTED;

// --- Portable fd helpers -------------------------------------------------------

/// An fd for the null device: any valid descriptor will do, the test only
/// follows its identity and lifetime.
int OpenNullFd() {
#if defined(_WIN32)
  int fd = -1;
  if (_sopen_s(&fd, "NUL", _O_RDONLY, _SH_DENYNO, 0) != 0) return -1;
  return fd;
#else
  return open("/dev/null", O_RDONLY | O_CLOEXEC);
#endif
}

void CloseNullFd(int fd) {
#if defined(_WIN32)
  _close(fd);
#else
  close(fd);
#endif
}

/// Whether [fd] is still an open descriptor. Linux only: Windows has no
/// probe without side effects, so the closes-once check carries it there.
bool FdIsOpen(int fd) {
#if defined(__linux__)
  return fcntl(fd, F_GETFD) != -1;
#else
  (void)fd;
  return true;
#endif
}

// --- DRM-RESOLVE ---------------------------------------------------------------

int g_resolve_cases = 0;
bool g_resolve_ok = true;

void ResolveCheck(bool condition, const std::string& what) {
  g_resolve_cases++;
  if (condition) return;
  std::printf("DRM-RESOLVE mismatch: %s\n", what.c_str());
  g_resolve_ok = false;
}

void ResolvePortable() {
  using mpv_kit::IsRenderNodePath;
  ResolveCheck(IsRenderNodePath("/dev/dri/renderD128"), "renderD128 accepted");
  ResolveCheck(IsRenderNodePath("/dev/dri/renderD0"), "renderD0 accepted");
  ResolveCheck(!IsRenderNodePath("/dev/dri/card0"), "primary node refused");
  ResolveCheck(!IsRenderNodePath("/dev/dri/renderD"), "no digits refused");
  ResolveCheck(!IsRenderNodePath("/dev/dri/renderD12a"),
               "trailing letter refused");
  ResolveCheck(!IsRenderNodePath("/dev/dri/renderD128/../card0"),
               "traversal refused");
  ResolveCheck(!IsRenderNodePath("/tmp/renderD128"), "other directory refused");
  ResolveCheck(!IsRenderNodePath("/dev/dri/renderD123456"),
               "six digits refused");
  ResolveCheck(!IsRenderNodePath(""), "empty refused");

  mpv_opengl_drm_params_v2 params;
  std::memset(&params, 0x5a, sizeof params);
  mpv_kit::FillDrmDisplayParams(7, &params);
  ResolveCheck(params.fd == -1 && params.crtc_id == 0 &&
                   params.connector_id == 0 &&
                   params.atomic_request_ptr == nullptr &&
                   params.render_fd == 7,
               "FillDrmDisplayParams fields");
}

#if defined(__linux__)

/// Creates a symlink [dir]/[name] -> /dev/null; false on failure.
bool LinkNull(const std::string& dir, const char* name) {
  return symlink("/dev/null", (dir + "/" + name).c_str()) == 0;
}

void ResolveLinux() {
  using mpv_kit::OpenRenderNode;
  using mpv_kit::RenderNodePathForDevnum;
  struct stat null_stat;
  if (stat("/dev/null", &null_stat) != 0) {
    ResolveCheck(false, "stat /dev/null");
    return;
  }
  const uint32_t null_major = major(null_stat.st_rdev);
  const uint32_t null_minor = minor(null_stat.st_rdev);

  std::string why;
  ResolveCheck(
      RenderNodePathForDevnum("/nonexistent-mpv-kit-dir", 1, 1, &why).empty() &&
          !why.empty(),
      "missing directory gives no path and a reason");

  char tmpl[] = "/tmp/mpv_kit_drm_XXXXXX";
  const char* made = mkdtemp(tmpl);
  if (!made) {
    ResolveCheck(false, "mkdtemp");
    return;
  }
  const std::string dir = made;

  // A regular file named like a node is not a character device.
  const std::string plain = dir + "/renderD128";
  std::FILE* f = std::fopen(plain.c_str(), "w");
  if (f) std::fclose(f);
  why.clear();
  ResolveCheck(
      f != nullptr &&
          RenderNodePathForDevnum(dir.c_str(), null_major, null_minor, &why)
              .empty() &&
          !why.empty(),
      "regular file renderD128 is not a render node");

  // Names that are not renderD<digits> are ignored even if they are devices.
  const bool linked_other = LinkNull(dir, "card0") && LinkNull(dir, "renderDx");
  why.clear();
  ResolveCheck(
      linked_other &&
          RenderNodePathForDevnum(dir.c_str(), null_major, null_minor, &why)
              .empty(),
      "card0 and renderDx are ignored");

  // The character device renderD200 is found by its device number only.
  const bool linked = LinkNull(dir, "renderD200");
  why.clear();
  ResolveCheck(linked && RenderNodePathForDevnum(dir.c_str(), null_major,
                                                 null_minor, &why) ==
                             dir + "/renderD200",
               "device number match returns the path");
  why.clear();
  ResolveCheck(RenderNodePathForDevnum(dir.c_str(), null_major,
                                       null_minor + 1, &why)
                       .empty() &&
                   !why.empty(),
               "other device number gives no path and a reason");

  // The temporary path is outside /dev/dri: never opened.
  why.clear();
  ResolveCheck(OpenRenderNode(dir + "/renderD200", &why) == -1 &&
                   why == "not a DRM render node path",
               "path outside /dev/dri refused by OpenRenderNode");
  // Allowlisted but absent: a clean failure with a reason.
  why.clear();
  ResolveCheck(OpenRenderNode("/dev/dri/renderD99999", &why) == -1 &&
                   !why.empty(),
               "absent allowlisted node fails with a reason");

  for (const char* name : {"renderD128", "card0", "renderDx", "renderD200"})
    unlink((dir + "/" + name).c_str());
  rmdir(dir.c_str());
}

#endif  // __linux__

// --- DRM-PARAMS: the recording libmpv and interop ----------------------------

/// One mpv_render_context_create call as the backend made it.
struct CreateRecord {
  std::string renderer;  // MPV_RENDER_PARAM_VULKAN_RENDERER, "" if absent
  bool has_drm = false;
  mpv_opengl_drm_params_v2 drm{};  // copy, as libmpv copies it
};

std::mutex g_mu;
std::vector<CreateRecord> g_creates;
std::vector<std::string> g_events;  // "free" and "close", in order
mpv_kit::MpvApi g_real;             // the harness's fake libmpv
mpv_kit::MpvApi g_api;              // g_real with create/free recorded

int RecordingCreate(mpv_render_context** out, mpv_handle* handle,
                    mpv_render_param* params) {
  CreateRecord rec;
  if (const char* renderer = static_cast<const char*>(
          golden::FindParam(params, MPV_RENDER_PARAM_VULKAN_RENDERER)))
    rec.renderer = renderer;
  if (void* drm = golden::FindParam(params, MPV_RENDER_PARAM_DRM_DISPLAY_V2)) {
    rec.has_drm = true;
    std::memcpy(&rec.drm, drm, sizeof rec.drm);
  }
  {
    std::lock_guard<std::mutex> lock(g_mu);
    g_creates.push_back(rec);
  }
  return g_real.render_context_create(out, handle, params);
}

void RecordingFree(mpv_render_context* ctx) {
  {
    std::lock_guard<std::mutex> lock(g_mu);
    g_events.push_back("free");
  }
  g_real.render_context_free(ctx);
}

/// Vulkan interop that hands out an fd for the null device (or -1) and
/// checks what the backend does with it.
class DrmVulkanInterop : public golden::FakeVulkanInterop {
 public:
  explicit DrmVulkanInterop(bool with_node) : with_node_(with_node) {}

  int OpenDrmRenderNode(VkPhysicalDevice) override {
    std::lock_guard<std::mutex> lock(g_mu);
    opens_++;
    fd_ = with_node_ ? OpenNullFd() : -1;
    return fd_;
  }

  void CloseDrmRenderNode(int fd) override {
    std::lock_guard<std::mutex> lock(g_mu);
    closes_++;
    closed_fd_ = fd;
    open_at_close_ = FdIsOpen(fd);
    g_events.push_back("close");
    CloseNullFd(fd);
  }

  int opens() const { return Locked(opens_); }
  int closes() const { return Locked(closes_); }
  int fd() const { return Locked(fd_); }
  int closed_fd() const { return Locked(closed_fd_); }
  bool open_at_close() const { return Locked(open_at_close_); }

 private:
  template <typename T>
  T Locked(const T& value) const {
    std::lock_guard<std::mutex> lock(g_mu);
    return value;
  }

  const bool with_node_;
  int opens_ = 0;
  int closes_ = 0;
  int fd_ = -1;
  int closed_fd_ = -2;
  bool open_at_close_ = false;
};

/// A platform with the DRM-aware Vulkan interop and the renderers on it.
struct Rig {
  explicit Rig(bool with_node)
      : vk(with_node), interop(2, false, nullptr, &vk) {}

  std::unique_ptr<VideoRenderer> NewRenderer() {
    return std::make_unique<VideoRenderer>(
        g_api, golden::FakeHandle(), &interop, [](const std::string&) {},
        [](const char*, const std::string&) {});
  }

  DrmVulkanInterop vk;
  golden::FakeInterop interop;
};

/// State of one running scenario.
struct Run {
  explicit Run(const char* scenario) : name(scenario) {}

  const char* name;
  bool ok = true;

  void Check(bool condition, const std::string& what) {
    if (condition) return;
    std::printf("DRM-PARAMS mismatch scenario=%s: %s\n", name, what.c_str());
    ok = false;
  }
};

std::vector<CreateRecord> Creates() {
  std::lock_guard<std::mutex> lock(g_mu);
  return g_creates;
}

/// Whether [rec] carries DRM_DISPLAY_V2 as the host contract defines it, with
/// [fd] as the render node.
bool HasDrmParams(const CreateRecord& rec, int fd) {
  return rec.has_drm && rec.drm.fd == -1 && rec.drm.crtc_id == 0 &&
         rec.drm.connector_id == 0 && rec.drm.atomic_request_ptr == nullptr &&
         rec.drm.render_fd == fd && fd >= 0;
}

/// Starts a renderer (auto choice) and checks it won on the Vulkan backend.
bool StartVulkan(Run& run, Rig& rig, std::unique_ptr<VideoRenderer>* r) {
  *r = rig.NewRenderer();
  const bool started = (*r)->Start(RendererChoice::kAuto);
  run.Check(started && (*r)->backend() == mpv_kit::Backend::kVulkan,
            "Vulkan backend started: " + (*r)->backend_reason());
  return started;
}

/// Destroys [r] the way the plugin does (the render thread frees the context,
/// then the backend goes) and checks that no fake image leaked.
void Teardown(Run& run, std::unique_ptr<VideoRenderer>* r) {
  golden::Fake().SignalPending();
  r->reset();
  if (golden::Images().live() != 0)
    run.Check(false, std::to_string(golden::Images().live()) +
                         " image(s) never destroyed");
  for (const std::string& v : golden::Images().TakeViolations())
    run.Check(false, v);
}

// --- Scenarios ---------------------------------------------------------------

void DrmFd(Run& run) {
  Rig rig(true);
  std::unique_ptr<VideoRenderer> r;
  StartVulkan(run, rig, &r);
  const std::vector<CreateRecord> creates = Creates();
  run.Check(creates.size() == 1, "one create, got " +
                                     std::to_string(creates.size()));
  if (!creates.empty()) {
    run.Check(creates[0].renderer == "gpu-next", "gpu-next create");
    run.Check(HasDrmParams(creates[0], rig.vk.fd()),
              "gpu-next create carries DRM_DISPLAY_V2 with the injected fd");
  }
  run.Check(rig.vk.opens() == 1, "OpenDrmRenderNode called once");
  run.Check(rig.vk.closes() == 0, "fd still open while the renderer runs");
  Teardown(run, &r);
}

void DrmFdFallback(Run& run) {
  Rig rig(true);
  golden::Fake().SetCreateResult(MPV_RENDER_API_TYPE_VULKAN, "gpu-next",
                                 kCreateError);
  std::unique_ptr<VideoRenderer> r;
  StartVulkan(run, rig, &r);
  const std::vector<CreateRecord> creates = Creates();
  run.Check(creates.size() == 2, "two creates, got " +
                                     std::to_string(creates.size()));
  for (const CreateRecord& rec : creates)
    run.Check(HasDrmParams(rec, rig.vk.fd()),
              "create of renderer '" + rec.renderer +
                  "' carries DRM_DISPLAY_V2 with the injected fd");
  if (creates.size() == 2)
    run.Check(creates[0].renderer == "gpu-next" && creates[1].renderer == "gpu",
              "gpu-next then gpu");
  run.Check(rig.vk.opens() == 1, "OpenDrmRenderNode called once in total");
  Teardown(run, &r);
}

void DrmNone(Run& run) {
  Rig rig(false);
  golden::Fake().SetCreateResult(MPV_RENDER_API_TYPE_VULKAN, "gpu-next",
                                 kCreateError);
  std::unique_ptr<VideoRenderer> r;
  StartVulkan(run, rig, &r);
  const std::vector<CreateRecord> creates = Creates();
  run.Check(creates.size() == 2, "two creates, got " +
                                     std::to_string(creates.size()));
  for (const CreateRecord& rec : creates)
    run.Check(!rec.has_drm, "create of renderer '" + rec.renderer +
                                "' has no DRM_DISPLAY_V2 without a node");
  run.Check(rig.vk.opens() == 1, "OpenDrmRenderNode asked once");
  Teardown(run, &r);
  run.Check(rig.vk.closes() == 0, "nothing to close without a node");
}

void DrmClose(Run& run) {
  Rig rig(true);
  std::unique_ptr<VideoRenderer> r;
  StartVulkan(run, rig, &r);
  const int fd = rig.vk.fd();
  run.Check(fd >= 0, "interop handed out an fd");
  run.Check(rig.vk.closes() == 0, "not closed before destruction");
  Teardown(run, &r);
  run.Check(rig.vk.closes() == 1, "closed exactly once, got " +
                                      std::to_string(rig.vk.closes()));
  run.Check(rig.vk.closed_fd() == fd, "the injected fd is the one closed");
  run.Check(rig.vk.open_at_close(), "fd was still open when it was closed");
  std::lock_guard<std::mutex> lock(g_mu);
  int last_free = -1;
  int close_at = -1;
  for (size_t i = 0; i < g_events.size(); i++) {
    if (g_events[i] == "free") last_free = static_cast<int>(i);
    if (g_events[i] == "close") close_at = static_cast<int>(i);
  }
  run.Check(last_free >= 0, "render context was freed");
  run.Check(close_at > last_free,
            "fd closed after the last render_context_free");
}

struct ScenarioDef {
  const char* name;
  void (*fn)(Run&);
};

const ScenarioDef kScenarios[] = {
    {"drm-fd", DrmFd},
    {"drm-fd-fallback", DrmFdFallback},
    {"drm-none", DrmNone},
    {"drm-close", DrmClose},
};

void ResetState() {
  golden::Fake().Reset();
  golden::Images().Reset();
  std::lock_guard<std::mutex> lock(g_mu);
  g_creates.clear();
  g_events.clear();
}

/// Same probe as golden_vk: skip only when the loader, an instance or a
/// Vulkan 1.3 device is missing. Returns the reason to skip, or "" to run.
std::string Probe() {
  ResetState();
  std::string skip;
  Rig rig(false);
  std::unique_ptr<VideoRenderer> r = rig.NewRenderer();
  r->Start(RendererChoice::kGpuNext);
  const std::string reason = r->backend_reason();
  if (r->backend() != mpv_kit::Backend::kVulkan &&
      (reason.find("Vulkan loader") != std::string::npos ||
       reason.find("vkCreateInstance failed") != std::string::npos ||
       reason.find("no Vulkan 1.3 device") != std::string::npos ||
       reason.find("Vulkan < 1.3 on") != std::string::npos))
    skip = reason;
  golden::Fake().SignalPending();
  r.reset();
  return skip;
}

}  // namespace

int main() {
  std::setvbuf(stdout, nullptr, _IONBF, 0);
  std::setvbuf(stderr, nullptr, _IONBF, 0);

  ResolvePortable();
#if defined(__linux__)
  ResolveLinux();
#endif
  if (g_resolve_ok) std::printf("DRM-RESOLVE ok cases=%d\n", g_resolve_cases);

  g_real = golden::MakeApi();
  g_api = g_real;
  g_api.render_context_create = &RecordingCreate;
  g_api.render_context_free = &RecordingFree;
  // The scenarios own the variable: whatever the caller set is ignored.
  golden::SetEnv(kApiVariable, nullptr);

  const std::string vk_skip = Probe();
  if (!vk_skip.empty()) {
    std::printf("DRM-PARAMS vk scenarios skipped: %s\n", vk_skip.c_str());
    return g_resolve_ok ? 0 : 1;
  }
  int ran = 0;
  bool ok = true;
  for (const ScenarioDef& def : kScenarios) {
    ResetState();
    Run run(def.name);
    try {
      def.fn(run);
    } catch (const std::exception& e) {
      std::printf("DRM-PARAMS mismatch scenario=%s: waiting for %s\n",
                  def.name, e.what());
      run.ok = false;
    }
    ran++;
    if (!run.ok) ok = false;
  }
  if (ok) std::printf("DRM-PARAMS ok scenarios=%d\n", ran);
  return ok && g_resolve_ok ? 0 : 1;
}

// DRM render node helpers for VA-API zero-copy (Phase 16, HWD-03).
//
// mpv's hwdec_vaapi opens its VA display from the render node fd carried by
// MPV_RENDER_PARAM_DRM_DISPLAY_V2 (`render_fd`, hwdec_vaapi.c): x11 and
// wayland are compiled out of the bundle, so this is the only display source.
// libmpv copies the struct but does not dup the fd, so the host owns the fd
// and must close it only after mpv_render_context_free.
//
// Header-only and thread-agnostic, like linux_candidates.h. The portable part
// (struct filling, path allowlist) compiles everywhere so the native test
// runs it on every platform; the lookup and open functions exist only on
// Linux. Security: only /dev/dri/renderD<N> is ever opened (a render node has
// no KMS privileges), and the path comes from a device lookup, never from an
// environment variable or other external input.
#pragma once

#include <cstddef>
#include <string>

#include <mpv/render_gl.h>

#if defined(__linux__)
#include <dirent.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/sysmacros.h>
#include <sys/types.h>
#include <unistd.h>

#include <cerrno>
#include <cstdint>
#include <cstring>
#endif

namespace mpv_kit {

/// Directory the render nodes live in. The only directory ever opened.
constexpr const char* kDrmDirectory = "/dev/dri";

/// Fills the MPV_RENDER_PARAM_DRM_DISPLAY_V2 struct for a render-node-only
/// host: no KMS display (fd -1: mpv then skips the drmprime overlay), no
/// CRTC, connector or atomic request; [render_fd] is the VA-API render node.
inline void FillDrmDisplayParams(int render_fd,
                                 mpv_opengl_drm_params_v2* out) {
  out->fd = -1;
  out->crtc_id = 0;
  out->connector_id = 0;
  out->atomic_request_ptr = nullptr;
  out->render_fd = render_fd;
}

/// Allowlist: exactly `/dev/dri/renderD` followed by 1-5 decimal digits.
/// Rejects primary nodes (`card0`), traversal (`renderD128/../card0`) and
/// every other directory.
inline bool IsRenderNodePath(const std::string& path) {
  constexpr char kPrefix[] = "/dev/dri/renderD";
  constexpr size_t kPrefixLength = sizeof(kPrefix) - 1;
  constexpr size_t kMaxDigits = 5;
  if (path.compare(0, kPrefixLength, kPrefix) != 0) return false;
  const size_t digits = path.size() - kPrefixLength;
  if (digits < 1 || digits > kMaxDigits) return false;
  for (size_t i = kPrefixLength; i < path.size(); i++)
    if (path[i] < '0' || path[i] > '9') return false;
  return true;
}

#if defined(__linux__)

/// Name of a render node entry (`renderD<digits>`), as found in [kDrmDirectory].
inline bool IsRenderNodeName(const char* name) {
  constexpr char kPrefix[] = "renderD";
  constexpr size_t kPrefixLength = sizeof(kPrefix) - 1;
  if (std::strncmp(name, kPrefix, kPrefixLength) != 0) return false;
  const char* digits = name + kPrefixLength;
  if (*digits == '\0') return false;
  for (const char* c = digits; *c != '\0'; c++)
    if (*c < '0' || *c > '9') return false;
  return true;
}

/// `<dir>/renderD<N>` whose character device number is
/// ([dev_major], [dev_minor]) (the `renderMajor`/`renderMinor` of
/// VkPhysicalDeviceDrmPropertiesEXT), or "" with [why] set. Matching by device
/// number, not by name: renderD128 is not necessarily the GPU Flutter renders
/// on (hybrid GPUs). [dir] is a parameter only so the native test can point at
/// a temporary directory; production passes [kDrmDirectory].
inline std::string RenderNodePathForDevnum(const char* dir,
                                           uint32_t dev_major,
                                           uint32_t dev_minor,
                                           std::string* why) {
  DIR* d = opendir(dir);
  if (!d) {
    *why = std::string("cannot open ") + dir + ": " + std::strerror(errno);
    return "";
  }
  std::string found;
  while (const dirent* entry = readdir(d)) {
    if (!IsRenderNodeName(entry->d_name)) continue;
    const std::string path = std::string(dir) + "/" + entry->d_name;
    struct stat st;
    // stat, not lstat: the entry may be a link to the real node.
    if (stat(path.c_str(), &st) != 0 || !S_ISCHR(st.st_mode)) continue;
    if (major(st.st_rdev) == dev_major && minor(st.st_rdev) == dev_minor) {
      found = path;
      break;
    }
  }
  closedir(d);
  if (found.empty())
    *why = "no render node with device number " + std::to_string(dev_major) +
           ":" + std::to_string(dev_minor);
  return found;
}

/// Opens [path] read-write with close-on-exec, or -1 with [why] set. Refuses
/// everything [IsRenderNodePath] refuses, so a bad lookup result can never
/// open a primary node or a file outside /dev/dri.
inline int OpenRenderNode(const std::string& path, std::string* why) {
  if (!IsRenderNodePath(path)) {
    *why = "not a DRM render node path";
    return -1;
  }
  const int fd = open(path.c_str(), O_RDWR | O_CLOEXEC);
  if (fd < 0) *why = "open " + path + ": " + std::strerror(errno);
  return fd;
}

#endif  // __linux__

}  // namespace mpv_kit

## 0.1.0-dev.4

- libmpv: stream-bridge use-after-free on cancel after close, a host-source
  leak and seek desynchronisation fixed (patch 0006); render failures are
  reported instead of silently succeeding (0001/0004); CoreAudio NULL-string
  crashes fixed (0007); four upstream mpv fixes backported (0009).
- libplacebo 7.360.1 with 14 upstream fixes (Vulkan command races,
  external-image hand-off, pl_queue lifetime, memory safety).
- The bundles are the v0.1.0-dev.4 release (`bundleTag`). Patch changes since
  v0.1.0-dev.3: 0010 adds the Direct3D 11 render API, 0012 builds the Linux
  libmpv against libdrm 2.4.113, 0008 (vendor integration fixes) and 0009
  (upstream backports) are new, 0004 is now
  `libmpv-gpu-next-render-backend-and-renderer-report` and absorbs 0005.
  Windows libmpv gains the Direct3D 11 render API; the Windows bundle adds
  `libshaderc_shared.dll` and `libspirv-cross-c-shared.dll` (with their
  `licenses/shaderc` and `licenses/spirv-cross` entries). Linux libmpv is
  built with OpenGL/EGL and needs the host `libEGL.so.1` (libglvnd), so a
  host without libEGL cannot load it. macOS has no backend change.
- The build hook reuses a cached bundle only when its extracted `lib/`
  directory still holds shared libraries, so a stale `{target}.ok` stamp left
  by a cleaned cache now leads to a reinstall from the verified archive (or a
  fresh download) instead of silently bundling no libmpv; a pinned bundle that
  yields no shared libraries now fails the build with
  `BundleIntegrityException`.

## 0.1.0-dev.3

- Windows: the bundled libmpv now includes the Vulkan render API. The
  0.1.0-dev.1/dev.2 Windows builds were configured without it (mpv's
  Vulkan header check failed against MSYS2's include directory and meson
  disabled the feature silently), so mpv_kit_video always fell back to
  software rendering there. The build now uses the pinned Vulkan headers
  and fails if libmpv is configured without Vulkan or libplacebo.

## 0.1.0-dev.2

- macOS: apps using the bundles build again. The 0.1.0-dev.1 dylibs (the
  official MoltenVK dylib and FFmpeg) had too little Mach-O header space
  for Flutter's install-name rewrite ("larger updated load commands do not
  fit"). All dylibs now link with `-headerpad_max_install_names`; MoltenVK
  is relinked from its static library for one architecture
  (arm64 10.9 MB → 3.8 MB).
- libmpv patch 0007 fixes two crashes when listing audio devices
  (`audio-device-list`):
  - macOS: CoreAudio device enumeration called a NULL import;
    `cfstr_get_cstr`, Foundation, libobjc and Metal are now really linked.
  - Windows: disposing a player after enumeration released WASAPI
    objects whose COM apartment had already ended.
  libmpv is now linked with `b_lundef=true`, so a missing symbol fails the
  build instead of crashing at run time.

## 0.1.0-dev.1

- Bundles are built from pinned sources (native/build/deps.sh, build.sh)
  and run on Windows 10+, macOS 12+ and Linux with glibc 2.35+; 14–17 MB
  per target compressed. Linux bundles include PulseAudio/ALSA output and
  VA-API; all bundles include uchardet (subtitle charset detection).
  Every bundle passes the Dart test suite and a ~40-format playback matrix
  before it is published.
- Build hook that bundles a prebuilt LGPL libmpv (mpv 0.41.0 with the
  mpv_kit patches, FFmpeg 8.1.3) and its dependency closure for
  windows/linux/macos × x64/arm64.
- Downloads the GitHub release bundle for the target, verifies the archive
  against a pinned sha256 and every file against the bundle's
  `MANIFEST.txt`; nothing is executed during the build.
- `libmpv_bundle` hook user define for a local bundle archive or
  directory.
- Emits no assets when no release is pinned or no bundle exists for the
  target, so mpv_kit falls back to `MPV_KIT_LIBMPV_PATH` / a system libmpv.

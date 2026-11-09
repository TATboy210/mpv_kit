## 0.1.2

- Changed: `crypto` lower bound raised to `^3.0.8`; no behavior change.

## 0.1.1

- Packaging now strips Linux and macOS shared libraries at the bundle
  boundary (`strip --strip-unneeded` on Linux, `strip -x` before `codesign`
  on macOS). The 0.1.1 candidates still carried 6.5–6.9 MiB (Linux) and
  ~1.1 MiB (macOS) of removable symbol/debug sections; Windows was already
  stripped. The P3 rebuild is 6.5–6.8 MiB (Linux) and ~0.47 MiB (macOS)
  smaller unpacked; compressed artifacts shrank by 2.8–2.9 MB and ~0.1 MB.
  No library version, feature set or license change; the GPL-3.0+ full
  bundle and the six-target contract are unchanged.

## 0.1.0-dev.10

- The released bundle is now the **GPL-3.0-or-later full flavor**: mpv 0.42.0,
  libplacebo 7.387.0, FFmpeg 8.1.3 (LGPL) and the optical-disc stack.
  - CD-DA through libcdio; DVD-Video menus through libdvdnav/libdvdread
    (with libdvdcss); DVD-Audio through libdvdread; Blu-ray/UHD HDMV through
    libbluray with AACS/BD+ helpers (libaacs/libbdplus; user supplies KEYDB).
  - BD-J is not included (no JVM). VCD has no `vcd://` module; play
    `MPEGAV/*.DAT` files directly.
  - libcurl HTTP/2 backend (mbedTLS + nghttp2). `Player` keeps it disabled
    by default; enable with `curl-enabled=yes`.
- **License change:** applications shipping this bundle must be
  GPL-compatible. The Dart packages remain MIT. `MPV_KIT_FLAVOR=lgpl` keeps
  the old `-Dgpl=false` build for self-builders; the release pipeline does
  not publish it.
- Every bundle now carries `LICENSE.GPL`, `LICENSE.LGPL`, `SOURCE.txt` and the
  third-party licenses; releases also carry `sources-<tag>.tar.gz`.
- libplacebo moved from 7.360.1 to 7.387.0; the 16 local backports were
  upstreamed and removed.

## 0.1.0-dev.9

- Version bump only; this release changes Dart and plugin code, not libmpv.
  It is pinned to the v0.1.0-dev.9 bundles, rebuilt from the same libmpv
  sources as v0.1.0-dev.8.

## 0.1.0-dev.8

- Version bump only; this release changes Dart and plugin code, not libmpv,
  and stays pinned to the v0.1.0-dev.7 bundles.

## 0.1.0-dev.7

- Version bump only; this release changes plugin and Dart code, not libmpv,
  and stays pinned to the v0.1.0-dev.6 bundles.

## 0.1.0-dev.6

- Version bump only; this release has no native changes and stays pinned to
  the v0.1.0-dev.5 bundles.

## 0.1.0-dev.5

- Pinned to the v0.1.0-dev.5 LGPL bundles: FFmpeg linked with
  `--gc-sections`/`-dead_strip`, MSYS2 DLLs stripped on Windows, mpv built
  without a build date, reproducible `gzip -9n` archives (each target
  0.6-1.3% smaller than dev.4).
- The build hook deletes the cached bundles of older release tags once the
  current pin is installed (each pin bump used to leave 17-70 MB behind).

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
  directory still holds every shared library that `MANIFEST.txt` lists (and the
  manifest itself is present), so a stale `{target}.ok` stamp left by a cleaned
  or partly cleaned cache (an empty `lib/`, or libmpv gone while a dependency
  remains) now leads to a reinstall from the verified archive (or a fresh
  download) instead of silently bundling no libmpv; a pinned bundle that
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

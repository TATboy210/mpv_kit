---
last_mapped_commit: 9f90a45322ab3537941540e6b35a76d978669ef5
last_mapped_at: 2026-10-23
---
# External Integrations

**Analysis Date:** 2026-10-23

## APIs & External Services

**Media engine (native library):**
- libmpv 0.41.0 (client API 2.5) — the entire playback engine, loaded at runtime via `dart:ffi`.
  - SDK/Client: in-repo hand-written bindings, `packages/mpv_kit/lib/src/ffi/bindings.dart`
  - Loader: `packages/mpv_kit/lib/src/ffi/library.dart` (`MpvLibrary.open`)
  - Resolution order: explicit `path` → `MPV_KIT_LIBMPV_PATH` → platform default names:
    - Windows: `libmpv-2.dll`, `mpv-2.dll`
    - macOS: `@rpath/mpv.2.framework/mpv.2`, `libmpv.2.dylib`, `libmpv.dylib`
    - Linux: `libmpv.so.2`, `libmpv.so`
  - Compatibility gate: client API major version must be 2 (`MpvLibrary.requiredMajor`).
  - The library is loaded once per process and cached in `MpvLibrary._bindings`; it is never unloaded.

**Prebuilt binary distribution (GitHub Releases):**
- `mpv_kit_libs` downloads `libmpv-<target>.tar.gz` from `https://github.com/TATboy210/mpv_kit/releases/download/v0.1.0-dev.3/`.
  - SDK/Client: `dart:io` `HttpClient` in `packages/mpv_kit_libs/lib/src/bundle.dart`
  - Auth: none (public release assets)
  - Integrity: pinned sha256 per target in `packages/mpv_kit_libs/lib/src/bundles.dart`, plus per-file `MANIFEST.txt` verification in `verifyEntries`
  - Offline override: `libmpv_bundle` build user-define (`packages/mpv_kit_libs/hook/build.dart`)
  - Proxy: `HTTPS_PROXY` / `HTTP_PROXY` / `NO_PROXY` via `HttpClient.findProxyFromEnvironment`

**Flutter platform channel:**
- Method channel `mpv_kit_video` between `packages/mpv_kit_video/lib/src/video_controller.dart` and each platform plugin.
  - Dart → native: `create {handle, symbols, renderer}`, `setSize {textureId,width,height}`, `setIccProfile {textureId,profile}`, `dispose {textureId}`, `getDisplayRefreshRate` (Windows only, `packages/mpv_kit_video/windows/mpv_kit_video_plugin.cpp:118`).
  - Native → Dart: `event {textureId, kind, message}` handled by `_installHandler`.
  - Contract documented in `packages/mpv_kit_video/windows/mpv_kit_video_plugin.cpp` and `packages/mpv_kit_video/linux/mpv_kit_video_plugin.cc`.
- Custom stream protocol bridge — Dart supplies `MpvStreamSource` implementations through `Mpv.registerStreamProtocol`; mpv's demuxer thread blocks while Dart answers `open`/`read`/`seek`/`close` (`packages/mpv_kit/lib/src/core/stream_bridge.dart`, native patch `native/patches/0006-libmpv-asynchronous-stream-bridge.patch`).

**GPU / rendering APIs:**
- Vulkan 1.3 through `mpv/render_vk.h` and volk (`packages/mpv_kit_video/third_party/volk`); loader resolved at runtime (host `libvulkan.so.1`/`vulkan-1.dll`, direct MoltenVK link on macOS).
- Windows: D3D11 + DXGI external-memory interop, `VK_EXTERNAL_MEMORY_HANDLE_TYPE_D3D11_TEXTURE_KMT_BIT` (`packages/mpv_kit_video/windows/d3d11_interop.cpp`); textures exposed to Flutter through `FlTextureRegistrar` / pixel-buffer textures.
- Linux: EGL + OpenGL texture mirrors via libepoxy (`packages/mpv_kit_video/linux/gl_interop.cc`, links `PkgConfig::EPOXY`, GTK).
- macOS: Metal / IOSurface / CVPixelBuffer through MoltenVK (`packages/mpv_kit_video/macos/Classes/metal_interop.mm`, frameworks `Metal`, `CoreVideo`, `IOSurface`).
- Codec acceleration: VA-API (Linux, render nodes only), VideoToolbox (macOS), D3D11VA/DXVA2 (Windows) — configured in `native/build/build.sh` and `native/build/ffmpeg.sh`.

**Audio output:**
- Windows WASAPI, macOS CoreAudio, Linux PulseAudio/ALSA/PipeWire (`native/build/build.sh` Meson flags).

**Network media sources (indirect):**
- Playback of remote URLs is handled inside libmpv/FFmpeg, not by Dart code. mpv is built with `-Dlibcurl=disabled`, so HTTP(S) and other protocols use FFmpeg's built-in network layer (OpenSSL linked on Linux, system TLS on other targets).
- mpv's built-in command execution surfaces are disabled by default for embedded use: `Mpv.secureDefaultOptions` sets `config=no`, `load-scripts=no`, `ytdl=no`, `osc=no`, default key bindings off (`packages/mpv_kit/lib/src/core/mpv.dart:87`).

## Data Storage

**Databases:**
- None. No database drivers, ORM, or persistence layer exists in any package.

**File Storage:**
- Local filesystem only. Playback reads user-chosen media paths (`Player.open`).
- Compiled shader cache written to a per-user directory set as `gpu-shader-cache-dir` (`MpvVideoController.defaultShaderCacheDir`, `packages/mpv_kit_video/lib/src/video_controller.dart:254`), based on `LOCALAPPDATA` / platform cache conventions.
- Bundles extracted under the Flutter build output's shared directory (`packages/mpv_kit_libs/hook/build.dart`).

**Caching:**
- libmpv GPU shader cache (persistent, on-disk; patch `0003-libmpv_vk-persistent-shader-cache.patch`).
- In-memory event/property state in `Mpv` and `Player`; no external cache service.

## Authentication & Identity

**Auth Provider:**
- Not applicable. The project implements no user authentication, accounts, tokens, or identity provider integration.

## Monitoring & Observability

**Error Tracking:**
- None (no Sentry/Crashlytics or equivalent).

**Logs:**
- mpv log messages surface as typed events through `Mpv` (`packages/mpv_kit/lib/src/core/events.dart`) and mpv's `log-message` stream.
- Dart-side diagnostics use `debugPrint` (`packages/mpv_kit_video/lib/src/video_controller.dart`).
- Example app optionally mirrors logs to a file via `MPV_KIT_EXAMPLE_LOG` (`example/lib/main.dart`).
- CI emits coverage and test logs as GitHub Actions annotations.

## CI/CD & Deployment

**Hosting:**
- Libraries are published to pub.dev as `mpv_kit`, `mpv_kit_video`, `mpv_kit_libs` (per package metadata in each `pubspec.yaml`); native binaries are published to GitHub Releases.
- Published to: `https://github.com/TATboy210/mpv_kit`.

**CI Pipeline:**
- GitHub Actions (`.github/workflows/`):
  - `flutter-plugin.yml` — matrix Linux/Windows/macOS, `flutter analyze --fatal-infos`, `flutter test`, debug build of `example`.
  - `native-verify.yml` — builds patched libmpv on Linux x64/arm64, macOS arm64/x64, Windows x64/arm64 (MSYS2 CLANG64/CLANGARM64); ABI audit against `tools/rea_abi_audit/expected_symbols.txt`; Vulkan smoke tests via lavapipe/MoltenVK; Dart tests with an 80% coverage gate; ASan/UBSan job.
  - `release.yml` — on `v*` tags builds LGPL bundles on six targets, audits licenses/ABI, tests the packaged bundle with the build prefix hidden, and publishes tarballs plus `SHA256SUMS` via `gh release create`.
- External CI inputs pinned or verified: Mesa lavapipe 26.2.4 from the `pal1000/mesa-dist-win` release (sha256 checked), FFmpeg 8.1.3 tarball from `ffmpeg.org` (sha256 checked), dependency sources from KhronosGroup, VideoLAN, SourceForge, GitHub, and freedesktop GitLab (each sha256 checked in `native/build/deps.sh`).

## Environment Configuration

**Required env vars:**
- None are mandatory for building. At runtime, one of these supplies libmpv: a pinned bundle (default), `MPV_KIT_LIBMPV_PATH`, or a system-installed libmpv with the default name.

**Optional env vars:**
- `MPV_KIT_LIBMPV_PATH` — libmpv location override.
- `MPV_KIT_VIDEO_RENDERER` — `auto` | `gpu-next` | `gpu` | `software`.
- `MPV_KIT_FORMAT_SAMPLES` — directory of generated samples for `packages/mpv_kit/test/format_matrix_test.dart`.
- `HTTPS_PROXY` / `HTTP_PROXY` / `NO_PROXY` — bundle download and `tools/pin_bundles.dart`.
- `MPV_KIT_EXAMPLE_AO`, `MPV_KIT_EXAMPLE_LOG` — example app audio driver / log file path.
- `MACOSX_DEPLOYMENT_TARGET` — native build baseline (defaults to 12.0).

**Secrets location:**
- No secrets are stored in the repository; there are no `.env` files or credential files. CI uses the implicit `GITHUB_TOKEN` (`permissions: contents: write` only in the release `publish` job) and no third-party API keys.
- Integrity pins (bundle and dependency sha256 hashes) are intentionally committed in `packages/mpv_kit_libs/lib/src/bundles.dart`, `native/build/deps.sh`, and `native/build/ffmpeg.sh`.

## Webhooks & Callbacks

**Incoming:**
- None. No HTTP server or webhook endpoint exists.

**Outgoing:**
- HTTPS downloads only: GitHub release assets (`packages/mpv_kit_libs/lib/src/bundle.dart`, `tools/pin_bundles.dart`) and, during native builds, source tarballs fetched by `native/build/deps.sh` / `ffmpeg.sh`. CI additionally downloads Mesa lavapipe.
- Media stream callbacks are in-process: mpv wakeup callback → `NativeCallable.listener` (`packages/mpv_kit/lib/src/core/mpv.dart`), render update callback → render thread (`packages/mpv_kit_video/src/video_renderer.cc`), and Flutter texture frame callbacks (`FrameReady` / `AcquireFront`).

---

*Integration audit: 2026-10-23*

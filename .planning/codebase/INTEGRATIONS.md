---
last_mapped_commit: cd47d6761925b8ccb49e153864bf9789dc3f5039
last_mapped_at: 2026-10-27
---
# External Integrations

**Analysis Date:** 2026-10-27

## APIs & External Services

**Binary distribution:**
- GitHub Releases is the source of the prebuilt libmpv bundles. The URL is `https://github.com/TATboy210/mpv_kit/releases/download/<bundleTag>/libmpv-<target>.tar.gz`.
  - SDK/Client: `dart:io` HttpClient in `packages/mpv_kit_libs/lib/src/bundle.dart`, which honors proxy environment variables. URLs and pins are in `packages/mpv_kit_libs/lib/src/bundles.dart`.
  - Integrity: every bundle is checked against a pinned sha256 (`crypto`). A mismatch throws `BundleIntegrityException`. Archives are extracted by the in-house tar reader in `packages/mpv_kit_libs/lib/src/tar.dart`.
  - Auth: none (public assets).
  - Pin refresh: `tools/pin_bundles.dart` reads the release's `SHA256SUMS`.

**Native libraries (in-process):**
- libmpv is accessed through FFI (`packages/mpv_kit/lib/src/ffi/`). The plugin receives the handle and the render symbol addresses over `MethodChannel('mpv_kit_video')`, then loads them in `packages/mpv_kit_video/src/mpv_api.h`.
- Platform graphics interop:
  - Windows: D3D11 shared textures (`packages/mpv_kit_video/windows/d3d11_interop.cpp`).
  - Linux: GL memory objects (`linux/gl_interop.cc`).
  - macOS: IOSurface/Metal (`macos/Classes/metal_interop.mm`).
- Custom `protocol://` streams are served from Dart (`packages/mpv_kit/lib/src/core/stream_bridge.dart`).

## Data Storage

**Databases:**
- Not applicable.

**File Storage:**
- Local filesystem only. Bundles are extracted into the hook output directory, and the shader cache defaults to `defaultShaderCacheDir` in `packages/mpv_kit_video/lib/src/video_controller.dart`.

**Caching:**
- The persistent Vulkan shader cache comes from patch `native/patches/0003-libmpv_vk-persistent-shader-cache.patch`.

## Authentication & Identity

**Auth Provider:**
- Not applicable.

## Monitoring & Observability

**Error Tracking:**
- None. Diagnostics are delivered as data: the `MpvVideoEvent` stream, `Player.errors` and `Player.logs`.

**Logs:**
- libmpv logs are exposed through `Player.logs`. The controller prints one line per creation (`video_controller.dart`).

## CI/CD & Deployment

**Hosting:**
- Packages are intended for pub.dev (`repository: https://github.com/TATboy210/mpv_kit`). Binaries are published on GitHub Releases.

**CI Pipeline:**
- GitHub Actions:
  - `.github/workflows/flutter-plugin.yml`: plugin build, analyze and test on Linux, Windows and macOS.
  - `.github/workflows/native-verify.yml`: libmpv build, ABI audit, smoke tests, Dart tests with an 80% coverage gate, and sanitizers.
  - `.github/workflows/release.yml`: six-target LGPL bundles published when a `v*` tag is pushed.

## Environment Configuration

**Required env vars:**
- None are strictly required. `MPV_KIT_LIBMPV_PATH` is needed when no bundle is pinned for the target. See `STACK.md` for the full list.

**Secrets location:**
- No secrets are stored in the repo. CI uses the GitHub-provided token for release uploads.

## Webhooks & Callbacks

**Incoming:**
- None over the network. In-process callbacks are the mpv wakeup and stream callbacks delivered through `NativeCallable.listener`, and the native render events marshalled to the platform thread.

**Outgoing:**
- None.

---

*Integration audit: 2026-10-27*

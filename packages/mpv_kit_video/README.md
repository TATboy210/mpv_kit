# mpv_kit_video

Flutter video output for [mpv_kit](https://pub.dev/packages/mpv_kit).

mpv renders with its own renderer (gl_video + libplacebo) through the
Vulkan render API added by mpv_kit's libmpv patch, directly into images the
Flutter compositor samples — no per-frame copies:

| Platform | Shared image | Flutter texture |
|---|---|---|
| Windows | D3D11 texture (KMT handle) imported into Vulkan | `GpuSurfaceTexture` (DXGI shared handle) |
| Linux | Vulkan `OPAQUE_FD` memory imported with `GL_EXT_memory_object_fd` | `FlTextureGL` |
| macOS | IOSurface `CVPixelBuffer` bound by MoltenVK (`VK_EXT_metal_objects`) | `FlutterTexture` |

If Vulkan 1.3, the interop extensions or a matching GPU are missing, the
plugin falls back to mpv's software renderer; `MpvVideoController.backend`
and `.reason` say which path is active and why.

```dart
final player = Player();
final video = await MpvVideoController.create(player);
await player.open('/path/to/video.mkv');
// in build():
MpvVideo(controller: video, fit: BoxFit.contain);
```

libmpv itself is loaded by `mpv_kit` (bundled binaries or
`MPV_KIT_LIBMPV_PATH`); this plugin never loads a second copy.

## License

MIT for this package. Vendored Vulkan-Headers (Apache-2.0 OR MIT) and volk
(MIT) are listed in `third_party/README.md`.

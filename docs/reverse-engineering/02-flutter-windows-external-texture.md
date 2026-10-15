# Flutter Windows external textures (decompiled)

Target: `flutter_windows.dll` of Flutter 3.47.6 stable (engine artifacts in
`bin/cache/artifacts/engine/windows-x64`), analysed with Ghidra 12.1.4
headless using the shipped `flutter_windows.dll.pdb` (PDB analyzer only,
then targeted decompilation).

## `flutter::ExternalTextureD3d::CreateOrUpdateTexture`

For a `FlutterDesktopGpuSurfaceDescriptor` from our texture callback:

1. If `handle` differs from the last one: `eglReleaseTexImage` +
   `eglDestroySurface` on the old surface, then
   `egl::Manager::CreateSurfaceFromHandle(0x3200 EGL_D3D_TEXTURE_2D_SHARE_HANDLE_ANGLE
   or 0x33A3 EGL_D3D_TEXTURE_ANGLE, handle, {width, height, RGBA texture})`
   and `eglBindTexImage`.
2. Immediately afterwards it calls `release_callback(release_context)`.
3. Returns a GL texture (`GL_TEXTURE_2D`, `GL_RGBA8`) for the compositor.

There is no fence, query, keyed-mutex acquire or flush between our callback
and the compositor's sampling, and the release callback does not mean
"done reading". ANGLE's D3D11 back end reads the texture whenever the
frame's command list executes, i.e. up to the DXGI frame latency later.

## Consequences for mpv_kit

* The renderer must not write into an image the compositor took until it
  can no longer be in flight: quarantine of 4 frames on Windows
  (`D3D11Interop::CompositorLatency`). With 2 frames the first seconds of
  playback, when the GPU is busiest, showed tearing.
* The per-frame CPU wait for mpv's timeline value before publishing a frame
  is the only producer-side guarantee and cannot be dropped on Windows.
* A GPU-side alternative would be `D3D11_RESOURCE_MISC_SHARED_KEYEDMUTEX`
  textures: ANGLE contains `EGL_ANGLE_keyed_mutex` and `SwapChain11` keeps an
  `IDXGIKeyedMutex` for share-handle surfaces. Whether the pbuffer-from-
  client-buffer path acquires it is not verified yet.

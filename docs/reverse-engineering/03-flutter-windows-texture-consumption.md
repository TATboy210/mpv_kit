# Flutter Windows external textures: registration, production, consumption

Target: `flutter_windows.dll` of **Flutter 3.47.8 stable**, the artifact
installed on this machine under
`D:/flutter/bin/cache/artifacts/engine/windows-x64/`.

This report is the Phase 10 deepening of
[02-flutter-windows-external-texture.md](02-flutter-windows-external-texture.md).
Doc 02 established the 3.47.6 picture at symbol level; this document goes to
pseudocode for each of the three paths (D-01) and answers the three driving
questions per path: **does it go through ANGLE, who owns the DXGI device, and
what are the fence semantics**. Settled facts from doc 02 are cited, not
re-derived.

All addresses below are file RVAs (image base `0x180000000`). The raw Ghidra
export, including the complete pseudocode, is
`../.planning/phases/10-composition-spike/evidence/decompilation.txt`.

---

## 1. Target, method, provenance

### 1.1 Artifact pin

| Property | Value |
|---|---|
| Path | `D:/flutter/bin/cache/artifacts/engine/windows-x64/flutter_windows.dll` |
| Size | 46,636,544 bytes |
| sha256 | `9a3a09cabda0fb31b27313394205bdcac62a5211c0d71934d2272313ffb7d170` |
| PDB | `flutter_windows.dll.pdb`, 278,859,776 bytes, same directory |
| SDK | Flutter 3.47.8 stable |
| Framework revision | `737ba8f885` |
| Engine revision / hash | `cf636b1dfb` / `dfd2e6cb7d319db05e3bf1503f3e2ac60f6288a2` |
| Dart | 3.13.7 |
| Decompiler | Ghidra 12.1.4 headless (`D:/ghidra_12.1.4_PUBLIC/support/analyzeHeadless.bat`), PyGhidra 3.1.0 with CPython 3.12.8, JVM heap 8 GB |
| Analysis cost | ~63 minutes wall clock, full auto-analysis with the shipped PDB analyzer |

The artifact was verified by sha256 and byte size before analysis. Nothing was
downloaded for this report. The DLL and PDB are **not** copied into the
repository; only text evidence is committed.

**Excluded stale copy.** `example/windows/flutter/ephemeral/flutter_windows.dll`
exists in this repository's build tree at 46,621,696 bytes with sha256
`b60f6940fdabeca7ea9688448852c705e76dbe6513902651dfb1e92bc1db9fd2`. It is
neither the 3.47.8 SDK artifact nor a previous SDK release artifact; it was
recorded and excluded as an analysis object (threat T-10-03). See
`evidence/engine-3.47.8.sha256.txt`.

### 1.2 Symbols and decompiler caveats

The PDB analyzer resolved **684,430 symbols**, so every target below is
located by its real symbol rather than by anchor-string xref fallback. The
anchor scan was still run as an independent cross-check
(`evidence/engine-3.47.8.anchors.txt`).

Three caveats apply to the pseudocode in `decompilation.txt`:

1. **Identical-code folding (ICF).** Several tiny virtual functions share an
   address. `rx::SurfaceD3D::bindTexImage` and `releaseTexImage` both resolve
   to RVA `0xc2cbe0`, where Ghidra decompiles an unrelated 19-byte function
   (`DeviceVk::initialize`). That address is **not** usable as the bind
   implementation; Path B therefore relies on the production call site in
   `ExternalTextureD3d::CreateOrUpdateTexture` plus ANGLE's public
   `EGL_BindTexImage`/`egl::BindTexImage` wrapper symbols.
2. **Function-ID collisions on callees.** A few indirect/virtual callees are
   mislabeled (`X509_get_notBefore`, `ui::AXTreeObserver::OnNodeDataWillChange`,
   `flutter::AccessibilityBridge::GetTree`, `flutter::FlutterWindowsView::GetEngine`).
   Where a callee name conflicts with the PDB symbol at the primary address,
   the primary symbol wins and the call is described structurally.
3. **One-instruction lambda thunks** at RVAs `0x1900`/`0x1980` are excluded
   from the export (the script filters them).

### 1.3 The `#191017` footnote

The post-fix code shape is present in 3.47.8: `ResolveTexture` dispatches on
`aiks_context` before `context`, and `ResolveTextureSkia` begins with a null
guard. The three relevant engine source files are byte-identical between tags
3.47.6 and 3.47.8. The *commit* that carried #191017 into a release branch was
not identified (the merge commit `bb8568060d` is not an ancestor of either
tag). This is a provenance footnote, not a behavioural doubt; see §7.

---

## 2. The chain at a glance

| Level | Function | RVA | Size | Role |
|---|---|---|---|---|
| A | `flutter::FlutterWindowsTextureRegistrar::RegisterTexture` | `0x1b24c` | 646 B | Validates the surface descriptor, allocates `ExternalTextureD3d` |
| A | `flutter::FlutterWindowsTextureRegistrar::EmplaceTexture` | `0x1b4d2` | 284 B | Takes ownership into `textures_`, returns the texture id |
| B | `flutter::ExternalTextureD3d::PopulateTexture` | `0xea82` | 124 B | Invokes the app callback, fills `FlutterOpenGLTexture` |
| B | `flutter::ExternalTextureD3d::CreateOrUpdateTexture` | `0xeafe` | 675 B | Creates/rebinds the EGL pbuffer surface through ANGLE |
| B | `flutter::ExternalTextureD3d::ReleaseImage` | `0xea3e` | 67 B | `eglReleaseTexImage` + `eglDestroySurface` |
| B | `flutter::egl::Manager::CreateSurfaceFromHandle` | `0xdf7a` | 34 B | Thin wrapper over `eglCreatePbufferFromClientBuffer` |
| C | `flutter::EmbedderExternalTextureGL::ResolveTexture` | `0xeb436` | 77 B | Chooses Impeller or Skia |
| C | `…::ResolveTextureImpeller` | `0xeb484` | 1371 B | Wraps the ANGLE GL texture in an Impeller `TextureGLES` |
| C | `…::ResolveTextureSkia` | `0xeb9e0` | 665 B | Flushes/resets Ganesh, borrows the GL texture as an `SkImage` |

The external-texture handoff is therefore exactly three levels deep, matching
the shape researched for 3.47.6. Impeller changes **level C only**.

---

### Path A — Registration

`RegisterTexture` (RVA `0x1b24c`) accepts only
`kFlutterDesktopGpuSurfaceTexture` and only surface types
`kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle` and
`kFlutterDesktopGpuSurfaceTypeD3d11Texture2D` (the decompiler checks
`type - DxgiSharedHandle < 2`). It validates the descriptor size and callback,
then:

```c
// flutter_windows_texture_registrar.cc, reconstructed from RVA 0x1b24c
if (info->type != kFlutterDesktopGpuSurfaceTexture) {
  log("Attempted to register texture of unsupport type.");
  return -1;
}
surface_type = info->gpu_surface_config.type;         // 0 = DxgiSharedHandle, 1 = D3d11Texture2D
if (surface_type != DxgiSharedHandle && surface_type != D3d11Texture2D) { ... }
callback  = info->gpu_surface_config.callback;        // required
user_data = info->gpu_surface_config.user_data;       // only if struct_size >= 0x20
auto texture = std::make_unique<ExternalTextureD3d>(
    surface_type, callback, user_data, engine_->egl_manager_,
    /*shared_ptr<ProcTable>*/ this->gl_);
return EmplaceTexture(std::move(texture));
```

`EmplaceTexture` (RVA `0x1b4d2`) locks `map_mutex_`, inserts the
`unique_ptr<ExternalTexture>` into the `textures_` map under the returned id,
unlocks, and posts a `TaskRunner::RunNowOrPostTask` notification to the
engine.

The `ExternalTextureD3d` constructor (RVA `0xe998`) only stores the surface
type, callback, user data, EGL manager and GL proc table; it initialises
`gl_texture_ = 0`, `egl_surface_ = nullptr`, `last_surface_handle_ = nullptr`.
No GL or EGL object is created at registration.

#### Allocation

`operator_new(0x50)` in `RegisterTexture` allocates one
`ExternalTextureD3d` (80 bytes). Its lifetime is the `unique_ptr` stored in
the registrar's `textures_` map; the destructor (RVA `0xe9f6`) calls
`ReleaseImage`, then `glDeleteTextures(1, &gl_texture_)` if a texture name
exists, then releases the GL proc table. Registration allocates **no** GPU
object: no GL texture name, no EGL surface, no D3D resource.

#### Fence semantics

None. Registration is CPU-side bookkeeping under a mutex. The only ordering
constraint is that the map insert happens before the id is returned; there is
no GPU work and therefore nothing to synchronise.

#### Device ownership

No device is touched. The producing D3D11 device belongs to the embedder
(mpv_kit), not to Flutter/ANGLE, and registration does not know about it yet.

---

### Path B — Production

`ExternalTextureD3d::PopulateTexture` (RVA `0xea82`) invokes the application
callback to obtain a `FlutterDesktopGpuSurfaceDescriptor`, calls
`CreateOrUpdateTexture`, and on success fills the GL texture description that
the compositor will consume:

```c
// external_texture_d3d.cc, reconstructed from RVA 0xea82
FlutterDesktopGpuSurfaceDescriptor* d =
    texture_callback(/*width*/ result_size.width,
                     /*height*/ result_size.height, user_data_);
if (!CreateOrUpdateTexture(d)) return false;

out->target               = GL_TEXTURE_2D;   // 0x0DE1
out->name                 = gl_texture_;     // the ANGLE-bound GL name
out->format               = GL_RGBA8;        // 0x8058
out->user_data            = nullptr;
out->destruction_callback = nullptr;
out->width                = d->visible_width;   // only if struct_size >= 0x28
out->height               = d->visible_height;  // only if struct_size >= 0x30
```

`CreateOrUpdateTexture` (RVA `0xeafe`) is the only function that touches the
shared surface:

```c
// external_texture_d3d.cc, reconstructed from RVA 0xeafe
if (!d || d->struct_size < 0x10 || !d->handle) { ReleaseImage(this); return false; }

if (gl_texture_ == 0) {
  glGenTextures(1, &gl_texture_);
  glBindTexture(GL_TEXTURE_2D, gl_texture_);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);  // 0x812F
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);     // 0x2601
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
} else {
  glBindTexture(GL_TEXTURE_2D, gl_texture_);
}

if (d->handle != last_surface_handle_) {
  ReleaseImage(this);                       // eglReleaseTexImage + eglDestroySurface
  EGLint attrs[] = {
    EGL_WIDTH, d->width, EGL_HEIGHT, d->height,          // 0x3057 / 0x3056
    EGL_TEXTURE_TARGET, EGL_TEXTURE_2D,                  // 0x3081 / 0x305F
    EGL_TEXTURE_FORMAT, EGL_TEXTURE_RGBA,                // 0x3080 / 0x305E
    EGL_NONE                                             // 0x3038
  };
  EGLenum handle_type = EGL_D3D_TEXTURE_2D_SHARE_HANDLE_ANGLE;   // 0x3200
  if (type_ == kFlutterDesktopGpuSurfaceTypeD3d11Texture2D)
    handle_type = EGL_D3D_TEXTURE_ANGLE;                          // 0x33A3
  egl_surface_ = egl_manager_->CreateSurfaceFromHandle(
      handle_type, d->handle, attrs);        // -> eglCreatePbufferFromClientBuffer
  if (!egl_surface_) {
    log("Binding D3D surface failed.");      // source line 0x6B
  } else if (!eglBindTexImage(display_, egl_surface_, EGL_BACK_BUFFER)) {  // 0x3084
    log("Binding D3D surface failed.");
  }
  last_surface_handle_ = d->handle;
}

if (d->struct_size > 0x3F && d->release_callback)
  d->release_callback(d->release_context);   // called immediately, same call
return egl_surface_ != nullptr;
```

`egl::Manager::CreateSurfaceFromHandle` (RVA `0xdf7a`, 34 bytes) is exactly:

```c
return eglCreatePbufferFromClientBuffer(display_, handle_type, handle,
                                        config_, attributes);
```

The two handle types are therefore not interchangeable, and each surface type
maps to a distinct EGL enum:

| `FlutterDesktopGpuSurfaceType` | EGL enum | Value | What ANGLE receives |
|---|---|---|---|
| `DxgiSharedHandle` | `EGL_D3D_TEXTURE_2D_SHARE_HANDLE_ANGLE` | `0x3200` | the legacy KMT share handle (what mpv_kit produces) |
| `D3d11Texture2D` | `EGL_D3D_TEXTURE_ANGLE` | `0x33A3` | a live `ID3D11Texture2D*` |

Inside ANGLE, `rx::DisplayD3D::createPbufferFromClientBuffer`
(RVA `0xee9d40`) allocates a `PbufferSurfaceD3D`; the `SurfaceD3D`
constructor (RVA `0xf18220`) stores the buffer in one of two fields:

```c
if (handle_type == 0x33A3 /* EGL_D3D_TEXTURE_ANGLE */) {
  mD3DTexture = client_buffer;   AddRef();
} else if (handle_type == 0x3200 /* SHARE_HANDLE */) {
  mShareHandle = client_buffer;
}
```

`SurfaceD3D::resetSwapChain` (RVA `0xf18760`) later calls
`RendererD3D::createSwapChain(native_window, mShareHandle, mD3DTexture)`.
`SwapChain11::resetOffscreenColorBuffer` (RVA `0xecb660`) opens the share
handle on ANGLE's own device (`ID3D11Device::OpenSharedResource`, IID
`dc8e63f3-d12b-4952-b47b-5e45026a862d` = `ID3D11Texture2D`) or uses the
provided texture directly, then calls `QueryInterface` for
`6f15aaf2-d208-4e89-9ab4-489535d34f9c` = **`IDXGIKeyedMutex`** and stores the
result (null when the resource was not created with keyed-mutex sharing).

The `release_callback` is invoked **after** `eglBindTexImage` returns and
**before** `PopulateTexture` returns the GL description to the compositor.
That ordering is the key semantic: the callback releases the producer's frame
reference, but it is not a statement that the consumer has finished reading.

#### Allocation

- GL texture name: lazily created (`glGenTextures`) on the first successful
  `PopulateTexture`, destroyed in `~ExternalTextureD3d` (`glDeleteTextures`).
- EGL pbuffer surface: created only when `handle != last_surface_handle_`
  (first frame, resize, new ring slot), destroyed by `ReleaseImage`
  (`eglReleaseTexImage` + `eglDestroySurface`).
- D3D resource: **not allocated by Flutter**. It is allocated by the
  embedder (mpv_kit's own D3D11 device) and merely opened/imported by ANGLE.

#### Fence semantics

None, in either direction:

- no `eglSwapBuffers`, no fence/query, no keyed-mutex acquire in the Flutter
  call chain;
- `eglBindTexImage` binds the surface to the current GL texture; it does not
  wait for the producer or the consumer;
- the immediate `release_callback` is a lifetime signal, not "read complete";
- the only bound on how long ANGLE may sample the image is implicit: the
  frame's command list executes later, bounded in practice by the DXGI frame
  queue (default 3) plus the frame being composed. Doc 02 derived the
  resulting quarantine of 4 from this; Phase 10 does not re-measure it
  (Phase 11 owns that, see §6).

#### Device ownership

Two D3D11 devices exist in the same process:

1. **Producer device** — mpv_kit creates its own `ID3D11Device` on Flutter's
   adapter (`packages/mpv_kit_video/windows/d3d11_interop.cpp:34-40`) and
   creates the texture with `D3D11_RESOURCE_MISC_SHARED` (legacy KMT handle,
   lines 99-103). It imports the same handle into Vulkan as
   `VK_EXTERNAL_MEMORY_HANDLE_TYPE_D3D11_TEXTURE_KMT_BIT`.
2. **Consumer device** — ANGLE's `Renderer11` device inside the same PE
   opens that KMT handle with `OpenSharedResource`.

For the `D3d11Texture2D` surface type, ANGLE instead AddRefs and keeps the
producer's `ID3D11Texture2D` directly. In both cases the Vulkan import is on
mpv_kit's side; Flutter never sees Vulkan.

Because ANGLE is compiled into `flutter_windows.dll` (no `libEGL.dll` /
`libGLESv2.dll` import; see `evidence/engine-3.47.8.imports.txt`), all three
devices — mpv_kit's D3D11, ANGLE's D3D11, and mpv_kit's Vulkan — are in one
process. Synchronisation cannot be explained or fixed at a DLL boundary; it
must be a resource-level contract (or none).

---

### Path C — Consumption

`ResolveTexture` (RVA `0xeb436`, 77 bytes) is a two-way dispatch:

```c
if (aiks_context)                       // Impeller is live
  return ResolveTextureImpeller(texture_id, aiks_context, size);
else if (skia_context)                  // legacy Skia/Ganesh
  return ResolveTextureSkia(texture_id, skia_context, size);
return nullptr;
```

The Ghidra parameter names are shuffled at this address; the callee list
(`ResolveTextureImpeller`, `ResolveTextureSkia`) and the 3.47.8 source shape
fix the semantics.

**Impeller branch** (`ResolveTextureImpeller`, RVA `0xeb484`, 1371 bytes):

```c
std::unique_ptr<FlutterOpenGLTexture> tex =
    external_texture_callback_(/*width*/, /*height*/, /*user_data*/);
if (!tex) return nullptr;

if (tex->format != GL_RGBA8) {          // 0x8058, reuses GL_RGBA8_OES value
  log("Only support GL_RGBA8 format now");   // source line 0x9A
  return nullptr;                            // silent black texture, no crash
}

auto context = AiksContext::GetContext(aiks_context);   // ContextGLES
HandleGLES handle = ReactorGLES::CreateHandle(
    reactor, kTexture, tex->name);                      // the ANGLE GL name
TextureDescriptor desc = {
    .storage_mode = kDeviceTransient,
    .type         = kTexture2D,
    .format       = kR8G8B8A8UNormInt,
    .mip_count    = 1,
    .usage        = kRead,
    .sample_count = kCount1,
    .compression  = kLossless,
    .size         = {tex->width, tex->height},
};
auto wrapped = TextureGLES::WrapTexture(reactor, desc, handle);
if (!wrapped) { log("Could not create external texture"); return nullptr; }

if (!ReactorGLES::RegisterCleanupCallback(
        reactor, handle,
        [tex = std::move(tex)](...) { /* release the FlutterOpenGLTexture */ })) {
  log("Could not register destruction callback");   // source line 0xBB
  return nullptr;
}
return DlImageImpeller::Make(wrapped);              // no flush, no reset
```

**Skia branch** (`ResolveTextureSkia`, RVA `0xeb9e0`, 665 bytes):

```c
if (!skia_context) return nullptr;                  // #191017 null guard
GrDirectContext::flush(skia_context, ...);
GrDirectContext::submit(skia_context, ...);
GrDirectContext::resetContext(skia_context, kAll_GrBackendState);  // 0xFFFFFFFF

std::unique_ptr<FlutterOpenGLTexture> tex =
    external_texture_callback_(/*width*/, /*height*/, /*user_data*/);
if (!tex) return nullptr;

GrGLTextureInfo info = { tex->name, tex->format };
GrBackendTexture backend = GrBackendTextures::MakeGL(
    tex->width, tex->height, kNo, &info, ...);
SkImage image = SkImages::BorrowTextureFrom(
    skia_context, backend, kUnknown_SkColorType,
    /*alpha*/ 4, color_space, release_proc, tex->user_data);
if (!image) { log("Could not create external texture->"); return nullptr; }
return DlImageSkia::Make(image);
```

Differences that matter for an implementation:

| Aspect | Impeller (`ResolveTextureImpeller`) | Skia (`ResolveTextureSkia`) |
|---|---|---|
| Per-resolve flush | none | `flush` + `submit` + `resetContext(kAll_GrBackendState)` |
| Wrapper | `HandleGLES` + `TextureGLES::WrapTexture` + `DlImageImpeller` | `GrBackendTexture` + `BorrowTextureFrom` + `DlImageSkia` |
| Lifetime hook | `ReactorGLES::RegisterCleanupCallback` (reactor-owned) | `SkImage` release proc (Skia-owned) |
| Format gate | hard: `format == GL_RGBA8`, else black texture | no such gate at this layer |
| Texture handle | same ANGLE-bound GL name | same ANGLE-bound GL name |

The two error strings explain the anchor count of 2 in the binary: the Impeller
branch prints `Could not create external texture`, the Skia branch prints
`Could not create external texture->`.

#### Allocation

- Impeller: `ReactorGLES::CreateHandle` allocates a reactor handle; the
  `TextureGLES` wrapper and its descriptor are heap objects owned by an
  Impeller `shared_ptr`. The reactor cleanup callback owns the
  `FlutterOpenGLTexture` returned by the app callback. The GL texture name
  itself is **not** allocated here — it was allocated in Path B.
- Skia: `GrBackendTexture` and the borrowed `SkImage` are wrappers over the
  same GL name; `DlImageSkia` is the returned image. No new GPU allocation.

#### Fence semantics

- Impeller: no flush, no submit barrier, no fence, no wait. The only signal is
  the reactor cleanup callback, which fires when Impeller is done with the
  wrapped texture — a **lifetime** signal, not a per-frame read-completion
  fence. Submission is deferred to Impeller's GLES reactor/command buffer.
- Skia: `flushAndSubmit()` submits recorded work and returns immediately; it
  does not wait for the GPU. `resetContext(kAll_GrBackendState)` drops backend
  state after submission. Neither is a fence.
- Therefore neither branch creates a cross-API synchronization primitive
  between mpv_kit's Vulkan writes and ANGLE's D3D11 sampling.

#### Device ownership

Both branches consume the **same** GL texture name created and bound in Path B
inside ANGLE's context. Neither branch touches a D3D11 device, an `EGLSurface`
or the shared handle. Consequences:

- no device owner changes at consumption;
- the D3D11 devices remain: mpv_kit's producer device and ANGLE's consumer
  device (both in-process);
- the Impeller-vs-Skia choice cannot change which device owns the shared
  image, because both wrap the ANGLE-bound GL texture rather than the D3D
  resource.

**Keyed-mutex answer:** the Impeller branch does **not** change the acquisition
semantics of `EGL_ANGLE_keyed_mutex` / `IDXGIKeyedMutex`, because no
acquisition happens anywhere in this chain. Three independent observations
settle it. (1) In the binary, `rx::SwapChain11::resetOffscreenColorBuffer`
(RVA `0xecb660`) obtains the mutex with `QueryInterface` on
`6f15aaf2-d208-4e89-9ab4-489535d34f9c` (`IID_IDXGIKeyedMutex`) and stores the
pointer, but the function contains no `AcquireSync`/`ReleaseSync` call; the
only way to reach the stored pointer is
`rx::SurfaceD3D::querySurfacePointerANGLE` (RVA `0xf18f50`), which answers
attribute `0x33A2` (`EGL_DXGI_KEYED_MUTEX_ANGLE`) by calling the virtual
`rx::SwapChain11::getKeyedMutex` (RVA `0x3d960`, a 5-byte getter returning the
field). (2) The `eglQuerySurfacePointerANGLE` string is referenced only by
EGL's own export wrappers (`EGL_QuerySurfacePointerANGLE`,
`egl::QuerySurfacePointerANGLE`) — no Flutter embedder function calls it, and
`EGL_ANGLE_keyed_mutex` is referenced only by
`egl::DisplayExtensions::getStrings`. (3) ANGLE's public source at the
revision pinned by Flutter 3.47.8 (`84027aca9b71c9ba335bd000dad1107b8810a511`)
contains no `AcquireSync`/`ReleaseSync` in `SwapChain11.cpp`; it only stores
`mKeyedMutex` via `DynamicCastComObject<IDXGIKeyedMutex>` and returns it from
`getKeyedMutex()`. In addition, mpv_kit creates its texture with
`D3D11_RESOURCE_MISC_SHARED`, not `..._SHARED_KEYEDMUTEX`, so the
`QueryInterface` returns null for our surfaces. **Evidence boundary:** the
full `SwapChain11::reset` / `present` / `swapRect` path was not
instruction-audited, so an internal acquisition inside ANGLE's own swap-chain
presentation is not excluded by this dump; it would sit in Path B, not in the
Impeller consumption branch, and would not be introduced by choosing Impeller.

---

## 3. Answers per path (summary)

| Path | Through ANGLE? | DXGI device owner | Fence semantics |
|---|---|---|---|
| A — Registration | No GPU work | none | none |
| B — Production | **Yes**, always: `eglCreatePbufferFromClientBuffer` + `eglBindTexImage` | producer = mpv_kit's D3D11 device; consumer = ANGLE's `Renderer11` device opening the KMT handle | none; `release_callback` fires immediately after bind and is not a completion signal |
| C — Consumption | **Yes**, even under Impeller: the GL texture is ANGLE-bound | no device change; same ANGLE context | Impeller: no flush/wait; Skia: `flush`+`submit`+`resetContext`, still no wait |

The consequence for the project's driving question is unchanged from the
research: **enabling Impeller shortens level C (removes Ganesh, the per-resolve
flush and the context reset) but does not remove ANGLE from level B.** The
cheaper path, if any, is in what level C does around the same ANGLE texture,
not in eliminating the EGL handoff.

---

## 4. Alignment with mpv_kit's producer

| mpv_kit side | Engine side |
|---|---|
| `D3D11Interop` creates its own `ID3D11Device` on Flutter's adapter (`d3d11_interop.cpp:19-48`) | ANGLE's `Renderer11` device is created inside `flutter_windows.dll` |
| Texture created with `D3D11_RESOURCE_MISC_SHARED` and `GetSharedHandle` (`:90-106`) | `SurfaceD3D` stores `mShareHandle` for `0x3200`; `resetOffscreenColorBuffer` calls `OpenSharedResource` |
| Vulkan imports the KMT handle as `D3D11_TEXTURE_KMT_BIT` (`:108-155`) | Flutter never sees the Vulkan image |
| `FlutterDesktopGpuSurfaceDescriptor` with `DxgiSharedHandle` | `RegisterTexture` selects `ExternalTextureD3d`; `CreateOrUpdateTexture` selects `EGL_D3D_TEXTURE_2D_SHARE_HANDLE_ANGLE` |
| `release_callback` → `D3D11Interop` frame reference release | invoked immediately after `eglBindTexImage`, before the compositor consumes |

The `D3d11Texture2D` alternative would let ANGLE AddRef the producer's texture
directly (no KMT handle, no `OpenSharedResource`), but it does not add a
fence. It changes the transport, not the synchronization contract.

---

## 5. Implementation constraints Phase 11 can rely on

1. **Format cliff.** `ResolveTextureImpeller` returns null unless
   `FlutterOpenGLTexture::format == GL_RGBA8` (`0x8058`). Path B always sets
   `GL_RGBA8`, so today the check passes. Any future format change produces a
   **silent black texture**, not a crash; the smoke must assert a non-black
   frame, not merely survival.
2. **Reactor cleanup lifetime.** Under Impeller the `FlutterOpenGLTexture` is
   owned by a reactor cleanup callback; under Skia it is owned by the
   `SkImage` release proc. A controller that frees the producer's image on a
   timer must not assume Skia-like release timing.
3. **No flush is not "faster completion".** Skia's `flush`/`submit` submits
   work but does not wait; removing it (Impeller) removes CPU work, not GPU
   latency. Any reasoning about how long the compositor may hold an image must
   still come from measurement, not from the presence/absence of `flush`.
4. **Same ANGLE handoff.** Any Phase 11 change that tries to shorten the chain
   by altering level B must replace `eglCreatePbufferFromClientBuffer` +
   `eglBindTexImage` (i.e. change the engine or upstream a patch); changing
   only level C cannot remove ANGLE.
5. **One process, no DLL boundary.** ANGLE is compiled into the engine PE;
   device/fence reasoning must be resource-level. Swapping an `libEGL.dll`
   is not an available lever.

---

## 6. Quarantine / compositor-latency hypothesis (not measured here)

Doc 02 derived `quarantine = 4` on Windows from the absence of a fence and a
DXGI queue depth of 3 plus the frame being composed. Nothing in this dump
contradicts that. What changes under Impeller is only level C: there is no
`flushAndSubmit`/`resetContext`, so if Impeller's GLES command buffer defers
submission across frames, ANGLE could sample the shared texture later than the
Skia-era bound. That remains a **hypothesis for Phase 11 to measure**; Phase
10 records the values (`CompositorLatency() == 4`,
`kMaxQuarantine == 4`, ring 7) and does not re-measure them.

---

## 7. Open items and assumptions

| Item | Status |
|---|---|
| Which commit carried #191017 into the release branch | **Unverified.** The code is present in 3.47.8; the merge commit is not an ancestor. Content-level conclusion only. |
| Whether the shipped DLL (engine `cf636b1dfb`) corresponds byte-for-byte to tag-tree source | **Unverified link.** `cf636b1dfb` does not resolve in `flutter/engine`; supported indirectly by identical anchors/imports and byte-identical source files between tags. |
| Whether `flutter test -d windows` forwards the engine log line | **Open**, owned by plan 10-03 (smoke). |
| Whether Impeller's GLES command buffer defers submission enough to invalidate `quarantine = 4` | **Hypothesis**, Phase 11 measurement. |
| Whether ANGLE internally acquires the keyed mutex in `SwapChain11::reset/present/swapRect` | **Not instruction-audited.** No acquisition in the creation path or in public `SwapChain11.cpp`; boundary stated in §2 Path C. |
| `rx::SurfaceD3D::bindTexImage` pseudocode | **Unavailable** at RVA `0xc2cbe0` because of ICF folding with unrelated 19-byte virtuals; the production behaviour is taken from `CreateOrUpdateTexture` and the `egl::BindTexImage` wrapper. |

---

## 8. Sources and reproducibility

- Evidence files committed alongside this report:
  - `evidence/engine-3.47.8.sha256.txt` — artifact pin and excluded copy
  - `evidence/engine-3.47.8.imports.txt` — import table and ANGLE linkage
  - `evidence/engine-3.47.8.anchors.txt` — anchor counts and meanings
  - `evidence/decompilation.txt` — full Ghidra export (function metadata,
    pseudocode, callers/callees, anchor xrefs)
  - `tools/DumpTargets.py` — the PyGhidra post-script used to produce it
- Elided Ghidra project (not committed): `D:/ghidra-work-3.47.8/project`,
  program `mpvkit103478`, same DLL/PDB, full analysis with PDB.
- Engine sources at tag 3.47.8: `flutter_windows_texture_registrar.cc`,
  `external_texture_d3d.cc`, `egl/manager.cc`,
  `embedder_external_texture_gl.cc`.
- ANGLE revision pinned by Flutter 3.47.8 `DEPS`:
  `84027aca9b71c9ba335bd000dad1107b8810a511`
  (`flutter/third_party/angle`). Public headers/implementation consulted:
  `include/EGL/eglext_angle.h` (`EGL_DXGI_KEYED_MUTEX_ANGLE = 0x33A2`,
  `EGL_D3D_TEXTURE_ANGLE = 0x33A3`), `SwapChain11.cpp` (`mKeyedMutex` stored
  and exposed, no acquire), `src/libANGLE/Caps.cpp`
  (`EGL_ANGLE_keyed_mutex` extension string).
- Prior analysis: `docs/reverse-engineering/02-flutter-windows-external-texture.md`
  (3.47.6, symbol level) and `docs/ARCHITECTURE.md` (quarantine and ring).

Reproduction: run Ghidra 12.1.4 headless via PyGhidra with the DLL and its
sibling PDB, `-processor x86:LE:64:default`,
`-analysisTimeoutPerFile 7200`, then `-postScript DumpTargets.py <out>`.
The script is deterministic; anchor counts and addresses in this report are
from the run recorded in `evidence/decompilation.txt`.

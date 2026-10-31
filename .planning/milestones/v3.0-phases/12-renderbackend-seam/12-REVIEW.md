---
phase: 12-renderbackend-seam
reviewed: 2026-10-27T02:42:23Z
depth: standard
files_reviewed: 26
files_reviewed_list:
  - packages/mpv_kit_video/src/render_backend.h
  - packages/mpv_kit_video/src/video_renderer.cc
  - packages/mpv_kit_video/src/video_renderer.h
  - packages/mpv_kit_video/src/vulkan_backend.cc
  - packages/mpv_kit_video/windows/mpv_kit_video_plugin.cpp
  - packages/mpv_kit_video/linux/mpv_kit_video_plugin.cc
  - packages/mpv_kit_video/linux/gl_interop.h
  - packages/mpv_kit_video/macos/Classes/MpvKitVideoPlugin.mm
  - packages/mpv_kit_video/lib/src/video_controller.dart
  - packages/mpv_kit_video/test/controller_channel_test.dart
  - packages/mpv_kit_video/test/video_controller_test.dart
  - native/tests/meson.build
  - native/tests/renderer_harness.h
  - native/tests/video_renderer_golden_sw.cc
  - native/tests/video_renderer_golden_vk.cc
  - native/tests/video_renderer_golden_vk_fallback.cc
  - native/tests/video_renderer_golden_vk_retire_twice.cc
  - native/tests/video_renderer_golden_sw_retire_twice.cc
  - native/tests/video_renderer_api_test.cc
  - native/tests/video_renderer_affinity_test.cc
  - example/integration_test/impeller_smoke_test.dart
  - example/integration_test/impeller_smoke_modes.dart
  - example/integration_test/real_plugin_test.dart
  - example/integration_test/uhd_endurance_test.dart
  - .github/workflows/native-verify.yml
  - .github/workflows/flutter-plugin.yml
findings:
  critical: 1
  warning: 6
  info: 6
  total: 13
status: issues_found
---

# Phase 12: Code Review Report

**Reviewed:** 2026-10-27T02:42:23Z
**Depth:** standard (diff vs `2ed9c80`)
**Files Reviewed:** 26
**Status:** issues_found

## Summary

The review covered the RenderBackend seam (`render_backend.h`, `SoftwareBackend`, `VulkanRenderBackend`), the candidate loop and `MPV_KIT_VIDEO_API` parsing in `VideoRenderer::Start`, the move of swap reports and render-context release onto the render thread, the wire-name changes in the three plugins and in Dart, and the new native and integration tests.

What holds up:
- **Thread affinity.** After `Start`, every `mpv_render_*` call runs on the render thread. The update-callback removal comes before `Release`. The destructor's join gives the needed happens-before for `render_ctx_`.
- **Swap bookkeeping.** `swaps_to_report_` and `swap_pending_` are only touched under `mutex_`.
- **`MPV_KIT_VIDEO_API`.** Parsing, the `?` echo, the 16-character cut and the strict filter match ADR 0004. Excluded candidates never construct a backend.
- **Device lifetime.** Each api's device is released before the next api is tried.
- **Vulkan keep-slot fix.** The `AllocateRing` handle clear (`*keep_retired = SharedImage{}`) is correct.

What does not hold up:
- **CR-01 (blocker).** The retire-twice fix (12-09) only stops *new* acquisitions of the generation-before-last. On the software path, `SoftwareBackend::AllocTargets` still frees a generation whose pixels the compositor received from the latest `AcquireFront()`. That breaks the header's own "valid until the next AcquireFront()" guarantee, and Flutter on Windows and Linux reads those pixels after the callback returns.
- **WR-01.** The seam's documented deferred-release contract does not describe what either backend actually does.
- **Reason strings.** Sanitisation does not cover invalid UTF-8, and the engine does not sanitise `why` text that comes from a backend (WR-02).
- **Golden tests.** They inherit `MPV_KIT_VIDEO_API` from the developer's environment (WR-03).

Known accepted items were not re-reported: the frozen golden files, the size of `renderer_harness.h`, the no-op `BindThread`/`UnbindThread` before Phase 15, the frozen public API, and RBE-05 swap timing deferred to 12-12.

## Narrative Findings (AI reviewer)

## Critical Issues

### CR-01: Software path frees retired pixels that the last AcquireFront() handed to the compositor (retire-twice fix incomplete)

**File:** `packages/mpv_kit_video/src/video_renderer.cc:184-195` (SoftwareBackend::AllocTargets), `:474-485` (AcquireFront retired branch), `:699-718` (RenderOnce resize block); consumers at `packages/mpv_kit_video/linux/mpv_kit_video_plugin.cc:188-192` and `packages/mpv_kit_video/windows/mpv_kit_video_plugin.cpp:231-240`

**Issue:** `video_renderer.h:118-120` promises that a returned frame "stays valid until the next AcquireFront() call". The Linux plugin depends on this explicitly (`*buffer = f.pixels;  // stays valid until the next AcquireFront()`). Both Flutter embedders upload the pixel buffer *after* the copy callback returns and outside every lock.

Two traces break the promise on the software backend:

1. **Retire twice.** Resize A→B retires all of A (`retired_ = std::move(buffers_)`). The raster thread's `AcquireFront` then returns `retired_front_` (A's front pixels). B's first render fails. Resize B→C: line 703 clears `retired_front_`, and `AllocTargets` runs `retired_ = std::move(buffers_)`, whose move-assignment frees A immediately. That pointer was the latest one handed out, and Flutter may still be copying from it.
2. **Rapid resize.** The same thing happens without a render failure. After A→B, B publishes, then a B→C resize arrives before the next `AcquireFront`. The last pointer handed out is still A's front, and C's `AllocTargets` frees A without waiting for `retired_countdown_`.

On Vulkan, the platform references (COM AddRef, CVPixelBufferRetain, GL graveyard) protect the object. Software has no such reference.

The `*_retire_twice` goldens cannot catch this. The sw golden "never dereferences the window frame", and no golden models a consumer still reading after the call returns. The window is small (one upload), but the result is a heap use-after-free on the raster thread. The reachable trace is a resize debounce firing while the previous generation is still on screen.

**Fix:** Do not free a software generation while its frame may be the one the compositor was last given. The simplest option keeps the generation the engine last handed out alive across one more reallocation and frees it only in `FreeRetired()`:
```cpp
// SoftwareBackend
bool AllocTargets(int count, int width, int height, int keep_slot,
                  std::string* error) override {
  (void)keep_slot;
  try {
    // Keep up to two retired generations; FreeRetired() drops them all once
    // the engine's countdown has passed.
    older_ = std::move(retired_);
    retired_ = std::move(buffers_);
    buffers_.assign(count, std::vector<uint8_t>(size_t(width) * height * 4));
  } catch (const std::bad_alloc&) {
    *error = "software buffer allocation failed";
    return false;
  }
  return true;
}
void FreeRetired() override { retired_.clear(); older_.clear(); }
```
In `RenderOnce`, when `front_ < 0 && retired_front_` is set (the older survivor is what the compositor is showing), do not clear `retired_front_` before the reallocation. Instead, keep showing it and restart its countdown after the first new-size publish. Alternatively, make the pixel buffers `shared_ptr`-owned and keep the last handed-out buffer alive in the plugin until the next copy callback. Add a golden with a consumer that keeps reading the returned pointer across the second resize (ASan job).

## Warnings

### WR-01: The RenderBackend deferred-release contract does not match either implementation

**File:** `packages/mpv_kit_video/src/render_backend.h:69-73`; `packages/mpv_kit_video/src/vulkan_backend.cc:371`; `packages/mpv_kit_video/src/video_renderer.cc:186-192, 700-703`

**Issue:** The contract says the retired generation "stays valid until the engine calls FreeRetired()". Both backends break it on the next `AllocTargets`:
- `VulkanContext::AllocateRing` calls `FreeRetired()` first.
- `SoftwareBackend` replaces `retired_`.

The engine depends on that undocumented behaviour: the line 700-703 comment says "which the reallocation below frees". The Phase 14/15 backends (D3D11, OpenGL) are meant to be written against this header. A backend that follows the documented contract would keep every retired generation until `FreeRetired()`, which differs in memory from what the engine expects. A backend that copies the real behaviour reproduces CR-01 on any path without a platform reference.

**Fix:** State the real rule in the header ("AllocTargets first releases the previous retired generation; the engine guarantees it no longer hands that generation out"), and make the engine guarantee it (see CR-01). Or change the implementations to match the documented contract. Either way, the contract and the code must say the same thing before Phase 14 builds on it.

### WR-02: Reason fields are not checked for valid UTF-8, and the engine trusts `why` text from backends

**File:** `packages/mpv_kit_video/src/video_renderer.cc:15-24` (SanitizeReasonField), `:38-41` (Trail), `:346` (`Trail(c, why)` with backend-supplied text); `packages/mpv_kit_video/windows/mpv_kit_video_plugin.cpp:219-220, 249`; `packages/mpv_kit_video/linux/mpv_kit_video_plugin.cc:330, 362`; `packages/mpv_kit_video/macos/Classes/MpvKitVideoPlugin.mm:252, 259`

**Issue:** `SanitizeReasonField` maps only `;` and bytes below 0x20. Bytes of 0x80 and above pass through unchecked.

The reason now goes onto the method channel in two places: in `render_init.details`, and in the success map after the texture is already registered. If any byte sequence is invalid UTF-8 (driver device name, interop reason, mpv error text), each platform fails differently:
- **Windows and Linux:** Dart's StandardMessageCodec `utf8` decode throws `FormatException`. `create()` then fails with a non-`PlatformException` and never receives the `textureId`, so the native renderer and texture leak until process exit.
- **macOS:** `stringWithUTF8String` returns nil, and the reason is silently replaced by `""`.

Separately, `Trail()` takes the backend's `why` as is. Only the built-in backends sanitise their own text, so a Phase 14/15 platform backend that forgets would inject `;`, which splits trails.

**Fix:** Sanitise in one place, the engine:
```cpp
std::string Trail(const BackendCandidate& c, const std::string& why) {
  return std::string(c.api) + "/" + c.renderer + " unavailable: " +
         SanitizeReasonField(why);
}
```
Extend `SanitizeReasonField` to replace invalid UTF-8 sequences (or every byte >= 0x80) with `?`.

### WR-03: Renderer tests inherit `MPV_KIT_VIDEO_API` from the environment

**File:** `native/tests/meson.build:68-163`; `native/tests/video_renderer_golden_vk_fallback.cc`, `video_renderer_golden_vk_retire_twice.cc`, `video_renderer_golden_sw_retire_twice.cc` (no `SetEnv` call; only the api and affinity tests clear it)

**Issue:** `VideoRenderer::Start` now reads `MPV_KIT_VIDEO_API` on every call. golden_sw, golden_vk, golden_vk_fallback and both retire-twice goldens never clear it. The variable is documented as a diagnostic switch for shipped apps, so a developer (or a CI job) that has it exported gets golden mismatches or skips that have nothing to do with the code under test. The frozen files cannot be edited, but their `test()` registrations can.

**Fix:** Give every renderer `test()` an environment where the variable is empty. Empty means unset in `ParseForcedApi`, and `_putenv_s` with `""` removes it on Windows:
```meson
renderer_test_env = environment({'MPV_KIT_VIDEO_API': ''})
# merge into golden_vk_env, and pass env: renderer_test_env to golden_sw /
# golden_sw_retire_twice
```

### WR-04: Dispose frees software pixel buffers while the raster thread may still be uploading the last frame

**File:** `packages/mpv_kit_video/windows/mpv_kit_video_plugin.cpp:256-263` (Stop → `inst->renderer.reset()`), `packages/mpv_kit_video/linux/mpv_kit_video_plugin.cc:367-377` (Dispose → `st->renderer.reset()`); `packages/mpv_kit_video/src/video_renderer.cc:288`

**Issue:** The `dead` flag stops *new* `AcquireFront` calls. However, the pixel pointer returned by the previous copy callback is uploaded by the engine after the callback has returned and the plugin mutex is released. `renderer.reset()` joins the render thread and then destroys the `SoftwareBackend`, freeing `buffers_`/`retired_`, possibly during that upload.

On Windows the struct deletion is deferred to the `UnregisterTexture` callback, but the renderer, and with it the pixels, is destroyed before that. This predates phase 12, but phase 12 rewrote the teardown order in exactly this code (render-thread `Release`, then `render_backend_.reset()` in the destructor) without covering it. The Vulkan path is protected by platform references; software is not.

**Fix:** Keep the software buffers alive until the platform confirms the texture is gone. On Windows, move the `renderer.reset()` for software instances into the `UnregisterTexture` completion, after calling `Release()` for the render context first so the mpv core can still be destroyed. On Linux, defer it into the existing `g_timeout_add` release. Alternatively, set `FlutterDesktopPixelBuffer::release_callback` and refcount the buffers.

### WR-05: `SoftwareBackend::AllocTargets` can throw `std::bad_alloc` on the render thread (process terminate)

**File:** `packages/mpv_kit_video/src/video_renderer.cc:184-195`

**Issue:** The seam gives `AllocTargets` a `false` + `*error` path, and the engine handles it (ring fallback, then `failed_before_render`). The software backend ignores it ("bad_alloc aside"). At 8K the full generation is `ring_size_` x 7680x4320x4 bytes: 7 x ~133 MB on Windows, plus the retired generation. A `bad_alloc` escapes `RenderOnce`/`RenderLoop` on a `std::thread`, which calls `std::terminate`. The software path is exactly where large frames land after a Vulkan failure.

**Fix:** Catch `std::bad_alloc`, set `*error`, release partial buffers and return `false` (see the CR-01 snippet). The engine's fallback ring and backoff then apply.

### WR-06: `Start()` lets `std::system_error` from `std::thread` escape; the destructor's "thread never ran" path is unreachable in the plugins

**File:** `packages/mpv_kit_video/src/video_renderer.cc:362-364`, `:277-287`

**Issue:** If `std::thread` construction throws, `Start` propagates the exception with `render_ctx_` live and the update callback registered. None of the three plugins catches it:
- On Linux it unwinds through a GLib C callback, which is undefined behaviour.
- On Windows it unwinds through the Flutter method handler, so `std::terminate` is likely.

The destructor fallback added in 12-11 (bind, remove the callback, `Release`) is therefore dead in practice. It also runs only if the caller survives the exception.

**Fix:** Handle it inside `Start`:
```cpp
api_.render_context_set_update_callback(render_ctx_, &OnMpvUpdate, this);
try {
  thread_ = std::thread(&VideoRenderer::RenderLoop, this);
} catch (const std::system_error& e) {
  api_.render_context_set_update_callback(render_ctx_, nullptr, nullptr);
  render_backend_->Release(api_, render_ctx_);
  render_ctx_ = nullptr;
  render_backend_.reset();
  backend_reason_ = std::string("render thread: ") + SanitizeReasonField(e.what());
  return false;
}
```
After that, the destructor fallback can be removed.

## Info

### IN-01: Redundant `retired_front_` resets

**File:** `packages/mpv_kit_video/src/video_renderer.cc:708, 751`
**Issue:** Line 708 repeats the unconditional reset at line 703. Line 751 repeats the reset at line 741 on the same branch.
**Fix:** Drop the duplicates. Keep the comments at lines 700-702 and 737-740.

### IN-02: Hard-coded "Vulkan" in log lines that the generic engine now emits

**File:** `packages/mpv_kit_video/src/video_renderer.cc:351-353, 658`
**Issue:** The fallback notice only fires for `a.api == "vulkan"`, and the device-lost log says "Vulkan device lost" for any backend. Once Phase 14/15 add `d3d11` and `opengl`, a failed platform backend logs no fallback line, and a lost D3D11 device is reported as a Vulkan one.
**Fix:** Use `a.api` and `render_backend_->wire_name()` in both messages, or note them as Phase 14 follow-ups.

### IN-03: `wire_name()` dereferences `render_backend_` unconditionally

**File:** `packages/mpv_kit_video/src/video_renderer.h:134`
**Issue:** The precondition is only in a comment. `backend()` right above it is null-safe. A plugin path that calls it after a failed `Start` (for example, logging) crashes.
**Fix:** `return render_backend_ ? render_backend_->wire_name() : "";`, or an `assert`.

### IN-04: Stale file header in `video_renderer.h`

**File:** `packages/mpv_kit_video/src/video_renderer.h:1-6`
**Issue:** It still describes "Two backends" as part of the renderer. Since 12-09 the backends sit behind `RenderBackend` (`render_backend.h`) and the chain is data.
**Fix:** Point to `render_backend.h` and the candidate chain.

### IN-05: Stale source line reference in the impeller smoke test

**File:** `example/integration_test/impeller_smoke_test.dart:43-44`
**Issue:** It cites `video_renderer.h:171` for `kIdleTimeout`, which is now at line 190.
**Fix:** Cite the symbol name rather than a line number.

### IN-06: No test for the `MPV_KIT_VIDEO_API` echo with control, `;` or non-ASCII bytes

**File:** `native/tests/video_renderer_api_test.cc:200-250`
**Issue:** Only upper case (`VULKAN`) exercises the `?` substitution. The bytes the echo exists to defuse are untested: `;`, `\n`, bytes >= 0x80 (signed `char`) and a space.
**Fix:** Add one scenario, for example `"vk;\n\xc3\xa9 x"`, with the expected echo `vk?????x` in `golden/api_override.txt` (not one of the frozen goldens, so it can be extended).

---

_Reviewed: 2026-10-27T02:42:23Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_

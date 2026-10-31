---
created: 2026-10-27T03:30:00.000Z
title: Phase 12 code review and UI review follow-ups (WR-02..WR-06, IN-01..IN-06, UI warnings, CR-01 residuals)
area: video-output
severity: minor
files:
  - packages/mpv_kit_video/src/video_renderer.cc
  - packages/mpv_kit_video/src/video_renderer.h
  - packages/mpv_kit_video/src/render_backend.h
  - packages/mpv_kit_video/windows/mpv_kit_video_plugin.cpp
  - packages/mpv_kit_video/linux/mpv_kit_video_plugin.cc
  - packages/mpv_kit_video/macos/Classes/MpvKitVideoPlugin.mm
  - packages/mpv_kit_video/lib/src/video_controller.dart
  - packages/mpv_kit_video/README.md
  - native/tests/meson.build
  - native/tests/video_renderer_api_test.cc
  - example/integration_test/impeller_smoke_test.dart
---

## Problem

The Phase 12 code review (`.planning/phases/12-renderbackend-seam/12-REVIEW.md`, commit ae5c286) reported 1 blocker, 6 warnings and 6 infos. The UI review (`12-UI-REVIEW.md`) reported 3 warnings. The user decided (verbatim: "a") to fix CR-01 now and send the rest here. CR-01 and WR-01 are fixed (see `12-REVIEW-DISPOSITION.md`). Everything below is still open.

Line numbers are for the tree after the CR-01 fix (025bdad). The `video_renderer.cc` lines after about 184 moved by +11 compared with the review.

## Open items

### Code review warnings

- **WR-02** `video_renderer.cc:15` (`SanitizeReasonField`), `:39` (`Trail`), `:357` (`Trail(c, why)` with backend text). Reason fields pass bytes >= 0x80 unchecked, so invalid UTF-8 breaks the channel codec on Windows/Linux and becomes `""` on macOS. **Fix:** call `SanitizeReasonField(why)` inside `Trail`, and map invalid UTF-8 (or every byte >= 0x80) to `?`.
- **WR-03** `native/tests/meson.build`: golden_sw, golden_vk, golden_vk_fallback, both retire-twice goldens and sw_hold_front_test inherit `MPV_KIT_VIDEO_API` from the environment. **Fix:** set `environment({'MPV_KIT_VIDEO_API': ''})` on every renderer `test()` (merge it into `golden_vk_env`).
- **WR-04** `windows/mpv_kit_video_plugin.cpp:262` and `linux/mpv_kit_video_plugin.cc:377` (`renderer.reset()` on dispose). Software pixels are freed while the engine may still be uploading the last frame. **Fix:** for software, defer `renderer.reset()` into the `UnregisterTexture` completion (Windows) or the existing `g_timeout_add` release (Linux), after `Release()`. Or use `FlutterDesktopPixelBuffer::release_callback`.
- **WR-05** `video_renderer.cc:184-207` (`SoftwareBackend::AllocTargets`): `std::bad_alloc` escapes onto the render thread and calls `std::terminate`. The CR-01 fix keeps one more retired generation, so the peak is now three generations while the new ring is allocated. **Fix:** catch `bad_alloc`, set `*error`, free the partial buffers and return `false`.
- **WR-06** `video_renderer.cc:374` (`thread_ = std::thread(...)`): `std::system_error` escapes `Start` with the render context live. **Fix:** catch it in `Start`, remove the update callback, `Release` the context, reset the backend, set `backend_reason_` and return `false`. Then remove the dead destructor fallback.

### Code review infos

- **IN-01** `video_renderer.cc:719` and `:762`: these `retired_front_` resets repeat `:714` and `:752`. **Fix:** drop the duplicates and keep the comments.
- **IN-02** `video_renderer.cc:362-364` (fallback notice only for `a.api == "vulkan"`) and `:669` ("Vulkan device lost"). **Fix:** use `a.api` and `render_backend_->wire_name()` before Phase 14/15 add d3d11/opengl.
- **IN-03** `video_renderer.h:134`: `wire_name()` dereferences `render_backend_` unconditionally. **Fix:** `return render_backend_ ? render_backend_->wire_name() : "";`
- **IN-04** `video_renderer.h:1-6`: the stale "Two backends" file header. **Fix:** point to `render_backend.h` and the candidate chain.
- **IN-05** `example/integration_test/impeller_smoke_test.dart:43-44` cites `video_renderer.h:171` for `kIdleTimeout`. **Fix:** cite the symbol, not a line number.
- **IN-06** `native/tests/video_renderer_api_test.cc:200-250`: there is no echo test for `;`, control or non-ASCII bytes. **Fix:** add a scenario such as `"vk;\n\xc3\xa9 x"` with the expected echo `vk?????x` in `golden/api_override.txt` (not frozen).

### UI review warnings

- **UI-W1** `packages/mpv_kit_video/lib/src/video_controller.dart:18` (`enum MpvVideoBackend { vulkan, software }`). `vulkan` now means "any GPU zero-copy API", and the enum doc is Chinese only. **Fix:** lead the dartdoc with "GPU zero-copy (not necessarily Vulkan)" in English and show `reason.split(' ').first` for the real API. The API freeze forbids a rename.
- **UI-W2** `packages/mpv_kit_video/README.md:68` links to `blob/main/docs/adr/0004-render-backend-reporting.md`, which is dead on pub.dev until the merge and moves with `main` later. **Fix:** pin the link to a tag, or ship the grammar inline.
- **UI-W3** `video_controller.dart:221` (the creation `debugPrint`): there is no runtime hint when `MPV_KIT_VIDEO_API` is set, and `create` then fails with no fallback. **Fix:** make the one-line `debugPrint` say when the override is active.

### CR-01 residuals (found while fixing CR-01, not in the review)

- **CR-01-R1** `video_renderer.cc:184-207`: the software backend now keeps two retired generations. A frame handed out from three generations back is still freed early. Two cases reach that:
  - a third reallocation before the compositor takes another frame;
  - a second reallocation after the retired front was handed out, again with no acquisition in between.

  Both need resizes faster than the compositor acquires. That is most plausible with an offstage texture, which is not uploading at the time. A precise fix needs the engine to tell the backend which generation backs the last `AcquireFront()`, which is a seam change.
  **Fix:** decide in Phase 14 (seam work). One option is to pass the last handed-out generation or slot to `AllocTargets`. Another is to refcount the software buffers and release them from `FlutterDesktopPixelBuffer::release_callback`.
- **CR-01-R2** `video_renderer.cc:842-844` (countdown start). After resize, failed render, resize, `retired_front_` is cleared, so the countdown never starts. `FreeRetired()` is then not called until the next resize's countdown, and the software backend holds the two retired generations until then: up to 2 x ring x w x h x 4 bytes. Before the fix this was one generation. **Fix:** start the countdown at the first new-size publish whenever a reallocation retired anything, not only when `retired_front_` is set. Check the vk goldens, since FreeRetired is a no-op there after a keep -1 reallocation.

## Solution

Take these with the Phase 14 seam work, or in a small cleanup plan before it. Each item is small and can be rolled back on its own. WR-02 through WR-06 need a regression test first, in new files: the five frozen files stay byte-identical (`evidence/golden-freeze.sha256`).

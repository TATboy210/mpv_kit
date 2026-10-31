---
last_mapped_commit: cd47d6761925b8ccb49e153864bf9789dc3f5039
last_mapped_at: 2026-10-27
---
# Codebase Concerns

**Analysis Date:** 2026-10-27

Sources: code in `packages/`, `native/tests/`, `native/patches/`, plus the open todos `.planning/todos/pending/2026-10-27-*.md` and `.planning/phases/12-renderbackend-seam/12-REVIEW.md` / `12-REVIEW-DISPOSITION.md`. CR-01 and WR-01 are fixed in `025bdad`. Every other review finding is open. Line numbers refer to the tree after `025bdad`.

## Tech Debt

**Software backend generation lifetime (CR-01 residuals R1/R2):**
- Issue: `SoftwareBackend::AllocTargets` keeps two retired generations (`retired_`, `older_`). A frame handed out three generations back is still freed early (R1). After a resize, a failed render and another resize, `retired_front_` is cleared, so the `FreeRetired()` countdown never starts. Up to 2 x ring x w x h x 4 bytes then stay held until the next resize (R2).
- Files: `packages/mpv_kit_video/src/video_renderer.cc:184-207` (AllocTargets/FreeRetired), `:842-844` (countdown start)
- Impact: R1 is a possible use-after-free under resizes faster than compositor acquisition, most likely with an offstage texture. R2 holds extra memory, which adds up at 4K/8K.
- Fix approach: R1 needs a seam change (deferred to Phase 14). Either pass the last handed-out generation to `AllocTargets`, or refcount the buffers and release them via `FlutterDesktopPixelBuffer::release_callback`. R2: start the countdown at the first new-size publish whenever a reallocation retired anything, then re-check the vk goldens.

**Vulkan-specific wording in the generic engine (IN-02, IN-04, UI-W1):**
- Issue: The fallback notice fires only for `a.api == "vulkan"`, and the log text "Vulkan device lost" is hard-coded. The file header still says "Two backends". `MpvVideoBackend.vulkan` now means "any GPU zero-copy API" and has only a Chinese doc.
- Files: `packages/mpv_kit_video/src/video_renderer.cc:362-364`, `:669`; `packages/mpv_kit_video/src/video_renderer.h:1-6`; `packages/mpv_kit_video/lib/src/video_controller.dart:18`
- Impact: Diagnostics will be misleading once d3d11/opengl backends land (Phases 14/15). The enum cannot be renamed because the public API is frozen.
- Fix approach: Use `a.api` / `render_backend_->wire_name()`. Rewrite the header to point at `render_backend.h`. Lead the enum dartdoc in English with "GPU zero-copy (not necessarily Vulkan)".

**Redundant resets and stale references (IN-01, IN-05):**
- Files: `packages/mpv_kit_video/src/video_renderer.cc:719`, `:762` (duplicate `retired_front_` resets); `example/integration_test/impeller_smoke_test.dart:43-44` (cites `video_renderer.h:171` instead of the `kIdleTimeout` symbol)
- Fix approach: Remove the duplicate resets and keep their comments. Cite the symbol instead of the line number.

**Formatting not enforced:**
- Issue: CI runs `analyze --fatal-infos` but has no `dart format --set-exit-if-changed` gate.
- Files: `.github/workflows/flutter-plugin.yml`, `.github/workflows/native-verify.yml`
- Fix approach: Add a format-check step.

## Known Bugs

**Second controller in the same process never reaches first frame (major, cause unknown):**
- Symptoms: In resize-front round 2 (a fresh controller), the run times out 30 s after `set-size-1280-done` with `StateError: resize-front: no 1280x720 resize in round 2`, even though `resizeEvents=3`. The unmet condition is most likely `estimated-vf-fps > 0`. In d05 part 2, every run reads `nonBlackRatio 0.0`, `probeTiming before-first-frame` and `longestMountMs` of about 32.1 s. The readings are the same before and after the Phase 12 fixes, with Impeller on and off (RTX 4060).
- Files: `example/integration_test/impeller_smoke_modes.dart:324-342`, `:620-640`; `packages/mpv_kit_video/src/video_renderer.cc`; `.planning/phases/12-renderbackend-seam/evidence/final-runs.txt`, `postfix-runs.txt`; `docs/perf/renderbackend-seam-regression.md`
- Trigger: Create, dispose and create a second `MpvVideoController` in one process, then resize.
- Workaround: None. The result is classified `inconclusive` (resize-front) or `failed (pixel probe only)` (d05).
- Todo: `.planning/todos/pending/2026-10-27-diagnose-second-controller-first-frame-stall-in-resize-front.md`. Diagnose only. Separate presented-frame count from `estimated-vf-fps` at each poll, and decide whether the harness or the product is wrong.

**Dispose frees software pixels during the last upload (WR-04):**
- Symptoms: Possible read of freed memory by the raster thread on dispose (software path).
- Files: `packages/mpv_kit_video/windows/mpv_kit_video_plugin.cpp:262` (`inst->renderer.reset()`), `packages/mpv_kit_video/linux/mpv_kit_video_plugin.cc:377` (`st->renderer.reset()`)
- Fix: Release the render context first, then defer `renderer.reset()` into the `UnregisterTexture` completion (Windows) or the existing `g_timeout_add` release (Linux).

**Render-thread exceptions terminate the process (WR-05, WR-06):**
- Symptoms: `buffers_.assign(...)` in `SoftwareBackend::AllocTargets` can throw `std::bad_alloc` on the render thread, which calls `std::terminate`. Peak memory is now three generations during reallocation. `thread_ = std::thread(...)` in `VideoRenderer::Start` can throw `std::system_error` while the render context and update callback are live.
- Files: `packages/mpv_kit_video/src/video_renderer.cc:184-207`, `:374`
- Fix: Catch `bad_alloc`, set `*error`, free partial buffers and return `false` so backoff and fallback apply. In `Start`, catch `system_error`, unset the update callback, release the context, reset the backend, set `backend_reason_` and return `false`. Then delete the unreachable destructor fallback.

**`wire_name()` null dereference (IN-03):**
- Files: `packages/mpv_kit_video/src/video_renderer.h:134`
- Fix: `return render_backend_ ? render_backend_->wire_name() : "";`

## Security Considerations

**Reason strings not UTF-8 safe (WR-02):**
- Risk: `SanitizeReasonField` maps only `;` and bytes below 0x20. Bytes >= 0x80 pass through, and `Trail()` does not sanitise backend-supplied `why` text. Invalid UTF-8 breaks the method-channel codec on Windows/Linux and becomes `""` on macOS. `MPV_KIT_VIDEO_API` values are echoed into this text.
- Files: `packages/mpv_kit_video/src/video_renderer.cc:15-24`, `:39-41`, `:357`; `native/tests/video_renderer_api_test.cc:200-250` (no echo test, IN-06)
- Current mitigation: Control bytes and `;` are replaced.
- Recommendations: Sanitise inside `Trail` and map every byte >= 0x80 to `?`. Add the `"vk;\n\xc3\xa9 x"` -> `vk?????x` scenario to `golden/api_override.txt`.

**Silent API override (UI-W3):**
- Risk: When `MPV_KIT_VIDEO_API` is set, `create` fails with no fallback, and the log gives no hint that the override is active.
- Files: `packages/mpv_kit_video/lib/src/video_controller.dart:221`
- Recommendations: Mention the active override in the creation `debugPrint`.

**Bundle supply chain:**
- Risk: libmpv binaries are downloaded at build time.
- Files: `packages/mpv_kit_libs/lib/src/bundles.dart`, `packages/mpv_kit_libs/lib/src/bundle.dart`
- Current mitigation: Per-target sha256 pins (`bundleTag`), a tar reader that rejects malformed archives (`tar.dart`), and the LGPL/ABI audit (`tools/rea_abi_audit/pe_audit.py`).
- Recommendations: Pins must be regenerated only through `tools/pin_bundles.dart`. Never hand-edit them.

## Performance Bottlenecks

**Software fallback memory at UHD:**
- Problem: Each reallocation keeps up to three generations of `ring x w x h x 4` bytes. At 8K with ring 7 (Windows), one generation is about 930 MB.
- Files: `packages/mpv_kit_video/src/video_renderer.cc:184-207`, `packages/mpv_kit_video/src/video_renderer.h` (ring/quarantine sizes)
- Cause: CR-01 fix plus CR-01-R2.
- Improvement path: Fix R2, then cap or refcount the generations (Phase 14).

## Fragile Areas

**Frame ring / quarantine without cross-API fences:**
- Files: `packages/mpv_kit_video/src/video_renderer.h` (`CompositorLatency`, ring = front + in use + quarantine + free), `packages/mpv_kit_video/src/vulkan_backend.cc`, `docs/ARCHITECTURE.md`
- Why fragile: Correctness depends on quarantine counts (Windows 4, others 2) and timeline waits. There is no keyed mutex or fence with ANGLE or Metal.
- Safe modification: Add a RED native test first (pattern: `native/tests/video_renderer_sw_hold_front_test.cc`). Keep the frozen goldens byte-identical by checking with `sha256sum -c .planning/phases/12-renderbackend-seam/evidence/golden-freeze.sha256`.
- Test coverage: The backend bind and call-order contract is not tested (Nyquist gap RBE-05/03).

**Timing-sensitive goldens (macOS vk-gpu-timeout flake):**
- Files: `native/tests/meson.build` (250 ms non-sanitizer slack), frozen `golden_vk.cc` / `golden/vk.txt`
- Why fragile: native-verify run 40432973419 (docs-only commit 4d46d70) failed with `GOLDEN mismatch scenario=vk-gpu-timeout line=13` on macos-15. At least four code-identical runs passed. This is the T-12-11 class, tracked in `12-SECURITY.md` Notes c.
- Safe modification: Make a macOS-only slack argument in meson. Do not edit the goldens without an explicit unfreeze decision. Todo: `.planning/todos/pending/2026-10-27-vk-gpu-timeout-golden-flake-macos.md`.

**Test environment leakage (WR-03):**
- Files: `native/tests/meson.build:68-163`
- Why fragile: golden_sw, golden_vk, golden_vk_fallback, both retire-twice goldens and sw_hold_front_test inherit `MPV_KIT_VIDEO_API` from the environment.
- Safe modification: Set `MPV_KIT_VIDEO_API` to `''` on every renderer `test()` by merging it into `golden_vk_env`.

**Dispose ordering and process-wide library cache:**
- Files: `packages/mpv_kit/lib/src/ffi/library.dart:30` (static `_bindings`; a later `open(path:)` with a different path is ignored), `packages/mpv_kit/lib/src/player/player.dart` (`addDisposeHook`), `packages/mpv_kit/lib/src/core/stream_bridge.dart`
- Why fragile: The render context must die before the mpv core. A stream source that never completes stalls mpv's demuxer thread.
- Safe modification: Keep the controller-before-player order and the protocol shutdown that runs before core destroy.

**Large hand-written files:**
- Files: `packages/mpv_kit/lib/src/player/player.dart` (936 lines), `packages/mpv_kit_video/src/video_renderer.cc` (858), `packages/mpv_kit/lib/src/ffi/bindings.dart` (858), `packages/mpv_kit/lib/src/core/mpv.dart` (828)
- Why fragile: Each is above the 800-line guideline. Split them only with minimal, separately revertible changes, because the API is frozen.

## Scaling Limits

**One libmpv per process:**
- Current capacity: One `DynamicLibrary` mapping and client API major 2 only (`library.dart`).
- Limit: Switching libraries requires a new process.
- Scaling path: Not planned (by design).

**Multiple controllers per process:**
- Current capacity: The first controller works. A second one shows the first-frame stall described under Known Bugs.
- Limit: Unverified beyond one controller.
- Scaling path: Diagnosis todo above.

## Dependencies at Risk

**Patched vendored mpv (`native/mpv/`, third-party):**
- Risk: Eight downstream patches totalling 2,164 lines (`native/patches/0001`-`0009`; 0005 is merged into 0004). The largest are 0004 gpu-next/renderer report (643 lines), 0001 Vulkan render backend (554) and 0006 asynchronous stream bridge (440). 0008 keeps `video/out/wayland_common.c` at a pre-refactor snapshot, marked "revisit before the next rebase". 0009 carries upstream backports.
- Impact: Every rebase means hand-rebasing the render API hunks. Drift breaks the byte-identical provenance gate (`tools/check_patches.sh`, `patch-drift` job).
- Migration plan: Upstream the patches as tracked in `native/patches/UPSTREAM.md`. Drop backports once the base moves past them.

**Pinned native stack:**
- Risk: FFmpeg 8.1.3, libplacebo 7.360.1, MoltenVK 1.4.2 and others are pinned in `native/build/deps.sh` and `ffmpeg.sh`. Security updates need a manual bump and release. The macOS bundle needs macOS 15 although the documented floor is 12.
- Migration plan: Bump the pins periodically and re-run the release workflow.

**Unstable docs link (UI-W2):**
- Files: `packages/mpv_kit_video/README.md:68` links to `blob/main/docs/adr/0004-render-backend-reporting.md`. The link is dead on pub.dev until the merge and moves with `main` afterwards.
- Fix: Pin it to a tag, or put the grammar inline.

## Missing Critical Features

**No backend contract test harness:**
- Problem: There is no recording `RenderBackend` injected through `CreateBackend` / `BackendCandidates` (`video_renderer.h` ~:79, :85).
- Blocks: Safe Phase 14/15 seam work (d3d11/opengl backends).

## Test Coverage Gaps

**Phase 12 Nyquist gaps (`12-VALIDATION.md`: nyquist_compliant false):**
- What's not tested:
  - RBE-05/03: bind and call order (`native/tests/video_renderer_bind_test.cc` missing).
  - RBE-07: reason regex on the real plugin (`example/integration_test/backend_reason_test.dart` missing).
  - RBE-08: `MPV_KIT_VIDEO_API=software` override in CI (`api_override_test.dart` missing).
  - RBE-04: `tools/constants_audit.sh` and the golden-freeze sha256 check are not in the patch-drift job.
  - RBE-01: no scheduled 100-round `impeller_smoke_test` cycles job on lavapipe.
- Files: `.planning/todos/pending/2026-10-27-phase-12-nyquist-validation-gaps.md`, `.github/workflows/native-verify.yml`
- Risk: Seam regressions and override behaviour can break without CI noticing.
- Priority: High for RBE-05/03 (before Phase 14), Medium for the rest.

**No regression tests for WR-02..WR-06:**
- What's not tested: UTF-8 reason echo, environment isolation, dispose during upload, `bad_alloc` and thread-start failure.
- Files: `native/tests/` (new files required; the five frozen files stay byte-identical)
- Risk: Crashes on rare paths.
- Priority: Medium.

**Real-GPU behaviour only partly in CI:**
- What's not tested: The second-controller stall and d05 pixel probe were seen only on local RTX 4060 runs. Hosted CI uses lavapipe or hosted macOS.
- Risk: GPU-specific regressions.
- Priority: Medium.

---

*Concerns audit: 2026-10-27*

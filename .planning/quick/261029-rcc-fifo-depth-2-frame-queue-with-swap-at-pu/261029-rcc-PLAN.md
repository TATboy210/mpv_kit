---
phase: quick-261029-rcc
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - packages/mpv_kit_video/src/video_renderer.h
  - packages/mpv_kit_video/src/video_renderer.cc
  - packages/mpv_kit_video/windows/mpv_kit_video_plugin.cpp
  - native/tests/video_renderer_swap_test.cc
  - native/tests/video_renderer_superseded_test.cc
  - native/tests/meson.build
  - native/tests/golden/vk.txt
  - native/tests/golden/vk_fallback.txt
  - native/tests/golden/vk_retire_twice.txt
  - native/tests/video_renderer_golden_vk_fallback.cc
  - native/tests/video_renderer_golden_vk_retire_twice.cc
  - native/tests/video_renderer_golden_sw_retire_twice.cc
  - native/tests/video_renderer_affinity_test.cc
  - native/tests/video_renderer_bind_test.cc
  - docs/ARCHITECTURE.md
  - .planning/phases/14-windows-native-d3d11-backend/evidence/golden-freeze-14-rcc.sha256
  - .planning/phases/14-windows-native-d3d11-backend/evidence/laptop-package.txt
  - .planning/quick/261029-rcc-fifo-depth-2-frame-queue-with-swap-at-pu/261029-rcc-PLAN.md
  - .planning/quick/261029-rcc-fifo-depth-2-frame-queue-with-swap-at-pu/261029-rcc-CONTEXT.md
  - .planning/quick/261029-rcc-fifo-depth-2-frame-queue-with-swap-at-pu/261029-rcc-AB.txt
  - .planning/quick/261029-rcc-fifo-depth-2-frame-queue-with-swap-at-pu/261029-rcc-native-tests.log
autonomous: false
requirements: [RBE-05, D3D-06]

estimate:
  tokens: 260000
  raw_tokens: 260000
  tasks: 3
  confidence: low

must_haves:
  truths:
    - "Every frame VideoRenderer publishes gets exactly one mpv_render_context_report_swap on the render thread right after the publish, before Interop::FrameReady; no swap waits for AcquireFront and no present-timeout path remains; RBE-05 holds (affinity_test and bind_test green with debug asserts on)."
    - "Published frames wait in a FIFO of at most two (kReadyDepth). AcquireFront hands out the oldest frame the compositor has not taken yet, else the frame it holds again (counted as repeated=). A publish into a full queue drops the oldest waiting frame (counted as superseded=). When AcquireFront takes the older of two waiting frames it calls Interop::FrameReady once more, after releasing the renderer lock, so the mark-driven Flutter compositor takes the newer one at its next frame (counted as queued=). The 120-frame probe line ends with ` superseded=<n> repeated=<n> queued=<n>`. Idle detection (last_acquire_) and video-sync=audio are unchanged."
    - "Ring = front + one waiting frame + in use + quarantine + one free image (quarantine + 4: Windows 8, other platforms 6). PickBackBuffer never returns front_, queued_, in_use_ or a quarantined slot. The allocation fallback keeps its old footprint (quarantine 2, ring 5) and runs without a waiting frame (newest wins on that path)."
    - "video_renderer_swap_test (10 scenarios, fake libmpv, no GPU) is RED at HEAD 4be7678 and GREEN after the change; every locally buildable renderer test passes 3x under MSVC /W4 /WX with asserts on; the frozen harness, golden_sw.cc, golden_vk.cc and sw.txt are byte-identical; vk.txt changes only by the ring's extra image (create/destroy of that image and serial renumbering, checked by build/rcc/golden_check.py) and only after the user's approval is recorded in 261029-rcc-CONTEXT.md, with golden-freeze-14-rcc.sha256 superseding golden-freeze-14.sha256."
    - "On the RTX 4060 (4K60 lavfi with sine, ao=null, 150 s, auto and MPV_KIT_VIDEO_API=d3d11; baseline = HEAD 4be7678), effective drops (mpv frame-drop-count delta + superseded) are at most baseline + 2 per config, avsync within 10x, pickup median at most baseline + 20 ms, no new render errors; recorded as ab_gate=PASS in 261029-rcc-AB.txt; real_plugin_test and d3d11_backend_test pass locally."
    - "package4 (`mpv_kit_d3d11_demo_<sha>_fifo`) sits on the desktop, verified like package3 (bundle_match, angle_audit, debug switches absent, adapter line, power line, FIFO counters in the DLL and the smoke log), its launchers write numbered `mpv_kit_fifo_{auto,d3d11}_log_<N>.txt` whose first line names the FIFO build; `## package4` is committed alone; the user has run it on the laptop on AC and replied."
  artifacts:
    - path: "packages/mpv_kit_video/src/video_renderer.cc"
      provides: "swap at publish; FIFO ready queue with re-notify; repeated=/queued= probe counters; ring = quarantine + 4"
      contains: " queued="
    - path: "packages/mpv_kit_video/src/video_renderer.h"
      provides: "queued_, ready_depth_, kReadyDepth, probe_repeated_, probe_queued_; FrameReady and AcquireFront contracts"
      contains: "kReadyDepth"
    - path: "packages/mpv_kit_video/windows/mpv_kit_video_plugin.cpp"
      provides: "pickup measured from the FrameReady stamp read before AcquireFront"
      contains: "RecordPickup(inst, "
    - path: "native/tests/video_renderer_swap_test.cc"
      provides: "swap at publish, FIFO order, cap drop, repeat, re-notify, resize/retire, idle, failure, allocation fallback"
      contains: "SWAP ok scenarios="
    - path: "native/tests/meson.build"
      provides: "video_renderer_swap_test on every CI platform and under the sanitizers (replaces video_renderer_superseded_test)"
      contains: "video_renderer_swap_test"
    - path: ".planning/phases/14-windows-native-d3d11-backend/evidence/golden-freeze-14-rcc.sha256"
      provides: "re-freeze record: vk.txt new hash, the other four frozen files unchanged"
      contains: "native/tests/golden/vk.txt"
    - path: "docs/ARCHITECTURE.md"
      provides: "swap reporting at publish, frame queue, ring sizes"
      contains: "reported when it is published"
    - path: ".planning/phases/14-windows-native-d3d11-backend/evidence/laptop-package.txt"
      provides: "package4 provenance"
      contains: "## package4"
  key_links:
    - from: "VideoRenderer::RenderOnce publish block (front_/queued_ under mutex_)"
      to: "vo_libmpv flip_page wait on flip_count (native/mpv/video/out/vo_libmpv.c:526-563)"
      via: "ReportSwaps(1) -> api_.render_context_report_swap, before interop_->FrameReady()"
      pattern: "ReportSwaps\\(1\\)"
    - from: "VideoRenderer::AcquireFront (compositor thread) taking queued_"
      to: "Flutter EmbedderExternalTextureGL/Metal::MarkNewFrameAvailable (texture callback only runs after a mark)"
      via: "interop_->FrameReady() after the renderer lock is released -> platform mark (MarkTextureFrameAvailable / fl_texture_registrar_mark_texture_frame_available / textureFrameAvailable)"
      pattern: "FrameReady\\(\\)"
    - from: "VideoRenderer::PickBackBuffer"
      to: "ring_size_ = quarantine_count_ + 2 + ready depth (Start, allocation fallback)"
      via: "busy set front_, queued_, in_use_, quarantine_[]"
      pattern: "queued_"
    - from: "D3D11 plugin Describe (raster thread)"
      to: "RecordPickup pickup log line"
      via: "frame_ready_ns stamp loaded before AcquireFront, so a re-notify inside AcquireFront does not mask the pickup"
      pattern: "RecordPickup\\(inst, "
  prohibitions:
    - requirement_id: RBE-05
      category: scope
      status: unresolved
      verification: null
      statement: "MUST NOT call any mpv_render_* function outside the render thread (AcquireFront calls only Interop::FrameReady/RetainFrame); MUST NOT change any Dart file, the public API, the reason grammar or kWindowsApiOrder; MUST NOT edit renderer_harness.h, video_renderer_golden_sw.cc, video_renderer_golden_vk.cc or golden/sw.txt; MUST NOT edit golden/vk.txt unless `golden_refreeze: approved` is recorded in 261029-rcc-CONTEXT.md."
    - requirement_id: D3D-06
      category: process
      status: unresolved
      verification: null
      statement: "MUST keep the Windows quarantine at 4; MUST NOT commit the temporary libmpv_bundle hooks user_define in the root pubspec.yaml; MUST NOT push; MUST NOT stage or modify .planning/config.json, .planning/state.json, .planning/tmp/, .planning/ui-reviews/, .planning/debug/ or engine_repo_embedder.cc."
---

<objective>
Replace "swap at compositor pickup" with "swap at publish plus a depth-2 FIFO of finished frames" in the shared video renderer, prove it on the RTX 4060 against HEAD, and ship laptop package4 so the GTX 960M result decides between this and step 2 (timestamp picker, deferred).

Why both parts: package3 (swap at pickup) keeps mpv's frame-drop-count rising on the laptop (vulkan 3-6 %, d3d11 25-34 %), because vo_libmpv's flip_page waits for our report_swap before the core queues the next frame. package3-control (swap at publish, newest wins) fixed mpv's drops but threw away 10-20 % of rendered frames as `superseded` (two publishes before one compositor pickup). A FIFO lets the second frame wait one compositor frame instead of being replaced.

Two findings from planning change the shape of the work (both verified in local sources, see context):
1. Flutter's desktop embedders call the texture callback only after a frame was marked available (embedder_external_texture_gl.cc:45 resolves only when `last_image_` is null, MarkNewFrameAvailable clears it at :203; Metal the same at :40/:145). One mark yields at most one AcquireFront. So when AcquireFront takes the older of two waiting frames, the renderer must mark again or the queue never drains (the FIFO would degrade to newest-wins plus latency). The render thread cannot do that mark: with BLOCK_FOR_TARGET_TIME (default 1) it sits inside mpv_render_context_render until the next frame's target time (vo_libmpv.c:395-432). So AcquireFront itself calls Interop::FrameReady after releasing the renderer lock.
2. The extra ring image (quarantine + 4) is visible in the frozen golden vk.txt, which lists every image the renderer creates. The FIFO cannot ship with vk.txt byte-identical. The plan builds and checks a mechanical vk.txt proposal, and only applies it when the user's approval is recorded; otherwise it stops before the commit with all evidence prepared.

Purpose: give mpv its full frame budget on slow GPUs without losing the frames that jitter between publish and pickup, with every libmpv call still on the render thread (RBE-05).
Output: one code+tests+docs commit (with the re-freeze record), one `## package4` evidence commit, package4 on the desktop, and the user's laptop reply.
</objective>

<execution_context>
@~/.claude/gsd-core/workflows/execute-plan.md
@~/.claude/gsd-core/templates/summary.md
</execution_context>

<context>
@.planning/STATE.md
@CLAUDE.md
@.planning/quick/261029-rcc-fifo-depth-2-frame-queue-with-swap-at-pu/261029-rcc-CONTEXT.md
@packages/mpv_kit_video/src/video_renderer.h
@packages/mpv_kit_video/src/video_renderer.cc
@docs/ARCHITECTURE.md
@.planning/quick/261029-nwm-report-swap-at-publish-power-aware-gpu-p/261029-nwm-PLAN.md

Facts the planner verified; do not re-derive them.
- HEAD 4be7678 (branch feat/mpv-master-upgrade). video_renderer.{h,cc} are unchanged since 6a712eb. `git apply --check build/nwm/fix-control.patch` succeeds on HEAD: that patch is exactly the swap-at-publish part (removes the swap members, the present-timeout deadline and branch, the "woken only to report swaps" branch and the AcquireFront swap counting; adds ReportSwaps(1) after the publish block). Apply it first, then add the FIFO on top.
- Line map at HEAD, video_renderer.h: Interop::FrameReady doc 67-69; AcquireFront doc 119-124; swap members 175-186; probe members 206-218 (probe_superseded_ 215-218); ring comment 226-234; kMaxQuarantine 236; quarantine_count_ 239; ring_size_ 240; front_ 243; front_acquired_ 244; in_use_ 245; quarantine_ 246; retired_front_ 250.
- Line map at HEAD, video_renderer.cc: Start ring sizing 306-308 (`ring_size_ = quarantine_count_ + 3`); AcquireFront 469-520; PickBackBuffer 522-531; RenderLoop 555-669; RenderOnce resize block 723-749; allocation fallback 751-793 (fallback_quarantine 2, fallback_ring = 2 + 3, condition `ring_size_ > fallback_ring`); probe block 833-847; publish block 856-878.
- Windows plugin packages/mpv_kit_video/windows/mpv_kit_video_plugin.cpp: the D3D11Interop FrameReady lambda (230-237) stores `frame_ready_ns` and calls MarkTextureFrameAvailable (FlutterWindowsTextureRegistrar posts to the platform runner: flutter_windows_texture_registrar.cc:103-109); RecordPickup 305-327 reads `frame_ready_ns` and skips a stamp it already counted; Describe 330-345 calls AcquireFront (333) and then RecordPickup (335). If AcquireFront marks again, the stamp changes before RecordPickup reads it, so the stamp must be loaded before AcquireFront and passed in.
- Every platform FrameReady is lock-free on the plugin side and only marks the texture: Windows (above), Linux gl_interop lambda (linux/mpv_kit_video_plugin.cc:316-319, fl_texture_registrar_mark_texture_frame_available, already called from the render thread today), macOS MetalInterop lambda (macos/Classes/MpvKitVideoPlugin.mm:350-353, textureFrameAvailable). The AcquireFront callers hold their own plugin mutex (Windows Describe, Linux populate 126-135 / 183-188, macOS copyPixelBuffer 107-110); none of the FrameReady lambdas takes it. Engine side: shell.cc:1318-1345 posts MarkNewFrameAvailable to the raster runner and ScheduleFrame to the UI runner, so a mark from inside the texture callback takes effect at the next compositor frame.
- Ring allocation is generic in every backend (vectors sized by count): vulkan_backend.cc:539-543, windows/d3d11_backend.cpp:218-240, the software backend in video_renderer.cc:184-201. Windows CompositorLatency is 4 (d3d11_interop.h:37), others 2.
- Goldens. Frozen (golden-freeze-14.sha256): renderer_harness.h, video_renderer_golden_sw.cc, video_renderer_golden_vk.cc, golden/sw.txt, golden/vk.txt. CI does not read the freeze file; it is a process record (Phase 14 superseded Phase 12's with an explicit user reply). Software traces print buffer ordinals by first use, so the larger ring is invisible in sw.txt and sw_retire_twice.txt. Vulkan traces print one `create serial=` line per image, so vk.txt, vk_fallback.txt and vk_retire_twice.txt change: expected in vk.txt every scenario except vk-reasons (no images) and vk-ring-fallback (ring 8 fails at the 6th CreateImage exactly like ring 7 did, and the fallback ring stays 5). In lockstep scenarios (acquire after every publish) the queue never forms, the extra image is never rendered into (lowest free slot wins), and no extra FrameReady happens. golden_vk takes the golden path as argv[1] and prints `GOLDEN mismatch ...` on stdout and the full actual trace of a mismatching scenario on stderr (`  actual trace of [<name>]:` then each line indented by 4 spaces; renderer_harness.h:1036-1080).
- non-frozen test edits needed: golden_vk_fallback.cc kFullRing = kWindowsLatency + 3 (line 50) feeds kFallbackLog (54-57), so it becomes + 4 and vk_fallback.txt's log line reads `ring 8, retried with a ring of 5`; ring comments at golden_vk_fallback.cc:46-47 and 194-195, golden_vk_retire_twice.cc:185, golden_sw_retire_twice.cc:168; the present-timeout comment above kPastPresentTimeout at golden_vk_fallback.cc:43-44, golden_vk_retire_twice.cc:45-46, golden_sw_retire_twice.cc:41-42 (keep the constant's name and value: it is a settle margin before the quiesce counts); affinity_test.cc:63-65 and bind_test.cc:75-76 (the 2 ms raster period only keeps the compositor active, which keeps the renderer out of idle).
- Stale comments in frozen files that stay (report them in the SUMMARY): renderer_harness.h 365-367 (swaps reported by AcquireFront), video_renderer_golden_sw.cc:40 and video_renderer_golden_vk.cc:47 (present timeout), video_renderer_golden_vk.cc:337, 346, 398-400 (ring 5 / ring 7).
- Harness API (renderer_harness.h): Fake().Reset/QueueFrames(n)/Poke()->seq/WaitPokeSeen(seq)/counters() {renders, skips, swaps}/SetRenderResults(vector)/HoldRenders(bool)/WaitRenderHeld()/WaitSkips(n)/WaitNoted(line)/Note/DrainAsync; golden::MakeApi(), FakeHandle(), SetEnv, CheckSwapInvariant(); FakeInterop(latency, bgra, reason) with frame_ready() and WaitFrameReady(n) (throws TimeoutError after 10 s); the fake writes an incrementing frame number into bytes 0..2 of the target on every successful non-skip render (decode as p[0] | p[1] << 8 | p[2] << 16, as video_renderer_golden_sw.cc:120). Error strings are `fake error -<n>`; MPV_ERROR_GENERIC is -20. native/tests/video_renderer_superseded_test.cc holds a ready FakeGpuBackend (pipelined, CPU buffers, platform = slot buffer), GpuInterop, Run and the log capture; build/nwm/video_renderer_swap_test.cc adds CheckSwapsAtPublish and the swap-at-publish scenarios. Reuse both.
- mpv timing: vo_libmpv.c:395-432 (mpv_render_context_render renders, then with BLOCK_FOR_TARGET_TIME blocks until flip_page bumps present_count at the frame's target time), 509-563 (draw_frame sets expected_flip_count; flip_page waits for report_swap up to 200 ms). With swaps at publish the render thread spends most of each frame period blocked inside the render call, holding the back buffer it picked: that is why the waiting frame needs its own ring image (an "evict at the next render start" variant on a ring of quarantine + 3 would evict almost immediately and behave like newest-wins).
- Expectations to read the numbers correctly: on Flutter's mark-driven texture path a compositor frame without a new mark reuses its cached image without calling AcquireFront, so `repeated=` stays near zero on desktop Flutter (the 59.94 vs 60 Hz display repeat is invisible to the renderer); `queued=` counts frames that newest-wins would have dropped and that are now shown one compositor frame later; `superseded=` counts only frames dropped from a full queue (plus the older waiting frame at a resize or a return from idle). The pickup log measures FrameReady (publish or re-notify) to compositor callback, so the extra display latency of the queue is reported by `queued=`, not by pickup.
- Host: Windows MINGW64 Git Bash, cwd D:/mpv_kit, `/d/flutter/bin/flutter`, MSVC 14.44 (vcvars path as used by build/nwm-tests/build_all.bat), RTX 4060 Laptop GPU at 165 Hz, single hardware adapter. No meson or ffmpeg locally. Repo filesystem D: about 6 GB free; desktop filesystem C: about 2.4 GB free; no mpv_kit_d3d11_demo_* folder is on the desktop right now.
- Reusable scripts (gitignored, under build/): build/nwm/relbuild.sh (Release build with the temporary libmpv_bundle user_define, reverts pubspec.yaml, appends `build rc=` and the porcelain line), run_ab.sh, ab_metrics.sh, smoke.sh, power.ps1, make_pkg.sh, fin_pkg.sh, check_bats.sh, pkg3-src/ and pkg3c-src/ (launchers and 使用说明 sources); build/nwm-tests/build_all.bat and run_all.sh (MSVC /W4 /WX build and meson-arg runner of the renderer tests). Copy and adapt them into build/rcc/ and build/rcc-tests/; do not edit the build/nwm originals. Debug integration env (docs/perf/d3d11-backend.md Reproduce): bundle user_define as in relbuild.sh plus `LIB="$PWD/build/phase14/libmpv-rtx/lib"`, `MPV_KIT_LIBMPV_PATH="$LIB/libmpv-2.dll"`, `MPV_KIT_REQUIRE_LIBMPV=1`, `PATH="$LIB:$PATH"`; revert pubspec.yaml afterwards whatever the exit status.
- All tracked files this plan touches are LF (`git ls-files --eol`); keep them LF. RBE-04 froze the ring/timeout constants only for the Phase 12 move commits; this is a deliberate, measured behaviour change (say so in the SUMMARY).
</context>

<locked_decisions>
From 261029-rcc-CONTEXT.md, "Decision (user, 2026-10-29)". Cited as D-NN.
- D-01: Step 1 = FIFO depth-2 ready queue plus report_swap at publish; video-sync=audio stays.
- D-02: Publish appends to the ready queue (cap 2); when full, the oldest is dropped and counted as superseded.
- D-03: AcquireFront pops the oldest ready frame if any, else repeats the current one; repeats are counted (log only).
- D-04: The ring gets one extra slot (ring_size_ = quarantine + 4); the allocation-failure retry path is checked. Planner's call on the open "ring 5 -> 6?" question: the fallback keeps ring 5 / quarantine 2 and runs with a queue depth of 1, because that path exists for memory pressure (8K on small GPUs) and must not grow; its golden trace stays unchanged.
- D-05: RBE-05 stays (report_swap only on the render thread); idle detection (last_acquire_) stays.
- D-06: Log-only counters on the 120-frame probe line: superseded= (existing), repeated= (new), plus the optional queue statistic, implemented as queued=.
- Deferred, NOT planned: step 2 (timestamp picker on the same queue), display-resample.
- Orchestrator constraint that collides with D-04: the frozen golden files stay unchanged, and if a frozen golden trace changes the executor stops and reports. Resolution in this plan: vk.txt is edited only when `golden_refreeze: approved` is recorded in 261029-rcc-CONTEXT.md (see the golden gate in Task 1); without it Task 1 stops before its commit.
</locked_decisions>

<executor_rules>
- `source /tmp/gsd-bak/root_pin.sh` (PINNED_ROOT='D:/mpv_kit') before the first Edit/Write and before every commit.
- Never stage or modify .planning/config.json, .planning/state.json, .planning/tmp/, .planning/ui-reviews/, .planning/debug/, engine_repo_embedder.cc. Around any gsd-tools call: `cp .planning/state.json /tmp/rcc_state.bak` before, `cmp` after, restore from the backup if it changed. Stage by explicit path only (`git rm` for the deleted test).
- Sequential, main tree, local commits only, never push. Every commit message ends with `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.
- Scratch goes to build/rcc/ and build/rcc-tests/ (gitignored) or /tmp. Evidence files in the quick dir (261029-rcc-AB.txt, 261029-rcc-native-tests.log) are written LF (strip CR from tool output).
- C++ comments in English at the surrounding density. New comments describe behaviour and never name the removed swap members or the removed timeout.
- Before every interactive run `tasklist | grep -i mpv_kit_example` must be empty. During A/B runs and smokes the window stays visible and untouched; no other GPU load.
- Any test failure not predicted by this plan: diagnose; if the cause is the FIFO or ring semantics in a file outside files_modified, or any change to a frozen trace other than the vk.txt rule, STOP and report instead of widening the diff.
</executor_rules>

<package_spec>
Package4 files (Task 2). The .bat files are ASCII, CRLF, no BOM; write them with the Write tool into build/rcc/pkg4-src/ (LF) and convert while copying, as build/nwm/make_pkg.sh does.

run-probe.bat: byte-identical copy of build/nwm/pkg3-src/run-probe.bat (the package3 file).

run-auto-log.bat:

```bat
@echo off
rem mpv_kit demo, FIFO build (quick 261029-rcc), auto backend chain.
rem stdout+stderr go to a new numbered desktop log file; its first line names the FIFO build.
set MPV_KIT_VIDEO_API=
set N=1
:next
if exist "%USERPROFILE%\Desktop\mpv_kit_fifo_auto_log_%N%.txt" (
  set /a N+=1
  goto next
)
set LOG=%USERPROFILE%\Desktop\mpv_kit_fifo_auto_log_%N%.txt
cd /d "%~dp0demo"
echo FIFO BUILD (quick 261029-rcc): swap reported at publish, up to 2 finished frames shown in order> "%LOG%"
echo Logging to %LOG%
echo This is the FIFO build (package4).
echo Close the demo window when done. Do not close this console window.
"%~dp0demo\mpv_kit_example.exe" %* >> "%LOG%" 2>&1
echo Log saved: %LOG%
pause
```

run-d3d11.bat: the same file with `auto backend chain` replaced by `forced d3d11 backend`, `set MPV_KIT_VIDEO_API=d3d11`, and `mpv_kit_fifo_d3d11_log_%N%.txt` in both places.

使用说明.txt (Chinese, UTF-8 with BOM, CRLF). Base it on build/nwm/pkg3c-src/使用说明.txt (structure and tone). Required content, in order:
1. Title `mpv_kit D3D11 演示包 使用说明（版本 <短 SHA>，package4，FIFO）`.
2. 目的: package3 results on this laptop: 主包 (ade3eea, swap at pickup) mpv 掉帧持续上升 (earlier vulkan 3-6 %, d3d11 25-34 %); 对照包 (swapfix) mpv 掉帧约为 0 (vulkan 0, d3d11 共 10)，但约 vulkan 10 %、d3d11 20 % 的帧渲染了却没显示 (superseded=). This build reports each frame to mpv as soon as it is rendered (like the control) and lets up to 2 finished frames wait in order for Flutter (FIFO): a frame that used to be replaced is shown one screen refresh later instead. Expected: dropped close to 0 and superseded close to 0. The probe lines also carry repeated= and queued= (queued= counts the frames shown one refresh later); no action needed.
3. 本目录内容: demo\, d3d11_caps_probe.exe, run-probe.bat, run-auto-log.bat (auto, desktop mpv_kit_fifo_auto_log_<编号>.txt), run-d3d11.bat (forced d3d11, desktop mpv_kit_fifo_d3d11_log_<编号>.txt), 使用说明.txt. Every run creates a new number; the first line of every log reads FIFO BUILD.
4. Step 0: Windows 显示卡 setting and NVIDIA 控制面板 program setting for mpv_kit_example.exe stay at their defaults, as for package3. Copy the folder. Run run-probe.bat only if it has not been run in this boot session (LUIDs change after a reboot).
5. On AC power (charger connected, battery saver off): run-auto-log.bat, then run-d3d11.bat. In each run drag the 3840x2160 59.94 fps H.264 file into the window, press F9 for the HUD, keep the window visible (no minimising, moving or resizing), no seeking, no other programs, play at least 2 minutes and note the actual duration; record backend, reason (full), dropped, dec-drop, avsync, hwdec and fps (a screenshot is fine); close with X and press a key in the console.
6. In every log, report the lines starting `mpv_kit_example: GPU preference`, `mpv_kit: compositor adapter` and `mpv_kit: hybrid GPU hint:` (or 无).
7. 注意: same conditions as the package3 runs (same machine, file and duration, AC, no seeking). The HUD backend label shows vulkan during d3d11 runs (known label issue); a reason starting with "d3d11 (" means D3D11.
8. 请回复: for both runs, duration, reason (full), dropped, dec-drop, avsync, hwdec, fps and the three lines; attach every mpv_kit_fifo_auto_log_*.txt and mpv_kit_fifo_d3d11_log_*.txt (and mpv_kit_d3d11_probe.txt if run-probe.bat was run).
9. 其他说明 as in package3: unsigned dev build (SmartScreen: 仍要运行), VC++ runtime included, 64-bit Windows 10+.
</package_spec>

<golden_gate>
Question for the user (the orchestrator may ask it before execution and record the answer; Task 1 asks it at its commit step otherwise):

"The FIFO needs one more ring image (ring = quarantine + 4: Windows 7 -> 8, other platforms 5 -> 6). The frozen golden vk.txt lists every image the renderer creates, so its Vulkan scenarios change in the create/destroy lines of that extra image and in the serial numbers after it, and nothing else (checked mechanically by build/rcc/golden_check.py; vk-reasons and vk-ring-fallback stay identical). The four other frozen files stay byte-identical. Approve updating native/tests/golden/vk.txt and recording .planning/phases/14-windows-native-d3d11-backend/evidence/golden-freeze-14-rcc.sha256, which supersedes golden-freeze-14.sha256 for vk.txt? If not, the FIFO cannot ship as decided; the alternatives are to keep HEAD (swap at pickup) or to make the queue a per-platform opt-in so the goldens keep testing depth 1 (not planned)."

Approval is recorded by appending one line to 261029-rcc-CONTEXT.md that starts with `golden_refreeze: approved` (for example `golden_refreeze: approved (user, <date>)`).
</golden_gate>

<!-- planner-discipline-allow: swap_pending_ -->
<!-- planner-discipline-allow: swaps_to_report_ -->
<!-- planner-discipline-allow: kPresentTimeout -->
<!-- planner-discipline-allow: swap_pending_|swaps_to_report_|kPresentTimeout -->
<!-- planner-discipline-allow: Swaps not yet reported -->
<!-- planner-discipline-allow: superseded_test -->

<tasks>

<task type="tracer" tdd="true">
  <name>Task 1: Swap at publish + FIFO ready queue. RED test, baseline A/B, implementation, goldens, GREEN, FIFO A/B, docs, golden gate, one commit</name>
  <files>packages/mpv_kit_video/src/video_renderer.h, packages/mpv_kit_video/src/video_renderer.cc, packages/mpv_kit_video/windows/mpv_kit_video_plugin.cpp, native/tests/video_renderer_swap_test.cc (new), native/tests/video_renderer_superseded_test.cc (deleted), native/tests/meson.build, native/tests/golden/vk.txt (only after approval), native/tests/golden/vk_fallback.txt, native/tests/golden/vk_retire_twice.txt, native/tests/video_renderer_golden_vk_fallback.cc, native/tests/video_renderer_golden_vk_retire_twice.cc, native/tests/video_renderer_golden_sw_retire_twice.cc, native/tests/video_renderer_affinity_test.cc, native/tests/video_renderer_bind_test.cc, docs/ARCHITECTURE.md, .planning/phases/14-windows-native-d3d11-backend/evidence/golden-freeze-14-rcc.sha256 (new), .planning/quick/261029-rcc-fifo-depth-2-frame-queue-with-swap-at-pu/{261029-rcc-PLAN.md, 261029-rcc-CONTEXT.md, 261029-rcc-AB.txt, 261029-rcc-native-tests.log}</files>
  <read_first>
    - packages/mpv_kit_video/src/video_renderer.h and video_renderer.cc (whole files; line map in context)
    - build/nwm/fix-control.patch (whole) and build/nwm/video_renderer_swap_test.cc (whole)
    - native/tests/video_renderer_superseded_test.cc (whole)
    - native/tests/renderer_harness.h lines 95-110, 296-440, 600-660, 770-835, 1036-1100
    - native/tests/meson.build lines 130-200
    - native/tests/golden/vk.txt, vk_fallback.txt, vk_retire_twice.txt (whole)
    - native/tests/video_renderer_golden_vk_fallback.cc lines 40-60 and 190-246
    - packages/mpv_kit_video/windows/mpv_kit_video_plugin.cpp lines 225-240 and 300-345
    - docs/ARCHITECTURE.md lines 80-113, 130-150, 196-246, 368-378
    - build/nwm-tests/build_all.bat, build/nwm-tests/run_all.sh, build/nwm/run_ab.sh, build/nwm/ab_metrics.sh, build/nwm/relbuild.sh
  </read_first>
  <precondition>HEAD is 4be7678 or a descendant and `git status --porcelain -- packages native docs example pubspec.yaml` is empty; `git apply --check build/nwm/fix-control.patch` succeeds; `cd build/phase14/libmpv-rtx && sha256sum -c --quiet MANIFEST.txt` reports no failure; `sha256sum -c --quiet .planning/phases/14-windows-native-d3d11-backend/evidence/golden-freeze-14.sha256` passes; `df -P .` shows at least 1.5 GB available; build/nwm-tests/build_all.bat exists.</precondition>
  <behavior>
    New native test native/tests/video_renderer_swap_test.cc, output `SWAP ok scenarios=10`, exit 0 pass / 1 fail. "fakegpu" = the pipelined FakeGpuBackend behind a GpuInterop(latency, fail_above) whose only candidate is {"fakegpu","gpu-next"}; "sw" = the software backend through FakeInterop(2, false, nullptr). Every scenario: Fake().Reset(), fresh renderer, Start, SetSize(64, 36), WaitFrameReady(1), frame 1 acquired; the test keeps its own expected FrameReady total (publishes + re-notifies) and after every AcquireFront asserts interop.frame_ready() equals it (a re-notify is synchronous inside AcquireFront). fakegpu scenarios 3-6 also keep the last (latency + 1) acquired frames and after every publish and acquire assert that each buffer still holds its frame number (tearing check). Probe counters are read from the single `render waits avg/over 120 frames` line, written in frame 120's render before its publish.
    - 1 swap-at-publish-sw (sw): 20 times AcquireFront, publish one frame, then at once (no barrier) swaps == renders. RED at HEAD.
    - 2 swap-at-publish-gpu (fakegpu, latency 2): the same. RED at HEAD.
    - 3 fifo-jitter (fakegpu, latency 2): cycles of [publish a; acquire] then [publish b; publish c; acquire -> b with one re-notify; acquire -> c], frames 2..119, then publish 120 and stop. Acquired frames are exactly 2..119 once each in order; probe `superseded=0 repeated=0 queued=39`. RED at HEAD (newest wins returns c first).
    - 4 fifo-cap-drop-q2 (fakegpu, latency 2, ring 6): cycles of [publish a, b, c; acquire -> b (re-notify); acquire -> c] for a = 2, 5, ..., 116, then publish 119 and 120 and stop. Acquired frames are b, c of every cycle (a never shown); probe `superseded=39 repeated=0 queued=39`. RED at HEAD.
    - 5 fifo-cap-drop-q4 (fakegpu, latency 4, ring 8): the same pattern and numbers. RED at HEAD.
    - 6 fifo-repeat (fakegpu, latency 2): for f = 2..119: publish f; acquire -> f; acquire -> f again (same index and frame number, no FrameReady); then publish 120. Probe `superseded=0 repeated=118 queued=0`. RED at HEAD (no repeated= key).
    - 7 resize-with-queue (sw): publish 2 and 3 without acquiring; HoldRenders(true); SetSize(32, 18); WaitRenderHeld; AcquireFront returns index -2, 64x36, frame 3 (the newest old frame; 2 is dropped); HoldRenders(false); wait for frame 4's FrameReady; acquire -> frame 4 at 32x18 with index >= 0; three more publish/acquire cycles -> 5, 6, 7 at 32x18; frame 2 is never returned; after a Sync() barrier swaps == renders. May pass at HEAD (regression guard).
    - 8 idle-no-stall (sw): no acquires after frame 1; publish 2..6, after each one at once swaps == renders (no swap waits for a consumer); sleep a named 600 ms (past the 500 ms idle timeout); queue one frame and poke; WaitNoted("event idle") and WaitSkips(1); one more FrameReady from the skip; AcquireFront returns frame 6 (the newest; the older waiting frame 5 is dropped on the return from idle, no re-notify); the redraw then publishes frame 7; WaitNoted("event active"); acquire -> 7; after Sync() swaps == renders; FrameReady total 8. RED at HEAD.
    - 9 failure-keeps-queue (sw): publish 2 (not acquired); SetRenderResults({MPV_ERROR_GENERIC}); queue one frame and poke; WaitNoted("event render_error render: fake error -20"); acquire -> frame 2 (the failed render did not touch the queue, no FrameReady for it); after the 100 ms backoff the automatic retry publishes frame 3; WaitNoted("event recovered"); acquire -> 3; after Sync() swaps == renders. May pass at HEAD.
    - 10 fallback-newest-wins (fakegpu, latency 2, AllocTargets fails for count > 5 by clearing its buffers and returning false): the log has exactly one line `mpv_kit: shared-image allocation failed at ring 6, retried with a ring of 5`; publish 2 and 3 without acquiring; acquire -> 3 and no re-notify (the fallback runs without a waiting frame). RED at HEAD (ring 5 fits, no log line).
  </behavior>
  <action>
    Implements D-01..D-06. Minimal diff; every mpv_render_* call stays on the render thread (RBE-05, D-05).

    1. `source /tmp/gsd-bak/root_pin.sh`. Create build/rcc/ and build/rcc-tests/. Copy build/nwm-tests/build_all.bat and run_all.sh into build/rcc-tests/ and adapt: OUT and D point at build/rcc-tests; the test list replaces superseded_test with swap_test; run_all.sh runs `swap_test` with no arguments and takes an optional env GOLDEN_VK (default native/tests/golden/vk.txt) as golden_vk's golden path. Copy build/nwm/run_ab.sh and ab_metrics.sh into build/rcc/: logs go to build/rcc/<tag>-<cfg>.log; ab_metrics additionally prints repeated= and queued= (sums over probe lines 6..end, `na` when the key is absent) next to the existing keys (reason, probe_lines, stat_lines, drops, superseded, effective, done_med, pickup_med, avsync_max, errors).

    2. RED (tdd). Write native/tests/video_renderer_swap_test.cc from build/nwm/video_renderer_swap_test.cc and native/tests/video_renderer_superseded_test.cc: header block comment in their style (what it proves: swap at publish, FIFO order, cap drop, repeat, re-notify, resize and idle interplay, failure path, allocation fallback; how: the real video_renderer.cc against the fake libmpv, a CPU-backed pipelined backend and the software backend, no GPU; why a separate binary: the golden set and the harness are frozen; output contract `SWAP ok scenarios=<n>`, `SWAP invariant|timeout ...` per problem, exit 0/1). Implement exactly the 10 scenarios of the behavior block with the named constants style of superseded_test (sizes, kProbeFrames = 120, the probe keys, a named idle wait). A scenario returns at its first invariant failure, checks the acquired frame before waiting for any re-notify (so RED fails fast), prints the renderer log on failure, and uses no sleep except the named idle wait and bounded harness waits. It must be clean under MSVC /W4 /WX and gcc/clang -Wall -Wextra -Wpedantic -Werror. Replace the superseded_test block in native/tests/meson.build with the same block for swap_test (`executable('video_renderer_swap_test', 'video_renderer_swap_test.cc', ...)`, same include_directories, cpp_args, link_with, dependencies; `test('video_renderer_swap_test', swap_test, timeout: 120)`) and a comment in that block's style (separate binary because the golden set is frozen; fake backends, so it runs on every platform and under the sanitizers); `git rm native/tests/video_renderer_superseded_test.cc` (its newest-wins expectations no longer hold; its scenarios live on as 3-5 with FIFO semantics). Build with `cmd //c 'build\rcc-tests\build_all.bat'` against the unchanged HEAD renderer and run build/rcc-tests/run_all.sh. Expected: swap_test rc=1 (at least scenarios 1-6, 8 and 10 fail), every other test rc=0. Write the quick-dir file 261029-rcc-native-tests.log: a host and cl version line, `--- RED (swap_test against HEAD 4be7678) ---`, the per-test lines, and `red swap_test rc=1 failing=<comma-separated scenario names>`. If another test fails here, STOP and report.

    3. Baseline A/B (HEAD code, no source edit yet): `bash build/nwm/relbuild.sh build/rcc/base-build.log` (exit 0, porcelain line empty), then `bash build/rcc/run_ab.sh base auto` and `bash build/rcc/run_ab.sh base d3d11` (150 s each, 4K60 lavfi with sine, ao=null, default window untouched).

    4. Swap at publish: `git apply build/nwm/fix-control.patch`. Keep its comments, which already describe the behaviour.

    5. FIFO ready queue (D-02, D-03, D-04, D-06) in video_renderer.{h,cc}:
       - Header ring state: a private `static constexpr int kReadyDepth = 2` (finished frames that may wait for the compositor), `int ready_depth_ = kReadyDepth` (1 after the allocation fallback), `int queued_ = -1` (the older waiting frame, published before front_ and not yet taken; -1 if none), all guarded by mutex_. Rewrite the ring comment to "Ring = front + one waiting frame + in use + quarantine + one free image", the front_acquired_ comment to "the compositor took front_ (it is in_use_)", and the default `ring_size_` to 6. Probe members: `int probe_repeated_ = 0` (acquisitions that found nothing new) and `int probe_queued_ = 0` (acquisitions that took the older of two waiting frames); rewrite the probe_superseded_ comment (frames rendered and dropped before the compositor took them: from a full queue, the older waiting frame at a resize or a return from idle, or a replaced frame on the fallback ring). All three are written under mutex_ and read and reset under it by the render thread.
       - Interop::FrameReady doc: called from the render thread, and from AcquireFront's caller without the renderer lock when a further finished frame still waits; implementations only mark the texture and must accept either thread. AcquireFront doc: returns the oldest finished frame the compositor has not taken yet (at most two wait), or the frame it took last when nothing new was published; the index stays valid until the next call; makes no libmpv call, and may call Interop::FrameReady once, after releasing its lock, so that the compositor takes the next waiting frame at its next frame.
       - Start: `ring_size_ = quarantine_count_ + 2 + kReadyDepth` and `ready_depth_ = kReadyDepth`, with a one-line comment naming the five parts.
       - Publish block (RenderOnce, under the lock, before `front_ = back`): if front_ >= 0 and the compositor has not taken it: with ready_depth_ > 1 the old front becomes queued_, and a queued_ that was already set is dropped first (probe_superseded_++); with ready_depth_ == 1 the old front is replaced (probe_superseded_++). Then front_ = back and front_acquired_ = false; the retired-countdown start stays. After the lock ReportSwaps(1) then interop_->FrameReady(), as the patch has it.
       - AcquireFront, under the lock, after last_acquire_ and the resumed check: if resumed and queued_ >= 0, drop queued_ (probe_superseded_++), because the newest picture is shown first after skipped frames. Then choose the next frame: queued_ >= 0 -> take it, clear queued_, probe_queued_++, and remember to re-notify (front_ still waits); else front_ >= 0 and not taken -> take front_ and set front_acquired_; else front_ >= 0 -> keep in_use_ and probe_repeated_++. The quarantine shift and the retired countdown use "the next frame differs from in_use_" instead of "front_ differs from in_use_"; in_use_ becomes the next frame; f.index is the next frame, and the retired-front branch applies when there is no next frame (front_ < 0). After unlocking: interop_->FrameReady() when a re-notify is due (outside the lock, as the platforms mark their texture), and cv_.notify_one() when resumed. Comment the re-notify with the reason: Flutter calls the texture callback only after a mark, so without it the newer waiting frame would sit until the next publish.
       - PickBackBuffer: the busy set also contains queued_; comment "never the frame being displayed, a frame waiting to be taken, the one the compositor holds, or one it may still be sampling"; on the unreachable path add `assert(false)` with a short message before `return 0`.
       - Resize block (RenderOnce, top, under the lock): when the ring is reallocated, a queued_ frame is dropped (probe_superseded_++) and queued_ = -1 next to the existing `front_ = in_use_ = -1`; the newest old frame (front_) stays the retired front as before.
       - Allocation fallback: keep fallback_quarantine 2 and fallback_ring 5 (2 + 3); the retry condition `ring_size_ > fallback_ring` now also covers latency 2 (ring 6); on success also set ready_depth_ = 1. Update the comment: the retry keeps the footprint the ring had before the waiting frame existed, so on this path a newer frame replaces an untaken one.
       - Probe block: take a snapshot of the three counters under mutex_ and reset them there, then log outside the lock, appending ` repeated=<n> queued=<n>` after ` superseded=<n>`.
       - Windows plugin (mpv_kit_video_plugin.cpp): RecordPickup takes the stamp as a parameter (`RecordPickup(Instance* inst, int64_t ready)`), Describe loads `frame_ready_ns` before AcquireFront and passes it; one comment line saying why (AcquireFront may mark the texture again for a waiting frame). Nothing else changes in that file.

    6. Goldens and stale test comments. Rebuild (build_all.bat) and run run_all.sh. golden_vk, golden_vk_fallback and golden_vk_retire_twice are expected to mismatch; every other test must pass except swap_test, which must now pass. Then:
       - Apply the non-frozen test edits listed in context (kFullRing = kWindowsLatency + 4; ring and present-timeout comments; affinity and bind comments). Comment-only changes otherwise.
       - Write build/rcc/golden_check.py (run with `python -I`). For each pair (old = `git show 4be7678:<path>`, new = candidate) it parses `[scenario]` sections (blank and `#` lines ignored), requires the same scenario names in order, splits each body into allocation runs (maximal runs of consecutive `create serial=` / `create failed` lines), requires the runs to correspond in order with identical `create failed` positions and the new run to have either the same number of created images or exactly one more (the last one), maps the k-th new serial of a run to the k-th old serial and the extra one to EXTRA, translates every `serial=<n>` of the new body through that map, drops every line that names an EXTRA serial, and requires the result to equal the old body line by line. A line starting `log mpv_kit: shared-image allocation failed at ring ` may differ only in the number after `at ring `, which must be the old number + 1. Comment lines, compared with every number that follows `ring `, `ring of ` or `-> ring ` replaced by a placeholder, must be identical. It prints one `scenario=<name> runs=<r> extra=<e>` line per scenario and `golden_check <file>=PASS|FAIL`.
       - Build the candidates from the stderr `actual trace of [<name>]` blocks: for vk_fallback.txt and vk_retire_twice.txt edit the tree files directly (bodies replaced, ring numbers in their comments updated); for vk.txt write build/rcc/golden/vk.txt (the tree file stays untouched). Run golden_check on the three; all must PASS, and vk.txt must show extra=0 for vk-reasons and vk-ring-fallback. A FAIL means the change altered a trace beyond the extra image: STOP and report with the diff. Append `--- GOLDEN ---`, the check output and the single line `golden_check vk.txt=PASS vk_fallback.txt=PASS vk_retire_twice.txt=PASS` to the native-tests log.
       - GREEN: rebuild and run `GOLDEN_VK=build/rcc/golden/vk.txt bash build/rcc-tests/run_all.sh` three times; each must end `ALL rc=0`; append `--- GREEN run <k> ---` blocks. Run `sha256sum -c .planning/phases/14-windows-native-d3d11-backend/evidence/golden-freeze-14.sha256` (must still pass: vk.txt is untouched) and append the result.

    7. FIFO A/B: `bash build/nwm/relbuild.sh build/rcc/fifo-build.log`, then `bash build/rcc/run_ab.sh fifo auto` and `bash build/rcc/run_ab.sh fifo d3d11`. Write the quick-dir file 261029-rcc-AB.txt: host line (GPU, refresh rate via Win32_VideoController.CurrentRefreshRate, power online); source, ao, window, run_seconds=150 and the measurement windows; builds line (base = HEAD 4be7678, swap at pickup; fifo = HEAD + fix-control.patch + FIFO, uncommitted tree); one `ab run=<base|fifo>-<auto|d3d11> ...` line per run from ab_metrics; the rule line: not_worse = effective_fifo <= effective_base + 2 per config; avsync_max_fifo <= 10 * max(avsync_max_base, 0.001); pickup_med_fifo <= pickup_med_base + 20; errors_fifo <= errors_base; probe_lines >= 65 in every run (otherwise repeat that run once); an `eval ...` line; a note on how to read repeated= and queued= (context); and `ab_gate=PASS` or `ab_gate=FAIL`. On FAIL: `git diff > build/rcc/fifo.patch`, copy the new test and the candidate goldens to build/rcc/, leave the tree as it is, and STOP with a checkpoint carrying the table (no commit, no Task 2).

    8. Integration and analysis (debug plugin, asserts on), from example/ with the bundle user_define and env from context: `/d/flutter/bin/flutter test integration_test/real_plugin_test.dart -d windows`, then with `MPV_KIT_VIDEO_API=d3d11` `/d/flutter/bin/flutter test integration_test/d3d11_backend_test.dart -d windows`; revert pubspec.yaml and check porcelain. Then `/d/flutter/bin/flutter analyze --fatal-infos` in packages/mpv_kit_video and in example, and `/d/flutter/bin/flutter test` in packages/mpv_kit_video. Append `integration real_plugin_test=<pass|fail> d3d11_backend_test=<pass|fail>` and `flutter analyze=<pass|fail> flutter_test=<pass|fail>` to 261029-rcc-AB.txt. A failure blocks the commit (diagnose; a real regression is treated as ab_gate FAIL).

    9. docs/ARCHITECTURE.md (comment-free prose, matching the file):
       - Rewrite the "Swap reporting" bullet (87-98) as the new contract, with the exact phrase "reported when it is published": the render thread reports each frame's swap right after the publish, before FrameReady; skipped, failed and timed-out frames on the same thread, so every render call is answered by exactly one swap; why (flip_page waits for it before the core queues the next frame; the render API gives mpv no presentation feedback; reporting at pickup added the pickup latency to every frame: quick 261029-nwm, GTX 960M laptop drops); AcquireFront makes no libmpv call. Keep the display-fps-override sentence.
       - Replace the "Superseded frames" bullet with a "**Frame queue.**" bullet: FIFO of at most two finished frames; AcquireFront takes the oldest, else repeats (repeated=); a full queue drops its oldest (superseded=), as do a resize (older waiting frame) and a return from idle; the re-notify with its reason (Flutter's embedder resolves an external texture only after MarkNewFrameAvailable, so a second waiting frame needs another mark; AcquireFront does it outside the renderer lock because the render thread is blocked in mpv's render call until the next target time) and its count (queued=); effect (jitter up to about one frame period costs no frame, a longer compositor stall drops the oldest) and the reading of repeated= on mark-driven Flutter. Effective drops are still mpv's frame-drop-count plus superseded=.
       - "Render context release" (107-112): delete the sentence about unreported swaps.
       - Line 135-136 ring bookkeeping list: add the waiting frame. Frame ring section (198-224): ring size = front + one waiting frame + in use + quarantine + one free image; "Windows uses 4 (ring of 8)"; "Other platforms use 2 (ring of 6)"; one sentence on the allocation fallback (one retry with quarantine 2 and a ring of 5, without a waiting frame). Line 374 (Linux GL): "The ring (6) and the quarantine (2)".
       - Do not edit historical perf documents.

    10. Final local run: rebuild, run `GOLDEN_VK=build/rcc/golden/vk.txt bash build/rcc-tests/run_all.sh` once more and append it as `--- FINAL (candidate vk.txt) ---`.

    11. Golden gate. Re-read 261029-rcc-CONTEXT.md. If no line starts with `golden_refreeze: approved`: save `git diff > build/rcc/fifo.patch` and copy the untracked new files to build/rcc/, leave the tree uncommitted, and STOP with a `checkpoint:decision` carrying the <golden_gate> question, `git diff --no-index native/tests/golden/vk.txt build/rcc/golden/vk.txt`, the golden_check output and the A/B table. The continuation, once the line exists, resumes here. With approval: copy build/rcc/golden/vk.txt over native/tests/golden/vk.txt; write .planning/phases/14-windows-native-d3d11-backend/evidence/golden-freeze-14-rcc.sha256 (LF) with two `#` header lines (quick 261029-rcc re-freeze, approval as recorded in 261029-rcc-CONTEXT.md, supersedes golden-freeze-14.sha256; only vk.txt changed, by the ring's extra image, checked by build/rcc/golden_check.py), the four unchanged lines copied verbatim from golden-freeze-14.sha256, and `sha256sum -b native/tests/golden/vk.txt` in the same `<hash> *<path>` form; `sha256sum -c` it. Run `bash build/rcc-tests/run_all.sh` (tree vk.txt, no override) and append it as `--- FINAL ---`; the log's last line must be `ALL rc=0`.

    12. `source /tmp/gsd-bak/root_pin.sh`; stage exactly the paths in <files> (git rm already staged the deletion); commit once, for example `feat(video): FIFO ready queue of two frames, mpv swap reported at publish`, with a body covering: why (package3 and package3-control laptop numbers), the re-notify and why it lives in AcquireFront, ring = quarantine + 4 and the unchanged fallback footprint, the counters, the A/B effective drops per config, RBE-05 unchanged, the golden re-freeze with its approval, and quick 261029-rcc; end with the Co-Authored-By line. Do not push.
  </action>
  <verify>
    <automated>S=packages/mpv_kit_video/src && Q=.planning/quick/261029-rcc-fifo-depth-2-frame-queue-with-swap-at-pu && F=.planning/phases/14-windows-native-d3d11-backend/evidence && T=native/tests && ! grep -qE 'swap_pending_|swaps_to_report_|kPresentTimeout' $S/video_renderer.h $S/video_renderer.cc && for k in queued_ ready_depth_ kReadyDepth probe_repeated_ probe_queued_; do grep -q "$k" $S/video_renderer.h || exit 1; done && grep -q ' repeated=' $S/video_renderer.cc && grep -q ' queued=' $S/video_renderer.cc && sed -n '/^int VideoRenderer::PickBackBuffer/,/^}/p' $S/video_renderer.cc | grep -q 'queued_' && sed -n '/^Frame VideoRenderer::AcquireFront/,/^}/p' $S/video_renderer.cc | grep -q 'FrameReady()' && ! sed -n '/^Frame VideoRenderer::AcquireFront/,/^}/p' $S/video_renderer.cc | grep -q 'api_\.' && grep -q 'RecordPickup(inst, ' packages/mpv_kit_video/windows/mpv_kit_video_plugin.cpp && grep -q 'SWAP ok scenarios=' $T/video_renderer_swap_test.cc && test ! -e $T/video_renderer_superseded_test.cc && grep -q "'video_renderer_swap_test.cc'" $T/meson.build && ! grep -q 'superseded_test' $T/meson.build && ! grep -q 'kPresentTimeout' $T/video_renderer_affinity_test.cc $T/video_renderer_bind_test.cc $T/video_renderer_golden_vk_fallback.cc $T/video_renderer_golden_vk_retire_twice.cc $T/video_renderer_golden_sw_retire_twice.cc && grep -qx 'log mpv_kit: shared-image allocation failed at ring 8, retried with a ring of 5' $T/golden/vk_fallback.txt && for p in 'reported when it is published' 'Frame queue' 'repeated=' 'queued=' 'ring of 8' 'ring of 6' 'MarkNewFrameAvailable'; do grep -q "$p" docs/ARCHITECTURE.md || exit 1; done && ! grep -q 'swaps_to_report_' docs/ARCHITECTURE.md && ! grep -q 'Swaps not yet reported' docs/ARCHITECTURE.md && grep -q '^golden_refreeze: approved' $Q/261029-rcc-CONTEXT.md && sha256sum -c --quiet $F/golden-freeze-14-rcc.sha256 && test "$(grep -v '^#' $F/golden-freeze-14.sha256 | grep -v 'golden/vk.txt$')" = "$(grep -v '^#' $F/golden-freeze-14-rcc.sha256 | grep -v 'golden/vk.txt$')" && test -z "$(git diff --name-only 4be7678 HEAD -- $T/renderer_harness.h $T/video_renderer_golden_sw.cc $T/video_renderer_golden_vk.cc $T/golden/sw.txt)" && grep -qx 'golden_check vk.txt=PASS vk_fallback.txt=PASS vk_retire_twice.txt=PASS' $Q/261029-rcc-native-tests.log && grep -q '^red swap_test rc=1' $Q/261029-rcc-native-tests.log && test "$(tail -n 1 $Q/261029-rcc-native-tests.log | tr -d '\r')" = 'ALL rc=0' && test "$(bash build/rcc-tests/run_all.sh | tail -n 1 | tr -d '\r')" = 'ALL rc=0' && grep -qx 'ab_gate=PASS' $Q/261029-rcc-AB.txt && grep -q '^integration real_plugin_test=pass d3d11_backend_test=pass' $Q/261029-rcc-AB.txt && grep -q '^flutter analyze=pass flutter_test=pass' $Q/261029-rcc-AB.txt && test "$(grep -a -c ' queued=' example/build/windows/x64/runner/Release/mpv_kit_video_plugin.dll)" -ge 1 && E=$(printf '%s\n' $F/golden-freeze-14-rcc.sha256 $Q/261029-rcc-AB.txt $Q/261029-rcc-CONTEXT.md $Q/261029-rcc-PLAN.md $Q/261029-rcc-native-tests.log docs/ARCHITECTURE.md $T/golden/vk.txt $T/golden/vk_fallback.txt $T/golden/vk_retire_twice.txt $T/meson.build $T/video_renderer_affinity_test.cc $T/video_renderer_bind_test.cc $T/video_renderer_golden_sw_retire_twice.cc $T/video_renderer_golden_vk_fallback.cc $T/video_renderer_golden_vk_retire_twice.cc $T/video_renderer_superseded_test.cc $T/video_renderer_swap_test.cc $S/video_renderer.cc $S/video_renderer.h packages/mpv_kit_video/windows/mpv_kit_video_plugin.cpp | LC_ALL=C sort) && H1=$(git show --name-only --format= HEAD) && C=$(printf '%s\n' "$H1" | LC_ALL=C sort) && test "$C" = "$E" && E2=$(printf '%s\n' "$E" | grep -v 'superseded_test') && EOL=$(git ls-files --eol -- $E2) && ! printf '%s\n' "$EOL" | grep -qv 'i/lf *w/lf' && test -z "$(git status --porcelain pubspec.yaml)" && test -z "$(git diff --name-only 4be7678 HEAD -- '*.dart')"</automated>
    <baseline>Measured at HEAD 4be7678 during planning: swap members/timeout h=4 cc=12 (negative gate fails); queued_, ready_depth_, kReadyDepth, probe_repeated_, probe_queued_ 0; ` repeated=` and ` queued=` in the .cc 0; queued_ in PickBackBuffer 0; FrameReady in AcquireFront 0; `api_.` in AcquireFront 0 (prohibition guard, passes at HEAD by design); `RecordPickup(inst, ` 0; swap_test absent, superseded_test present, meson swap_test 0 / superseded_test 3; kPresentTimeout 1 in each of the five non-frozen tests; vk_fallback.txt has the `ring 7` line, `ring 8` 0; ARCHITECTURE.md: "reported when it is published" 0, "Frame queue" 0, repeated= 0, queued= 0, "ring of 8" 0, "ring of 6" 0, MarkNewFrameAvailable 0, swaps_to_report_ 1, "Swaps not yet reported" 1; approval line absent; golden-freeze-14-rcc.sha256, native-tests log and AB file absent; Release plugin DLL ` queued=` 0 (superseded= 1); golden-freeze-14 OK. Every positive gate fails at HEAD.</baseline>
    <fails_when>a removed swap member or the timeout survives; the queue members, the counters, the PickBackBuffer exclusion, the re-notify in AcquireFront or the pickup-stamp change are missing; AcquireFront calls libmpv; swap_test is missing or superseded_test survives; a non-frozen test still names the removed timeout; the fallback log line is not ring 8; ARCHITECTURE.md misses a required phrase or keeps the old swap text; vk.txt changed without the approval line or without a matching freeze record; another frozen file changed; golden_check, the RED line or a final run is missing or failing; ab_gate is not PASS; an integration test, analyze or flutter test failed; the Release DLL lacks the new counters; the commit holds anything other than the 20 paths; a file became CRLF; pubspec.yaml is modified; a Dart file changed</fails_when>
  </verify>
  <acceptance_criteria>
    - Swaps are reported at publish on the render thread before FrameReady; AcquireFront makes no libmpv call; affinity and bind tests stay green (RBE-05, D-05).
    - FIFO of two with cap drop, repeat and re-notify, counters superseded=/repeated=/queued= on the probe line (D-01, D-02, D-03, D-06); ring = quarantine + 4 with the fallback at ring 5 and depth 1 (D-04); PickBackBuffer excludes the waiting frame.
    - swap_test RED at HEAD and GREEN after; all local renderer tests ALL rc=0 3x plus final; golden_check PASS for the three Vulkan goldens; the four other frozen files byte-identical; vk.txt and golden-freeze-14-rcc.sha256 only with the recorded approval.
    - ab_gate=PASS on the RTX 4060; real_plugin_test and d3d11_backend_test pass; analyze and flutter test green.
    - One local commit with exactly the 20 paths; nothing pushed.
  </acceptance_criteria>
  <done>Swap at publish plus a depth-2 FIFO with re-notify is in the renderer, proven by a RED-then-GREEN native test, mechanically checked golden updates with a recorded re-freeze, local integration tests and a passing A/B gate, and committed with its docs and evidence.</done>
</task>

<task type="auto">
  <name>Task 2: Build, verify and ship package4 (FIFO) for the laptop; record and commit ## package4</name>
  <files>.planning/phases/14-windows-native-d3d11-backend/evidence/laptop-package.txt</files>
  <read_first>
    - .planning/phases/14-windows-native-d3d11-backend/evidence/laptop-package.txt from `## package3` (line 276) to the end (key names and formats of package3 and package3-control)
    - build/nwm/make_pkg.sh, build/nwm/fin_pkg.sh, build/nwm/check_bats.sh, build/nwm/smoke.sh, build/nwm/power.ps1
    - build/nwm/pkg3c-src/ (run-auto-log.bat, run-d3d11.bat, 使用说明.txt) and build/nwm/pkg3-src/run-probe.bat
    - this plan's package_spec
  </read_first>
  <precondition>Task 1's commit is HEAD, 261029-rcc-AB.txt says `ab_gate=PASS`, and the CONTEXT has the `golden_refreeze: approved` line; `git status --porcelain -- packages example native docs tools pubspec.yaml` is empty; the libmpv-rtx MANIFEST check has no failure; `df -P .` shows at least 1 GB available.</precondition>
  <action>
    1. `source /tmp/gsd-bak/root_pin.sh`. Desktop space: `C_FREE_MB=$(df -P "$HOME/Desktop" | awk 'NR==2{print int($4/1024)}')`. If it is below 400, STOP with a checkpoint that lists the existing `$HOME/Desktop/mpv_kit_d3d11_demo_*` folders and asks whether to remove any (never remove one without that answer). Otherwise leave every existing package folder alone.

    2. `FEAT=$(git rev-parse HEAD)`, `SHORT=$(git rev-parse --short=7 HEAD)`, `FIFO=$(git log -1 --format=%H -- packages/mpv_kit_video/src/video_renderer.cc)` (equal to FEAT). Rebuild Release from the commit: `bash build/nwm/relbuild.sh build/rcc/pkg4-build.log`.

    3. Smoke: copy build/nwm/smoke.sh to build/rcc/smoke.sh with logs and screenshots under build/rcc/; run `bash build/rcc/smoke.sh pkg4 auto` and `bash build/rcc/smoke.sh pkg4 d3d11`; look at both screenshots (picture and HUD visible). Each log must have exactly one `mpv_kit_example: GPU preference ` line matching the host power state (build/nwm/power.ps1), one `mpv_kit: compositor adapter "NVIDIA GeForce RTX 4060` line, no hybrid hint line, probe lines carrying ` superseded=`, ` repeated=` and ` queued=`, and the reasons `vulkan (gpu-next) on NVIDIA GeForce RTX 4060 Laptop GPU` and `d3d11 (gpu-next) on NVIDIA GeForce RTX 4060 Laptop GPU; vulkan/gpu-next unavailable: excluded by MPV_KIT_VIDEO_API=d3d11`. A failed check is a defect of Task 1: STOP and report.

    4. Launcher sources: write build/rcc/pkg4-src/run-auto-log.bat, run-d3d11.bat and 使用说明.txt with the Write tool per package_spec; copy build/nwm/pkg3-src/run-probe.bat unchanged.

    5. build/rcc/make_pkg.sh, adapted from build/nwm/make_pkg.sh with a single fifo mode: SRC=build/rcc/pkg4-src (run-probe.bat from build/nwm/pkg3-src), desktop dir `$HOME/Desktop/mpv_kit_d3d11_demo_${SHORT}_fifo`, section file build/rcc/package4.txt, smoke logs build/rcc/pkg4-smoke-*.log. It writes, in this order and with the package3 formats: `## package4`; a `#` line (quick 261029-rcc: FIFO ready queue of two frames with mpv swap reported at publish, probe counters superseded= repeated= queued=, ring = quarantine + 4; laptop demo package4 for the 14-10 GTX 960M + HD 530 comparison with ## package3 and ## package3-control); feat_sha, `fifo_sha=$FIFO`, `golden_refreeze=approved` and a golden_refreeze_note naming golden-freeze-14-rcc.sha256; feat_branch; date_utc; release_run=40812562348 and release_run_note; bundle_dir; build; release_dir; flutter; the 24 dll lines, bundle_dll_count, bundle_match; the 25 angle lines, angle_audit_files, angle_audit; release_plugin, debug_build_plugin, debug_build_has_switches, debug_switches_absent; adapter_log_string_in_dll, hint_string_in_dll, superseded_string_in_dll, `fifo_string_in_dll` (yes only when both ` repeated=` and ` queued=` are found with grep -a -c in the plugin DLL), power_string_in_exe; probe_host lines; power_host; local_smoke and local_smoke_note; power_log and power_log_matches_host; hint_log; superseded_in_log; `fifo_in_log` (yes when the auto smoke log's probe lines carry both new keys); adapter_log, adapter_log_runs, adapter_luid_matches_probe; `c_free_mb_before=$C_FREE_MB`.

    6. build/rcc/check_bats.sh, adapted from build/nwm/check_bats.sh: prefix mpv_kit_fifo; run-auto-log.bat twice and run-d3d11.bat once from the desktop copy through cmd with stdin from NUL and the package's demo/data/flutter_assets/integration_test/route_samples/h264-8bit.mp4 as argument, about 15 s each; each of the three new logs must contain the GPU preference, compositor adapter and `mpv_kit_video:` lines (the d3d11 one with a `d3d11 (` reason) and its first line must contain `FIFO BUILD`; delete only the logs this check created. Append `bat_log_check auto=<yes|no> d3d11=<yes|no> numbering=<yes|no> first_line=<yes|no>` and a bat_log_check_note. If cmd mishandles the numbering, fix only the bat files, re-test and record the deviation.

    7. build/rcc/fin_pkg.sh, adapted from build/nwm/fin_pkg.sh: desktop_path, desktop_layout (run-probe.bat and d3d11_caps_probe.exe carried over byte-identical from package3, with their sha256), desktop_check, desktop_size, one `sha256 <hash> ./<path>` line per file (sorted); no removal of any folder; `existing_packages_left=<space-separated names of the other mpv_kit_d3d11_demo_* folders on the desktop, or none>`. Check the encodings with `file` (bats CRLF; 使用说明 UTF-8 with BOM, CRLF).

    8. Append build/rcc/package4.txt to laptop-package.txt (one blank line first, LF; earlier sections untouched). `source /tmp/gsd-bak/root_pin.sh`; `git add` only that file; commit, for example `docs(14-10): package4 provenance (FIFO ready queue, swap at publish)`, ending with the Co-Authored-By line. Do not push.
  </action>
  <verify>
    <automated>L=.planning/phases/14-windows-native-d3d11-backend/evidence/laptop-package.txt && test "$(git show --name-only --format= HEAD)" = "$L" && S="$(sed -n '/^## package4$/,$p' "$L")" && test -n "$S" && F=$(printf '%s\n' "$S" | sed -n 's/^feat_sha=//p') && test "$F" = "$(git rev-parse HEAD~1)" && printf '%s\n' "$S" | grep -qx "fifo_sha=$(git log -1 --format=%H -- packages/mpv_kit_video/src/video_renderer.cc)" && for k in golden_refreeze=approved bundle_match=yes angle_audit=ok debug_switches_absent=yes adapter_log_string_in_dll=yes hint_string_in_dll=yes superseded_string_in_dll=yes fifo_string_in_dll=yes power_string_in_exe=yes power_log_matches_host=yes superseded_in_log=yes fifo_in_log=yes adapter_luid_matches_probe=yes; do printf '%s\n' "$S" | grep -qx "$k" || exit 1; done && printf '%s\n' "$S" | grep -Eq '^local_smoke auto=.* d3d11=d3d11 \(gpu-next\) on NVIDIA GeForce RTX 4060' && printf '%s\n' "$S" | grep -Eq '^adapter_log=mpv_kit: compositor adapter "NVIDIA GeForce RTX 4060[^"]*" luid=[0-9A-F]{8}:[0-9A-F]{8}$' && printf '%s\n' "$S" | grep -Eq '^bat_log_check auto=yes d3d11=yes numbering=yes first_line=yes' && printf '%s\n' "$S" | grep -q '^existing_packages_left=' && CF=$(printf '%s\n' "$S" | sed -n 's/^c_free_mb_before=//p') && test "$CF" -ge 400 && D=$(printf '%s\n' "$S" | sed -n 's/^desktop_path=//p') && test "$D" = "$HOME/Desktop/mpv_kit_d3d11_demo_$(git rev-parse --short=7 "$F")_fifo" && test -f "$D/demo/mpv_kit_example.exe" && test -f "$D/d3d11_caps_probe.exe" && for b in run-probe.bat run-auto-log.bat run-d3d11.bat; do file "$D/$b" | grep -q CRLF || exit 1; done && grep -q 'mpv_kit_fifo_auto_log_%N%' "$D/run-auto-log.bat" && grep -q 'mpv_kit_fifo_d3d11_log_%N%' "$D/run-d3d11.bat" && grep -q 'FIFO BUILD' "$D/run-auto-log.bat" && grep -q 'FIFO BUILD' "$D/run-d3d11.bat" && grep -q 'MPV_KIT_VIDEO_API=d3d11' "$D/run-d3d11.bat" && file "$D/使用说明.txt" | grep -q 'with BOM' && file "$D/使用说明.txt" | grep -q CRLF && test "$(grep -a -c ' queued=' "$D/demo/mpv_kit_video_plugin.dll")" -ge 1 && test "$(grep -a -c ' repeated=' "$D/demo/mpv_kit_video_plugin.dll")" -ge 1 && EOL=$(git ls-files --eol "$L") && ! printf '%s\n' "$EOL" | grep -qv 'i/lf *w/lf' && test -z "$(git status --porcelain pubspec.yaml)" && test -z "$(git diff --name-only 4be7678 HEAD -- '*.dart')" && ST=$(git status --porcelain) && test -z "$(printf '%s\n' "$ST" | grep -vE '^( M \.planning/config\.json| M \.planning/state\.json|\?\? \.planning/(debug|tmp|ui-reviews)/|\?\? engine_repo_embedder\.cc|\?\? \.planning/quick/261029-rcc-fifo-depth-2-frame-queue-with-swap-at-pu/.*)$' | grep -v '^$')"</automated>
    <baseline>At HEAD 4be7678 (and right after Task 1): laptop-package.txt has no `## package4` (S is empty, the gate fails); no `mpv_kit_d3d11_demo_*_fifo` folder exists on the desktop (no package folder at all was there during planning); C: had about 2472 MB free.</baseline>
    <fails_when>the HEAD commit holds anything but laptop-package.txt; a package4 key is missing or not yes; feat_sha or fifo_sha does not name the Task 1 commit; the smoke reasons or the adapter line do not name the RTX 4060; the launchers lack the fifo log names, the FIFO BUILD first line or CRLF; 使用说明 lacks BOM or CRLF; the package DLL lacks the counters; C: free space was below 400 MB without an answer; an existing package folder was removed; the file became CRLF; pubspec.yaml is modified; a Dart file changed; the tree has an unexpected change</fails_when>
  </verify>
  <acceptance_criteria>
    - package4 is built from the Task 1 commit, verified on this host with the package3 checks plus the FIFO counters in the DLL and the smoke log, and placed at `~/Desktop/mpv_kit_d3d11_demo_<sha>_fifo/`.
    - The launchers write numbered `mpv_kit_fifo_{auto,d3d11}_log_<N>.txt` whose first line names the FIFO build; 使用说明 asks for AC runs of at least 2 minutes per mode with no seeking and the durations noted.
    - Existing package folders are untouched (C: had at least 400 MB free); `## package4` is committed alone; nothing pushed.
  </acceptance_criteria>
  <done>A verified, self-contained package4 is on the desktop and its provenance is committed.</done>
</task>

<task type="checkpoint:human-verify" gate="blocking-human">
  <name>Task 3: User runs package4 on the GTX 960M + HD 530 laptop (AC, auto and d3d11) and replies</name>
  <files>none (the orchestrator records the reply later)</files>
  <read_first>
    - .planning/phases/14-windows-native-d3d11-backend/evidence/laptop-package.txt `## package4` (desktop_path, feat_sha)
  </read_first>
  <action>Present the checkpoint below with the desktop path filled in, then stop and wait. Edit no file. The run needs the user's other machine, so this checkpoint is blocking even though workflow.human_verify_mode is end-of-phase.</action>
  <what-built>Desktop folder `mpv_kit_d3d11_demo_<短 SHA>_fifo` (package4): the example Release build with mpv's swap reported at publish and up to two finished frames shown in order (FIFO), A/B-checked on the RTX 4060; the 120-frame probe lines carry superseded=, repeated= and queued=. run-auto-log.bat and run-d3d11.bat write a new numbered desktop log per run whose first line reads FIFO BUILD; run-probe.bat writes mpv_kit_d3d11_probe.txt; 使用说明.txt has the steps.</what-built>
  <how-to-verify>
    1. Keep the Windows Graphics and NVIDIA program settings for mpv_kit_example.exe at their defaults; copy the folder to the laptop; run run-probe.bat only if it has not been run in this boot session.
    2. On AC power with battery saver off: run-auto-log.bat, then run-d3d11.bat. Play the 3840x2160 59.94 fps H.264 file for at least 2 minutes each, window visible and untouched, no seeking; note the actual duration and the HUD values (backend, reason, dropped, dec-drop, avsync, hwdec, fps).
    3. In each log find the `mpv_kit_example: GPU preference`, `mpv_kit: compositor adapter` and (if present) `mpv_kit: hybrid GPU hint:` lines.
  </how-to-verify>
  <resume-signal>Reply with, for both runs (auto, d3d11): duration, reason (full), dropped, dec-drop, avsync, hwdec, fps and the three log lines (or "none"); attach every mpv_kit_fifo_auto_log_*.txt and mpv_kit_fifo_d3d11_log_*.txt (and mpv_kit_d3d11_probe.txt if it was run).</resume-signal>
  <verify><automated>echo "blocking-human: no automated check; the user's reply is the result (recorded later by the orchestrator)"</automated></verify>
  <acceptance_criteria>
    - The reply covers both runs with durations, HUD values and the three lines, and the logs are attached.
  </acceptance_criteria>
  <done>The user's package4 laptop result (AC, auto and d3d11) is in hand for the orchestrator to compare with package3 and package3-control.</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| render thread <-> libmpv VO thread | swap timing decides when flip_page returns and when mpv drops |
| compositor (raster) thread -> renderer state | AcquireFront pops the queue, quarantines, and now marks the texture again |
| renderer -> platform texture registrar | FrameReady from two threads (render, compositor) |
| frozen golden record -> regression safety | vk.txt edit and the superseding freeze record |
| dev machine build -> user's laptop | unsigned Release package run on another machine |
| user report / log files -> evidence | human-read values and log text become verification input |
| workspace root pubspec.yaml | temporary local bundle user_define during builds |

## STRIDE Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation Plan |
|-----------|----------|-----------|----------|-------------|-----------------|
| T-261029rcc-01 | Tampering | ring slots (tearing: rendering into a waiting, held or quarantined image) | high | mitigate | PickBackBuffer busy set includes queued_; ring = quarantine + 4; assert on the unreachable path; swap_test tearing check over the last latency + 1 acquired frames and FIFO identity checks at q2 and q4; vk goldens and real_plugin_test resizes |
| T-261029rcc-02 | Denial of Service | mpv VO stall or frame loss from changed swap timing | high | mitigate | one swap per render call (CheckSwapInvariant in every quiesce, swap-at-publish and idle-no-stall scenarios); A/B gate on effective drops, avsync, errors |
| T-261029rcc-03 | Denial of Service | re-notify loop or missing mark (queue never drains) | medium | mitigate | re-notify only when AcquireFront took the older of two waiting frames; swap_test asserts the exact FrameReady total after every AcquireFront; queued= in the probe line |
| T-261029rcc-04 | Denial of Service | deadlock from FrameReady on the compositor thread | medium | mitigate | called after mutex_ is released; all three platform lambdas are lock-free and only post marks (verified in context); Windows integration tests locally; Linux/macOS plugin legs listed as CI-only |
| T-261029rcc-05 | Tampering | data races on queued_, ready_depth_ and probe counters | medium | mitigate | all under mutex_, probe snapshot under mutex_; sanitizer CI job runs swap_test |
| T-261029rcc-06 | Denial of Service | GPU memory growth from the extra image (4K +33 MB, 8K +127 MiB) | low | mitigate | allocation fallback keeps ring 5 / quarantine 2 and depth 1 (footprint unchanged on memory pressure); fallback-newest-wins scenario |
| T-261029rcc-07 | Tampering | frozen golden set | high | mitigate | four frozen files must stay byte-identical (git diff gate); vk.txt only with the recorded approval, mechanical golden_check (extra image and renumbering only), superseding record golden-freeze-14-rcc.sha256 |
| T-261029rcc-08 | Tampering | package4 contents | medium | mitigate | every bundle DLL sha256-compared; ANGLE audit on plugin + bundle DLLs; sha256 of every desktop file recorded in `## package4` |
| T-261029rcc-09 | Tampering | root pubspec.yaml user_define | medium | mitigate | relbuild.sh reverts with git checkout regardless of exit status; both gates require an empty porcelain line; explicit-path staging |
| T-261029rcc-10 | Repudiation | laptop verification result | medium | mitigate | numbered logs whose first line names the FIFO build; the reply asks for raw HUD values and durations |
| T-261029rcc-11 | Information Disclosure | adapter, power and counter log lines | low | accept | hardware facts only, in the user's own log files, sent voluntarily |
| T-261029rcc-12 | Elevation of Privilege | unsigned exe and bat launchers on the laptop | low | accept | the user's own dev build run as the user; launchers set one env var and redirect output |
| T-261029rcc-SC | Tampering | npm/pip/cargo installs | high | mitigate | no package installs; builds use the pinned workspace pub dependencies and the local bundle |
</threat_model>

<source_audit>
| Source item | Covered by |
|---|---|
| GOAL: FIFO depth-2 ready queue, swap at publish, repeated= counter, RTX 4060 A/B, laptop package4 | Task 1 steps 4-7, Task 2, Task 3 |
| D-01 FIFO + swap at publish, video-sync=audio unchanged | Task 1 steps 4-5; Dart-unchanged gate |
| D-02 cap 2, drop oldest -> superseded | Task 1 step 5 (publish block); scenarios 4, 5 |
| D-03 pop oldest else repeat, repeated counted | Task 1 step 5 (AcquireFront); scenarios 3, 6 |
| D-04 ring = quarantine + 4; fallback checked (ring 5, depth 1) | Task 1 step 5 (Start, fallback); scenario 10; vk-ring-fallback unchanged |
| D-05 RBE-05 kept, idle detection kept | Task 1 (AcquireFront has no libmpv call; affinity/bind tests); scenario 8 |
| D-06 probe counters superseded=/repeated=/queued= | Task 1 step 5 (probe block); scenarios 3-6 |
| Orchestrator test list (swap-at-publish, jitter, cap drop, repeat, resize/retire+quarantine, idle, device-lost/failure unchanged) | scenarios 1-9; device-lost covered by the unchanged chain_test and golden_vk gpu-timeout |
| PickBackBuffer never picks a queued frame; alloc-failure retry ring | Task 1 step 5; tearing check; scenario 10 |
| ARCHITECTURE.md swap reporting + frame queue | Task 1 step 9 |
| Local native tests /W4 /WX asserts; golden freeze unchanged or STOP; flutter analyze/test | Task 1 steps 2, 6, 8, 10, 11 (golden gate) |
| A/B baseline HEAD vs FIFO, metrics and gate; commit only on PASS | Task 1 steps 3, 7, 12 |
| package4: rebuild from the commit, package3 audit, desktop `_fifo`, `mpv_kit_fifo_*` logs with first line, 使用说明 AC >= 2 min per mode, keep old packages unless C: < 400 MB, `## package4` alone | Task 2, package_spec |
| checkpoint:human-verify laptop run | Task 3 |
| Re-notify (not in the decision text, required by Flutter's mark-driven textures) | Task 1 step 5, scenarios 3-5; reported as a judgment call |
| Deferred: step 2 timestamp picker, display-resample | excluded (not planned) |
</source_audit>

<verification>
- Task 1: swap machinery gone; FIFO members, counters, PickBackBuffer exclusion, re-notify and pickup-stamp change present; swap_test RED then GREEN; ALL rc=0 3x plus final; golden_check PASS; four frozen files unchanged; vk.txt and the new freeze record only with approval; ab_gate=PASS; integration, analyze and flutter test pass; commit is exactly the 20 paths.
- Task 2: `## package4` keys all yes; desktop package files and encodings correct; existing folders untouched; one commit with only laptop-package.txt; tree clean apart from protected files and the quick dir.
- Task 3: user reply received.
- Only CI can run (list in the SUMMARY as pending; the orchestrator pushes): meson builds of every renderer test incl. swap_test on Linux x64/arm64, macOS and Windows MSYS2 (warning_level=3, -Werror); the ASan/UBSan job; render_vk_smoke, render_d3d11_smoke, render_gl_smoke and stream_bridge_test (meson-built libmpv); the Linux-only drm_params_test; the Linux GL and macOS Metal plugins with FrameReady now also called from the compositor thread (real_plugin legs on CI runners); WARP and hosted-runner integration legs.
- Nothing pushed by this plan.
</verification>

<success_criteria>
- mpv gets each frame's swap at publish on the render thread, and frames that jitter between publish and pickup wait in a two-frame FIFO instead of being dropped; on the RTX 4060 effective drops are not worse than HEAD, and the laptop run is requested.
- The renderer never writes into a waiting, held or quarantined image; the frozen golden record changes only by the documented extra image and only with the user's approval.
- package4 is verified, on the desktop and traceable; the user's laptop reply is available to the orchestrator.
</success_criteria>

<output>
Create `.planning/quick/261029-rcc-fifo-depth-2-frame-queue-with-swap-at-pu/261029-rcc-SUMMARY.md` when done (not committed; the orchestrator handles quick-task docs). Include the A/B table, the RED/GREEN lines, the golden_check summary and the approval line, the frozen-file stale comments left in place (renderer_harness.h 365-367, golden_sw.cc:40, golden_vk.cc:47, 337, 346, 398-400), the RBE-04 note, how to read repeated=/queued= on mark-driven Flutter, the CI-only list, and any MSVC-only /WX relaxations.
</output>

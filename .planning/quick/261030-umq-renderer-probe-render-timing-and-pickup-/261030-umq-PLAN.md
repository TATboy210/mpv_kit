---
phase: quick-261030-umq
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - packages/mpv_kit_video/src/video_renderer.h
  - packages/mpv_kit_video/src/video_renderer.cc
  - packages/mpv_kit_video/windows/mpv_kit_video_plugin.cpp
  - native/tests/video_renderer_swap_test.cc
  - docs/ARCHITECTURE.md
  - .planning/quick/261030-umq-renderer-probe-render-timing-and-pickup-/261030-umq-PLAN.md
  - .planning/quick/261030-umq-renderer-probe-render-timing-and-pickup-/261030-umq-local-tests.log
  - .planning/quick/261030-umq-renderer-probe-render-timing-and-pickup-/261030-umq-measure.patch
  - .planning/quick/261030-umq-renderer-probe-render-timing-and-pickup-/261030-umq-RESULTS.txt
  - .planning/quick/261030-umq-renderer-probe-render-timing-and-pickup-/runs/run-d3d11-d3d11va.log
  - .planning/quick/261030-umq-renderer-probe-render-timing-and-pickup-/runs/run-d3d11-d3d11va.smi.csv
  - .planning/quick/261030-umq-renderer-probe-render-timing-and-pickup-/runs/run-vulkan-vulkan.log
  - .planning/quick/261030-umq-renderer-probe-render-timing-and-pickup-/runs/run-vulkan-vulkan.smi.csv
  - .planning/quick/261030-umq-renderer-probe-render-timing-and-pickup-/runs/run-vulkan-d3d11va-copy.log
  - .planning/quick/261030-umq-renderer-probe-render-timing-and-pickup-/runs/run-vulkan-d3d11va-copy.smi.csv
  - .planning/quick/261030-umq-renderer-probe-render-timing-and-pickup-/runs/run-d3d11-no.log
  - .planning/quick/261030-umq-renderer-probe-render-timing-and-pickup-/runs/run-d3d11-no.smi.csv
autonomous: false
requirements: [D3D-08, RBE-05]

estimate:
  tokens: 175000
  raw_tokens: 175000
  tasks: 3
  confidence: low

must_haves:
  truths:
    - "The renderer's 120-frame probe line keeps every existing field in its order (prev, done, max_done, superseded, repeated, queued) and ends with ` render=<avg>ms max_render=<max>ms`: the time the render thread spends in RenderBackend::Render (mpv_render_context_render plus the backend's completion signal) per published pipelined frame. Log only: no new lock, no new libmpv call, the publish block, the swap reporting and the software path are unchanged (RBE-05 holds)."
    - "video_renderer_swap_test checks that tail (both keys after queued=, in order, non-negative, max >= avg, max_render last). It is RED at the pre-change renderer in exactly fifo-jitter, fifo-cap-drop-q2, fifo-cap-drop-q4 and fifo-repeat, and GREEN after; every locally buildable renderer test ends ALL rc=0 under MSVC /W4 /WX with asserts on; the five golden-freeze-17 files are byte-identical."
    - "The Windows plugin's compositor pickup line keeps its fields (avg, max, backend) and ends with ` describes=<n> describe=<avg>ms max_describe=<max>ms handle_changes=<n> binds=<n> bind=<avg>ms max_bind=<max>ms`: Describe calls in the window, their duration from entry through AcquireFront, how many handed Flutter a different shared handle than the call before, and the time from Describe's return to the engine's release callback, which Flutter 3.47.8 calls synchronously right after its per-handle EGL surface update. The release callback still releases the same texture pointer exactly once; the callback never dereferences an Instance."
    - "real_plugin_test (auto) and d3d11_backend_test (forced d3d11) pass locally with the debug plugin; no Dart file is in any commit; example/lib and pubspec.yaml are clean after every build (the hwdec/loop/stats patch is applied only for the measurement build and stored as 261030-umq-measure.patch)."
    - "After the user's `start`, four gated 135 s runs on the RTX 4060 (d3d11+d3d11va, vulkan+vulkan, vulkan+d3d11va-copy, d3d11+no; example window in front, hands-off) are recorded with 1 s nvidia-smi samples, and no nvidia-smi option that changes GPU state is ever invoked; 261030-umq-RESULTS.txt holds the sample provenance, one gate, run and smi line per combo, a comparison table and the reading notes, including what the plugin still cannot time."
    - "Two local commits by explicit path (probe code, then results); nothing pushed; protected user files untouched."
  artifacts:
    - path: "packages/mpv_kit_video/src/video_renderer.cc"
      provides: "render-call timing on the probe line"
      contains: "max_render="
    - path: "packages/mpv_kit_video/src/video_renderer.h"
      provides: "probe_render_ms_, probe_render_max_ms_"
      contains: "probe_render_max_ms_"
    - path: "packages/mpv_kit_video/windows/mpv_kit_video_plugin.cpp"
      provides: "Describe duration, handle-change count and release-callback bracket on the pickup line"
      contains: "max_bind="
    - path: "native/tests/video_renderer_swap_test.cc"
      provides: "probe tail check (render=, max_render=)"
      contains: "kMaxRenderKey"
    - path: "docs/ARCHITECTURE.md"
      provides: "both probe line formats and how to read the new fields"
      contains: "handle_changes="
    - path: ".planning/quick/261030-umq-renderer-probe-render-timing-and-pickup-/261030-umq-RESULTS.txt"
      provides: "four-combo RTX 4060 record"
      contains: "run combo=d3d11+no "
  key_links:
    - from: "VideoRenderer::RenderOnce (render thread)"
      to: "render waits probe line"
      via: "steady_clock around render_backend_->Render, summed in the pipelined block, appended after queued="
      pattern: "max_render="
    - from: "Describe (raster thread)"
      to: "Flutter ExternalTextureD3d::CreateOrUpdateTexture (external_texture_d3d.cc:84-115, 3.47.8)"
      via: "return stamp in a thread_local, read by the captureless release callback the engine calls right after its surface update"
      pattern: "thread_local"
    - from: "build/umq/run_combo.sh + metrics.sh"
      to: "261030-umq-RESULTS.txt"
      via: "CR-stripped logs, windows probe 6.., pickup 6.., stats 10.."
      pattern: "run combo="
  prohibitions:
    - requirement_id: RBE-05
      category: scope
      status: unresolved
      verification: null
      statement: "MUST NOT add any libmpv call, lock or behaviour change to video_renderer.{h,cc} or the plugin (timing and log text only); MUST NOT change any Dart file in a commit, the public API, the reason grammar, kWindowsApiOrder, ring sizes or any golden-freeze-17 file."
    - requirement_id: D3D-08
      category: process
      status: unresolved
      verification: null
      statement: "MUST NOT lock or change GPU clocks, power limit or persistence mode; MUST NOT start a hardware run before the user replied `start`; MUST NOT shorten or repeat a run; MUST NOT push; MUST NOT stage or modify .planning/config.json, .planning/state.json, .planning/tmp/, .planning/ui-reviews/, .planning/debug/ or engine_repo_embedder.cc; MUST NOT download any tool or media."
---

<objective>
Add two log-only measurements and use them in a controlled four-combo run on the RTX 4060.

1. Renderer probe line: time spent in `render_backend_->Render` per frame, as ` render=<avg>ms max_render=<max>ms` at the end of the existing `render waits avg/over 120 frames` line.
2. Windows pickup line: Describe duration per call, whether the shared handle changed from the previous call, and the engine's surface update after Describe returns (bracketed by the release callback), at the end of the existing `compositor pickup avg/over 120 frames` line.
3. Four 135 s runs of a 4K H.264 file with forced backend and hwdec (d3d11+d3d11va, vulkan+vulkan, vulkan+d3d11va-copy, d3d11+no), with nvidia-smi samples. These separate the decoder from the render API. The GTX 960M A/B that started the todo compared vulkan+hwdec=vulkan with d3d11+d3d11va.

Purpose: the todo `.planning/todos/pending/2026-10-30-d3d11-slower-than-vulkan-on-maxwell-before-switch.md` needs per-frame cost data before the D3D11-first switch (D3D-08) is revisited. The investigation has two open questions. Is the cost in mpv's render call or in the compositor's per-frame handle change? Does the decoder path explain the gap?
Output: one code commit (probe fields, test, docs, local test log), one results commit (RESULTS, raw logs, nvidia-smi CSVs, measurement patch). Nothing is pushed.
</objective>

<execution_context>
@~/.claude/gsd-core/workflows/execute-plan.md
@~/.claude/gsd-core/templates/summary.md
</execution_context>

<context>
@.planning/STATE.md
@CLAUDE.md
@.planning/.continue-here.md
@.planning/todos/pending/2026-10-30-d3d11-slower-than-vulkan-on-maxwell-before-switch.md
@.planning/quick/261029-rcc-fifo-depth-2-frame-queue-with-swap-at-pu/261029-rcc-SUMMARY.md
@.planning/quick/261029-rcc-fifo-depth-2-frame-queue-with-swap-at-pu/261029-rcc-AB.txt

The planner verified these facts. Do not derive them again.
- HEAD during planning: a2c05d7 (a docs-only commit on top of 6407ea0). Product code has not changed since 0e792c8 plus Phase 17. golden-freeze-17 sha check: OK. `build/phase17/libmpv-rtx` MANIFEST check: OK.
- Renderer, packages/mpv_kit_video/src/video_renderer.cc:
  - `AssertRenderThread()` and `render_backend_->Render(api_, render_ctx_, back, w, h)` are at lines 807-808, and the err < 0 return is at 809-815.
  - The pipelined block after the render is at 816-861: done-wait timing at 823-830, the probe window at 833-853 (counter snapshot under mutex_ at 834-841, log_ expression at 842-848 ending `" queued=" + std::to_string(queued)`, sum resets at 849-852).
  - The publish block (862-882) and ReportSwaps(1)/FrameReady (889-890) stay untouched.
- Header, packages/mpv_kit_video/src/video_renderer.h: probe comment at 202-205; kProbeWindow 206; probe_frames_, probe_wait_prev_ms_, probe_wait_done_ms_, probe_wait_done_max_ms_ at 207-210 (render thread only, no lock); superseded/repeated/queued at 211-220 (under mutex_).
- mpv timing, native/mpv/video/out/vo_libmpv.c:
  - 425-431: with MPV_RENDER_PARAM_BLOCK_FOR_TARGET_TIME at its default 1, mpv_render_context_render returns only after the VO thread's flip_page bumped present_count. flip_page (526-545) runs after vo.c's wait_until(target), video/out/vo.c:1014-1018.
  - So `render=` is the later of the render work and the frame's target time. It is an upper bound on the render work, not the render work itself. Neither backend passes that parameter: windows/d3d11_backend.cpp:254-270 passes only D3D11_FBO and FLIP_Y.
  - The Vulkan and D3D11 Render implementations (vulkan_backend.cc:553, d3d11_backend.cpp:254) also signal their completion value after the mpv call.
- Plugin, packages/mpv_kit_video/windows/mpv_kit_video_plugin.cpp. The file is CRLF in the index and in the worktree. MSYS grep and awk strip CR, so check line endings with `file` and `git ls-files --eol` only.
  - LogLine 56-59, kPickupWindow 63, SteadyNowNs 66-70.
  - Instance 73-91: pickup fields 78-85 under `mutex`, raster thread.
  - RecordPickup 310-327: `char line[...]` of 160 bytes, format at 319-322 ending `backend=%s`, resets 324-326.
  - Describe 330-352: lock 331; stamp load before AcquireFront 333-335; AcquireFront 336; null check 337; RecordPickup 338; tex cast 339; descriptor fill 340-347; release callback 348-350, a captureless lambda that releases `static_cast<ID3D11Texture2D*>(ctx)`. release_context is the COM texture pointer, on purpose: a ring reallocation may free the D3D11Interop::Texture struct while the compositor holds the texture.
  - The plugin has no mpv call (0 matches for libmpv render symbols).
- Flutter 3.47.8 at /d/flutter (the SDK on this host), engine/src/flutter/shell/platform/windows/external_texture_d3d.cc:
  - PopulateTexture (32-52) calls the texture callback, which is Describe, and then CreateOrUpdateTexture.
  - CreateOrUpdateTexture does GL BindTexture (71-81). When `handle != last_surface_handle_` (84) it runs ReleaseImage (eglReleaseTexImage + eglDestroySurface, 54-61), then CreateSurfaceFromHandle (eglCreatePbufferFromClientBuffer, egl/manager.cc:317-322), then eglBindTexImage (86-110).
  - Only after that does it call `release_callback(release_context)` synchronously (112-115).
  - So the interval from Describe's return to the release callback brackets the engine's per-frame surface update on the raster thread, and the plugin can time it without changing ownership. The orchestrator's assumption that this cost cannot be timed is refined here. The engine's later draw and sampling of the texture, and ANGLE's internal synchronization, stay unmeasurable from the plugin.
  - mpv_kit hands out a different ring texture per new frame, so the handle should change on almost every Describe. `handle_changes=` measures that.
- Probe line consumers:
  - native/tests/video_renderer_swap_test.cc reads ` superseded=`, ` repeated=`, ` queued=` with find + atoi (ReadKey 423-428, ReadProbe 432-455). Appended fields do not disturb it.
  - CheckProbe callers: fifo-jitter (544), CheckCapDrop (562, used by fifo-cap-drop-q2 and fifo-cap-drop-q4), fifo-repeat (583). Scenario table at 725-736.
  - No golden file contains a probe line (`render waits` occurs 0 times in native/tests/golden/*). build/rcc/ab_metrics.sh parses both lines with unanchored regexes, so appended fields are safe.
  - swap_test.cc is not in golden-freeze-17 (renderer_harness.h, golden_sw.cc, golden_vk.cc, golden/sw.txt, golden/vk.txt).
- Example: example/lib/main.dart.
  - The Player options map at 41-53 has `'ao': ?Platform.environment['MPV_KIT_EXAMPLE_AO']`, and hwdec comes from the per-platform default.
  - `_hudTick` debugPrint at 87-88 prints `mpv_kit_example: <dropped> dropped, avdiff=<avsync>`.
  - The first ticks print HudSnapshot.fabricated() values (dropped 0, hwdec `vulkan`, hud.dart:127-150), so stats lines before line 10 are never evaluated.
  - Player gives a user hwdec precedence over the default (hwdec_defaults.dart). mpv's `config=no` secure default means no mpv.conf or environment can set hwdec. Forcing hwdec therefore needs the temporary example patch.
- Samples on this host (read-only moov parse during planning):
  - No 3840x2160 59.94 fps H.264 file exists in example/integration_test/route_samples/ (640x360 files plus a 3840x2160 HEVC Main10 30 fps 10 s file), in build/phase17/samples-ci/ (the same), or in `$HOME/Desktop`, `$HOME/Downloads` or /d (depth 3).
  - Nearest match: `$HOME/Desktop/1145142.mp4`. It is avc1 (Main, level 5.2), 3840x2160, 60.000 fps (mdhd timescale 60, stts delta 1, 2214 frames), 36.9 s, with an AAC 44.1 kHz track.
  - `$HOME/Downloads/4k_test.mp4` is 2560x1440 at 29.97 fps, and `$HOME/Desktop/114514.mp4` is 1920x1080 at 60 fps.
  - Generating a 59.94 file locally is impossible. There is no ffmpeg on the host, and the LGPL bundle disables every H.264 encoder (native/build/ffmpeg.sh:82, only png, mjpeg and ac3).
  - x264 test media is only made on CI (tools/make_hwdec_samples.sh, ubuntu ffmpeg), which would need a workflow change and a push.
  - So the checkpoint asks the user for the laptop's own 4K59.94 H.264 file, or for approval of the looped 60.000 fps fallback.
- nvidia-smi on this host accepts `--query-gpu=timestamp,pstate,clocks.gr,clocks.sm,clocks.mem,clocks.video,utilization.gpu,utilization.memory,utilization.decoder,utilization.encoder,temperature.gpu,power.draw,clocks_event_reasons.active` (checked during planning). Event-reason bits: 0x1 idle, 0x4 SW power cap, 0x8 HW slowdown, 0x20 SW thermal, 0x40 HW thermal, 0x80 power brake.
- Reusable, gitignored scripts. Copy them into build/umq/ and adapt; do not edit the originals:
  - build/phase17/goldens/build_all.bat and run_all.sh: MSVC 14.44 /W4 /WX with asserts on, all 13 renderer tests.
  - build/rcc/run_ab.sh, ab_metrics.sh, integ.sh, smoke.sh.
  - build/nwm/relbuild.sh and power.ps1.
  - .planning/phases/17-fallback-hardening-uhd-regression/tools/rtx_run.sh: the `gate` subcommand, plus the standby and crash query at 175-195.
  - A copy at build/umq/ resolves PHASE_DIR to build/, so its PREP file is absent, native_equal is n/a, and the gate never writes a file.
- Host: Windows MINGW64 Git Bash, cwd D:/mpv_kit, `/d/flutter/bin/flutter` 3.47.8, MSVC 14.44, RTX 4060 Laptop GPU at 165 Hz.
  - D: has about 7.5 GB free and C: about 2.2 GB.
  - Python is `python` (/d/python/python); run it with `-I` on media files.
  - The Dart VM needs a backslash MPV_KIT_LIBMPV_PATH (`cygpath -w`).
  - Release runs unset MPV_KIT_LIBMPV_PATH: the hook places the bundle next to the exe.
- Tracked files: video_renderer.{h,cc}, swap_test.cc and ARCHITECTURE.md are LF; the plugin .cpp is CRLF. Keep each as it is.
</context>

<executor_rules>
- `source /tmp/gsd-bak/root_pin.sh` (PINNED_ROOT='D:/mpv_kit') before the first Edit/Write and before every commit. If /tmp was cleared, regenerate it from ~/.claude/gsd-core/references/worktree-path-safety.md step 0p.
- Protected user files: `.planning/config.json`, `.planning/state.json`, `.planning/tmp/`, `.planning/ui-reviews/`, `.planning/debug/`, `engine_repo_embedder.cc`. Never stage, modify, revert or delete them.
  - Around any gsd-tools call: `cp .planning/state.json /tmp/gsd-bak/state.json.umq` before, `cmp` after, restore if it changed.
  - Stage by explicit path only; never `git add -A` or `git add .`.
  - Other sessions work in this repository: during planning, ROADMAP.md and STATE.md were modified and a new phase dir 17.1 appeared that are not this task's. Leave them alone.
  - Commit with an explicit pathspec (`git add <paths>`, then `git commit -m ... -- <paths>`), so anything another session staged stays out of the commit.
  - Gates name commits by the shas recorded in build/umq/commit1.sha and build/umq/commit2.sha, never by HEAD~N.
- Sequential, main tree, local commits only, never push. Every commit message ends with `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.
- Scratch goes to build/umq/ (gitignored) or /tmp. Evidence files in the quick dir are LF: strip CR from tool and program output.
- C++ comments are in English, at the density of the surrounding code; every new field and function gets a comment saying what it measures and that it is log-only.
- GPU: only `--query-gpu` reads. Never call any nvidia-smi option that changes state (clock locks or resets, application clocks, power limit, persistence or compute mode, ECC, GPU reset). The user did not authorize clock locking.
  - Do not write any such option letter or name on a build/umq script line that mentions nvidia-smi, not even in a comment: a gate scans every such line.
- Hardware runs, per .continue-here: no run before `start`; a gate before every run; never shorten or repeat a run; on any interruption (gate FAIL, standby, crash, process gone early, example not in front at the end) stop the remaining runs and return a checkpoint with the facts.
- Never copy, move, re-encode or modify a media file. Never download anything. If a test failure is not predicted here, diagnose it; if the cause is outside files_modified, STOP and report instead of widening the diff.
</executor_rules>

<!-- planner-discipline-allow: -lgc -->
<!-- planner-discipline-allow: --lock-gpu-clocks -->
<!-- planner-discipline-allow: nvidia-smi -->
<!-- planner-discipline-allow: mpv_kit_example -->

<tasks>

<task type="tracer" tdd="true">
  <name>Task 1: Probe fields end to end. RED/GREEN native test, renderer and plugin timing, docs, local gates, commit, then measurement build, harness, smoke and sample selection</name>
  <files>native/tests/video_renderer_swap_test.cc, packages/mpv_kit_video/src/video_renderer.h, packages/mpv_kit_video/src/video_renderer.cc, packages/mpv_kit_video/windows/mpv_kit_video_plugin.cpp, docs/ARCHITECTURE.md, .planning/quick/261030-umq-renderer-probe-render-timing-and-pickup-/261030-umq-PLAN.md, .planning/quick/261030-umq-renderer-probe-render-timing-and-pickup-/261030-umq-local-tests.log, .planning/quick/261030-umq-renderer-probe-render-timing-and-pickup-/261030-umq-measure.patch (created here, committed in Task 3)</files>
  <read_first>
    - packages/mpv_kit_video/src/video_renderer.cc lines 793-892; packages/mpv_kit_video/src/video_renderer.h lines 200-222
    - packages/mpv_kit_video/windows/mpv_kit_video_plugin.cpp lines 54-91 and 305-352
    - native/tests/video_renderer_swap_test.cc lines 1-30, 60-80, 417-475, 725-776
    - docs/ARCHITECTURE.md lines 96-122 and 336-348
    - /d/flutter/engine/src/flutter/shell/platform/windows/external_texture_d3d.cc lines 32-118 (read-only, outside the repo)
    - example/lib/main.dart lines 40-95
    - build/phase17/goldens/build_all.bat, build/phase17/goldens/run_all.sh, build/rcc/integ.sh, build/rcc/run_ab.sh, build/rcc/ab_metrics.sh, build/nwm/relbuild.sh, build/nwm/power.ps1
    - .planning/phases/17-fallback-hardening-uhd-regression/tools/rtx_run.sh lines 1-60 and 84-200
  </read_first>
  <precondition>All of these hold:
- `git diff --quiet 6407ea0 HEAD -- packages/mpv_kit_video native/tests docs/ARCHITECTURE.md example/lib` succeeds, so the line maps in context hold, and `git status --porcelain -- packages native docs example pubspec.yaml` is empty.
- `sha256sum -c --quiet .planning/phases/17-fallback-hardening-uhd-regression/evidence/golden-freeze-17.sha256` passes, and `(cd build/phase17/libmpv-rtx && sha256sum -c --quiet MANIFEST.txt)` reports no failure.
- `df -Pm .` shows at least 2048 MiB available.
- build/phase17/goldens/build_all.bat and /tmp/gsd-bak/root_pin.sh exist.</precondition>
  <behavior>
    - swap_test probe tail check. Every probe line that ReadProbe accepts must:
      - contain ` render=` after the ` queued=` value, and ` max_render=` after that;
      - have both values parse as finite, non-negative decimals, each immediately followed by `ms`;
      - have max_render at or above render;
      - end with the `ms` of max_render.
    - Without the tail, the scenario reports `SWAP invariant scenario=<name>: probe line does not end with render=<ms>ms max_render=<ms>ms: <line>`.
    - Before the renderer change, exactly fifo-jitter, fifo-cap-drop-q2, fifo-cap-drop-q4 and fifo-repeat fail (swap_test rc=1). After it, `SWAP ok scenarios=10`.
    - All other scenario expectations (counts, order, FrameReady totals) are unchanged.
  </behavior>
  <action>
    Requirement scope: D3D-08 (data for the open decision) and RBE-05 (no new libmpv call off the render thread; in fact none at all). The change is timing and log text only.

    1. Pin the root.
       - Create build/umq/ and build/umq/tests/. build/umq/tests/ has the same depth as build/phase17/goldens/, so the bat's `..\..\..` root computation stays valid.
       - Copy build/phase17/goldens/build_all.bat and run_all.sh into build/umq/tests/ and change only the output directory (OUT, D) to build/umq/tests.
       - Start the quick-dir file 261030-umq-local-tests.log (LF) with:
         - `host` (uname -a),
         - `cl` (the cl banner line),
         - `base=<git rev-parse HEAD>`.

    2. RED.
       - In native/tests/video_renderer_swap_test.cc add the named constants kRenderKey (` render=`) and kMaxRenderKey (` max_render=`), next to kQueuedKey.
       - Implement the tail check of the behavior block inside ReadProbe, after the three existing keys were read. Use std::strtod with an end pointer, no new headers beyond the standard library.
       - Extend the file header comment by one sentence: the probe line also ends with the render call time, checked for presence and order only (quick 261030-umq).
       - The file must stay clean under MSVC /W4 /WX and gcc/clang -Wall -Wextra -Wpedantic -Werror.
       - Build with `cmd //c 'build\umq\tests\build_all.bat'` against the unchanged renderer, then run `bash build/umq/tests/run_all.sh`.
       - Append to the log: `--- RED (swap_test tail check, renderer at base) ---`, the per-test lines, and `red swap_test rc=1 failing=<names>`. Take the names from the `SWAP invariant scenario=<name>:` lines of build/umq/tests/out_swap_test.txt.clean, in the order they appear.
       - The expected line is `red swap_test rc=1 failing=fifo-jitter,fifo-cap-drop-q2,fifo-cap-drop-q4,fifo-repeat`, with every other test at rc=0. Anything else: STOP and report.

    3. Renderer, render-call timing.
       - video_renderer.h, after probe_wait_done_max_ms_: add `double probe_render_ms_ = 0;` and `double probe_render_max_ms_ = 0;`. Comment them as time in RenderBackend::Render per probed frame: mpv's render call, including its wait for the frame's target time, plus the backend's completion signal. They are render-thread only, like the wait sums.
       - Extend the probe comment block above kProbeWindow by one sentence about the render time.
       - video_renderer.cc: take a steady_clock stamp right before `render_backend_->Render(...)`, after AssertRenderThread, and compute `render_ms` right after it.
       - Comment above the stamp: what it includes (BLOCK_FOR_TARGET_TIME is left at mpv's default 1, so mpv_render_context_render also waits for the frame's target time, vo_libmpv.c:425-431; the result is an upper bound on render work) and that it is log-only.
       - Inside the existing pipelined block, next to the done-wait sums and before the window check, add render_ms to probe_render_ms_ and raise probe_render_max_ms_.
       - Append to the log_ expression, after the queued value: ` render=`, avg (std::to_string(probe_render_ms_ / probe_frames_)), `ms max_render=`, max (std::to_string), `ms`.
       - Reset both sums with the other probe sums.
       - Nothing else changes. The err < 0 path returns before any accumulation, as the other sums do; the software backend never reaches the pipelined block; no lock or libmpv call is added.

    4. Plugin. Keep CRLF on every new line, and edit only this file's Instance, the new thread-locals, RecordPickup and Describe.
       - Instance, after pickup_max_ms: a commented group "Describe probe (measurement only; raster thread under [mutex]; reset with the pickup line)" with:
         - `int describe_count`, `double describe_total_ms`, `double describe_max_ms`;
         - `int handle_changes` and `HANDLE last_handle = nullptr`;
         - `int bind_count`, `double bind_total_ms`, `double bind_max_ms`.
       - After SteadyNowNs, add four `thread_local` variables in the anonymous namespace:
         - the owner (`const void*`) and steady-ns stamp of the last descriptor Describe handed out on this thread;
         - the owner (`const void*`) and duration of the last bracketed engine update.
       - Doc comment for the thread-locals:
         - why they are needed: the release callback's only context is the texture, and Flutter 3.47.8 calls it synchronously on the raster thread right after its surface update (external_texture_d3d.cc:84-115);
         - owners are compared, never dereferenced;
         - a callback on another thread, or another instance in between, drops that sample (binds= counts the matched ones).
       - Describe:
         - Stamp entry before the lock_guard.
         - After the null check, move the tex cast up.
         - If the bound owner equals inst, add its duration to the bind sums and clear the owner.
         - Count a handle change when tex->shared_handle differs from inst->last_handle, then store it.
         - Add (now - entry) to the describe sums and max. This covers lock, stamp load, AcquireFront (including a re-notify mark) and the handle compare. It excludes the descriptor stores and the window's log write.
         - Then call RecordPickup(inst, ready) unchanged, then do the unchanged descriptor fill.
         - Right before `return &d`, set this thread's descriptor owner to inst and its stamp to SteadyNowNs().
         - Comment each step.
       - Release callback:
         - Before the unchanged `static_cast<ID3D11Texture2D*>(ctx)->Release()`: if this thread has a descriptor stamp, store (now - stamp) as the bound duration with that owner, and clear the stamp.
         - Comment it as the end of the engine's GL bind and, on a handle change, EGL surface recreate (external_texture_d3d.cc:71-115).
         - The texture pointer and the single Release stay as they are.
       - RecordPickup:
         - Grow the 160-byte line buffer to `char line[320]`.
         - Append ` describes=%d describe=%.3fms max_describe=%.3fms handle_changes=%d binds=%d bind=%.3fms max_bind=%.3fms` after `backend=%s`. Averages print 0 when the count is 0.
         - Reset the new fields with the pickup sums.
         - Update its doc comment and the Instance comment.

    5. docs/ARCHITECTURE.md, two scoped edits in the file's prose style.
       - Frame queue bullet (about lines 114-116): the probe line now carries `superseded=<n> repeated=<n> queued=<n>` and ends with `render=<avg>ms max_render=<max>ms`. Add the time in RenderBackend::Render and the BLOCK_FOR_TARGET_TIME caveat (mpv waits for the frame's target time inside the call, so this is an upper bound on render work).
       - Pickup latency bullet (about lines 344-347): give the full line with the new fields. Explain:
         - describes= and describe= (entry through AcquireFront);
         - handle_changes= (Flutter's ExternalTextureD3d keeps one cached handle and recreates its EGL pbuffer surface on every change, external_texture_d3d.cc in Flutter 3.47.8; with the ring nearly every new frame is a change);
         - binds= and bind= (Describe's return to the release callback, which the engine calls synchronously after that update, so it brackets the per-frame surface update but not the later draw).
         - Close with "Measurement only."

    6. GREEN.
       - Rebuild with build_all.bat and run run_all.sh twice. Each run must end `ALL rc=0` (swap_test `SWAP ok scenarios=10`).
       - Append `--- GREEN run 1 ---` and `--- GREEN run 2 ---` blocks.
       - Run `sha256sum -c .planning/phases/17-fallback-hardening-uhd-regression/evidence/golden-freeze-17.sha256` and append its five OK lines.

    7. Integration, debug plugin with asserts on. Write build/umq/integ.sh from build/rcc/integ.sh:
       - temporary root pubspec user_define `libmpv_bundle: build/phase17/libmpv-rtx`;
       - LIB=$PWD/build/phase17/libmpv-rtx/lib;
       - MPV_KIT_LIBMPV_PATH set from `cygpath -w` of $LIB/libmpv-2.dll. If the value contains no backslash, STOP;
       - MPV_KIT_REQUIRE_LIBMPV=1 and PATH=$LIB:$PATH;
       - a trap that runs `git checkout -- pubspec.yaml` on every exit path.

       It runs `real_plugin_test.dart` with MPV_KIT_VIDEO_API unset and `d3d11_backend_test.dart` with MPV_KIT_VIDEO_API=d3d11, both via `/d/flutter/bin/flutter test integration_test/<file> -d windows` from example/, logging to build/umq/integ-real.log and build/umq/integ-d3d11.log.
       - Pass means rc 0 and a line matching `tests passed\.[[:space:]]*$`.
       - Append `integration real_plugin_test=<pass|fail> d3d11_backend_test=<pass|fail>` and `pubspec_porcelain=[<git status --porcelain pubspec.yaml>]`.
       - A failure blocks the commit: diagnose, fix only inside files_modified, rerun.

    8. Commit 1.
       - Pin the root.
       - Stage exactly: video_renderer.h, video_renderer.cc, mpv_kit_video_plugin.cpp, native/tests/video_renderer_swap_test.cc, docs/ARCHITECTURE.md, the quick-dir 261030-umq-PLAN.md and 261030-umq-local-tests.log.
       - Message, for example: `feat(video): log render-call and compositor Describe timing on the probe lines`.
       - Body:
         - what each new field measures;
         - the BLOCK_FOR_TARGET_TIME caveat;
         - the release-callback bracket and its Flutter source;
         - log only, no behaviour change, RBE-05 unchanged;
         - goldens unchanged;
         - quick 261030-umq.
       - End with the Co-Authored-By line. Commit with the explicit pathspec, then write the full sha to build/umq/commit1.sha. Do not push.

    9. Measurement patch and build. The example is never committed.
       - Edit example/lib/main.dart with three edits:
         1. In the Player options map, right after the 'ao' entry, add a one-line comment `// Measurement only (quick 261030-umq, never committed): forced hwdec, looping, decoder line.`, then the null-aware entry `'hwdec': ?Platform.environment['MPV_KIT_EXAMPLE_HWDEC'],`, then a collection-if that adds `'loop-file': 'inf'` when MPV_KIT_EXAMPLE_LOOP is `1`.
         2. In `_hudTick`'s debugPrint, append ` hwdec=${hud.decode['hwdec']} dec-drop=${hud.sync['dec-drop']}` after the avdiff value.
         3. Nothing else.
       - Save it with `git diff -- example/lib/main.dart` to the quick-dir 261030-umq-measure.patch (LF), then `git checkout -- example/lib/main.dart`. `git apply --check` of the patch must succeed.
       - Write build/umq/relbuild.sh from build/nwm/relbuild.sh:
         - append the phase17 bundle user_define;
         - `git apply` the patch;
         - `(cd example && /d/flutter/bin/flutter build windows --release)`;
         - restore pubspec.yaml and example/lib/main.dart with `git checkout --` from a trap on every exit path;
         - append `build rc=<n> seconds=<n>`, `head=<git rev-parse HEAD>`, `patch_sha256=<sha256 of the patch>` and `porcelain=[<git status --porcelain -- pubspec.yaml example/lib>]`.
       - Run `bash build/umq/relbuild.sh build/umq/meas-build.log`. It needs rc 0 and an empty porcelain.
       - Then check the Release dir example/build/windows/x64/runner/Release:
         - mpv_kit_video_plugin.dll contains ` max_render=` and ` max_bind=` (grep -a);
         - data/app.so contains `MPV_KIT_EXAMPLE_HWDEC`.

    10. Harness, all under build/umq/ (gitignored).
        - mp4info.py, run with `python -I`. A read-only parse of moov/trak:
          - hdlr `vide`;
          - mdhd timescale and duration;
          - the first stsd entry: fourcc, width and height (offset 32 into the entry);
          - the first stts entry: frame delta.
          - Output per file: `sample_candidate path=<p> codec=<fourcc> size=<w>x<h> fps=<timescale/delta, 3 decimals> duration_s=<1 decimal>`.
          - It prints `sample_candidate path=<p> unreadable` for files without a parsable moov.
        - select_sample.sh <optional explicit path>. Without an argument it probes, in this order:
          - build/umq/sample/* (where the user may place a file);
          - then *.mp4, *.mov and *.m4v of at least 20 MB under `$HOME/Desktop`, `$HOME/Downloads`, `$HOME/Videos` (depth 3) and /d (depth 3).

          It writes all candidate lines plus one `sample_selected path=<p> codec=.. size=.. fps=.. duration_s=.. qualifies=<yes|no> loop=<0|1> note="<...>"` line to build/umq/sample.txt. Selection rule:
          - The first file that qualifies wins: codec avc1 or avc3, 3840x2160, fps within 0.01 of 59.940. loop=0 when its duration is at least 135 s, else loop=1.
          - Without one, the fallback is `$HOME/Desktop/1145142.mp4`. It must probe as avc1 3840x2160 60.000 fps; if not, STOP. Use qualifies=no, loop=1 and note "deviation: 60.000 fps not 59.94; 36.9 s looped, about three loop seeks per run".
          - An explicit path is probed and selected as given (loop by duration), whether or not it qualifies.
        - rtx_gate.sh: a copy of the Phase 17 rtx_run.sh with MIN_DISK_MIB=1024 and a header line saying it is the quick 261030-umq copy, used only as `bash build/umq/rtx_gate.sh gate <run>`.
        - run_combo.sh <tag> <api> <hwdec> <seconds>, with GATE=0 for smokes. It runs from the repo root. Steps:
          1. Unless GATE=0, run the gate, appending its line to build/umq/<tag>.meta. On FAIL, exit 3 and start nothing.
          2. Refuse to overwrite an existing build/umq/<tag>.log (exit 4).
          3. Require that no mpv_kit_example process is running.
          4. Read build/umq/sample.txt for path and loop.
          5. Write `start=<UTC ms>` to the meta.
          6. Start the nvidia-smi logger in the background with the verified query list, `--format=csv,noheader,nounits -lms 1000`, into build/umq/<tag>.smi.csv.
          7. Start example/build/windows/x64/runner/Release/mpv_kit_example.exe with:
             - `env -u MPV_KIT_LIBMPV_PATH -u MPV_KIT_VIDEO_RENDERER`;
             - MPV_KIT_VIDEO_API=<api>, MPV_KIT_EXAMPLE_HWDEC=<hwdec> and MPV_KIT_EXAMPLE_AO=null;
             - MPV_KIT_EXAMPLE_LOOP=1 only when loop=1;
             - the sample's `cygpath -w` path as the only argument;
             - stdout and stderr to build/umq/<tag>.log.
          8. After 10 s, record `fg_start=<process name of the foreground window>` (GetForegroundWindow/GetWindowThreadProcessId as in rtx_run.sh's gate_facts). If it is not mpv_kit_example, try one WScript.Shell AppActivate on the example's pid, record `fg_fix=yes` and the re-checked name.
          9. Sleep until <seconds> after the start. Record `alive_at_end=<yes|no>` (tasklist) and `fg_end=<name>`.
          10. Run `taskkill //IM mpv_kit_example.exe`; force it after 10 s if needed and record `forced=yes`.
          11. Stop the logger (kill its pid; taskkill //F only for our nvidia-smi if it survives).
          12. Write `end=<UTC ms>`, then run the System Kernel-Power 506/507 and Application 1000/1001 query of rtx_run.sh lines 175-195 for the window, giving `standby=<none|...>` and `forensics=<none|...>`.
          13. Exit 0. Comment the script header with usage and exit codes.
        - metrics.sh <tag> <api> <hwdec> prints two lines from the CR-stripped build/umq/<tag>.log, .meta and .smi.csv.

          The run line, keys in this order:
          `run combo=<api>+<hwdec> tag=<tag> start=.. end=.. alive_at_end=.. fg_start=.. fg_end=.. standby=.. forensics=.. reason="<first mpv_kit_video: line minus prefix>" api_ok=<yes|no> hwdec_seen=<distinct hwdec values of stats lines 10..end, comma-joined> hwdec_ok=<yes|no> stat_lines=<n> probe_lines=<n> pickup_lines=<n> drops=<n> dec_drops=<n> superseded=<n> queued=<n> effective=<n> prev_med=<ms> done_med=<ms> done_max=<ms> render_med=<ms> render_max=<ms> pickup_med=<ms> pickup_max=<ms> describes=<n> describe_med=<ms> describe_max=<ms> handle_changes=<n> handle_change_ratio=<2 decimals> binds=<n> bind_med=<ms> bind_max=<ms> avsync_max=<s> errors=<n>`
          - api_ok: the reason matches `^[a-z0-9-]+ \(<api> \(gpu-next\) on NVIDIA GeForce RTX 4060`.
          - hwdec_ok: every stats line from 10 on shows hwdec=<hwdec>.
          - Windows and drops as in build/rcc/ab_metrics.sh: probe and pickup lines 6..end, stats lines 10..end.
          - drops and dec_drops are the last minus the 10th stats value.
          - *_med is the median of per-window averages; *_max is the maximum of per-window maxima.
          - describes, handle_changes and binds are sums over pickup windows 6..end.
          - errors counts as in ab_metrics.

          The smi line, over CSV rows from start + 10 s to end:
          `smi combo=<api>+<hwdec> rows=<n> pstates=<set> gr_mhz=<med>/<min>/<max> mem_mhz=<med>/<min>/<max> video_mhz=<med>/<min>/<max> util_gpu=<med>/<max> util_mem=<med>/<max> util_dec=<med>/<max> temp_c=<first>/<max> power_w=<med>/<max> event_reasons=<distinct values>`.
        - Every nvidia-smi invocation in these scripts is a `--query-gpu` read.

    11. Smoke. This is the harness dry run, not a measurement; the user may be using the machine.
        - Run `bash build/umq/select_sample.sh`.
        - Run `GATE=0 bash build/umq/run_combo.sh smoke-d3d11-d3d11va d3d11 d3d11va 30` and `GATE=0 bash build/umq/run_combo.sh smoke-vulkan-vulkan vulkan vulkan 30`.
        - Write both metrics outputs to build/umq/smoke.txt.
        - In both CR-stripped smoke logs:
          - every line containing `render waits avg/over` matches `render waits avg/over [0-9]+ frames: prev=[0-9.]+ms done=[0-9.]+ms max_done=[0-9.]+ms superseded=[0-9]+ repeated=[0-9]+ queued=[0-9]+ render=[0-9.]+ms max_render=[0-9.]+ms$`, and there are at least 5;
          - every line containing `compositor pickup avg/over` matches `compositor pickup avg/over [0-9]+ frames: [0-9.]+ms max=[0-9.]+ms backend=[a-z0-9]+ describes=[0-9]+ describe=[0-9.]+ms max_describe=[0-9.]+ms handle_changes=[0-9]+ binds=[0-9]+ bind=[0-9.]+ms max_bind=[0-9.]+ms$`, and there are at least 5;
          - at least 10 stats lines match `^mpv_kit_example: [0-9]+ dropped, avdiff=[^ ]+ hwdec=[^ ]+ dec-drop=[0-9]+$`;
          - api_ok=yes;
          - the smi CSV has at least 20 rows.
        - hwdec_ok and fg_start are recorded, not gated: a forced hwdec that falls back, or a window that does not come to the front, is reported in the checkpoint for the user.
        - A format mismatch is a defect of steps 3-4. STOP and report; do not amend commit 1.

    12. Checkpoint brief: write build/umq/checkpoint.txt (LF) with:
        - commit 1's sha;
        - the meas-build head and patch_sha256;
        - the two smoke run lines, shortened to combo, api_ok, hwdec_seen, fg_start, probe_lines, pickup_lines, render_med, describe_med, handle_change_ratio, bind_med;
        - sample.txt;
        - the run plan: order d3d11+d3d11va, vulkan+vulkan, vulkan+d3d11va-copy, d3d11+no; 135 s each plus a 60 s cool-down; about 15 minutes in all;
        - the conditions (AC, battery saver off, sleep and screen-off at never or above 30 min, Steam and other GPU programs closed, no input until the last run ends, ROOT D: free MiB).
        Then continue to Task 2.
  </action>
  <verify>
    <automated>Q=.planning/quick/261030-umq-renderer-probe-render-timing-and-pickup- && S=packages/mpv_kit_video/src && P=packages/mpv_kit_video/windows/mpv_kit_video_plugin.cpp && T=native/tests/video_renderer_swap_test.cc && R=example/build/windows/x64/runner/Release && C1=$(cat build/umq/commit1.sha) && git cat-file -e "$C1^{commit}" && for k in probe_render_ms_ probe_render_max_ms_; do grep -q "$k" $S/video_renderer.h || exit 1; done && grep -q 'max_render=' $S/video_renderer.cc && grep -q 'kMaxRenderKey' $T && grep -q 'kRenderKey' $T && for k in describes= max_describe= handle_changes= binds= max_bind= thread_local last_handle; do grep -q -- "$k" $P || exit 1; done && grep -q 'char line\[320\]' $P && file $P | grep -q 'with CRLF line terminators' && EP=$(git ls-files --eol -- $P) && printf '%s\n' "$EP" | grep -q 'i/crlf *w/crlf' && for f in $S/video_renderer.h $S/video_renderer.cc $T docs/ARCHITECTURE.md; do EF=$(git ls-files --eol -- $f) && printf '%s\n' "$EF" | grep -q 'i/lf *w/lf' || exit 1; done && OLD=$(git show "$C1^:$S/video_renderer.cc") && NEW=$(git show "$C1:$S/video_renderer.cc") && test "$(printf '%s\n' "$OLD" | grep -o 'api_\.[a-z_]*' | LC_ALL=C sort | uniq -c)" = "$(printf '%s\n' "$NEW" | grep -o 'api_\.[a-z_]*' | LC_ALL=C sort | uniq -c)" && for p in 'max_render=' 'BLOCK_FOR_TARGET_TIME' 'handle_changes=' 'max_bind=' 'external_texture_d3d.cc'; do grep -q -- "$p" docs/ARCHITECTURE.md || exit 1; done && sha256sum -c --quiet .planning/phases/17-fallback-hardening-uhd-regression/evidence/golden-freeze-17.sha256 && grep -qx 'red swap_test rc=1 failing=fifo-jitter,fifo-cap-drop-q2,fifo-cap-drop-q4,fifo-repeat' $Q/261030-umq-local-tests.log && grep -q '^integration real_plugin_test=pass d3d11_backend_test=pass' $Q/261030-umq-local-tests.log && test "$(grep -c '^ALL rc=0' $Q/261030-umq-local-tests.log)" -ge 2 && test "$(bash build/umq/tests/run_all.sh | tail -n 1 | tr -d '\r')" = 'ALL rc=0' && E=$(printf '%s\n' $S/video_renderer.h $S/video_renderer.cc $P $T docs/ARCHITECTURE.md $Q/261030-umq-PLAN.md $Q/261030-umq-local-tests.log | LC_ALL=C sort) && N1=$(git show --name-only --format= "$C1") && test "$(printf '%s\n' "$N1" | LC_ALL=C sort)" = "$E" && D1=$(git diff --name-only "$C1^" "$C1" -- '*.dart') && test -z "$D1" && test -z "$(git status --porcelain -- packages native docs example/lib pubspec.yaml)" && grep -q '^build rc=0' build/umq/meas-build.log && H=$(sed -n 's/^head=//p' build/umq/meas-build.log) && test -n "$H" && git diff --quiet "$C1" "$H" -- packages native example pubspec.yaml && grep -qx 'porcelain=\[\]' build/umq/meas-build.log && test -s $Q/261030-umq-measure.patch && git apply --check $Q/261030-umq-measure.patch && test "$(grep -a -c ' max_render=' $R/mpv_kit_video_plugin.dll)" -ge 1 && test "$(grep -a -c ' max_bind=' $R/mpv_kit_video_plugin.dll)" -ge 1 && test "$(grep -a -c 'MPV_KIT_EXAMPLE_HWDEC' $R/data/app.so)" -ge 1 && for t in smoke-d3d11-d3d11va smoke-vulkan-vulkan; do L=$(tr -d '\r' < build/umq/$t.log) && test "$(printf '%s\n' "$L" | grep -c 'render waits avg/over')" -ge 5 && ! printf '%s\n' "$L" | grep 'render waits avg/over' | grep -Evq 'render waits avg/over [0-9]+ frames: prev=[0-9.]+ms done=[0-9.]+ms max_done=[0-9.]+ms superseded=[0-9]+ repeated=[0-9]+ queued=[0-9]+ render=[0-9.]+ms max_render=[0-9.]+ms$' && test "$(printf '%s\n' "$L" | grep -c 'compositor pickup avg/over')" -ge 5 && ! printf '%s\n' "$L" | grep 'compositor pickup avg/over' | grep -Evq 'compositor pickup avg/over [0-9]+ frames: [0-9.]+ms max=[0-9.]+ms backend=[a-z0-9]+ describes=[0-9]+ describe=[0-9.]+ms max_describe=[0-9.]+ms handle_changes=[0-9]+ binds=[0-9]+ bind=[0-9.]+ms max_bind=[0-9.]+ms$' && test "$(printf '%s\n' "$L" | grep -Ec '^mpv_kit_example: [0-9]+ dropped, avdiff=[^ ]+ hwdec=[^ ]+ dec-drop=[0-9]+$')" -ge 10 && test "$(wc -l < build/umq/$t.smi.csv)" -ge 20 && grep -Eq "^run combo=[a-z0-9-]+\+[a-z0-9-]+ tag=$t .* api_ok=yes " build/umq/smoke.txt || exit 1; done && grep -q '^sample_selected path=' build/umq/sample.txt && test -s build/umq/checkpoint.txt && ! grep -h 'nvidia-smi' build/umq/*.sh | grep -Eq -e '(^|[[:space:]])(-lgc|-rgc|-lmc|-rmc|-ac|-rac|-pl|-pm|-c|-e|-r|--lock-gpu-clocks|--reset-gpu-clocks|--lock-memory-clocks|--reset-memory-clocks|--applications-clocks|--reset-applications-clocks|--power-limit|--persistence-mode|--compute-mode|--ecc-config|--gpu-reset)([[:space:]=]|$)'</automated>
    <baseline>Measured at HEAD a2c05d7 during planning:
- probe_render_ms_ and probe_render_max_ms_: 0 in the .h. ` max_render=` and ` render=`: 0 in the .cc. kRenderKey, kMaxRenderKey and max_render: 0 in swap_test.
- Plugin: describes=, max_describe=, handle_changes=, binds=, max_bind=, thread_local, last_handle and `char line[320]` are all 0. `file` reports CRLF line terminators and git reports i/crlf w/crlf.
- `api_.` occurs 10 times in video_renderer.cc. That equality gate passes before and after by design: it guards against new libmpv calls.
- ARCHITECTURE.md: max_render=, BLOCK_FOR_TARGET_TIME, handle_changes=, max_bind= and external_texture_d3d.cc are all 0.
- golden-freeze-17: OK.
- The local-tests log, the patch, build/umq (including commit1.sha) and the smoke logs are absent. The Release DLL has 0 ` max_render=`, and app.so has 0 `MPV_KIT_EXAMPLE_HWDEC`.
- Every positive gate fails at HEAD.</baseline>
    <fails_when>Any of these:
- a new member, field, constant or doc phrase is missing;
- the plugin line buffer is not 320 bytes;
- the plugin lost CRLF or another file lost LF;
- video_renderer.cc gained or lost a libmpv call;
- a frozen golden changed;
- the RED line differs from the four predicted scenarios;
- the integration tests did not pass, or fewer than two ALL rc=0 runs were logged;
- a fresh run_all.sh is not ALL rc=0;
- commit 1 holds anything but the seven paths, or a Dart file;
- example/lib or pubspec.yaml is dirty;
- the measurement build is not from HEAD, is dirty, or lacks the probe strings or the patch marker;
- any smoke probe or pickup line lacks the full new tail, or there are fewer than 5 of either;
- the stats lines lack hwdec=/dec-drop=;
- a smoke run is not api_ok=yes;
- sample.txt or checkpoint.txt is missing;
- a script calls an nvidia-smi option that changes GPU state.</fails_when>
  </verify>
  <acceptance_criteria>
    - The probe line ends with render=/max_render= after the unchanged fields, and the pickup line ends with the seven Describe fields after the unchanged ones. Both are proven in real Release smoke logs on the RTX 4060.
    - swap_test is RED in exactly four scenarios before the change and GREEN after. All local renderer tests pass twice. golden-freeze-17 is OK. real_plugin_test and d3d11_backend_test pass.
    - No behaviour change: no new libmpv call or lock, release ownership unchanged, no Dart change committed, example/lib and pubspec.yaml clean.
    - Commit 1 holds exactly seven paths. The measurement build, harness, sample selection and checkpoint brief are ready. Nothing is pushed.
  </acceptance_criteria>
  <done>Both probe lines carry the new timing fields end to end on real hardware, verified by a RED-then-GREEN native test, the unchanged golden set and the local integration tests. The code is committed, and the hwdec-forcing measurement build and harness are ready for the user's start.</done>
</task>

<task type="checkpoint:human-action" gate="blocking-human">
  <name>Task 2: User confirms the sample and conditions, then replies `start` (hands-off from then on)</name>
  <files>none</files>
  <action>Present the content of build/umq/checkpoint.txt with the instructions below, then stop and wait. Edit no file. The runs need the user away from the keyboard and the window in front, so this checkpoint is blocking even though workflow.human_verify_mode is end-of-phase.</action>
  <instructions>
    What Claude already did:
    - committed the probe fields (sha from the brief);
    - built the measurement Release (HEAD plus the temporary example patch: forced hwdec, optional loop, hwdec/dec-drop on the stats line; not committed);
    - smoke-tested d3d11+d3d11va and vulkan+vulkan (results in the brief);
    - searched this machine for a 3840x2160 59.94 fps H.264 file.

    None exists here. Generating one needs an H.264 encoder that this machine and the LGPL bundle do not have.

    The user chooses the sample:
    a. Best for comparison with the GTX 960M runs: copy the laptop's own 3840x2160 59.94 fps H.264 file (ideally 2.5 minutes or longer) into the repo folder build\umq\sample\ (the brief gives the full Windows path), then reply `start`.
    b. Reply `start` without copying: the fallback is used. It is Desktop\1145142.mp4, 3840x2160 at 60.000 fps, 36.9 s, looped, so each 2-minute run contains about three loop seeks. This is recorded as a deviation.
    c. Reply `start sample=<full path>` for another file.

    Before replying:
    - Connect AC power and turn battery saver off.
    - Set sleep and screen-off to never (or 30 minutes or more).
    - Close Steam and any game, video or browser tab using the GPU.
    - Then leave the machine untouched for about 15 minutes, until the executor reports the last run.

    The executor gates each run (unlocked desktop, AC, free disk space, no stray example, no other process at 10 % or more of a GPU engine). It never changes GPU clocks.
  </instructions>
  <verification>On resume, Task 3 re-runs build/umq/select_sample.sh (with the given path if there is one), checks the gate before each run, and records the reply verbatim in RESULTS.</verification>
  <resume-signal>`start`, or `start sample=<path>`. Any other reply means do not run: report back to the orchestrator.</resume-signal>
  <verify><automated>echo "blocking-human: no automated check; the user's reply starts Task 3"</automated></verify>
  <done>The user replied `start` (with or without a sample path) and is hands-off.</done>
</task>

<task type="auto">
  <name>Task 3: Four gated 135 s RTX 4060 runs with nvidia-smi, results and commit 2</name>
  <files>.planning/quick/261030-umq-renderer-probe-render-timing-and-pickup-/261030-umq-RESULTS.txt, .planning/quick/261030-umq-renderer-probe-render-timing-and-pickup-/261030-umq-measure.patch, .planning/quick/261030-umq-renderer-probe-render-timing-and-pickup-/runs/run-d3d11-d3d11va.log, .planning/quick/261030-umq-renderer-probe-render-timing-and-pickup-/runs/run-d3d11-d3d11va.smi.csv, .planning/quick/261030-umq-renderer-probe-render-timing-and-pickup-/runs/run-vulkan-vulkan.log, .planning/quick/261030-umq-renderer-probe-render-timing-and-pickup-/runs/run-vulkan-vulkan.smi.csv, .planning/quick/261030-umq-renderer-probe-render-timing-and-pickup-/runs/run-vulkan-d3d11va-copy.log, .planning/quick/261030-umq-renderer-probe-render-timing-and-pickup-/runs/run-vulkan-d3d11va-copy.smi.csv, .planning/quick/261030-umq-renderer-probe-render-timing-and-pickup-/runs/run-d3d11-no.log, .planning/quick/261030-umq-renderer-probe-render-timing-and-pickup-/runs/run-d3d11-no.smi.csv</files>
  <read_first>
    - build/umq/checkpoint.txt, build/umq/sample.txt, build/umq/smoke.txt, build/umq/meas-build.log
    - build/umq/run_combo.sh and build/umq/metrics.sh (written in Task 1)
    - .planning/quick/261029-rcc-fifo-depth-2-frame-queue-with-swap-at-pu/261029-rcc-AB.txt (record style)
  </read_first>
  <precondition>All of these hold:
- The user's reply starts with `start`.
- With C1 from build/umq/commit1.sha and H from the `head=` line of build/umq/meas-build.log: `git diff --quiet "$C1" HEAD -- packages native example pubspec.yaml` and `git diff --quiet "$C1" "$H" -- packages native example pubspec.yaml` both succeed. The product tree and the measurement build both equal commit 1, whatever docs commits other sessions added.
- `git status --porcelain -- packages native docs example/lib pubspec.yaml` is empty.
- The Release DLL contains ` max_bind=` and app.so contains `MPV_KIT_EXAMPLE_HWDEC`.
- No mpv_kit_example process is running.</precondition>
  <action>
    1. Pin the root.
       - Re-run `bash build/umq/select_sample.sh`, passing the path from the reply if one was given, and keep the new sample.txt.
       - Start a scratch results file build/umq/RESULTS.draft with these lines:
         - `reply="<user reply verbatim>"`;
         - host: GPU name and driver_version (`nvidia-smi --query-gpu=name,driver_version,clocks.max.gr,clocks.max.mem,enforced.power.limit --format=csv,noheader`), the current refresh rate (Win32_VideoController CurrentRefreshRate), power (build/nwm/power.ps1) and OS (uname);
         - build: head, patch_sha256, the libmpv-2.dll sha256 from build/phase17/libmpv-rtx/MANIFEST.txt and the flutter version line;
         - the sample_selected line.

    2. Runs, in this fixed order, one attempt each:
       `bash build/umq/run_combo.sh run-d3d11-d3d11va d3d11 d3d11va 135`,
       `bash build/umq/run_combo.sh run-vulkan-vulkan vulkan vulkan 135`,
       `bash build/umq/run_combo.sh run-vulkan-d3d11va-copy vulkan d3d11va-copy 135`,
       `bash build/umq/run_combo.sh run-d3d11-no d3d11 no 135`.

       After each run:
       - append its gate line and both metrics.sh lines to the draft;
       - then wait 60 s, except after the last run.

       Stop the remaining runs and return a checkpoint with the draft so far (never repeat or shorten a run) when any of these happens:
       - exit 3 (gate FAIL);
       - exit 4;
       - alive_at_end=no;
       - standby or forensics other than none;
       - fg_end is not mpv_kit_example.

       A run with api_ok=no or hwdec_ok=no is recorded as measured and the sequence continues. Note it in the findings: the combo did not take effect.

    3. Write the quick-dir file 261030-umq-RESULTS.txt (LF) from the draft. Sections, in order:
       - the header lines;
       - the four gate lines;
       - the four run lines;
       - the four smi lines;
       - a fixed-width table, one row per combo, with columns effective, drops, dec_drops, render_med, render_max, done_med, pickup_med, describe_med, handle_change_ratio, bind_med, bind_max, gr_mhz med, util_gpu med, util_dec med, temp max and event_reasons;
       - `notes:` lines (below);
       - `findings:` lines.

       The notes say how to read each field:
       - render= includes mpv's wait for the target time (BLOCK_FOR_TARGET_TIME default 1, vo_libmpv.c:425-431). It is an upper bound on render work and close to the frame period when the work finishes early. A max_render far above 16.7 ms marks a stall inside the render call.
       - describe= covers entry through AcquireFront.
       - A handle_change_ratio near 1 means Flutter's one-handle cache misses on nearly every frame.
       - bind= is Describe's return to the release callback: GL bind plus, on a handle change, eglReleaseTexImage, eglDestroySurface, eglCreatePbufferFromClientBuffer and eglBindTexImage (external_texture_d3d.cc:54-115, Flutter 3.47.8). It excludes the compositor's draw and ANGLE's internal synchronization, which the plugin still cannot time.
       - Effective drops = mpv frame-drop-count + superseded.
       - The sample deviation, if the fallback was used.
       - The window: 1280x720 default, untouched.
       - No clock locking was used; clocks are as the driver chose them, see the smi lines.
       - These are RTX 4060 numbers. The todo's decision host is the GTX 960M, so nothing here changes the D3D-08 decision on its own.

       The findings state only what the table shows: per metric, the highest and lowest combo; whether bind= is the same for d3d11 and vulkan (expected, since both hand out DXGI shared handles); how render= and dec_drops differ between d3d11+d3d11va and d3d11+no and between vulkan+vulkan and vulkan+d3d11va-copy. No causal claims beyond the table.

    4. Copy the four run logs and four smi CSVs, CR-stripped, to the quick-dir runs/ folder under the names in files_modified.

    5. Commit 2.
       - Pin the root.
       - Stage exactly the RESULTS file, the measure patch and the eight runs/ files.
       - Message, for example: `docs(quick-261030-umq): RTX 4060 render/Describe probe results for four backend+hwdec combos`.
       - Body: the per-combo effective drops, render_med, bind_med and handle_change_ratio; the sample used; that the example patch was measurement-only and is not in the tree; Co-Authored-By.
       - Commit with the explicit pathspec, then write the full sha to build/umq/commit2.sha. Do not push.

    6. Write the quick-dir 261030-umq-SUMMARY.md (not committed; the orchestrator handles quick-task docs). Include:
       - the table;
       - the RED/GREEN lines;
       - the integration result;
       - the sample provenance and any deviation;
       - the planner's addition beyond the request (the bind= release-callback bracket, with its engine source);
       - which combos took effect;
       - the follow-ups: the same probe on the GTX 960M; d3d11va-zero-copy=yes as a separate A/B; and that the engine's per-handle surface recreate could only be avoided by an engine-side cache or a stable handle, which is not planned.
  </action>
  <verify>
    <automated>Q=.planning/quick/261030-umq-renderer-probe-render-timing-and-pickup- && F=$Q/261030-umq-RESULTS.txt && C1=$(cat build/umq/commit1.sha) && C2=$(cat build/umq/commit2.sha) && git cat-file -e "$C2^{commit}" && git merge-base --is-ancestor "$C1" "$C2" && grep -q '^reply="start' $F && grep -q '^sample_selected path=' $F && for t in run-d3d11-d3d11va run-vulkan-vulkan run-vulkan-d3d11va-copy run-d3d11-no; do grep -q "^gate run=$t result=pass " $F || exit 1; done && for c in 'd3d11\+d3d11va' 'vulkan\+vulkan' 'vulkan\+d3d11va-copy' 'd3d11\+no'; do grep -Eq "^run combo=$c tag=run-[a-z0-9-]+ .* alive_at_end=yes .* standby=none forensics=none .* probe_lines=[0-9]+ pickup_lines=[0-9]+ .* render_med=[0-9.]+ render_max=[0-9.]+ .* handle_change_ratio=[0-9.]+ binds=[0-9]+ bind_med=[0-9.]+ bind_max=[0-9.]+ " $F || exit 1; grep -Eq "^smi combo=$c rows=(1[0-9][0-9]|[2-9][0-9][0-9]) " $F || exit 1; done && grep -q '^notes:' $F && grep -q '^findings:' $F && grep -q 'BLOCK_FOR_TARGET_TIME' $F && grep -q 'external_texture_d3d.cc' $F && for t in run-d3d11-d3d11va run-vulkan-vulkan run-vulkan-d3d11va-copy run-d3d11-no; do test -s $Q/runs/$t.log && test -s $Q/runs/$t.smi.csv || exit 1; done && E=$(printf '%s\n' $F $Q/261030-umq-measure.patch $Q/runs/run-d3d11-d3d11va.log $Q/runs/run-d3d11-d3d11va.smi.csv $Q/runs/run-vulkan-vulkan.log $Q/runs/run-vulkan-vulkan.smi.csv $Q/runs/run-vulkan-d3d11va-copy.log $Q/runs/run-vulkan-d3d11va-copy.smi.csv $Q/runs/run-d3d11-no.log $Q/runs/run-d3d11-no.smi.csv | LC_ALL=C sort) && N2=$(git show --name-only --format= "$C2") && test "$(printf '%s\n' "$N2" | LC_ALL=C sort)" = "$E" && for f in $E; do EF=$(git ls-files --eol -- "$f") && printf '%s\n' "$EF" | grep -q 'i/lf *w/lf' || exit 1; done && D2=$(git diff --name-only "$C2^" "$C2" -- '*.dart') && test -z "$D2" && git diff --quiet "$C1" HEAD -- packages native example pubspec.yaml && test -z "$(git status --porcelain -- packages native docs example/lib pubspec.yaml)" && TL=$(tasklist) && ! printf '%s\n' "$TL" | grep -qi mpv_kit_example && ! grep -h 'nvidia-smi' build/umq/*.sh | grep -Eq -e '(^|[[:space:]])(-lgc|-rgc|-lmc|-rmc|-ac|-rac|-pl|-pm|-c|-e|-r|--lock-gpu-clocks|--reset-gpu-clocks|--lock-memory-clocks|--reset-memory-clocks|--applications-clocks|--reset-applications-clocks|--power-limit|--persistence-mode|--compute-mode|--ecc-config|--gpu-reset)([[:space:]=]|$)'</automated>
    <baseline>After Task 1 and before this task, the RESULTS file, the runs/ folder and build/umq/commit2.sha do not exist, so the gate fails at its first checks.</baseline>
    <fails_when>Any of these:
- the reply or sample provenance is missing;
- a combo has no passing gate line, no complete run line (alive, no standby or forensics, the timing fields) or no smi line with at least 100 rows;
- notes or findings are missing, or lack the target-time and engine-source references;
- a raw log or CSV is missing, or is not LF in git;
- commit 2 holds anything but the ten paths;
- a Dart file was committed;
- the product tree is dirty;
- an example process is left running;
- a script calls an nvidia-smi option that changes GPU state.</fails_when>
  </verify>
  <acceptance_criteria>
    - Four gated, uninterrupted 135 s runs with the requested backend and hwdec combos. Combos that did not take effect are reported, not hidden.
    - Each run has 1 s nvidia-smi samples. No GPU state was changed.
    - RESULTS holds provenance, gate/run/smi lines, the table, the reading notes (including what remains unmeasurable) and table-only findings.
    - Commit 2 holds exactly ten paths. Nothing is pushed.
  </acceptance_criteria>
  <done>The RTX 4060 four-combo record with render=, describe=, handle-change and bind= numbers is committed locally in the quick dir, ready for the orchestrator to compare with a GTX 960M run.</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| render thread -> probe state | new timing sums written by the render thread |
| raster thread / engine release callback -> plugin probe state | thread_local stamps read and written around the engine's synchronous callback |
| plugin -> Flutter engine texture ownership | the descriptor's release_context and callback must keep exactly one Release of the same texture |
| user media file -> header parser and mpv decoders | the sample is parsed read-only (python -I) and decoded by the bundled FFmpeg |
| executor -> GPU driver state | nvidia-smi is used during the runs |
| temporary example patch and pubspec user_define -> committed tree | measurement-only edits must never be committed |
| hands-off session -> evidence validity | user input, standby or occlusion would invalidate runs |

## STRIDE Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation Plan |
|-----------|----------|-----------|----------|-------------|-----------------|
| T-261030umq-01 | Tampering | Describe release callback (texture refcount) | high | mitigate | release_context stays the COM texture and the single Release is unchanged. The callback only writes thread_locals and never dereferences an Instance (owners compared as const void*). real_plugin_test and d3d11_backend_test run with asserts on; the smoke runs exercise both backends. |
| T-261030umq-02 | Denial of Service | renderer timing (lock or libmpv change) | high | mitigate | The `api_.` count equality gate, no new lock, sums only in the pipelined block. swap_test, affinity and bind tests are green under MSVC asserts. |
| T-261030umq-03 | Tampering | frozen golden set | high | mitigate | `sha256sum -c` of golden-freeze-17 in Task 1, and the commit file-list gate excludes native/tests/golden and the harness. |
| T-261030umq-04 | Tampering | pickup line buffer overflow or truncation | medium | mitigate | `char line[320]` gate. snprintf is bounded, and the smoke regex requires the full tail on every pickup line. |
| T-261030umq-05 | Tampering | GPU driver state | high | mitigate | Only `--query-gpu` reads. A negative gate over every nvidia-smi line in build/umq scripts covers the setter flags. Clock locking is not authorized by the user. |
| T-261030umq-06 | Tampering | temporary example patch / pubspec | medium | mitigate | Applied only inside relbuild.sh with trap restores. Porcelain gates on example/lib and pubspec.yaml, no Dart file in either commit, and the patch stored in the quick dir for reproducibility. |
| T-261030umq-07 | Information Disclosure / Tampering | media sample parsing | low | mitigate | Read-only header parse with `python -I`, the file never copied, moved or modified by the executor, and nothing downloaded. |
| T-261030umq-08 | Repudiation | run validity | medium | mitigate | A gate line per run, fg_start/fg_end, alive_at_end, standby/forensics queries, the verbatim user reply, raw logs and CSVs committed, and no reruns or shortening. |
| T-261030umq-09 | Denial of Service | thermal or power state during runs | low | accept | Clocks and event reasons are logged per second and reported. No locking by decision; the 60 s cool-down is recorded. |
| T-261030umq-SC | Tampering | npm/pip/cargo installs | high | mitigate | No package installs or downloads. Builds use the pinned workspace pub dependencies and the local MANIFEST-checked bundle. |
</threat_model>

<source_audit>
| Source item | Covered by |
|---|---|
| (1) time render_backend_->Render per frame, avg render= and max_render= appended at the end of the probe line, log only, existing fields and order kept | Task 1 steps 2-3, 6; swap_test tail check; smoke regex |
| (2) time Describe per call and whether the shared handle changed; add to the pickup log, log only | Task 1 step 4; smoke regex. bind= is an addition from the verified engine source, flagged in the SUMMARY. |
| (3) build and run 2-minute 4K59.94 H.264 runs for the four combos, example in front, hands-off, nvidia-smi alongside, no clock locking, results in the quick dir | Task 1 steps 9-12 (build, harness, smoke); Task 2 (start); Task 3 (runs, RESULTS) |
| No 4K59.94 H.264 sample on the host: plan how to get one and say so | context (planning probe), Task 1 step 10 (select_sample.sh), Task 2 options a/b/c |
| No Dart API change, no behaviour change | measurement patch never committed; Dart and porcelain gates; `api_.` equality; RBE-05 prohibition |
| Goldens stay green (golden-freeze-17) | Task 1 steps 2, 6; sha gate; commit list |
| Protected user files untouched; commit by explicit path; no push | executor_rules; commit list gates in Tasks 1 and 3 |
| Blocking human-action checkpoint before the runs (`start`) | Task 2 |
| Engine handle cache facts: say what the plugin can and cannot time | context; ARCHITECTURE edit; RESULTS notes |
| Deferred / out of scope: d3d11va-zero-copy A/B, GTX 960M rerun, D3D-08 switch, CI push | named as follow-ups only (Task 3 step 6) |
</source_audit>

<verification>
- Task 1:
  - Both probe lines carry the new tails in real Release logs, with the existing fields unchanged.
  - swap_test is RED in exactly four scenarios, then GREEN.
  - The native suite is ALL rc=0 twice plus a fresh run, and golden-freeze-17 is OK.
  - Both integration tests pass.
  - Commit 1 holds exactly seven paths, and the tree is clean.
  - The measurement build is from HEAD with the patch marker.
  - The harness smoke passes for d3d11+d3d11va and vulkan+vulkan.
- Task 2: the user's `start`.
- Task 3: four gated, uninterrupted runs with smi rows; RESULTS complete; commit 2 holds exactly ten paths.
- CI only (not run here; listed as pending in the SUMMARY; the orchestrator decides about pushing): the meson build and run of swap_test on Linux, macOS and Windows MSYS2 (warning_level=3, -Werror), and the ASan/UBSan job. The Windows plugin change compiles locally under the Flutter MSVC build; Linux and macOS plugins are untouched.
- Nothing is pushed.
</verification>

<success_criteria>
- mpv's render call time and the compositor's Describe and per-handle engine update time are visible on the existing 120-frame log lines, with no behaviour change and the golden set unchanged.
- The four backend+hwdec combos on the RTX 4060 are measured under gated, hands-off conditions with GPU clocks logged and never locked. The results are recorded in the quick dir, ready to pair with a GTX 960M run.
</success_criteria>

<output>
Create `.planning/quick/261030-umq-renderer-probe-render-timing-and-pickup-/261030-umq-SUMMARY.md` when done (not committed; the orchestrator handles quick-task docs), with the content listed in Task 3 step 6.
</output>

---
phase: quick-261029-nwm
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - packages/mpv_kit_video/src/video_renderer.h
  - packages/mpv_kit_video/src/video_renderer.cc
  - native/tests/video_renderer_swap_test.cc
  - native/tests/meson.build
  - native/tests/video_renderer_affinity_test.cc
  - native/tests/video_renderer_bind_test.cc
  - native/tests/video_renderer_golden_vk_fallback.cc
  - native/tests/video_renderer_golden_vk_retire_twice.cc
  - native/tests/video_renderer_golden_sw_retire_twice.cc
  - docs/ARCHITECTURE.md
  - docs/perf/d3d11-backend.md
  - example/windows/runner/main.cpp
  - packages/mpv_kit_video/windows/d3d11_interop.cpp
  - packages/mpv_kit_video/README.md
  - .planning/phases/14-windows-native-d3d11-backend/evidence/laptop-package.txt
autonomous: false
requirements: [RBE-05, D3D-06]

estimate:
  tokens: 225000
  raw_tokens: 225000
  tasks: 3
  confidence: low

must_haves:
  truths:
    - "Every frame VideoRenderer publishes gets its mpv_render_context_report_swap on the render thread right after the publish and before Interop::FrameReady (D-05 order: this fix ships first); no swap waits for the compositor's AcquireFront and no 50 ms present-timeout path remains; RBE-05 holds (affinity_test and bind_test green, debug asserts on)."
    - "The existing 120-frame probe line ends with ` superseded=<n>`: published frames replaced before the compositor took them (hidden drops mpv does not count). No public API, Dart or reason-string change."
    - "On the RTX 4060 (4K60 lavfi with audio, ao=null, auto and MPV_KIT_VIDEO_API=d3d11, 150 s each, before and after), effective drops (mpv frame-drop-count delta + superseded) are not worse in any run (at most +2) and at least halved with at least 5 fewer in one run; avsync within 10x; no new render errors. Recorded in 261029-nwm-AB.txt (`ab_gate=PASS`) and docs/perf/d3d11-backend.md."
    - "All renderer native tests meson builds on Windows pass locally under MSVC /W4 /WX with asserts on, including the new video_renderer_swap_test, which failed on the pre-fix code (RED recorded); the frozen golden set is byte-unchanged (golden-freeze-14.sha256 OK)."
    - "The example runner picks HighPerformancePreference only when GetSystemPowerStatus reports AC online and battery saver off, otherwise NoPreference. It decides once at startup and writes one `mpv_kit_example: GPU preference ...` line (D-04). The Windows candidate chain stays Vulkan-first (D-01)."
    - "The plugin writes one `mpv_kit: hybrid GPU hint: ...` line when Flutter's compositor adapter looks integrated (non-Microsoft, under 512 MiB dedicated) while another hardware, non-Microsoft adapter with at least 512 MiB exists. It only logs and changes no reason (D-03)."
    - "README and docs/perf carry the power-aware runner snippet, the hint line and the optional low-cost config (linear-downscaling=no, cscale=bilinear, d3d11va-zero-copy=yes with the padding caveat) for weak or integrated GPUs. No default changes (D-02)."
    - "package3 sits on the desktop, verified on this host and traceable; its `## package3` provenance is committed alone; the user has run it on the laptop on AC and on battery and replied."
  artifacts:
    - path: "packages/mpv_kit_video/src/video_renderer.cc"
      provides: "swap reported at publish; superseded counter in the probe line"
      contains: "superseded="
    - path: "native/tests/video_renderer_swap_test.cc"
      provides: "regression test: swap reported at publish (software + fake pipelined backend), superseded probe count"
      contains: "SWAP ok scenarios="
    - path: "native/tests/meson.build"
      provides: "video_renderer_swap_test on every CI platform and under the sanitizers"
      contains: "video_renderer_swap_test"
    - path: "docs/ARCHITECTURE.md"
      provides: "new swap reporting contract"
      contains: "reported when it is published"
    - path: "docs/perf/d3d11-backend.md"
      provides: "A/B numbers; hybrid/power/low-cost notes"
      contains: "## Swap reporting at publish (261029-nwm)"
    - path: "example/windows/runner/main.cpp"
      provides: "power-aware GPU preference + decision log"
      contains: "GetSystemPowerStatus"
    - path: "packages/mpv_kit_video/windows/d3d11_interop.cpp"
      provides: "hybrid GPU hint log line"
      contains: "mpv_kit: hybrid GPU hint: "
    - path: ".planning/phases/14-windows-native-d3d11-backend/evidence/laptop-package.txt"
      provides: "package3 provenance"
      contains: "## package3"
  key_links:
    - from: "VideoRenderer::RenderOnce publish block (front_ = back under mutex_)"
      to: "vo_libmpv flip_page wait on flip_count (native/mpv/video/out/vo_libmpv.c:526-563)"
      via: "ReportSwaps(1) -> api_.render_context_report_swap, before interop_->FrameReady()"
      pattern: "ReportSwaps\\(1\\)"
    - from: "VideoRenderer::AcquireFront (raster thread, under mutex_)"
      to: "probe line ` superseded=<n>` (RenderOnce, render thread)"
      via: "front_acquired_ flag, checked and reset at the next publish"
      pattern: "front_acquired_"
    - from: "example/windows/runner/main.cpp GetSystemPowerStatus"
      to: "D3D11Interop constructor (adapter line + hybrid hint)"
      via: "project.set_gpu_preference -> engine adapter -> registrar GetView()->GetGraphicsAdapter()"
      pattern: "set_gpu_preference"
    - from: "package3 run-auto-log.bat / run-d3d11.bat"
      to: "%USERPROFILE%\\Desktop\\mpv_kit_<auto|d3d11>_log_<N>.txt (new number per run)"
      via: "stdout+stderr redirection of mpv_kit_example.exe"
      pattern: "mpv_kit_auto_log_"
  prohibitions:
    - requirement_id: RBE-05
      category: scope
      status: unresolved
      verification: null
      statement: "MUST NOT call any mpv_render_* function from AcquireFront or any thread but the render thread; MUST NOT change the public VideoRenderer surface, any Dart file, the reason grammar or kWindowsApiOrder; MUST NOT edit the frozen golden files listed in golden-freeze-14.sha256."
    - requirement_id: D3D-06
      category: process
      status: unresolved
      verification: null
      statement: "MUST NOT commit the temporary libmpv_bundle hooks user_define in the root pubspec.yaml, MUST NOT push, and MUST NOT stage or modify .planning/config.json, .planning/state.json, .planning/tmp/, .planning/ui-reviews/, .planning/debug/ or engine_repo_embedder.cc."
---

<objective>
Fix render-side frame drops by reporting mpv's swap when a frame is published instead of when the compositor picks it up, proven by an A/B run on this RTX 4060 host. Then make the example runner choose its GPU by power state, add a log-only hybrid-GPU hint to the plugin, document an optional low-cost mpv config, and ship laptop demo package3.

Root cause (verified in native/mpv, see 261029-nwm-RESEARCH.md): under video-sync=audio, vo_libmpv's `flip_page` waits until `flip_count` reaches `expected_flip_count`, which only our `mpv_render_context_report_swap` advances (vo_libmpv.c:526-563). Only then does the core queue the next frame (vo.c:837-862), and a frame is dropped when `end_time < now` (vo.c:956). The render API gives mpv no presentation timing: there is no get_vsync, and vo.c:1024-1030 uses `now`, so report_swap's only effect is to unblock the VO thread. e9ca28f moved report_swap to compositor pickup, so each frame's VO cycle became render + GPU-done wait + pickup latency (about 8 ms). On the GTX 960M laptop (package2, 824a69e) that meant drops of 2.5-6% (auto, vulkan gpu-next) and 25-34% (forced d3d11, done 8 -> 15-17 ms).

Purpose: give mpv its whole frame budget back on slower GPUs without moving any libmpv call off the render thread (RBE-05), with an honest count of frames that are rendered but never shown.
Output: one fix commit (code + tests + docs), one feature commit (runner, hint, docs), one evidence commit (`## package3`), package3 on the desktop, and the user's laptop reply.
</objective>

<execution_context>
@~/.claude/gsd-core/workflows/execute-plan.md
@~/.claude/gsd-core/templates/summary.md
</execution_context>

<context>
@.planning/STATE.md
@.claude/CLAUDE.md
@.planning/quick/261029-nwm-report-swap-at-publish-power-aware-gpu-p/261029-nwm-RESEARCH.md
@packages/mpv_kit_video/src/video_renderer.h
@packages/mpv_kit_video/src/video_renderer.cc
@docs/ARCHITECTURE.md
@.planning/quick/261029-ljp-hybrid-gpu-high-performance-adapter-for-/261029-ljp-PLAN.md

Interfaces and facts the executor needs. The planner read these already; do not re-derive them.
- video_renderer.h: AcquireFront doc at 119-124 (its last two lines describe swap counting); ReportSwaps at 146-147 (stays); swap members at 175-182 (to remove); last_acquire_ at 183-186 (stays, used by idle detection at video_renderer.cc:630-632; its comment talks about deferring swaps and must be rewritten); probe members at 206-214.
- video_renderer.cc: AcquireFront 469-519 (the swap counting at 471-479, the notify at 517); RenderLoop 554-668 (ready predicate 567-570, deadline and timeout branch 571-591, swap hand-off and the "woken only to report swaps" branch 593-605, ReportSwaps(swaps) at 612, "Swaps not yet reported are dropped" at 661); SkipFrame 702-714 (reports 1 swap, stays); the failure paths at 814 and 847 (report 1 swap, stay); probe log 832-844; publish block 853-871.
- Pre-e9ca28f behaviour (`git show e9ca28f -- packages/mpv_kit_video/src/video_renderer.cc`): report_swap right after render, once per frame. The fix restores "once per frame, at once" but after the publish gate, on the render thread.
- Who uses the swap machinery: only video_renderer.{h,cc}. Comments mentioning it: native/tests/video_renderer_affinity_test.cc:63-65, video_renderer_bind_test.cc:75-76, and the `kPastPresentTimeout` comment at video_renderer_golden_vk_fallback.cc:43, video_renderer_golden_vk_retire_twice.cc:45 and video_renderer_golden_sw_retire_twice.cc:41. Frozen, NOT edited: renderer_harness.h, video_renderer_golden_sw.cc, video_renderer_golden_vk.cc, golden/sw.txt, golden/vk.txt (.planning/phases/14-windows-native-d3d11-backend/evidence/golden-freeze-14.sha256). Golden traces never contain swap calls (ReportSwap only bumps counters): `quiesce ... swaps=<n>` with swaps == renders is the only swap assertion and still holds.
- Harness API (native/tests/renderer_harness.h): `golden::Fake()` (Reset, QueueFrames(n), Poke() -> seq, WaitPokeSeen(seq), counters() -> {renders, skips, swaps, ...}, DrainAsync, Note), `golden::MakeApi()`, `golden::FakeHandle()`, `golden::FakeInterop(latency, bgra, interop_reason)` (frame_ready(), WaitFrameReady(n), virtual BackendCandidates / CreateBackend inherited from mpv_kit::Interop), `golden::CheckSwapInvariant()`. Patterns to copy: renderer + log capture at video_renderer_sw_hold_front_test.cc:195-215, scenario table and main at 389-454; pipelined fake backend `FakeGpuBackend` at video_renderer_chain_test.cc:81-183 and its Interop at 187-205 (FakeMpv::Create accepts any API type string). meson template: native/tests/meson.build:140-153 (sw_hold_front_test). Project defaults: warning_level=3, werror=true (gcc/clang on CI, sanitizers on Linux), so the new test must be -Wall -Wextra -Wpedantic clean.
- Windows plugin pickup log (packages/mpv_kit_video/windows/mpv_kit_video_plugin.cpp:314-326): `mpv_kit: compositor pickup avg/over 120 frames: <avg>ms max=<max>ms backend=<wire>`. Example stat line each second (example/lib/main.dart:89-90): `mpv_kit_example: <N> dropped, avdiff=<avsync|null>` (N is mpv frame-drop-count, cumulative). Startup line: `mpv_kit_video: <backend> (<reason>)`. Forced runs log `mpv_kit: MPV_KIT_VIDEO_API=d3d11 restricts rendering to that API`. Example env: `MPV_KIT_EXAMPLE_AO=null` sets ao=null.
- This host: Windows MINGW64 Git Bash, `/d/flutter/bin/flutter` (3.47.8), MSVC vcvars at `/d/vs community/VC/Auxiliary/Build/vcvars64.bat` (POSIX form; in cmd `D:\vs community\VC\Auxiliary\Build\vcvars64.bat`; cl 14.44), NVIDIA GeForce RTX 4060 Laptop GPU at 165 Hz, on AC (PowerOnline True). Its only hardware adapter is the RTX 4060 (probe_host lines in laptop-package.txt `## package2`: NVIDIA 7956 MiB, plus the Microsoft Basic Render Driver), so the hybrid hint cannot fire here. No meson or ffmpeg locally. Disk: D: about 6 GB, C: about 2.8 GB free. Prior local MSVC golden runs: .planning/phases/14-windows-native-d3d11-backend/evidence/local-14-02-goldens.log (cl /W4 /WX, all OK).
- Earlier 4K60 lavfi smokes on this host (build/phase14/ljp-smoke-*.log, no audio, about 45 s): auto 2 dropped, d3d11 5 dropped; done about 0.4-2.2 ms, pickup avg 6-10 ms with max about 21-24 ms. So the baseline has a small but measurable drop rate.
- Release build and bundle procedure (from 261029-ljp, reuse it as is): append the temporary block `hooks:` / `  user_defines:` / `    mpv_kit_libs:` / `      libmpv_bundle: build/phase14/libmpv-rtx` to the root pubspec.yaml, run `cd example && /d/flutter/bin/flutter build windows --release`, then `git checkout -- pubspec.yaml` whatever the exit status, and check that `git status --porcelain pubspec.yaml` is empty. The Release dir is example/build/windows/x64/runner/Release. Debug integration tests use the same user_define plus env `LIB="$PWD/build/phase14/libmpv-rtx/lib"`, `MPV_KIT_LIBMPV_PATH="$LIB/libmpv-2.dll"`, `MPV_KIT_REQUIRE_LIBMPV=1`, `PATH="$LIB:$PATH"` (docs/perf/d3d11-backend.md Reproduce).
- Plugin and runner compile flags: /W4 /WX (example/windows/CMakeLists.txt:42; plugin CMake, /utf-8). All files in files_modified are LF (`git ls-files --eol`); keep them LF.
- Package procedure: 261029-ljp-PLAN.md Task 2 and its package_spec; laptop-package.txt `## package2` (line 132 onward) for key names and line formats. The package2 desktop folder `mpv_kit_d3d11_demo_824a69e` is NOT on the desktop any more (checked during planning), so the package-1 run-probe.bat (sha 3b1efa2b...) is gone and gets recreated (package_spec). build/phase14/pkg2-src/ holds the package2 launcher and 使用说明 sources (LF, no BOM). Probe exe: build/phase14/laptop-probe-obj/d3d11_caps_probe.exe, sha256 d85cd7f33c80c809228ff7c15387611e5477331459c25ab1e48699b6b2a2a042. VC++ runtime: `/d/vs community/VC/Redist/MSVC/14.44.35112/x64/Microsoft.VC143.CRT/`. ANGLE audit: `python -I tools/rea_abi_audit/pe_audit.py <dll> --forbid-angle`.
</context>

<locked_decisions>
From the orchestrator (user decisions, this session). Cited as D-NN.
- D-01: The Windows candidate chain stays Vulkan-first. `kWindowsApiOrder` in packages/mpv_kit_video/windows/d3d11_interop.cpp is not touched (the 14-11 switch is not part of this task).
- D-02: No automatic quality downgrade. Docs only, with a recommended optional low-cost config for weak or integrated GPUs: `linear-downscaling=no`, `cscale=bilinear`, and for d3d11 `d3d11va-zero-copy=yes` with its padding caveat.
- D-03: Hybrid-GPU hint, log-only. When the compositor (Flutter) adapter is integrated and another hardware, non-software adapter exists, write one `mpv_kit:`-style line to stderr and DebugView that tells app authors to set the GPU preference in their runner. Detect via DXGI enumeration (DXGI_ADAPTER_DESC1 flags, software adapters excluded); "integrated" = DedicatedVideoMemory below 512 MiB; document the heuristic. The renderer reason is not changed.
- D-04: Power-aware GPU preference in example/windows/runner/main.cpp. If GetSystemPowerStatus reports ACLineStatus==1 and SystemStatusFlag bit 0 clear, use `HighPerformancePreference`; otherwise (battery, saver, unknown, or the call fails) use `NoPreference`, which respects Windows' per-app graphics settings. Decide once at startup, log the decision, and mirror the snippet in README/docs.
- D-05: Order: the swap fix first (A/B on the RTX 4060, gate must pass), then package3 for the laptop.
</locked_decisions>

<executor_rules>
- Run `source /tmp/gsd-bak/root_pin.sh` (PINNED_ROOT='D:/mpv_kit') before the first Edit/Write and before every commit.
- Protected user files are never staged or modified: .planning/config.json, .planning/state.json, .planning/tmp/, .planning/ui-reviews/, .planning/debug/, engine_repo_embedder.cc. Around any gsd-tools call: `cp .planning/state.json /tmp/nwm_state.bak` before, `cmp` after, and restore from the backup if it changed. Stage by explicit path only.
- Sequential execution on the main tree. Commit locally only, never push. Every commit message ends with `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.
- Scratch files (logs, scripts, screenshots, patches, test binaries) go under build/nwm/ or build/nwm-tests/ (build/ is gitignored), or under /tmp. Evidence for the orchestrator goes into the quick directory: 261029-nwm-AB.txt and 261029-nwm-native-tests.log (not committed by the executor).
- C++ comments are in English and match the density of the surrounding code. A new comment never names the removed swap members or the removed timeout; describe the behaviour instead.
- Before every interactive run, make sure no mpv_kit_example.exe is running (`tasklist | grep -i mpv_kit_example` is empty). During A/B runs leave the window visible and untouched: no moving, resizing or minimising, and no other GPU load.
</executor_rules>

<package_spec>
Package3 files written by Task 2 (ASCII, CRLF, no BOM for the .bat files).

run-probe.bat. Recreated: the package-1 original is no longer available, so its new sha256 is recorded.

```bat
@echo off
rem mpv_kit D3D11 capability probe (read-only). Output goes to a desktop text file.
set OUT=%USERPROFILE%\Desktop\mpv_kit_d3d11_probe.txt
"%~dp0d3d11_caps_probe.exe" --host gtx960-laptop > "%OUT%" 2>&1
echo Done. Output saved: %OUT%
pause
```

run-auto-log.bat. Every run writes a new numbered log, so the AC and battery runs never overwrite each other.

```bat
@echo off
rem mpv_kit demo, auto backend chain. stdout+stderr go to a new numbered desktop log file.
set MPV_KIT_VIDEO_API=
set N=1
:next
if exist "%USERPROFILE%\Desktop\mpv_kit_auto_log_%N%.txt" (
  set /a N+=1
  goto next
)
set LOG=%USERPROFILE%\Desktop\mpv_kit_auto_log_%N%.txt
cd /d "%~dp0demo"
echo Logging to %LOG%
echo Close the demo window when done. Do not close this console window.
"%~dp0demo\mpv_kit_example.exe" %* > "%LOG%" 2>&1
echo Log saved: %LOG%
pause
```

run-d3d11.bat: the same file with the comment `forced d3d11 backend`, `set MPV_KIT_VIDEO_API=d3d11` and the name `mpv_kit_d3d11_log_%N%.txt` in both places.

使用说明.txt (Chinese, UTF-8 with BOM, CRLF). Use build/phase14/pkg2-src/使用说明.txt as the base and keep its structure and tone. Required content, in order:
1. Title `mpv_kit D3D11 演示包 使用说明（版本 <feat 短 SHA>，package3）`.
2. 目的: package2 (824a69e) result on this laptop. The in-program preference moved Flutter to the GTX 960M, but frames still dropped: auto (vulkan gpu-next) about 2.5-6%, forced d3d11 25-34%. This version (a) reports each frame to mpv as soon as it is rendered, which should reduce drops caused by waiting on the screen; (b) chooses the GPU by power state at startup: on AC with battery saver off it asks for the high-performance GPU, on battery or with battery saver on it lets Windows decide (Windows 显示卡 settings apply); (c) writes a hint line when Flutter is on the integrated GPU while a discrete one exists. The logs also carry a new `superseded=` count, which needs no action.
3. 本目录内容: demo\, d3d11_caps_probe.exe, run-probe.bat, run-auto-log.bat (auto, writes 桌面 mpv_kit_auto_log_<编号>.txt), run-d3d11.bat (forced d3d11, writes 桌面 mpv_kit_d3d11_log_<编号>.txt), 使用说明.txt. Each run creates a new number (_1, _2, ...); before starting, move any old mpv_kit_*_log_*.txt off the desktop.
4. Step 0: leave the Windows 显示卡 setting and the NVIDIA 控制面板 program setting for mpv_kit_example.exe at their defaults (让 Windows 决定 / 使用全局设置), as reset for package2; note what they are.
5. Copy the folder; run run-probe.bat in the same boot session (LUIDs change after a reboot).
6. On AC power (charger connected, battery saver off): run-auto-log.bat, then run-d3d11.bat. In each run drag the 3840x2160 59.94 fps H.264 file into the window, open the HUD with F9, keep the window visible, no seeking, no other window operations, play at least 2 minutes, and note the actual duration. Record backend, reason (full), dropped, dec-drop, avsync, hwdec and fps (a screenshot is fine), close the demo with X, and press a key in the console.
7. On battery (charger unplugged; battery saver off unless the user wants to try it too, and if so say so): the same two runs, at least 2 minutes each.
8. In every log, report three lines: the one starting `mpv_kit_example: GPU preference` (expected: AC -> high-performance, battery -> none), `mpv_kit: compositor adapter`, and `mpv_kit: hybrid GPU hint:` if it is there (it may appear on battery when Windows puts Flutter on the HD 530).
9. 注意: the HUD backend label shows vulkan during d3d11 runs (known label issue); judge by the reason prefix.
10. 请回复: for each of the 4 runs, the power state (AC/battery, battery saver on/off), duration, reason (full), dropped, dec-drop, avsync, hwdec, fps and the three lines (or "none"); attach every mpv_kit_auto_log_*.txt, mpv_kit_d3d11_log_*.txt and mpv_kit_d3d11_probe.txt.
11. 其他说明 as in package2: unsigned dev build (SmartScreen: 仍要运行), VC++ runtime included, 64-bit Windows 10+.
</package_spec>

<!-- planner-discipline-allow: swap_pending_ -->
<!-- planner-discipline-allow: swaps_to_report_ -->
<!-- planner-discipline-allow: kPresentTimeout -->
<!-- planner-discipline-allow: swap_pending_|swaps_to_report_|kPresentTimeout -->

<tasks>

<task type="tracer" tdd="true">
  <name>Task 1: Swap at publish. Instrument (superseded), RED test, baseline, fix, GREEN, A/B on the RTX 4060, docs, one commit</name>
  <files>packages/mpv_kit_video/src/video_renderer.h, packages/mpv_kit_video/src/video_renderer.cc, native/tests/video_renderer_swap_test.cc, native/tests/meson.build, native/tests/video_renderer_affinity_test.cc, native/tests/video_renderer_bind_test.cc, native/tests/video_renderer_golden_vk_fallback.cc, native/tests/video_renderer_golden_vk_retire_twice.cc, native/tests/video_renderer_golden_sw_retire_twice.cc, docs/ARCHITECTURE.md, docs/perf/d3d11-backend.md</files>
  <read_first>
    - packages/mpv_kit_video/src/video_renderer.h and video_renderer.cc (whole files; line map in context)
    - native/tests/video_renderer_sw_hold_front_test.cc lines 1-30, 195-300, 389-454
    - native/tests/video_renderer_chain_test.cc lines 1-30, 78-215
    - native/tests/renderer_harness.h lines 300-386, 444-531, 735-835, 1092-1100
    - native/tests/meson.build (whole file, 300 lines)
    - docs/ARCHITECTURE.md lines 50-105
    - docs/perf/d3d11-backend.md lines 1-110
  </read_first>
  <precondition>HEAD is 0bf0bb6 or a descendant, and `git status --porcelain -- packages native docs example pubspec.yaml` is empty; `cd build/phase14/libmpv-rtx && sha256sum -c --quiet MANIFEST.txt` reports no failure; `df -P .` shows at least 1.5 GB available; `test -f "/d/vs community/VC/Auxiliary/Build/vcvars64.bat"` succeeds.</precondition>
  <behavior>
    - swap-at-publish-sw: software renderer, a frame is shown and acquired once (so the compositor counts as active); then 20 times: AcquireFront, queue one frame, wait for its FrameReady, and read the fake counters at once with no barrier. swaps == renders every time. On the pre-fix code it fails at the first iteration (that frame's swap is still pending).
    - swap-at-publish-gpu: the same through a fake pipelined backend (publish gate path), with the same expectation and the same RED.
    - superseded-alternate: fake pipelined backend; frame 1 acquired, then frames 2..120 with an AcquireFront only after odd frames. The single `render waits avg/over 120 frames` log line ends with `superseded=59` (publishes 3, 5, ..., 119 each replace an unacquired frame; the line is written in frame 120's render before its publish). skips == 0 and, after a Sync barrier, swaps == renders.
    - superseded-none: the same with an AcquireFront after every frame: `superseded=0`.
  </behavior>
  <action>
    Implements D-05 (fix first, gate before anything ships). Keep the diff minimal; RBE-05 render-thread affinity stays.

    1. `source /tmp/gsd-bak/root_pin.sh`. Create build/nwm/ and build/nwm-tests/.

    2. Instrumentation (log-only; it goes into the baseline build too). In video_renderer.h, next to the probe members (206-214), add `int probe_superseded_ = 0;` with a comment: published frames replaced before the compositor took them, which mpv does not count as drops; written at publish under mutex_, read and reset by the render thread only. Next to the ring state, add `bool front_acquired_ = false;` (guarded by mutex_; the compositor has taken the current front_). In AcquireFront, under the lock, set front_acquired_ = true when front_ >= 0. In the RenderOnce publish block, under the lock and before `front_ = back`: if front_ >= 0 and !front_acquired_, increment probe_superseded_; after the assignment set front_acquired_ = false. Do not count in the resize block (line 744 path): the old front becomes the retired front, which AcquireFront may still show, so it is not superseded. Append ` superseded=<probe_superseded_>` (std::to_string) at the end of the probe log line (835-839) and reset the counter with the others (840-843). Comment the counter's meaning in one line. Note: frames published in the up to 500 ms before the renderer goes idle (hidden window) also count; that is real.

    3. RED test (tdd). Create native/tests/video_renderer_swap_test.cc in the style of video_renderer_sw_hold_front_test.cc. Header block comment: what it proves (each frame's swap is reported when the frame is published, before FrameReady, so vo_libmpv's flip_page never waits on the compositor; the probe line's superseded count), how it runs (fake libmpv of renderer_harness.h, software backend plus a fake pipelined backend modelled on chain_test's FakeGpuBackend behind Interop::CreateBackend, no GPU, no libmpv), why it is a separate binary (the golden set is frozen), and the output contract `SWAP ok scenarios=<n>` with exit codes 0 pass, 1 failure. Implement the four scenarios in the behavior block (names swap-at-publish-sw, swap-at-publish-gpu, superseded-alternate, superseded-none). The pipelined fake: wire_name "fakegpu", frame_kind kVulkan, pipelined true, Create passes `MPV_RENDER_PARAM_API_TYPE` "fakegpu" and the renderer to the fake mpv, CPU buffers per slot, FrameFor returns the slot buffer as platform, Render uses the fake's SW params, Wait returns kOk. Its Interop is a golden::FakeInterop(2, false, nullptr) subclass whose BackendCandidates returns only {"fakegpu", "gpu-next"} and whose CreateBackend("fakegpu") returns the fake. Capture log lines through the LogFn and parse the probe line's `superseded=` value. Each scenario: Fake().Reset(), fresh renderer, Start, SetSize(64, 36), WaitFrameReady(1), then the steps; every failure is reported with the scenario name, and the renderer log is printed on failure. No sleeps except bounded harness waits. Warning-clean under gcc/clang -Wall -Wextra -Wpedantic -Werror and MSVC /W4 /WX. Add it to native/tests/meson.build directly after the sw_hold_front_test block, with a comment in that block's style (separate binary because the golden set is frozen; software and a fake pipelined backend, so it runs on every platform and under the sanitizers): `executable('video_renderer_swap_test', ...)` with the same include_directories, cpp_args, link_with and dependencies, and `test('video_renderer_swap_test', swap_test, timeout: 120)`.

    4. Local native build (MSVC; meson only runs on CI). Write build/nwm-tests/build_all.bat (CRLF) that calls the vcvars64.bat from context. It compiles third_party/volk/volk.c as C with /W0, then video_renderer.cc and vulkan_backend.cc with `/nologo /EHsc /std:c++17 /W4 /WX /O2 /utf-8 /DVK_NO_PROTOTYPES /DWIN32_LEAN_AND_MEAN /DNOMINMAX`, includes packages/mpv_kit_video/src, src/include, third_party/vulkan-headers/include, third_party/volk and native/tests, and asserts on (no NDEBUG). It then links these Windows meson tests into build/nwm-tests/: video_renderer_golden_sw, _golden_vk, _golden_vk_fallback, _golden_vk_retire_twice, _golden_sw_retire_twice, _sw_hold_front_test, _api_test, _affinity_test, _chain_test, _linux_chain_test, _bind_test, _swap_test. If a test file this plan does not modify fails only because MSVC turns a warning into an error, build that one without /WX and note it; never edit a test source to please MSVC. Write build/nwm-tests/run_all.sh, which runs each test with the meson args (golden file under native/tests/golden/ plus `--slack-ms=250` where meson passes them: golden_sw sw.txt, golden_vk vk.txt, vk_fallback vk_fallback.txt, vk_retire_twice vk_retire_twice.txt, sw_retire_twice sw_retire_twice.txt, sw_hold_front `--slack-ms=250` only, api_test api_override.txt, chain_test chain.txt, linux_chain_test linux_chain.txt; affinity, bind and swap take no args). It prints `<test> rc=<rc> <last output line>` per test and finally `ALL rc=0` only when every rc is 0 (77 counts as a failure here: this host has a Vulkan 1.3 device). Build with `cmd //c 'build\nwm-tests\build_all.bat'`, then run. Expected RED: swap_test rc=1 (swap-at-publish-sw and -gpu fail, both superseded scenarios pass), every other test rc=0. Write the quick-dir file 261029-nwm-native-tests.log: a host/cl version line, `--- RED (instrumentation only, pre-fix) ---`, the per-test lines, and one line `red swap_test rc=1 <first failure message>`. If anything other than swap_test fails here, stop and report: the instrumentation broke something.

    5. Baseline Release build of this instrumented tree with the bundle procedure from context (user_define, build, revert, porcelain check). Then two A/B runs, base-auto and base-d3d11, each started from the Release dir in the background with `env -u MPV_KIT_LIBMPV_PATH MPV_KIT_EXAMPLE_AO=null` (plus `MPV_KIT_VIDEO_API=d3d11` for d3d11) and the single argument `av://lavfi:testsrc2=size=3840x2160:rate=60:duration=200[out0];sine=frequency=440:sample_rate=48000:duration=200[out1]`. Redirect stdout and stderr to build/nwm/base-<cfg>.log, sleep 150 s, `taskkill //IM mpv_kit_example.exe`, and add //F only if it still runs 10 s later. Default window (1280x720), untouched. Write build/nwm/ab_metrics.sh (awk over one log, CR stripped) printing: reason (from the `mpv_kit_video:` line); probe_lines (count of `render waits` lines); drops = N of the last `mpv_kit_example: N dropped` line minus N of the 10th; superseded = sum of `superseded=` values over probe lines 6..end; effective = drops + superseded; done_med = median `done=` and pickup_med = median pickup avg, both over lines 6..end; avsync_max = max |avdiff| over stat lines 10..end (numeric values only); errors = lines matching `frame render failed|device lost|gpu timeout|rendering recovered`.

    6. The fix. Swaps are reported when a frame is published.
       - RenderOnce publish block: after the lock (publish plus superseded counting), call ReportSwaps(1) and then interop_->FrameReady(), in that order. Remove the old accounting at 857-868: the previous-frame-pending increment and the consuming check. Rationale: a superseded frame already had its swap at its own publish, so the old "previous frame never displayed still counts" increment would now count it twice; that frame survives only in the log-only superseded counter. Replace the comment with one explaining why: flip_page waits for the swap before mpv queues the next frame, and the render API gives mpv no presentation timing, so waiting for the compositor only shortened mpv's frame budget.
       - AcquireFront: remove the presented/swap counting (471-479) and its comment, keep the front_acquired_ marking, and notify the render thread only when resumed. Update the header doc (video_renderer.h:119-124) to say that it makes no libmpv call and only records which frame the compositor took.
       - RenderLoop: remove the swap term from the ready predicate, the pending-swap deadline and its timeout branch (keep the failure-backoff deadline and the retry logic), the swap hand-off, the "woken only to report swaps" branch, the local swaps counter and the ReportSwaps(swaps) call, and the sentence about unreported swaps being dropped at exit (661).
       - video_renderer.h: delete the three swap members (swap_pending_, swaps_to_report_, kPresentTimeout) and their comments, and rewrite the last_acquire_ comment as "last time the compositor took a frame (idle detection)". ReportSwaps, SkipFrame and the failure-path swaps stay unchanged.
       - Then rebuild and run all native tests 3 times (run_all.sh x3): every run must end in `ALL rc=0`. Append `--- GREEN (fix) run <k> ---` blocks to 261029-nwm-native-tests.log. Also run `sha256sum -c .planning/phases/14-windows-native-d3d11-backend/evidence/golden-freeze-14.sha256` and append its result.

    7. After-fix Release build (same procedure), then runs fix-auto and fix-d3d11, identical to step 5 (logs build/nwm/fix-<cfg>.log).

    8. Gate. Write the quick-dir file 261029-nwm-AB.txt with:
       - a host line (GPU, refresh rate from `Win32_VideoController.CurrentRefreshRate`, power online);
       - the source URL, ao, window size, run_seconds=150 and the measurement windows;
       - a builds line (base = HEAD + instrumentation, fix = HEAD + instrumentation + fix);
       - one `ab run=<base|fix>-<auto|d3d11> reason=... probe_lines=... drops=... superseded=... effective=... done_med=... pickup_med=... avsync_max=... errors=...` line per run;
       - the rule line: not_worse = effective_fix <= effective_base + 2 per config; clearly_better = effective_fix * 2 <= effective_base and effective_base - effective_fix >= 5 for at least one config; avsync_max_fix <= 10 * max(avsync_max_base, 0.001); errors_fix <= errors_base; probe_lines >= 65 in every run (else the run was not continuously rendered: repeat that run once);
       - `ab_gate=PASS` when all rules hold, `ab_gate=FAIL` when not_worse, avsync or errors is violated, and `ab_gate=INCONCLUSIVE` when nothing is worse but no config reaches clearly_better.
       On FAIL: `git diff > build/nwm/fix.patch`, copy the new test to build/nwm/, restore the tracked files with `git checkout -- <the touched tracked paths>`, remove the untracked test file, and STOP: return a checkpoint with the table (do not ship, do not start Task 2). On INCONCLUSIVE: save the patch, leave the tree uncommitted and STOP: return a checkpoint with the table so the orchestrator asks the user. Only on PASS continue.

    9. Real-plugin integration tests (debug plugin, asserts on) with the bundle user_define and env from context, from example/: `/d/flutter/bin/flutter test integration_test/real_plugin_test.dart -d windows`, then `MPV_KIT_VIDEO_API=d3d11 /d/flutter/bin/flutter test integration_test/d3d11_backend_test.dart -d windows`; revert pubspec.yaml afterwards and check porcelain. Append `integration real_plugin_test=<pass|fail> d3d11_backend_test=<pass|fail>` to 261029-nwm-AB.txt. Either failing blocks the commit (diagnose; if it is a real regression, treat it as FAIL in step 8).

    10. Docs and stale comments.
       - docs/ARCHITECTURE.md "Swap reporting" bullet (87-98): rewrite it as the new contract and include the exact phrase "reported when it is published". Say: the render thread reports each frame's swap right after the publish gate made it the front, before FrameReady; skipped, failed and timed-out frames are reported on the same thread, so every render call is answered by exactly one swap; why (flip_page waits for it; no presentation feedback in the render API; reporting at pickup added the pickup latency to every frame, quick 261029-nwm, numbers in docs/perf/d3d11-backend.md); the tradeoff (a frame replaced before the compositor takes it is never shown and mpv does not count it; the probe line reports it as `superseded=<n>`); AcquireFront makes no libmpv call. Keep the display-fps-override sentence. In "Render context release" (99-104) delete the sentence about unreported swaps.
       - docs/perf/d3d11-backend.md: add `## Swap reporting at publish (261029-nwm)` before `## Hybrid-GPU laptops (14-10)`. Include the motivation (the laptop package2 numbers from the objective), the method (host, source, ao=null, window, 150 s, metric definitions), a 4-row table copied from 261029-nwm-AB.txt (run, reason head, drops, superseded, effective, done med, pickup med, avsync max), the verdict, and a note that the laptop result comes from package3.
       - Comment-only updates, so that no non-frozen test still names the removed timeout or says a swap is left to the compositor: affinity_test.cc:63-65 and bind_test.cc:75-76 (the raster period just keeps the compositor active, which keeps the renderer out of idle), and the `kPastPresentTimeout` comment in the three non-frozen goldens (a settle margin before the quiesce counts; keep the constant's name and value). Do not edit the frozen files. Their stale comments are reported in the SUMMARY.
       - Rebuild the native tests once more and run run_all.sh (must print `ALL rc=0`); append it as `--- FINAL ---`.

    11. `source /tmp/gsd-bak/root_pin.sh`; `git add` exactly the 11 files in <files>; commit once, for example `fix(video): report mpv swaps when a frame is published`, with a body covering the root cause, the A/B effective drops before and after per config, RBE-05 unchanged, the superseded counter, and quick 261029-nwm, ending with the Co-Authored-By line. Do not push. A note for the SUMMARY: RBE-04 froze constants only for the Phase 12 move commits; removing the present timeout is a deliberate, measured behaviour change.
  </action>
  <verify>
    <automated>S=packages/mpv_kit_video/src && Q=.planning/quick/261029-nwm-report-swap-at-publish-power-aware-gpu-p && ! grep -qE 'swap_pending_|swaps_to_report_|kPresentTimeout' $S/video_renderer.h $S/video_renderer.cc && grep -q 'superseded=' $S/video_renderer.cc && grep -q 'front_acquired_' $S/video_renderer.h && ! grep -q 'kPresentTimeout' native/tests/video_renderer_affinity_test.cc native/tests/video_renderer_bind_test.cc native/tests/video_renderer_golden_vk_fallback.cc native/tests/video_renderer_golden_vk_retire_twice.cc native/tests/video_renderer_golden_sw_retire_twice.cc && ! grep -q 'swaps_to_report_' docs/ARCHITECTURE.md && grep -q 'reported when it is published' docs/ARCHITECTURE.md && grep -q '^## Swap reporting at publish (261029-nwm)' docs/perf/d3d11-backend.md && grep -q 'video_renderer_swap_test' native/tests/meson.build && grep -q 'SWAP ok scenarios=' native/tests/video_renderer_swap_test.cc && sha256sum -c --quiet .planning/phases/14-windows-native-d3d11-backend/evidence/golden-freeze-14.sha256 && grep -qx 'ab_gate=PASS' $Q/261029-nwm-AB.txt && grep -q '^integration real_plugin_test=pass d3d11_backend_test=pass' $Q/261029-nwm-AB.txt && grep -q '^red swap_test rc=1' $Q/261029-nwm-native-tests.log && tail -n 1 $Q/261029-nwm-native-tests.log | tr -d '\r' | grep -qx 'ALL rc=0' && bash build/nwm-tests/run_all.sh | tail -n 1 | tr -d '\r' | grep -qx 'ALL rc=0' && test "$(grep -a -c 'superseded=' example/build/windows/x64/runner/Release/mpv_kit_video_plugin.dll)" -ge 1 && E=$(printf '%s\n' docs/ARCHITECTURE.md docs/perf/d3d11-backend.md native/tests/meson.build native/tests/video_renderer_affinity_test.cc native/tests/video_renderer_bind_test.cc native/tests/video_renderer_golden_sw_retire_twice.cc native/tests/video_renderer_golden_vk_fallback.cc native/tests/video_renderer_golden_vk_retire_twice.cc native/tests/video_renderer_swap_test.cc packages/mpv_kit_video/src/video_renderer.cc packages/mpv_kit_video/src/video_renderer.h | LC_ALL=C sort) && H1=$(git show --name-only --format= HEAD) && C=$(printf '%s\n' "$H1" | LC_ALL=C sort) && test "$C" = "$E" && EOL=$(git ls-files --eol $E) && ! printf '%s\n' "$EOL" | grep -qv 'i/lf *w/lf' && PS=$(git status --porcelain pubspec.yaml) && test -z "$PS" && test -z "$(git diff --name-only 0bf0bb6..HEAD -- '*.dart')"</automated>
    <baseline>At HEAD 0bf0bb6: swap members/timeout in src h=4 cc=12 (the negative gate fails); `superseded=` in video_renderer.cc 0; `front_acquired_` 0; kPresentTimeout in the five non-frozen tests 1 each; `swaps_to_report_` in ARCHITECTURE.md 1; "reported when it is published" 0; the docs/perf heading 0; video_renderer_swap_test in meson 0; the A/B and native-tests files are absent; Release DLL `superseded=` 0; golden-freeze-14 OK (it must stay OK). Every positive gate fails at HEAD.</baseline>
    <fails_when>any removed swap member or the timeout survives in the renderer sources, or the timeout's name survives in a non-frozen test; no superseded counter, or it is not in the Release DLL; a frozen golden file changed; the RED was not recorded or a final run is not ALL rc=0; ab_gate is not PASS; either integration test failed; the commit holds anything other than the 11 files; a file became CRLF; pubspec.yaml is left modified; a Dart file changed</fails_when>
  </verify>
  <acceptance_criteria>
    - Swaps are reported at publish on the render thread, before FrameReady; the deferral machinery is gone; affinity and bind tests stay green (RBE-05).
    - The probe line carries `superseded=<n>`; the new swap test was RED before the fix and GREEN after; all locally buildable renderer tests pass 3x; frozen goldens unchanged.
    - A/B on the RTX 4060: ab_gate=PASS (effective drops not worse anywhere, at least halved in one config, avsync and errors unchanged); real-plugin and d3d11 integration tests pass locally.
    - One local commit with exactly the 11 files (code, tests, docs); nothing pushed (D-05: the fix lands before Task 2 starts).
  </acceptance_criteria>
  <done>The swap is reported when the frame is published, verified by a RED-then-GREEN native test, the unchanged frozen goldens, local integration tests and a passing A/B gate on real hardware, and committed with its docs.</done>
</task>

<task type="auto">
  <name>Task 2: Power-aware runner preference + hybrid GPU hint + low-cost config docs; build, verify and ship package3; record ## package3</name>
  <files>example/windows/runner/main.cpp, packages/mpv_kit_video/windows/d3d11_interop.cpp, packages/mpv_kit_video/README.md, docs/perf/d3d11-backend.md, .planning/phases/14-windows-native-d3d11-backend/evidence/laptop-package.txt</files>
  <read_first>
    - example/windows/runner/main.cpp (whole file, 49 lines; the preference call and its comment are at 22-26)
    - packages/mpv_kit_video/windows/d3d11_interop.cpp lines 1-83 (namespace helpers, LogCompositorAdapter at 27-50, constructor at 53-83)
    - packages/mpv_kit_video/README.md lines 47-101
    - docs/perf/d3d11-backend.md (whole file as committed by Task 1)
    - .planning/phases/14-windows-native-d3d11-backend/evidence/laptop-package.txt from line 132 (`## package2`: key names and formats)
    - .planning/quick/261029-ljp-hybrid-gpu-high-performance-adapter-for-/261029-ljp-PLAN.md Task 2 action (procedure) and build/phase14/pkg2-src/ (launcher and 使用说明 sources)
    - this plan's package_spec
  </read_first>
  <precondition>Task 1's commit is HEAD and 261029-nwm-AB.txt says `ab_gate=PASS`; `git status --porcelain -- packages example native docs tools pubspec.yaml` is empty; the libmpv-rtx MANIFEST check has no failure; `df -P . "$HOME/Desktop"` shows at least 1 GB on the repo filesystem and 300 MB on the desktop filesystem.</precondition>
  <action>
    1. `source /tmp/gsd-bak/root_pin.sh`.

    2. main.cpp (per D-04). Replace the comment and the `set_gpu_preference(...HighPerformancePreference)` call at 22-26 with `project.set_gpu_preference(ChooseGpuPreference());` and add a file-local `ChooseGpuPreference()` above wWinMain, with a `///`-style or `//` comment in the file's style. The comment says: the engine picks its adapter once, before any plugin registers (Flutter 3.41+, flutter/flutter#177653), and mpv_kit_video renders on that adapter; on AC power with battery saver off ask for the high-performance GPU; otherwise NoPreference, so that Windows' per-app graphics setting decides; decided once at startup. The function calls `::GetSystemPowerStatus`. It uses named constants for the AC-online value (1) and the battery-saver bit (SystemStatusFlag & 1), with a comment citing SYSTEM_POWER_STATUS. It returns HighPerformancePreference only when the call succeeded, ACLineStatus is AC online and the saver bit is clear; otherwise NoPreference, with a reason chosen in this order: call failed or ACLineStatus 255 -> `power status unknown`, 0 -> `on battery`, saver bit set -> `battery saver on`. It writes exactly one line to OutputDebugStringA (with a newline) and to stderr (`if (stderr) fprintf(stderr, ...)`): `mpv_kit_example: GPU preference high-performance (AC power, battery saver off)` or `mpv_kit_example: GPU preference none (<reason>); Windows graphics settings decide`. Add `<cstdio>` if needed. It must stay clean under /W4 /WX; add no other change and no driver-hint exports.

    3. d3d11_interop.cpp (per D-03, log-only; kWindowsApiOrder is untouched per D-01). In the anonymous namespace, factor LogCompositorAdapter's UTF-16 to UTF-8 conversion and its two log sinks into small helpers (`Utf8(const WCHAR*)`, `LogLine(const std::string&)`), keeping its output byte-identical. Add named constants: `kMicrosoftVendorId = 0x1414` (Basic Render Driver / WARP; never counted as integrated or discrete) and `kIntegratedMaxDedicatedMiB = 512`. Their comment documents the heuristic: integrated = under 512 MiB of DedicatedVideoMemory (Intel iGPUs report about 128 MiB); AMD APUs with a UMA carve-out of 512 MiB or more are not detected and get no hint, which is harmless.

       Add `LogHybridGpuHint(IDXGIAdapter* adapter, const DXGI_ADAPTER_DESC& desc)`, called in the constructor right after LogCompositorAdapter(desc):
       - Return when the compositor adapter is Microsoft or has 512 MiB or more dedicated.
       - Get its IDXGIFactory1 via `adapter->GetParent(__uuidof(IDXGIFactory1), ...)` into a ComPtr. On failure, return: this is a best-effort hint, so say so in a comment.
       - Enumerate `EnumAdapters1(i, ...)` until it fails and call `GetDesc1` on each. Skip adapters with `DXGI_ADAPTER_FLAG_SOFTWARE`, the Microsoft vendor, the compositor's LUID, or under 512 MiB dedicated.
       - On the first match, write one line via LogLine and stop: `mpv_kit: hybrid GPU hint: Flutter composites on "<compositor name>" (<N> MiB dedicated, looks integrated) while "<other name>" (<M> MiB) is present; set the GPU preference in the app's windows/runner/main.cpp (flutter::DartProject::set_gpu_preference, see the mpv_kit_video README) to render on it`.
       Use MiB values via `static_cast<unsigned long long>(x / (1024 * 1024))` and keep it clean under /W4 /WX.

    4. README (D-02, D-03, D-04). Rework the "Hybrid-GPU laptops" paragraph (71-90):
       - the plugin renders on Flutter's adapter;
       - the 14-10 HD 530 numbers stay;
       - the app chooses in its runner; replace the snippet with the power-aware version: GetSystemPowerStatus, AC online and saver bit clear -> HighPerformancePreference, else NoPreference, so Windows' per-app setting decides on battery;
       - the example runner does exactly this and logs `mpv_kit_example: GPU preference ...`;
       - the adapter line stays, and the new `mpv_kit: hybrid GPU hint:` line is described, including when it appears.
       Then add a short "Weak or integrated GPUs" paragraph: optional, not defaults, nothing is applied automatically; a Dart `Player(options: {...})` snippet with `'linear-downscaling': 'no'`, `'cscale': 'bilinear'` and, only for the D3D11 backend with d3d11va hardware decoding, `'d3d11va-zero-copy': 'yes'`. Add the caveat from mpv's options.rst (the bottom and right edges may be sampled wrongly because of padding, and driver bugs are possible) and point to ADR 0006 for why it is not a default.

    5. docs/perf/d3d11-backend.md `## Hybrid-GPU laptops (14-10)`:
       - Opt-in bullet: the example runner is now power-aware (D-04), with the decision line.
       - New bullet: the hint (D-03), with the heuristic and that it is log-only.
       - New bullet: the optional low-cost config (D-02), with a link to the README paragraph.
       - Status bullet: package2 (824a69e) moved Flutter to the GTX 960M, but drops remained (auto vulkan gpu-next 2.5-6%, forced d3d11 25-34%); the swap fix (section above) and the power-aware choice ship in package3; the laptop result is pending.
       Make no other edits.

    6. Release build (bundle procedure from context), then local smoke from the Release dir with `env -u MPV_KIT_LIBMPV_PATH MPV_KIT_EXAMPLE_AO=null`, using the Task 1 4K60 lavfi URL with audio, once under auto and once with `MPV_KIT_VIDEO_API=d3d11`. Logs go to build/nwm/pkg3-smoke-auto.log and pkg3-smoke-d3d11.log. About 25 s in, take a full-screen screenshot (PowerShell System.Drawing CopyFromScreen into build/nwm/) and look at it to confirm the picture and the HUD; then `taskkill //IM mpv_kit_example.exe`.

       Read the host's power status with a PowerShell Add-Type P/Invoke of GetSystemPowerStatus (ACLineStatus, SystemStatusFlag). The checks:
       - each log has exactly one `mpv_kit_example: GPU preference ` line, and it matches the host status (on AC with saver off: high-performance);
       - one `mpv_kit: compositor adapter "NVIDIA GeForce RTX 4060...` line;
       - no `mpv_kit: hybrid GPU hint:` line (single hardware adapter here);
       - probe lines carry `superseded=`;
       - the startup reasons read `vulkan (gpu-next) on NVIDIA GeForce RTX 4060 Laptop GPU` and `d3d11 (gpu-next) on NVIDIA GeForce RTX 4060 Laptop GPU; vulkan/gpu-next unavailable: excluded by MPV_KIT_VIDEO_API=d3d11`.
       If any check fails, fix main.cpp or d3d11_interop.cpp only and rebuild. Then run the CI plugin checks: `flutter analyze --fatal-infos` in packages/mpv_kit_video and in example, and `flutter test` in packages/mpv_kit_video with the env from context.

    7. `source /tmp/gsd-bak/root_pin.sh`; `git add` exactly main.cpp, d3d11_interop.cpp, README.md and docs/perf/d3d11-backend.md; commit, for example `feat(windows): power-aware GPU preference in the example; plugin hybrid-GPU hint`, with a body citing D-02..D-04, quick 261029-nwm and the heuristic, ending with the Co-Authored-By line.

    8. package3, following 261029-ljp Task 2 adapted.
       a. Set `FEAT=$(git rev-parse HEAD)`, `SHORT=$(git rev-parse --short=7 HEAD)` and `FIX=$(git log -1 --format=%H -- packages/mpv_kit_video/src/video_renderer.cc)`. Rebuild Release from that commit (bundle procedure, record exit status and seconds).
       b. Write the draft build/nwm/package3-section.txt (LF) with the same keys as `## package2`:
          - header `## package3` and a `#` comment (quick 261029-nwm: swap at publish + superseded counter, power-aware GPU preference, hybrid hint);
          - feat_sha, `swap_fix_sha=$FIX`, feat_branch, date_utc;
          - release_run=40812562348, plus a release_run_note with `git diff --stat ad5c54b..$FEAT -- native/ .github/` and the local-build changes under packages/ and example/;
          - bundle_dir, build, release_dir, flutter;
          - the 24 dll lines, bundle_dll_count, bundle_match;
          - the 25 angle lines, angle_audit_files, angle_audit;
          - release_plugin (MPV_KIT_D3D11_SYNC / MPV_KIT_D3D11_INJECT counts), debug_build_plugin, debug_build_has_switches, debug_switches_absent;
          - `adapter_log_string_in_dll`, `hint_string_in_dll`, `superseded_string_in_dll` (grep -a -c on the Release plugin DLL) and `power_string_in_exe` (grep -a -c 'GPU preference' on mpv_kit_example.exe), each `=yes` only when the count is at least 1;
          - probe_host lines (rerun the reused probe exe with `--host rtx4060-dev`);
          - `power_host ac=<n> saver=<n>`;
          - `local_smoke auto=<reason> d3d11=<reason>` and local_smoke_note;
          - `power_log=<the decision line>` and `power_log_matches_host=yes|no`;
          - `hint_log=none (single hardware adapter on the dev host)`;
          - `superseded_in_log=yes`;
          - adapter_log, adapter_log_runs, adapter_luid_matches_probe.
       c. Create `$HOME/Desktop/mpv_kit_d3d11_demo_$SHORT/` with:
          - demo/: the whole Release dir plus msvcp140.dll, vcruntime140.dll and vcruntime140_1.dll from the VC143 CRT dir, whose sha256 must equal the package2 lines;
          - d3d11_caps_probe.exe, reused unless its sha differs;
          - run-probe.bat, run-auto-log.bat and run-d3d11.bat exactly as in package_spec, written with the Write tool to build/nwm/pkg3-src/ and then converted to CRLF;
          - 使用说明.txt per package_spec (CRLF, UTF-8 BOM, `<feat 短 SHA>` = $SHORT).
          Check the encodings with `file`.
       d. Launcher check from the desktop copy. Record which `mpv_kit_*_log_*.txt` files already exist on the dev desktop. Run run-auto-log.bat twice and run-d3d11.bat once through cmd with stdin from NUL, in the background, passing the absolute Windows path of `demo\data\flutter_assets\integration_test\route_samples\h264-8bit.mp4` inside the package; `taskkill //IM mpv_kit_example.exe` after about 15 s each. Confirm that mpv_kit_auto_log_1.txt and _2.txt and mpv_kit_d3d11_log_1.txt (numbering relative to what existed) were created. Each must contain the GPU preference line, the compositor adapter line and the `mpv_kit_video:` line (d3d11 with the `d3d11 (` reason). Then delete only the log files this check created. Record `bat_log_check auto=yes d3d11=yes numbering=yes` and one note. If cmd mishandles the numbering loop, fix only the bat files, re-test, and record the deviation.
       e. Record desktop_path, desktop_layout (note that run-probe.bat was recreated and give its new sha), desktop_check, desktop_size, and one `sha256 <hash> ./<path>` line per file (sorted).
       f. Old package: if `$HOME/Desktop/mpv_kit_d3d11_demo_824a69e` exists and differs from the new path, `rm -rf --` that exact path now and record `old_package_removed=<path>`. Otherwise record `old_package_removed=none (mpv_kit_d3d11_demo_824a69e was not on the desktop when package3 was built)`.
       g. Append the draft to laptop-package.txt (one blank line first, LF; the earlier sections untouched). `source /tmp/gsd-bak/root_pin.sh`; `git add` only that file; commit, for example `docs(14-10): package3 provenance (swap at publish, power-aware GPU preference)`, with the Co-Authored-By line. Do not push.
  </action>
  <verify>
    <automated>M=example/windows/runner/main.cpp && I=packages/mpv_kit_video/windows/d3d11_interop.cpp && R=packages/mpv_kit_video/README.md && P=docs/perf/d3d11-backend.md && L=.planning/phases/14-windows-native-d3d11-backend/evidence/laptop-package.txt && grep -v '^\s*//' $M | grep -q 'GetSystemPowerStatus' && grep -v '^\s*//' $M | grep -q 'NoPreference' && grep -v '^\s*//' $M | grep -q 'HighPerformancePreference' && grep -q 'mpv_kit_example: GPU preference ' $M && grep -v '^\s*//' $I | grep -q 'mpv_kit: hybrid GPU hint: ' && grep -v '^\s*//' $I | grep -q 'EnumAdapters1' && grep -v '^\s*//' $I | grep -q 'DXGI_ADAPTER_FLAG_SOFTWARE' && grep -q 'kIntegratedMaxDedicatedMiB = 512' $I && grep -qF 'constexpr const char* kWindowsApiOrder[] = {"vulkan", "d3d11"};' $I && for f in $R $P; do grep -q 'GetSystemPowerStatus\|NoPreference' $f && grep -q 'hybrid GPU hint' $f && grep -q 'linear-downscaling' $f || exit 1; done && grep -q 'cscale' $R && grep -q 'd3d11va-zero-copy' $R && grep -q 'padding' $R && H2=$(git show --name-only --format= HEAD~1) && test "$(printf '%s\n' "$H2" | LC_ALL=C sort | tr '\n' ' ')" = "docs/perf/d3d11-backend.md example/windows/runner/main.cpp packages/mpv_kit_video/README.md packages/mpv_kit_video/windows/d3d11_interop.cpp " && test "$(git show --name-only --format= HEAD)" = "$L" && S="$(sed -n '/^## package3$/,$p' "$L")" && test -n "$S" && F=$(printf '%s\n' "$S" | sed -n 's/^feat_sha=//p') && test "$F" = "$(git rev-parse HEAD~1)" && printf '%s\n' "$S" | grep -qx "swap_fix_sha=$(git log -1 --format=%H -- packages/mpv_kit_video/src/video_renderer.cc)" && for k in bundle_match=yes angle_audit=ok debug_switches_absent=yes adapter_log_string_in_dll=yes hint_string_in_dll=yes superseded_string_in_dll=yes power_string_in_exe=yes power_log_matches_host=yes superseded_in_log=yes adapter_luid_matches_probe=yes; do printf '%s\n' "$S" | grep -qx "$k" || exit 1; done && printf '%s\n' "$S" | grep -Eq '^power_log=mpv_kit_example: GPU preference (high-performance \(AC power, battery saver off\)|none \((on battery|battery saver on|power status unknown)\); Windows graphics settings decide)$' && printf '%s\n' "$S" | grep -Eq '^local_smoke auto=.* d3d11=d3d11 \(gpu-next\) on NVIDIA GeForce RTX 4060' && printf '%s\n' "$S" | grep -Eq '^adapter_log=mpv_kit: compositor adapter "NVIDIA GeForce RTX 4060[^"]*" luid=[0-9A-F]{8}:[0-9A-F]{8}$' && printf '%s\n' "$S" | grep -Eq '^bat_log_check auto=yes d3d11=yes numbering=yes' && printf '%s\n' "$S" | grep -q '^old_package_removed=' && D=$(printf '%s\n' "$S" | sed -n 's/^desktop_path=//p') && test "$D" = "$HOME/Desktop/mpv_kit_d3d11_demo_$(git rev-parse --short=7 "$F")" && test -f "$D/demo/mpv_kit_example.exe" && test -f "$D/d3d11_caps_probe.exe" && for b in run-probe.bat run-auto-log.bat run-d3d11.bat; do file "$D/$b" | grep -q CRLF || exit 1; done && grep -q 'mpv_kit_auto_log_%N%' "$D/run-auto-log.bat" && grep -q 'mpv_kit_d3d11_log_%N%' "$D/run-d3d11.bat" && file "$D/使用说明.txt" | grep -q 'with BOM' && file "$D/使用说明.txt" | grep -q CRLF && test "$(grep -a -c 'mpv_kit: hybrid GPU hint: ' "$D/demo/mpv_kit_video_plugin.dll")" -ge 1 && test "$(grep -a -c 'superseded=' "$D/demo/mpv_kit_video_plugin.dll")" -ge 1 && EOL=$(git ls-files --eol $M $I $R $P "$L") && ! printf '%s\n' "$EOL" | grep -qv 'i/lf *w/lf' && PS=$(git status --porcelain pubspec.yaml) && test -z "$PS" && test -z "$(git diff --name-only 0bf0bb6..HEAD -- '*.dart')" && ST=$(git status --porcelain) && test -z "$(printf '%s\n' "$ST" | grep -vE '^( M \.planning/config\.json| M \.planning/state\.json|\?\? \.planning/(debug|tmp|ui-reviews)/|\?\? engine_repo_embedder\.cc|\?\? \.planning/quick/261029-nwm-report-swap-at-publish-power-aware-gpu-p/)$' | grep -v '^$')" && (cd packages/mpv_kit_video && /d/flutter/bin/flutter analyze --fatal-infos) && (cd example && /d/flutter/bin/flutter analyze --fatal-infos)</automated>
    <baseline>At HEAD 0bf0bb6 (and after Task 1): main.cpp has GetSystemPowerStatus 0, NoPreference 0, and the `mpv_kit_example: GPU preference` string 0 (HighPerformancePreference 1); d3d11_interop.cpp has the hint string 0, EnumAdapters1 0, DXGI_ADAPTER_FLAG_SOFTWARE 0, the 512 constant 0, and the kWindowsApiOrder line 1 (it must stay); README/perf have GetSystemPowerStatus 0, NoPreference 0, hint 0, linear-downscaling 0, cscale 0, d3d11va-zero-copy 0; laptop-package.txt `## package3` 0, so S is empty and the gate fails; no package3 folder on the desktop.</baseline>
    <fails_when>the power decision does not use GetSystemPowerStatus with both branches, or the decision line is missing or does not match the host; the hint is missing from the source or the shipped DLL, or kWindowsApiOrder changed; README/perf lack the power snippet, the hint or the low-cost config with the padding caveat; either commit has the wrong file set; any package3 key is missing or not yes, or the adapter line does not name the RTX 4060; the launchers do not number logs or have the wrong line endings; 使用说明 lacks the BOM or CRLF; a file became CRLF; pubspec.yaml is modified; a Dart file changed; the tree has an unexpected change; analyze fails</fails_when>
  </verify>
  <acceptance_criteria>
    - The example runner chooses HighPerformancePreference on AC with battery saver off and NoPreference otherwise, once at startup, with one decision log line (D-04); the chain stays Vulkan-first (D-01).
    - The plugin logs the hybrid GPU hint only for an integrated compositor adapter next to a discrete one (D-03); README/perf document the snippet, the hint and the optional low-cost config (D-02).
    - package3 is traceable to the Task 2 code commit and the Task 1 fix commit, verified on this host (bundle_match, angle_audit, debug switches, adapter line naming the RTX 4060, power line matching the host, no hint, superseded present); the launchers write numbered logs; `## package3` is committed alone; nothing pushed.
  </acceptance_criteria>
  <done>The power-aware preference, the hint and the docs are committed; a verified, self-contained package3 with numbered-log launchers and updated Chinese instructions is on the desktop, and its provenance is committed.</done>
</task>

<task type="checkpoint:human-verify" gate="blocking-human">
  <name>Task 3: User runs package3 on the GTX 960M + HD 530 laptop (AC and battery) and replies</name>
  <files>none (the orchestrator records the reply later)</files>
  <read_first>
    - .planning/phases/14-windows-native-d3d11-backend/evidence/laptop-package.txt `## package3` (desktop_path, feat_sha, swap_fix_sha)
  </read_first>
  <action>Present the checkpoint below to the user with the desktop path filled in, then stop and wait. Edit no file. Config `workflow.human_verify_mode` is end-of-phase, but the orchestrator asked for this blocking checkpoint explicitly, and the run needs the user's other machine.</action>
  <what-built>Desktop folder `mpv_kit_d3d11_demo_<feat 短 SHA>` (package3). It contains the example Release build with: swaps reported to mpv at publish (Task 1, A/B-verified on the RTX 4060); a `superseded=` count in the 120-frame probe lines; a power-aware GPU preference (AC with saver off -> high-performance, otherwise Windows decides), logged as `mpv_kit_example: GPU preference ...`; and the plugin's `mpv_kit: compositor adapter` line plus `mpv_kit: hybrid GPU hint:` when Flutter is on the integrated GPU. run-auto-log.bat and run-d3d11.bat write a new numbered desktop log per run, run-probe.bat writes mpv_kit_d3d11_probe.txt, and 使用说明.txt has the steps.</what-built>
  <how-to-verify>
    1. Keep the Windows Graphics and NVIDIA program settings for mpv_kit_example.exe at their defaults and note them; copy the folder to the laptop; run run-probe.bat in the same boot session.
    2. On AC power (battery saver off): run-auto-log.bat, then run-d3d11.bat. Play the 3840x2160 59.94 fps H.264 file for at least 2 minutes each with no seeking and the window visible, and note the duration and the HUD values (backend, reason, dropped, dec-drop, avsync, hwdec, fps).
    3. On battery: the same two runs.
    4. In each log, find the `mpv_kit_example: GPU preference`, `mpv_kit: compositor adapter` and (if present) `mpv_kit: hybrid GPU hint:` lines.
  </how-to-verify>
  <resume-signal>Reply with, for each of the 4 runs (AC/battery x auto/d3d11): power state and battery saver state, play duration, reason (full), dropped, dec-drop, avsync, hwdec, fps, and the three log lines (or "none"). Attach all mpv_kit_auto_log_*.txt, mpv_kit_d3d11_log_*.txt and mpv_kit_d3d11_probe.txt, and say what the Windows Graphics / NVIDIA settings were.</resume-signal>
  <verify><automated>echo "blocking-human: no automated check; the user's reply is the result (recorded later by the orchestrator)"</automated></verify>
  <acceptance_criteria>
    - The reply covers all four runs with the HUD values, the durations and the three lines, and the log and probe files are attached.
  </acceptance_criteria>
  <done>The user's package3 laptop result (AC and battery, auto and d3d11) is in hand for the orchestrator.</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| render thread <-> libmpv VO thread | swap timing decides when mpv's flip_page returns |
| raster thread -> renderer state | AcquireFront writes front_acquired_ under mutex_ |
| dev machine build -> user's laptop | unsigned Release package run on another machine |
| user report / log files -> evidence | human-read values and log text become verification input |
| workspace root pubspec.yaml | temporary local bundle user_define during builds |

## STRIDE Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation Plan |
|-----------|----------|-----------|----------|-------------|-----------------|
| T-261029nwm-01 | Denial of Service | VideoRenderer swap reporting (stall or ring overrun from changed timing) | high | mitigate | one swap per render call kept (CheckSwapInvariant in every golden quiesce); new swap test RED/GREEN; ring/quarantine goldens unchanged; affinity/bind tests (render-thread only, debug asserts); local real_plugin and d3d11 integration tests; A/B gate with errors and avsync rules |
| T-261029nwm-02 | Tampering | data race on front_acquired_ / probe_superseded_ | medium | mitigate | front_acquired_ only under mutex_; probe_superseded_ written under mutex_ and read only by the render thread; sanitizer CI job runs the new test |
| T-261029nwm-03 | Tampering | frozen golden set | medium | mitigate | `sha256sum -c golden-freeze-14.sha256` in the Task 1 gate; the plan forbids edits to the five frozen files |
| T-261029nwm-04 | Tampering | package3 contents | medium | mitigate | every bundle DLL sha256-compared with build/phase14/libmpv-rtx; ANGLE audit on plugin + bundle DLLs; sha256 of every desktop file recorded in `## package3` |
| T-261029nwm-05 | Information Disclosure | adapter, hint and power log lines (GPU names, dedicated memory, AC state) | low | accept | hardware facts only, written to the user's own stderr/log files and sent voluntarily |
| T-261029nwm-06 | Repudiation | laptop verification result | medium | mitigate | numbered log per run; each log names its power decision, adapter and forced API; the reply asks for raw HUD values |
| T-261029nwm-07 | Tampering | root pubspec.yaml user_define | medium | mitigate | `git checkout -- pubspec.yaml` after each build regardless of exit status; both gates check porcelain is empty; staging by explicit path |
| T-261029nwm-08 | Denial of Service | removal of an old desktop package | low | mitigate | only the exact literal path of package2, only after package3 verification, recorded as old_package_removed= |
| T-261029nwm-09 | Elevation of Privilege | unsigned exe and bat launchers on the laptop | low | accept | the user's own dev build run as the user; launchers only set one env var and redirect output |
| T-261029nwm-SC | Tampering | npm/pip/cargo installs | high | mitigate | no package installs; builds use the pinned workspace pub dependencies and the local bundle |
</threat_model>

<source_audit>
| Source item | Covered by |
|---|---|
| GOAL: fix render-side frame drops by reporting swaps at publish | Task 1 steps 6-8 |
| Evidence ask: superseded counter in the 120-frame probe line, no API/Dart change | Task 1 step 2, gate (Dart unchanged) |
| Evidence ask: baseline before fix, 4K60 lavfi, auto + d3d11, >=120 s, frame-drop-count/superseded/done/pickup | Task 1 step 5 (150 s), metrics script |
| Remove deferral machinery only if unused; keep RBE-05; reason out "previous frame still counts" | Task 1 step 6 (members removed: only used for deferral; last_acquire_ kept for idle; the double count is the reason the increment goes) |
| Update ARCHITECTURE.md swap paragraph and affected native tests; say which tests only CI runs | Task 1 steps 4, 6, 10; SUMMARY lists CI-only tests |
| A/B gate (not worse anywhere, clearly better in one, avsync, no new errors); STOP if no help | Task 1 step 8 |
| Atomic commit fix + tests + docs | Task 1 step 11 |
| D-01 Vulkan-first chain unchanged | Task 2 gate (kWindowsApiOrder line) |
| D-02 low-cost config docs only | Task 2 steps 4-5 |
| D-03 hybrid hint, DXGI enumeration, 512 MiB heuristic documented, log-only | Task 2 step 3 |
| D-04 power-aware preference, logged, mirrored in docs | Task 2 steps 2, 4-5 |
| D-05 order: fix first, then package3 | Task 1 precedes Task 2 (precondition ab_gate=PASS) |
| package3 like 261029-ljp Task 2, desktop folder, old folder removed only after verification, 使用说明 AC + battery runs, `## package3` committed alone | Task 2 step 8, package_spec |
| Blocking human checkpoint | Task 3 |
</source_audit>

<verification>
- Task 1: removed swap machinery absent; superseded counter present in source and Release DLL; swap test RED then GREEN; all locally buildable renderer tests ALL rc=0 (3x + final); frozen goldens OK; ab_gate=PASS; local integration tests pass; commit is exactly the 11 files.
- Task 2: power decision and hint in source and shipped binaries; docs updated; two commits with exact file sets; `## package3` keys all yes; desktop package files and encodings correct; analyze green; no unexpected working-tree change.
- Task 3: user reply received.
- Only CI can run: the meson builds of every renderer test on Linux x64/arm64, macOS and Windows (MSYS2 clang/gcc, warning_level=3 -Werror); the ASan/UBSan sanitizer job (including the new swap test); render_vk_smoke / render_d3d11_smoke / render_gl_smoke / stream_bridge_test (they need meson-built libmpv); the Linux-only drm_params_test; WARP and hosted-runner integration legs; and the Linux and macOS plugins. The SUMMARY must list these as pending CI (the orchestrator pushes).
- Nothing pushed by this plan.
</verification>

<success_criteria>
- mpv gets each frame's swap at publish on the render thread; drops measured as mpv drops plus superseded are lower on the RTX 4060 with no regression, and the laptop result is requested.
- The example picks its GPU by power state, the plugin hints on hybrid machines, and the docs give an optional low-cost config; there is no public API or Dart change and the chain stays Vulkan-first.
- package3 is verified, on the desktop, and its provenance is committed; the user's laptop reply is available to the orchestrator.
</success_criteria>

<output>
Create `.planning/quick/261029-nwm-report-swap-at-publish-power-aware-gpu-p/261029-nwm-SUMMARY.md` when done (do not commit it; the orchestrator handles quick-task docs). Include the A/B table, the RED/GREEN lines, the frozen-file stale comments left in place (renderer_harness.h around 365-367, golden_sw.cc:40, golden_vk.cc:47), the CI-only test list, and any MSVC-only /WX relaxations.
</output>

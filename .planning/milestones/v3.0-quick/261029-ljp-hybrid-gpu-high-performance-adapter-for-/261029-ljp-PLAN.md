---
phase: quick-261029-ljp
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - example/windows/runner/main.cpp
  - packages/mpv_kit_video/windows/d3d11_interop.cpp
  - packages/mpv_kit_video/README.md
  - docs/perf/d3d11-backend.md
  - .planning/phases/14-windows-native-d3d11-backend/evidence/laptop-package.txt
autonomous: false
requirements: [D3D-06]

estimate:
  tokens: 90000
  raw_tokens: 90000
  tasks: 3
  confidence: low

must_haves:
  truths:
    - "The example's Windows runner asks the Flutter engine for the high-performance adapter (`project.set_gpu_preference(flutter::GpuPreference::HighPerformancePreference)`), so on a hybrid laptop Flutter's compositor adapter, and with it the adapter the plugin binds its D3D11/Vulkan device to, is the discrete GPU when one exists."
    - "Every D3D11Interop creation writes exactly one line `mpv_kit: compositor adapter \"<DXGI_ADAPTER_DESC.Description>\" luid=<HighPart hex8>:<LowPart hex8>` to stderr and DebugView, so the adapter actually used can be read from a redirected log file."
    - "packages/mpv_kit_video/README.md and docs/perf/d3d11-backend.md tell hybrid-GPU apps to opt in from their own runner (the plugin cannot), with the 14-10 laptop numbers (HD 530, dropped 477-3310, dec-drop 0)."
    - "No Dart file and no public API change; the Windows Release build of example, `flutter analyze --fatal-infos` (plugin and example) and `flutter test` in packages/mpv_kit_video pass."
    - "package2 on the dev desktop is built from the commit that carries the preference, is traceable (bundle_match=yes, angle_audit=ok, debug switches absent), plays a picture under auto and forced d3d11 on this host, and its adapter log line names NVIDIA GeForce RTX 4060; run-auto-log.bat and run-d3d11.bat produce desktop log files containing that line."
    - "The old desktop package mpv_kit_d3d11_demo_11b728a is removed only after package2 is verified; the user has run package2 on the laptop and replied."
  artifacts:
    - path: "example/windows/runner/main.cpp"
      provides: "high-performance GPU preference for the engine"
      contains: "project.set_gpu_preference(flutter::GpuPreference::HighPerformancePreference);"
    - path: "packages/mpv_kit_video/windows/d3d11_interop.cpp"
      provides: "one compositor adapter log line per interop creation"
      contains: "mpv_kit: compositor adapter"
    - path: "packages/mpv_kit_video/README.md"
      provides: "hybrid-GPU opt-in guidance for app runners"
      contains: "set_gpu_preference"
    - path: "docs/perf/d3d11-backend.md"
      provides: "14-10 hybrid laptop numbers and opt-in"
      contains: "HD 530"
    - path: ".planning/phases/14-windows-native-d3d11-backend/evidence/laptop-package.txt"
      provides: "package2 provenance section"
      contains: "## package2"
  key_links:
    - from: "example/windows/runner/main.cpp set_gpu_preference"
      to: "Flutter engine EGL manager adapter choice (IDXGIFactory6::EnumAdapterByGpuPreference, LUID passed to ANGLE)"
      via: "flutter::DartProject -> FlutterDesktopEngineProperties.gpu_preference"
      pattern: "set_gpu_preference"
    - from: "registrar_->GetView()->GetGraphicsAdapter() (packages/mpv_kit_video/windows/mpv_kit_video_plugin.cpp:228-230)"
      to: "D3D11Interop constructor log line (packages/mpv_kit_video/windows/d3d11_interop.cpp)"
      via: "IDXGIAdapter::GetDesc -> Description + AdapterLuid"
      pattern: "mpv_kit: compositor adapter"
    - from: "run-auto-log.bat / run-d3d11.bat in the desktop package"
      to: "%USERPROFILE%\\Desktop\\mpv_kit_auto_log.txt / mpv_kit_d3d11_log.txt"
      via: "stdout+stderr redirection of mpv_kit_example.exe"
      pattern: "adapter_log="
  prohibitions:
    - requirement_id: D3D-06
      category: process
      status: unresolved
      verification: null
      statement: "MUST NOT commit the temporary libmpv_bundle hooks user_define in the workspace root pubspec.yaml, MUST NOT push, and MUST NOT stage .planning/config.json, .planning/state.json, .planning/tmp/, .planning/ui-reviews/, .planning/debug/ or engine_repo_embedder.cc."
    - requirement_id: D3D-06
      category: scope
      status: unresolved
      verification: null
      statement: "MUST NOT add GPU driver-hint symbol exports to the runner or plugin, MUST NOT change any Dart file or public API."
---

<objective>
Hybrid-GPU high-performance adapter for the Windows example, plus a rebuilt laptop demo (package2) for the 14-10 user.

Background (verified this session): on the 14-10 laptop (GeForce GTX 960M + Intel HD 530, package 11b728a) Flutter/ANGLE stays on the HD 530. The plugin binds by design to `registrar_->GetView()->GetGraphicsAdapter()` (`packages/mpv_kit_video/windows/mpv_kit_video_plugin.cpp:228-230`; `d3d11_interop.cpp:35-50` records the LUID; `d3d11_backend.cpp:296-337` creates the device on the same adapter), so d3d11va decode plus d3d11 gpu-next render also ran on the HD 530: dropped 477-3310, dec-drop 0. Setting the exe to "High performance" in Windows Settings did not move it (cause not established). Flutter 3.41+ (this repo builds with 3.47.8) has `flutter::DartProject::set_gpu_preference(flutter::GpuPreference::HighPerformancePreference)` (flutter/flutter#177653, merged 2025-12-04); the engine's EGL manager then picks the adapter with `IDXGIFactory6::EnumAdapterByGpuPreference` and passes its LUID to ANGLE, falling back to the default adapter. The wrapper header is `example/windows/flutter/ephemeral/cpp_client_wrapper/include/flutter/dart_project.h:14-25,121`. `example/windows/runner/main.cpp:20-25` does not set it.

Purpose: let the laptop test whether the in-app preference alone moves Flutter and mpv to the GTX 960M, with a log line that proves which adapter was used.
Output: one code+docs commit; desktop package2 with logging launchers; a `## package2` provenance section in the 14-10 evidence; the user's laptop reply.
</objective>

<execution_context>
@~/.claude/gsd-core/workflows/execute-plan.md
@~/.claude/gsd-core/templates/summary.md
</execution_context>

<context>
@.planning/STATE.md
@CLAUDE.md
@.planning/phases/14-windows-native-d3d11-backend/14-10-PLAN.md
@.planning/phases/14-windows-native-d3d11-backend/evidence/laptop-package.txt
@example/windows/runner/main.cpp
@packages/mpv_kit_video/windows/d3d11_interop.cpp
@packages/mpv_kit_video/README.md
@docs/perf/d3d11-backend.md

Interfaces the executor needs (already read by the planner, do not re-derive):
- `flutter::GpuPreference` (enum class in namespace flutter, dart_project.h:14-25): `NoPreference`, `LowPowerPreference`, `HighPerformancePreference` ("falls back to a low power GPU if no high performance GPU is available"). Setter: `void DartProject::set_gpu_preference(GpuPreference)` (dart_project.h:121).
- `D3D11Interop::D3D11Interop(IDXGIAdapter*, std::function<void()>)` in d3d11_interop.cpp:28-57: `DXGI_ADAPTER_DESC desc` is read at line 35-39, `luid_ = desc.AdapterLuid;` at line 40. File-local anonymous namespace at lines 13-26. `<cstdio>` and `<string>` already included; `<windows.h>` arrives through `<d3d11.h>`.
- Existing log style: `LogLine` (mpv_kit_video_plugin.cpp:54-59) and `Log` (d3d11_backend.cpp:56-60) both do `OutputDebugStringA(msg + "\n")` then `if (stderr) fprintf(stderr, "%s\n", ...)`; messages start with `mpv_kit: `. UTF-16 to UTF-8 helper `Utf8` (d3d11_backend.cpp:68-75) is file-local to d3d11_backend.cpp.
- The probe prints the same LUID as `luid=%08X%08X` (HighPart then LowPart, no separator; tools/d3d11_probe/d3d11_caps_probe.cpp:192-193), so `<hi>:<lo>` with the colon removed equals the probe's value. LUIDs are only stable within one boot.
- Plugin compile flags: `/W4 /WX /utf-8`, C++17 (packages/mpv_kit_video/windows/CMakeLists.txt).
- All five files in files_modified are LF in index and working tree (`git ls-files --eol`); keep them LF.

Prior commands that already worked here (reuse verbatim):
- Release build: `cd example && /d/flutter/bin/flutter build windows --release` with the temporary root pubspec hooks user_define `libmpv_bundle: build/phase14/libmpv-rtx` (relative, laptop-package.txt line 8), reverted with `git checkout -- pubspec.yaml`.
- CI plugin checks (.github/workflows/flutter-plugin.yml:86-88): `cd packages/mpv_kit_video && flutter analyze --fatal-infos && flutter test`, then `cd ../../example && flutter analyze --fatal-infos`; local libmpv env as in docs/perf/d3d11-backend.md Reproduce (`MPV_KIT_LIBMPV_PATH`, `MPV_KIT_REQUIRE_LIBMPV=1`, bundle `lib` on PATH in POSIX form).
- ANGLE audit: `python -I tools/rea_abi_audit/pe_audit.py <dll> --forbid-angle`.
- VC++ runtime source: `/d/vs community/VC/Redist/MSVC/14.44.35112/x64/Microsoft.VC143.CRT/` (msvcp140.dll, vcruntime140.dll, vcruntime140_1.dll).
- Probe exe: `build/phase14/laptop-probe-obj/d3d11_caps_probe.exe`, sha256 d85cd7f33c80c809228ff7c15387611e5477331459c25ab1e48699b6b2a2a042 (= package-1 copy); tools/d3d11_probe/ unchanged since 11b728a. Rebuild only if either differs: `cl /nologo /EHsc /std:c++17 /W4 /WX /O2 tools/d3d11_probe/d3d11_caps_probe.cpp` in a vcvars64 environment.
</context>

<locked_decisions>
From the request (orchestrator, this session); cite as L-NN.
- L-01: Opt in through `project.set_gpu_preference(flutter::GpuPreference::HighPerformancePreference);` in example/windows/runner/main.cpp with a short comment citing flutter#177653 and the reason (hybrid laptops: compositor adapter == our D3D11/Vulkan adapter).
- L-02: Do not add GPU driver-hint symbol exports (NVIDIA/AMD) anywhere; do not mention them in source comments.
- L-03: Plugin logs once per D3D11Interop creation, `mpv_kit:` style, `mpv_kit: compositor adapter "<desc>" luid=<hi>:<lo>` (hex). No public API change, no Dart change.
- L-04: Docs: packages/mpv_kit_video README Windows section and docs/perf/d3d11-backend.md say hybrid-GPU apps must opt in from their own runner (plugin cannot) and cite the 14-10 laptop numbers.
- L-05: package2 is built exactly like 14-10 Task 1 (bundle, provenance, VC++ runtime, probe), plus run-auto-log.bat; delete ~/Desktop/mpv_kit_d3d11_demo_11b728a only after package2 verifies; append `## package2` to laptop-package.txt and commit that file only.
- L-06: Commit locally only, never push; stage by explicit path; every commit ends with `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.
- L-07: Recording the laptop result into 14-10 Task 3 evidence is NOT part of this quick task (orchestrator does it later).
</locked_decisions>

<executor_rules>
- Host: Windows MINGW64 Git Bash, cwd D:/mpv_kit, Flutter `/d/flutter/bin/flutter`, MSVC, RTX 4060. Disk is tight: repo filesystem D: (~6 GB free), desktop filesystem C: (~2.7 GB free).
- Run `source /tmp/gsd-bak/root_pin.sh` (PINNED_ROOT='D:/mpv_kit') before the first Edit/Write and before every commit.
- Protected user files are never staged or modified: .planning/config.json, .planning/state.json, .planning/tmp/, .planning/ui-reviews/, .planning/debug/, engine_repo_embedder.cc. Around any gsd-tools call: `cp .planning/state.json /tmp/ljp_state.bak` before, `cmp` after, restore from the backup if it changed.
- Sequential execution on the main tree. Commit locally only (L-06).
- Temporary files (logs, screenshots, section drafts) go under build/phase14/ (gitignored) or /tmp, never into the repo tree outside build/.
</executor_rules>

<package_spec>
Exact launcher contents for the desktop package (ASCII, CRLF line endings, no BOM). Task 2 writes these files.

run-probe.bat: byte-identical copy of the package-1 file (sha256 3b1efa2bf548c074f5ec87b898c882be00ed650463978046d0f7fc9a9c6e9111); copy it from ~/Desktop/mpv_kit_d3d11_demo_11b728a/ before that folder is removed.

run-auto-log.bat:

```bat
@echo off
rem mpv_kit demo, auto backend chain. stdout+stderr go to a desktop log file.
set MPV_KIT_VIDEO_API=
set LOG=%USERPROFILE%\Desktop\mpv_kit_auto_log.txt
cd /d "%~dp0demo"
echo Logging to %LOG%
echo Close the demo window when done. Do not close this console window.
"%~dp0demo\mpv_kit_example.exe" %* > "%LOG%" 2>&1
echo Log saved: %LOG%
pause
```

run-d3d11.bat (replaces the package-1 `start` launcher so the forced run is logged too; discretion: the user reports the adapter line for both runs):

```bat
@echo off
rem mpv_kit demo, forced d3d11 backend. stdout+stderr go to a desktop log file.
set MPV_KIT_VIDEO_API=d3d11
set LOG=%USERPROFILE%\Desktop\mpv_kit_d3d11_log.txt
cd /d "%~dp0demo"
echo Logging to %LOG%
echo Close the demo window when done. Do not close this console window.
"%~dp0demo\mpv_kit_example.exe" %* > "%LOG%" 2>&1
echo Log saved: %LOG%
pause
```

使用说明.txt (Chinese, UTF-8 with BOM, CRLF). Keep the package-1 file's structure and tone (read it from ~/Desktop/mpv_kit_d3d11_demo_11b728a/使用说明.txt before removal). Required content, in this order:
1. Title `mpv_kit D3D11 演示包 使用说明（版本 <feat 短 SHA>，package2）`.
2. 目的: this build asks Windows/Flutter for the high-performance GPU from inside the program. Last time (11b728a) on this GTX 960M + Intel HD 530 laptop both the Flutter compositor and mpv rendering ran on the HD 530 (dropped 477-3310, dec-drop 0), and the Windows Settings "高性能" option did not move it. This run checks whether the in-program preference alone moves it to the GTX 960M.
3. 本目录内容: demo\, d3d11_caps_probe.exe, run-probe.bat, run-auto-log.bat (auto, writes 桌面 mpv_kit_auto_log.txt), run-d3d11.bat (forced d3d11, writes 桌面 mpv_kit_d3d11_log.txt), 使用说明.txt.
4. Step 0 (先复位设置): open 设置 -> 系统 -> 屏幕 -> 显示卡 (Graphics); find any mpv_kit_example.exe entry added for the previous package and choose 重置/删除 (or 让 Windows 决定); do not add an entry for the new exe. If mpv_kit_example.exe was given a processor in NVIDIA 控制面板 -> 管理 3D 设置 -> 程序设置, set it back to 使用全局设置. Reason: test the program's own preference alone. Ask the user to note what was there before resetting.
5. Copy the whole folder to the laptop.
6. Run run-probe.bat in the same boot session as the demo runs (LUIDs change after a reboot); it writes 桌面 mpv_kit_d3d11_probe.txt.
7. Auto run: double-click run-auto-log.bat (or drag the video onto it). A black console window opens: do not close it. Drag the 3840x2160 59.94 fps H.264 file into the demo window, HUD with F9, keep the window visible, no seeking, no other window operations, play at least 2 minutes and note the actual play duration. Record backend, reason (full text), dropped, dec-drop, avsync, hwdec, fps (a HUD screenshot is fine). Close the demo window with its X button; the console shows `Log saved`; press any key.
8. Forced d3d11 run: same with run-d3d11.bat, at least 2 minutes, no seeking.
9. In each log file find the line starting with `mpv_kit: compositor adapter`: `NVIDIA GeForce GTX 960M` means the preference worked, `Intel(R) HD Graphics 530` means it did not; report it either way.
10. Notes: in the auto run the reason may now start with `vulkan (` (with Flutter on the GTX 960M the Vulkan path may be accepted); that is fine, the forced run covers d3d11. The HUD backend label still shows vulkan during a d3d11 run (known label issue): judge by the reason prefix.
11. 请回复: per run the play duration, reason (full), dropped, dec-drop, avsync, hwdec, fps and the adapter line; attach mpv_kit_auto_log.txt, mpv_kit_d3d11_log.txt and mpv_kit_d3d11_probe.txt; say what the Windows Graphics / NVIDIA settings were before the reset.
12. 其他说明: unsigned dev build (SmartScreen: 仍要运行), VC++ runtime included, 64-bit Windows 10+ only.
</package_spec>

<tasks>

<task type="tracer">
  <name>Task 1: Runner GPU preference + compositor adapter log + docs, proven end-to-end by a Release build that prints the adapter line</name>
  <files>example/windows/runner/main.cpp, packages/mpv_kit_video/windows/d3d11_interop.cpp, packages/mpv_kit_video/README.md, docs/perf/d3d11-backend.md</files>
  <read_first>
    - example/windows/runner/main.cpp (whole file, 43 lines)
    - packages/mpv_kit_video/windows/d3d11_interop.cpp lines 1-57 (anonymous namespace and constructor)
    - packages/mpv_kit_video/windows/d3d11_backend.cpp lines 56-75 (Log sinks and the Utf8 helper to mirror)
    - packages/mpv_kit_video/README.md lines 47-81 (Renderers and fallback; Windows D3D11 paragraph at 65-69)
    - docs/perf/d3d11-backend.md lines 92-101 (Follow-ups, Verification tiers; GTX 960 bullet at line 100)
  </read_first>
  <precondition>build/phase14/libmpv-rtx exists and `cd build/phase14/libmpv-rtx && sha256sum -c MANIFEST.txt` reports 0 failures; `df -P .` shows at least 1 GB available on the repo filesystem.</precondition>
  <action>
    1. `source /tmp/gsd-bak/root_pin.sh`.
    2. main.cpp (per L-01): directly after `flutter::DartProject project(L"data");` add the call `project.set_gpu_preference(flutter::GpuPreference::HighPerformancePreference);` preceded by a 2-4 line `//` comment in the file's style: hybrid-GPU laptops; the engine picks the high-performance adapter (Flutter 3.41+, flutter/flutter#177653) and falls back to the default adapter without one; mpv_kit_video renders on the adapter Flutter composites on, so this moves decode/render and composition together. No other change to main.cpp. Per L-02 add no driver-hint exports and do not name them in the comment.
    3. d3d11_interop.cpp (per L-03): in the anonymous namespace add one file-local helper (for example `LogCompositorAdapter(const DXGI_ADAPTER_DESC&)`) with a `//` comment saying why (lets a user's redirected log show which adapter Flutter, and therefore the plugin, uses on hybrid machines). It converts `desc.Description` to UTF-8 with `WideCharToMultiByte(CP_UTF8, ...)` mirroring `Utf8` in d3d11_backend.cpp:68-75 (do not move or export that helper: minimal diff), formats the LUID with `snprintf` as `%08lX:%08lX` from `static_cast<unsigned long>(desc.AdapterLuid.HighPart)` and `desc.AdapterLuid.LowPart`, builds the line `mpv_kit: compositor adapter "<name>" luid=<hi>:<lo>` and writes it to the same two sinks as `Log` in d3d11_backend.cpp:57-60 (OutputDebugStringA with a trailing newline, then `if (stderr) fprintf(stderr, "%s\n", ...)`). Call it in the constructor right after `luid_ = desc.AdapterLuid;` so the line appears once per interop creation, also when the D3D11CreateDevice call below fails. Nothing else in the file changes; must compile under /W4 /WX (explicit casts, no narrowing).
    4. README (per L-04), Windows section, directly after the D3D11 paragraph (lines 65-69): a short "Hybrid-GPU laptops" paragraph: the plugin always renders on the adapter Flutter's compositor uses (shared textures cannot cross adapters), so on a laptop where Flutter lands on the integrated GPU, decode and rendering do too; on the 14-10 test laptop (GeForce GTX 960M + Intel HD 530) that meant d3d11 gpu-next on the HD 530 with 477-3310 dropped frames and dec-drop 0. Apps opt in from their own runner, because the engine picks its adapter before any plugin registers: in `windows/runner/main.cpp` call `project.set_gpu_preference(flutter::GpuPreference::HighPerformancePreference);` before creating the window (Flutter 3.41 or newer, flutter/flutter#177653); without a discrete GPU the engine uses the default adapter. Mention the stderr line `mpv_kit: compositor adapter "<name>" luid=<hi>:<lo>` that shows the adapter in use. A short fenced cpp snippet in the README is fine. Do not claim the preference is verified on the laptop.
    5. docs/perf/d3d11-backend.md (per L-04): add a section `## Hybrid-GPU laptops (14-10)` before `## Follow-ups` with: machine (GTX 960M + Intel HD 530, package 11b728a, user report 2026-10-29); observation (Flutter/ANGLE on the HD 530, plugin bound to `GetGraphicsAdapter()` by design, d3d11va + d3d11 gpu-next on the HD 530, dropped 477-3310, dec-drop 0, Windows Settings per-app "High performance" did not move it, cause not established); the opt-in (`set_gpu_preference(HighPerformancePreference)` in the app runner, the plugin cannot do it; the example runner now does) and the adapter log line; status: the laptop result with the preference comes from package2 (evidence/laptop-package.txt `## package2`) and is not recorded here yet. Replace the `- **GTX 960 laptop:** see 14-10 (user session); no data here.` bullet in Verification tiers with one pointing at the new section. No other edits.
    6. Build (Windows plugin + example, Release): append the temporary hooks user_define exactly as last time (`hooks:` / `user_defines:` / `mpv_kit_libs:` / `libmpv_bundle: build/phase14/libmpv-rtx`) to the root pubspec.yaml, run `cd example && /d/flutter/bin/flutter build windows --release`, and run `git checkout -- pubspec.yaml` immediately afterwards whatever the build's exit status; confirm `git status --porcelain pubspec.yaml` is empty. Fix compile errors in the two C++ files only.
    7. End-to-end check of the one path: from example/build/windows/x64/runner/Release, with `MPV_KIT_LIBMPV_PATH` unset and no bundle dir on PATH, start `./mpv_kit_example.exe 'av://lavfi:testsrc2=size=1280x720:rate=30:duration=30[out0]'` with stdout+stderr redirected to build/phase14/ljp-t1.log, wait about 15 s, close it with `taskkill //IM mpv_kit_example.exe` (add `//F` only if it is still running 10 s later). The log must contain one `mpv_kit: compositor adapter "...` line with `luid=XXXXXXXX:XXXXXXXX`, and the `mpv_kit_video:` startup line.
    8. Checks CI runs (L-03: no Dart change, so these must stay green): `flutter analyze --fatal-infos` in packages/mpv_kit_video and in example; `flutter test` in packages/mpv_kit_video with `LIB="$PWD/build/phase14/libmpv-rtx/lib"`, `MPV_KIT_LIBMPV_PATH="$LIB/libmpv-2.dll"`, `MPV_KIT_REQUIRE_LIBMPV=1`, `PATH="$LIB:$PATH"` (POSIX form, docs/perf/d3d11-backend.md Reproduce).
    9. `source /tmp/gsd-bak/root_pin.sh`; `git add` exactly the four files; commit once (L-06), e.g. `feat(windows): example prefers the high-performance GPU; plugin logs the compositor adapter`, body naming quick 261029-ljp and flutter/flutter#177653, ending with the Co-Authored-By line. Do not push.
  </action>
  <verify>
    <automated>grep -v '^\s*//' example/windows/runner/main.cpp | grep -qF 'project.set_gpu_preference(flutter::GpuPreference::HighPerformancePreference);' && grep -q '177653' example/windows/runner/main.cpp && grep -v '^\s*//' packages/mpv_kit_video/windows/d3d11_interop.cpp | grep -q 'mpv_kit: compositor adapter' && ! grep -rqE 'NvOptimusEnablement|AmdPowerXpressRequestHighPerformance' example/windows/runner packages/mpv_kit_video/windows && grep -q 'set_gpu_preference' packages/mpv_kit_video/README.md && grep -q 'set_gpu_preference' docs/perf/d3d11-backend.md && grep -q 'HD 530' docs/perf/d3d11-backend.md && grep -q '^## Hybrid-GPU laptops (14-10)' docs/perf/d3d11-backend.md && C=$(git show --name-only --format= HEAD) && test "$(printf '%s\n' "$C" | sort | tr '\n' ' ')" = "docs/perf/d3d11-backend.md example/windows/runner/main.cpp packages/mpv_kit_video/README.md packages/mpv_kit_video/windows/d3d11_interop.cpp " && EOL=$(git ls-files --eol docs/perf/d3d11-backend.md example/windows/runner/main.cpp packages/mpv_kit_video/README.md packages/mpv_kit_video/windows/d3d11_interop.cpp) && test -n "$EOL" && ! printf '%s\n' "$EOL" | grep -qv 'w/lf' && PS=$(git status --porcelain pubspec.yaml) && test -z "$PS" && test "$(grep -a -c 'mpv_kit: compositor adapter' example/build/windows/x64/runner/Release/mpv_kit_video_plugin.dll)" -ge 1 && test "$(tr -d '\r' < build/phase14/ljp-t1.log | grep -nE '^mpv_kit: compositor adapter ".+" luid=[0-9A-F]{8}:[0-9A-F]{8}$' | wc -l)" -eq 1 && (cd packages/mpv_kit_video && /d/flutter/bin/flutter analyze --fatal-infos) && (cd example && /d/flutter/bin/flutter analyze --fatal-infos) && LIB="$PWD/build/phase14/libmpv-rtx/lib" && (cd packages/mpv_kit_video && MPV_KIT_LIBMPV_PATH="$LIB/libmpv-2.dll" MPV_KIT_REQUIRE_LIBMPV=1 PATH="$LIB:$PATH" /d/flutter/bin/flutter test)</automated>
    <baseline>At HEAD 479c7a8: set_gpu_preference count in main.cpp 0, `compositor adapter` in d3d11_interop.cpp 0, README/d3d11-backend.md set_gpu_preference 0, `## Hybrid-GPU laptops` absent, Release plugin DLL string count 0 (package-1 build), driver-hint symbols 0 (guard only). Every positive gate fails at HEAD.</baseline>
    <fails_when>the preference call or its flutter#177653 comment is missing; the log line is missing from the source, the Release DLL or the 15 s run's log, or its LUID is not two 8-digit uppercase hex groups; a driver-hint export appears; the HEAD commit contains anything but the four files; a file turned CRLF; pubspec.yaml left modified; analyze or the plugin tests fail</fails_when>
  </verify>
  <acceptance_criteria>
    - The Release example built from this tree prints exactly one `mpv_kit: compositor adapter "<name>" luid=<hi>:<lo>` line per controller creation.
    - The runner requests HighPerformancePreference (L-01); no driver-hint exports (L-02); no Dart or public API change (L-03).
    - README and d3d11-backend.md carry the opt-in guidance and 14-10 numbers (L-04).
    - One local commit with exactly the four files; pubspec.yaml clean; nothing pushed (L-06).
  </acceptance_criteria>
  <done>The preference and the adapter log are committed, built, and proven on one end-to-end run; CI-equivalent analyze and plugin tests pass locally.</done>
</task>

<task type="auto">
  <name>Task 2: Build package2 from the Task 1 commit, verify it like 14-10, copy to the desktop, remove the old package, record ## package2</name>
  <files>.planning/phases/14-windows-native-d3d11-backend/evidence/laptop-package.txt</files>
  <read_first>
    - .planning/phases/14-windows-native-d3d11-backend/14-10-PLAN.md Task 1 action (procedure)
    - .planning/phases/14-windows-native-d3d11-backend/evidence/laptop-package.txt (whole file: key names, line formats, package-1 sha256 list)
    - ~/Desktop/mpv_kit_d3d11_demo_11b728a/使用说明.txt and run-probe.bat (to carry over before removal)
    - this plan's package_spec section
  </read_first>
  <precondition>Task 1's commit is HEAD; `git status --porcelain -- packages example native tools pubspec.yaml` is empty; build/phase14/libmpv-rtx MANIFEST check has 0 failures; at least 1 GB free on the repo filesystem and 300 MB on the desktop filesystem (`df -P . "$HOME/Desktop"`).</precondition>
  <action>
    1. `FEAT=$(git log -1 --format=%H -- example/windows/runner/main.cpp)`, `SHORT=$(git rev-parse --short=7 "$FEAT")`; FEAT must equal HEAD. Rebuild exactly like 14-10 Task 1 step 1 (per L-05): temporary root pubspec.yaml hooks user_define `libmpv_bundle: build/phase14/libmpv-rtx`, `cd example && /d/flutter/bin/flutter build windows --release`, then `git checkout -- pubspec.yaml` regardless of exit status and confirm `git status --porcelain pubspec.yaml` is empty.
    2. Provenance into a draft at build/phase14/package2-section.txt (LF only), same key names and line formats as the package-1 section of laptop-package.txt: header `## package2` then a `#` comment naming quick 261029-ljp (high-performance GPU preference + adapter log); `feat_sha=$FEAT`, `feat_branch=`, `date_utc=`; `release_run=40812562348` and a `release_run_note=` recording `git diff --stat ad5c54b..$FEAT -- native/ .github/` (bundle inputs) and that the plugin DLL and exe are local builds; `bundle_dir=` with the MANIFEST result; `build=` (command, exit status, seconds, the user_define and its revert); `release_dir=`; `flutter=`; one `dll <name> bundle=<sha> release=<sha> same|differs` line per `build/phase14/libmpv-rtx/lib/*.dll` (24) and `bundle_dll_count=24 same=N differs=M`, then `bundle_match=yes` only when all are same; `angle <dll> rc=<rc> :: <RESULT line>` for mpv_kit_video_plugin.dll and each bundle DLL via `python -I tools/rea_abi_audit/pe_audit.py <dll> --forbid-angle`, `angle_audit_files=25 ... pass=N`, `angle_audit=ok` only when all pass (flutter_windows.dll not audited, ADR 0003); `release_plugin <switch>=0 <switch>=0` with `grep -a -c` for the two debug switch names shown on the package-1 `release_plugin` line, `debug_build_plugin ...` baseline from example/build/windows/x64/runner/Debug/mpv_kit_video_plugin.dll (stale earlier Debug build; say so), `debug_switches_absent=yes` only when both release counts are 0; `adapter_log_string_in_dll=yes` when `grep -a -c 'mpv_kit: compositor adapter'` on the Release plugin DLL is at least 1.
    3. Dev-host adapters: run `build/phase14/laptop-probe-obj/d3d11_caps_probe.exe --host rtx4060-dev` and record each `CAPS` line's adapter and luid as `probe_host adapter="<name>" luid=<16 hex>`.
    4. Local smoke exactly like 14-10 Task 1 step 3, from the Release dir with `MPV_KIT_LIBMPV_PATH` unset and no bundle dir on PATH (the package must be self-contained): `./mpv_kit_example.exe 'av://lavfi:testsrc2=size=3840x2160:rate=60:duration=60[out0]'` once under auto and once with `MPV_KIT_VIDEO_API=d3d11`, stdout+stderr each redirected to build/phase14/ljp-smoke-auto.log and ljp-smoke-d3d11.log; about 20 s in, take a full-screen screenshot (PowerShell System.Drawing CopyFromScreen into build/phase14/) and look at it to confirm a picture and the HUD; close with `taskkill //IM mpv_kit_example.exe`. Write `local_smoke auto=<reason from the mpv_kit_video: startup line> d3d11=<reason>` (expected `vulkan (gpu-next) on NVIDIA GeForce RTX 4060 Laptop GPU` and `d3d11 (gpu-next) on NVIDIA GeForce RTX 4060 Laptop GPU; vulkan/gpu-next unavailable: excluded by MPV_KIT_VIDEO_API=d3d11`), a `local_smoke_note=` (picture and HUD seen in both screenshots; backend label note as in package 1), `adapter_log=<the exact compositor adapter line, CR stripped>`, `adapter_log_runs=auto,d3d11 identical=yes|no`, and `adapter_luid_matches_probe=yes` only when the line's `<hi><lo>` (colon removed) equals the luid of the RTX 4060 `probe_host` line. If the adapter line does not name `NVIDIA GeForce RTX 4060`, or any smoke has no picture, stop: do not ship, do not delete the old package, return a checkpoint to the orchestrator with the logs.
    5. Package: create `$HOME/Desktop/mpv_kit_d3d11_demo_$SHORT/` with `demo/` (the whole Release dir, plus msvcp140.dll, vcruntime140.dll, vcruntime140_1.dll from the VC143 CRT dir in context; their sha256 must equal the package-1 lines), `d3d11_caps_probe.exe` (reuse per context; rebuild only if source or sha differ, and record which), and the four files from package_spec: run-probe.bat (copied from package 1, sha unchanged), run-auto-log.bat, run-d3d11.bat (ASCII, CRLF), 使用说明.txt (Chinese, UTF-8 BOM, CRLF, `<feat 短 SHA>` filled with $SHORT). Write the text files with the Write tool, then convert to CRLF and prefix the BOM for 使用说明.txt; check with `file` (CRLF line terminators; "with BOM" for 使用说明.txt only).
    6. Launcher check from the desktop copy: run each logging bat through cmd with stdin from NUL so `pause` returns, passing the absolute Windows path of `demo\data\flutter_assets\integration_test\route_samples\h264-8bit.mp4` inside the desktop package (avoids cmd quoting of lavfi URLs), in the background; about 15 s later `taskkill //IM mpv_kit_example.exe`; confirm `%USERPROFILE%\Desktop\mpv_kit_auto_log.txt` and `mpv_kit_d3d11_log.txt` each contain the compositor adapter line and the `mpv_kit_video:` line (the d3d11 one with the `d3d11 (` reason), then delete those two test logs from the dev desktop. Record `bat_log_check auto=yes d3d11=yes` with one note. If the redirect does not capture the lines, adjust only the bat files (for example `start "" /b /wait`), re-test, record what worked, and update package_spec deviations in the SUMMARY; never change main.cpp for this.
    7. `desktop_path=$HOME/Desktop/mpv_kit_d3d11_demo_$SHORT` (absolute POSIX form as in package 1), `desktop_layout=`, `desktop_check=` (every demo/ bundle DLL byte-identical to the bundle; plugin DLL and exe identical to the Release dir), `desktop_size=`, and one `sha256 <hash> ./<relative path>` line per file (sorted, as in package 1).
    8. Only now (per L-05): `rm -rf -- "$HOME/Desktop/mpv_kit_d3d11_demo_11b728a"` (exact literal path, after confirming the new directory differs from it) and record `old_package_removed=<that path>`.
    9. Append the draft to laptop-package.txt (`cat build/phase14/package2-section.txt >> ...`, preceded by one blank line; LF only; package-1 lines untouched). `source /tmp/gsd-bak/root_pin.sh`; `git add` only that file; commit, e.g. `docs(14-10): package2 provenance (high-performance GPU preference)`, ending with the Co-Authored-By line. Do not push.
  </action>
  <verify>
    <automated>L=.planning/phases/14-windows-native-d3d11-backend/evidence/laptop-package.txt && S="$(sed -n '/^## package2$/,$p' "$L")" && test -n "$S" && F=$(printf '%s\n' "$S" | sed -n 's/^feat_sha=//p') && test "$F" = "$(git log -1 --format=%H -- example/windows/runner/main.cpp)" && printf '%s\n' "$S" | grep -qx 'bundle_match=yes' && printf '%s\n' "$S" | grep -qx 'angle_audit=ok' && printf '%s\n' "$S" | grep -qx 'debug_switches_absent=yes' && printf '%s\n' "$S" | grep -qx 'adapter_log_string_in_dll=yes' && printf '%s\n' "$S" | grep -qx 'adapter_luid_matches_probe=yes' && printf '%s\n' "$S" | grep -Eq '^local_smoke auto=.* d3d11=d3d11 \(gpu-next\) on NVIDIA GeForce RTX 4060' && printf '%s\n' "$S" | grep -Eq '^adapter_log=mpv_kit: compositor adapter "NVIDIA GeForce RTX 4060[^"]*" luid=[0-9A-F]{8}:[0-9A-F]{8}$' && printf '%s\n' "$S" | grep -Eq '^bat_log_check auto=yes d3d11=yes' && D=$(printf '%s\n' "$S" | sed -n 's/^desktop_path=//p') && test "$D" = "$HOME/Desktop/mpv_kit_d3d11_demo_$(git rev-parse --short=7 "$F")" && test -f "$D/demo/mpv_kit_example.exe" && test -f "$D/d3d11_caps_probe.exe" && test -f "$D/run-auto-log.bat" && test -f "$D/run-d3d11.bat" && test "$(sha256sum "$D/run-probe.bat" | cut -d' ' -f1)" = 3b1efa2bf548c074f5ec87b898c882be00ed650463978046d0f7fc9a9c6e9111 && file "$D/run-auto-log.bat" | grep -q 'CRLF' && file "$D/run-d3d11.bat" | grep -q 'CRLF' && file "$D/使用说明.txt" | grep -q 'with BOM' && file "$D/使用说明.txt" | grep -q 'CRLF' && test "$(grep -a -c 'mpv_kit: compositor adapter' "$D/demo/mpv_kit_video_plugin.dll")" -ge 1 && test ! -e "$HOME/Desktop/mpv_kit_d3d11_demo_11b728a" && printf '%s\n' "$S" | grep -q '^old_package_removed=' && EOL=$(git ls-files --eol "$L") && printf '%s\n' "$EOL" | grep -q 'w/lf' && C=$(git show --name-only --format= HEAD) && test "$C" = "$L" && PS=$(git status --porcelain pubspec.yaml) && test -z "$PS" && ST=$(git status --porcelain) && test -z "$(printf '%s\n' "$ST" | grep -vE '^( M \.planning/config\.json| M \.planning/state\.json|\?\? \.planning/(debug|tmp|ui-reviews)/|\?\? engine_repo_embedder\.cc|\?\? \.planning/quick/261029-ljp-hybrid-gpu-high-performance-adapter-for-/)$')"</automated>
    <baseline>At HEAD 479c7a8 laptop-package.txt has no `## package2` line (count 0), so the region-scoped section S is empty and the gate fails; the package-1 keys (bundle_match=yes etc.) are outside S and cannot satisfy it. The old desktop folder exists (the `test ! -e` gate fails at HEAD).</baseline>
    <fails_when>package2 is not built from the Task 1 commit; any of bundle_match, angle_audit, debug switches, adapter string in DLL, LUID-vs-probe, local d3d11 smoke or launcher-log checks is missing or not yes; the adapter line does not name the RTX 4060; a package file is missing or has the wrong encoding/line endings; run-probe.bat changed; the old package still exists or was removed without being recorded; the evidence file turned CRLF; the commit contains more than laptop-package.txt; pubspec.yaml modified; any unexpected working-tree change</fails_when>
  </verify>
  <acceptance_criteria>
    - package2 is traceable to the Task 1 commit with bundle_match=yes, angle_audit=ok and debug_switches_absent=yes, and plays a picture under auto and forced d3d11 on this host (L-05).
    - The adapter log line names NVIDIA GeForce RTX 4060 and its LUID matches the probe; both logging launchers capture it.
    - Desktop holds only package2 (old package removed after verification); laptop-package.txt gains a `## package2` section committed alone (L-06).
  </acceptance_criteria>
  <done>A verified, self-contained package2 is on the desktop with logging launchers and Chinese instructions, and its provenance is committed.</done>
</task>

<task type="checkpoint:human-verify" gate="blocking-human">
  <name>Task 3: User runs package2 on the GTX 960M + HD 530 laptop and replies</name>
  <files>none (the orchestrator records the reply into 14-10 Task 3 evidence later, per L-07)</files>
  <read_first>
    - .planning/phases/14-windows-native-d3d11-backend/evidence/laptop-package.txt `## package2` section (desktop_path, feat_sha)
  </read_first>
  <action>Present the checkpoint below to the user verbatim with the desktop path filled in, then stop and wait. Do not edit any file. Note: config `workflow.human_verify_mode` is end-of-phase, but the orchestrator explicitly requested this blocking checkpoint and the run needs the user's other machine, so it stays a checkpoint.</action>
  <what-built>Desktop folder `mpv_kit_d3d11_demo_<feat 短 SHA>` (package2): the example Release build whose runner requests the high-performance GPU and whose plugin logs `mpv_kit: compositor adapter "<name>" luid=<hi>:<lo>`; run-auto-log.bat and run-d3d11.bat write `mpv_kit_auto_log.txt` and `mpv_kit_d3d11_log.txt` to the laptop desktop; run-probe.bat writes `mpv_kit_d3d11_probe.txt`; 使用说明.txt has the steps.</what-built>
  <how-to-verify>
    1. On the laptop, reset the per-app Windows Graphics setting (and any NVIDIA Control Panel program setting) for mpv_kit_example.exe, noting what it was, so only the in-app preference is tested.
    2. Copy the whole folder to the laptop; run run-probe.bat in the same boot session as the playback runs.
    3. run-auto-log.bat: play the 3840x2160 59.94 fps H.264 file at least 2 minutes, no seeking, window visible; note the play duration and HUD backend, reason (full), dropped, dec-drop, avsync, hwdec, fps; close the demo window normally.
    4. run-d3d11.bat: same, at least 2 minutes, no seeking.
    5. From each log, the `mpv_kit: compositor adapter` line: GTX 960M means the preference worked, HD 530 means it did not.
  </how-to-verify>
  <resume-signal>Reply with, per run (auto, d3d11): play duration, reason full text, dropped, dec-drop, avsync, hwdec, fps and the compositor adapter line; attach mpv_kit_auto_log.txt, mpv_kit_d3d11_log.txt and mpv_kit_d3d11_probe.txt; say what the Windows Graphics / NVIDIA settings were before the reset.</resume-signal>
  <verify><automated>echo "blocking-human: no automated check; the user's reply is the result (recorded later by the orchestrator, L-07)"</automated></verify>
  <acceptance_criteria>
    - The reply contains both runs' reason, dropped, dec-drop, avsync, hwdec values, play durations and the adapter line, plus the log and probe files.
  </acceptance_criteria>
  <done>The user's laptop result for package2 is in hand for the orchestrator.</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| dev machine build -> user's laptop | unsigned Release package copied to and run on another machine |
| user report / log files -> evidence | human-read values and log text become verification input |
| workspace root pubspec.yaml | temporary local bundle user_define during builds |

## STRIDE Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation Plan |
|-----------|----------|-----------|----------|-------------|-----------------|
| T-261029ljp-01 | Tampering | package2 contents | medium | mitigate | every bundle DLL sha256-compared with build/phase14/libmpv-rtx (release run 40812562348); ANGLE audit on plugin and bundle DLLs; sha256 of every desktop file recorded in `## package2` |
| T-261029ljp-02 | Information Disclosure | compositor adapter log line (adapter name, LUID) | low | accept | hardware model and a boot-local LUID only; written to the user's own stderr/log file and sent voluntarily |
| T-261029ljp-03 | Repudiation | laptop verification result | medium | mitigate | launchers write stdout+stderr log files the user sends back; reply asks for raw values and the prior settings state |
| T-261029ljp-04 | Tampering | root pubspec.yaml user_define | medium | mitigate | `git checkout -- pubspec.yaml` right after each build regardless of exit status; gates check `git status --porcelain pubspec.yaml` is empty; stage by explicit path |
| T-261029ljp-05 | Denial of Service | removal of the old desktop package | low | mitigate | `rm -rf --` on the exact literal path only after package2 verification passed and the new path is confirmed different; recorded as `old_package_removed=` |
| T-261029ljp-06 | Elevation of Privilege | unsigned exe and bat launchers on the laptop | low | accept | user's own dev build run as the user; launchers only set one env var and redirect output, no admin rights |
| T-261029ljp-SC | Tampering | npm/pip/cargo installs | high | mitigate | no package installs; Release build uses the pinned workspace pub dependencies and the local bundle |
</threat_model>

<source_audit>
| Source item | Covered by |
|---|---|
| GOAL: hybrid-GPU high-performance adapter for the Windows example | Task 1 steps 2, 6-7 |
| Request 1: set_gpu_preference + flutter#177653 comment (L-01) | Task 1 step 2 |
| Request 1: one adapter log line per D3D11Interop creation, `mpv_kit:` style, desc + LUID hi:lo (L-03) | Task 1 step 3, 7 |
| Request 1: README Windows section + d3d11-backend.md, runner opt-in, 14-10 numbers (L-04) | Task 1 steps 4-5 |
| Request 1: release build, analyze --fatal-infos, plugin flutter test, atomic commit | Task 1 steps 6, 8-9 |
| Decision: no driver-hint exports (L-02) | Task 1 step 2, negative guard in verify |
| Request 2: rebuild like 14-10 Task 1 (relative user_define, revert, bundle_match, pe_audit, debug switches, VC++ runtime, probe reuse) (L-05) | Task 2 steps 1-2, 5 |
| Request 2: local smoke auto + d3d11 with picture, adapter line names RTX 4060 | Task 2 steps 3-4 |
| Request 2: desktop folder with run-probe.bat, run-d3d11.bat, run-auto-log.bat, 使用说明.txt (BOM, CRLF) with reset / 2+ min / duration / report items | Task 2 steps 5-6, package_spec |
| Request 2: delete old 11b728a folder only after verification | Task 2 step 8 |
| Request 2: `## package2` with feat sha, bundle_match, angle_audit, debug_switches_absent, local_smoke, adapter_log, desktop_path, sha256s; commit that file only | Task 2 steps 2-4, 7, 9 |
| Request 3: blocking human checkpoint | Task 3 |
| Excluded: recording the laptop result into 14-10 Task 3 evidence (L-07) | orchestrator, later |
</source_audit>

<verification>
- Task 1 gate: preference call, adapter log in source, Release DLL and a real run; docs updated; analyze and plugin tests green; HEAD commit is exactly the four files; pubspec.yaml clean.
- Task 2 gate (scoped to the `## package2` section): provenance keys yes, adapter line names the RTX 4060 and matches the probe LUID, launchers log, package files and encodings correct, old package removed, evidence-only commit, no unexpected working-tree change.
- Task 3: user reply received.
- Nothing pushed: `git status -sb` shows the branch ahead of origin by the two new commits (plus any already-unpushed ones), never pushed by this task.
</verification>

<success_criteria>
- The example runner requests the high-performance adapter and the plugin reports the compositor adapter once per controller, with no Dart or public API change.
- package2 is on the desktop, verified on this host, traceable, with logging launchers and updated Chinese instructions; the old package is gone; provenance is committed.
- The user's laptop reply (both runs, adapter lines, logs, probe) is available to the orchestrator.
</success_criteria>

<output>
Create `.planning/quick/261029-ljp-hybrid-gpu-high-performance-adapter-for-/261029-ljp-SUMMARY.md` when done (do not commit it; the orchestrator handles quick-task docs).
</output>

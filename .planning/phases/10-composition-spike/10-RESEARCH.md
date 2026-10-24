# Phase 10: Composition Spike - Research

**Researched:** 2026-10-24
**Domain:** Flutter Windows embedder (binary reverse engineering) + Impeller renderer smoke
**Confidence:** HIGH for the engine-source findings (MEDIUM for the two runtime claims that only the smoke can settle)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** 对纹理消费路径做**逐路径反编译到伪代码**，而不是只做符号级定位。报告要能逐点落到 allocation / fence / 设备归属，使 Phase 11 可以直接照着实现。 — **Reversibility:** reversible — 只是文档深度，多做的取证不会约束后续设计。
- **D-02:** 取证对象固定为本机 Flutter 3.47.6 的 `flutter_windows.dll`（与 CI 的 `FLUTTER_VERSION: 3.47.6` 一致），不额外搭建其他版本。 — **Reversibility:** reversible。
- **D-03:** 冒烟**只测锁定的 3.47.6**，不额外试含 #191017 的新引擎。若失败，报告负责记录「升级到哪个版本可能修好、升级的前置条件是什么」，但不代为验证。 — **Reversibility:** reversible。
- **D-04:** 冒烟内容合并为同一次运行的三段（这是 D-03 的 Impeller 范围与 D-06 的判定门槛调和后的结果，不是两个独立任务）：
  1. `create → 渲一帧 → dispose`（最小链路）
  2. 一次 4K 帧
  3. 30 秒连续播放 + 100 轮 resize/dispose 交错

  被明确排除的是「N 分钟稳定性」与「完整 gpu-next→gpu→software 回退矩阵在 Impeller 下的一致性」——那两项留给 Phase 11。
- **D-05:** 判定 Impeller 路径可行的门槛是：**30 秒连续播放 + 100 轮 resize/dispose 交错不崩**。单帧成功不构成可行。 — **Reversibility:** costly — 这个门槛直接决定 Phase 11 是被正式批准还是缩为记录性收口；一旦按「可行」批准，Phase 11 的排期与范围随之锁定，改判需要重走一次决策。
- **D-06:** 若门槛未过，Phase 10 仍算完成：产出「不可行」的证据与所需版本/条件，Phase 11 依此缩为记录性收口（ROADMAP 已允许）。

### Claude's Discretion
- **回退契约与 quarantine 预算**（用户本轮未选择讨论）：运行时 Impeller 路径失败时是静默回退 ANGLE + 发事件，还是显式报错；以及是否在 spike 内实测 compositor 延迟以替换 `quarantine=4`。这两项归属 Phase 11（其成功标准已要求 `backend`/`reason`/HUD 上报与延迟参数化），本阶段不锁定，planner 不应把它们写成 Phase 10 的交付物。

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| COMP-01 | 合成路径 spike 报告——REA 逆向本机 flutter_windows.dll（3.47.6）的纹理消费路径 + Impeller 开关冒烟；决策记录（哪条路径、证据、回退条件） | Findings 1–6 below: verified 3.47.6 artifact acquisition + sha256 (Finding 3), the exact three-level call chain to decompile (Findings 1/3), Impeller-on-by-default (Finding 1), #191017 present in 3.47.6 (Finding 2), harness shape and commands (Finding 5), quarantine evidence to record (Finding 6) |
</phase_requirements>

## Summary

Three facts change this phase from the framing in `.planning/research/SUMMARY.md`, and the planner should build around them:

1. **Impeller is already ON by default on Windows in 3.47.6.** `shell/platform/windows/flutter_windows_engine.cc` at tag 3.47.6 initialises `bool enable_impeller = true;` and only turns it off for an explicit `--enable-impeller=false` switch or `DisabledImpeller`. The example runner uses `flutter::DartProject`, whose `impeller_switch_` defaults to `ImpellerSwitch::Default`. So the smoke is **not** "opt in to Impeller" — it is "prove which renderer is live, then run the workload", with a `--no-enable-impeller` run as the control.
2. **Impeller on Windows is GLES-over-ANGLE, not a D3D backend.** At tag 3.47.6 `impeller/renderer/backend/` contains only `gles`, `metal`, `vulkan`; external textures are consumed by `EmbedderExternalTextureGL::ResolveTextureImpeller`, which casts to `impeller::ContextGLES` and wraps the **same ANGLE-bound GL texture** that the Skia path borrowed. Enabling Impeller therefore removes Skia/Ganesh from the compositor (and the per-resolve `flushAndSubmit()` + `resetContext()`), but it does **not** remove ANGLE from the external-texture handoff. Any decision text claiming "Impeller ⇒ ANGLE-free" must be corrected.
3. **3.47.6 already contains the #191017 fix.** The merge commit `bb8568060d` is not an ancestor of tag 3.47.6, but the source at tag 3.47.6 contains the post-fix code in all three touched files (`embedder_external_texture_gl.cc`, `layer_tree.cc`, `picture.cc`) — it arrived via a different commit (cherry-pick/release-branch merge, mechanism unverified).

**Primary recommendation:** plan four tasks — (a) fetch and pin the 3.47.6 engine artifact by sha256, (b) REA that walks the three-level chain `FlutterWindowsTextureRegistrar::RegisterTexture → ExternalTextureD3d::CreateOrUpdateTexture → EmbedderExternalTextureGL::ResolveTexture{Impeller,Skia}` down to pseudocode, (c) one integration-test file with one `testWidgets` running the D-04 three-part sequence, executed twice (`--enable-impeller` and `--no-enable-impeller`) with the engine's own log line as renderer proof, (d) decision doc that records the ANGLE-still-present conclusion and the Phase 11 conditions.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Binary reverse engineering of `flutter_windows.dll` | Host tooling (Ghidra/REA, offline) | — | Static analysis of a shipped PE; no runtime involvement, no repo code changes |
| Engine-renderer identity proof | Flutter engine (native logs) | Example app (integration test) | Only the engine knows whether Impeller is active; Dart cannot query it |
| Three-part workload | Example app (`example/integration_test/`) | Native plugin + mpv render thread | Reuses the established BENCH harness; exercises the real Flutter texture path |
| Texture production (already built) | Native plugin (`d3d11_interop.cpp`, `video_renderer.cc`) | — | Not modified in Phase 10; the REA aligns engine consumption against it |
| Decision record | Planning docs (`docs/reverse-engineering/03-*`, `docs/adr/0003-*`) | — | Evidence artifact, not code |

---

## Findings

### Finding 1 — Forcing Impeller on Windows 3.47.6, and proving it at runtime

**Is Impeller off by default? No — it is ON.** At tag 3.47.6, `engine/src/flutter/shell/platform/windows/flutter_windows_engine.cc` (lines 195–211) reads:

```cpp
  // Check for impeller support.
  auto& switches = project_->GetSwitches();
  bool enable_impeller = true;
  if (project_->impeller_switch() == FlutterImpellerSwitch::Enabled) {
    enable_impeller = true;
  } else if (project_->impeller_switch() == FlutterImpellerSwitch::Disabled) {
    enable_impeller = false;
  }
  for (const auto& env_switch : switches) {
    if (env_switch == "--enable-impeller" ||
        env_switch == "--enable-impeller=true") {
      enable_impeller = true;
    } else if (env_switch == "--enable-impeller=false") {
      enable_impeller = false;
    }
  }
```

[VERIFIED: raw.githubusercontent.com/flutter/flutter/3.47.6/engine/src/flutter/shell/platform/windows/flutter_windows_engine.cc:195-211]

The example runner never overrides the default: `example/windows/runner/main.cpp` constructs `flutter::DartProject project(L"data");`, and the C++ wrapper defaults `ImpellerSwitch impeller_switch_ = ImpellerSwitch::Default;` (`cpp_client_wrapper/include/flutter/dart_project.h:197`, local SDK 3.47.7; the 3.47.6 header declares the same enum in the same order — `DefaultImpeller, EnabledImpeller, DisabledImpeller`, `flutter_windows.h:73-82` in the downloaded 3.47.6 artifact). [VERIFIED: local `bin/cache/artifacts/engine/windows-x64/cpp_client_wrapper/include/flutter/dart_project.h:197`; VERIFIED: 3.47.6 `flutter_windows.h:73-82`]

**Conclusion:** `Default` → `enable_impeller = true`. The example app is already expected to run Impeller. This is a source-level conclusion; the smoke must confirm it at runtime (see Open Questions).

**How to force it on / off (both commands support the flag):**

- `flutter test` registers `addEnableImpellerFlag` (`packages/flutter_tools/lib/src/commands/test.dart:80`) and plumbs it: `enableImpeller: ImpellerStatus.fromBool(argResults!['enable-impeller'] as bool?)` (test.dart:489) → `DebuggingOptions.enableImpeller` → `desktop_device.dart:297-304` emits `enable-impeller=true|false` into `FLUTTER_ENGINE_SWITCH_n`.
- `ImpellerStatus.fromBool(null) == platformDefault` (`device.dart:924-935`) → **no switch is emitted** → engine default (on).
- `engine_switches.cc` prefixes each env value with `--` and is compiled out under `FLUTTER_RELEASE`, i.e. **only debug/profile honour `FLUTTER_ENGINE_SWITCHES`**. [VERIFIED: 3.47.6 `shell/platform/common/engine_switches.cc`]
- The `--help` text on the flag still says "On other platforms, this flag will be ignored" (`flutter_command.dart:1276-1282`). **That text is stale** — the Windows engine demonstrably reads `--enable-impeller*` (lines above). Do not let the help text talk the plan out of the control run.

**Runtime proof of which renderer is live.** The engine logs, at startup:

```
[IMPORTANT:flutter/shell/platform/embedder/embedder_surface_gl_impeller.cc(126)] Using the Impeller rendering backend (OpenGLESSDF).
```

This exact line is quoted in the #191468 report under plain `flutter run -d windows` [CITED: github.com/flutter/flutter/issues/191468] and the string `"Using the Impeller rendering backend"` **and** `"OpenGLESSDF"` are both present once in the 3.47.6 `flutter_windows.dll` [VERIFIED: grep of the downloaded 3.47.6 DLL]. Capture the full console of the test run to a file and grep for it; the negative control (`--no-enable-impeller`) must *not* print it.

**What does NOT prove the engine renderer:** `mpv_kit_video: <backend> (<reason>)` (`packages/mpv_kit_video/lib/src/video_controller.dart:210`) reports **mpv's** render backend (vulkan/software), never the Flutter engine's. The HUD's `'compositor': 'ANGLE (DxgiSharedHandle)'` (`example/lib/hud.dart:99`) is a hardcoded placeholder until Phase 11 and must not be cited as evidence either. Both are pitfalls below.

**Confidence: HIGH** for the source logic; **UNVERIFIED at runtime** for "the example app currently runs Impeller" — that is exactly what task (c) settles.

---

### Finding 2 — flutter#191468 / PR #191017: signature, fix, and 3.47.6 status

**Issue #191468** (opened 2026-08-21, closed 2026-09-03, labels `e: impeller`, `platform-windows`) [CITED: github.com/flutter/flutter/issues/191468]:

- Reproducer: four `Texture` widgets, `flutter::GpuSurfaceTexture` with `kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle`, D3D11 `DXGI_FORMAT_B8G8R8A8_UNORM` + `D3D11_RESOURCE_MISC_SHARED`, `Flush()` + `MarkTextureFrameAvailable` per frame.
- Failure: process termination with `code=0xc0000005` (ACCESS_VIOLATION), `module=...\flutter_windows.dll, offset=0x2c55f7`, "as soon as the first frames are rendered", under Impeller; identical app is clean with `--no-enable-impeller`.
- Reporter confirmed on 2026-09-03 that **`main` no longer crashes** after #191017 (fix verified by the reporter on main, not on a stable tag).
- The engine log in the report confirms Impeller was the *default* renderer at the time (plain `flutter run`, no flag).

**PR #191017** — "Makes sure impeller context's are plumbed through to `LayerTree::Flatten`", merged 2026-08-17, merge commit `bb8568060d4f8882b4c069f764b74b2ff92993b0`, fixes #190774 [CITED: github.com/flutter/flutter/pull/191017]. Files changed: `flow/layers/layer_tree.{cc,h}` (+ `layer_tree_unittests.cc`), `lib/ui/painting/{display_list_deferred_image_gpu_impeller.cc,picture.cc}`, `lib/ui/snapshot_delegate.h`, `shell/platform/embedder/embedder_external_texture_gl.{cc,h}`, `embedder_external_texture_metal.h`, `tests/embedder_gl_unittests.cc`.

The operative hunks: `LayerTree::Flatten` gained an `impeller::AiksContext*` parameter and sets `.impeller_enabled = !!aiks_context, .aiks_context = aiks_context`; `EmbedderExternalTextureGL::ResolveTexture` gained the `else if (context)` null guard and `ResolveTextureSkia` gained `if (!context) return nullptr;`.

**Does 3.47.6 include it?** `gh api compare/bb8568060d...5fc346839b5d` (tag 3.47.6) returns `status: diverged`, `behind_by: 634` — the merge commit is **not** an ancestor. But the code at tag 3.47.6 is post-fix:

```
67  sk_sp<DlImage> EmbedderExternalTextureGL::ResolveTexture(
72    if (!!aiks_context) {
73      return ResolveTextureImpeller(texture_id, aiks_context, size);
74    } else if (context) {
75      return ResolveTextureSkia(texture_id, context, size);
76    }
77    return nullptr;
...
192      .impeller_enabled              = !!aiks_context,
193      .aiks_context                  = aiks_context,
...
254        auto aiks_context = is_impeller_enabled ...
```

[VERIFIED: 3.47.6 `embedder_external_texture_gl.cc:67-88`, `layer_tree.cc:151/192-193`, `picture.cc:195-263`]

**Conclusion:** the fix's *content* is in 3.47.6 via a non-ancestor commit (cherry-pick or release-branch merge; the exact commit is unverified). This **supersedes** `.planning/research/SUMMARY.md`'s "PR #191017 修复于 main，3.47.6 未验证" — 3.47.6 is now verified by source. The smoke should record this so the decision doc does not repeat the stale premise.

**What the smoke must capture to be comparable to #191468** (the offset `0x2c55f7` is 3.47.0-specific — never grep for it):

1. The engine renderer log line (Impeller vs not).
2. Whether the process died by native exception (`0xC0000005`) and the module + offset **as reported**.
3. The stage: after N frames / during resize / during dispose / during texture acquire.
4. WER evidence: exit code of `flutter test`, plus a lookup of `%LOCALAPPDATA%\CrashDumps` and the Application event log for `Application Error` naming `flutter_windows.dll`.
5. The texture count (our app uses **one**; the issue used four) — a non-crash on one texture is a scope difference, not proof the bug is gone.

**Confidence: HIGH.**

---

### Finding 3 — REA entry points into `flutter_windows.dll` (artifact, symbols, anchors)

**Target artifact — verified, exact, downloadable:**

```
Engine revision for tag 3.47.6: 692136cb6582dbfc5af3fb33c2515a069f2f66d0
URL: https://storage.googleapis.com/flutter_infra_release/flutter/692136cb6582dbfc5af3fb33c2515a069f2f66d0/windows-x64-debug/windows-x64-flutter.zip
Size: 86,256,529 bytes
Contents: flutter_windows.dll (46,621,696 B, 2026-09-29 18:34)
          flutter_windows.dll.pdb (278,671,360 B, same timestamp)
sha256(flutter_windows.dll) = e25ba971353d0f285a11814f2fa3d8351d097778ae5b7286351dad4d00a70ac5
```

[VERIFIED: HTTP 200 + `unzip -l` + `sha256sum`, this session]

The zip name comes from the tool's own manifest: `_getWindowsDesktopBinaryDirs` maps `windows-$arch` ← `windows-$arch-debug/windows-$arch-flutter.zip` (`packages/flutter_tools/lib/src/flutter_cache.dart:876-883`). The `windows-x64/artifacts.zip` (30.5 MB) does **not** contain the DLL — do not fetch that one.

**Where it lands in a real SDK install:** `bin/cache/artifacts/engine/windows-x64/flutter_windows.dll` (+ `.pdb`), per the observed 3.47.7 layout. The phase does **not** need a full 1.93 GB SDK install for the REA; the zip above is sufficient and is byte-identical to what `flutter precache` would place there. (A full SDK *is* needed to **run** the smoke on 3.47.6 — see Finding 5.)

**Symbols: present, not stripped.** Both the debug DLL and its PDB ship in the zip; the local 3.47.7 install likewise has a 278 MB PDB next to the DLL. Ghidra's PDB analyzer is the right entry (this is exactly how `docs/reverse-engineering/02-...` was produced). Ghidra 12.1.4 headless is installed at `D:\ghidra_12.1.4_PUBLIC\support\analyzeHeadless.bat`. A 46.6 MB PE with a matching PDB is routine; size is not a blocker.

**Anchor strings — all verified present exactly once in the 3.47.6 binary** (grep of the extracted DLL):

| Anchor | Meaning | Source of truth (tag 3.47.6) |
|---|---|---|
| `Only support GL_RGBA8 format now` | Impeller rejects non-RGBA8 external textures | `embedder_external_texture_gl.cc:154` |
| `Could not create external texture` | `TextureGLES::WrapTexture` failure | `:170` |
| `Could not register destruction callback` | reactor cleanup registration failure | `:187` |
| `Binding D3D surface failed.` | ANGLE `eglBindTexImage` failure | `shell/platform/windows/external_texture_d3d.cc:107` |
| `Using the Impeller rendering backend` / `OpenGLESSDF` | renderer identity at runtime | `embedder_surface_gl_impeller.cc` |
| `EmbedderExternalTextureGL` | RTTI/type-name string | — |

`ExternalTextureD3d` is **not** present as a string in the binary — do not anchor on that class name; anchor via the PDB symbol table and the two log strings instead. [VERIFIED: grep of the downloaded 3.47.6 DLL]

Also useful as xref anchors: `eglBindTexImage`, `eglCreatePbufferSurface` (present as strings) and `dxgi.dll` (imported). `libEGL.dll`, `libGLESv2.dll`, `IDXGIKeyedMutex`, `OpenSharedResource` are **absent as strings** — evidence that ANGLE is linked into `flutter_windows.dll` rather than loaded as a side-by-side DLL, which means the D3D11 interop inside ANGLE is in scope for this same binary. That is good for the fence question and bad for effort estimate; see Open Questions.

**The three-level chain to decompile** (each level is a distinct REA path; D-01 requires pseudocode for all three):

1. **Registration** — `shell/platform/windows/flutter_windows_texture_registrar.cc:26-62`: `kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle` / `...D3d11Texture2D` → `EmplaceTexture(std::make_unique<flutter::ExternalTextureD3d>(...))`.
2. **Production / ANGLE bind** — `shell/platform/windows/external_texture_d3d.cc:32-117`: `PopulateTexture` sets `target = GL_TEXTURE_2D`, `name = gl_texture_`, `format = GL_RGBA8_OES`, `destruction_callback = nullptr`, `user_data = nullptr`; `CreateOrUpdateTexture` calls `egl_manager_->CreateSurfaceFromHandle(...)` → `egl::Manager::CreateSurfaceFromHandle` → `::eglCreatePbufferFromClientBuffer(display_, handle_type, handle, config_, attributes)` with `EGL_D3D_TEXTURE_ANGLE` for `D3d11Texture2D` and `EGL_D3D_TEXTURE_2D_SHARE_HANDLE_ANGLE` otherwise, then `eglBindTexImage(..., EGL_BACK_BUFFER)`, then **immediately** `release_callback(release_context)` (lines 112–115). [VERIFIED: 3.47.6 sources; `egl/manager.cc:317-322`]
3. **Consumption** — `shell/platform/embedder/embedder_external_texture_gl.cc:67-194`: `ResolveTexture` → `ResolveTextureImpeller` (Impeller live) or `ResolveTextureSkia`. Impeller: `ContextGLES::Cast(*aiks_context->GetContext())`, `CreateHandle(kTexture, texture->name)`, `TextureGLES::WrapTexture`, `RegisterCleanupCallback`, `DlImageImpeller::Make`. Skia: `context->flushAndSubmit(); context->resetContext(kAll_GrBackendState);` then `SkImages::BorrowTextureFrom(...)`.

**What the REA tooling needs as input:** the `flutter_windows.dll` PE (and its PDB for symbol names). The session's REA toolchain (`analyze_function`, `search_strings`, `xrefs`, `procedure_pseudo_code`, `search_procedures`) operates on an opened binary target; there is no special container format. **Unverified in this session:** the REA MCP tools were not available to me, so I could not confirm their exact accepted inputs or whether they consume the PDB automatically. The planner should treat "open the PE, confirm symbols resolved" as task step zero rather than an assumption.

**Confidence: HIGH** for paths/anchors/hashes; **UNVERIFIED** for the REA tool's precise input contract.

---

### Finding 4 — What `docs/reverse-engineering/02` already settles (do not re-derive)

| Question | Already answered? | Answer | Where |
|---|---|---|---|
| Do both surface types go through ANGLE? | Yes | Both bind via `eglCreateSurfaceFromHandle` + `eglBindTexImage`; the type only selects the EGL enum | doc 02 §`CreateOrUpdateTexture`; confirmed at `external_texture_d3d.cc:98-106` |
| Is it re-bound every frame? | Yes | Only when the handle changes (`handle != last_surface_handle_`); otherwise the existing surface is reused | `:84-110` |
| Is there a fence / keyed mutex / query? | Yes (Skia path) | None. `release_callback` is called immediately after bind and does not mean "done reading" | doc 02; `:112-115` |
| Who owns the DXGI device? | Partially | `mpv_kit` creates its **own** D3D11 device on Flutter's adapter (`d3d11_interop.cpp:34-40`); Flutter opens the KMT handle on its device. ANGLE's device internals not examined | doc 02; `d3d11_interop.h` |
| What quarantine follows? | Yes | Windows 4 (ring 7), per `CompositorLatency()` | doc 02 §Consequences; `d3d11_interop.h:35` |
| Is the keyed-mutex pbuffer path used? | **No** | Explicitly listed as "not verified yet" | doc 02, last paragraph |

**What doc 02 does NOT cover (the delta Phase 10 must add):**
- The **Impeller** consumption path (`ResolveTextureImpeller`) — doc 02 predates the realisation that Impeller is the default. This is the single biggest gap.
- The `TextureGLES::WrapTexture` + `RegisterCleanupCallback` lifetime semantics (when Impeller's reactor frees the wrapped handle) versus Skia's `SkImage` release proc.
- The absence of `flushAndSubmit()`/`resetContext()` in the Impeller path — a behavioural difference with performance consequences.
- Pseudocode (D-01 exceeds doc 02's symbol-level narrative), with per-path allocation / fence / device-ownership annotations.

**Confidence: HIGH** (doc read verbatim; sources re-verified at tag 3.47.6).

---

### Finding 5 — Smoke harness shape (existing patterns, parameters, gotchas)

**Use a new file, not the existing ones.** `example/integration_test/` has `playback_bench_test.dart`, `uhd_endurance_test.dart`, `seek_recovery_test.dart`, `real_plugin_test.dart`. Reusing them would co-mingle D-05's workload with unrelated gates (drops, avsync) that are not Impeller criteria — and `playback_bench_test.dart:10-13` documents a hard constraint: **sequential `testWidgets` in one file leave the binding in a state where later tests hang**. Recommendation: `example/integration_test/impeller_smoke_test.dart`, `@TestOn('windows')`, **one** `testWidgets`, three parts inside one `tester.runAsync`.

**Established parameters (quoted from `uhd_endurance_test.dart:5-8`):**

```
//   MPV_KIT_BENCH_SIZE    WxH      (default 3840x2160)
//   MPV_KIT_BENCH_SECONDS duration (default 1800)
//   MPV_KIT_BENCH_LABEL   run name for the BENCH line (default uhd)
```

Plus `MPV_KIT_LIBMPV_PATH`, `PATH`, and `MPV_KIT_VIDEO_RENDERER` (forces mpv's renderer, `video_controller.dart:163-166`). None of these controls the **engine** renderer — that is the new `--enable-impeller` / `--no-enable-impeller` axis. Report through `print('BENCH <name> {json}')` — the established channel (`playback_bench_test.dart:15`), because integration tests have no logger.

**Exact commands** (run from `example/`; debug build; visible window; **not** minimized):

```bash
LIB="D:/mpv_kit/.dart_tool/hooks_runner/shared/mpv_kit_libs/build/v0.1.0-dev.3/windows-x64/lib"

# Impeller live (explicit, though it is already the default) — primary run
MPV_KIT_LIBMPV_PATH="$LIB/libmpv-2.dll" PATH="$PATH:$LIB" \
  flutter test integration_test/impeller_smoke_test.dart -d windows \
  --enable-impeller 2>&1 | tee /tmp/impeller-on.log

# Control run: same binary, Impeller disabled
MPV_KIT_LIBMPV_PATH="$LIB/libmpv-2.dll" PATH="$PATH:$LIB" \
  flutter test integration_test/impeller_smoke_test.dart -d windows \
  --no-enable-impeller 2>&1 | tee /tmp/impeller-off.log

grep -c "Using the Impeller rendering backend" /tmp/impeller-on.log   # expect >= 1
grep -c "Using the Impeller rendering backend" /tmp/impeller-off.log  # expect 0
```

The control run is cheap and is the only thing that separates "Impeller defect" from "environment/harness defect" — see Pitfalls.

**Local libmpv gotcha (restate it in the plan).** `MpvLibrary.open` tries explicit path → `MPV_KIT_LIBMPV_PATH` → platform default names, and **falls through on failure** (`packages/mpv_kit/lib/src/ffi/library.dart:66-96`). On Windows there is no rpath, so pointing `MPV_KIT_LIBMPV_PATH` at a DLL whose dependency DLLs are not on `PATH` does **not** fail loudly: it quietly loads a different `libmpv-2.dll` found by the OS loader. The seams exist — `MpvLibrary.resolvedPath` and `MpvLibrary.lastOpenAttempts` (documented as the "Phase 1 wrong-DLL incident class"). **The smoke must assert `MpvLibrary.resolvedPath == Platform.environment['MPV_KIT_LIBMPV_PATH']` before it measures anything**, otherwise a software-fallback run gets recorded as an Impeller result.

Second half of the gotcha: `docs/perf/2026-10-24-baseline.md:5` warns the old `bt/libmpv-2.dll` "lacks the working Vulkan render path and falls back to software; do not use it for these benches." Use the hooks_runner bundle path above.

**D-04 three-part sequence inside the single test:**

| Part | Shape | Evidence it actually happened |
|---|---|---|
| 1. create → one frame → dispose | `MpvVideoController.create(player)`, open a short lavfi source, wait until `estimated-vf-fps > 0` and one `resize` event, `controller.dispose()` | `estimated-vf-fps` (mpv produced frames) + `resize` event (ring allocated) — note this does **not** prove Flutter composited; the visible window plus absence of crash is the composition evidence |
| 2. one 4K frame | `setSize(3840, 2160)` or open a 3840x2160 lavfi source; wait for `videoParams.width == 3840`, hold ~2 s | `videoParams` + `resize` event |
| 3. 30 s continuous + 100 resize/dispose rounds | keep playback running; 100 rounds of {`setSize` to an alternating size, dispose + recreate the controller against the **same live Player**}, paced so the rounds span ≥ 30 s (≈250–300 ms each); if the rounds finish early, keep playing until 30 s elapsed | `BENCH` JSON: rounds completed, elapsed seconds, `renderErrors`, `deviceLost`, `MpvVideoEventKind` histogram, `ProcessInfo.currentRss` |

Pacing note: D-05 requires **both** conditions, not throughput. Pacing 100 rounds across ~30 s is the simplest way to satisfy "interleaved" without inventing a timing gate that D-04 never asked for.

**Suggested BENCH schema** (one line, parseable, mirrors existing runs):

```json
BENCH impeller {"engineRenderer":"impeller","switch":"enabled","resolvedLibmpv":"...",
 "parts":{"oneFrame":"ok","uhd4k":"ok","soak":"ok"},
 "rounds":100,"seconds":30.4,"resizeEvents":100,"renderErrors":0,"deviceLost":false,
 "rssStart":...,"rssEnd":...,"result":"pass"}
```

**Confidence: HIGH** for the harness mechanics (all quoted from repo code); **MEDIUM** for whether the engine log line is forwarded by `flutter test -d windows` — unverified, see Open Questions.

---

### Finding 6 — Quarantine / compositor latency: current value, and what Phase 10 must *not* measure

Current values, quoted verbatim:

- Windows: `int CompositorLatency() const override { return 4; }` — [VERIFIED: `packages/mpv_kit_video/windows/d3d11_interop.h:35`]
- Cap: `static constexpr int kMaxQuarantine = 4;` — [VERIFIED: `packages/mpv_kit_video/src/video_renderer.h:212`]
- Defaults for the other platforms: `int quarantine_count_ = 2;` and `int ring_size_ = 5;` — [VERIFIED: `packages/mpv_kit_video/src/video_renderer.h:215-216`]
- Ring formula: `front + in use + quarantine + one free image` → 7 slots on Windows — [VERIFIED: `video_renderer.h:210`, `docs/ARCHITECTURE.md:102-107`]

The 4 is derived from "DXGI default frame latency 3 + the frame being composed" (`d3d11_interop.h:30-34` comment), not measured.

**Phase 10 does not measure this.** CONTEXT's Claude's-Discretion section puts parameterisation in Phase 11, and D-04/D-05 do not mention latency. What Phase 10 *must* do is record the **hypothesis to be tested**, because Finding 1 changes the premise:

- The 4 was inherited from the Skia path, where every resolve does `flushAndSubmit()` + `resetContext(kAll_GrBackendState)`. Note what that is *not*: `flushAndSubmit` submits work and returns — it does not wait for the GPU — so even under Skia the 4 was a heuristic about DXGI queue depth, never a synchronisation guarantee.
- The Impeller path performs **no flush and no context reset** on resolve (`embedder_external_texture_gl.cc:135-194`); the GL texture is wrapped and a reactor cleanup callback is registered. If Impeller's GLES command buffer defers submission across frames, the ANGLE sampling of our D3D texture could occur later than the Skia-era bound.
- Therefore "quarantine 4 remains correct under Impeller" is **unproven** and belongs in the decision doc as an explicit Phase 11 measurement item (mirrors `.planning/research/SUMMARY.md` P3: "无 fence 生命周期的安全预算按路径实测").

**Confidence: HIGH** for the values; the deferral hypothesis is stated as a hypothesis, not a finding.

---

## Validation Architecture

> `workflow.nyquist_validation` is `true` in `.planning/config.json` — included.

This phase has three verifiable artifacts (REA report, smoke result, decision doc) and **no new application code**. Validation is therefore evidence review plus one executable harness.

### Test Framework

| Property | Value |
|----------|-------|
| Framework | `integration_test` + `flutter_test` (already a dev dependency in `example/pubspec.yaml`) |
| Config file | none — the harness is the test file itself |
| Quick run command | `flutter test integration_test/impeller_smoke_test.dart -d windows --enable-impeller` (with the env prefix from Finding 5) |
| Full suite command | quick run + the `--no-enable-impeller` control run |

### Phase Requirements → Test Map

| Req ID | Behavior | Verification Type | Automated Command | File Exists? |
|--------|----------|-------------------|-------------------|--------------|
| COMP-01(a) | REA report pins the 3.47.6 binary and answers ANGLE / device-owner / fence per path | Review checklist + hash check | `sha256sum <dll>` must equal `e25ba971...70ac5` | ❌ Wave 0: `docs/reverse-engineering/03-*.md` |
| COMP-01(b) | Impeller smoke: 3-part run, viability bar met or refuted | integration (real window) | the command above | ❌ Wave 0: `example/integration_test/impeller_smoke_test.dart` |
| COMP-01(c) | Decision doc names path, evidence, fallback conditions | Review checklist | — (manual) | ❌ Wave 0: `docs/adr/0003-*.md` |
| Regression guard | Contract suite still green (no public API change) | unit | `cd packages/mpv_kit && dart test` | ✅ |

### Sampling Rate
- **Per task commit:** `dart analyze --fatal-infos` in the touched package (the smoke file lives in `example/`).
- **Per wave merge:** the full smoke pair (on + off) — the control run is not optional, it is the discriminator.
- **Phase gate:** REA report review + both smoke logs + decision doc before `/gsd-verify-work`.

### Wave 0 Gaps
- [ ] `example/integration_test/impeller_smoke_test.dart` — covers COMP-01(b)
- [ ] `docs/reverse-engineering/03-flutter-windows-texture-consumption.md` — covers COMP-01(a)
- [ ] `docs/adr/0003-windows-composition-path.md` (numbering: `docs/adr/` currently ends at `0002-lgpl-self-built-binaries.md`) — covers COMP-01(c)
- [ ] 3.47.6 engine artifact fetched and sha256 recorded in the REA report header

---

## Pitfalls

1. **"I passed `--enable-impeller`, so Impeller is on."** It is on by default; the flag proves nothing. Only the engine log line (`Using the Impeller rendering backend (OpenGLESSDF)`) and its absence in the control run are evidence. This is the "Impeller silently staying off" trap inverted — here it is "Impeller silently already on, and the run is misdescribed".
2. **Mistaking the HUD/renderer log for engine evidence.** `mpv_kit_video: <backend> (<reason>)` is mpv's renderer. `example/lib/hud.dart:99` hardcodes `'compositor': 'ANGLE (DxgiSharedHandle)'`. Neither may be cited as proof of the Flutter engine's renderer.
3. **Phase 9 lesson — a harness failure with no `BENCH` line is not evidence about the renderer.** An exception before the `print('BENCH ...')` (missing libmpv, wrong resolved DLL, no visible window, test-binding hang) must be classified as `inconclusive`, never as "Impeller crashed". Design the harness so the BENCH line is emitted *before* the gates, and so the run's classification is `pass | renderer-crash | inconclusive` — D-06 needs the third bucket.
4. **Silent libmpv fallback.** `MPV_KIT_LIBMPV_PATH` failing falls through to OS default names (`library.dart:66-96`). A software-backend run would look like an Impeller result. Assert `MpvLibrary.resolvedPath`.
5. **Wrong DLL under the microscope.** The local SDK is **3.47.7** (verified: `flutter --version`, `bin/cache/flutter.version.json`), not 3.47.6. D-02 forbids substituting it. Download the 3.47.6 artifact by exact URL and verify `sha256 = e25ba971…70ac5` before decompiling.
6. **Wrong zip.** `windows-x64/artifacts.zip` (30.5 MB) has no DLL/PDB. The DLL is in `windows-x64-debug/windows-x64-flutter.zip` (86 MB).
7. **Chasing the issue's offset.** `0x2c55f7` is 3.47.0-specific. Compare stage and exception code, not offsets.
8. **Sequential `testWidgets` hang.** Documented in `playback_bench_test.dart:10-13`. One `testWidgets` per file.
9. **Minimized window.** Triggers the renderer's idle path (`video_renderer.h:168-171`, `kIdleTimeout{500}`) and invalidates "30 s continuous". Keep the window visible; state it in the runbook.
10. **Impeller's format check is a cliff.** `ResolveTextureImpeller` returns null with `Only support GL_RGBA8 format now` when `texture->format != GL_RGBA8`. Today `ExternalTextureD3d` sets `GL_RGBA8_OES`; both macros are `0x8058` [CITED: Khronos `GLES2/gl2ext.h` and `GLES3/gl3.h`], so the check passes. Any future surface-format change would produce a **silent black texture**, not a crash — the smoke must assert a non-black frame is actually composited, not merely that the process survived.
11. **Dispose ordering.** `controller.dispose()` before `player.dispose()` (the 100 recycles must follow `playback_bench_test.dart:142-146`: stop playback, dispose the controller, recreate against the same `Player`). Violating it makes libmpv wait/fail (`docs/ARCHITECTURE.md:76-90`).
12. **Env-switch scope.** `FLUTTER_ENGINE_SWITCHES` is compiled out in release builds (`engine_switches.cc`). All smoke runs must be debug builds; a profile/release run would silently ignore the switch.
13. **Reading the decision from the smoke alone.** Finding 1 (ANGLE remains) is a source-level conclusion independent of the smoke's verdict. If the smoke passes, that does not make the path ANGLE-free; if it fails, that does not mean ANGLE is the alternative engine version's problem. Keep the two evidence streams separate in the decision doc.

---

## Open Questions

1. **Is the engine renderer log line forwarded by `flutter test -d windows`?**
   What we know: it appears in `flutter run` console output (issue #191468's log), and the strings exist in the 3.47.6 DLL.
   What's unclear: whether the integration-test runner surfaces the app process's stderr the same way.
   What settles it: task (c) executes once and greps the captured log. Fallback if absent: run the same three parts under `flutter run -d windows --enable-impeller` for the log line, or compare behaviour between the two switch settings as weaker evidence.

2. **Is the example app in fact running Impeller today?**
   What we know: the engine default is `true`; `DartProject::impeller_switch_` defaults to `Default`; the runner never overrides it.
   What's unclear: runtime confirmation — and, if Impeller has been live all along, whether previous Phase 7–9 benchmark numbers were measured under Impeller (which would make the "Skia baseline" in docs an artefact of the analysis, not of the runtime).
   What settles it: the log grep in task (c), plus a note in the decision doc that historical bench numbers' renderer is unrecorded.

3. **Is ANGLE statically linked into `flutter_windows.dll`?**
   What we know: `libEGL.dll` / `libGLESv2.dll` strings are absent; `eglBindTexImage` / `eglCreatePbufferSurface` are present; `dxgi.dll` is imported while `d3d11.dll` did not match a grep.
   What's unclear: whether the D3D11 interop code (and its synchronization) lives inside this PE, which determines how much of the fence question the REA can answer from this single artifact.
   What settles it: the REA's import-table dump and xref walk (task a). If ANGLE is statically linked, budget extra effort and cite ANGLE's public source for the `DisplayD3D`/`SurfaceD3D` semantics rather than fully decompiling it.

4. **Does Impeller's GLES backend defer submission enough to invalidate `quarantine = 4`?**
   Explicitly a Phase 11 measurement (Finding 6). Phase 10 records the hypothesis and the values; it must not spend effort measuring latency.

5. **Which commit carried #191017 into 3.47.6?**
   What we know: the merge commit is not an ancestor; the code is present at the tag.
   What's unclear: the cherry-pick SHA. Not needed for the decision, only for the REA report's provenance footnote. `git log --all --oneline -- <file>` in a Flutter checkout would settle it if the report wants to be exhaustive.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|---|---|---|---|---|
| Ghidra (headless) | REA decompilation | ✓ | 12.1.4 (`D:\ghidra_12.1.4_PUBLIC\support\analyzeHeadless.bat`) | Manual decompilation — not viable at D-01 depth |
| Flutter SDK 3.47.6 | Smoke + REA target | ✗ | local is **3.47.7** | Download the 86 MB `windows-x64-debug/windows-x64-flutter.zip` for the REA; full SDK zip (`flutter_windows_3.47.6-stable.zip`, 1.93 GB, sha256 `a01bb0d26de91bc23c97cd9ccfaad281a612fb8304213fdd5df1119a09404796`) to *run* the smoke on 3.47.6 |
| Flutter SDK 3.47.7 | Current local builds/tests | ✓ | 3.47.7 (Dart 3.13.5) | — |
| Python 3 | `tools/rea_abi_audit/pe_audit.py`, small JSON/file chores | ✓ | 3.x (used this session) | — |
| libmpv bundle | Smoke run | ✓ (expected) | `v0.1.0-dev.3` under `.dart_tool/hooks_runner/shared/mpv_kit_libs/build/...` | `MPV_KIT_LIBMPV_PATH` override (must be verified via `resolvedPath`) |
| Vulkan 1.3 driver | mpv render backend | ✓ (Phase 7–9 ran on this host) | — | software renderer — but then the smoke is not testing the same path; record as inconclusive |
| Visible desktop session | All three smoke parts | required | — | none; headless/CI runners are unsuitable for D-04/D-05 |

**Missing dependencies with no fallback:** none that blocks execution.

**Missing dependencies with fallback:** 3.47.6 SDK (fallback = download the exact artifact zip for the REA; the full SDK is required only for the runtime smoke, and D-03 forbids substituting 3.47.7 for the smoke).

---

## Standard Stack / Don't Hand-Roll

This phase installs **no packages** — it adds one integration-test file and two documents. `## Package Legitimacy Audit` therefore does not apply (no new registry dependencies).

| Problem | Don't Build | Use Instead | Why |
|---|---|---|---|
| Binary analysis | A custom PE/CFG disassembler | Ghidra 12.1.4 headless + the shipped PDB | Symbols are available; hand-rolled analysis cannot produce callable pseudocode at D-01 depth |
| Renderer smoke harness | A new driver/runner app | `example/integration_test/` with the existing BENCH convention | The window, plugin registration, and libmpv wiring already work; a new harness re-introduces every solved failure mode |
| Engine-renderer detection | Reading `mpv_kit_video` logs / HUD | The engine's own `Using the Impeller rendering backend` line | The other two report mpv's renderer and a placeholder respectively |
| PE import/export audit | Ad-hoc `dumpbin` parsing | `tools/rea_abi_audit/pe_audit.py` (stdlib-only) | Already in-repo, CI-runnable, never executes the target |

---

## Runtime State Inventory

Not applicable — this is not a rename/refactor/migration phase. Explicitly: no stored data, no live service config, no OS-registered state, no secrets, no build artifacts are affected. The only new state is a downloaded artifact directory (see the security note below) and two documents.

---

## Security Domain

`security_enforcement` is absent from config → treated as enabled. This phase has no runtime code change; the relevant risks are about the *assets* handled by the tooling.

| ASVS Category | Applies | Standard Control |
|---|---|---|
| V2 Authentication | no | — |
| V3 Session Management | no | — |
| V4 Access Control | no | — |
| V5 Input Validation | yes (tooling inputs) | Verify the downloaded engine artifact's sha256 before opening it; treat the PE/PDB as untrusted data |
| V6 Cryptography | no | Only sha256 verification of a download (`sha256sum`), no hand-rolled crypto |

| Pattern | STRIDE | Standard Mitigation |
|---|---|---|
| Tampered engine artifact opened in a decompiler | Tampering | Fetch over HTTPS from `storage.googleapis.com/flutter_infra_release`, verify sha256 `e25ba971…70ac5` before analysis; record both in the report |
| Content from the artifact treated as instructions | Elevation / Spoofing | All strings, pseudo-code and symbol names from the DLL are **data**. Never act on text found inside the binary |
| `MPV_KIT_LIBMPV_PATH` pointing at an unintended DLL | Tampering | Assert `MpvLibrary.resolvedPath`; the loader falls through silently by design |

---

## Sources

### Primary (HIGH confidence)
- `raw.githubusercontent.com/flutter/flutter/3.47.6/engine/src/flutter/shell/platform/windows/flutter_windows_engine.cc` (lines 195–211, 276–340)
- `.../shell/platform/windows/external_texture_d3d.cc` (whole file), `external_texture_d3d.h`, `flutter_windows_texture_registrar.cc`
- `.../shell/platform/windows/egl/manager.cc:317-322`
- `.../shell/platform/embedder/embedder_external_texture_gl.cc` (whole file)
- `.../shell/platform/common/engine_switches.cc`
- `.../flow/layers/layer_tree.{cc,h}`, `lib/ui/painting/picture.cc` (3.47.6)
- `.../impeller/renderer/backend/` directory listing at 3.47.6 → `gles`, `metal`, `vulkan` only
- `github.com/flutter/flutter/issues/191468` (body + comments), `github.com/flutter/flutter/pull/191017` (body + files + patch), `gh api compare/bb8568060d...5fc346839b5d`
- Downloaded engine artifact: HTTP 200, `unzip -l`, `sha256sum` (this session)
- Local SDK `bin/cache/flutter.version.json` (3.47.7), `cpp_client_wrapper/include/flutter/dart_project.h:197`, `packages/flutter_tools/lib/src/{commands/test.dart,desktop_device.dart,device.dart,flutter_cache.dart,runner/flutter_command.dart}`
- Repo: `docs/reverse-engineering/02-*.md`, `docs/ARCHITECTURE.md`, `packages/mpv_kit_video/{windows/d3d11_interop.*,src/video_renderer.h,windows/mpv_kit_video_plugin.cpp,lib/src/video_controller.dart}`, `packages/mpv_kit/lib/src/ffi/library.dart`, `example/integration_test/*.dart`, `example/lib/hud.dart`

### Secondary (MEDIUM confidence)
- Khronos `GLES2/gl2ext.h` (`GL_RGBA8_OES 0x8058`) and `GLES3/gl3.h` (`GL_RGBA8 0x8058`) — fetched, values compared

### Tertiary (LOW confidence / explicit non-claims)
- The exact cherry-pick commit that delivered #191017 into 3.47.6 — **unverified**
- Whether `flutter test -d windows` forwards the engine log line — **unverified**
- The REA MCP tools' precise input contract — **not exercised this session**

---

## Metadata

**Confidence breakdown:**
- Impeller default / disable path: **HIGH** — engine source at the exact tag, plus tool plumbing read locally
- Impeller-on-Windows = GLES-over-ANGLE: **HIGH** — backend directory listing, consumer source, and the engine's own runtime log string
- #191017 present in 3.47.6: **HIGH** for content, **LOW** for the delivery commit
- REA artifact acquisition: **HIGH** — downloaded, hashed, string-checked
- Smoke harness shape: **HIGH** for mechanics, **MEDIUM** for log forwarding
- Quarantine guidance: **HIGH** for values, hypothesis clearly flagged

**Research date:** 2026-10-24
**Valid until:** 2026-11-23 (stable engine artifacts; the flutter#191468/#191017 facts are historical and will not drift)

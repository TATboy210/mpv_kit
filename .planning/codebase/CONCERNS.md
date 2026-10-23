---
last_mapped_commit: 9f90a45322ab3537941540e6b35a76d978669ef5
last_mapped_at: 2026-10-23
---
# Codebase Concerns

**Analysis Date:** 2026-10-23

Scope: full repo (`packages/mpv_kit`, `packages/mpv_kit_video`, `packages/mpv_kit_libs`,
`example`, `native/`, `tools/`, CI). `native/mpv` is a vendored mpv source tree
(963 tracked files) and is covered only where mpv_kit modifies or depends on it.

## Tech Debt

**Vendored mpv tree plus a downstream-only patch series:**
- Issue: the repository embeds a full mpv snapshot (`native/mpv`, 17 MB, 963 files) and
  carries seven patches (`native/patches/*.patch`, 1,851 lines) that are rebased by
  hand. `native/patches/UPSTREAM.md` records that upstreaming is not planned.
- Files: `native/mpv/MPV_VERSION` (`v0.41.0-1113-gfd9265a905`), `native/patches/`,
  `native/patches/UPSTREAM.md`, `native/build/build.sh`
- Impact: every mpv security or API update is a manual rebase of 0001–0007, including
  conflicting gpu-next refactors. Release builds depend on this tree compiling cleanly
  with `--fatal-infos`/`/WX`-style settings.
- Fix approach: keep `UPSTREAM.md` current per rebase; add a CI job that applies the
  patch series to a fresh upstream tarball and runs the ABI audit + smoke tests, so
  rebases are exercised before release.

**Generated artifacts are stale relative to the vendored source:**
- Issue: `packages/mpv_kit/lib/src/generated/options.dart` says it was generated from
  `mpv v0.41.0-689-g9e06c3248`, while `native/mpv/MPV_VERSION` is
  `v0.41.0-1113-gfd9265a905`. The option/catalog tables therefore do not describe the
  source tree that actually ships.
- Files: `packages/mpv_kit/lib/src/generated/options.dart:1`,
  `native/mpv/MPV_VERSION`, `tools/gen_options.dart`, `tools/gen_catalog.dart`
- Impact: typed `MpvOptions` can miss options added upstream and can contain options
  removed since the generation run. Runtime failures are partly softened by ignoring
  `optionNotFound` in `packages/mpv_kit/lib/src/core/mpv.dart:66-77`, but generated docs
  and type information mislead users.
- Fix approach: regenerate both artifacts in the same commit as every mpv rebase and add
  a CI check that compares the generated header/version with `MPV_VERSION`.

**Vendored prebuilt DLLs committed to git:**
- Issue: `bt/` contains 22 Windows DLLs (38 MB) including `bt/libmpv-2.dll`, with no
  manifest, checksum, license note, or regeneration script in the repo. They are not
  referenced by CI or docs except a diagram.
- Files: `bt/` (22 tracked files), `docs/ARCHITECTURE-diagrams.md:32`
- Impact: binary supply-chain surface and repository bloat; it is impossible to tell
  which mpv/FFmpeg commit or configuration produced these DLLs, and they can silently
  drift from the shipped bundles.
- Fix approach: remove `bt/` from version control (document a download/generation
  procedure), or add a `MANIFEST.txt` with sha256 plus the producing release tag and use
  it only for local debugging.

**Large generated files with an unusual regeneration workflow:**
- Issue: `options.dart` (7,617 lines) and `catalog.dart` (4,346 lines) are committed and
  can only be regenerated with a working libmpv in the environment; `gen_options.dart`
  imports the package being generated.
- Files: `packages/mpv_kit/lib/src/generated/`, `tools/gen_options.dart:1-17`
- Impact: contributors cannot regenerate safely without a bundled libmpv, encouraging
  hand edits or stale data. Both files are excluded from normal review value.
- Fix approach: document a pinned regeneration command (`MPV_KIT_LIBMPV_PATH=...`) and
  wire it into the release workflow as a diff check.

**Duplicated symbol-order contract between Dart and C++:**
- Issue: `MpvVideoController._symbols` must match the field order in `MpvApi` and
  `kSymbolCount` exactly, but the only enforcement is a comment and a count check.
- Files: `packages/mpv_kit_video/lib/src/video_controller.dart:127-138`,
  `packages/mpv_kit_video/src/mpv_api.h:10-31`
- Impact: reordering or inserting a symbol produces a type-confused native call (wrong
  function pointer signature) rather than a clean error.
- Fix approach: derive both from one manifest (generated header + Dart constant), or
  pass a symbol name table and look up by name natively.

**Inconsistent workspace SDK constraints and ignored lockfile:**
- Issue: root/example/`mpv_kit` declare `sdk: ^3.8.0`, while `mpv_kit_libs` and
  `mpv_kit_video` require `^3.10.0`; `pubspec.lock` is gitignored. The example app and
  the workspace therefore have no reproducible dependency graph.
- Files: `pubspec.yaml`, `packages/mpv_kit/pubspec.yaml`,
  `packages/mpv_kit_libs/pubspec.yaml`, `packages/mpv_kit_video/pubspec.yaml`,
  `example/pubspec.yaml`, `.gitignore:6`
- Impact: a "minimum supported" Dart 3.8 build cannot actually resolve the workspace;
  dependency updates can change CI behavior without a diff.
- Fix approach: align all SDK constraints on the real minimum (3.10) and commit a
  workspace lockfile (or at least the example's) for CI reproducibility.

**Documentation drift around mpv version and decode defaults:**
- Issue: README and ADRs describe mpv `0.41.0`, while the tree is a master snapshot
  (`0.41.0-1113`). README says `Player()` sets `hwdec=auto-safe`
  (`README.md:44`, `README.md:131`), but the code uses
  `vulkan,d3d11va-copy,auto-safe` (`packages/mpv_kit/lib/src/player/player.dart:86`).
  ADR 0002 still lists "macOS bundles require macOS 15", while README/workflow claim
  macOS 12+.
- Files: `README.md:3,44,131`, `docs/adr/0002-lgpl-self-built-binaries.md:38-47`,
  `docs/ARCHITECTURE.md:17`, `packages/mpv_kit/pubspec.yaml:3`
- Impact: users diagnose hardware decoding against the wrong default; platform
  requirements are ambiguous.
- Fix approach: make version strings sourced from one constant and update docs in the
  rebase checklist; correct the hwdec description or the code.

**Experimental native-assets build-hook dependencies:**
- Issue: `mpv_kit_libs` depends on `hooks ^2.2.0` and `code_assets ^2.1.0`, Flutter
  ≥3.38/Dart 3.10; these APIs are young and have had breaking changes across releases.
- Files: `packages/mpv_kit_libs/pubspec.yaml`,
  `packages/mpv_kit_libs/hook/build.dart`, `.github/workflows/flutter-plugin.yml:20`
- Impact: a Flutter/Dart upgrade can break asset bundling even when app code is
  unchanged.
- Fix approach: pin CI to a known Flutter and add an upgrade smoke job early in the
  cycle; document the supported range explicitly.

## Known Bugs

**`Player` leaks two state streams and never resets them:**
- Symptoms: `position` and `decodeWarning` are created manually / directly and are not
  registered in `_states`, so `Player.dispose()` never closes their controllers; on
  `ShutdownEvent`, `_states` are reset but these two are not.
- Files: `packages/mpv_kit/lib/src/player/player.dart:120-129` (manual bind),
  `packages/mpv_kit/lib/src/player/player.dart:312` (`decodeWarning`),
  `packages/mpv_kit/lib/src/player/player.dart:634-636` (closes only `_states`),
  `packages/mpv_kit/lib/src/player/player.dart:681-684` (resets only `_states`)
- Trigger: create a `Player`, listen to `position.stream` or `decodeWarning.stream`,
  dispose the player.
- Impact: listeners never receive `done`; controllers and their listeners stay
  reachable after disposal (leak in long-lived apps that create/destroy players).
- Workaround: none from the public API.
- Fix: add `position` and `decodeWarning` to the same bookkeeping path as `_bind`, or
  explicitly close/reset them in `dispose`/`ShutdownEvent`.

**Every observed property change decodes the node twice:**
- Symptoms: `MpvEventData.decode` calls `_prop(data.cast())` twice in the same event
  constructor — once for `.name`, once for `.value`. The first decoded value is
  discarded.
- Files: `packages/mpv_kit/lib/src/core/events.dart:28-33` and `:54-59`
- Trigger: any `property-change` or `get-property-reply`, including `time-pos` at video
  frame rate.
- Impact: doubles node deep-copying, UTF-8 decoding and allocation on the owning
  isolate for every observed property event. At 4K/60 this is measurable UI-isolate
  CPU and GC pressure.
- Fix: `final (name, value) = _prop(data.cast());` once per event.

**Use of a disposed `Mpv` handle is not guarded:**
- Symptoms: after `Mpv.dispose()`/`Player.dispose()`, public methods still hold the raw
  `handle` and call libmpv. Only `MpvAsyncCommand.abort`, the wakeup loop and
  `observeProperty`'s cancel path check `_disposed`.
- Files: `packages/mpv_kit/lib/src/core/mpv.dart:163-187`, e.g. `setProperty` at
  `:270-280`, `command` at `:226-237`, `getProperty` at `:303-319`
- Trigger: a late timer, widget callback or plugin event calling `player.mpv.*` after
  disposal (common during hot restart or rapid page changes).
- Impact: use-after-free in native code — process crash, not a Dart exception.
- Fix: check `_disposed` in every public method and throw `StateError`; optionally null
  the handle (cannot, it is `final`; track validity separately).

**Async property/command futures can hang indefinitely:**
- Symptoms: `_pending` completers are only failed on `dispose()`. `QueueOverflowEvent`
  (`packages/mpv_kit/lib/src/core/events.dart:324-329`) and `ShutdownEvent` do not fail
  them; no request has a timeout or cancellation token.
- Files: `packages/mpv_kit/lib/src/core/mpv.dart:105`, `:349-387`, `:550-558`
- Trigger: a reply event lost to queue overflow, a core shutdown from another handle, or
  a buggy/blocked libmpv request.
- Impact: `await player.open(...)`, `seek(...)`, `getPropertyAsync(...)` never completes
  and the caller hangs forever (no error surfaced).
- Fix: fail `_pending` on `ShutdownEvent` and `QueueOverflowEvent`; expose a timeout or
  `abort()` on every async request.

**`Player.dispose()` is not exception-safe:**
- Symptoms: dispose hooks, subscription cancellation, `mpv.dispose()` and controller
  closes run sequentially with no `try/finally`. A throwing hook (for example a method
  channel failure in `MpvVideoController.dispose`) skips all remaining teardown.
- Files: `packages/mpv_kit/lib/src/player/player.dart:620-637`,
  `packages/mpv_kit_video/lib/src/video_controller.dart:370-377`
- Trigger: plugin channel error, a user dispose hook that throws, a source whose
  `close()` throws during `StreamBridge.shutdown` (mostly swallowed) or a platform
  thread teardown failure.
- Impact: libmpv core and render context leak; the render context may outlive the core,
  which libmpv explicitly forbids; the app may crash on exit.
- Fix: wrap each stage in `try/finally` (and collect/aggregate errors), ensuring
  `mpv.dispose()` always runs after hooks.

**`MpvLibrary.open()` silently ignores a later explicit path:**
- Symptoms: once any library is loaded, the process-global cache returns it for every
  caller, even when a different `libraryPath` (or changed `MPV_KIT_LIBMPV_PATH`) is
  passed later.
- Files: `packages/mpv_kit/lib/src/ffi/library.dart:29-70`
- Trigger: tests or multi-tenant apps that try to A/B a system libmpv and a bundled one
  in the same process.
- Impact: surprising behavior and impossible-to-test library selection; callers cannot
  detect that their path was ignored.
- Fix: expose a reset/close API for tests, or reject mismatched explicit paths with a
  clear error.

**`BoxFit.cover` renders above the video resolution (contradicts the API contract):**
- Symptoms: `MpvVideoController.setSize` documents "capped at the video size", but
  `MpvVideo._requestSize` receives the scaled *destination* rect. With `BoxFit.cover`
  that rect is larger than the source video, so mpv renders an upscaled frame every
  frame.
- Files: `packages/mpv_kit_video/lib/src/video_controller.dart:337-339`,
  `packages/mpv_kit_video/lib/src/mpv_video.dart:53-67`, `:83-93`
- Trigger: `MpvVideo(fit: BoxFit.cover)` in a viewport bigger than the video.
- Impact: wasted GPU/VRAM and scaler work; higher ring memory than necessary.
- Fix: clamp `shown` to the video size before `setSize`, or update the doc/contract if
  upscaling is intentional.

**`MpvVideoController.create` trusts the platform map:**
- Symptoms: `result['textureId']! as int` throws `TypeError`/null error on a malformed
  or newer native response; `create` has already installed the controller in `_live`
  and registered a dispose hook by then.
- Files: `packages/mpv_kit_video/lib/src/video_controller.dart:177-186`
- Impact: a plugin/protocol mismatch crashes instead of raising a `PlatformException`;
  partially created resources remain until player disposal.
- Fix: validate types with `is` checks and throw `PlatformException` before mutating
  `_live`/hooks.

**Windows D3D11 interop ignores `D3D11CreateDevice` failure:**
- Symptoms: `D3D11Interop` discards the HRESULT of `D3D11CreateDevice`; on failure `device_` stays null while `luid_` is already set. `CreateImage` unconditionally dereferences `device_->CreateTexture2D`. Today `vulkan()` returns null when `device_` is null, so `StartVulkan` falls back to software before `CreateImage` can run; the null dereference is therefore latent to that invariant rather than reachable on the current call path.
- Files: `packages/mpv_kit_video/windows/d3d11_interop.cpp:28-31`, `:83-84`,
  `packages/mpv_kit_video/windows/d3d11_interop.h:12-17`,
  `packages/mpv_kit_video/src/video_renderer.cc:47-50`
- Trigger: `D3D11CreateDevice` fails (driver missing, feature level unsupported) while the adapter LUID and extension checks would otherwise pass.
- Impact: silent loss of the Vulkan backend today; any future change to the `vulkan()` guard or a direct `CreateImage` caller turns it into a process crash. The real defect is the ignored HRESULT and this unreported fallback; the null dereference is latent rather than currently reachable.
- Fix: record a `d3d_ok_` flag from the HRESULT, return null/false from `AcceptDevice`/`CreateImage` when it failed, and log the HRESULT so the renderer can report a useful software-fallback reason.

## Security Considerations

**Untrusted media is decoded in-process with a large native attack surface:**
- Risk: libmpv + FFmpeg + libass/libplacebo parse untrusted containers, codecs and
  subtitle fonts in the app process. A decoder or subtitle-renderer bug becomes an app
  compromise.
- Files: `packages/mpv_kit/lib/src/core/mpv.dart:37-94` (secure defaults),
  `native/build/build.sh`, `native/build/ffmpeg.sh`
- Current mitigation: `Mpv.create` disables `config`, `load-scripts`, `ytdl`,
  `input-default-bindings`, `input-vo-keyboard`, `osc` by default (`mpv.dart:87-94`);
  release FFmpeg is license-gated and built from pinned sources.
- Gaps: automatic sidecar loading (`sub-auto`, `audio-file-auto`) remains at mpv
  defaults, so opening a file can read adjacent untrusted subtitle/audio files; network
  protocols/demuxers stay enabled. No OS sandbox or content-process isolation exists
  because everything runs in-process.
- Recommendations: document a "hostile media" profile (e.g. `sub-auto=no`,
  `audio-file-auto=no`, `ytdl=no`, restricted protocols), keep libmpv/FFmpeg patched,
  and avoid enabling `loadConfigFile`/`commandString` on untrusted input.

**Library loading is environment/search-path controlled:**
- Risk: `DynamicLibrary.open` tries bare names (`libmpv-2.dll`, `libmpv.so.2`, …), which
  on Windows can be satisfied from directories in the loader search path; an attacker
  who can plant a DLL can get code execution before any media is opened.
  `MPV_KIT_LIBMPV_PATH` is likewise trusted verbatim.
- Files: `packages/mpv_kit/lib/src/ffi/library.dart:32-44`, `:49-70`
- Current mitigation: bundled copy is expected next to the executable / in the app
  bundle; release bundles are sha256-verified at build time.
- Recommendations: document the DLL-preloading risk; consider loading the bundled
  library by absolute app-relative path first, and validating that a non-default path
  is absolute.

**Build-time bundle downloads and local bundle trust:**
- Risk: the build hook contacts GitHub at build time. Pinned releases are protected by
  sha256 (`packages/mpv_kit_libs/lib/src/bundles.dart`), and archive entries are
  verified against `MANIFEST.txt` and path-traversal-checked
  (`packages/mpv_kit_libs/lib/src/tar.dart:85-95`,
  `packages/mpv_kit_libs/lib/src/bundle.dart:44-63`). A user-provided `libmpv_bundle`
  directory, however, is "trusted by path"; `verifyDirectory` checks manifest entries
  but does **not** reject extra files, so an injected extra shared library in `lib/`
  would still be bundled.
- Files: `packages/mpv_kit_libs/hook/build.dart:53-67`,
  `packages/mpv_kit_libs/lib/src/bundle.dart:100-124`
- Recommendations: make `verifyDirectory` enforce the same exact-file-set rule as
  `verifyEntries`, and document the trust boundary of `libmpv_bundle`.

**No secrets observed in tracked files:**
- `.env*`, credential and key files were not found in the repo; the analysis did not
  read any such file. `pubspec.lock` and build outputs are ignored. The main secret-like
  material is the pinned hash list, which is public by design.

## Performance Bottlenecks

**All client API calls are synchronous on the calling isolate:**
- Problem: commands/property get/set are direct FFI calls. Most are fast, but some block:
  `mpv_terminate_destroy` waits for the core, `waitAsyncRequests` waits for all async
  work, and `getProperty`/`mediaInfo` can stall while mpv is busy.
- Files: `packages/mpv_kit/lib/src/core/mpv.dart:163-187`, `:506`;
  `packages/mpv_kit/lib/src/player/player.dart:577-600`
- Impact: `Player.dispose()` and `Player.mediaInfo()` can freeze the UI isolate for
  hundreds of milliseconds (or indefinitely if a child handle is leaked — see below).
- Improvement path: document that dispose may block, offer an async dispose that sends
  `quit` and waits for `ShutdownEvent`, and move `mediaInfo()` off the UI isolate.

**Double node decoding per property event:**
- See Known Bugs. `time-pos` is observed at source frame rate and is the hottest path.
- Files: `packages/mpv_kit/lib/src/core/events.dart:28-33`, `:54-59`
- Improvement path: decode once; consider a dedicated fast path for scalar formats
  instead of `MPV_FORMAT_NODE` for high-frequency properties.

**Unbounded event drain in the wakeup callback:**
- Problem: `_onWakeup` loops `mpv_wait_event(0)` until empty and dispatches each event
  synchronously on the isolate. A flood of `time-pos`, `log-message` (trace), or
  property changes is processed in one go.
- Files: `packages/mpv_kit/lib/src/core/mpv.dart:521-548`
- Impact: UI jank and long frame times under verbose logging or high-frequency
  property observation; a slow listener also delays every remaining event.
- Improvement path: cap events per turn and reschedule the remainder, or coalesce
  high-frequency properties before dispatch.

**Per-build side effects in `MpvVideo.build`:**
- Problem: every build calls `syncDisplayRefreshRate`, which performs a synchronous FFI
  `tryGetProperty('display-fps-override')` and possibly a `setProperty`, plus
  `_requestSize` can invoke a platform channel from layout.
- Files: `packages/mpv_kit_video/lib/src/mpv_video.dart:70-74`, `:53-67`
- Impact: layout/build work includes cross-boundary calls; errors from the channel are
  unawaited and surface as unhandled async errors.
- Improvement path: cache refresh rate per `View`/display and move size application to
  a post-frame callback.

**Ring size and teardown cost:**
- Problem: the Vulkan ring is 5–7 full-size RGBA images (Windows uses 7;
  `packages/mpv_kit_video/src/video_renderer.cc:42-46`). At 8K that is ~930 MB VRAM.
  Reallocation waits on each old image's timeline value with a 1 s timeout *while
  holding the renderer mutex* (`vulkan_backend.cc:342-359`), blocking the raster path.
- Files: `packages/mpv_kit_video/src/video_renderer.cc:467-540`,
  `packages/mpv_kit_video/src/vulkan_backend.cc:363-409`
- Impact: resolution/pixel-ratio changes can freeze the compositor thread for seconds
  on a hung GPU; device loss or driver stalls make `VideoRenderer`'s destructor (which
  joins the render thread) block indefinitely.
- Improvement path: reduce waits during resize (release images asynchronously after a
  fence), cap frame size, and add a bounded shutdown path that detaches rather than
  hangs.

**Sequential playlist construction:**
- Problem: `openPlaylist` awaits one `loadfile append` async command per URL.
- Files: `packages/mpv_kit/lib/src/player/player.dart:374-392`
- Impact: a 1,000-entry playlist costs 1,000 round trips and is not atomic; a failure
  midway leaves a partial playlist with no playback started.
- Improvement path: use `loadlist` with a file/`memory://` list or a single command
  batch, and roll back on failure.

**Resize debounce happens after first frame, not before:**
- `MpvVideo._requestSize` applies the first requested size immediately and debounces
  later ones (`mpv_video.dart:53-67`). Dragging a window still reallocates the ring at
  intermediate sizes when the debounce window is shorter than drag steps; each
  reallocation is expensive (see above). Consider a longer debounce or a grow-only
  target during interaction.

## Fragile Areas

**Native renderer thread/lifetime model:**
- Files: `packages/mpv_kit_video/src/video_renderer.cc` (esp. `AcquireFront` 205-254,
  `RenderOnce` 410-631), `packages/mpv_kit_video/src/video_renderer.h`
- Why fragile: three threads interact (mpv core/render thread, platform raster thread,
  plugin/platform thread). `AcquireFront` calls `mpv_render_context_report_swap` from
  the compositor thread while the render thread calls `update`/`render` on the same
  context; correctness relies on libmpv's internal locking and the "same context"
  thread-safety rule, not on a local contract. Ring reuse is governed by a heuristic
  quarantine count (`CompositorLatency`) and a 50 ms present timeout. Any change to
  Flutter's texture sampling behavior (or a driver that samples later than assumed) can
  produce tearing or reading a slot while it is rendered.
- Safe modification: keep acquisition and report_swap outside long locks as intended,
  and add a debug build that asserts ring-slot ownership with a mutex or fence.
- Test coverage: none for concurrency, resize, device loss, or multi-controller use.

**Linux texture teardown relies on a 1-second timer heuristic:**
- Files: `packages/mpv_kit_video/linux/mpv_kit_video_plugin.cc:29-32`, `:360-390`,
  `packages/mpv_kit_video/linux/gl_interop.cc:26-37`
- Why fragile: after unregistering the texture, the plugin waits 1 s (`g_timeout_add`)
  before orphaning GL images, assuming the engine can no longer draw the old texture.
  A slower engine/queue, a blocked main loop, or an app exiting before the timer fires
  leaves GL objects leaked (or, if the assumption is wrong, frees an image the engine
  still samples). Orphan cleanup only happens when some texture's `populate` runs, so a
  process that stops rendering never frees disposed players' images.
- Safe modification: tie cleanup to a generation counter/engine callback if available;
  at minimum drain orphans on plugin dispose and document the timing assumption.

**Windows plugin event marshalling and raw `Instance*` captures:**
- Files: `packages/mpv_kit_video/windows/mpv_kit_video_plugin.cpp:46-57`, `:159-172`,
  `:250-291`
- Why fragile: renderer callbacks capture raw `Instance*`; the GPU-surface callback
  returns a pointer to a shared `FlutterDesktopGpuSurfaceDescriptor` member, and texture
  deletion is deferred to `UnregisterTexture`'s callback. `PostEvent` allocates on the
  render thread and frees in the window procedure; if the delegate is unregistered
  before a posted message is processed, the allocation is leaked. `PostEvent` also
  touches `registrar_->GetView()` from a non-platform thread, which Flutter does not
  promise to be thread-safe.
- Safe modification: use an owned per-instance event queue drained on the platform
  thread, avoid calling registrar APIs off-thread, and validate `Instance` ownership
  under the existing mutex in every method path.

**Process-wide Vulkan state caches failures permanently:**
- Files: `packages/mpv_kit_video/src/vulkan_backend.cc:88-93`
- Why fragile: `GetSharedInstance` uses `std::call_once` capturing the first
  `VulkanInterop`. If the first attempt fails (loader missing, transient driver error),
  the empty instance/error is cached for the process lifetime; every later
  controller silently falls back to software. The captured interop also makes the
  instance's extension set depend on whichever player started first.
- Safe modification: cache only successful instances or allow a retry after a failure;
  key the cache by platform/interop.

**Stream bridge swallows all failures and can block a demuxer thread:**
- Files: `packages/mpv_kit/lib/src/core/stream_bridge.dart:221-278`
- Why fragile: `on Object` catches programming errors as well as source failures and
  converts them to "loading failed"/generic errors with no diagnostics. A
  `MpvStreamSource.read/seek/close` future that never completes blocks mpv's demuxer
  thread until `Mpv.dispose` calls `mpv_kit_stream_shutdown`; there is no per-request
  timeout. `close()` is fire-and-forget and its errors are discarded.
- Safe modification: catch `Exception` (not `Error`), log/report the error through a
  diagnostics channel, provide a configurable read timeout, and surface source errors
  via `Player.errors`/a dedicated stream error stream.

**Player state parsing uses unchecked casts inside a synchronous event loop:**
- Files: `packages/mpv_kit/lib/src/player/player.dart:641-644`,
  `packages/mpv_kit/lib/src/player/models.dart:49-51`, `:115-118`, `:216-221`
- Why fragile: `_bind` callbacks use `as String?`/`as int?` on raw node values. A
  libmpv version that returns a different node type (or a malformed/extension value)
  throws `TypeError` inside `MpvState._set` while `_dispatch` is delivering a sync
  broadcast. The exception escapes the wakeup callback; remaining queued events are not
  drained until the next wakeup, and the offending property update is lost.
- Safe modification: use lenient conversion helpers (as already done for `_int`,
  `_maps`) for every parse callback, and guard listener dispatch with error reporting.

**Vendored/prebuilt headers and hand-written FFI structs:**
- Files: `packages/mpv_kit/lib/src/ffi/bindings.dart:192-381`,
  `packages/mpv_kit_video/src/include/mpv/`, `packages/mpv_kit_video/third_party/`
- Why fragile: struct layouts (`mpv_event_end_file`, `mpv_stream_cb_info`, etc.) and
  symbol counts are hand-maintained. The ABI audit (`tools/rea_abi_audit`) checks symbol
  *names*, not struct layout or signatures. A newer libmpv with an extended event struct
  can be loaded (only the client API major is checked) and misread.
- Safe modification: generate bindings/structs with `ffigen` from the vendored headers,
  or at least compile-time/runtime `sizeof` assertions exposed by the library; document
  the maximum tested client API minor.

**Reentrant disposal from event listeners:**
- Files: `packages/mpv_kit/lib/src/core/mpv.dart:521-548`,
  `packages/mpv_kit_video/lib/src/video_controller.dart:232-248`
- Why fragile: event streams are synchronous broadcasts; a listener may call
  `Mpv.dispose()`/`Player.dispose()`, which closes the `NativeCallable` and stream
  controllers while the wakeup callback is still executing. This is not exercised by
  tests and depends on Dart's rules for closing a listener callable from within its own
  invocation.
- Safe modification: defer disposal to a microtask/event-queue turn, or document that
  disposal must not be called reentrantly from event callbacks.

**Native display-refresh-rate probe is Windows-only:**
- Files: `packages/mpv_kit_video/lib/src/video_controller.dart:215-230`,
  `packages/mpv_kit_video/windows/mpv_kit_video_plugin.cpp:118-139`,
  `packages/mpv_kit_video/linux/mpv_kit_video_plugin.cc:239-243`,
  `packages/mpv_kit_video/macos/Classes/MpvKitVideoPlugin.mm:162-167`
- Why fragile: `_syncInitialRefreshRate` always invokes `getDisplayRefreshRate`, but
  only the Windows plugin implements it. On Linux/macOS the no-argument call hits the
  handlers' `bad_args` guard and surfaces as a `PlatformException`, which `create`
  catches before falling back to `PlatformDispatcher.instance.displays`; this works
  today, but the native error is misleading (`bad_args` rather than `not_implemented`)
  and no test covers the fallback. If the handlers are reordered to dispatch by method
  name first (or otherwise reply not-implemented), Dart raises `MissingPluginException`,
  which `create` does not catch; the call happens after the renderer/texture exist, so
  that path would throw with native resources already allocated.
- Safe modification: implement `getDisplayRefreshRate` natively on Linux/macOS, or make
  the Dart probe tolerant of `MissingPluginException` in addition to
  `PlatformException`; add a fake-platform-channel test where the method is
  unimplemented.

`_applyShaderCacheDir` assumes the gpu renderer is compiled in; a heavily reduced libmpv build without vo_gpu/gpu-next would reject `gpu-shader-cache-dir` with `optionNotFound`, and `create()` would surface it. Cheap hardening: ignore `optionNotFound`/`propertyNotFound` when setting it.

## Scaling Limits

**One libmpv per process:**
- `MpvLibrary` is a process-wide singleton (`packages/mpv_kit/lib/src/ffi/library.dart:28-30`).
  Apps cannot hold two different libmpv builds (for example one LGPL bundle and one
  custom build) or upgrade the library at runtime.
- Limit: any test matrix or multi-tenant use that needs distinct library versions.

**Per-controller VRAM and ring allocation:**
- Each `MpvVideoController` owns a ring of 5–7 full-resolution images; at 4K RGBA that
  is ~130–190 MB per player, at 8K up to ~930 MB. Multiple simultaneous players
  multiply this linearly (`video_renderer.cc:42-46`, `:206-230`). The fallback ring is
  smaller but still large. There is no global memory budget or eviction.

**Event throughput and one isolate:**
- All events, property parsing and listener callbacks run on the isolate that created
  `Mpv` (`mpv.dart:24-27`). There is no built-in worker-isolate mode. With several
  players and high-frequency observations (time-pos, logs, cache properties), the UI
  isolate becomes the bottleneck. `Player` throttles `time-pos` to 100 ms
  (`player.dart:120-129`) but raw `observeProperty` users get every event.

**Child client handles can block shutdown:**
- `mpv_terminate_destroy` blocks until all client handles are destroyed
  (`native/mpv/player/client.c:424-466`, libmpv docs at
  `native/mpv/include/mpv/client.h:517-542`). `Mpv.createClient` returns handles that
  callers may forget to dispose; `Player`/`Mpv` do not track them. Disposing the main
  `Player` then blocks on the isolate indefinitely.
- Limit: apps using sub-clients must manually dispose every one before the main player.

**Playlist construction is O(n) round trips:**
- See Performance. Large playlists are slow and non-atomic.

**Stream protocol registrations are never freed:**
- Native `mpv_kit_stream_add` registrations are intentionally leaked (documented in
  `native/patches/0006-libmpv-asynchronous-stream-bridge.patch` and
  `stream_bridge.dart:127-165`). Repeated player creation with custom protocols grows
  process memory and the global registration list.

## Dependencies at Risk

**mpv master snapshot + seven downstream patches:**
- Risk: `native/mpv` is a moving master commit (`0.41.0-1113-gfd9265a905`) with no
  upstream plan; patches touch vo_gpu_next internals that mpv refactors frequently.
- Impact: security updates and API changes require hand rebases; a failed rebase cannot
  be substituted with a stock libmpv because the render API and stream bridge are
  custom.
- Files: `native/patches/UPSTREAM.md`, `native/mpv/MPV_VERSION`
- Migration plan: none upstream; maintain a rebase checklist and a CI "apply patches to
  upstream tarball" job.

**FFmpeg 8.1.3 / libplacebo 7.360.1 / Vulkan SDK 1.4.363.0 / MoltenVK 1.4.2 pins:**
- Risk: security fixes in FFmpeg/decoders require manual version bumps in
  `native/build/ffmpeg.sh` and `native/build/deps.sh`; the hashes are hard-coded.
- Impact: shipped bundles can lag upstream security releases until someone bumps pins
  and reruns the release workflow.
- Files: `native/build/ffmpeg.sh:11-12`, `native/build/deps.sh:117-260`
- Migration plan: add a scheduled CI job that checks upstream releases and opens a
  bump PR; keep the license gate.

**Native-assets toolchain (`hooks`, `code_assets`) and Flutter/Dart minimums:**
- Risk: pre-1.0 API churn; `mpv_kit_libs` requires Dart 3.10 and Flutter 3.38 while
  other workspace members claim 3.8.
- Impact: upgrades can break bundling/builds independent of mpv_kit code.
- Files: `packages/mpv_kit_libs/pubspec.yaml`, `packages/mpv_kit_video/pubspec.yaml`
- Migration plan: pin toolchain versions in CI and test the next Flutter beta early.

**Committed `bt/` DLL closure:**
- Risk: unversioned, unverified binaries (see Tech Debt). They can be mistaken for the
  supported runtime and are not checked by any CI.
- Migration plan: remove or document with a manifest tied to a release tag.

## Missing Critical Features

**Mobile and web platform support:**
- The Flutter plugin declares only Windows, Linux and macOS
  (`packages/mpv_kit_video/pubspec.yaml:31-38`). `mpv_kit` itself is pure Dart/FFI and
  could work where a libmpv is provided, but there is no documented Android/iOS/Web
  path or bundled library for them.

**Async command timeouts/cancellation and stream timeouts:**
- `MpvAsyncCommand.abort()` maps to `mpv_abort_async_command`, but there is no timeout
  or status API beyond the result future; stream sources have no timeout. This blocks
  robust handling of hung network sources and broken players.

**Built-in recovery from `deviceLost`:**
- `MpvVideoController.isBroken` reports device loss, but neither the controller nor the
  `MpvVideo` widget disposes/recreates itself or falls back automatically. Every app
  must implement recovery, despite README calling it out.

**Background-isolate mode / worker support:**
- No supported way to keep libmpv off the UI isolate. All synchronous FFI, parsing and
  callbacks run where `Mpv` was created. This is a scaling limitation for large apps
  and multi-player UIs.

**Unregisterable stream protocols:**
- `registerStreamProtocol` has no unregister/dispose counterpart; combined with the
  intentionally leaked native registration, apps that create many players cannot clean
  up.

**No integration/crash test for the real Flutter texture path in CI:**
- The plugin is only compiled; no automated test renders through the actual platform
  plugin (see Test Coverage Gaps).

## Test Coverage Gaps

**`mpv_kit_video` behavioral tests are skipped in CI:**
- What's not tested: `MpvVideoController.create/setSize/events/dispose` and `MpvVideo`
  layout against a real libmpv. Every test in
  `packages/mpv_kit_video/test/controller_channel_test.dart` is guarded by
  `_libmpvAvailable()` (`:10-17`, `skip: skip` at `:78-166`). The `flutter-plugin`
  workflow does not install or build libmpv (comment at
  `.github/workflows/flutter-plugin.yml:1-6`), so all of them skip; the native and
  release workflows delete `packages/mpv_kit_video` before running Dart tests
  (`.github/workflows/native-verify.yml:74-86`,
  `.github/workflows/release.yml:84-91`).
- Files: `packages/mpv_kit_video/test/controller_channel_test.dart`,
  `.github/workflows/flutter-plugin.yml`
- Risk: controller/plugin regressions (channel contract, dispose ordering, event
  routing) ship green. Only `video_controller_test.dart` (shader-cache path logic) runs
  unconditionally.
- Priority: High.

**No tests for native interop or renderer failure paths:**
- What's not tested: D3D11/GL/Metal shared-image creation, resize/retirement, quarantine,
  `render_error` backoff, `gpu_timeout`, `device_lost`, multiple simultaneous
  controllers, Windows event marshalling, Linux delayed texture release, macOS
  `copyPixelBuffer` ownership.
- Files: `packages/mpv_kit_video/src/`, `packages/mpv_kit_video/windows/`,
  `packages/mpv_kit_video/linux/`, `packages/mpv_kit_video/macos/`
- Existing coverage: only `native/tests/render_vk_smoke.c` (one 64×64 frame through
  lavapipe/MoltenVK) and `native/tests/stream_bridge_test.c` (host-thread bridge, not
  Dart). The Windows smoke test skips when no lavapipe build exists
  (`.github/workflows/native-verify.yml:202-216`); the macOS Intel
  smoke/package tests are `continue-on-error`
  (`.github/workflows/release.yml:137-167`).
- Risk: platform-specific crashes/leaks are found by users, not CI.
- Priority: High.

**Format matrix is release-only and optional:**
- What's not tested in PR CI: decode coverage for the trimmed FFmpeg build. The test is
  skipped unless `MPV_KIT_FORMAT_SAMPLES` is set
  (`packages/mpv_kit/test/format_matrix_test.dart:20-24`) and only the release workflow
  generates samples.
- Risk: a dependency change can drop a codec/pixel format and only fail at release time
  (or not at all if the release job is skipped).
- Priority: Medium.

**No tests for `Player` lifecycle edge cases:**
- What's not tested: `position`/`decodeWarning` stream closure, disposing while a
  request is pending, `ShutdownEvent` with pending async futures, double dispose beyond
  the controller case, dispose-hook exceptions, post-dispose method calls,
  `Player.wrap` ownership, `openPlaylist` failure mid-way.
- Files: `packages/mpv_kit/test/player_test.dart` (244 lines),
  `packages/mpv_kit/test/mpv_test.dart`
- Risk: the two confirmed bugs above (leaked state streams, hanging futures) have no
  regression test and can regress silently.
- Priority: High.

**Tests depend on real libmpv features and a global cache:**
- The suites require a libmpv with `libavdevice`/lavfi (`av://lavfi:...` in
  `packages/mpv_kit/test/mpv_test.dart:17`, `player_test.dart:12`,
  `stream_bridge_test.dart:12`) and rely on `MpvLibrary`'s process-wide cache. A system
  libmpv without lavfi fails unrelated tests; a loaded library cannot be swapped.
- Risk: environment-dependent failures and flaky wall-clock timeouts (10–15 s) on CI.
- Priority: Medium.

**No coverage threshold for `mpv_kit_video` or native plugin code:**
- `native-verify` enforces 80% line coverage only for `mpv_kit`
  (`.github/workflows/native-verify.yml:83-86`); no coverage is collected for the
  Flutter plugin or the C++/ObjC++ sources.
- Priority: Medium.

---

*Concerns audit: 2026-10-23*

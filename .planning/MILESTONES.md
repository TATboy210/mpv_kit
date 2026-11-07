# Milestones

## v3.0 统一渲染生命周期与平台原生图形后端 (Shipped: 2026-10-31)

**Delivered:** one RenderBackend lifecycle across platforms with native Windows D3D11 and Linux OpenGL backends, cross-backend hwdec defaults and fallback hardening, shipped to consumers as GitHub Release `v0.1.0-dev.4` (tag at 47cbbf2) and pub.dev `mpv_kit` / `mpv_kit_libs` / `mpv_kit_video` 0.1.0-dev.4.

**Closeout type:** `override_closeout` — all 7 phases complete and their verifiers passed, but the reports of Phases 12, 14, 16, 17 and 17.1 went stale when later commits (quick 261030-umq, 261031-wrf, Phase 17.1 CI edits) touched covered files; the user chose not to re-run them.

**Known verification overrides:** 8 newly acknowledged (7 todos, 1 Phase 17 deferred item), 1 carried forward from a prior close (see STATE.md Deferred Items). One debug session (`d3d11-render-context-not-implemented`, fixed by bc6a6bf/091228a) was left unacknowledged because it lives in the user-owned `.planning/debug/`.

**Git range:** 2ed9c80..1e19ad8 (358 commits, 2026-10-26 → 2026-10-31); outside `.planning/`: 155 files, +29439/−1031.

**Requirements:** 29/31.

### Known Gaps

- [ ] **D3D-08** — Windows auto chain not switched to d3d11 first (user decision 2026-10-29: keep Vulkan first; d3d11 stays second and forceable).
- [ ] **HWD-03** — Linux DRM display for vaapi interop is implemented but unverified on real Linux GPU hardware (hosted llvmpipe only).

**Phases completed:** 7 phases, 54 plans, 53 tasks

**Key accomplishments:**
- Hosted CI is green on `feat/mpv-master-upgrade` for the first time. Three workflow-only fixes did it: the pin check now runs from the repo root, the example is built before the hook-bundle locate step, and the Linux runners get the runtime libraries libmpv needs. A reusable `ci_gate.sh` now checks job results and log lines for a given pushed SHA. The real-plugin integration test has run on all three platforms for the first time.
- The part-2 pixel probe does see the external texture. The new three-region control read the texture region as fully non-black, stable across two reads and after the first presented frame, with Impeller both on and off. 10-05's 1266x683 surface is the production 1280x720 boundary clamped by a 1265.33x682.67 view at dpr 1.5. With the probe confirmed, part 2 now waits for a first-frame readiness gate before it reads, and the pass rule is byte-identical. The harness also gained a 100-cycle create/dispose segment, a `resize-front` reproducer and a rendered variant of the UHD 4K gate.
- The Dart side now accepts the private GPU wire names `d3d11`, `opengl` and `vulkan` and maps all three to the frozen `MpvVideoBackend.vulkan`. Any other value still fails loudly with `render_init`. ADR 0004 fixes the `reason` grammar and the strict meaning of `MPV_KIT_VIDEO_API`, so 12-06 and 12-10 have one written contract to implement.
- RTX 4060 baseline on the unchanged 3a5f450 Vulkan path: cycles 100/100 under both Impeller switches, while D-05 and resize-front abort in round 1 with the same shape whether Impeller is on or off (exit 79, no crash forensics, unexplained). Recorded as data and not re-run until green.
- A fake libmpv, filled into the nine-pointer `MpvApi` table, now drives the real `video_renderer.cc` with no libmpv in the process. Twelve software-path golden scenarios cover fallback reasons, quarantine rotation, retire-on-resize, backoff and its cap, idle/active, ICC and invalid sizes. They pass on all six native-verify jobs, sanitizers included, with no change to product code.
- The native `reason` now follows ADR 0004 exactly. It is `vulkan (gpu-next) on <device>` or `software (sw) on cpu`, followed by one `; vulkan/<renderer> unavailable: <why>` trail per candidate ranked before the winner, with `;` and control characters sanitized out of every field. The Linux GL probe failure becomes a trail instead of a free-text suffix, and golden_sw pins the software side on all six native-verify jobs.
- The same 12-04 commands, rerun after the 12-06/12-07 fixes, now complete the D-05 soak: 100/100 rounds under both Impeller switches, where every pre-fix attempt aborted in round 1. That gives the verdict `resolved-by-fix`. cycles is 100/100 with lower RSS growth. resize-front no longer loses the process but ends inconclusive in round 2. A first rendered 4K 600 s run passed with 0 drops. The user approved the data and the move to 12-09.
- The final Phase 12 HEAD passes the full hosted CI gate (15/15 jobs) and seven re-runnable audits. On the RTX 4060, 4K 30 min matches Phase 4 on every gate item, rendered 4K 600 s keeps 0 drops and 0 vo-delayed frames against 12-08, and all six harness groups show no new failure. The user approved the Phase 12 close.
- The user accepted ADR 0005 (MoltenVK to IOSurface route), the HWD-04 classification and the SC2 result after seeing the real hosted readings; the ADR is now `Status: accepted`.
- Phase 14 can now push and dispatch under a recorded green-plus-scratch authorization, judge any branch's CI with one parameterised gate command, and 14-07 has measured (not assumed) answers: fences work on every host, VIDEO_SUPPORT needs a retry-without path on the Basic Render Driver, 8K shared textures open cross-device everywhere.
- On a machine like the GTX 960 + iGPU laptop, the Vulkan failure reason now says which device failed and why (`Vulkan < 1.3 on <name>` or `<name> is not the compositor adapter`), with the Phase 12 golden freeze re-cut under a new Phase 14 manifest and CI green on every platform.
- `pe_audit.py --forbid-angle` now fails any DLL that imports libEGL/libGLESv2 or contains `eglGetPlatformDisplayEXT`/those names (ASCII or UTF-16LE), is proven red by synthetic PE samples, and runs on the verify-layer libmpv, the plugin DLL and every Windows bundle DLL, with the Windows build explicitly switching off ANGLE/EGL/WGL-GL.
- The Windows build now compiles SPIRV-Cross (`spirv-cross-c-shared`) and `shaderc_shared` from sha256-pinned official sources, turns on libplacebo `pl_d3d11` and mpv `-Dd3d11/-Dshaderc/-Dspirv-cross` there, and carries the 82224764a9 + c43baa7a0c libplacebo fixes as patches 0015/0016; none of it has been built on Windows yet (hosted CI deferred).
- Patch 0010 backports the upstream mpv D3D11 render API (client API 2.6, params 21/22) as six verbatim upstream commits plus a one-line `done_frame` bool adaptation; `render_d3d11.h` and `render.h` are byte-identical to upstream 4255130de4, and PATCH-DRIFT passes locally with `patches=10`. No Windows compile has run (hosted CI deferred).
- gpu-next now has a D3D11 branch in patch 0004 (same-device `ra_d3d11` + `pl_d3d11`, `pl_d3d11_wrap` host texture, VO-owned DXBC shader cache), with a new `render_d3d11_smoke` (gpu, gpu-next, cache) and a packaged-bundle step in release.yml. PATCH-DRIFT passes locally with `patches=10`; nothing has been compiled or run on Windows with mpv (hosted CI deferred).
- The Windows plugin now has a native D3D11 backend: own `ID3D11Device` on Flutter's adapter, mpv rendering through its D3D11 render API into a KMT-shared BGRA8 ring handed to `GpuSurfaceTexture`, with an `ID3D11Fence` (or `D3D11_QUERY_EVENT`) completion gate before publish. Everything compiles clean under MSVC `/W4 /WX` (debug and release plugin builds) and the plugin DLL stays ANGLE-free; no frame has been rendered through it yet because no D3D11-capable libmpv exists locally (hosted CI deferred).
- D3D11 device removal now has one HRESULT source that debug builds can inject into (`MPV_KIT_D3D11_INJECT=device-removed:<n>|create-fail`, absent from release), a real-plugin test for both injections, and a platform-independent chain golden (5 scenarios) that fixes interleaved candidates, d3d11 device-failure trails, forced-API no-fallback and exactly-one `device_lost`. The golden and all earlier renderer tests pass under MSVC `/W4 /WX`; no injection run happened because no D3D11-capable libmpv exists locally (hosted CI deferred).
- The user's GTX 960M + HD 530 laptop no longer falls back to software: the cause was the compositor adapter (Flutter on the HD 530), a runner GPU preference moves it to the GTX 960M, and a two-frame FIFO queue brings effective drops on vulkan/auto to about 0.5 percent (estimate).
- The Linux libmpv build now turns on mpv's upstream OpenGL render API (`-Dgl -Degl -Dplain-gl`, x11/wayland still off), asserts it in `config.h`, and a new surfaceless-EGL smoke test (`render_gl_smoke gl|gles`) is wired into native-verify and release; none of it has been built or run on Linux (hosted CI deferred).
- render_gl_smoke now replays the Linux OpenGLBackend's per-frame handoff on one EGL display (blit into an export texture, EGLImage from that texture only, EGL fence, GLES 2 import on another thread with an unshared context) and reports FLIP_Y orientation for a red-over-blue source; release_gate.sh is written. Nothing was compiled or run on Linux and no spike decision exists yet (hosted CI deferred).
- The mounted-texture probe, the full ProbeGl failure diagnosis and the Flutter 3.47.8 embedder facts are in place; every decision that needs a CI log line is a deferred placeholder.
- `MPV_KIT_VIDEO_API=opengl` now renders on the real Linux plugin through mpv's OpenGL render API: a private context on Flutter's EGLDisplay, private texture -> blit -> per-slot export texture -> EGLImage -> `FlTextureGL`, published only after an EGL fence; the Linux chain (decision A) is wired in.
- `GlInterop::ProbeGl` now runs on its own short-lived thread, so every controller gets the same backend as the first; with Vulkan made unavailable (`vkCreateInstance failed`) the auto chain lands on `opengl (gpu)` with the Vulkan reason in the trail, proven on the real plugin.
- Docs now match the code (Linux chain, `opengl` on Linux, `RunBound` thread rules, EGLImage handoff); one full CI gate on HEAD reproduces every Phase 15 key line, and the audit maps GLX-01..04 and SC1..SC4 to run ids with the llvmpipe-only boundary written down.
- CI can now say zero-copy / copy-back / software on real H.264 and HEVC samples (ubuntu forced opengl, windows forced d3d11 on WARP, macOS route probe), and the hosted spike shows the macOS default list does select VideoToolbox zero-copy once the probe stops feeding `List.toString()` back as the option.
- Three fault classes (device lost, GPU timeout storm, target-allocation failure) are injected into fake d3d11/vulkan backends and pinned by `video_renderer_fault_test` (7 scenarios, golden/fault.txt) on all six CI jobs plus MSVC, with no product-code change; the macOS vk-gpu-timeout flake is addressed by judging the 1 s device wait and the 100 ms engine backoff separately.
- Every backend of each platform is now forced in turn against the real-plugin texture probe in CI (8 cells, all ok, hosted Windows Vulkan asserted unavailable with its real `vkCreateInstance failed` reason), the create-time `softwareFallback` event finally reaches the first `events` listener with the whole fallback chain, and `MPV_KIT_REQUIRE_HWDEC` fails loudly on hosted WARP.
- A pre-registered memory-plateau rule (committed with its unit tests before any measurement), one 100-round soak that runs on every forced backend and passes flat on hosted ubuntu opengl in CI, plus a gated, timestamped, never-overwriting RTX session wrapper with a CIM VRAM sampler and verdict tool, and fully traceable session inputs.
- RTX 4060 evidence: all forced-backend probes, the hwdec guard (positive and negative), three soaks, Vulkan 4K 1800 s and the d3d11 HEVC 4K 1800 s pass, but forced d3d11 4K 1800 s (lavfi) had 3 and 5 VO drops in two attempts, so the VER-04 zero-drop gate is not met for d3d11.
- Phase 17 is documented and audited against its evidence: one full CI gate on the final docs-over-product SHA reproduced every key line of 17-01..17-03, the audit maps VER-01..04 and SC1..SC4 to run ids with 17 unverified items listed, and the user approved the SC1, VER-01, VER-04 and SC4 wording.
- The mpv_kit_libs build hook no longer trusts a `{target}.ok` stamp over a missing or empty `lib/`: it reinstalls from the sha256-verified cached archive (or re-downloads), and an installed pinned bundle without shared libraries now fails the build with `BundleIntegrityException`.
- The flutter-plugin Windows leg now exports native Windows paths for libmpv and its PATH entry, and its Analyze step runs under bash with one command per line, so a failing test or analyze fails the job instead of being masked by pwsh.
- Tag candidate `b524b3a76fd6a79e40b30024ffae5988b131b04c` is on origin `feat/mpv-master-upgrade` and green on native-verify, flutter-plugin and macos-route (PR_PREP set: Windows build log `29 tests passed.`, no `could not be loaded`, resolvePinnedBundle tests run), with the phase gate tooling proven on finished runs first.
- `v0.1.0-dev.4` is published from `47cbbf21f603cffb0d0d472796f42f72ad768099`: tag run 41123644028 passed the RELEASE_TAG gate (publish success), and all six bundle archives match SHA256SUMS and the API digests.
- bundles.dart now pins v0.1.0-dev.4 (six sha256 from the release's SHA256SUMS, each equal to the API digest), the hook verified the dev.4 windows-x64 bundle locally, and the pushed pin (95c2b6d) is green on native-verify, flutter-plugin and macos-route; the pinned bundle alone rendered forced d3d11 on windows-2025 and forced opengl on ubuntu-24.04 under xvfb.
- On the RTX 4060 Laptop GPU with only the pinned v0.1.0-dev.4 bundle, forced d3d11 renders (gpu-next D3D11 branch, nonBlack 1.0/1.0 before and after resize, exit 0) and the default chain still wins on vulkan gpu-next; the libmpv sha256 is identical before and after.
- The todo is closed with its Linux half and a resolution copied from the Phase 17.1 evidence, the v3.0 audit gets an appended update, and the close-out head 7b9871c is on origin and green on native-verify, flutter-plugin and macos-route.

---

## v2.0 GPU-Next Optimization & Full-Rate UHD (Closed: 2026-10-25)

**Closeout type:** `override_closeout` — closed by explicit user decision
("simple close-out"), not by verification. 2 of 5 phases complete, 0 of 5
fully verified at close; 6 of 10 requirements delivered.

**Phases in scope:** 5 phases (7-11), 14 plans, 10 tasks

**Known verification overrides:** 1 newly acknowledged, 0 carried forward from
a prior close (see STATE.md Deferred Items — Phase 10 `10-VERIFICATION.md`
`gaps_found` acknowledged, not resolved).

**Key accomplishments:**
- Vendor provenance made exact at mpv 0.41.0-1115 (gb2c255c13e8e); the advance doubles as a correction of v1's misattributed 0008 deltas.
- seek 恢复、全套件、基准全绿；4K 30 分钟被宿主磁盘写满阻塞（非代码回归，证据链完整），解除条件已记录。
- The example is now a debugging cockpit: five-group HUD + live event overlay (F9), drag-and-drop playback with a non-video notice — all example-side, production untouched.
- Flutter 3.47.8 external textures decompiled per path: both surface types bind through ANGLE, mpv_kit's D3D11 device owns the shared resource, and no fence or keyed-mutex acquisition exists; Impeller only removes Ganesh's per-resolve flush and context reset.
- A pinned-3.47.8, single-testWidgets D-04 harness now exists: 1080p chain, one 4K render target with a non-black pixel proof, and a 100-round / >=30 s resize-dispose soak, behind an identity gate that refuses to report an Impeller result from a substituted libmpv or a non-Vulkan backend.
- Both D-05 runs on the pinned 3.47.8 SDK abort in the 10-02 harness's own unsatisfiable part-1 gate (inconclusive, identity proven from the engine log), and ADR 0003 records that Impeller is still GLES-over-ANGLE, sets Phase 11's route, and makes settling D-05 its first task.
- The smoke harness now reports through `print()` with a run-proven BENCH preflight line, gates part 1 on decoder params plus a real `setSize`-driven resize, slices the pixel buffer by offset/length, and reports harness failures at both preflight stages — CR-01, CR-02, WR-02 and IN-06 closed without weakening any verdict rule.
- The fixed harness ran both switches end to end but aborted inside the soak window in both; with no complete line and no crash forensics, neither workload proof (A) nor renderer-abort proof (B) holds, so the plan FAILS rather than closing D-05.
- A synchronous-flush trace and a diag-only reproducer were added and run three times, but the 10-05 soak abort did not recur (5, 5 and 25 rounds all completed with exit 0), so the honest outcome is `diagnosis: not-reproduced`, Task 1 fails, and no fix is applied.

### Known Gaps

- [ ] **UHD-02** — 8K 7680x4320 × 30 minutes never run. Evidence stops at a 60 s
  run with all v1 gates green (Phase 9, `09-01-SUMMARY.md`); the 30-minute
  endurance gate required by the requirement was not attempted.
- [ ] **COMP-02** — native composition path not implemented; the ADR route
  (upstream first, upgrade as vehicle, modified ANGLE as fallback) has no code
  deliverable in this milestone.
- [ ] **COMP-03** — compositor-latency budget never measured or parameterised;
  Windows still uses `CompositorLatency() == 4` / `kMaxQuarantine == 4`.
  The 100-round interleaved resize/dispose soak never produced a usable pass.

### Deferred to Later Milestones

| Requirement | Reason deferred |
|---|---|
| UHD-02 | No 8K test media conditions at close; needs a 30-minute gate run |
| COMP-02 | Blocked on D-05 (never settled) and on a Flutter engine with a non-GLES Windows external-texture backend |
| COMP-03 | Blocked on COMP-02 existing; the measurement harness half-exists but its soak aborts |

### Technical Debt Incurred

- Phase 10's gap-closure plans (10-08 probe-surface control, 10-09 rerun,
  10-06 ADR final verdict) are abandoned mid-flight. `10-VERIFICATION.md`
  stays `gaps_found`; ADR 0003 stays `inconclusive`. Do not read either as a
  completed verdict.
- The 10-05 soak abort is unexplained and `diagnosis: not-reproduced`. It was
  never attributed to the renderer, and it was never ruled out either.
- `example/lib/hud.dart` still prints a static `compositor: 'ANGLE
  (DxgiSharedHandle)'` placeholder; no runtime composition-path reporting exists.

---

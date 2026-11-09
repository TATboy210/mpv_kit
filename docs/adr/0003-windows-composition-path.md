# ADR 0003 — Windows composition path after the 3.47.8 Impeller spike

verdict: inconclusive
engine-renderer: Impeller (GLES-over-ANGLE, OpenGLESSDF) when --enable-impeller; the --no-enable-impeller control shows no Impeller line
identity: proven

Status: accepted (evidence recorded 2026-10-25; D-05 not exercised — see Context)
Date: 2026-10-25
Supersedes: the premise in `.planning/research/SUMMARY.md` that "Impeller is the
bypass of ANGLE" and that 3.47.6 lacked #191017's content.
Related: `docs/reverse-engineering/03-flutter-windows-texture-consumption.md`,
`docs/ARCHITECTURE.md`, ADR 0001 (Vulkan render backend).

## Context

Phase 10 asked whether the Windows composition chain can be made **shorter or
cheaper** than the current path, where mpv_kit produces a D3D11 KMT-shared
texture, Flutter's engine consumes it through ANGLE, and the compositor samples
the ANGLE-bound GL texture. Two evidence streams were produced:

1. **REA** (static, independent of any runtime): `docs/reverse-engineering/03-*.md`,
   a PDB-guided Ghidra decompilation of the shipped 3.47.8
   `flutter_windows.dll`, walked to pseudocode for registration, production and
   consumption.
2. **Smoke** (runtime): the 10-02 harness run twice on the pinned local 3.47.8
   SDK, `--enable-impeller` and `--no-enable-impeller`.

The two streams answer different questions and are not interchangeable. The REA
settles what the code does; the smoke was meant to settle whether the Impeller
consumption path survives the D-05 workload. It did not: both runs aborted in
the harness's own part-1 readiness gate before any workload or pixel probe (see
"Runtime smoke"). Therefore this ADR records a **decision under an incomplete
runtime evidence set**, and says so wherever that matters.

### Premise corrections carried into this decision

- **Impeller on Windows 3.47.8 is GLES-over-ANGLE.** The engine's Windows
  backends are `gles`, `metal`, `vulkan`; Windows uses the GLES one. Enabling
  Impeller removes Ganesh from level C, not ANGLE from level B.
- **#191017's content is present in 3.47.8.** The post-fix dispatch
  (`aiks_context` before `context`, plus the null guard in
  `ResolveTextureSkia`) is in the tag tree and is byte-identical between
  3.47.6 and 3.47.8. The merge commit `bb8568060d` is not an ancestor; the
  delivery commit is **unverified** (provenance footnote, not a behavioural
  doubt).
- **Binary ↔ tag-source provenance is one link short.** The shipped DLL was
  built at engine revision `cf636b1dfb`, which does not resolve in
  `flutter/engine`. The correspondence is inferred from identical anchor
  counts, identical import tables, and byte-identical source files between the
  two tags.
- The earlier framing "the real bypass is Impeller" is retired. The question is
  whether the chain can be **shortened**, not whether ANGLE can be removed by a
  switch.

## Renderer identity

Identity is established only by the engine's own log line, never by
`mpv_kit_video`'s `mpv_kit_video: <backend> (<reason>)` line (that is mpv's
renderer) and never by the HUD's `compositor` field (a Phase 8 placeholder).

identity-guard: unproven => inconclusive (never 不可行)

- Positive (`--enable-impeller`, source `flutter-run`, same SDK and env):

  ```
  [IMPORTANT:flutter/shell/platform/embedder/embedder_surface_gl_impeller.cc(126)] Using the Impeller rendering backend (OpenGLESSDF).
  ```

  One match, in `evidence/impeller-run-on.log`; also appended, clearly
  delimited and labelled with its source, to `evidence/impeller-on.log`.
- Negative (`--no-enable-impeller`, same transport): zero matches in
  `evidence/impeller-run-off.log` / `evidence/impeller-off.log`.
- `flutter test -d windows` does **not** forward the app process's engine log;
  neither test log contains any engine line. The documented fallback
  (`flutter run -d windows`, recorded as `identity-source: flutter-run`) was
  used. Identity is `proven` because both halves come from the same transport
  with only the switch changed.

The guard exists because a run whose identity is unproven may never be used as
a renderer verdict: an unproven run makes this ADR's `verdict:` `inconclusive`,
even if that run crashed. Run classifications are retained verbatim; they are
not rewritten by the guard.

## Evidence

### REA — static, independent of the smoke

Per-path answers from `docs/reverse-engineering/03-*.md` (file RVAs, image base
`0x180000000`):

| Path | Through ANGLE? | DXGI device owner | Fence semantics |
|---|---|---|---|
| A — Registration (`RegisterTexture` `0x1b24c`, `EmplaceTexture` `0x1b4d2`) | No GPU work | none | none |
| B — Production (`CreateOrUpdateTexture` `0xeafe`, `CreateSurfaceFromHandle` `0xdf7a`) | **Yes, always**: `eglCreatePbufferFromClientBuffer` + `eglBindTexImage` | producer = mpv_kit's D3D11 device (KMT handle); consumer = ANGLE's in-PE `Renderer11` device via `OpenSharedResource` | none; `release_callback` fires immediately after bind and is **not** a read-completion signal |
| C — Consumption (`ResolveTexture` `0xeb436`) | **Yes, even under Impeller**: the GL texture is ANGLE-bound | unchanged; same ANGLE context | Impeller (`0xeb484`): no flush, no wait; Skia (`0xeb9e0`): `flush` + `submit` + `resetContext`, still no wait |

Key details a Phase 11 implementation can rely on:

- The surface type selects only the EGL enum:
  `DxgiSharedHandle` → `EGL_D3D_TEXTURE_2D_SHARE_HANDLE_ANGLE` (`0x3200`),
  `D3d11Texture2D` → `EGL_D3D_TEXTURE_ANGLE` (`0x33A3`). It does not select a
  fence.
- The Impeller branch gates hard on `format == GL_RGBA8` (`0x8058`) and returns
  null otherwise, logging `Only support GL_RGBA8 format now`. A format change
  would appear as a **silent black texture**, not a crash.
- The Impeller branch wraps the ANGLE GL name via
  `TextureGLES::WrapTexture` + `ReactorGLES::RegisterCleanupCallback`, then
  returns `DlImageImpeller`; no `flushAndSubmit`/`resetContext`.
- **Keyed mutex:** ANGLE stores an `IDXGIKeyedMutex` from `QueryInterface`
  (`0xecb660`) but never acquires it; the pointer is only reachable through
  `eglQuerySurfacePointerANGLE` (`0xf18f50`), which Flutter never calls. With
  `D3D11_RESOURCE_MISC_SHARED` (our case) the query returns null anyway.
  The full `SwapChain11::reset/present` path was not instruction-audited; that
  boundary is stated in the report.
- ANGLE is compiled into the engine PE (no `libEGL.dll`/`libGLESv2.dll`
  imports in any form); all devices are in one process.

### Runtime smoke — incomplete, and recorded as such

Both runs used the pinned local 3.47.8 SDK (framework `737ba8f885`, engine
revision `cf636b1dfb`), a debug build, a visible desktop window, one external
texture, and the `mpv_kit_libs` hook-build libmpv `v0.1.0-dev.3`
(`resolvedLibmpv` gate passed, `mpvBackend` = `vulkan`). Full commands, exit
codes and switch values are in `evidence/impeller-bench.txt`; logs are
`evidence/impeller-on.log` and `evidence/impeller-off.log`.

- **Classification: `inconclusive`.** Both runs stopped at the same harness
  gate after 30 s:
  `Bad state: part 1 readiness timeout: params=1920x1080 fps=30 resizeEvents=0`.
  The gate requires a `resize` event, but `VideoRenderer::SetSize` is the only
  writer of `width_`/`height_` (`video_renderer.cc:166-179`), `resize` is
  emitted only when those differ from the ring (`:499`, `:541`), and the
  harness never calls `setSize` before part 1. This is a harness defect, not a
  renderer failure.
- **No BENCH line** reached the captured console in either run (count 0).
  Per the plan, that is an evidence gap by itself.
- **The pixel probe was never executed**, so `nonBlackRatio` is `unsupported`
  and `pass` is impossible: a pass requires `pixelProbe.supported == true` and
  `nonBlackRatio >= 0.01`.
- **RGBA8 scan:** 0 hits in both logs. No format rejection occurred; this does
  not become a pass because the workload never ran.
- **Not a crash:** `flutter test` exit code 1 is the framework reporting the
  timeout. No `mpv_kit_example` WER dump appeared in
  `%LOCALAPPDATA%/CrashDumps`, and no `Application Error` event naming
  `flutter_windows.dll` was logged in the run window. The 3.47.0-specific
  offset `0x2c55f7` was not used for matching (per the research). Last stage:
  `part1`.
- **Scope vs #191468:** this app uses one external texture; the issue used
  four. Even a clean run would not prove that historical crash is gone.
- **D-05 was neither confirmed nor refuted.** `failed` and `renderer-crash`
  would attribute a harness defect to the renderer, which T-10-09 forbids;
  `pass` is impossible without the non-black proof. Hence the verdict below.

### Historical benchmark renderer — unrecorded

The 4K baseline in `docs/perf/2026-10-24-baseline.md` does not record which
engine renderer was live. Impeller is the Windows default in the 3.47.x line,
so those numbers **cannot be assumed to be Skia** and must not be used as a
"Skia baseline" when measuring a composition change. Any before/after
comparison in Phase 11 must record the renderer line alongside the numbers.

## Decision

### What the evidence forces

1. **Enabling Impeller cannot remove ANGLE from external-texture handoff.**
   It changes level C only: it removes Ganesh's per-resolve
   `flush`/`submit`/`resetContext` and wraps the same ANGLE-bound GL texture.
   No configuration on 3.47.8 changes level B.
2. **The only structural shortening available is a different engine
   consumption backend** (Vulkan or D3D external-texture import, instead of
   GLES-over-ANGLE). 3.47.8 does not ship one.
3. **D-05 remains unsettled.** Phase 11 must not claim "Impeller feasible" or
   "Impeller infeasible" on this evidence.

### Can the chain be shorter or cheaper?

Yes in principle, but **not by a switch on 3.47.8**. The slogan "no ANGLE" is
rejected here because it is unverifiable on this version: every Windows surface
type binds through `eglCreatePbufferFromClientBuffer` + `eglBindTexImage`, and
Impeller consumes the resulting GL texture. The measurable, honest options are:

- remove the per-resolve Ganesh work (already true under Impeller) — this is a
  CPU-side saving, not the removal of the handoff;
- replace the handoff itself, which requires an engine change (upgrade or
  upstream patch);
- optimize inside ANGLE (e.g. avoid redundant binds), which changes cost, not
  structure.

No claim of "cheaper" is accepted without numbers: every option must be
measured on this machine, with the renderer line recorded.

### What Impeller does NOT remove

- It does **not** remove ANGLE: `ResolveTextureImpeller` consumes the
  ANGLE-bound GL texture created by `eglBindTexImage`.
- It does **not** remove the EGL pbuffer surface or the two D3D11 devices.
- It does **not** add a fence. Neither branch synchronises mpv_kit's Vulkan
  writes with ANGLE's D3D11 sampling.
- It does **not** remove the `GL_RGBA8` format gate; it makes that gate harder
  (silent black texture on mismatch).
- It does **not** shorten the chain on the producer side.

### Route for Phase 11

**Primary: upstream the requirement and the repro (candidate ②), with the
upgrade bypass (candidate ①) as its delivery vehicle and self-modified ANGLE
(candidate ③) as the fallback.**

Rationale from the evidence:

- Candidate ① ("upgrade to an engine version with a Vulkan/D3D backend") is the
  only route that can remove ANGLE from the handoff, but no such Windows
  backend exists in 3.47.8; it is a *condition*, not an executable step today.
- Candidate ② is executable now, directly addresses the missing capability, and
  is supported by this phase's REA and smoke evidence (one-texture 4K
  external-texture composition, no fence, GLES-over-ANGLE).
- Candidate ③ is the expensive fallback: it can optimize ANGLE's cost but
  cannot remove the handoff, so it should not be the first spend.

**Measurable closing indicators (no "feels faster"):**

- per-resolve CPU cost in microseconds, from the renderer's existing
  `probe_wait_prev_ms_`/`probe_wait_done_ms_` probe and a before/after trace;
- the presence/absence of `flush`/`submit`/`resetContext` in the resolve path
  (static proof from the engine build used, plus a runtime trace);
- 4K composition cost before/after (CPU and GPU), with the engine renderer line
  recorded for both sides;
- the D-05 workload (100 resize/dispose rounds interleaved with >= 30 s
  continuous playback) with zero use-after-release and no black frame;
- 4K 30-minute gate re-green, and 8K re-verified after Phase 9.

**Immediate Phase 11 precondition:** settle D-05 with a corrected harness
(call `setSize` before the part-1 gate, or gate part 1 on
`estimated-vf-fps > 0` plus a first rendered frame). Until then, no
composition change is approved on the basis of "Impeller works".

### Runtime fallback contract (owned by Phase 11, not implemented here)

If a Phase 11 composition path is selected and fails at runtime, the player
must keep working on the ANGLE path. The contract to implement in Phase 11:

- automatic fallback to the existing ANGLE-bound external-texture path when the
  selected path cannot be created or reports a renderer error;
- the active path, the fallback reason and a failure counter exposed through
  `backend`/`reason` and the HUD, reusing the Phase 3 honest-reason
  infrastructure;
- no silent degradation: a fallback is an observable event, not a log-only
  side effect.

This ADR does **not** implement the fallback itself; it is not a Phase 10
deliverable.

### Quarantine hypothesis (not measured here)

- Current Windows values: `CompositorLatency() == 4` (`d3d11_interop.h:35`),
  `kMaxQuarantine == 4` (`video_renderer.h:212`), ring 7
  (front + in use + quarantine + one free).
- The 4 is a heuristic inherited from the Skia path: "DXGI default frame
  latency 3 + the frame being composed". It was never measured.
- Under Impeller there is no `flushAndSubmit`/`resetContext` on resolve. If
  Impeller's GLES command buffer defers submission across frames, ANGLE may
  sample the shared texture later than the Skia-era bound. That is a
  hypothesis for Phase 11 to measure; this phase changes no parameter.

### D-06 — required version/conditions, explicitly unverified

Because the verdict is not `pass`, Phase 11's composition change is gated on
conditions this phase did **not** verify:

- a released Flutter engine whose Windows external-texture consumption backend
  is Vulkan or D3D (not GLES-over-ANGLE), or an accepted upstream patch that
  adds one;
- the six-target build matrix (Windows/Linux/macOS × x64/arm64) still green;
- public API compatibility (this project's API is frozen; the plugin method
  channel contract is unchanged);
- the CI `FLUTTER_VERSION` lock and engine-artifact pins updated, followed by a
  fresh REA of the new engine and a re-run of the harness pair.

If those conditions are never met, Phase 11 shrinks to a record-only close-out
(D-06 permits it), and this ADR plus report 03 remain the decision record.
**`inconclusive` is not `failed` and must not be written as "Impeller 不可行".**

## Consequences

- The project stops treating "enable Impeller" as the composition optimisation.
  The observable effect of Impeller today is the removal of Ganesh's per-resolve
  CPU work around the same ANGLE texture.
- Phase 11's first deliverable is evidence work (fix the harness gate, settle
  D-05, then select/implement the route), not a renderer rewrite.
- Any 4K composition benchmark taken before this ADR must be re-taken with the
  renderer line recorded before it is compared.
- The REA's format-cliff and reactor-lifetime constraints become implementation
  requirements for any path that touches level C.
- No public API change; `packages/` is untouched by Phase 10.

## Research Open Questions

| Question | Disposition |
|---|---|
| Q1 — Does `flutter test -d windows` forward the engine log? | **Answered: no.** Both test logs contain no engine line; identity was captured via the `flutter-run` fallback (`evidence/impeller-bench.txt`, labelled section in `impeller-on.log`). |
| Q2 — Is the example app actually running Impeller today? | **Answered for the pinned 3.47.8 build:** yes under `--enable-impeller` (engine line with `OpenGLESSDF`); no under the control. The historical benchmark's renderer is unrecorded and cannot be assumed Skia. |
| Q3 — Is ANGLE statically linked into `flutter_windows.dll`? | **Settled by the 3.47.8 Delta** (no `libEGL.dll`/`libGLESv2.dll` imports; ANGLE compiled into the PE). The REA adds only the synchronisation/device semantics. |
| Q4 — Does Impeller's deferred GLES submission invalidate `quarantine = 4`? | **Phase 11 measurement.** This ADR records the hypothesis and the current values; no parameter change here. |
| Q5 — Which commit carried #191017 into the release branch? | **Unresolved** (provenance footnote only; the content is present in 3.47.8). |

## Provenance

- Engine artifact: `D:/flutter/bin/cache/artifacts/engine/windows-x64/flutter_windows.dll`,
  46,636,544 B, sha256
  `9a3a09cabda0fb31b27313394205bdcac62a5211c0d71934d2272313ffb7d170`;
  PDB 278,859,776 B beside it. SDK: Flutter 3.47.8 stable, framework
  `737ba8f885`, engine revision `cf636b1dfb`, engine hash
  `dfd2e6cb7d319db05e3bf1503f3e2ac60f6288a2`, Dart 3.13.7.
- REA toolchain: Ghidra 12.1.4 headless, PyGhidra 3.1.0, CPython 3.12.8,
  JVM heap 8 GB; anchors and RVAs in `evidence/decompilation.txt`,
  `engine-3.47.8.anchors.txt`, `engine-3.47.8.imports.txt`.
- Smoke logs and classification:
  `evidence/impeller-on.log`, `evidence/impeller-off.log`,
  `evidence/impeller-run-on.log`, `evidence/impeller-run-off.log`,
  `evidence/impeller-bench.txt`, `evidence/disk-gate.txt`.
- Commands and switch values: recorded verbatim in
  `evidence/impeller-bench.txt` (`run-on.command` / `run-off.command`,
  `run-on.switch` / `run-off.switch`) and in the `*.meta` files.
- Hard constraints honored: no SDK other than the pinned 3.47.8; no
  `bt/libmpv-2.dll`; public API unchanged; `packages/` untouched.

### Open items

| Item | Status |
|---|---|
| Which commit carried #191017 into the release branch | Unverified (content present in 3.47.8) |
| Shipped DLL ↔ tag-tree source correspondence (`cf636b1dfb`) | One link short (inferred from identical anchors/imports and byte-identical sources) |
| Engine-log forwarding by `flutter test -d windows` | Answered: no; fallback used |
| ANGLE's internal D3D11 synchronisation in `SwapChain11::reset/present` | Not instruction-audited (boundary stated in report 03) |
| Historical 4K benchmark renderer | Unrecorded; cannot be assumed Skia |
| D-05 (30 s + 100 rounds) | Not exercised (harness defect); first Phase 11 task |

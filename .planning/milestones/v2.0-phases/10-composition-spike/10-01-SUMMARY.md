---
phase: 10-composition-spike
plan: 01
subsystem: reverse-engineering
tags: [flutter, windows, impeller, angle, d3d11, external-texture, ghidra, keyed-mutex]

requires:
  - phase: 10-composition-spike
    provides: 10-RESEARCH.md 3.47.8 delta (hashes, anchor counts, import-table facts)
  - phase: 09-8k-full-rate
    provides: the shipped 3.47.8 SDK install used as the analysis target

provides:
  - Pinned Flutter 3.47.8 engine artifact evidence (sha256, sizes, excluded stale copy)
  - Import-table proof that ANGLE is compiled into flutter_windows.dll
  - Per-anchor string counts and their path meaning
  - Per-path pseudocode for registration, production and consumption (Impeller + Skia)
  - A definitive keyed-mutex answer with binary and pinned-ANGLE-source evidence

affects: [phase-11, composition-path-decision]

actuals:
  tokens: 58000
  tasks: 2
  commits: 2
  plan_head_before: cc461be5e7f87df675004d061b7554ef3d099837
  plan_head_after: f1cd40def76d9c8fe4d187302821258bd0f9cbdc

tech-stack:
  added: []
  patterns:
    - PyGhidra headless post-script that exports named functions by PDB symbol
    - Evidence files carry commands and raw output, never binary content

key-files:
  created:
    - docs/reverse-engineering/03-flutter-windows-texture-consumption.md
    - .planning/phases/10-composition-spike/evidence/engine-3.47.8.sha256.txt
    - .planning/phases/10-composition-spike/evidence/engine-3.47.8.imports.txt
    - .planning/phases/10-composition-spike/evidence/engine-3.47.8.anchors.txt
    - .planning/phases/10-composition-spike/evidence/decompilation.txt
    - .planning/phases/10-composition-spike/tools/DumpTargets.py
  modified: []

key-decisions:
  - "Both surface types bind through ANGLE: DxgiSharedHandle uses EGL_D3D_TEXTURE_2D_SHARE_HANDLE_ANGLE (0x3200), D3d11Texture2D uses EGL_D3D_TEXTURE_ANGLE (0x33A3)"
  - "The DXGI resource is owned by mpv_kit's own D3D11 device; ANGLE's in-PE Renderer11 device opens the KMT handle, so two D3D11 devices coexist in one process"
  - "No fence, query or keyed-mutex acquisition exists in the production or consumption paths; release_callback fires immediately after eglBindTexImage and is not a read-completion signal"
  - "Impeller changes only the consumption level: it removes Ganesh flush/submit/reset and wraps the same ANGLE-bound GL texture via ReactorGLES"
  - "The keyed-mutex open item from doc 02 is closed: ANGLE stores IDXGIKeyedMutex but never acquires it; only eglQuerySurfacePointerANGLE exposes it, and Flutter never calls it"

patterns-established:
  - "Evidence-first REA: pin hash/size, record anchor counts individually, dump named functions with RVAs, then write conclusions"
  - "State decompiler limits explicitly (ICF folding, mislabelled indirect callees) rather than presenting them as findings"

requirements-completed: [COMP-01]

coverage:
  - id: D1
    description: "Flutter 3.47.8 SDK artifact is pinned by sha256 and byte size, with the stale build-tree copy excluded"
    requirement: COMP-01
    verification:
      - kind: other
        ref: "sha256sum/stat gate in 10-01-PLAN Task 1 verify (passed)"
        status: pass
    human_judgment: false
  - id: D2
    description: "Import table proves libEGL/libGLESv2 are absent and ANGLE is compiled into the PE"
    requirement: COMP-01
    verification:
      - kind: other
        ref: "grep gates over evidence/engine-3.47.8.imports.txt (libEGL.dll: ABSENT, libGLESv2.dll: ABSENT, 'compiled into')"
        status: pass
    human_judgment: false
  - id: D3
    description: "Three-path report with pseudocode, per-path allocation/fence/device-ownership annotations and both EGL enums"
    requirement: COMP-01
    verification:
      - kind: other
        ref: "heading/string gates in 10-01-PLAN Task 2 verify (3 path headings, 3x3 annotations, EGL enums)"
        status: pass
    human_judgment: true
    rationale: "Automated gates prove structure and required strings; the correctness and completeness of the pseudocode interpretation need human review."
  - id: D4
    description: "Keyed-mutex answer distinguishing ANGLE's stored-but-never-acquired IDXGIKeyedMutex from embedder-driven acquisition"
    requirement: COMP-01
    verification:
      - kind: other
        ref: "grep gates for 'Keyed-mutex answer:' and 'IDXGIKeyedMutex'"
        status: pass
    human_judgment: true
    rationale: "The conclusion combines binary pseudocode with pinned public ANGLE source; the boundary of what was not instruction-audited needs review."

duration: 2h 10m
completed: 2026-10-25
status: complete
---

# Phase 10 Plan 01: Flutter 3.47.8 Texture-Consumption REA Summary

**Flutter 3.47.8 external textures decompiled per path: both surface types bind through ANGLE, mpv_kit's D3D11 device owns the shared resource, and no fence or keyed-mutex acquisition exists; Impeller only removes Ganesh's per-resolve flush and context reset.**

## Performance

- **Duration:** 2h 10m (of which ~63 min was the one-off Ghidra PDB analysis)
- **Started:** 2026-10-24T15:12Z (session start)
- **Completed:** 2026-10-25T17:22Z
- **Tasks:** 2 of 2
- **Files created:** 6
- **Commits:** 2 task commits (+1 metadata commit)

## Accomplishments

- Pinned the locally installed Flutter 3.47.8 engine artifact: 46,636,544 B,
  sha256 `9a3a09ca…b7d170`, PDB 278,859,776 B, and explicitly excluded the
  stale 46,621,696 B `example/windows/flutter/ephemeral` copy.
- Proved from the import table that `libEGL.dll`/`libGLESv2.dll` are absent in
  every form (regular, delay-load, ASCII, UTF-16LE) while `dxgi.dll`,
  `OPENGL32.dll` and `d3d9.dll` are present; `d3d11.dll` is runtime-resolved.
- Recorded per-anchor counts (1/2/1/1/4/1) that corrected the old uniform
  "exactly once" assumption and identified each literal's path/branch.
- Decompiled all three levels to pseudocode with RVAs and call graphs, and
  added the ANGLE pbuffer/swap-chain path needed to answer the fence and
  keyed-mutex questions.
- Wrote `docs/reverse-engineering/03-…` with exactly three path sections, each
  carrying `Allocation`, `Fence semantics` and `Device ownership`, and a
  dedicated keyed-mutex answer.

## Task Commits

1. **Task 1: pin the 3.47.8 artifact (hash / PDB / anchors / imports)** — `05739bf` (docs)
2. **Task 2: decompile per path and write the 03 report** — `f1cd40d` (docs)

**Plan metadata:** committed separately after this SUMMARY.

## Files Created/Modified

- `docs/reverse-engineering/03-flutter-windows-texture-consumption.md` — the
  three-path pseudocode report, keyed-mutex answer, provenance and open items.
- `.planning/phases/10-composition-spike/evidence/engine-3.47.8.sha256.txt` —
  artifact pin, SDK identity, excluded ephemeral copy, provenance gap.
- `.planning/phases/10-composition-spike/evidence/engine-3.47.8.imports.txt` —
  dumpbin/pe_audit import table and ANGLE linkage meaning.
- `.planning/phases/10-composition-spike/evidence/engine-3.47.8.anchors.txt` —
  measured anchor counts and their path meaning.
- `.planning/phases/10-composition-spike/evidence/decompilation.txt` — 183,749 B
  Ghidra export: function metadata, pseudocode, callers/callees, anchor xrefs.
- `.planning/phases/10-composition-spike/tools/DumpTargets.py` — reproducible
  PyGhidra post-script (symbol lookup, RVA export, decompilation, xrefs).

## Decisions Made

- **Both surface types remain on ANGLE.** `DxgiSharedHandle` maps to
  `EGL_D3D_TEXTURE_2D_SHARE_HANDLE_ANGLE` (0x3200), `D3d11Texture2D` to
  `EGL_D3D_TEXTURE_ANGLE` (0x33A3). The type selects the EGL enum; it does not
  select a fence.
- **Device ownership is split by role, not by path.** mpv_kit's own D3D11
  device creates the KMT-shared texture; ANGLE's in-PE `Renderer11` device
  opens it; Vulkan imports it on mpv_kit's side. Because ANGLE is compiled into
  the engine PE, all devices are in one process and no DLL boundary explains
  synchronization.
- **Keyed-mutex open item closed.** ANGLE's `SwapChain11` stores an
  `IDXGIKeyedMutex` obtained by `QueryInterface` but never acquires it;
  `SurfaceD3D::querySurfacePointerANGLE` only exposes the pointer, and Flutter
  never calls `eglQuerySurfacePointerANGLE`. With
  `D3D11_RESOURCE_MISC_SHARED` (our case) the query returns null anyway.
- **Impeller's gain is level C only.** It removes Ganesh's
  `flush`/`submit`/`resetContext` and wraps the same ANGLE-bound GL texture
  through `ReactorGLES`; it cannot remove the EGL handoff.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] REA MCP tools were unavailable in this executor**
- **Found during:** Task 2 setup
- **Issue:** The dispatch advertised `mcp__rea__*`, but no REA tool was
  callable in this environment.
- **Fix:** Used the plan's own Ghidra 12.1.4 headless path and recorded the
  fallback in this summary; no disassembly was invented.
- **Files modified:** none (tooling choice)
- **Verification:** Every extracted address comes from the Ghidra export in
  `evidence/decompilation.txt`.
- **Committed in:** `f1cd40d` (Task 2)

**2. [Rule 3 - Blocking] Ghidra 12.1.4 headless could not run Python post-scripts**
- **Found during:** Task 2 setup
- **Issue:** Ghidra 12.1.4 ships PyGhidra only (no Jython), and analyzeHeadless
  aborted with "Ghidra was not started with PyGhidra. Python is not available".
- **Fix:** Created a local venv and installed Ghidra's own bundled
  `pyghidra-3.1.0` wheel with `pip --no-index -f <Ghidra>/pypkg/dist`
  (no registry, no network). Launched headless via
  `python -m pyghidra.ghidra_launch`.
- **Files modified:** none in the repository; venv lives at
  `D:/ghidra_pyghidra_venv` (outside the repo).
- **Verification:** A probe script printed `PYVER 3.12.8`, its args and the
  current program before the real run.
- **Committed in:** `f1cd40d` (Task 2)

**3. [Rule 1 - Bug] RVA helper assumed `Address.subtract` returned an Address**
- **Found during:** first full Ghidra run
- **Issue:** `Address.subtract(Address)` returns a Java long; the export
  aborted on the first RVA with `'JLong' object has no attribute 'getOffset'`.
- **Fix:** Replaced it with `offset - imageBase.offset` formatting.
- **Files modified:** `tools/DumpTargets.py`
- **Verification:** Re-ran against the saved project; full export produced.
- **Committed in:** `f1cd40d` (Task 2)

**4. [Rule 1 - Bug] Reference iterator was treated as a sized collection**
- **Found during:** second full Ghidra run
- **Issue:** `ReferenceManager.getReferencesTo()` returns an iterator without
  `len()`, aborting the anchor-xref section.
- **Fix:** Materialised it with `list(...)`.
- **Files modified:** `tools/DumpTargets.py`
- **Verification:** Anchor xrefs now export, including the keyed-mutex and
  `eglQuerySurfacePointerANGLE` evidence.
- **Committed in:** `f1cd40d` (Task 2)

**5. [Rule 1 - Bug] Ghidra thunk stubs collided with real symbol names**
- **Found during:** keyed-mutex target expansion
- **Issue:** Import/thunk stubs at RVAs `0x1900`/`0x1980` produced fake
  1–3-byte "functions" matching `SurfaceD3D`, `DisplayD3D` and others.
- **Fix:** Filtered `isThunk()` and the two stub RVAs; documented the filter.
- **Files modified:** `tools/DumpTargets.py`
- **Verification:** Only real functions remain in the export.
- **Committed in:** `f1cd40d` (Task 2)

**6. [Rule 2 - Missing Critical] Extended the target list to settle the keyed-mutex question**
- **Found during:** Task 2 analysis
- **Issue:** The plan's minimum target list cannot answer doc 02's open
  keyed-mutex item; the answer lives in ANGLE's pbuffer/swap-chain path.
- **Fix:** Added `egl::Display::createPbufferFromClientBuffer`,
  `rx::DisplayD3D::createPbufferFromClientBuffer`, `SurfaceD3D`,
  `SwapChain11` (constructor / reset / offscreen buffer / keyed-mutex getter),
  `TextureStorage11_External`, and the `EGL_ANGLE_keyed_mutex` /
  `eglQuerySurfacePointerANGLE` anchors.
- **Files modified:** `tools/DumpTargets.py`, `evidence/decompilation.txt`
- **Verification:** `Keyed-mutex answer:` is backed by RVAs `0xecb660`,
  `0xf18f50`, `0x3d960` and the pinned ANGLE source.
- **Committed in:** `f1cd40d` (Task 2)

---

**Total deviations:** 6 auto-fixed (3 blocking tooling, 3 correctness/completeness)
**Impact on plan:** No scope creep. The tooling fixes were required to run the
prescribed Ghidra path; the target expansion was required to answer an explicit
plan question rather than leave it open.

## Issues Encountered

- Full PDB-guided analysis of the 46.6 MB DLL took ~63 minutes and needed an
  8 GB JVM heap (analyzeHeadless defaults to 2 GB headless). The project was
  retained outside the repository at `D:/ghidra-work-3.47.8` so later runs can
  use `-process` with `-noanalysis`.
- Identical-code folding made `rx::SurfaceD3D::bindTexImage` unusable at its
  address (folded with unrelated 19-byte virtuals). The report states this
  boundary instead of inventing a bind implementation.
- Several indirect callees are mislabelled by function ID
  (`X509_get_notBefore`, `AXUI` helpers). The report states that primary PDB
  symbols win over these labels.
- Network access was available; the pinned ANGLE revision
  (`84027aca…` in Flutter's DEPS) could not be fetched from the
  `flutter/third_party/angle` mirror (404), so the report cites the same public
  implementation from `google/angle` and states the mirror limitation.

## User Setup Required

None — no external service configuration required.

## Threat Surface

No new runtime surface. The plan handled an untrusted 46.6 MB PE plus a 279 MB
PDB as data only; nothing was executed or loaded, and no binary was committed
(`git ls-files` contains no DLL/PDB).

## Next Phase Readiness

- COMP-01(a) evidence is complete: the binary is pinned and each path answers
  ANGLE / device ownership / fence with addresses.
- Plan 10-02 (Impeller smoke) and 10-03 can now use the format cliff, reactor
  cleanup and no-fence conclusions directly.
- Phase 11 can decide "shorter/cheaper" against a settled fact: Impeller does
  not remove ANGLE from the handoff.

## Self-Check: PASSED

- `docs/reverse-engineering/03-flutter-windows-texture-consumption.md` exists and passes all Task 2 string/structure gates.
- All three evidence text files and `decompilation.txt` exist and are non-empty.
- `tools/DumpTargets.py` exists; the generated `__pycache__` was removed before commit.
- Commits `05739bf` and `f1cd40d` are ancestors of HEAD; no DLL/PDB is tracked.

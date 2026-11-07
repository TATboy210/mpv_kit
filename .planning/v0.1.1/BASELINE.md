# v0.1.1 P0 Baseline — 1080p Working Set and Attribution

**Status:** P0 complete; P1 fix confirmed (2026-11-07)
**Gate:** example app + local 1080p + default hardware decode + 10 min stable → Windows Working Set < 250 MB (hard gate)
**Tree:** `89761501b5eb82328932a52f72ef7b7c1a9f7d3f`
**Machine:** Windows 11 x64, NVIDIA RTX 4060 Laptop, 32 GiB RAM
**Flutter:** 3.47.9 stable / Dart 3.13.7

---

## 1. Method

- **App:** `example` release build (`flutter build windows --release`), HUD visible,
  `MPV_KIT_EXAMPLE_AO=null`.
- **Source:** `C:/Users/35490/Downloads/13349743_1920_1080_25fps.mp4`
  (1920×1080 H.264, 25 fps, 17.2 s). A 200-entry `.m3u` repeats it for the
  10-minute window; the file itself is a local 1080p sample.
- **Sampling:** `Get-Process` `WorkingSet64` and `PrivateMemorySize64` every 5 s
  for 600 s, via `.planning/tmp/p0-sample.ps1`. Working Set is the gate metric;
  private memory is recorded for attribution only.
- **Bundles:**
  - `dev.9` local hook bundle (mpv 0.41, LGPL), used as a provisional control.
  - **0.42 candidate**: one `workflow_dispatch` run `42341558262`
    (`release.yml`, Windows x64 GPL full, `libmpv-2.dll` version `v0.42.0`).
- **Headless attribution:** `.planning/tmp/probe_8k.dart` (`vo=null`, `ao=null`,
  `loop-file=inf`) against each bundle, 120 s, same sample.
- **Event attribution:** `.planning/tmp/p0-events.dart`, 60 s, real libmpv 0.42.

---

## 2. Results

### 2.1 Example app, 1080p, 10 minutes

| Bundle | Peak WS | Min WS | Mean last 5 min | First 10 / last 10 | Samples ≥250 MB |
|---|---:|---:|---:|---:|---:|
| dev.9 (mpv 0.41, LGPL) | 233.3 MiB | 200.4 | 225.3 | 213.7 / 229.4 (+15.7) | 0 / 120 |
| 0.42 GPL full, before fix | **294.1 MiB** | 259.5 | 282.9 | 269.2 / 284.8 | **120 / 120** |
| 0.42 GPL full, after fix | **234.0 MiB** | 204.7 | 225.7 | 213.6 / 229.0 (+15.5) | **0 / 120** |

- dev.9 is under the gate; the 0.42 GPL full candidate is **~60 MiB higher** and
  fails the hard gate before the fix.
- Private memory (not the gate): dev.9 ~530–600 MiB; 0.42 ~570–650 MiB.

### 2.2 Headless attribution (`vo=null`, 120 s)

| Bundle | Peak RSS | `demuxer-cache-state.fw-bytes` | `hwdec-current` | `vd-lavc-threads` |
|---|---:|---:|---|---:|
| dev.9 (mpv 0.41) | 338.4 MiB | 0.4–10 MB | `d3d11va-copy` | 4 |
| 0.42 GPL full | 339.2 MiB | 0.4–10 MB | `d3d11va-copy` | 4 |
| 0.42, `hwdec-extra-frames=1` | 339.7 MiB | 0.4–10 MB | `d3d11va-copy` | 4 |

**Conclusion:** the demuxer cache is not the cause (never approaches its
199.5/49.9 MiB cap), and the 0.42 headless decode/demux path is identical to
dev.9. The regression is in the **Vulkan zero-copy render path**.

### 2.3 Render-path A/B (minimal 1080p harness, 60 s)

| Renderer / option | Working Set |
|---|---:|
| 0.42, `hwdec-extra-frames=auto` (default) | 254–259 MiB |
| 0.42, `hwdec-extra-frames=1` | **200–207 MiB** |
| 0.42, `hwdec-extra-frames=2` | **202–213 MiB** |
| 0.42, forced `Vulkan/gpu` (`MPV_KIT_VIDEO_RENDERER=gpu`) | 268–275 MiB |

**Conclusion:** mpv 0.42's `hwdec-extra-frames=auto` derives the surface pool
from the VO queue and over-allocates for the 8-slot Windows ring. Capping it to
1–2 frames removes ~50 MiB. gpu-next is not the cause (forced `gpu` is the same).

### 2.4 Event emissions (60 s, real libmpv 0.42, `vo=null`)

| State | Emissions | Equal-value re-emissions | Duplicate ratio |
|---|---:|---:|---:|
| `videoParams` | 2 | 0 | 0% |
| `audioParams` | 0 | 0 | — |
| `tracks` | 3 | 1 | 33% |
| `playlist` | 1 | 0 | 0% |
| `chapters` | 1 | 0 | 0% |
| `metadata` | 1 | 0 | 0% |
| `position` | 501 | 0 | 0% |

**Conclusion:** model value-equality/lazy-observer work is **not** a meaningful
memory lever for this scenario. Do not implement it in v0.1.1 (avoid speculative
changes). Only `tracks` had one duplicate in 60 s.

### 2.5 Bundle sizes (0.42 candidate, unpacked `lib/`)

| Target | `lib/` size | Largest libraries |
|---|---:|---|
| windows-x64 | 62.4 MiB / 44 libs | avcodec 14.2, shaderc 7.4, gcrypt 6.3, avfilter 4.7, libplacebo 3.3, spirv-cross 3.0 |
| linux-x64 | 47 MiB | avcodec 12.8, gcrypt 6.5, avfilter 4.2, libplacebo 3.9, libmpv 2.5 |
| linux-arm64 | 43 MiB | avcodec 10.9, gcrypt 6.3, libplacebo 3.7, avfilter 3.7 |
| macos-x64 | 43 MiB | avcodec 13.7, avfilter 4.4, MoltenVK 3.9, libplacebo 3.3 |
| macos-arm64 | 38 MiB | avcodec 11.0, avfilter 3.6, MoltenVK 3.6, libplacebo 3.1 |
| windows-arm64 | 53 MiB | avcodec 10.6, shaderc 6.7, gcrypt 6.2, avfilter 3.5, libplacebo 3.0 |

Compressed artifact sizes: windows-x64 26.75 MB, windows-arm64 24.89 MB,
linux-x64 21.23 MB, linux-arm64 20.55 MB, macos-x64 19.41 MB,
macos-arm64 17.77 MB.

**Strip check (2026-11-07):** the Linux candidates still carry 6.5–6.9 MiB of
`.symtab` / `.debug_*` (libgcrypt ~5.2 MiB debug, plus libcdio/libaacs/libbdplus),
macOS ~1.1 MiB (libplacebo/libxml2/etc.), Windows 0. `package.sh` now strips at
the packaging boundary (Linux `--strip-unneeded`, macOS `-x` before codesign).

Notes:
- GPL full disc/network stack is a user decision; `libgcrypt` (~6.3 MiB) and the
  disc/network libraries account for most of the Windows/Linux delta over dev.9.
- Windows also carries shaderc + SPIRV-Cross (~10.4 MiB), required by the D3D11
  backend; removing them is out of scope.
- `avcodec`/`avfilter` trimming (filter whitelist) is out of scope for v0.1.1.

### 2.6 Community / upstream

- Vendored tree is upstream mpv **v0.42.0** (`b0841e8`); #16619/#17737/#16260,
  packet_pool incremental release, hwdec surface-pool derivation, #18613 and the
  0.42 frame-lifetime/ra_gl fixes are all present.
- #12566 (packet_pool fast quit) is still unmerged and drifted → not backported.
- #15099 / #16658 / #18022 have no upstream patch → not backported; keep as
  known risks (long-run leak, playlist, screenshot).
- No verbatim backport candidate exists for v0.1.1.

---

## 3. Confirmed cause and minimal fix

**Confirmed:** mpv 0.42 `hwdec-extra-frames=auto` in the Vulkan zero-copy path
adds ~50 MiB Working Set at 1080p with the Windows 8-slot frame ring.

**Fix (implemented in `Player`):**
- Reuse the existing `on_preloaded` weak-client hook (same place as the software
  thread cap).
- For video pixel area ≤ 1920×1088, set `hwdec-extra-frames=2`; above 1080p keep
  `auto`.
- A user-provided `hwdec-extra-frames` option or a runtime change is never
  overridden.
- Tests: real-libmpv cases for 1080p → 2, 4K → auto, and explicit user value.

**Post-fix result:** the full 600 s example + HUD + 0.42 GPL full run peaks at
**234.0 MiB** (mean last 5 min 225.7 MiB, p95 231.4 MiB, 0/120 samples ≥250 MiB),
down from 294.1 MiB before the fix. **The hard gate passes.** CSV:
`.planning/tmp/p0-1080p-release-600s-042-fix.csv`.

---

## 4. Residual unknowns

- Linux/macOS 1080p Working Set: **not measured** (no real hardware); do not
  infer.
- The HUD/example UI contribution is included in the gate by user decision;
  a minimal harness measured ~254–259 MiB before the fix, so the HUD adds
  roughly 20–30 MiB.
- #15099 long-run leak cannot be proven or disproven by a 10-minute run.
- windows-arm64 artifact is now measured (53 MiB `lib/`, 24.89 MB compressed).
- The post-fix 600 s run is complete and passes the gate (234.0 MiB peak).

---

## 5. Artifacts

- `p0-1080p-release-600s-dev9.csv`
- `p0-1080p-release-600s-042.csv` (before fix)
- `p0-1080p-release-600s-042-fix.csv` (after fix)
- `p0-min-042-extra-{auto,1,2}.csv`
- `p0-1080p-042-gpu-60s.csv`
- `.planning/tmp/p0-artifacts/` (six-target candidate bundles)
- `.planning/tmp/p0-sample.ps1`, `probe_8k.dart`, `p0-events.dart`

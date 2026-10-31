# ADR 0006 — Per-platform default hwdec lists

Status: accepted
Accepted: 2026-10-28 by the user (.planning/phases/16-hardware-decode-zero-copy/evidence/decisions.txt, decision=hwdec-defaults)
Date: 2026-10-28
Related: ADR 0001 (Vulkan render backend), ADR 0004 (render backend
reporting), ADR 0005 (macOS Metal route), `.planning/REQUIREMENTS.md`
HWD-01 / HWD-02 / HWD-03 / HWD-05.

Statements that this project cannot prove are marked `unverified`.

## Context

`Player()` used one list on every platform, `vulkan,d3d11va-copy,auto-safe`
(player.dart before this change). mpv works through such a list in order
(`native/mpv/video/decode/vd_lavc.c`):

* A non-`-copy` entry that has no interop on the active renderer fails with
  "Could not create device." and mpv continues with the next entry
  (vd_lavc.c:586-592). It never copies back.
* A `-copy` entry decodes on its own device, so it can always be created. Placed
  before a zero-copy entry it wins and copies every frame back to system memory.
* `auto-safe` is a whitelist (the `HWDEC_FLAG_WHITELIST` entries of
  `hwdec_autoprobe_info`, vd_lavc.c:271-292) sorted by `hwdec_compare`, which
  lists non-copying entries before copying ones (vd_lavc.c:294-312).

Consequences of the old list:

* Windows on the D3D11 backend: `vulkan` has no interop and is skipped, then
  `d3d11va-copy` is created and wins before `d3d11va` zero-copy is ever tried.
  That blocks HWD-02.
* macOS: the leading `vulkan` registers an interop (MoltenVK) but cannot decode,
  costing one extra fallback round (research Pitfall 2 / A7). The hosted macOS
  probe still ended on `videotoolbox` with `hwdecInterop=videotoolbox,vulkan`
  (evidence/hwdec-spike.txt, macos-route run 40704363148).
* Linux: `auto-safe` already prefers `vaapi` over `vaapi-copy`, so the old list
  gave no explicit `vaapi` entry.

Hosted runners have no hardware video decoding: the Linux (llvmpipe) and Windows
(WARP) default runs ended in software with the old list
(evidence/hwdec-spike.txt, native-verify run 40704367040). They show nothing
about zero-copy.

Community context the user weighed: media-kit#1278 and media-kit#296 (Windows
media_kit is limited to `-copy` hwdec through ANGLE, giving high CPU and power;
it waits for mpv PR #17764, which is our patch 0010); mpv#12948 and PR #15815
(upstream moving to safe-by-default hwdec lists).

## Options

1. Keep one list for all platforms (no change).
2. Per-platform lists with zero-copy candidates first (chosen), and
   `d3d11va-zero-copy` left at mpv's default.
3. The same lists plus `d3d11va-zero-copy=yes` in the Player defaults.

## Decision

Per-platform lists, user choice `adopt`; every zero-copy candidate precedes every
`-copy` entry and `auto-safe`, and each list ends with `auto-safe`:

| Platform | `hwdec` |
|---|---|
| windows | `vulkan,d3d11va,d3d11va-copy,auto-safe` |
| linux | `vulkan,vaapi,auto-safe` |
| macos | `videotoolbox,auto-safe` |
| other | `auto-safe` |

* `d3d11va-zero-copy` stays at mpv's default (`no`). With `no`, `d3d11va` copies
  each frame GPU-to-GPU from the decoder surface to a shader resource
  (hwdec_d3d11va.c:204, 240-257): no CPU round trip. `yes` saves that copy but
  may sample the bottom/right edge wrongly because of padding and may hit driver
  bugs (options.rst:6495-6505), which conflicts with HWD-02's "no green or black
  frames". Plan 16-06 compares no/yes on the RTX 4060 and only records data.
* A user-supplied `hwdec` always wins: the defaults map is spread before
  `...options` in the `Player` factory (test: `hwdec default yields to an
  explicit user hwdec option`).
* The platform switch is library-internal (`lib/src/player/hwdec_defaults.dart`,
  not exported, no new `Player`/`Mpv` member), so the public API is unchanged
  (api_freeze_test).

## Consequences

* Behavior change. Windows on the D3D11 backend gets `d3d11va` zero-copy by
  default (the benefit appears only with the D3D11 backend: forced today, the
  default if Phase 14 switches it; on the Vulkan backend `d3d11va` has no interop
  and is skipped, so behavior is unchanged). macOS loses one useless fallback
  round. Linux's real change depends on HWD-03 (a DRM render node so the vaapi
  interop loads, plans 16-03/16-04); on real hardware `vaapi` is `unverified`
  and a failure falls back to `vaapi-copy` inside `auto-safe`.
* Releasing it makes the new lists the defaults users rely on; reverting is
  itself a behavior change. Users keep full control through `options`.
* Known risks this change does not solve (all unverified follow-ups):
  mpv#13304 (`d3d11va` direct mode disables VRR in mpv's own swapchain; may not
  apply to a Flutter-composited texture); mpv#14934 (Vulkan hwdec 4K purple
  screen on amdvlk; `vulkan` was already first before this change); on hybrid-GPU
  laptops `d3d11va-copy` decodes on the default adapter
  (`video/d3d.c`, research Open Question 4), not Flutter's; not fixed here.

## Verification tiers

* Hosted CI proves list order, the fallback and software decoding only; the
  default HWDEC rows of the integration and macos-route runs must show the lists
  above (evidence/ci-runs-16-02.txt).
* `d3d11va` real zero-copy is verified on the RTX 4060 (plan 16-06).
* `vaapi` zero-copy: unverified (no real Linux GPU available).

## Re-evaluation triggers

* MoltenVK supports Vulkan Video (the macOS `vulkan` entry could return).
* The RTX 4060 comparison shows `d3d11va-zero-copy=yes` with a large gain and no
  bad frames.
* nvdec (HWD-F1) enters the bundle.
* mpv changes the `auto-safe` whitelist or `hwdec_compare` ordering.

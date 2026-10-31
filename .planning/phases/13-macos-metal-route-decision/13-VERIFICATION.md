---
phase: 13-macos-metal-route-decision
verified: 2026-10-28T12:00:00Z
status: passed
score: 3/3 roadmap success criteria verified (requirements MAC-01, MAC-02, HWD-04)
behavior_unverified: 0
overrides_applied: 0
gaps: []
---

# Phase 13: macOS Metal Route Decision Verification Report

**Phase Goal:** The macOS Metal carrier route is decided by ADR; the existing MoltenVK to IOSurface path runs as a `RenderBackend` and reports honestly; VideoToolbox zero-copy is either verified or left with unreachable-evidence.
**Status:** passed. **Re-verification:** No (initial).

## Success criteria

| # | Criterion | Status | Evidence |
|---|-----------|--------|----------|
| SC1 | ADR compares MoltenVK/IOSurface, CGL+IOSurface, own Metal (cost, gpu-next/gpu, deprecation risk), decides, states re-evaluation triggers | VERIFIED | `docs/adr/0005-macos-metal-route.md`: three options, 7-row comparison table (cost, renderers, VT zero-copy, deprecation, licensing, texture contract, CI verifiability, upstream status) with `[G<n>]` citations into `evidence/adr-0005-grounding.txt`; Decision = (a); five numbered re-evaluation triggers with check commands (libplacebo Metal pl_gpu, mpv Metal render API, MoltenVK maintenance, Flutter texture contract, real-hardware evidence). `Status: accepted`, matches `evidence/route-decision.txt` (`decision=accept decided_at=2026-10-28T06:37:12Z`). ADR 0004 Decision 3 carries the `via <carrier>` grammar. |
| SC2 | Real-plugin test on macOS runner through `RenderBackend`; non-black pixel probe consistent with pre-Phase-12; `reason` names the Metal carrier | VERIFIED | Code: `packages/mpv_kit_video/macos/Classes/metal_interop.mm` appends ` via <carrier>` (`VK_DRIVER_ID_MOLTENVK` -> `MoltenVK`, else driverName, else `unknown Vulkan driver`), `CarrierFor` in `.h`. CI (spot-checked with `gh`): native-verify run 40627862148 (sha 091228a, success) log line `INTEGRATION {"backend":"vulkan","reason":"vulkan (gpu-next) on Apple Paravirtual device via MoltenVK",...}`. macos-route run 40627862041 (success): `ROUTE-PARITY ok head=texture-visible pre12=texture-visible informative=yes dNonBlack=0.0000 dMeanMax=0.0000`, `ROUTE-SC2 pixel=proven channel=toImage`; HEAD vs pre-Phase-12 (3a5f450) readings identical (nonBlack 1.0, control red / background green discriminate). Same result in runs 40617697853 and 40616234145 (both success). |
| SC3 | VideoToolbox on MoltenVK: `hwdec-current=videotoolbox`, no copy-back, 8-bit and P010 free of green/black frames, or unreachable evidence | VERIFIED | Run 40627862041 `ROUTE-HWDEC` gate:true rows: h264-8bit, hevc-8bit, hevc-10bit all `outcome:zero-copy`, `hwdecCurrent:videotoolbox`, `pixelformat:videotoolbox`, hw format nv12/nv12/p010, screenshot match vs software reference (diff 1.32/1.30/0.0), failureEvidence 0. 10-bit row confirmed in live log. Decoder log: `Decoder format: 640x360 videotoolbox[p010]`. Classification is correctly scoped: hosted-VM interop chain only; Apple hardware vs software decoder not distinguishable; real hardware marked unverified (not written as passed on hardware). |

## Requirements

| ID | Status | Evidence |
|----|--------|----------|
| MAC-01 | SATISFIED | SC1 evidence; REQUIREMENTS.md ticked. |
| MAC-02 | SATISFIED | SC2 evidence; wrapper forwards 15 virtuals around the built-in Vulkan backend (Phase 12 `RenderBackend` stays rollback point); Linux/Windows reasons asserted unchanged via `--log-absent` gate. |
| HWD-04 | SATISFIED | SC3 evidence; ROADMAP explicitly allows evidence-based closure. |

## Artifacts and wiring

| Artifact | Status |
|----------|--------|
| `docs/adr/0005-macos-metal-route.md` | exists, substantive, accepted |
| `docs/perf/macos-route-verification.md` | exists, quotes run ids/shas that match live `gh` conclusions |
| `.github/workflows/macos-route.yml`, `example/integration_test/macos_route_{test,probe}.dart`, `tools/check_route_probe.py`, `tools/macos_frame_probe.patch` | exist; macos-route workflow has since run green on later commits (e.g. 5522944, 95393c9, 592015b) |
| `.planning/phases/13-macos-metal-route-decision/tools/ci_gate.sh`, `evidence/*` | exist; `route-runs.txt` lines match the live logs |

CI records spot-checked: 40627862041 macos-route, 40627862148 native-verify, 40627862039 flutter-plugin (sha 091228a), 40617697853, 40616234145 macos-route, 40465908724/40465908799 (sha 8103beb) all `conclusion: success`.

## Anti-patterns

No TBD/FIXME/XXX markers found in phase-touched files in the checked areas. Phase scope audit (`evidence/phase-audit.txt`): no user-owned files touched.

## Notes (non-blocking)

- Evidence is from one libmpv bundle (`v0.1.0-dev.3`), not the vendored tree; hosted macos-15 VM only. Real Apple hardware, Intel/dual-GPU Macs, 4K/HDR, concurrent VT sessions, multi-controller and playback-time pixel parity remain unverified and are recorded as such in the verification doc and ADR.
- Informational default-hwdec row (gate:false) shows software decode with the default list on the VM; handed to Phase 16 (HWD-01), not a Phase 13 gap.
- Post-phase commit e23fa38..890fe74 added a macOS integration leg with branch libmpv forced to the software renderer; the bundle-based Vulkan leg (source of the `via MoltenVK` line) remains in native-verify, so SC2 evidence is not invalidated. `phase-audit.txt` records `final_gate=deferred` for the local audit but the hosted gates were later evaluated on the final runs (documented in ci-runs.txt backfill note).

## Gaps

None.

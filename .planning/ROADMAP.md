# Roadmap: mpv_kit

## Milestones

- ✅ **v1.0 Driver-Stability Baseline** — Phases 1-6 (archived 2026-10-24; 21/21 requirements delivered)
- ✅ **v2.0 GPU-Next Optimization & Full-Rate UHD** — Phases 7-11 (closed 2026-10-25; 6/10 requirements delivered, 4 deferred)
- ✅ **v3.0 统一渲染生命周期与平台原生图形后端** — Phases 12-17.1 (shipped 2026-10-31; 29/31 requirements delivered; GitHub Release v0.1.0-dev.4, pub.dev 0.1.0-dev.4)

## Phases

<details>
<summary>✅ v1.0 Driver-Stability Baseline (Phases 1-6) — ARCHIVED 2026-10-24</summary>

Phase details, success criteria and verification records live in
`.planning/milestones/v1-phases/`.

</details>

<details>
<summary>✅ v2.0 GPU-Next Optimization & Full-Rate UHD (Phases 7-11) — CLOSED 2026-10-25</summary>

Closed by user decision as a simple close-out: incomplete phases were recorded
as not delivered rather than driven to green. Delivery is partial and is stated
as such below — no phase was rewritten to look complete.

- [x] Phase 7: mpv-master Vendor Advance & gpu-next Regression (2/2 plans) — completed 2026-10-24
- [x] Phase 8: Debug HUD & Drag-and-Drop (1/1 plan) — completed 2026-10-25
- [ ] Phase 9: 8K Full-Rate (1/2 plans) — UHD-01 delivered (frame-size-derived demuxer budgets + runtime auto-tune); UHD-02 unproven (8K survived 60 s with all v1 gates green, but no 30-minute run)
- [ ] Phase 10: Composition Spike (6/9 plans) — REA report 03 and ADR 0003 landed; ADR verdict stays `inconclusive`, D-05 never exercised; 10-08/10-09 not executed, 10-06 (ADR final verdict) never written
- [ ] Phase 11: Native Composition Path (0 plans) — not started; COMP-02/COMP-03 deferred

Full phase details: `.planning/milestones/v2.0-ROADMAP.md`
Requirements archive: `.planning/milestones/v2.0-REQUIREMENTS.md`

</details>

<details>
<summary>✅ v3.0 统一渲染生命周期与平台原生图形后端 (Phases 12-17.1) — SHIPPED 2026-10-31</summary>

Closeout type `override_closeout`: every phase completed and passed its
verifier; five reports later went stale when follow-up commits touched covered
files and were not re-run (user decision). D3D-08 was not switched (user kept
Vulkan first on Windows) and HWD-03 has no real Linux GPU evidence.

- [x] Phase 12: RenderBackend Seam (12/12 plans) — completed 2026-10-27
- [x] Phase 13: macOS Metal Route Decision (6/6 plans) — completed 2026-10-28
- [x] Phase 14: Windows Native D3D11 Backend (11/11 plans) — completed 2026-10-29 (D3D-08 not switched)
- [x] Phase 15: Linux OpenGL Backend (7/7 plans) — completed 2026-10-28
- [x] Phase 16: Hardware-Decode Zero-Copy (6/6 plans) — completed 2026-10-29
- [x] Phase 17: Fallback Hardening & UHD Regression (5/5 plans) — completed 2026-10-30
- [x] Phase 17.1: Release and pin a libmpv bundle with the D3D11 and OpenGL backends (INSERTED, 7/7 plans) — completed 2026-10-31

Full phase details: `.planning/milestones/v3.0-ROADMAP.md`
Requirements archive: `.planning/milestones/v3.0-REQUIREMENTS.md`
Milestone audit: `.planning/milestones/v3.0-MILESTONE-AUDIT.md`
Phase directories: `.planning/milestones/v3.0-phases/`; quick tasks: `.planning/milestones/v3.0-quick/`

</details>

## Next Milestone

Not started. Run `/gsd-new-milestone` (candidates are listed under Active in
`.planning/PROJECT.md`). Phase numbering continues at 18.

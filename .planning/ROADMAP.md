# Roadmap: mpv_kit

## Milestones

- ✅ **v1.0 Driver-Stability Baseline** — Phases 1-6 (archived 2026-10-24; 21/21 requirements delivered)
- ✅ **v2.0 GPU-Next Optimization & Full-Rate UHD** — Phases 7-11 (closed 2026-10-25; 6/10 requirements delivered, 4 deferred)

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

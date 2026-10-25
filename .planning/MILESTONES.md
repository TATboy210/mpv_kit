# Milestones

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

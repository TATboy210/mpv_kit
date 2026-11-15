# Project Retrospective

*A living document updated after each milestone. Lessons feed forward into future planning.*

## Milestone: v2.0 — GPU-Next Optimization & Full-Rate UHD

**Closed:** 2026-10-25 (`override_closeout`, user decision)
**Phases:** 5 in scope (2 complete, 1 partial, 2 not delivered) | **Plans:** 14 (10 summaries)

### What Was Built

- Vendor provenance made exact at mpv 0.41.0-1115 (gb2c255c13e8e), and the
  advance corrected v1's misattributed `0008` deltas.
- gpu-next regression on the new base: seek-recovery test, full suites and
  benchmarks green (the 4K 30-minute re-run was blocked by a full host disk,
  recorded as environment, not as a pass).
- The example became a debugging cockpit: five-group HUD, live event overlay,
  drag-and-drop playback.
- Frame-size-derived demuxer queue budgets with runtime auto-tune (UHD-01):
  1080p/4K/8K formula matrix in tests; 8K survived 60 s with all v1 gates green.
- A per-path static reverse-engineering of Flutter 3.47.8's external-texture
  consumption (report 03) and ADR 0003: both surface types bind through ANGLE,
  no fence or keyed mutex, Impeller only removes Ganesh's per-resolve work.

### What Worked

- Evidence-first composition work: the REA corrected a wrong premise ("enable
  Impeller" = "no ANGLE") before any production code was written.
- Identity gating on smoke runs: a run whose engine identity is unproven can
  never become a renderer verdict. This turned a would-be false pass/fail into
  an honest `inconclusive`.
- The harness defect was found, fixed and re-run rather than blamed on the
  renderer; the second abort was recorded as an evidence gap, not as a crash.

### What Was Inefficient

- The 10-05 soak abort consumed a full gap-closure cycle and never reproduced
  (5/5, 5/5, 25/25, all exit 0). Three runs produced no diagnosis.
- Phase 10's verification loop kept expanding (9 plans for a spike) while the
  actual decision (settle D-05) stayed blocked behind its own harness.
- Phase 9's second plan (30-minute 8K endurance) never started, leaving UHD-02
  in a state where 60 s passed but the requirement was not met.

### Patterns Established

- Requirement verdicts must match evidence strength: `inconclusive` is not
  `failed`, and neither may be written as "infeasible".
- Static evidence and runtime smoke answer different questions and are never
  interchangeable.
- Close-out may be an override, but it must be recorded as such: known gaps,
  deferred requirements and the override count go into MILESTONES.md rather
  than being smoothed away.

### Key Lessons

1. A spike whose acceptance gate depends on a harness defect will fail
   indefinitely; fix or replace the gate before scheduling more reruns.
2. When the user says "simple close-out", stop the verification loop and record
   the gap — do not manufacture a pass.
3. Before/after performance claims need the renderer identity recorded on both
   sides; v2.0's historical 4K baseline did not record it and cannot be reused
   as a Skia baseline.

### Cost Observations

- Model mix: not recorded for this milestone.
- Sessions: multiple; Phase 10 plan 01 alone took ~2 h 10 m (Ghidra decompile).
- Notable: the two most expensive activities were REA decompilation and
  repeated smoke reruns; both produced evidence, but the reruns produced no
  diagnosis.

---

## Milestone: v3.0 — 统一渲染生命周期与平台原生图形后端

**Shipped:** 2026-10-31
**Phases:** 7 (12–17.1) | **Plans:** 54

### What Was Built
- One `RenderBackend` lifecycle (Phase 12) moved Vulkan and software behind a seam, guarded by fake-libmpv golden tests and an RTX 4060 baseline taken before any move.
- Native backends per platform: Windows D3D11 through the upstream D3D11 render API (patch 0010, no ANGLE/EGL, CI-enforced), Linux OpenGL through EGLImage export, macOS MoltenVK→IOSurface fixed by ADR 0005.
- Cross-backend hwdec defaults (ADR 0006) with every test asserting zero-copy, copy-back or software; fault injection, a forced-backend CI matrix and per-backend 4K/soak gates (Phase 17).
- Consumers actually received it: GitHub Release v0.1.0-dev.4, bundles pinned to it, pinned-only CI cells on the consumer load path, and pub.dev 0.1.0-dev.4 for all three packages (Phase 17.1, quick 261031-wrf).

### What Worked
- Baseline-first and golden-first: measuring the unchanged path before the refactor made the D-05 fix provable (`resolved-by-fix`, 100/100 rounds) instead of anecdotal.
- Gate tools proven on finished runs before first use (17.1-03) caught a regex that matched the workflow's own echoed comment.
- A blocking go/no-go before the irreversible tag push let the user reorder work (no-go on b524b3a, umq first, then go on a re-gated 47cbbf2) at no cost.
- Independent re-checks by the orchestrator (gh run state, release assets, pub.dev versions) before relaying any agent claim.

### What Was Inefficient
- Bundle pin lag: v3.0 built new backends but consumers stayed on dev.3 until the milestone audit (INT-1/INT-2) forced an inserted phase; the pin should move with the backend.
- A masked Windows test failure (pwsh swallowing exit codes) went unnoticed for several phases (D-05 in 17.1).
- Verification fingerprints went stale for five phases because follow-up quick tasks touched covered files after verification; the close had to be an override.
- Plans written before a renderer change (0e792c8 FIFO queue) needed per-dispatch corrections from the orchestrator.

### Patterns Established
- Release candidates are gated twice (PR gate, then a release.yml rehearsal on the branch ref) and tagged only after the user's own go, with a single-ref `--no-follow-tags` push.
- Pinned-only CI cells must load libmpv the way a consumer app does (no `MPV_KIT_LIBMPV_PATH`, app bundle `lib/`, identity tool `app_copy=same`).
- Hardware sessions: gate before every run, never shorten or rerun until green, record the user's verbatim `start`.
- Protected user files are backed up and `cmp`-checked around every gsd-tools call; staging is by explicit path only.

### Key Lessons
1. Ship the artifact consumers use as part of the feature phase, not as audit follow-up: a backend is not delivered until the pinned bundle carries it.
2. Treat any CI step that can swallow a failing exit code as a defect in its own right; prove gates red before trusting them green.
3. Re-verify (or schedule verification) after follow-up commits that touch a verified phase's covered files, before the milestone close.
4. Probe-only instrumentation (umq) pays off: it found that every frame hands Flutter a new shared handle (7440/7440), the lead for the next performance milestone.

### Cost Observations
- Model mix: orchestrator Opus; executors, verifiers and reviewers Sonnet.
- Sessions: several (paused/resumed around 17.1-03 and the hardware checkpoints).
- Notable: most wall-clock time went to hosted CI polling (≥120 s cadence) and the release rehearsal/tag runs (~25 min each), not to code.

## Cross-Milestone Trends

### Process Evolution

| Milestone | Sessions | Phases | Key Change |
|-----------|----------|--------|------------|
| v1.0 | — | 6 | Failure-injection + soak invariants; five CI gates |
| v2.0 | — | 5 | Evidence-first composition spike; override close-out with recorded gaps |
| v3.0 | several | 7 | Baseline/golden-first refactor; twice-gated release with explicit go; consumer-path pinned CI |

### Cumulative Quality

| Milestone | Tests | Coverage | Zero-Dep Additions |
|-----------|-------|----------|-------------------|
| v1.0 | see v1 archives | 80% gate (mpv_kit) | — |
| v2.0 | +seek recovery, +formula matrix, +smoke harness | unchanged gates | 0 new runtime deps |
| v3.0 | +renderer golden/fault/swap tests, +forced-backend matrix, +pinned-bundle tests | 80% gate kept; ANGLE-free and pin gates added | 0 new Dart runtime deps |

### Top Lessons (Verified Across Milestones)

1. Verification conclusions must separate "measured and passed" from "not run
   because of the environment" (v1 Phase 1; re-confirmed by v2.0's 4K re-run).
2. Plans that grow a gap-closure tail are a signal that the acceptance gate is
   wrong, not that more plans are needed (v2.0 Phase 10).
3. A feature is delivered only when the artifact consumers resolve carries it
   (v3.0: backends built in Phases 14/15 reached users only after 17.1 pinned
   and published the bundle).

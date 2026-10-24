---
phase: "10"
slug: "composition-spike"
# status lifecycle: draft (seeded by plan-phase) → validated (set by validate-phase §6)
status: draft
nyquist_compliant: false
wave_0_complete: false
created: "2026-10-24"
---

# Phase 10 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | `dart test` (mpv_kit) + `flutter test -d windows` (example integration_test) + shell evidence gates |
| **Config file** | `packages/mpv_kit/dart_test.yaml`, `example/integration_test/` |
| **Quick run command** | `cd packages/mpv_kit && dart analyze --fatal-infos` |
| **Full suite command** | `cd example && flutter test integration_test/impeller_smoke_test.dart -d windows` (plus `--enable-impeller=false` control) |
| **Estimated runtime** | ~60–120 s quick; the smoke adds roughly 2–4 min per run (30 s continuous + 100 recycles + engine startup) |

This phase's primary verification is **evidence artifacts** (hashes, anchor counts, decompiled pseudocode, bench lines), not a unit-test suite. The shell gates below are the contract.

---

## Sampling Rate

- **After every task commit:** Run the quick command plus that task's own evidence gate.
- **After every plan wave:** Run the full suite command once (wave 1 ends with harness construction, wave 2 ends with the ADR).
- **Before `/gsd-verify-work`:** The full suite must be green, or the run must be recorded as `inconclusive` with its reason — never silently absent.
- **Max feedback latency:** ~180 s.

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 10-01-01 | 10-01 | 1 | COMP-01 | T-10-01 / T-10-03 | Artifact identity is pinned to the SDK path; the stale ephemeral copy can never be mistaken for it | evidence | size + sha256 + anchor counts + import-table greps | ✅ | ⬜ pending |
| 10-01-02 | 10-01 | 1 | COMP-01 | T-10-02 | Decompiled evidence is per-path and attributive, not a single blended narrative | evidence | per-path heading counts (`Allocation`/`Fence semantics`/`Device ownership` == 3 each) + keyed-mutex answer | ❌ W0 | ⬜ pending |
| 10-02-01 | 10-02 | 1 | COMP-01 | T-10-05..T-10-08 | Disk gate records a resource stop as `inconclusive`; harness asserts resolved libmpv path and `backend == vulkan` before measuring; CI pin moves to 3.47.8 | mixed | `evidence/disk-gate.txt`, `sdk-3.47.8.txt`, `dart analyze --fatal-infos`, harness greps | ❌ W0 | ⬜ pending |
| 10-03-01 | 10-03 | 2 | COMP-01 | T-10-09 / T-10-10 | Every bucket records renderer identity; RGBA8 rejection and black frames cannot be classified `pass`; idle-during-unmount is separated | behavioural | two run logs + `impeller-bench.txt` bucket/identity lines | ❌ W0 | ⬜ pending |
| 10-03-02 | 10-03 | 2 | COMP-01 | T-10-11 | The ADR answers "shorter or cheaper", never "no ANGLE"; identity-unproven cannot become 不可行; open questions are owned | evidence | ADR section greps + `verdict:` + identity-guard rule + 5 open-question rows | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `example/integration_test/impeller_smoke_test.dart` — single `testWidgets`, three parts, BENCH lines (10-02 Task 1 creates it)
- [ ] `docs/reverse-engineering/03-flutter-windows-texture-consumption.md` — created by 10-01 Task 2
- [ ] `docs/adr/0003-windows-composition-path.md` — created by 10-03 Task 2
- [ ] `evidence/` directory under the phase dir — created by 10-01 Task 1
- [ ] Local libmpv on PATH (`bt/`) plus `MPV_KIT_LIBMPV_PATH`, asserted by the harness preflight

*The three deliverables ARE the Wave 0 gaps; there is no pre-existing harness to extend.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| A human confirms the decompiled pseudocode is faithful to the disassembly at the cited addresses | COMP-01 | Reading pseudocode for correctness is a judgement call; the automated gate only proves structure and presence | Open `03-…md` next to `decompilation.txt`; spot-check three annotations against the raw listing |
| The engine log line `Using the Impeller rendering backend` is observed for the actual run | COMP-01 | Log forwarding under `flutter test -d windows` is unverified; the fallback is a short `flutter run` capture | If the smoke cannot surface the line, run `flutter run -d windows` on `example/` and capture the first 20 lines |

*If the manual row cannot be completed, the run is `inconclusive` — not `pass` and not `failed`.*

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 180s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending

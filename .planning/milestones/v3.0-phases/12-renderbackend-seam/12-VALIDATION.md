---
phase: "12"
slug: "renderbackend-seam"
# status lifecycle: draft → validated; validated + nyquist_compliant: false = PARTIAL
status: validated
nyquist_compliant: false
wave_0_complete: true
created: "2026-10-27"
---

# Phase 12 — Validation Strategy

> Retroactive validation map (State B, no prior VALIDATION.md), built from a read-only audit of the repo.
> Nyquist gaps ①–⑤ were NOT filled. User decision: "作为额外的待办事项，等整个阶段完成后再回过头来解决".
> Tracked in `.planning/todos/pending/2026-10-27-phase-12-nyquist-validation-gaps.md`.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Meson test (native C/C++, fake libmpv via `native/tests/renderer_harness.h`); `flutter_test`; Flutter `integration_test` (real plugin) |
| **Config file** | `native/tests/meson.build`; `packages/mpv_kit_video/test/`; `example/integration_test/` |
| **Quick run command** | `meson test -C tests-out` + `flutter test` in `packages/mpv_kit_video` |
| **Full suite command** | `tools/ci_gate.sh` (native-verify + flutter-plugin); `tools/constants_audit.sh`; `sha256sum -c .planning/phases/12-renderbackend-seam/evidence/golden-freeze.sha256` |
| **Estimated runtime** | native ~60 s local; full CI gate 15 jobs |

- Native: `render_vk_smoke`, `render_vk_smoke_gpu`, `stream_bridge`, `video_renderer_golden_{sw,vk,vk_fallback,vk_retire_twice,sw_retire_twice}`, `video_renderer_api_test`, `video_renderer_affinity_test`.
- Dart: `controller_channel_test.dart`, `video_controller_test.dart` (coverage gate 80%, final 91.4%).
- Integration: `example/integration_test/real_plugin_test.dart` (INTEGRATION + INTEGRATION-SOAK lines), native-verify `integration-test` on ubuntu/windows/macos.
- Manual (RTX 4060): `impeller_smoke_test.dart` (+ `impeller_smoke_modes.dart`), `uhd_endurance_test.dart`.

Final full gate: CI-GATE ok on `a3dc4c2` (native-verify 40421971121, flutter-plugin 40421971099), 15/15 jobs. Vulkan goldens SKIP on hosted Windows (user-accepted).

---

## Sampling Rate

- **After every task commit:** native `meson test` + package `flutter test`
- **After every plan wave:** push + `tools/ci_gate.sh`
- **Before `/gsd-verify-work`:** full CI gate green + golden freeze sha check
- **Max feedback latency:** ~60 s local; CI per wave

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 12-01-01 | 01 | 1 | RBE-02/04 | — | N/A | human checkpoint (push authorization) | — | n/a | ✅ approved |
| 12-01-02 | 01 | 1 | RBE-02/04 | — | N/A | CI smoke | `tools/ci_gate.sh` | ✅ | ✅ green |
| 12-01-03 | 01 | 1 | RBE-02/04 | — | N/A | integration | native-verify `integration-test`, `flutter-video-coverage` | ✅ | ✅ green |
| 12-02-01..02 | 02 | 1 | RBE-01 | — | N/A | manual (RTX 4060 harness) | `impeller_smoke_test.dart` (manual) | ✅ | ⚠️ manual |
| 12-03-01 | 03 | 2 | RBE-07/08 | — | N/A | unit (Dart) | `flutter test test/video_controller_test.dart` | ✅ | ✅ green |
| 12-03-02 | 03 | 2 | RBE-07/08 | — | N/A | docs (ADR 0004, READMEs) | — | ✅ | ✅ green |
| 12-04-01..02 | 04 | 2 | RBE-01 | — | N/A | manual (baseline runs) | — | ✅ | ⚠️ manual |
| 12-04-03 | 04 | 2 | RBE-01 | — | N/A | human checkpoint | — | n/a | ✅ approved |
| 12-05-01..02 | 05 | 2 | RBE-02 | — | N/A | native golden | `meson test -C tests-out video_renderer_golden_sw` | ✅ | ✅ green |
| 12-06-01..02 | 06 | 3 | RBE-07 | — | N/A | native golden (reason lines) | `meson test -C tests-out video_renderer_golden_sw video_renderer_golden_vk` | ✅ | ✅ green |
| 12-07-01..02 | 07 | 4 | RBE-02/06 | — | N/A | native golden (RED-first) | `meson test -C tests-out video_renderer_golden_vk video_renderer_golden_vk_fallback video_renderer_golden_vk_retire_twice video_renderer_golden_sw_retire_twice` | ✅ | ✅ green (hosted Windows SKIP) |
| 12-07-03 | 07 | 4 | RBE-02 | — | N/A | freeze check | `sha256sum -c .planning/phases/12-renderbackend-seam/evidence/golden-freeze.sha256` | ✅ | ✅ green (local only, gap ④) |
| 12-08-01..02 | 08 | 5 | RBE-01/06 | — | N/A | manual (post-fix runs) | — | ✅ | ⚠️ manual |
| 12-08-03 | 08 | 5 | RBE-01 | — | N/A | human checkpoint | — | n/a | ✅ approved |
| 12-09-01..03 | 09 | 6 | RBE-03/04/06 | — | N/A | native golden (equivalence) + grep | `meson test -C tests-out` | ✅ | ✅ green (call-order contract untested, gap ①) |
| 12-10-01 | 10 | 7 | RBE-07 | — | N/A | Dart unit + CI log regex | `flutter test`; `tools/ci_gate.sh` | ✅ | ⚠️ partial (gap ②) |
| 12-10-02 | 10 | 7 | RBE-08 | — | N/A | native unit (fake libmpv) | `meson test -C tests-out video_renderer_api_test` | ✅ | ⚠️ partial (gap ③) |
| 12-11-01 | 11 | 8 | RBE-05/06 | — | N/A | native unit (RED-first) | `meson test -C tests-out video_renderer_affinity_test` | ✅ | ⚠️ partial (gap ①) |
| 12-11-02 | 11 | 8 | RBE-06 | — | N/A | integration soak | native-verify `integration-test` (INTEGRATION-SOAK) | ✅ | ✅ green |
| 12-12-01 | 12 | 9 | RBE-01/04/05/06 | — | N/A | CI full gate + audit | `tools/ci_gate.sh`; `tools/constants_audit.sh` | ✅ | ✅ green (audit local only, gap ④) |
| 12-12-02 | 12 | 9 | RBE-01/04 | — | N/A | manual (RTX 4060) | `uhd_endurance_test.dart` (manual) | ✅ | ⚠️ manual |
| 12-12-03 | 12 | 9 | all | — | N/A | human checkpoint | — | n/a | ✅ approved |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky/partial/manual*

---

## Requirement Coverage

| Requirement | Status | Evidence | Gap |
|-------------|--------|----------|-----|
| RBE-01 | PARTIAL | manual RTX 4060 runs only; d05 pixel probe and resize-front round 2 recorded, not fixed (todo `2026-10-27-diagnose-second-controller-first-frame-stall-in-resize-front.md`) | ⑤ |
| RBE-02 | COVERED | sw/vk goldens, RED-first logs, freeze sha | — |
| RBE-03 | COVERED (behaviour) | goldens + grep checks; interface call-order contract untested | ① |
| RBE-04 | COVERED (automatable part) | frozen goldens, `constants_audit.sh` local; 4K parity manual (final-runs uhd4k pass) | ④ |
| RBE-05 | PARTIAL | thread identity via `video_renderer_affinity_test` + `AssertRenderThread`; "backend context bound" not asserted | ① |
| RBE-06 | COVERED | DOUBLE DESTROY / USE AFTER DESTROY invariants, retire scenarios, sanitizers, soak | — |
| RBE-07 | COVERED | Dart freeze/wire-name tests, reason lines in goldens, ADR 0004; real-plugin grammar only via ci_gate log regex | ② |
| RBE-08 | PARTIAL | switch logic via `video_renderer_api_test` vs fake; no CI real-plugin run with `MPV_KIT_VIDEO_API` | ③ |

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements (harness, goldens and gate scripts were built inside the phase).

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| 4K 30-min parity vs Phase 4 | RBE-04/01 | real GPU + long run | RTX 4060, `uhd_endurance_test.dart` |
| Rendered 4K 600 s vs 12-08 | RBE-01/04 | real GPU | RTX 4060, rendered 4K variant |
| d05 / cycles / resize-front 100-round soaks | RBE-01 | real GPU, Impeller on/off | `impeller_smoke_test.dart` modes |
| Pixel probe / window visibility | RBE-01 | visible window on a real display | `MPV_KIT_SMOKE_DIAG=probe` |
| Windows D3D11/Vulkan real interop | RBE-01/03 | hosted Windows has no Vulkan | RTX 4060 runs |
| Real plugin with `MPV_KIT_VIDEO_API=d3d11` | RBE-08 | real D3D11 device | RTX 4060 example run |
| Linux real GPU, macOS real hardware | RBE-01 | hardware unavailable (未验证) | — |
| Human checkpoints 12-01 T1, 12-04 T3, 12-08 T3, 12-12 T3 | — | blocking-human gates | recorded in SUMMARYs |

---

## Deferred Nyquist Gaps

Not filled by user decision ("作为额外的待办事项，等整个阶段完成后再回过头来解决"). Details in `.planning/todos/pending/2026-10-27-phase-12-nyquist-validation-gaps.md`.

1. ① RBE-05/03: backend bind / call-order contract test (`native/tests/video_renderer_bind_test.cc`).
2. ② RBE-07: real-plugin reason grammar integration test (`example/integration_test/backend_reason_test.dart`).
3. ③ RBE-08: real-plugin `MPV_KIT_VIDEO_API=software` CI step (`example/integration_test/api_override_test.dart`).
4. ④ RBE-04: `constants_audit.sh` + golden-freeze sha check in native-verify CI.
5. ⑤ RBE-01: scheduled cycles-mode 100-round run on lavapipe.

---

## Validation Sign-Off

- [x] All tasks have automated verify or a documented manual/human checkpoint
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [ ] `nyquist_compliant: true`: not set; gaps ①–⑤ deferred by user

**Approval:** validated 2026-10-27 (partial; Nyquist gaps deferred to todo)

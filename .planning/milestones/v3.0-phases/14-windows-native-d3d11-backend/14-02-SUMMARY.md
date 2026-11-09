---
phase: 14-windows-native-d3d11-backend
plan: 02
subsystem: infra
tags: [vulkan, pickdevice, reason-grammar, golden-freeze, adr-0004, windows]

requires:
  - phase: 14-01
    provides: push authorization (green-plus-scratch) and the parameterised ci_gate.sh
  - phase: 12-renderbackend-seam
    provides: frozen golden harness and golden-freeze.sha256
provides:
  - "VulkanContext::PickDevice rejection reason split by cause, with device names"
  - "Phase 14 golden freeze manifest golden-freeze-14.sha256 (decision=A)"
  - "ADR 0004 Decision 3 why vocabulary entry for the split"
affects: [14-03, 14-07, 14-10, 13-01, 13-05, 15-04, 15-07]

actuals:
  tokens: 9500
  tasks: 2
  commits: 2
plan_head_before: d8dd0c0bf2dbe992f867f8f10855ac70a388d8b1
plan_head_after: f799e41b8a7ed350dcd0087edc31ee375df598e7

tech-stack:
  added: []
  patterns:
    - "frozen golden re-freeze: new manifest file whose existence switches the shared freeze gate"

key-files:
  created:
    - .planning/phases/14-windows-native-d3d11-backend/evidence/golden-freeze-14.sha256
    - .planning/phases/14-windows-native-d3d11-backend/evidence/local-14-02-goldens.log
    - .planning/phases/14-windows-native-d3d11-backend/evidence/ci-runs-14-02.txt
  modified:
    - packages/mpv_kit_video/src/vulkan_backend.cc
    - native/tests/renderer_harness.h
    - native/tests/golden/vk.txt
    - native/tests/video_renderer_golden_vk.cc
    - native/tests/video_renderer_golden_vk_fallback.cc
    - native/tests/video_renderer_golden_vk_retire_twice.cc
    - native/tests/video_renderer_api_test.cc
    - native/tests/video_renderer_affinity_test.cc
    - docs/adr/0004-render-backend-reporting.md

key-decisions:
  - "Task 1 answered A (verbatim reply `A`): reason carries device names; frozen harness, vk.txt line 57 and five skip probes changed; Phase 14 freeze manifest created"
  - "Windows AcceptDevice refusals (LUID mismatch and KMT BGRA8 import) are both reported as `<deviceName> is not the compositor adapter`"
  - "Known limitation accepted with A: on a dev host with more than one Vulkan device the device-not-shareable golden scenario gains an extra entry and mismatches"

requirements-completed: []
requirements-partial: [D3D-07]  # reason-text part only; device_lost mapping and the auto-chain fallback land in later plans, so REQUIREMENTS.md was not ticked

coverage:
  - id: C1
    description: "PickDevice reports per-device rejection reasons (version vs compositor adapter); zero devices keeps the original wording"
    requirement: "D3D-07"
    verification:
      - kind: other
        ref: "build/phase14/goldens (not versioned): MSVC /W4 /WX, RED golden_vk rc=1 before the PickDevice change, GREEN ALL rc=0 after; local-14-02-goldens.log"
        status: pass
    human_judgment: false
  - id: C2
    description: "CI golden/api/affinity tests green on linux x2, macos-15, windows-2025 and sanitizers for f799e41"
    requirement: "D3D-07"
    verification:
      - kind: other
        ref: "ci_gate.sh -> CI-GATE ok sha=f799e41b8a7ed350dcd0087edc31ee375df598e7 (native-verify run 40470534448, flutter-plugin run 40470534435), evidence/ci-runs-14-02.txt"
        status: pass
    human_judgment: false
  - id: C3
    description: "Shared freeze gate selects golden-freeze-14.sha256 and all five files verify; Phase 12 manifest unchanged"
    requirement: "D3D-07"
    verification:
      - kind: other
        ref: "sha256sum -c evidence/golden-freeze-14.sha256 -> 5x OK; git diff of Phase 12 golden-freeze.sha256 empty"
        status: pass
    human_judgment: false

duration: 70min
completed: 2026-10-27
status: complete
---

# Phase 14 Plan 02: PickDevice reject reason split Summary

**On a machine like the GTX 960 + iGPU laptop, the Vulkan failure reason now says which device failed and why (`Vulkan < 1.3 on <name>` or `<name> is not the compositor adapter`), with the Phase 12 golden freeze re-cut under a new Phase 14 manifest and CI green on every platform.**

## Performance

- **Duration:** about 70 min (most of it waiting for hosted CI)
- **Tasks:** 2 (Task 1 recorded from the orchestrator's checkpoint answer `A`)
- **Files modified:** 9 in the repo, 3 evidence files created

## Accomplishments

- `VulkanContext::PickDevice` collects one reason per enumerated device in enumeration order, joined with `, `. Zero physical devices still gives `no Vulkan 1.3 device shareable with the compositor`. Scoring and device selection are unchanged. `SanitizeReasonField(init_error)` in `VulkanRenderBackend::Create` still cleans the whole string (T-14-04), no new bypass.
- Frozen harness: `FakeVulkanInterop::AcceptDevice` records the device name before deciding, so `NormalizeReason` turns rejected names into `<device>`. `golden/vk.txt` line 57 now reads `<device> is not the compositor adapter` twice. The five Vulkan tests also skip on `Vulkan < 1.3 on`.
- ADR 0004 Decision 3 gained the split `why` entry with an example. 13-02's hunks (`via` carrier grammar, carrier bullet, macOS example, `Related:` header) were not touched; the edit sits in a different bullet.
- `golden-freeze-14.sha256` created with the decision-A header comment; the shared freeze gate now prints `golden-freeze manifest=...golden-freeze-14.sha256` and all five lines are OK. The Phase 12 manifest is unchanged.

## Task Commits

1. **Task 1: Decision checkpoint (answered `A`)** - recorded in `local-14-02-goldens.log` (`decision=A user_reply=A ...`) and in the manifest header; no separate commit.
2. **Task 2: Split, local goldens, CI** - `92fcf1a` (feat: product + harness + goldens + skip probes + ADR; `packages/` touched only in `vulkan_backend.cc`) and `f799e41` (docs: local log and freeze manifest).

The `ci-runs-14-02.txt` record and this SUMMARY are in the plan metadata commit.

## Verification

- RED (local, MSVC, never pushed alone): with harness, vk.txt and probes changed but PickDevice not yet, `golden_vk rc=1 GOLDEN mismatch scenario=vk-reasons line=10`. GREEN after PickDevice: `ALL rc=0` (8 binaries, /W4 /WX). Only one local Vulkan device (RTX 4060 Laptop), so the known limitation does not trigger here.
- Pushed `f799e41` to feat as a fast-forward (`8103beb..f799e41`, which also published the 6 docs/planning commits that were ahead). `ci_gate.sh` printed `CI-GATE ok sha=f799e41...`: native-verify and flutter-plugin success, jobs `linux (`, `macos (`, `windows (`, `sanitizers` success, golden_vk / api_test / affinity_test log lines present as specified.

## Deviations from Plan

None - plan executed exactly as written (option A).

Notes, not deviations: the local build used a new `build/phase14/goldens/` copy of `build/cr01-local` with the repo-relative paths adjusted by one directory level (not versioned, as planned). The product commit and the evidence commit were separate as the plan allows; the RED state existed only in the working tree.

## Known Limitations

- Accepted with option A: on a dev host with more than one Vulkan device, the `device-not-shareable` golden scenario gains an extra `<device> is not the compositor adapter` entry and mismatches. CI runners each expose one Vulkan device (lavapipe, llvmpipe, Apple Paravirtual), so CI is deterministic.
- The Windows `AcceptDevice` conflates LUID mismatch and KMT BGRA8 import failure under one wording, as the plan specified.

## Known Stubs

None.

## Threat Flags

None. T-14-04 (device name into reason) is covered by the existing `SanitizeReasonField`; T-14-05 (golden rewrite) is covered by the explicit user answer, the minimal hunk set, the retained Phase 12 manifest and the all-platform green run.

## Notes for later plans

- Todo `2026-10-27-gtx960-igpu-laptop-4k-falls-back-to-software`, item 2 (distinguish version vs adapter) is done by this plan; 14-10's laptop run will read the new text in the vulkan trail.
- Any later plan that edits one of the five frozen files must recompute `golden-freeze-14.sha256` and say so (13-01, 13-05, 15-04, 15-07 use the shared gate).

## Self-Check: PASSED

- Files present: golden-freeze-14.sha256, local-14-02-goldens.log, ci-runs-14-02.txt, vulkan_backend.cc split (`grep 'Vulkan < 1.3'` hit).
- Commits `92fcf1a` and `f799e41` are ancestors of HEAD and of origin/feat/mpv-master-upgrade.

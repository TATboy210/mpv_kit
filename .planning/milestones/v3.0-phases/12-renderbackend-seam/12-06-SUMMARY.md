---
phase: 12-renderbackend-seam
plan: 06
subsystem: video-output
tags: [cpp17, reason-grammar, adr-0004, video-renderer, golden-test, linux-gl, ci]

requires:
  - phase: 12-03
    provides: "docs/adr/0004-render-backend-reporting.md, Decision 3 reason grammar"
  - phase: 12-04
    provides: "pre-refactor RTX 4060 baseline (native path == 3a5f450), approved"
  - phase: 12-05
    provides: "fake-libmpv harness and golden_sw (12 scenarios), golden/sw.txt"
provides:
  - "Native reason in ADR 0004 grammar: head `<api> (<renderer>) on <device>` + `; <api>/<renderer> unavailable: <why>` trails"
  - "SanitizeReasonField (`;` -> `,`, U+0000-U+001F -> space) on every device, renderer and why field; JoinTrails"
  - "Private StartVulkan(RendererChoice, std::vector<std::string>*) / StartSoftware(std::vector<std::string>*)"
  - "GlInterop::interopReason(); the Linux plugin no longer appends `: <gl_reason>`"
  - "golden/sw.txt reason lines in the new grammar (only lines changed)"
affects: [12-07, 12-08, 12-09, 12-10, 12-11, 12-12, 13, 17]

actuals:
  tokens: 3600
  tasks: 2
  commits: 2
plan_head_before: d7f617b4ebb24bd5112039f4ec03301cd93d056c
plan_head_after: 52341e1dd7af0daae0b3af8aaff18b876c9b6355

tech-stack:
  added: []
  patterns:
    - "Reason is assembled from a local trail vector threaded through Start -> StartVulkan/StartSoftware; the head is written only by the winner"
    - "Every externally supplied string passes SanitizeReasonField before it enters the reason"

key-files:
  created: []
  modified:
    - packages/mpv_kit_video/src/video_renderer.cc
    - packages/mpv_kit_video/src/video_renderer.h
    - packages/mpv_kit_video/linux/gl_interop.h
    - packages/mpv_kit_video/linux/mpv_kit_video_plugin.cc
    - native/tests/golden/sw.txt
    - .planning/phases/12-renderbackend-seam/evidence/ci-runs.txt

key-decisions:
  - "A failed software create (sw-create-fails) reports `software/sw unavailable: mpv_render_context_create: <err>` with no head; golden expects `fake error -18` (MPV_ERROR_UNSUPPORTED from the fake)"
  - "The renderer name returned by get_info is also sanitized, not only device and why, so the head can never contain `;`"
  - "render_init `details` carrying the trails stays in 12-10 (its plan owns that plugin change); 12-06 only changes the reason string"
  - "Task 2's CI gate was not waited for at the user's request (\"能不能快点或者跳过\"); it is recorded as pending, not as passed"

patterns-established:
  - "Golden reason lines change only in the commit that changes the reason grammar (a9ea902); every other golden line is diff-proven unchanged"

requirements-completed: []

coverage:
  - id: D1
    description: "Software-path reason grammar (explicit software, no interop, interop reason, software create failure) pinned by golden_sw; only reason lines changed in sw.txt"
    requirement: RBE-07
    verification:
      - kind: integration
        ref: "ci_gate.sh --jobs-success '^build \\(' + golden_sw OK on linux/windows/macos + sanitizers 'GOLDEN ok scenarios=12' (native-verify 40315268784 attempt 2, flutter-plugin 40315269051 on a9ea902): CI-GATE ok"
        status: pass
      - kind: other
        ref: "Task 1 golden diff verify (non-reason changed lines = 0, old formats 0, gl_reason()[0] 0): VERIFY2_OK"
        status: pass
    human_judgment: false
  - id: D2
    description: "Vulkan-path reason on RTX 4060: `vulkan (gpu-next) on NVIDIA GeForce RTX 4060 Laptop GPU`, matches the grammar regex"
    requirement: RBE-07
    verification:
      - kind: e2e
        ref: "flutter test integration_test/real_plugin_test.dart -d windows (local, Task 2 code): All tests passed!, RP_VERIFY_OK"
        status: pass
    human_judgment: false
  - id: D3
    description: "Three-platform CI INTEGRATION reasons match the grammar regex on 52341e1"
    requirement: RBE-07
    verification:
      - kind: integration
        ref: "ci_gate.sh --jobs-success '^integration-test' --log <ubuntu|windows|macos> <grammar regex> (CI_GATE_SHA=52341e1)"
        status: unknown
    human_judgment: false
  - id: D4
    description: "No constant or ring-size change: diff vs 3a5f450 in packages/mpv_kit_video/src touches none of kPresentTimeout, kIdleTimeout, kMinBackoff, kMaxBackoff, kMaxQuarantine, `quarantine_count_ + 3`"
    requirement: RBE-07
    verification:
      - kind: other
        ref: "git diff 3a5f450 -- packages/mpv_kit_video/src | grep changed lines for the constants: 0"
        status: pass
    human_judgment: false

duration: 2h 10m
completed: 2026-10-26
status: complete
---

# Phase 12 Plan 06: Native Reason Grammar Summary

**The native `reason` now follows ADR 0004 exactly. It is `vulkan (gpu-next) on <device>` or `software (sw) on cpu`, followed by one `; vulkan/<renderer> unavailable: <why>` trail per candidate ranked before the winner, with `;` and control characters sanitized out of every field. The Linux GL probe failure becomes a trail instead of a free-text suffix, and golden_sw pins the software side on all six native-verify jobs.**

## Performance

- **Duration:** about 2 h 10 min. Most of it was hosted CI: the linux (ubuntu-24.04) apt step stalled twice.
- **Started:** 2026-10-26T11:22Z
- **Completed:** 2026-10-26T13:33Z
- **Tasks:** 2 (2 commits)
- **Files modified:** 5 product/test files plus the evidence ledger

## Accomplishments

- **Grammar in `video_renderer.cc`.**
  - The anonymous namespace has four helpers: `SanitizeReasonField`, `JoinTrails`, `VulkanRenderers(choice)` (auto: gpu-next, gpu; kGpuNext; kGpu; kSoftware: none) and `AddVulkanTrails`.
  - `Start` keeps a local trail vector:
    - An explicit software request leaves no trail.
    - If the platform has no Vulkan interop, each renderer of the choice gets `platform interop unavailable: <why>` or `platform has no Vulkan interop`.
    - If the Vulkan device fails to initialise, each renderer gets the init error verbatim.
    - A failed `mpv_render_context_create` adds `vulkan/<r> unavailable: mpv_render_context_create: <err>`.
  - Software winning gives `software (sw) on cpu` followed by the trails.
  - Software failing appends `software/sw unavailable: …` and the reason is the trails only, with no head.
  - Log lines keep their format. The Vulkan fallback log now shows the trails inside its parentheses.
- **Linux.** `GlInterop::interopReason()` returns `gl_reason_` (or nullptr). The plugin returns `backend_reason()` as it is, and the `gl_reason()` accessor is kept.
- **Golden.** Only the 12 `reason=` lines in `sw.txt` changed. For example, `sw-fallback-interop-reason` now expects `software (sw) on cpu; vulkan/gpu-next unavailable: platform interop unavailable: probe failed (0x887A0004); vulkan/gpu unavailable: platform interop unavailable: probe failed (0x887A0004)`.
- **Real hardware.** The RTX 4060 INTEGRATION line on the Task 2 code reads `{"backend":"vulkan","reason":"vulkan (gpu-next) on NVIDIA GeForce RTX 4060 Laptop GPU",...}`. That string is unchanged from before, as expected: with no failed candidate there is no trail.

## Task Commits

1. **Task 1 (tracer): software-side grammar, Linux interopReason, golden reason lines.** `a9ea902` (feat).
   - Local checks passed: MSVC `/W4 /WX` golden_sw `GOLDEN ok scenarios=12`, the clang front end (clang-tidy, `-Wall -Wextra -Wpedantic -Werror`) clean on `video_renderer.cc` and the golden test, and `flutter build windows --debug` with 0 `error C`/`warning C`.
   - The CI gate passed on a9ea902 (native-verify 40315268784 attempt 2, flutter-plugin 40315269051).
   - The tracer feedback gate re-ran and passed before Task 2.
2. **Task 2: Vulkan-side grammar.** `52341e1` (feat).
   - Local checks: golden still OK, clang front end clean, and the RTX 4060 real-plugin test passed (RP_VERIFY_OK).
   - Pushed. The CI gate is **pending** (see Deferred Issues).

## Windows CI reason: before and after

- 12-01 baseline (ci-runs.txt, windows-2025 with WARP and no Vulkan ICD): `software (vkCreateInstance failed)`.
- Expected on 52341e1, derived from the code and **not yet observed**: `software (sw) on cpu; vulkan/gpu-next unavailable: vkCreateInstance failed; vulkan/gpu unavailable: vkCreateInstance failed`. This plan does not claim it until the gate below has run.

## Decisions Made

See `key-decisions` in the frontmatter.

## Deviations from Plan

### Auto-fixed / handled

**1. [Rule 3 - Blocking] Hosted CI linux (ubuntu-24.04) apt step stalled**
- **Found during:** Task 1 CI gate.
- **Issue:** `Install dependencies` crawled on azure.archive.ubuntu.com for 38 min; the same step took 36 s on the previous run. The other 7 native-verify jobs were green.
- **Fix:** cancelled run 40315268784 and reran the failed job once through `CI_GATE_RERUN_INFRA=1`. The rerun was slow again but finished green, and a fresh gate invocation then passed. The `note`/`rerun` lines are in `evidence/ci-runs.txt` (committed in 52341e1).
- **Commit:** 52341e1 (ledger only).

**2. [Rule 2 - Correctness] The renderer name in the head is also sanitized**
- The plan names device and why. The name mpv returns from `get_info` is also an external string, so it goes through `SanitizeReasonField` too. Without that, the grammar's "`; ` always splits trails" guarantee would not hold for the head.

**Total deviations:** 2 (1 infra, 1 correctness). **Impact:** none on behaviour beyond the planned reason change.

## Deferred Issues

- **Task 2 CI gate not awaited.** The user asked mid-run to speed up or skip ("还没好？能不能快点或者跳过"). On 52341e1, flutter-plugin 40327854823 is `success`. native-verify 40327855409 was still running when this summary was written: 7 of 8 build jobs were green, linux (ubuntu-24.04) was again stuck in `Install dependencies` (25 min and counting), and the three `integration-test` jobs wait on it. Re-run the gate to close this out:
  ```
  R='"reason":"(vulkan|software) \((gpu-next|gpu|sw|unknown renderer)\) on [^;"]+(; (vulkan|software)/(gpu-next|gpu|sw) unavailable: [^;"]+)*"'
  CI_GATE_SHA=52341e1 bash .planning/phases/12-renderbackend-seam/tools/ci_gate.sh --jobs-success '^integration-test' --log '^integration-test \(ubuntu' "$R" --log '^integration-test \(windows' "$R" --log '^integration-test \(macos' "$R"
  ```
  The first gate invocation on 52341e1 exited 1 on a GitHub API EOF while the run was still in progress; that was not a CI failure. Coverage D3 stays `unknown` until the gate passes.

## Next Phase Readiness

- 12-07 writes the Vulkan golden scenarios in this grammar. A Vulkan win with earlier failures and a device-init failure are the cases to pin.
- 12-10 adds the trails as `render_init` `details` in the three plugins.

## Self-Check: PASSED

- FOUND: packages/mpv_kit_video/src/video_renderer.cc (contains `software (sw) on cpu`), packages/mpv_kit_video/linux/gl_interop.h (contains `interopReason`), native/tests/golden/sw.txt (contains `software (sw) on cpu`)
- FOUND commits on HEAD: a9ea902, 52341e1
- `grep -c 'mpv_render_context_create: ' video_renderer.cc` = 2 (>= 1); `grep -c '+ tried'` = 0; constants grep vs 3a5f450 = 0
- Task 2 CI gate: pending (not claimed as passed)

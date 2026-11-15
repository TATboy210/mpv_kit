---
phase: 12-renderbackend-seam
plan: 01
subsystem: infra
tags: [github-actions, ci, gh-cli, native-assets, flutter-3.47.8, integration-test]

requires: []
provides:
  - "Hosted CI fully green on feat/mpv-master-upgrade for the first time (native-verify 40276446631, flutter-plugin 40276446702 on bbb071e)"
  - "Reusable CI gate .planning/phases/12-renderbackend-seam/tools/ci_gate.sh (--jobs-success, --log, CI_GATE_SHA; exit 0/1/2/3/4)"
  - "Phase 12 push authorization record evidence/push-authorization.txt (scope=push-green-only, red_commits=none)"
  - "Baseline three-platform INTEGRATION backend/reason lines in evidence/ci-runs.txt"
affects: [12-03, 12-05, 12-06, 12-07, 12-09, 12-10, 12-11, 12-12]

actuals:
  tokens: 3460
  tasks: 3
  commits: 3
plan_head_before: 2ed9c803f4774d56b98d8ae58f674d73377488d8
plan_head_after: dcdc782b9f2351e89c7376c406cdf94361c2c3eb

tech-stack:
  added: []
  patterns:
    - "CI gate: pick runs by headSha, gh run watch, then assert job conclusions and log lines (job field split on the first tab)"
    - "Evidence ledger: every gate invocation appends sha/workflow/run/conclusion lines, including failures"

key-files:
  created:
    - .planning/phases/12-renderbackend-seam/tools/ci_gate.sh
    - .planning/phases/12-renderbackend-seam/evidence/ci-runs.txt
    - .planning/phases/12-renderbackend-seam/evidence/push-authorization.txt
  modified:
    - .github/workflows/native-verify.yml
    - .github/workflows/flutter-plugin.yml

key-decisions:
  - "Push authorization is push-green-only (user reply, 2026-10-26): 12-07 Task 2 and 12-11 Task 1 RED commits are NOT authorized to be pushed and must stop before their RED push"
  - "Build-log success is asserted with 'tests passed\\.[[:space:]]*$' instead of the plan's 'All tests passed!', because Flutter 3.47.8 prints '🎉 N tests passed.'; the regex still rejects 'N tests passed, M skipped.'"
  - "ci_gate.sh infra reruns are opt-in (CI_GATE_RERUN_INFRA=1, at most once per invocation) because the script cannot tell an infra flake from a test failure"

patterns-established:
  - "Later Phase 12 plans express 'pushed and CI green plus log line X' as one ci_gate.sh call"

requirements-completed: [RBE-02, RBE-04]

coverage:
  - id: D1
    description: "native-verify linux jobs green: pin_bundles.dart --check runs from the repo root"
    requirement: RBE-04
    verification:
      - kind: other
        ref: "bash .planning/phases/12-renderbackend-seam/tools/ci_gate.sh --jobs-success '^linux \\(' (run 40276446631)"
        status: pass
    human_judgment: false
  - id: D2
    description: "flutter-plugin build jobs green on linux/windows/macos, with the hook-bundle libmpv located and 21 channel tests passing with none skipped"
    requirement: RBE-04
    verification:
      - kind: other
        ref: "ci_gate.sh --jobs-success '^build \\(' --log '^build \\(<os>' 'tests passed\\.[[:space:]]*$' (run 40276446702)"
        status: pass
    human_judgment: false
  - id: D3
    description: "integration-test (3 OS) and flutter-video-coverage ran for the first time and passed; INTEGRATION lines recorded"
    requirement: RBE-02
    verification:
      - kind: integration
        ref: "ci_gate.sh --jobs-success '^integration-test' --jobs-success '^flutter-video-coverage' --log ... 'INTEGRATION \\{' (run 40276446631)"
        status: pass
    human_judgment: false
  - id: D4
    description: "Push authorization recorded and committed before the first gated push"
    verification:
      - kind: other
        ref: "git merge-base --is-ancestor <commit adding push-authorization.txt> <first ci-runs.txt sha>"
        status: pass
    human_judgment: false
  - id: D5
    description: "No new continue-on-error; six-target matrix unchanged"
    requirement: RBE-04
    verification:
      - kind: other
        ref: "python tools/check_matrix.py"
        status: pass
    human_judgment: false

duration: 42min
completed: 2026-10-26
status: complete
---

# Phase 12 Plan 01: Hosted CI Restore Summary

**Hosted CI is green on `feat/mpv-master-upgrade` for the first time. Three workflow-only fixes did it: the pin check now runs from the repo root, the example is built before the hook-bundle locate step, and the Linux runners get the runtime libraries libmpv needs. A reusable `ci_gate.sh` now checks job results and log lines for a given pushed SHA. The real-plugin integration test has run on all three platforms for the first time.**

## Performance

- **Duration:** 42 min
- **Started:** 2026-10-26T05:30:06Z
- **Completed:** 2026-10-26T06:12:02Z
- **Tasks:** 3 (Task 1 resolved by the orchestrator checkpoint)
- **Files modified:** 5

## Accomplishments
- On bbb071e every native-verify job passed (patch-drift, sanitizers, linux x2, macos x2, windows x2, integration-test x3, flutter-video-coverage), and so did all three flutter-plugin build jobs.
- The `Locate the hook-bundle libmpv` step finds the hook output on all three build runners, and each runner reports `🎉 21 tests passed.` (earlier green runs had 16 skipped).
- First real-plugin INTEGRATION baseline:
  - linux: `vulkan (gpu-next) on llvmpipe`
  - macos: `vulkan (gpu-next) on Apple Paravirtual device`
  - windows: `software (vkCreateInstance failed)`
- mpv_kit_video line coverage is 91.4%.
- `ci_gate.sh` is ready for reuse in later plans. Locally checked: unpushed SHA exits 2, unmet expectations exit 3, and the check against the old green run 8774764 behaves as expected.

## Task Commits

1. **Task 1: push authorization checkpoint.** The user answered `push-green-only`. The record went into `evidence/push-authorization.txt` as part of `b9779d6`, which is the first pushed commit.
2. **Task 2: pin path, hook-bundle order and ci_gate.sh.** `b9779d6` (fix). Follow-up fix for the Linux runtime libraries: `bbb071e` (fix).
3. **Task 3: first integration-test and coverage run, INTEGRATION lines recorded.** `dcdc782` (docs).

Pushed to `origin/feat/mpv-master-upgrade` (no force): b9779d6, bbb071e. dcdc782 and the SUMMARY commit are local only (docs). They go out with the next authorized push.

## Files Created/Modified
- `.github/workflows/native-verify.yml`:
  - The linux job runs the pin check from `$GITHUB_WORKSPACE`.
  - integration-test on linux uses `lib/libmpv.so.2`, adds `stage/deps` to `LD_LIBRARY_PATH`, and installs the same distro runtime packages as flutter-video-coverage.
- `.github/workflows/flutter-plugin.yml`:
  - `Build example` now runs before `Locate the hook-bundle libmpv`.
  - Linux installs the bundle's host runtime libraries: libpulse0, libasound2t64, libva2, libva-drm2, libvulkan1.
- `.planning/phases/12-renderbackend-seam/tools/ci_gate.sh`: the hosted CI gate.
- `.planning/phases/12-renderbackend-seam/evidence/push-authorization.txt`: the Phase 12 push authorization.
- `.planning/phases/12-renderbackend-seam/evidence/ci-runs.txt`: run records, INTEGRATION lines and coverage.

## Decisions Made
- **Push scope is `push-green-only`.** 12-07 Task 2 and 12-11 Task 1 must stop before their RED pushes and ask the user how to get the pre-fix red evidence.
- **Success regex adjusted.** Flutter 3.47.8 does not print `All tests passed!`, so the gate uses `tests passed\.[[:space:]]*$`. This still requires zero skipped tests, which is what the plan intended.
- **Infra reruns are opt-in.** `CI_GATE_RERUN_INFRA=1` allows one rerun per invocation, and the rerun is recorded in ci-runs.txt. Test failures are never rerun automatically.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] The Linux hook bundle could not load on the flutter-plugin runner**
- **Found during:** Task 2, first gated run 40275120977 on b9779d6
- **Issue:** After the reorder, the hook bundle was found at `.../v0.1.0-dev.3/linux-x64/lib/libmpv.so.2`, but `controller_channel_test.dart` failed with "libmpv is required by CI ... could not be loaded". I parsed the bundle's DT_NEEDED entries with an isolated Python ELF reader. The bundle needs host libraries (libpulse.so.0, libasound.so.2, libva*.so.2, libvulkan.so.1) that the minimal ubuntu-24.04 install does not have. The integration-test log names `libpulse.so.0` directly.
- **Fix:** Added `libpulse0 libasound2t64 libva2 libva-drm2 libvulkan1` to the flutter-plugin Linux dependency step. This is the host allowlist in package.sh.
- **Verification:** Run 40276446702: build (ubuntu-24.04, linux) passed with `🎉 21 tests passed.`
- **Committed in:** bbb071e

**2. [Rule 3 - Blocking, Task 3 step 3 "CI config missing"] integration-test on Linux failed on its first run**
- **Found during:** Task 2's push (integration-test runs as soon as linux goes green), run 40275120925
- **Issue:** `stage/libmpv.so.2: cannot open shared object file`. The linux job stages libmpv under `stage/lib/` and its deps under `stage/deps/`. The integration-test runner also lacked the distro FFmpeg/libass runtime that the verify-tier build links against.
- **Fix:** Set `libname: lib/libmpv.so.2`, added `stage/deps` to `LD_LIBRARY_PATH`, and installed the same runtime packages that flutter-video-coverage already installs. No test expectation changed and no skip was added.
- **Verification:** Run 40276446631: integration-test (ubuntu-24.04) passed with an INTEGRATION line.
- **Committed in:** bbb071e

**3. [Rule 1 - Bug in plan verify] The literal `All tests passed!` cannot match**
- **Found during:** Task 2, local dry run of the gate against the old green run 40059341156
- **Issue:** On CI, Flutter 3.47.8 prints `🎉 21 tests passed.` or `🎉 5 tests passed, 16 skipped.`. The string `All tests passed!` never appears, so the plan's verify command would always exit 3.
- **Fix:** The gate runs with `--log '^build \(<os>' 'tests passed\.[[:space:]]*$'`. This matches a full pass and does not match a run with skipped tests.
- **Verification:** All three build logs on 40276446702 contain `🎉 21 tests passed.`

---

**Total deviations:** 3 auto-fixed (2 blocking CI config, 1 plan verify string)
**Impact on plan:** Only workflow configuration changed, and only for the never-run or broken Linux paths. There are no product code changes (`git diff --stat 3a5f450 HEAD -- packages/ native/ example/` is empty), no continue-on-error, and no skips. The first failed run is kept in ci-runs.txt with its run ids.

## Issues Encountered
- Both workflows failed on their first gated run (b9779d6, runs 40275120925 / 40275120977). Deviations 1–2 above fixed this, and the runs are kept as `conclusion=failure` lines in ci-runs.txt.
- ci-runs.txt has two record pairs for bbb071e, because the Task 2 and Task 3 gates both ran on the same SHA. This is expected: every gate run appends.

## User Setup Required
None. No external service configuration required.

## Next Phase Readiness
- Hosted CI is a usable verification layer. Later plans run `bash .planning/phases/12-renderbackend-seam/tools/ci_gate.sh <expectations>` after an authorized push.
- **Blocker for later plans:** under `push-green-only`, 12-07 Task 2 and 12-11 Task 1 must stop before their RED pushes and ask the user for a separate decision.

## Self-Check: PASSED
- FOUND: ci_gate.sh, ci-runs.txt, push-authorization.txt, both workflows
- FOUND commits: b9779d6, bbb071e, dcdc782
- Task 2 verify:
  - `bash -n`: pass
  - check_matrix: pass
  - gate `CI-GATE ok sha=bbb071e…`: pass
  - authorization ancestry (b9779d6 is an ancestor of b9779d6): pass
- Task 3 verify:
  - gate `CI-GATE ok`: pass
  - three `integration platform=` lines plus the coverage line: pass

---
*Phase: 12-renderbackend-seam*
*Completed: 2026-10-26*

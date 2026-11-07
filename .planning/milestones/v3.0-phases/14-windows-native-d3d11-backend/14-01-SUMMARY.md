---
phase: 14-windows-native-d3d11-backend
plan: 01
subsystem: infra
tags: [d3d11, dxgi, ci-gate, probe, windows, warp, push-authorization]

requires:
  - phase: 12-renderbackend-seam
    provides: ci_gate.sh (Phase 12 version) and the push-authorization.txt format
provides:
  - Phase 14 push authorization (green-plus-scratch, scratch prefix ci/14-)
  - Parameterised ci_gate.sh (CI_GATE_BRANCH, repeatable --workflow, CI_GATE_EVIDENCE, branch= in records)
  - tools/d3d11_probe/d3d11_caps_probe.cpp, a read-only D3D11 capability probe (MSVC and MSYS2 clang++)
  - Measured gate lines for 14-07 (fence, video_support, typed_uav, max_texture2d, open_shared)
affects: [14-02, 14-03, 14-04, 14-05, 14-06, 14-07, 14-08, 14-09, 14-10, 14-11]

actuals:
  tokens: 9800
  tasks: 3
  commits: 3
plan_head_before: 182a09700cb311b14383979875533f26fbbe3b7a
plan_head_after: d903da84ac3dc667589d59fc31ae3adf0fa73bee

tech-stack:
  added: []
  patterns:
    - "scratch-first CI: ci/14-* branches carry CI-only experiments, feat only gets green results"
    - "evidence gate lines: `gate <key>=<value> source=<host/run>`"

key-files:
  created:
    - .planning/phases/14-windows-native-d3d11-backend/evidence/push-authorization.txt
    - .planning/phases/14-windows-native-d3d11-backend/evidence/ci-runs.txt
    - .planning/phases/14-windows-native-d3d11-backend/evidence/spikes.txt
    - .planning/phases/14-windows-native-d3d11-backend/tools/ci_gate.sh
    - tools/d3d11_probe/d3d11_caps_probe.cpp
  modified: []

key-decisions:
  - "Task 1 answered green-plus-scratch: feat pushes green only, ci/14-* scratch branches may go red, no force-push, scratch branches deleted in 14-11"
  - "Fence path is available on every measured host (RTX 4060, WARP, hosted Basic Render Driver); 14-07 still needs a debug switch forcing the D3D11_QUERY_EVENT path so both code paths are covered"
  - "VIDEO_SUPPORT device creation fails with 0x887A0004 on Basic Render Driver / WARP while BGRA-only succeeds: 14-07 must retry without VIDEO_SUPPORT and log it"
  - "decision=no-uav: shared textures carry no UNORDERED_ACCESS bind flag (typed UAV store is supported everywhere, kept as data only)"
  - "Texture dimension cap stays at the documented 16384 (hardware rejects 16385 with 0x80070057; WARP accepting it is not a license)"

patterns-established:
  - "ci_gate.sh on a scratch branch: CI_GATE_BRANCH=ci/14-x CI_GATE_SHA=<sha> ... --workflow <file>"

requirements-completed: [D3D-06]

coverage:
  - id: D1
    description: "Push authorization for Phase 14 recorded from the user's blocking-human answer"
    requirement: "D3D-06"
    verification:
      - kind: other
        ref: "grep -Eq format check on evidence/push-authorization.txt (authorization regex from the plan) + user_reply line"
        status: pass
    human_judgment: false
  - id: D2
    description: "Parameterised Phase 14 ci_gate.sh reproduces CI-GATE ok on the Phase 12 green SHA 025bdad and judged the scratch probe run"
    requirement: "D3D-06"
    verification:
      - kind: other
        ref: "CI_GATE_SHA=025bdad bash tools/ci_gate.sh --jobs-success '^patch-drift' -> CI-GATE ok; CI_GATE_BRANCH=ci/14-probe ... --workflow spike-14-probe.yml -> CI-GATE ok (run 40464431371)"
        status: pass
    human_judgment: false
  - id: D3
    description: "D3D11 capability probe compiles with MSVC /W4 /WX and clang++ and emits CAPS lines on RTX 4060, local WARP, windows-2025 and windows-11-arm"
    requirement: "D3D-06"
    verification:
      - kind: other
        ref: "spikes.txt CAPS rows for rtx4060-local, windows-2025, windows-11-arm; hosted run 40464431371"
        status: pass
    human_judgment: false
  - id: D4
    description: "Five gate lines (fence, video_support, typed_uav, max_texture2d, open_shared) with probe-run sources plus the Microsoft resource-limits doc values"
    requirement: "D3D-06"
    verification:
      - kind: other
        ref: "spikes.txt grep for ^gate (fence|video_support|typed_uav|max_texture2d|open_shared)= and the doc d3d11_texture2d_max line"
        status: pass
    human_judgment: false

duration: 15min
completed: 2026-10-27
status: complete
---

# Phase 14 Plan 01: Push authorization, CI gate and D3D11 capability spikes Summary

**Phase 14 can now push and dispatch under a recorded green-plus-scratch authorization, judge any branch's CI with one parameterised gate command, and 14-07 has measured (not assumed) answers: fences work on every host, VIDEO_SUPPORT needs a retry-without path on the Basic Render Driver, 8K shared textures open cross-device everywhere.**

## Performance

- **Duration:** about 15 min
- **Started:** 2026-10-27T06:51:28Z (user answer time)
- **Completed:** 2026-10-27T07:06Z
- **Tasks:** 3 (Task 1 recorded from the orchestrator's checkpoint answer)
- **Files modified:** 5 created in the repo on feat, plus 1 scratch-only workflow on ci/14-probe

## Accomplishments

- Recorded the user's reply `green-plus-scratch` verbatim in `evidence/push-authorization.txt` (committed before any push; ancestor of every later record).
- `tools/ci_gate.sh` (Phase 14): `CI_GATE_BRANCH`, repeatable `--workflow`, `CI_GATE_EVIDENCE`, `branch=` on every record; selftest on 025bdad printed `CI-GATE ok`, the scratch probe run was judged by the same script.
- `tools/d3d11_probe/d3d11_caps_probe.cpp`: read-only probe, builds clean with MSVC `/W4 /WX` and with MSYS2 clang++ (CLANG64 and CLANGARM64 on the runners).
- Measured data on RTX 4060 (local), local WARP/Basic Render Driver, windows-2025 and windows-11-arm (run 40464431371), plus the Microsoft limits page (`D3D11_REQ_TEXTURE2D_U_OR_V_DIMENSION` = 16384; resource size `min(max(128,0.25*VRAM),2048)` MB; 8K BGRA8 is 126.6 MiB).

### Findings for 14-07

| Gate | Value | Evidence |
|------|-------|----------|
| fence | `fence` on runner and RTX 4060 (query_event also ok everywhere) | device5/create_fence/context4/fence_wait ok on all rows |
| video_support | `retry-without` | `create_bgra_video=0x887A0004` on Basic Render Driver / WARP, `create_bgra` ok; RTX 4060 ok with VIDEO_SUPPORT |
| typed_uav | `yes`, `decision=no-uav` | typed UAV store yes everywhere, shared UAV 4K create ok, not used |
| max_texture2d | 16384 (doc) | hardware rejects 16385 with `0x80070057`; Basic Render Driver / WARP accept it (not a license) |
| open_shared | `ok` | OpenSharedResource of 4K and 8K KMT handles on a second same-adapter device succeeds everywhere |

Hosted runners list two Basic Render Driver adapters: a first one without `DXGI_ADAPTER_FLAG_SOFTWARE` (`driver=hardware` row) and a software one (`driver=basic`), plus the WARP row. The first one is the likely Flutter adapter; every row gave the same results.

## Task Commits

1. **Task 1: Push authorization (checkpoint:decision, answered `green-plus-scratch`)** - `1d569bf` (docs)
2. **Task 2: Authorization on disk, parameterised ci_gate.sh, probe, local RTX 4060 / WARP data** - `900ce37` (feat)
3. **Task 3: Hosted runner probe results and gate lines** - `d903da8` (docs)

Scratch-only commit on `origin/ci/14-probe` (not on feat): `082162a` `.github/workflows/spike-14-probe.yml`.

**Plan metadata:** the commit that adds this SUMMARY.

## Files Created/Modified

- `.planning/phases/14-windows-native-d3d11-backend/evidence/push-authorization.txt` - authorization lines and user_reply
- `.planning/phases/14-windows-native-d3d11-backend/tools/ci_gate.sh` - parameterised CI gate
- `.planning/phases/14-windows-native-d3d11-backend/evidence/ci-runs.txt` - selftest and scratch run records
- `.planning/phases/14-windows-native-d3d11-backend/evidence/spikes.txt` - CAPS rows, doc lines, gate lines
- `tools/d3d11_probe/d3d11_caps_probe.cpp` - capability probe (518 lines)

## Decisions Made

See `key-decisions` in the frontmatter. `decision=no-uav` and the 16384 cap follow the plan's own wording; the fence and VIDEO_SUPPORT results are data, not choices.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `d3d10.h` include order broke the MSVC build**
- **Found during:** Task 2 (local compile)
- **Issue:** `fatal error C1189: d3d10.h is included before d3d10_1.h` under `/W4 /WX` with the Windows 10.0.26100 SDK.
- **Fix:** include `<d3d10_1.h>` (which pulls in `d3d10.h` and `ID3D10Multithread`).
- **Files modified:** `tools/d3d11_probe/d3d11_caps_probe.cpp`
- **Verification:** MSVC `/W4 /WX` clean; clang++ builds on both hosted runners.
- **Committed in:** `900ce37`

**2. [Rule 3 - Blocking] WebFetch is not available to this executor**
- **Found during:** Task 2 step 5
- **Issue:** the plan says to fetch the Microsoft limits page with WebFetch.
- **Fix:** fetched the page with `curl` and read the values from the page text (16384, `min(max(128,0.25f*VRAM),2048)` MB); same URL recorded in the doc lines. Values match the plan's expectation, so nothing differs from planning time.
- **Files modified:** `evidence/spikes.txt`
- **Committed in:** `900ce37`

### Additions within the plan's intent

- `ci_gate.sh` `find_run` falls back to the Actions REST API (branch + head_sha, matching the run `path`) when `gh run list --workflow` cannot resolve a workflow that exists only on a non-default branch. It was not needed: `gh run list --workflow` resolved `spike-14-probe.yml` on `ci/14-probe` directly.
- Probe extras beyond the plan's key list: `driver=basic` (enumerated software adapter), `create_fence_shared`, `open_shared_8k`, `test_device`, `factory=` on factory failure. They add data only.
- Task 1 was committed separately (`1d569bf`) so the authorization commit is an ancestor of everything else, instead of riding inside Task 2's commit.

---

**Total deviations:** 2 auto-fixed (2 Rule 3). **Impact:** none on scope; no product code, `native/`, `packages/` or feat `.github/` touched.

## Issues Encountered

None. Scratch run 40464431371 passed first time. The probe's `dim_16385` result differs between hardware (`0x80070057`) and software drivers (`0x00000000`); the documented 16384 remains the cap.

## Push state

- `origin/ci/14-probe` created (scratch, authorized). It also publishes the local docs/planning commits that were ahead of origin, on that scratch branch only.
- `feat/mpv-master-upgrade` was NOT pushed by this plan: nothing here needed it, and the authorization says feat only pushes green. Local feat is 12 commits ahead of origin (9 docs/planning before this plan plus 3 from it). PR #1 is untouched.
- `ci/14-probe` is deleted by 14-11.

## Known Stubs

None.

## Threat Flags

None. The scratch workflow is push-triggered only on `ci/14-**`, uses only `actions/checkout@v5` and `msys2/setup-msys2@v2` (both already used in the repo), and is absent from feat (`git ls-tree` check passed).

## Next Phase Readiness

Ready for 14-02. Later plans push scratch work under `ci/14-` and judge it with `CI_GATE_BRANCH=ci/14-<topic> ci_gate.sh --workflow <file> ...`; 14-07 reads the five gate lines in `evidence/spikes.txt`.

## Self-Check: PASSED

- Files present: push-authorization.txt, ci_gate.sh, ci-runs.txt, spikes.txt, d3d11_caps_probe.cpp.
- Commits `1d569bf`, `900ce37`, `d903da8` are ancestors of HEAD; `082162a` is on `origin/ci/14-probe`.
- Acceptance: authorization regex and `user_reply` pass; selftest `CI-GATE ok`; both hosted CAPS rows and all five gate keys present; `git show --stat` of the three commits over `packages/ native/ .github/` is empty; `spike-14` workflow absent from feat HEAD.

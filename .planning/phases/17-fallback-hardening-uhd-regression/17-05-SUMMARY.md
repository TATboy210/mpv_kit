---
phase: 17-fallback-hardening-uhd-regression
plan: 05
subsystem: testing
tags: [docs, final-audit, ci-gate, verification-tiers, wording-approval, ver-01, ver-02, ver-03, ver-04]

requires:
  - phase: 17-fallback-hardening-uhd-regression
    provides: 17-01 fault golden, 17-02 matrix and guard, 17-03 soak rule, 17-04 RTX 4060 evidence
provides:
  - "docs/perf/fallback-uhd-regression.md: VER-01..04 by tier, reproduce commands, all four d3d11 4K attempts shown, malloc-arena choice with evidence"
  - "evidence/unverified.txt (17 unverified, 2 deferred) and evidence/final-audit.txt (9 audit keys ok, VER-01..04 and SC1..SC4 mapped to run ids)"
  - "Full CI gate on c4a7158: native-verify 41056455257, flutter-plugin 41056455255, macos-route 41056455344, all success, 17-01..17-03 key lines reproduced"
  - "User-approved SC1, VER-01, VER-04 and SC4 wording applied; VER-01 and VER-04 ticked; vk-gpu-timeout todo closed"
affects: [phase-17-verification, milestone-v3.0]

requirements-completed: [VER-01, VER-02, VER-03, VER-04]

actuals:
  tokens: 21000
  tasks: 2
  commits: 3
plan_head_before: f8e3757108c3822181efb885cb4f31c9a4c7b6d1
plan_head_after: 1084a7b88669eebfe8dd6fb3fafb80c7d44eef9e

tech-stack:
  added: []
  patterns:
    - "Status words follow the tier that ran the check; 证明 only where every clause of the (approved) wording holds"

key-files:
  created:
    - docs/perf/fallback-uhd-regression.md
    - .planning/phases/17-fallback-hardening-uhd-regression/evidence/unverified.txt
    - .planning/phases/17-fallback-hardening-uhd-regression/evidence/final-audit.txt
  modified:
    - README.md
    - .planning/ROADMAP.md
    - .planning/REQUIREMENTS.md
    - .planning/phases/17-fallback-hardening-uhd-regression/evidence/decisions.txt
    - .planning/phases/17-fallback-hardening-uhd-regression/evidence/ci-runs.txt
    - .planning/phases/17-fallback-hardening-uhd-regression/evidence/flake-timing.txt
    - .planning/phases/17-fallback-hardening-uhd-regression/deferred-items.md
    - .planning/todos/completed/2026-10-27-vk-gpu-timeout-golden-flake-macos.md

key-decisions:
  - "User approved proposals SC1, VER-01, VER-04 and SC4 verbatim; VER-01/VER-04/SC1/SC4 became 证明 only under that wording."
  - "ubuntu opengl soak keeps MALLOC_ARENA_MAX=1 (b34a402) as a documented measurement-environment choice; rule and thresholds unchanged."
  - "vk-gpu-timeout todo closed by the user; the note that no mismatch is not elimination is kept in its resolution."

patterns-established: []

coverage:
  - id: D1
    description: "Performance doc, README test variables, unverified list with hosted and real-hardware tiers kept apart"
    requirement: "VER-04"
    verification:
      - kind: other
        ref: "plan Task 1 automated check (doc sections, 17 unverified lines) passed"
        status: pass
    human_judgment: true
    rationale: "Tiering and the unverified list were accepted by the user at the phase-close check."
  - id: D2
    description: "Final full CI gate on the docs-over-product SHA"
    requirement: "VER-01"
    verification:
      - kind: integration
        ref: "ci_gate (120 s polling) CI-GATE ok sha=c4a7158, native-verify 41056455257, flutter-plugin 41056455255, macos-route 41056455344"
        status: pass
    human_judgment: false
  - id: D3
    description: "Closing audit and requirement/criterion mapping with wording proposals"
    requirement: "VER-04"
    verification:
      - kind: other
        ref: "plan Task 2 automated checks (nine audit keys ok, eight id lines, flake summary, proposals) passed"
        status: pass
    human_judgment: true
    rationale: "Wording and worse compare items needed the user's decision; approved."

duration: about 3 h (including two CI gates of about 20 min each)
completed: 2026-10-30
status: complete
---

# Phase 17 Plan 05: close-out documentation, final gate and audit Summary

**Phase 17 is documented and audited against its evidence: one full CI gate on the final docs-over-product SHA reproduced every key line of 17-01..17-03, the audit maps VER-01..04 and SC1..SC4 to run ids with 17 unverified items listed, and the user approved the SC1, VER-01, VER-04 and SC4 wording.**

## Accomplishments

- **Performance doc** `docs/perf/fallback-uhd-regression.md` (English): reproduce commands (hosted and RTX session), VER-01 scenario table, VER-02 platform-by-backend table with run ids, VER-03 guard legs, VER-04 4K table with all three d3d11 attempts (3 and 5 drops with the example covered, 0 with it in front; one pass against two fails, attributed not proven), the 100-round soaks with 11-point RSS and VRAM curves, the pre-registered rule, the ubuntu opengl soak and the `MALLOC_ARENA_MAX=1` choice with its evidence, flake distribution, open findings (including the stale `$target.ok` hook stamp, not fixed) and `## Verification tiers`.
- **README:** three test-only environment variables and one CI paragraph; nothing else touched.
- **unverified.txt:** 17 items 未验证 and 2 延后 (UHD-02, COMP-03).
- **Final gate** (c4a7158): native-verify, flutter-plugin and macos-route all success; PATCH-DRIFT OK, matrix 3/3, 3/3, 2/2, guard negative, create-fail softwareFallback message, fault test on six jobs, macOS timing-info, ANGLE-FREE and the opengl soak flat (late +4.4 MiB) all present.
- **final-audit.txt:** nine audit keys ok; the eight id lines; four proposals (approved); `flake summary choice=measure-split runs=10 macos_wait_ms=1000..1113 macos_backoff_ms=103..169 mismatches=0`.
- **Human check (phase17-close, approve):** proposals approved verbatim, unverified list, tiering and the microsecond avsync worse items accepted, vk-gpu-timeout todo closed (moved to `.planning/todos/completed/`).

## Task Commits

1. **Task 1: doc, README, unverified list, CI and flake backfill** - `c4a7158` (docs); final gate green on it
2. **Task 2: final audit, mapping, proposals, flake resolution** - `b426246` (docs)
3. **Human-check follow-up: approved wording applied, todo closed** - `1084a7b` (docs)

**Plan metadata:** the docs commit for this SUMMARY, STATE and ROADMAP progress.

## Deviations from Plan

### Delegated by the orchestrator (user-authorized)

**1. ROADMAP.md and REQUIREMENTS.md were edited by this executor.**
- **Why:** the plan says the orchestrator or the user edits them after approval; the orchestrator relayed the user's explicit approval and delegated the edit.
- **What:** SC1 and SC4 in ROADMAP and VER-01 and VER-04 in REQUIREMENTS replaced by the approved proposal texts verbatim (taken programmatically from final-audit.txt); VER-01 and VER-04 ticked and their traceability rows set to Complete.
- **Commit:** `1084a7b`. This makes the plan's "no 17-05 commit touches ROADMAP/REQUIREMENTS" acceptance line true only for `c4a7158` and `b426246`.

### Auto-handled

**2. [Rule 3 - blocking] gate script path.** The first background gate run could not find the script (Git Bash `/tmp` versus the tool's temp path). Recreated it under the real `/tmp/gsd-bak/ci/` and ran once; no CI was triggered by the failed attempt.

**3. [Process] Amended an unpushed commit.** A failed `git add` (a path already moved by `git mv`) made the first attempt of `1084a7b` contain only the rename; the commit was amended before any push.

Otherwise the plan was executed as written. Backfilled records (ci-runs and flake-timing lines for earlier gated runs and the red-then-fixed opengl soak run 40993938470) came from `gh run view --log`.

## Known Stubs

None.

## Threat Flags

None. Docs, evidence and a README paragraph only; no product code changed (`git diff 9ae347f HEAD -- packages example/lib example/integration_test native` is empty).

## Self-Check: PASSED

- docs/perf/fallback-uhd-regression.md, final-audit.txt, unverified.txt exist; commits c4a7158, b426246, 1084a7b are ancestors of HEAD.
- Audit keys all `ok`; protected user files unchanged (`cmp` against the `.17-05-pre` copies).

---
phase: 10-composition-spike
plan: 02
subsystem: testing
tags: [flutter, impeller, integration-test, sdk-pin, mpv-kit, benching]

requires:
  - phase: 10-composition-spike
    provides: 10-01 REA conclusions (ANGLE stays in the handoff; GL_RGBA8 format cliff; no fence)
  - phase: 09-8k-full-rate
    provides: the locally installed Flutter 3.47.8 SDK and engine artifact

provides:
  - A single-testWidgets D-04 harness (1080p chain, 4K target, 100 rounds / >=30 s)
  - Pinned 3.47.8 SDK/engine identity evidence (version, revisions, DLL sha256/size, disk numbers)
  - A pre-build disk gate recorded as data (status ok, avail_bytes, threshold)
  - CI FLUTTER_VERSION synced to 3.47.8 (the only Phase 10 CI change)

affects: [phase-11, 10-03-impeller-smoke-run]

actuals:
  tokens: 5200
  tasks: 1
  commits: 1
  plan_head_before: 7cbbb8d4077ff5f093ea5286e17ef4e654656e6d
  plan_head_after: f56440d8c555b6352657eb99df190a717e8d1fdb

tech-stack:
  added: []
  patterns:
    - "Single-testWidgets BENCH harness with three stage lines (preflight / soak-start / complete)"
    - "Identity gate before measurement: resolved libmpv path and mpv backend, else inconclusive"
    - "Idle events classified by mount window (>= 500 ms mounted) so off-screen idle is not a renderer failure"

key-files:
  created:
    - example/integration_test/impeller_smoke_test.dart
    - .planning/phases/10-composition-spike/evidence/sdk-3.47.8.txt
    - .planning/phases/10-composition-spike/evidence/disk-gate.txt
  modified:
    - .github/workflows/flutter-plugin.yml

key-decisions:
  - "The smoke uses the single local Flutter 3.47.8 install (framework 737ba8f885, engine revision cf636b1dfb); no second SDK was installed and no engine DLL was substituted"
  - "Identity is proven before measurement: MpvLibrary.resolvedPath must equal MPV_KIT_LIBMPV_PATH (case-insensitive) and controller.backend must be vulkan, else the run is inconclusive rather than an Impeller result"
  - "engineRenderer is emitted as unresolved-by-harness by design: only the engine log line can prove the renderer, and 10-03 records it alongside the command line"
  - "A supported pixel probe with nonBlackRatio < 0.01 is a real compositing failure (failed); an unsupported probe is an evidence gap (inconclusive)"
  - "100 rounds are paced at ~250 ms so the soak spans >= 30 s; if the rounds finish early the harness keeps playback and the texture mounted until 30 s"

patterns-established:
  - "BENCH impeller <json> on stdout, one line per stage; no analyzer suppression comments are allowed in the harness"
  - "Disk gate and SDK identity are written to evidence files before any long build"

requirements-completed: [COMP-01]

coverage:
  - id: D1
    description: "Disk gate recorded before any long build, with raw df output, avail_bytes and the 5.5 GiB threshold"
    requirement: COMP-01
    verification:
      - kind: other
        ref: "plan verify gate 1 (disk-gate.txt status/avail_bytes/threshold greps) — passed"
        status: pass
    human_judgment: false
  - id: D2
    description: "Flutter 3.47.8 identity pinned to D-02a and CI FLUTTER_VERSION synced to 3.47.8"
    requirement: COMP-01
    verification:
      - kind: other
        ref: "flutter --version + sha256sum/stat + plan verify gates 2 and 3 — passed"
        status: pass
    human_judgment: false
  - id: D3
    description: "One-testWidgets harness containing the three D-04 parts, identity assertions, three BENCH stages, idle buckets and the non-black assertion"
    requirement: COMP-01
    verification:
      - kind: other
        ref: "plan verify gate 4 (string/structure greps) — passed"
        status: pass
    human_judgment: true
    rationale: "The greps prove structure and required strings; whether the workload and thresholds actually measure D-04/D-05 correctly is settled by review and by the 10-03 run, not by static analysis."
  - id: D4
    description: "dart analyze --fatal-infos is clean and the new file carries no analyzer suppression comments"
    requirement: COMP-01
    verification:
      - kind: other
        ref: "plan verify gate 5 (cd example && dart analyze --fatal-infos, exit 0) + ignore-count 0"
        status: pass
    human_judgment: false

duration: 7 min
completed: 2026-10-25
status: complete
---

# Phase 10 Plan 02: 3.47.8 Impeller Smoke Harness Summary

**A pinned-3.47.8, single-testWidgets D-04 harness now exists: 1080p chain, one 4K render target with a non-black pixel proof, and a 100-round / >=30 s resize-dispose soak, behind an identity gate that refuses to report an Impeller result from a substituted libmpv or a non-Vulkan backend.**

## Performance

- **Duration:** 7 min
- **Started:** 2026-10-24T17:26Z
- **Completed:** 2026-10-24T17:33Z
- **Tasks:** 1 of 1
- **Files changed:** 4 (3 created, 1 modified)
- **Commits:** 1 task commit (+1 metadata commit)

## Accomplishments

- Pinned the one local Flutter 3.47.8 SDK: framework `737ba8f885`, engine
  revision `cf636b1dfb`, Dart 3.13.7; engine DLL
  `9a3a09cabda0fb31b27313394205bdcac62a5211c0d71934d2272313ffb7d170`,
  46,636,544 B, with its 278,859,776 B PDB present locally.
- Wrote the disk gate before any build work: 8,183,160,832 B available
  against the 5,905,580,032 B (5.5 GiB) threshold, `status: ok`.
- Synced `.github/workflows/flutter-plugin.yml` `FLUTTER_VERSION` from
  3.47.6 to 3.47.8 — the only CI-side change in Phase 10 — and verified the
  literal appears exactly once.
- Added `example/integration_test/impeller_smoke_test.dart`: one
  `testWidgets`, one minimal `Texture` tree, and the D-04 three-part
  workload with `stage=preflight`, `stage=soak-start`, `stage=soak-progress`
  and `stage=complete` BENCH lines.
- The harness refuses to measure before proving identity: it compares
  `MpvLibrary.resolvedPath` with `MPV_KIT_LIBMPV_PATH` (case-insensitive) and
  requires `controller.backend == MpvVideoBackend.vulkan`; a mismatch emits
  `result=inconclusive` with `lastOpenAttempts` and rethrows.
- `result=pass` additionally requires `pixelProbe.supported == true` and
  `nonBlackRatio >= 0.01`; an unsupported probe downgrades to
  `inconclusive`, and a black-but-alive frame is `failed`, never `pass`.

## Task Commits

1. **Task 1: pin 3.47.8 SDK, sync CI lock, write the Impeller smoke harness** — `f56440d` (test)

**Plan metadata:** committed separately after this SUMMARY.

## Files Created/Modified

- `example/integration_test/impeller_smoke_test.dart` — the D-04 harness:
  `_SmokeHarness`, `_emitBench`, `_nextFrame`, `_idleTimeout`,
  `_minNonBlackRatio`, identity gate, event aggregation, idle buckets,
  pixel probe, explicit controller-then-player teardown.
- `.planning/phases/10-composition-spike/evidence/sdk-3.47.8.txt` — SDK and
  engine identity, exact commands, CI lock proof, disk numbers, exclusions.
- `.planning/phases/10-composition-spike/evidence/disk-gate.txt` — raw
  `df -B1 .` output, `status: ok`, `avail_bytes`, `threshold_bytes`.
- `.github/workflows/flutter-plugin.yml` — `FLUTTER_VERSION: 3.47.8`.

## Decisions Made

- **One SDK, no substitution.** Everything (pub get, build, test) uses
  `D:/flutter` 3.47.8; the stale `example/windows/flutter/ephemeral` copy is
  explicitly not an artifact of this work.
- **Identity before measurement.** A silently substituted libmpv or a
  software fallback is recorded as `inconclusive`, never as an Impeller
  result (T-10-05/T-10-06).
- **`engineRenderer` stays `unresolved-by-harness`.** Dart cannot query the
  engine renderer; 10-03 pairs the complete line with the engine's
  "Using the Impeller rendering backend" log line and the command line.
- **Idle is classified by mount window.** Only idle events arriving after
  the texture has been continuously mounted for 500 ms
  (`VideoRenderer::kIdleTimeout`) and after `soak-start` count as
  `idleSoak`; unmount-window idle is `idleDuringUnmount`.
- **Black frame = failure, missing probe = evidence gap.** A supported probe
  below 1% non-black pixels is `failed`; an unsupported probe is
  `inconclusive`.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- The first `dart analyze` run reported one real error: a `double` was passed
  to `Duration(milliseconds:)` while padding the soak to 30 s. Fixed in place
  (`ceiling` + `Duration(seconds:)`) before the commit; the final analyzer
  run is clean.

## User Setup Required

None - no external service configuration required.

## Threat Surface

Mitigations T-10-05 through T-10-08 are implemented in this plan:

- T-10-05: `resolvedPath` assertion plus `resolvedLibmpv` /
  `lastOpenAttempts` in the BENCH line.
- T-10-06: `engineRenderer` is explicitly `unresolved-by-harness`; the
  renderer verdict is deferred to the engine log in 10-03.
- T-10-07: disk gate written before any build; `status: ok` with raw numbers.
- T-10-08: single 3.47.8 install, CI `FLUTTER_VERSION` synced and grepped,
  engine DLL hash recorded.

No new runtime surface, no packages added, no public API change.

## Next Phase Readiness

- 10-03 can run the harness unchanged:
  `MPV_KIT_LIBMPV_PATH=<libmpv> PATH="$PATH:<libdir>" D:/flutter/bin/flutter
  test integration_test/impeller_smoke_test.dart -d windows
  --enable-impeller` (plus the `--no-enable-impeller` control).
- 10-03 must fill `engineRenderer` from the engine's own log line and record
  the command line; the harness deliberately cannot do that.
- The run was not executed in 10-02 by design (the plan scopes 10-02 to
  building and statically verifying the harness); the first execution and
  its pass/inconclusive/failed classification belong to 10-03.

## Self-Check: PASSED

- `example/integration_test/impeller_smoke_test.dart`,
  `evidence/sdk-3.47.8.txt` and `evidence/disk-gate.txt` exist.
- Commit `f56440d` is an ancestor of HEAD; it contains exactly the four
  intended files and no deletions.
- All five plan `<automated>` gates were re-run after the commit and passed;
  `dart analyze --fatal-infos` reports no issues.

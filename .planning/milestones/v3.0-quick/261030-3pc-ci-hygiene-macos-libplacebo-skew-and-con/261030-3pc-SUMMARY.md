---
type: quick
task: 261030-3pc
status: complete
completed: 2026-10-30
commits: 5
commit_hashes: [ba9af05, 6f6631c, 127a348, c00e843, 6ce5fba]
plan_head_before: 0e149daa807d15f68d58cb90e40b4480ecc05f9a
plan_head_after: 6ce5fba6f5f765431fcebe88bbfa582bda803128
ci: native-verify 40939860843 + flutter-plugin 40939860892 on 127a348; native-verify 40943562883 + flutter-plugin 40943562876 on c00e843 (all jobs success). First attempt 6f6631c: native-verify 40937808629 failed (macos-15-intel badsig, fixed in 127a348)
requirements: [VER-02, RBE-04]
actuals:
  tasks: 2
  commits: 5
---

# Quick 261030-3pc: macOS verify libplacebo skew and constants audit re-pin

## Outcome
Both items deferred by 17-01 are resolved.

1. The `integration-test (macos-15, ...)` job no longer resolves any dylib
   through its own Homebrew. The `macos` build job stages libmpv's complete
   Homebrew closure next to it (35 files) with `@loader_path` install names; the
   integration job installs no formula, checks the closure and proves in process
   which images were loaded.
2. `bash .planning/phases/12-renderbackend-seam/tools/constants_audit.sh` prints
   `CONSTANTS ok` on HEAD. The three constants changed on purpose by 0e792c8
   moved to fixed-count REPINNED checks.

Two consecutive pushed SHAs gated green on native-verify and flutter-plugin,
every job `success` and none skipped: 127a348 (fix) and c00e843 (its docs-only
child).

## Approach and why
- Closure staging, not a version check. Homebrew cannot install a pinned old
  bottle and an upgrade cannot fix a newer one, so recording `brew list
  --versions` only turns the flake into a clearer red. Staging removes the second
  Homebrew resolution.
- Not dylibbundler: one more unpinned formula, and it prompts on stdin for an
  unresolved `@rpath` (a hang risk; 261028-otr already lost a run to a hung
  step). About 250 lines of auditable bash 3.2 do the job.
- Removing the integration job's Homebrew install is safe because both macOS app
  runs load either the pinned hook bundle (no Homebrew) or the staged libmpv whose
  dependencies are all in `stage/`; the probe asserts `homebrew=0` and the check
  asserts only `@loader_path` and OS references. No DYLD_* variable is used, so
  SIP/hardened-runtime stripping cannot matter.
- The audit keeps base 3a5f450 for the 12 untouched checks (including the
  allocation fallback quarantine 2 / ring 5) so the re-pin cannot weaken them;
  only the four values 0e792c8 changed deliberately (golden re-freeze approved by
  the user, `golden_refreeze: approved` in 261029-rcc-CONTEXT.md) are pinned by
  count.

## Changes
- `.planning/phases/12-renderbackend-seam/tools/constants_audit.sh` (ba9af05):
  three CHECKS entries removed, `REPINNED` array (kPresentTimeout{50} 0,
  `kReadyDepth = 2` 1, `ring_size_ = 6` 1, ring formula 1) with a comment citing
  0e792c8 / 261029-rcc / the approved re-freeze; a malformed entry exits 2. PLAN.md
  committed with it.
- `tools/stage_macos_closure.sh` (6f6631c, 127a348): stage and `--check` modes,
  `MACOS-CLOSURE` lines, `resigned=` for unverifiable copies.
- `tools/macos_dyld_images.dart` (6f6631c): `dlopen` plus dyld image list.
- `.github/workflows/native-verify.yml` (6f6631c): macos job runs the stager;
  integration-test drops `macOS runtime dependencies` and gains `Staged libmpv
  closure (macOS)`; comments reworded. Every env value and test command unchanged.
- Evidence: `ci-runs.txt`, `deferred-items.md` (Status lines on items 1 and 2),
  `261030-3pc-ci.txt`, `261030-3pc-local-checks.log` (c00e843, 6ce5fba).

## Proof
constants_audit on HEAD: `CONSTANTS ok`. At 4be7678 (parent of 0e792c8) it exits
1 with exactly four `pinned=` drift lines.

macOS integration job, both samples (job `integration-test (macos-15, macos,
libmpv-verify-macos-macos-15, libmpv.2.dylib)`):

```
run 40939860843 (127a348)
MACOS-CLOSURE check entry=libmpv.2.dylib files=35 external=0
MACOS-DYLD api=2.6 libmpv=/Users/runner/work/mpv_kit/mpv_kit/stage/libmpv.2.dylib
MACOS-DYLD summary staged=35 homebrew=0 libplacebo=/Users/runner/work/mpv_kit/mpv_kit/stage/libplacebo.360.dylib
INTEGRATION {"libmpvApi":"2.5",... "backend":"vulkan" ...}   (pinned bundle run)
INTEGRATION {"libmpvApi":"2.6","mpvVersion":"mpv vv0.41.0-1115-gb2c255c13","backend":"software",...}

run 40943562883 (c00e843)   identical summary: staged=35 homebrew=0 libplacebo=.../stage/libplacebo.360.dylib
```

Build job (`macos (macos-15)`), both runs:
`MACOS-CLOSURE file=libplacebo.360.dylib from=/opt/homebrew/Cellar/libplacebo/7.360.1/lib/libplacebo.360.dylib`,
`MACOS-CLOSURE staged=34 rewritten=15 resigned=0 ...`, `check ... files=35 external=0`.
Intel (`macos (macos-15-intel)`): `staged=34 rewritten=15 resigned=16`, `check ... files=35 external=0`.
No `Library not loaded` line in any macOS integration log.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Intel Homebrew bottles carry no valid signature**
- **Found during:** Task 2, gate 1 on 6f6631c (run 40937808629, `macos (macos-15-intel)`)
- **Issue:** 15 rewritten files were re-signed, but 16 unmodified copies failed
  `codesign --verify`, so `--check` failed the job (and `integration-test` was
  skipped). arm64 bottles are signed, so macos-15 was green.
- **Fix:** the stager signs every staged copy that does not verify (ad hoc,
  like the rewritten ones) and prints `resigned=<n>`; the check stays strict.
  Harness scenario S6 added.
- **Files modified:** tools/stage_macos_closure.sh
- **Commit:** 127a348

### Plan-shape notes
- The plan's Task 1 verify expects exactly two commits (`rev-list --count` = 2)
  and its scope check at the end of Task 2 assumed no fix-forward; the dispatch
  required PLAN.md in commit A, so commit A (ba9af05) carries PLAN.md as well as
  the audit (amended before any push). The fix-forward restarted the consecutive
  pair, so the gated pair is 127a348 + c00e843, not 6f6631c + its child.
- Gate 1 on 6f6631c failed for a real reason, so no rerun was used (zero reruns).
- The stager is about 250 lines and writes `MACOS-CLOSURE staged=` with a new
  `resigned=` field in addition to the plan's spec.

## Limits
- Two samples show the mechanism, not the absence of every future flake. What
  changed is that the load path no longer consults the integration runner's
  Homebrew at all.
- The sandbox is still off for the branch run (PlistBuddy on the runner checkout).
- Branch libmpv plus the Vulkan renderer in the app is still unverified
  (unchanged from 261028-otr; the branch run forces the software renderer).
- The macOS verify artifact now carries Homebrew's (possibly GPL) FFmpeg closure
  for 14 days, like the Windows msys2 stage, and is never a release bundle.
- `macos-route` (unchanged workflow, not gated) was green on 0e149da and failed
  on 6f6631c, 127a348 and c00e843 (runs 40937808507, 40939860844, 40943562936) in
  `route-probe (macos-15)`, step `Route probe (HEAD plugin)`: the hwdec section
  `expect ... contains 'zero-copy-bad-frame'` got `Set:['zero-copy',
  'zero-copy-render-unverified','unavailable']` (macos_route_test.dart:755). That
  job measures the pinned bundle and the HEAD plugin; nothing under packages/,
  native/ or example/ changed in this plan, so the cause is not these commits, but
  it was not investigated here. Recommend a look before Phase 17 relies on it.
- Commit D (6ce5fba) is not pushed; commit A..C are on origin
  (c00e843 is the pushed head).

## Known Stubs
None.

## Threat Flags
None (no new endpoints, auth paths or schema; the stager copies and re-signs
third-party Homebrew binaries into a verify-only artifact, covered by
T-2610303pc-01/02/04 in the plan).

## Self-Check: PASSED
- tools/stage_macos_closure.sh, tools/macos_dyld_images.dart,
  261030-3pc-ci.txt, 261030-3pc-local-checks.log present.
- Commits ba9af05, 6f6631c, 127a348, c00e843, 6ce5fba are ancestors of HEAD;
  127a348 and c00e843 are ancestors of origin/feat/mpv-master-upgrade.
- `git rev-list --count 0e149da..HEAD` = 5 (matches `commits: 5`).

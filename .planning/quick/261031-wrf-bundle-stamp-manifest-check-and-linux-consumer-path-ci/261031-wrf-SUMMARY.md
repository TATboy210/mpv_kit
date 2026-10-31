---
type: quick
task: 261031-wrf
plan: 01
status: complete
completed: 2026-10-31
subsystem: mpv_kit_libs build hook, flutter-plugin CI
requirements: [GLX-01, GLX-02]
source: 17.1-REVIEW.md (WR-01, WR-03, IN-07)
commits: 2
plan_head_before: 8a2d64df0effc0041c08a645329f37a49cfe92d8
plan_head_after: ed36618c861e02487dace69b1e39e86faa0a5b95
commit_hashes: [d891f3b, ed36618]
ci: native-verify 41180276172 + flutter-plugin 41180276175 + macos-route 41180276139 on ed36618 (all success, attempt 1, no rerun)
actuals:
  tasks: 3
  commits: 2
---

# Quick 261031-wrf: stamp manifest check and Linux consumer-path CI

## Outcome

WR-01 and WR-03 of the 17.1 review are closed; no public API, version, bundle or release change (bundles.dart untouched, pubspecs stay 0.1.0-dev.4).

1. **WR-01 (d891f3b)** `resolvePinnedBundle` trusts a matching `<target>.ok` stamp only when `MANIFEST.txt` exists in the extraction and every shared library it lists directly under `lib/` exists (at least one listed). Otherwise it reinstalls from the archive re-hashed against the pin. Existence check only, no re-hashing. CHANGELOG 0.1.0-dev.4 line extended.
2. **WR-03 (ed36618)** The Linux pinned-only cell (INT-2) now does `unset MPV_KIT_LIBMPV_PATH` and runs `pinned_bundle_identity.sh linux-x64 build/linux/x64/debug/bundle/lib`, so libmpv.so.2 is found by default name in the app bundle's lib/ (RUNPATH `$ORIGIN/lib`). `PR_PIN` in `gate_expectations.sh` now expects `app_copy=same libmpv_env=unset` for Linux.

## RED / GREEN (Task 1, tdd)

Fixture: the resolvePinnedBundle group now bundles `lib/libmpv.so.2` plus a dependency `lib/libdep.so.1`.

RED (before the fix, `dart test test/bundle_test.dart`):
- `reinstalls when libmpv is gone but a dependency remains`: `Expected: contains 'libmpv.so.2'  Actual: ['libdep.so.1']`
- `reinstalls when the extraction has no MANIFEST.txt`: `Expected: true  Actual: false`
- `rejects a downloaded archive that does not match the pin` (IN-07) already passed at the old code; kept as a regression guard.

GREEN: `dart analyze --fatal-infos` clean, `dart test` in packages/mpv_kit_libs: 24 passed. native-verify also ran the group (gate expectation `resolvePinnedBundle reinstalls when the extracted directory is gone`).

## Gate (pushed head ed36618)

- Push: fast-forward `7b9871c..ed36618` of `feat/mpv-master-upgrade` with `--no-follow-tags`; it carried the local docs commits 0c95112, 3c44a95, 42094d3, 240186f, 8a2d64d. Remote tags before and after: exactly v0.1.0-dev.1 (+ peeled), dev.2, dev.3, dev.4 (identical `git ls-remote --tags`).
- `ci_gate.sh` with `PR_PIN` (native-verify, flutter-plugin, macos-route): `CI-GATE ok sha=ed36618c861e02487dace69b1e39e86faa0a5b95`, exit 0, attempt 1, no `gh run rerun`. Evidence kept in /tmp/gsd-bak/wrf/ci-runs.txt (the tracked evidence/ci-runs.txt was not touched).
- Linux INT-2 step log (run 41180276175, build (ubuntu-24.04, linux)):
  `PINNED-IDENTITY tag=v0.1.0-dev.4 target=linux-x64 stamp=match archive=match manifest=ok libs=17 app_copy=same libmpv_env=unset libmpv_sha256=5d1ee6220b9bb08f3c418d4c7617c408ecfb80e8287fe8f5811cb4913255bf80`
  and `PROBE {"api":"opengl", ... "supported":true,"nonBlackRatio":1.0,"orientation":"upright", ... "renderErrors":0 ...}` on llvmpipe.
- Windows INT-1 line unchanged: `PINNED-IDENTITY ... target=windows-x64 ... libs=24 app_copy=same libmpv_env=unset libmpv_sha256=1d66e561...`.
- bundle path assumption confirmed: `build/linux/x64/debug/bundle/lib` holds the 17 manifest libraries byte-identical.

## Deviations from Plan

None - plan executed as written. The IN-01 "third line" comment sits in the apt step, not the INT-2 step block, so it was left alone as the plan allows.

## Known Stubs

None.

## Self-Check: PASSED

- d891f3b and ed36618 are ancestors of HEAD and of origin/feat/mpv-master-upgrade.
- Edited files exist: bundle.dart, bundle_test.dart, CHANGELOG.md, flutter-plugin.yml, gate_expectations.sh.

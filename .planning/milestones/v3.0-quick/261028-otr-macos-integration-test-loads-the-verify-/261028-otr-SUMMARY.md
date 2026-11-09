---
type: quick
task: 261028-otr
status: complete
completed: 2026-10-28
commits: [e23fa38, 592015b, 95393c9, 5522944]
ci: native-verify 40676393002, flutter-plugin 40676393000, macos-route 40676392952 (all success)
---

# Quick 261028-otr: macOS integration leg exercises the branch libmpv

## Outcome
The `integration-test (macos-15, ...)` leg now loads THIS branch's
`libmpv.2.dylib` (artifact `libmpv-verify-macos-macos-15`) in the real example
app and asserts it by client API (2.6 after patch 0010; the pinned
v0.1.0-dev.3 bundle is 2.5). Partial by necessity: the branch build is run
with the software renderer only (see Limits).

Proof (run 40676393002, log /tmp/gsd-bak/ci/macos-integ-otr4.log):
- bundle run: `INTEGRATION {"libmpvApi":"2.5","mpvVersion":"mpv v0.41.0","backend":"vulkan",...}`
- branch run: `INTEGRATION {"libmpvApi":"2.6","mpvVersion":"mpv vv0.41.0-1115-gb2c255c13","backend":"software",...}`,
  `INTEGRATION-SOAK {"resizeEvents":30,"cycles":10,"renderErrors":0,"deviceLost":0}`
  (the test fails if `MPV_KIT_EXPECT_LIBMPV_API=2.6` does not match).

## Approach and why
- Hook-bundle route (like Windows) rejected: the artifact links Homebrew dylibs
  by absolute path, so a hook-bundled copy still reaches `/opt/homebrew`.
  `package.sh` cannot make it self-contained (Darwin branch demands the LGPL
  FFmpeg from the build prefix, rejects GPL libs; the verify job uses Homebrew
  FFmpeg), and re-building the LGPL stack in the verify job is not a CI-only
  change.
- Chosen: `MPV_KIT_LIBMPV_PATH` -> staged dylib (strict MpvLibrary), with the
  example's sandbox switched off on the runner's checkout only (PlistBuddy,
  never committed; shipped entitlements untouched). That alone loads the branch
  libmpv (`Player` creates), but with the Vulkan renderer the app dies in
  `MpvVideoController.create` ("No tests were found", no crash report on the
  runner; runs 40668191795, 40671229123, 40673113177). Probable cause (not
  proven): the artifact links Homebrew's Vulkan loader while the plugin loads
  the bundled MoltenVK, two Vulkan stacks in one process. So the branch run
  forces `MPV_KIT_VIDEO_RENDERER=software`.
- The previous pinned-bundle Vulkan run is kept (as `env -u MPV_KIT_LIBMPV_PATH`),
  so macOS Vulkan app coverage did not regress.

## Changes (CI/test only; no library/plugin code, API frozen)
- `.github/workflows/native-verify.yml`: macOS bundle run + new branch-libmpv step.
- `example/integration_test/real_plugin_test.dart`: INTEGRATION line carries
  `libmpvApi` / `mpvVersion`; optional `MPV_KIT_EXPECT_LIBMPV_API` expectation;
  two `INTEGRATION-STAGE` prints (kept; they localized the crash).

## Limits / unverified
- Branch libmpv + Vulkan renderer inside the macOS app is NOT verified (crash
  above; root cause unconfirmed). Branch Vulkan on macOS is covered only by the
  render_vk smoke test in the `macos` job.
- Sandbox is off for the branch run, so it does not prove sandboxed behavior.
- Run 40668191795 first failed on windows-11-arm (msys2 key trust, infra) and
  was re-run once with `--failed`; green afterwards.
- A diagnostic commit (592015b/95393c9) ran `find /` in a failure step and hung
  the job until cancelled (run 40673113177); that step was removed in 5522944.

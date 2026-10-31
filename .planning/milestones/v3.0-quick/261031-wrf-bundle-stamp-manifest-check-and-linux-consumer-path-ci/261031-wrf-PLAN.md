---
phase: quick-261031-wrf
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - packages/mpv_kit_libs/lib/src/bundle.dart
  - packages/mpv_kit_libs/test/bundle_test.dart
  - packages/mpv_kit_libs/CHANGELOG.md
  - .github/workflows/flutter-plugin.yml
  - .planning/quick/261031-wrf-bundle-stamp-manifest-check-and-linux-consumer-path-ci/261031-wrf-SUMMARY.md
autonomous: true
requirements: [GLX-01, GLX-02]
source: .planning/phases/17.1-close-gap-int-1-int-2-release-and-pin-a-libmpv-bundle-with-t/17.1-REVIEW.md (WR-01, WR-03)
decision: "User 2026-10-31: option 1 - fix WR-01 and WR-03, CI green, then pub.dev dry-run and confirmation."
---

<objective>
Close the two 17.1 review warnings that affect pub consumers before 0.1.0-dev.4 goes to pub.dev:
WR-01 (the hook stamp is trusted while any shared library remains, so a cache that lost libmpv but kept a dependency builds without libmpv) and
WR-03 (the Linux pinned-only CI cell loads libmpv by explicit path from the hook cache and never exercises the consumer path from the app bundle's lib/ by default name).
No public API change, no version bump (pubspecs stay 0.1.0-dev.4, not yet on pub.dev), no bundle/release change, bundles.dart untouched.
</objective>

<tasks>
<task type="auto" tdd="true">
  <name>Task 1: WR-01 - trust the stamp only when every MANIFEST lib/ shared library exists (test first)</name>
  <files>packages/mpv_kit_libs/lib/src/bundle.dart, packages/mpv_kit_libs/test/bundle_test.dart, packages/mpv_kit_libs/CHANGELOG.md</files>
  <action>
  RED: add tests in bundle_test.dart (same fixture style as the existing resolvePinnedBundle tests):
  (a) stamp matches, MANIFEST.txt present, lib/ keeps one dependency library but the libmpv library is deleted -> resolvePinnedBundle reinstalls from the valid cached archive WITHOUT calling fetch, and returns a set that includes libmpv;
  (b) stamp matches, MANIFEST.txt missing from the extraction -> reinstalls (no fetch when the archive is valid);
  (c) fetch writes a wrong archive -> throws BundleIntegrityException and writes no stamp (review IN-07).
  Run `dart test` in packages/mpv_kit_libs; (a) and (b) must fail at the current code; record the RED output in the commit body or SUMMARY.
  GREEN: in resolvePinnedBundle, when the stamp matches, read <target>/MANIFEST.txt with parseManifest; expected = keys under lib/ with no further '/' and isSharedLibrary(name); trust the stamp only if expected is non-empty and every expected file exists; otherwise fall through to the existing reinstall path (archive re-hashed against the pin). Existence check only, no re-hashing. Keep comment density and style of the file; update the existing comment.
  CHANGELOG 0.1.0-dev.4 entry of mpv_kit_libs: extend the existing stale-stamp line to say a cache missing any MANIFEST-listed library (not only an empty lib/) is reinstalled.
  `dart analyze --fatal-infos` and `dart test` green in packages/mpv_kit_libs. Do not reformat unrelated lines.
  One commit: `fix(libs): trust the bundle stamp only when every MANIFEST library is present (WR-01)`.
  </action>
  <verify>cd packages/mpv_kit_libs && dart analyze --fatal-infos && dart test</verify>
</task>

<task type="auto">
  <name>Task 2: WR-03 - Linux pinned-only cell runs the consumer path</name>
  <files>.github/workflows/flutter-plugin.yml</files>
  <action>
  In step "Pinned bundle only, forced opengl (INT-2)": mirror INT-1 - `unset MPV_KIT_LIBMPV_PATH`, run the same xvfb texture_probe_test, then `bash ../tools/pinned_bundle_identity.sh linux-x64 build/linux/x64/debug/bundle/lib` so the tool asserts app_copy=same and libmpv_env=unset. Update the step comment (libmpv.so.2 found by default name through the runner's $ORIGIN/lib RUNPATH; libEGL.so.1 is a host library). Check first that build/linux/x64/debug/bundle/lib is where Flutter 3.47.x puts native assets for a debug Linux build in this workflow; if the test step builds a different mode/dir, use that dir and say so.
  Also update the PR_PIN expectations in .planning/phases/17.1-*/tools/gate_expectations.sh ONLY if they assert the Linux line text `app_copy=skipped` / `libmpv_env=hook-cache` (then expect `app_copy=same` / `libmpv_env=unset`); otherwise leave it. If changed, include it in this commit.
  Fix the IN-01 stale "third line" comment only if it sits in the same step block; otherwise leave it.
  One commit: `ci(flutter-plugin): Linux pinned-only cell loads libmpv from the app bundle (WR-03)`.
  </action>
</task>

<task type="auto">
  <name>Task 3: push and gate</name>
  <action>
  One fast-forward push of the branch ref: `git push --no-follow-tags origin HEAD:refs/heads/feat/mpv-master-upgrade` (carries the local docs commits 0c95112..240186f too). Remote tags must stay exactly v0.1.0-dev.1..dev.4 before and after.
  Gate the pushed head with the phase tool `.planning/phases/17.1-*/tools/ci_gate.sh` and the PR_PIN expectation set (native-verify, flutter-plugin, macos-route). Required: the Linux INT-2 step log shows `PINNED-IDENTITY ... app_copy=same libmpv_env=unset` and the probe passes; the Windows INT-1 line unchanged; resolvePinnedBundle tests ran in native-verify.
  If the Linux consumer-path run fails because the bundle/lib closure or libEGL resolution is wrong, that is a real product finding: STOP and return a checkpoint with the log excerpt; do not paper over it by restoring MPV_KIT_LIBMPV_PATH.
  At most one `gh run rerun --failed` per gate, only for infra or registered flakes (macOS texture-probe black first frame; ubuntu opengl soak rssLateMiB).
  Write 261031-wrf-SUMMARY.md (RED/GREEN evidence, gate runs, Linux identity line) and add a row to STATE.md "Quick Tasks Completed"; commit by explicit path (local; it rides with the next push).
  </action>
</task>
</tasks>

<prohibitions>
- No tag, no --tags/--follow-tags/--mirror, no force, no other branch, no workflow dispatch, no `dart pub publish` of any kind.
- No change to bundles.dart, release.yml, native/, packages/mpv_kit, packages/mpv_kit_video, pubspec versions, or any golden-freeze-17 file.
- Protected user files: .planning/config.json, .planning/state.json, .planning/tmp/, .planning/ui-reviews/, .planning/debug/, engine_repo_embedder.cc, .planning/phases/17.1-*/.gitkeep.
</prohibitions>

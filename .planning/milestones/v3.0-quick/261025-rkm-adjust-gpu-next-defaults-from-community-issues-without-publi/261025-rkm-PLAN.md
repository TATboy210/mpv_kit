---
phase: quick-261025-rkm
plan: 261025-rkm
type: execute
wave: 1
depends_on: []
files_modified:
  - packages/mpv_kit/lib/src/player/player.dart
  - packages/mpv_kit/test/player_test.dart
autonomous: true

must_haves:
  truths:
    - "A Player created with no hwdec-codecs option reports hwdec-codecs equal to the running libmpv's own default list with only ffv1 removed (mpv #18255)"
    - "A Player created with an explicit hwdec-codecs option (e.g. all) keeps exactly the user's value"
    - "A source at least 7680 pixels wide plays in a default Player with hdr-compute-peak=no (mpv #17626)"
    - "A Player created with an explicit hdr-compute-peak option keeps the user's value after a source at least 7680 pixels wide loads"
    - "Mpv and Player public surfaces are unchanged (api_freeze_test passes with no baseline edit)"
  artifacts:
    - path: packages/mpv_kit/lib/src/player/player.dart
      provides: "Player factory default hwdec-codecs entry without ffv1, commented with mpv #18255; existing hdr-compute-peak=no entry commented with mpv #17626"
      contains: "'hwdec-codecs': 'h264,vc1,hevc,vp8,vp9,av1,prores,prores_raw,dpx,apv',"
    - path: packages/mpv_kit/test/player_test.dart
      provides: "Real-libmpv group pinning both community defaults and their user overrides"
      contains: "mpv #18255"
  key_links:
    - from: "Player factory options map"
      to: "Mpv.create (applied before mpv_initialize; user options spread last)"
      via: "'hwdec-codecs' map entry placed before the trailing ...options spread"
      pattern: "'hwdec-codecs': 'h264"
    - from: "player_test drift guard"
      to: "the running libmpv's own hwdec-codecs default"
      via: "a raw Mpv.create handle read with getPropertyString('hwdec-codecs')"
      pattern: "getPropertyString\\('hwdec-codecs'\\)"
---

<objective>
Adjust two gpu-next-related Player defaults from mpv community issues, with no public API change.

1. Exclude `ffv1` from `hwdec-codecs` (mpv #18255): FFmpeg's Vulkan FFV1 hwaccel produces an invalid SPIR-V shader (`OpVariable` not first in block), the driver resets and mpv gets `VK_ERROR_DEVICE_LOST`. Upstream attributed it to FFmpeg; the issue is still open. Player's default `hwdec` starts with `vulkan`, and the vendored mpv default list (`native/mpv/video/decode/vd_lavc.c`, the `hwdec_conf` defaults, line 176: `h264,vc1,hevc,vp8,vp9,av1,prores,prores_raw,ffv1,dpx,apv`) includes `ffv1`, so any ffv1 file goes straight into the crash path. The bundled FFmpeg is configured with `--enable-vulkan` and does not disable hwaccels (`native/build/ffmpeg.sh`), so the ffv1 Vulkan hwaccel is built. A runtime probe against the local libmpv (`bt/libmpv-2.dll`, mpv v0.41.0-689) confirmed that the Player default currently reports the full list including `ffv1`. **This part is a real change, not a no-op.**

2. `hdr-compute-peak=no` for sources at least 7680 pixels wide when the user has not set it (mpv #17626, a gpu-next 8K HDR render-peak and dropped-frame regression that improved when per-frame peak detection stopped blocking). **The behavior already exists:** the Player factory already sets `'hdr-compute-peak': 'no'` for every source (player.dart line 103), before the user's `...options` spread. A runtime probe confirmed that `getPropertyString('hdr-compute-peak')` returns `no` after `av://lavfi:testsrc2=size=7680x16` loads (videoParams width 7680), and that a user-passed `auto` survives. A per-file rule keyed on width (`file-local-options/hdr-compute-peak` after a `videoParams` check) could only ever write `no` where `no` is already set, and must leave any user-set value alone, so it would be dead code. **Recorded decision: no runtime mechanism is added.** This part delivers (a) the mpv #17626 comment on the existing entry and its doc bullet, and (b) real-libmpv tests that pin the required behavior so a later change to the global default cannot silently drop it. `Player.wrap(mpv)` applies none of the factory defaults by design (the caller owns every option). The item scopes the change to "the Dart location that holds current default options", which is the Player factory, so wrap is out of scope for both parts.

Purpose: stop a reproducible GPU device loss on ffv1 sources under the default Vulkan hwdec, and lock in the 8K gpu-next peak-detection behavior, while keeping the public API frozen and the diff small (CLAUDE.md: API freeze, minimal and independently revertible changes).
Output: one new map entry plus two comment updates in `player.dart`; one new real-libmpv test group in `player_test.dart`.
</objective>

<execution_context>
@~/.claude/gsd-core/workflows/execute-plan.md
@~/.claude/gsd-core/templates/summary.md
</execution_context>

<context>
@.planning/STATE.md
@CLAUDE.md
@packages/mpv_kit/lib/src/player/player.dart
@packages/mpv_kit/test/player_test.dart

Facts already established while planning (do not re-derive):
- Factory doc comment: player.dart lines 51-81. The options map passed to `Mpv.create` is at lines 88-106. `'hwdec': 'vulkan,d3d11va-copy,auto-safe',` is line 90. `'hdr-compute-peak': 'no',` is line 103. `...options,` is spread last at line 105, so user options always win.
- The doc and inline comments in this file are Chinese. Match that and do not translate existing comments. Test names and test comments in `player_test.dart` are English.
- `Mpv.dispose()` returns `void` (synchronous); `Player.dispose()` returns a `Future`. Both work with `addTearDown`.
- `getPropertyString('hdr-compute-peak')` returns the string `no`, `auto` or `yes`. `tryGetProperty` returns `false` for `no` (node flag form), so tests must use `getPropertyString`.
- `getPropertyString('hwdec-codecs')` on a raw `Mpv.create(options: const {'vo': 'null', 'ao': 'null'})` handle returns mpv's own default list.
- `videoParams` may emit before a late `listen`. Use the file's existing `_until(state, predicate)` helper (10 s timeout), not `stream.firstWhere`.
- `av://lavfi:testsrc2=size=7680x16:rate=30:duration=2` is a cheap source that is 7680 pixels wide. A real 8K frame (about 50 MiB YUV420P) is not needed to exercise the width condition.
- At HEAD, `dart format --set-exit-if-changed` already fails on both files (it would rewrite 45 lines of player.dart and 72 lines of player_test.dart). **Do NOT run `dart format` on either file**, because it would add unrelated churn. Hand-write the new lines in dart-format style: 2-space indent, 80 columns, trailing commas on multi-line lists. `dart analyze --fatal-infos` is clean at HEAD and must stay clean.
- At HEAD, none of the strings `mpv #18255`, `mpv #17626` or `hwdec-codecs` appear in either file (each grep -c returns 0).
- The local test command already works: `MPV_KIT_LIBMPV_PATH=${MPV_KIT_LIBMPV_PATH:-/Users/35490/mpv_kit/bt/libmpv-2.dll} dart test test/player_test.dart -n '<filter>'`, run from packages/mpv_kit. The auto-tune group passed this way during planning.
- A stray untracked `packages/mpv_kit/test/zz_rki_probe_test.dart` belongs to sibling item 261025-rki. Do not touch, stage or delete it. All test commands in this plan are file-scoped, so it does not affect them.
</context>

<tasks>

<task type="tracer" tdd="true">
  <name>Task 1: Exclude ffv1 from the Player default hwdec-codecs (mpv #18255), proven against the running libmpv</name>
  <files>packages/mpv_kit/test/player_test.dart, packages/mpv_kit/lib/src/player/player.dart</files>
  <behavior>
    - Test 1 "default hwdec-codecs is the mpv default list without ffv1 (mpv #18255)": open a raw `Mpv.create(options: const {'vo': 'null', 'ao': 'null'})` and read its `hwdec-codecs` as the mpv default list. Create `Player(options: const {'vo': 'null', 'ao': 'null'})` and read its `hwdec-codecs`. Split both on `,`. The Player list does not contain `ffv1`, and it equals the mpv default list with `ffv1` filtered out, element for element and in order. The `reason:` text tells the reader to resync the Player default with `hwdec_conf` in native/mpv/video/decode/vd_lavc.c. This test fails at HEAD because the Player list still contains ffv1.
    - Test 2 "an explicit hwdec-codecs option overrides the default": `Player(options: const {'vo': 'null', 'ao': 'null', 'hwdec-codecs': 'all'})` reports exactly `all`. This passes at HEAD by design: it guards user-first precedence after the change.
  </behavior>
  <action>
    RED: in packages/mpv_kit/test/player_test.dart, add a new `group('community gpu-next defaults (real libmpv)', ...)` between the closing of the existing `group('demuxer queue auto-tune (real libmpv)', ...)` and the `test('catalog is generated from mpv docs', ...)` at the end of `main`. Give it the same skip as the auto-tune group: `skip: _libmpvMissing ? 'libmpv not available' : null`. Inside it, add Test 1 and Test 2 from `<behavior>`. Use those test names verbatim; both contain the literal `hwdec-codecs`, which the verify filter matches. Register every handle with `addTearDown` (raw handle: `addTearDown(raw.dispose)`; player: `addTearDown(p.dispose)`). Avoid the `!` operator: read each string with `?? ''` before splitting. Add a one-line English comment above Test 1. It should say the test compares against the running libmpv's own default, so an mpv upgrade that changes the list fails here instead of silently losing hwdec for the new codec. Run the Task 1 verify command and confirm that Test 1 FAILS (ffv1 present) and Test 2 passes. Commit as `test(quick-261025-rkm): add failing test for ffv1-free default hwdec-codecs`.

    GREEN: in packages/mpv_kit/lib/src/player/player.dart, inside the `Mpv.create` options map of the `Player` factory, add a new entry directly after the `'hwdec': 'vulkan,d3d11va-copy,auto-safe',` line (line 90). The key is `'hwdec-codecs'` and the value is exactly `h264,vc1,hevc,vp8,vp9,av1,prores,prores_raw,dpx,apv`, which is the vendored mpv default list in its original order with only ffv1 removed. Put a 2-3 line Chinese `//` comment directly above the entry. It must say: mpv #18255, the FFmpeg Vulkan FFV1 hwaccel shader takes the GPU down with VK_ERROR_DEVICE_LOST, and ffv1 is an intra-only lossless codec so multi-threaded software decoding is enough. It must also say the rest of the list follows vd_lavc.c `hwdec_conf` verbatim. Keep the entry before the `...options` spread, so a user-passed `hwdec-codecs` still wins. In the factory doc comment, add one paragraph after the `auto-safe` paragraph (the one ending at line 62) that records the same facts in Chinese. That paragraph must cite mpv #18255, name native/mpv/video/decode/vd_lavc.c `hwdec_conf` as the source of the list, and say that player_test pins the list against the running libmpv's default. It must also say: once upstream fixes the hwaccel, delete this entry to return to mpv's default, and a user can override it through [options] (for example `all`). Do not use TODO/FIXME markers; the project has none. Do not change any other default and do not touch the stale `hwdec=vulkan,auto-safe` wording on line 53 (out of scope). Run the verify command again: both tests pass. Run `dart analyze --fatal-infos` in packages/mpv_kit: no issues. Commit as `fix(player): exclude ffv1 from default hwdec-codecs (mpv #18255)`.
  </action>
  <verify>
    <automated>cd D:/mpv_kit/packages/mpv_kit && MPV_KIT_LIBMPV_PATH=${MPV_KIT_LIBMPV_PATH:-/Users/35490/mpv_kit/bt/libmpv-2.dll} dart test test/player_test.dart -n 'hwdec-codecs' --reporter expanded && dart analyze --fatal-infos && test "$(grep -c "'hwdec-codecs': 'h264,vc1,hevc,vp8,vp9,av1,prores,prores_raw,dpx,apv'," lib/src/player/player.dart)" = 1 && test "$(grep -c 'mpv #18255' lib/src/player/player.dart)" -ge 2</automated>
  </verify>
  <done>Both hwdec-codecs tests pass against the real libmpv. Test 1 was observed failing before the GREEN edit. player.dart contains exactly one `'hwdec-codecs': 'h264,vc1,hevc,vp8,vp9,av1,prores,prores_raw,dpx,apv',` entry (baseline 0) and at least two `mpv #18255` citations, one inline and one in the doc (baseline 0). `dart analyze --fatal-infos` is clean, and two commits (test, then fix) exist.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 2: Pin hdr-compute-peak=no for 7680-wide sources (mpv #17626) and record why no per-resolution rule is added</name>
  <files>packages/mpv_kit/test/player_test.dart, packages/mpv_kit/lib/src/player/player.dart</files>
  <behavior>
    - Test 3 "a 7680-wide source plays with hdr-compute-peak=no by default (mpv #17626)": `Player(options: const {'vo': 'null', 'ao': 'null'})` opens `av://lavfi:testsrc2=size=7680x16:rate=30:duration=2`. After `_until(p.videoParams, (v) => v?.width == 7680)`, `p.mpv.getPropertyString('hdr-compute-peak')` equals `no`.
    - Test 4 "an explicit hdr-compute-peak option survives a 7680-wide source": the same flow with `'hdr-compute-peak': 'auto'` added to the options. After the width-7680 params arrive, the value equals `auto`.
    - Both pass at HEAD, because the requirement is already met by the global default. Their RED proof is a mutation check, described in the action.
  </behavior>
  <action>
    Tests: in the `community gpu-next defaults (real libmpv)` group created in Task 1, add Test 3 and Test 4 from `<behavior>`. Use those names verbatim; both contain `hdr-compute-peak`, which the verify filter matches. Register `addTearDown(p.dispose)` for each player and use the existing `_until` helper. Add a one-line English comment above Test 3. It should say that a 7680x16 source exercises the width condition without allocating real 8K frames.

    RED by mutation, because these are characterization tests for behavior that already exists (see objective part 2): temporarily delete the `'hdr-compute-peak': 'no',` line from the factory map and run the Task 2 verify filter. Test 3 must FAIL, because mpv's default `auto` is reported. Then restore the line byte-for-byte (`git diff` on player.dart must show only Task 1 and Task 2 comment changes). Record the observed failure in the SUMMARY; do not commit the mutated state. Commit the tests as `test(quick-261025-rkm): pin hdr-compute-peak=no for 7680-wide sources`.

    Comments: in player.dart, add a 2-line Chinese `//` comment directly above the existing `'hdr-compute-peak': 'no',` entry (line 103, inside the `4K/8K 满帧参数包` section). It must cite mpv #17626: gpu-next per-frame HDR peak detection causes render peaks and dropped frames on 8K HDR. It must also say that this global `no` already covers sources at least 7680 wide, so no per-resolution rule is needed. In the factory doc comment, append to the existing `dither=no` / `hdr-compute-peak=no` bullet (lines 79-81) one sentence that cites mpv #17626. The sentence should say the global default already covers 8K gpu-next, a per-file rule keyed on width would only re-write a value that is already set (and must not touch a user value), and so none is added. Do not change the value, do not add any observer, file-local option or new member to Player (per the objective's recorded decision), and do not touch `Player.wrap`. Run the Task 2 verify command, then the full plan verification below. Commit as `docs(player): cite mpv #17626 on the hdr-compute-peak default`.
  </action>
  <verify>
    <automated>cd D:/mpv_kit/packages/mpv_kit && MPV_KIT_LIBMPV_PATH=${MPV_KIT_LIBMPV_PATH:-/Users/35490/mpv_kit/bt/libmpv-2.dll} dart test test/player_test.dart -n 'hdr-compute-peak' --reporter expanded && dart analyze --fatal-infos && test "$(grep -c 'mpv #17626' lib/src/player/player.dart)" -ge 2 && test "$(grep -c "'hdr-compute-peak': 'no'," lib/src/player/player.dart)" = 1</automated>
  </verify>
  <done>Both hdr-compute-peak tests pass against the real libmpv, and Test 3 was observed failing with the default line removed (mutation recorded in the SUMMARY). player.dart cites `mpv #17626` at least twice, inline and in the doc (baseline 0). The `'hdr-compute-peak': 'no',` entry is still present exactly once (baseline 1, invariant). Player has no new member, observer or file-local option.</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| media file to decoder/GPU | Untrusted media selects the codec path. An ffv1 stream under the default Vulkan hwdec reaches a hwaccel that crashes the GPU driver. |
| app options to Player factory | The host application's `options` map overrides defaults. It is trusted, but user-first precedence must be kept. |

## STRIDE Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation Plan |
|-----------|----------|-----------|----------|-------------|-----------------|
| T-261025rkm-01 | Denial of Service | Player factory default `hwdec-codecs` (player.dart) | high | mitigate | Remove `ffv1` from the default list (Task 1), so an ffv1 file software-decodes instead of triggering VK_ERROR_DEVICE_LOST and a driver reset. Pinned by Test 1 against the running libmpv. |
| T-261025rkm-02 | Tampering | Default list drifting from the mpv default on an mpv upgrade, which silently drops hwdec for new codecs | medium | mitigate | Test 1 derives its expectation from the running libmpv's own `hwdec-codecs` default, so any list change in a new libmpv fails the suite. |
| T-261025rkm-03 | Denial of Service | 8K gpu-next render peaks from HDR peak detection (mpv #17626) | medium | mitigate | The existing global `hdr-compute-peak=no` is kept and pinned by Test 3 with a 7680-wide source (mutation-proven load-bearing). |
| T-261025rkm-04 | Elevation of Privilege | User override precedence (`...options` spread last) | low | mitigate | Tests 2 and 4 prove that explicit `hwdec-codecs` and `hdr-compute-peak` values survive, so the defaults never override the host. |
| T-261025rkm-SC | Tampering | npm/pip/cargo installs | low | accept | This plan installs no packages. It only edits Dart source and tests. |
</threat_model>

<verification>
Run from D:/mpv_kit/packages/mpv_kit with `MPV_KIT_LIBMPV_PATH=${MPV_KIT_LIBMPV_PATH:-/Users/35490/mpv_kit/bt/libmpv-2.dll}`:
- `dart test test/player_test.dart test/api_freeze_test.dart --reporter expanded`: all pass. The new group adds 4 tests, the existing player tests do not regress, and api_freeze needs no baseline edit because Player gains no public member.
- `dart analyze --fatal-infos`: No issues found (clean at HEAD).
- `git diff --stat main...HEAD -- packages` (or against the batch base): only `packages/mpv_kit/lib/src/player/player.dart` and `packages/mpv_kit/test/player_test.dart` changed. player.dart changes only add the hwdec-codecs entry and comment lines, with no reformatting of untouched lines (`dart format` was not run).
- `grep -c 'mpv #18255' lib/src/player/player.dart` >= 2 and `grep -c 'mpv #17626' lib/src/player/player.dart` >= 2 (both baselines 0).
</verification>

<success_criteria>
- By default, ffv1 sources no longer enter FFmpeg's Vulkan hwaccel. The rest of mpv's default hwdec codec list is unchanged and order-preserved, and an explicit user `hwdec-codecs` wins.
- Sources at least 7680 pixels wide play with `hdr-compute-peak=no` unless the user set it, through the existing global default. No redundant per-resolution mechanism is added, and the SUMMARY states why.
- Each default carries its mpv issue number in both the inline and the doc comment.
- 4 new real-libmpv tests. Test 1 was observed RED before the fix; Test 3 was observed RED under mutation.
- No public API change. Only 2 files changed.
</success_criteria>

<output>
Create `D:/mpv_kit/.planning/quick/261025-rkm-adjust-gpu-next-defaults-from-community-issues-without-publi/261025-rkm-SUMMARY.md` when done. It must record the hdr-compute-peak scope decision (behavior already provided by the global default; no runtime mechanism added; Player.wrap out of scope), the Test 1 RED observation, and the Test 3 mutation observation.
</output>

## Review revisions (2026-10-25, plan-checker pass; these are authoritative and supersede any conflicting text above)
- Before GREEN, print the runtime default of `hwdec-codecs` from
  bt/libmpv-2.dll (v0.41.0-689, older than the vendored tree) and compare it
  with the hard-coded list (vd_lavc.c:176 minus ffv1). If the local build lacks
  `prores_raw`/`apv`, Test 1 asserts only "contains no ffv1 and matches the
  vendored default minus ffv1" against the vendored list, not the local
  runtime default; record the comparison in the summary.
- State in the commit body and summary that this is a user-visible default
  change (ffv1 no longer hardware-decoded; override with
  `options: {'hwdec-codecs': ...}`).

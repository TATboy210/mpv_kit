---
status: resolved
trigger: "macOS-15 CI integration-test regression after FIFO ready queue (0e792c8)"
created: 2026-10-29
updated: 2026-10-29
resolved: 2026-10-29
fix_commit: 196cedc
note: "Session file lives in the phase dir because .planning/debug/ is user-owned (do not write there)."
---

# Debug: macOS black reference screenshot after FIFO ready queue

## Symptoms

<!-- DATA_START -->
- expected: native-verify `integration-test (macos-15, macos, libmpv-verify-macos-macos-15, libmpv.2.dylib)` passes, as on 11b728a (run 40828897026 green).
- actual: run 40884999133 (sha 9f2b78f, includes 0e792c8 FIFO ready queue) fails step "Real-plugin integration test", test "hwdec zero-copy probe on real samples" at example/integration_test/hwdec_zero_copy_test.dart:633 (`_expectReference`, called from :726).
- error: `TestFailure: black reference screenshot ... Expected: a value greater than or equal to <0.01> Actual: <0.006961805555555555>`; preceding lines: `HWDEC {"test":"hwdec_zero_copy","sample":"h264-8bit","api":"vulkan","requested":"no","hwdecCurrent":"no","outcome":"software","zeroCopy":false,"reason":"vulkan (gpu-next) on Apple Paravirtual device via MoltenVK"}` and `HWDEC-RUN {... "sample":"h264-8bit","api":"vulkan","requested":"no","firstFrameMs":157,"flutterFrame":"reference","playedToEnd":true,"hwdecStable":true,"frameDrops":32,"decoderDrops":0,"voDelayed":0,"renderErrors":0,"deviceLost":0}`. Full log: /tmp/gsd-bak/ci/native-verify-40884999133-failed.log.
- timeline: first seen on 9f2b78f (first push containing 0e792c8 FIFO + 6a712eb superseded counter + ade3eea power/hint + 824a69e adapter log). 11b728a green. Other 12 native-verify jobs and all flutter-plugin jobs green on 9f2b78f (incl. linux/windows real-plugin integration and sanitizers).
- repro: CI only (host is Windows, no macOS). Push to feat/mpv-master-upgrade triggers native-verify.
<!-- DATA_END -->

## Context

- FIFO change: packages/mpv_kit_video/src/video_renderer.{h,cc} — swap reported at publish; ready queue of two frames; AcquireFront hands out the older queued frame first and calls Interop::FrameReady (re-notify) from the compositor thread after releasing the lock; ring = quarantine + 4 (macOS: 2 + 4 = 6); alloc-failure fallback ring 5 newest-wins.
- macOS plugin: packages/mpv_kit_video/macos/Classes/MpvKitVideoPlugin.mm (copyPixelBuffer / textureFrameAvailable), metal_interop.mm.
- Distinct from known videotoolbox seek-point screenshot flake (Phase 16 W1: reference fine, a later seek point mismatches). Here the *reference* (hwdec=no software leg) is nearly black.
- Constraints: protected user files (.planning/config.json, .planning/state.json, .planning/tmp/, .planning/ui-reviews/, .planning/debug/, engine_repo_embedder.cc) never staged/modified; root pin `source /tmp/gsd-bak/root_pin.sh` before edits/commits; push only expected-green commits to origin feat/mpv-master-upgrade (authorized), at most one `gh run rerun --failed` for infra flakes; local commit a94e596 (CI evidence) not yet pushed.
- User-acceptable fallback: macOS-only newest-wins (queue depth 1) if a minimal root-cause fix is not possible.

## Current Focus

updated: 2026-10-29 (resolved: user chose A, fix 196cedc pushed, hosted macos-15 run green with absorbed flakes)
bug_class: Mandelbug/Heisenbug (non-deterministic on byte-identical code) -> SBFL skipped (flaky spectra)
hypothesis: "The black reference VO screenshot is a pre-existing, non-deterministic macos-15 CI screenshot-oracle failure (mpv gpu-next video_screenshot readback on MoltenVK / Apple Paravirtual device), independent of the FIFO ready queue."
test: "Same signature on pre-FIFO code? (native-verify run history on byte-identical code)"
result: CONFIRMED: run 40827789016 on c1cf4a1 (pre-FIFO, code byte-identical to green 11b728a) failed with `black reference screenshot ... Actual: 0.0000260416`. Pre-FIFO record of the macOS hwdec screenshot check: 4 red of 6 attempts.
local_state: "working tree (uncommitted): example/integration_test/macos_route_probe.dart, example/integration_test/hwdec_zero_copy_test.dart, example/test/macos_route_probe_test.dart. Local checks green: example unit tests 75/75, mpv_kit_video 25/25, flutter analyze --fatal-infos clean (example, mpv_kit_video), golden freeze OK, 12 native renderer tests rc=0 (build_ctl.bat built them; its superseded_test entry is stale, the file was deleted in 0e792c8). Renderer/plugin/golden files untouched."
next_action: "none (session resolved). Follow-up outside this session: keep watching macos-15 native-verify runs on later pushes (one green draw is not a rate); todo 2026-10-29-macos-route-test-single-capture-screenshot-oracle.md covers macos_route_test.dart."

## Evidence

- timestamp: 2026-10-29
  checked: failed CI log /tmp/gsd-bak/ci/native-verify-40884999133-failed.log (cleaned copy /tmp/gsd-bak/ci/fail40884999133.clean.txt)
  found: first test (real_plugin_test) passes on macos-15; hwdec_zero_copy_test fails in `_expectReference` on the first sample (h264-8bit, hwdec=no, vulkan gpu-next on Apple Paravirtual device via MoltenVK) with nonBlackRatio 0.006961805555555555 (=1604/230400 px, threshold 0.01). Same libmpv bundle (`@rpath/mpv.2.framework`, pinned v0.1.0-dev.3) as the green runs. `renderErrors:0, deviceLost:0, playedToEnd:true`.
  implication: renderer did not fail; the *screenshot image* (not the Flutter texture) was almost black.
- timestamp: 2026-10-29
  checked: what the failing assertion measures (example/integration_test/hwdec_zero_copy_test.dart `_screenshot`, `_expectReference`; macos_route_probe.dart routeBgr0Stats)
  found: the checked frames are `player.screenshot()` = mpv `screenshot-raw` via VOCTRL_SCREENSHOT -> vo_libmpv run_control_on_render_thread -> libmpv_screenshot -> vo_gpu_next video_screenshot (own FBO, pl_render_image from pl_queue, pl_tex_download). It never reads the plugin's ring images nor anything AcquireFront/FrameReady/ReportSwaps touches. Sample = lavfi testsrc2 (never black).
  implication: no code path from the FIFO queue (AcquireFront, queued_, re-notify, swap-at-publish) to the screenshot content; only timing changes.
- timestamp: 2026-10-29
  checked: `git diff 11b728a 9f2b78f` code files
  found: only packages/mpv_kit_video/src/video_renderer.{h,cc} (+Windows d3d11_interop/plugin, example/windows main.cpp, native tests) changed for macOS; the macOS plugin (.mm, metal_interop.mm) and vulkan_backend.cc are unchanged.
  implication: any FIFO effect on macOS is via renderer timing/ring size only.
- timestamp: 2026-10-29
  checked: all native-verify runs on feat/mpv-master-upgrade since the hwdec macOS check exists (gh run list) vs code identity (`git diff --stat` over packages example native tools .github)
  found: ad5c54b G(40798831729); 15f61ff R twice (VT screenshot mismatch t=1.33 diff 54.27; rerun t=2.67 diff 129.07); f644220 R (VT t=0 diff 10.04); c1cf4a1 R (40827789016); 11b728a G (40828897026). f644220, c1cf4a1 and 11b728a have byte-identical packages/ example/ native/ tools/ .github/ (only README/.planning/docs differ). 15f61ff is docs-only vs ad5c54b. So on pre-FIFO code (this check first ran on macOS at ad5c54b; all jobs on the same macos-15-arm64 image 20260907.0337.1, a fresh hosted VM per run): 2 green / 4 red attempts (~67% red); with the FIFO run 9f2b78f: 2 green / 5 red.
  implication: the macOS hwdec screenshot check is non-deterministic on identical code; the 11b728a green is one lucky draw, not a baseline.
- timestamp: 2026-10-29
  checked: failure log of run 40827789016 (c1cf4a1, PRE-FIFO), fetched with `gh run view --log-failed --job 123297018114` into /tmp/gsd-dbg/c1cf/log.txt
  found: `TestFailure ... black reference screenshot: HWDEC-RUN ... "sample":"hevc-8bit","requested":"no" ... Expected: a value greater than or equal to <0.01> Actual: <0.00002604166666666667>` (6 non-black px). IDENTICAL signature to the post-FIFO failure, on the second sample's software reference leg; first sample h264-8bit passed both legs in that run.
  implication: FIFO is not the cause (a pre-FIFO run reproduces the exact failure). Decisive.
- timestamp: 2026-10-29
  checked: macos-route.yml failure log /tmp/gsd-bak/ci/macos-route-fail.log (2026-10-28 06:55, well before Phase 16 and FIFO)
  found: `ROUTE-HWDEC-REF {"sample":"hevc-8bit","hwdecCurrent":"no","screenshotPath":"vo","nonBlackRatio":0.0,"valid":false,"textureVisibility":"texture-visible"}` then the VT leg `"screenshot":"mismatch","screenshotDiff":125.9009 ... "flutterFrame":"match"`.
  implication: black VO screenshot of the software reference on an even older tree, while the Flutter texture channel still matched the reference: the display is fine, the VO screenshot oracle is what goes black.
- timestamp: 2026-10-29
  checked: shape of the bad screenshots across runs
  found: bad captures are isolated, not session-wide: in run 40800969371 attempt 1 t=0 match 1.32, t=1.33 mismatch 54.27, t=2.67 match 1.76 (same sample, same paused file); attempt 2 t=0,1.33 match, t=2.67 mismatch 129.07. Magnitudes vary continuously (nonBlack 0, 6 px, 1604 px; diff 10 / 54 / 129): consistent with a partially completed readback (random completeness), not with one fixed bad state.
  implication: the failure is transient per screenshot (a re-capture of the same paused frame is expected to be good) -> bounded re-capture is a valid mitigation and the retry count can be made visible.
- timestamp: 2026-10-29
  checked: runner identity of the macOS jobs (gh api actions/jobs): 123204396525 G, 123232543132 R, 123297018114 R, 123300631383 G, 123490766315 R
  found: every job is a GitHub-hosted `macos-15` VM ("GitHub Actions 1000002xxx", a different ephemeral VM per run) on the same image macos-15-arm64 20260907.0337.1, provisioner 20260828.587. Green and red runs share the image.
  implication: no image change explains the flake; per-VM / host-load variance on the Apple Paravirtual device is the remaining environmental factor (consistent with `frameDrops` 14..35 and the log line "Failed to foreground app; open returned 1" in all macOS runs).
- timestamp: 2026-10-29
  checked: external context (web): the Apple Paravirtual device is a known-unreliable Metal target in macOS VMs (godotengine/godot#124859 black viewport and fence timeouts; #101773 missing Metal features)
  found: not MoltenVK-specific, only corroborates that readback/render anomalies on this device are plausible.
  implication: supports the environmental part of the AND-gate; not proof.
- timestamp: 2026-10-29
  checked: local verification of the prepared fix (Windows host)
  found: example/test/macos_route_probe_test.dart 43/43 (12 new); example `flutter test` 75/75; packages/mpv_kit_video `flutter test` 25/25; `flutter analyze --fatal-infos` clean in example and mpv_kit_video; 6/6 manual mutants of routeStableCapture killed; revert -> new tests fail to compile, reapply -> 43/43; golden-freeze-14-rcc.sha256 OK; 12 native renderer tests rc=0 (renderer sources untouched).
  implication: the helper behaves as specified; the macOS effect is only observable in CI.
- timestamp: 2026-10-29
  checked: user decision (via the orchestrator): A, adopt the stable-capture hardening without threshold changes, commit the three example files, push with a94e596, observe macOS CI; record a todo for macos_route_test.dart. Re-ran before committing on the Windows host: 12 native renderer tests by hand (rc=0 each, the stale build_ctl/run_all lists bypassed: superseded_test is gone, swap_test added), golden-freeze-14-rcc.sha256 OK (5/5), example flutter analyze --fatal-infos clean + flutter test 75/75, mpv_kit_video flutter analyze clean + flutter test 25/25.
  found: commit 196cedc (3 example files only, explicit-path staging); push 9f2b78f..196cedc fast-forward to origin feat/mpv-master-upgrade (a94e596 + 196cedc, no force, no tags).
  implication: the fix is on the branch exactly as verified locally.
- timestamp: 2026-10-29
  checked: hosted CI for 196cedc via the 120 s gate (CI_GATE_EVIDENCE=.planning/phases/14-windows-native-d3d11-backend/evidence/ci-runs-14-fifo.txt): native-verify 40896998200, flutter-plugin 40896998202, macos-route 40896998218; macOS job log /tmp/gsd-bak/ci/native-verify-40896998200-macos-int.log
  found: all three workflows success (native-verify 13/13 jobs including integration-test (macos-15, macos, ...)); no rerun used. The macOS log carries 3 `HWDEC-NOTE screenshot at ...` lines, all on the first sample h264-8bit hwdec=no (the exact leg that failed in 40884999133): t=1.3333 capture 2/5 differs (mean abs diff 111.4252), capture 3/5 differs (111.4252), t=2.6667 capture 2/5 differs (60.0941); each followed by an agreeing capture. All software legs ended `reference`, all videotoolbox legs `match` (diff 0.0 .. 1.76), renderErrors 0, deviceLost 0 on all 12 hwdec runs.
  implication: positive proof from the falsification test: isolated bad captures of the same paused frame (diff 60 and 111 between two captures) happened again on the same leg, were discarded, and the run was green. The mechanism (transient per-capture bad readback) is confirmed on a second independent run; the oracle no longer converts it into a red check. It does not prove the failure rate is zero (one green draw had about 30% chance on the old 5-of-7 red record).

## Eliminated

- hypothesis: "FIFO ready queue (0e792c8) causes the black reference screenshot"
  evidence: identical failure signature (black reference screenshot, <0.01) on pre-FIFO c1cf4a1 run 40827789016; screenshot path does not touch the ring/queue; pre-FIFO baseline on this check is ~67% red (4 of 6 attempts).
  timestamp: 2026-10-29
- hypothesis: "swap-at-publish / mpv backpressure change starves the screenshot dispatch on the render thread"
  evidence: RenderLoop wake predicate (update_pending_ ...) and mpv_render_context_update call are unchanged for the screenshot dispatch; render errors 0; test reaches playedToEnd; pre-FIFO runs fail the same way.
  timestamp: 2026-10-29

## Resolution

status_note: "resolved: user decision A (oracle evidence hardened, thresholds untouched), fix 196cedc pushed, hosted macos-15 native-verify 40896998200 green with 3 absorbed flakes on the failing leg."

reasoning_checkpoint:
  hypothesis: "The black reference screenshot is a transient, per-capture failure of mpv's `screenshot-raw` readback of a paused frame on the macos-15 hosted runner (Apple Paravirtual device behind MoltenVK). It is independent of the FIFO ready queue; the test's single-capture oracle turns it into a red check roughly 70% of runs."
  confirming_evidence:
    - "Run 40827789016 on c1cf4a1 (pre-FIFO) fails with the identical assertion text and magnitude class (`Actual: 0.0000260416`), on the software reference leg of hevc-8bit; run 40828897026 on 11b728a, whose packages/ example/ native/ tools/ .github/ are byte-identical to c1cf4a1, passes 11 minutes later."
    - "macos-route.yml (2026-10-28, older tree) printed `ROUTE-HWDEC-REF ... nonBlackRatio 0.0 valid false` and a videotoolbox VO screenshot diff 125.9 while `flutterFrame` matched twice: the display is right, the VO screenshot is black."
    - "Bad captures are isolated within one paused sample (run 40800969371 a1: t=0 diff 1.32, t=1.33 diff 54.27, t=2.67 diff 1.76; a2: only t=2.67 bad) and vary continuously (nonBlack 0 / 0.00003 / 0.007; diff 10 / 54 / 129): a partly completed readback, not one fixed state."
    - "Healthy captures of the same frame are bit-identical (`screenshotDiff 0.0` between two software runs), so disagreement between two captures is a sharp, content-independent detector."
    - "Pre-FIFO record of this check: ad5c54b G, 15f61ff R+R(rerun), f644220 R, c1cf4a1 R, 11b728a G (4 red of 6 attempts, ~67%); FIFO run 9f2b78f R is inside that distribution."
  falsification_test: "After the hardening, a macos-15 native-verify run is red with every capture of a bad frame black/wrong and agreeing (=> persistent state, hypothesis wrong), or the FIFO-free baseline stays red at the old rate. Positive proof: a green run that prints `HWDEC-NOTE screenshot at ...: capture n/5 ... taking another` (a flake was absorbed)."
  fix_rationale: "The assertion stays (non-black, mean diff <= 8.0, thresholds untouched); only the evidence quality is raised: a capture counts when the next capture of the same paused frame agrees (<= 1.0 mean abs diff) and is not black. A real black/green/wrong picture is identical on every capture and still fails; discarded captures are printed."
  blind_spots: "The GPU/MoltenVK-level mechanism of the partial readback is NOT identified (no macOS host, no repro). A bad window longer than ~1.2 s (5 captures, 300 ms apart) is not absorbed. The f644220 t=0 `diff 10.04 + flutterFrame mismatch` case is a wrong-frame, not black/partial, and is not absorbed. Whether FIFO shifts the flake probability cannot be told from 6 pre-FIFO attempts. An intermittent real zero-copy defect would also be absorbed (tradeoff)."
  candidate_causes:
    - "environment: Apple Paravirtual GPU + MoltenVK on a loaded macOS VM returns an incomplete texture readback"
    - "code: mpv gpu-next video_screenshot (own FBO + pl_tex_download) racing with / depending on libplacebo/MoltenVK completion semantics; or the state of p->queue after seek/idle (SkipFrame does not push frames)"
    - "config: test oracle timing (300 ms settle, single capture) and thresholds"
    - "data: none (testsrc2 is never black)"
  and_gate: "yes, plausibly two conditions at once: (environment) paravirtual GPU readback unreliability AND (config) a single-capture oracle. The fix removes the second; the first is outside the repo."

root_cause: "Not the FIFO ready queue. The macOS native-verify hwdec screenshot check uses a single mpv `screenshot-raw` capture as evidence, and on the macos-15 paravirtual GPU that capture is intermittently black or partly drawn (reference and videotoolbox legs alike, pre- and post-FIFO). Mechanism below the oracle (MoltenVK/paravirtual readback) is unproven."
fix: "example/integration_test/macos_route_probe.dart: new routeStableCapture (+ routeCaptureMaxMeanAbsDiff = 1.0); example/integration_test/hwdec_zero_copy_test.dart: frame checks use it and print HWDEC-NOTE for discarded captures; example/test/macos_route_probe_test.dart: 12 tests (scripted captures). No product code, no thresholds, no goldens, no public API changed."
verification:
  target_test: { result: pass, note: "example/test/macos_route_probe_test.dart 43/43 (12 new); real macOS behaviour is only observable in CI" }
  mutation_check: { result: pass, mutant_killed: "6/6 manual mutants of routeStableCapture killed (drop black check, accept anything, no-op, never advance previous, unavailable-second returns null, tolerance 1000); Stryker n/a (Dart)" }
  no_op_deletion: { result: pass, deletion_justified_by_rca: false, note: "adds logic only; assertions and thresholds unchanged; flagged to the user as an oracle-strength change" }
  adjacent_tests: { result: pass, suites_run: ["example flutter test 75/75", "packages/mpv_kit_video flutter test 25/25", "flutter analyze --fatal-infos example + mpv_kit_video clean", "golden-freeze-14-rcc.sha256 OK"] }
  revert_and_reconfirm: { result: pass, bug_returned_on_revert: true, fixed_on_reapply: true, note: "unit level only (HEAD version: routeStableCapture missing, new tests fail to compile; reapplied: 43/43). The CI flake itself is not reproducible on the Windows host; confirmation needs several macos-15 runs." }
  hosted_ci: { result: pass, run: "native-verify 40896998200 (sha 196cedc), flutter-plugin 40896998202, macos-route 40896998218", note: "3 HWDEC-NOTE lines on the h264-8bit hwdec=no leg: flake absorbed. One green run is not a rate; sampling continues on later pushes." }
  guardrail_verdict: accepted_by_user (decision A, 2026-10-29: oracle-strength change adopted, no threshold change)

postmortem_prevention:
  why_not_caught: "none (no gate existed for this class): the hwdec screenshot check had only one capture per paused frame, and no gate measured the per-capture reliability of `screenshot-raw` on the macos-15 paravirtual GPU, so a ~70% red rate on identical code was misread as a regression of the next change."
  guard: "routeStableCapture (example/integration_test/macos_route_probe.dart) with 12 unit tests (example/test/macos_route_probe_test.dart), HWDEC-NOTE lines in the CI log to make absorbed flakes visible, and todo 2026-10-29-macos-route-test-single-capture-screenshot-oracle.md for the sibling oracle in macos_route_test.dart."
  lesson: "Before attributing a red CI check to the latest change, look up the check's pass rate on byte-identical code (git diff --stat over packages/ example/ native/ tools/ .github/ between runs); a single-sample oracle on a virtualised GPU needs agreement between captures."

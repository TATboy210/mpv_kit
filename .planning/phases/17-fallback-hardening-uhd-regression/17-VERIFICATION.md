---
phase: 17-fallback-hardening-uhd-regression
verified: 2026-10-30T13:39:44Z
status: passed
score: 4/4 roadmap success criteria (SC1 and SC4 verified only under the user-approved wording of 1084a7b); 24/24 plan must-have truths (23 verified, 1 accepted override for the unconditional 17-04 d3d11 4K zero-drop truth)
covered_files:
  - .github/workflows/native-verify.yml
  - .planning/phases/17-fallback-hardening-uhd-regression/17-01-PLAN.md
  - .planning/phases/17-fallback-hardening-uhd-regression/17-01-SUMMARY.md
  - .planning/phases/17-fallback-hardening-uhd-regression/17-02-PLAN.md
  - .planning/phases/17-fallback-hardening-uhd-regression/17-02-SUMMARY.md
  - .planning/phases/17-fallback-hardening-uhd-regression/17-03-PLAN.md
  - .planning/phases/17-fallback-hardening-uhd-regression/17-03-SUMMARY.md
  - .planning/phases/17-fallback-hardening-uhd-regression/17-04-PLAN.md
  - .planning/phases/17-fallback-hardening-uhd-regression/17-04-SUMMARY.md
  - .planning/phases/17-fallback-hardening-uhd-regression/17-05-PLAN.md
  - .planning/phases/17-fallback-hardening-uhd-regression/17-05-SUMMARY.md
  - .planning/phases/17-fallback-hardening-uhd-regression/evidence/ci-runs.txt
  - .planning/phases/17-fallback-hardening-uhd-regression/evidence/decisions.txt
  - .planning/phases/17-fallback-hardening-uhd-regression/evidence/final-audit.txt
  - .planning/phases/17-fallback-hardening-uhd-regression/evidence/rtx-runs.txt
  - .planning/phases/17-fallback-hardening-uhd-regression/evidence/rtx-verdicts.txt
  - .planning/phases/17-fallback-hardening-uhd-regression/evidence/unverified.txt
  - docs/perf/fallback-uhd-regression.md
  - example/integration_test/backend_soak_test.dart
  - example/integration_test/d3d11_device_lost_test.dart
  - example/integration_test/hwdec_probe.dart
  - example/integration_test/hwdec_zero_copy_test.dart
  - example/integration_test/soak_memory.dart
  - example/integration_test/texture_probe_test.dart
  - example/integration_test/uhd_endurance_test.dart
  - example/test/hwdec_probe_test.dart
  - example/test/soak_memory_test.dart
  - native/tests/golden/fault.txt
  - native/tests/meson.build
  - native/tests/video_renderer_fault_test.cc
  - native/tests/video_renderer_golden_vk.cc
  - packages/mpv_kit_video/lib/src/video_controller.dart
  - packages/mpv_kit_video/test/controller_channel_test.dart
  - tools/backend_matrix.sh
  - tools/require_hwdec_negative.sh
covered_digest: "v4:sha256:cabd3af615daafcd826f7c1a4de9333749241b9054ce3aa336a874527386c71e"
behavior_unverified: 0
overrides_applied: 1
overrides:
  - must_have: "17-04 truth 5: RTX 4060 上 D3D11 与 Vulkan 后端各自真正渲染的 4K（3840x2160，1800 s，强制 api）零丢帧、无积压 (unconditional)"
    reason: "Forced d3d11 lavfi 4K 1800 s failed the zero-drop gate twice (attempt 1: 3 VO drops, attempt 2: 5 VO drops) with the example window covered by WindowsTerminal/msedge for most of each run; supplementary attempt 3 (same product sha 9ae347f, example in front 1777/1779 sampler rows, user hands-off) read 0 drops. The user approved SC4 and VER-04 wording that makes zero drops conditional on the example window being in front and the session hands-off, and records occluded drops as known behavior that is not a zero-drop proof. Attempts 1 and 2 remain recorded failures. The unconditional plan truth is NOT met."
    accepted_by: "user (decision=phase17-close choice=approve, evidence/decisions.txt; proposals VER-04-wording and SC4-wording status=approved in evidence/final-audit.txt)"
    accepted_at: "2026-10-30T13:01:05Z"
gaps: []
deferred:
  - truth: "UHD-02 8K 30 minutes and COMP-03 compositor latency budget parameterisation"
    addressed_in: "later milestone work (ROADMAP Phase 17 '验证分层' line states both remain deferred and are not accepted in this phase)"
    evidence: "ROADMAP.md Phase 17: '8K 30 分钟（UHD-02）与合成延迟预算参数化（COMP-03）仍延后，不在本阶段验收'; evidence/unverified.txt rows 状态=延后"
coincidental_reliance_items:
  - truth: "SC4: 100-round resize/dispose soak on RTX 4060 d3d11/vulkan/software with a flat dedicated-VRAM curve"
    reason: undeclared-precondition
    harden: "The verdict reads as 'per-round target allocation does not leak VRAM', but nothing evidences that the recreated controllers allocated a ring on the RTX: SOAK-CHECKPOINT resizeEvents is 1 of 101 controllers at round 100 in all three RTX soaks (hosted ubuntu: 48 of 101 on the final gate), lastControllerFrame=not-presented, and each controller is only sized right before it is disposed (D-05 design). resizeEvents is a race indicator (event dropped after Dart-side dispose), so this neither proves nor disproves allocation. Declare in the soak which work a round must do on real GPUs, or record a native per-round allocation count, before treating the VRAM verdict as covering ring churn."
---

# Phase 17: Fallback Hardening & UHD Regression Verification Report

**Phase Goal:** auto 回退的每一级都被强制演练过并留下带原因的事件；每个后端都在 CI 与 RTX 4060 上通过真实插件、硬解与 UHD 长时门禁。
**Verified:** 2026-10-30T13:39:44Z, branch feat/mpv-master-upgrade, HEAD 0255e49
**Status:** passed. SC1 and SC4 hold only in their user-approved wording (1084a7b). Four caveats are deliberately not upgraded to proven, see "Not proven (explicit)". One override, one coincidental-reliance advisory, residual risks listed.
**Re-verification:** Refresh of the 13:35Z report (status passed, no gaps) after docs-only commit 0255e49. That commit touches only docs/perf/fallback-uhd-regression.md, 17-05-SUMMARY.md, evidence/final-audit.txt and evidence/unverified.txt. I re-checked those files; every other finding is carried over unchanged. Product code still equals 9ae347f (`git diff 9ae347f HEAD -- packages example/lib example/integration_test native` is empty), and golden-freeze-17 is still 5/5 OK.

## Method

I checked SUMMARY claims against primary evidence and code:

- I re-ran the read-only audits myself: `shasum -a 256 -c golden-freeze-17.sha256` (5/5 OK), `constants_audit.sh` (`CONSTANTS ok`), and the `git diff --quiet` checks for api_freeze, native_unchanged and rtx_product_equal (all empty). The ci_gate copy is isomorphic to the Phase 13 gate. The authorization commit 24a10fe is an ancestor of the first gated sha 468f509.
- I downloaded and grepped the final native-verify log (run 41056455257) and the flutter-plugin log (41056455255).
- I checked the conclusions of runs 41056455257, 41056455255, 41056455344, 41060074045, 41060074053 and 41060073995 with `gh run view`. All are `success`, on c4a7158 (the final gate) and bf153c2. All 13 native-verify jobs and all 3 flutter-plugin jobs succeeded.
- I grepped the raw RTX logs and CSVs: BENCH lines, HWDEC-REQUIRE lines, and the foreground column counted per run. I joined the soak checkpoints to the VRAM CSV myself.
- I read the code of `tools/backend_matrix.sh`, `require_hwdec_negative.sh`, `texture_probe_test.dart`, `backend_soak_test.dart`, `soak_memory.dart`, `hwdec_probe.dart`, `hwdec_zero_copy_test.dart`, `uhd_endurance_test.dart`, `d3d11_device_lost_test.dart`, the `video_controller.dart` softwareFallback change, `video_renderer_fault_test.cc` with `golden/fault.txt`, and the `native-verify.yml` diff.

Nothing was built or run beyond grep/git/gh and the read-only audit scripts.

## Goal Achievement

### Observable Truths (ROADMAP success criteria, approved wording)

| # | Criterion | Status | Evidence |
|---|---|---|---|
| SC1 | Fake-backend fault injection: creation failures move along the auto chain with a reason trail; landing on software records the full chain and emits softwareFallback; runtime faults reach determinate states on the current backend: one deviceLost then stop (a rebuild while still failing moves to the next candidate), gpuTimeout doubling with a 5 s cap and then recovered, allocation failure retried at ring 5 then renderError with an immediate retry on resize; a running controller never switches backend (RBE-F1) | VERIFIED (approved wording only) | `golden/fault.txt` has 7 scenarios. Each SC1 clause maps to a pinned trace line: `create-device-lost-next-api` (vulkan wins with the d3d11 trail), `create-every-gpu-candidate-fails` (software reason with 4 trails in chain order), `runtime-device-lost-then-recreate` (one `device_lost`, then only `render skip`; the rebuild gives `vulkan (gpu-next) ... d3d11/gpu-next unavailable`, d3d11 device-inits=2), `runtime-timeout-storm` (gpu_timeout on failures 1, 2 and 4, `backoffs ok 100,...,3200,5000`, recovered, draws 8), and three alloc scenarios (`ring=8` fail, then `ring=5` fail, `render_error ... (injected, ring 5)`, `retry-after-resize ok`, same backend after the rebuild). The timing checks are real assertions: lower bounds plus the 5000+slack cap, `backoffs measured` on a miss. The test links the real `renderer` static library (meson.build). Final gate 41056455257: `video_renderer_fault_test OK` on linux x64, linux arm64, macos-15, windows x64, windows arm64 and sanitizers; `GOLDEN ok scenarios=7` 6 times. Local MSVC log: `fault_test rc=0 GOLDEN ok scenarios=7`, `ALL rc=0`. Real plugin: the final-gate windows job prints `D3D11-INJECT {"mode":"create-fail",... "softwareFallback":"rendering in software: software (sw) on cpu; vulkan/gpu-next unavailable: vkCreateInstance failed; d3d11/gpu-next unavailable: ..."}`. The delivery fix is `video_controller.dart` (`_pendingFallback` plus broadcast `onListen`, private state only). The library has no internal `events` listener (grep). The RED log was captured before the fix, and the channel tests passed in flutter-video-coverage. Limit: the original SC1 ("渲染切到 auto 链的下一候选" on runtime faults) is not met. Live switch is not implemented (unverified.txt). |
| SC2 | Per platform, `MPV_KIT_VIDEO_API` forces every available backend through the real-plugin integration test (Windows d3d11/vulkan/software, Linux vulkan/opengl/software, macOS vulkan/software), hosted `hwdec=no` plus non-black probe all green; the D3D-02 ANGLE gate is still green in the matrix | VERIFIED | `backend_matrix.sh` cell table matches SC2 exactly. Every cell runs (no `-e`). A cell is ok only when the exit code is 0 and its `PROBE {"api":"<api>"` or `PROBE-UNAVAILABLE` line is present. The probe asserts the reason's first token equals the forced api. Unavailable mode requires `render_init`, no head, a non-`excluded` own failure, and every other candidate `excluded`. Final gate 41056455257: `BACKEND-MATRIX-SUMMARY platform=linux cells=3 ok=3`, `windows cells=3 ok=3` (vulkan `expect:"unavailable"` ok), `macos cells=2 ok=2`. Raw per-cell PROBE lines with nonBlackRatio 1.0/1.0 are in `matrix.txt` (run 40982220052). The real Windows Vulkan cell runs on the RTX: `rtx-verdicts.txt` `probe run=matrix-rtx-vulkan ... expect_match=yes nonBlack=1.0/1.0 exit=0`, plus the d3d11 and software cells. ANGLE: native-verify windows x64 and arm64 print `ANGLE-FREE prefix/bin/libmpv-2.dll`; flutter-plugin 41056455255 (same sha c4a7158) prints `ANGLE-FREE ...plugins\mpv_kit_video\Debug\mpv_kit_video_plugin.dll` and the runner copy; `CHECK-MATRIX ok`. The new workflow steps have no `continue-on-error` (the two existing ones date from a9b3985, 2026-10-14). The hosted Windows Vulkan cell is an asserted absence, not a render pass. |
| SC3 | On the RTX 4060 the hwdec layer runs under `MPV_KIT_REQUIRE_HWDEC`: no usable hwdec, or `hwdec-current` not the expected zero-copy value, fails loudly instead of skipping | VERIFIED | `hwdec_probe.dart` `hwdecRequirementError` accepts only keys of `hwdecZeroCopyFormats` (d3d11va, vaapi, vulkan, videotoolbox, drm): `-copy`, `no`, `auto*` and typos are errors. `checkHwdecRequirement` passes only on `outcome==zeroCopy && hwdecCurrent==required`. The zero-copy test calls `fail(invalid)` before playback and judges first-frame and end reports. RTX positive `rtx-hwdec-require-d3d11va.log`: 8 `"result":"ok"`, 0 fail, all 4 samples (incl. hevc-10bit-2160p) `d3d11 d3d11va zero-copy`, `All tests passed!`. RTX negative: `Some tests failed.` and `REQUIRE-HWDEC-NEGATIVE ok required=d3d11va api=software exit=1`. Hosted WARP negative leg on the final gate: `REQUIRE-HWDEC-NEGATIVE ok required=d3d11va api=d3d11 exit=1`. The script also requires `HWDEC-IDENTITY` (playback reached) and no ok line. |
| SC4 | RTX 4060 D3D11 and Vulkan each 4K 30 min zero drops and no backlog, *provided the example window is in front and the session is hands-off*; occluded runs may drop a few VO frames, recorded as known behavior, not a zero-drop proof; 100-round soak on RTX d3d11/vulkan/software passes with a flat dedicated-VRAM curve; the opengl soak passes on ubuntu (llvmpipe, *single glibc malloc arena*) with flat process memory; real Linux VRAM unverified | VERIFIED (approved wording only; caveats below) | Raw logs: `rtx-uhd4k-1800-vulkan.log` frameDropCountFinal 0, decoder 0, voDelayedMax 0, renderErrors 0, deviceLost false, `All tests passed!`, example foreground 1773/1775 rows. `rtx-uhd4k-1800-d3d11-a3.log` 0/0/0, `All tests passed!`, foreground 1777/1779 rows (counted from the CSV). The test asserts `frameDrops == 0`, `decoderDrops == 0`, and avg vo-delayed < 1. Attempts 1 and 2 failed: `Expected: <0> Actual: <3>` and `Actual: <5>`, with the example in front for only 592/1775 and 472/1775 rows. HEVC Main10 d3d11 under the d3d11va guard: 0/0/0, `hwdecCurrentFinal d3d11va`, 2 HWDEC-REQUIRE ok. RTX soaks: rounds 100, 39.2/38.4/30.9 s, errors 0, deviceLost 0, idleSoak 0, apiMismatches 0, process VRAM verdict flat. My checkpoint join of the adapter column is also flat inside each soak (d3d11 1637 to 1654 MiB, vulkan 1672 to 1684 after r10, software 1627 to 1633). Ubuntu opengl soak on the final gate: `SOAK ... "rounds":100 ... "rssMiB":[660.9,...,854.3],"rssVerdict":"flat","rssLateMiB":4.4`; the step env shows `MALLOC_ARENA_MAX: 1`. The rule file `soak_memory.dart` has exactly one commit (2296c9a, together with its 13 unit tests); rule and thresholds were never changed. Linux VRAM is listed 未验证. |

**Score:** 4/4 SC. `behavior_unverified: 0`: every behavior-dependent truth (fallback chain, event cadence and backoff, device-lost stop, softwareFallback delivery, guard failure, soak and endurance gates) has a passing test run on CI or the RTX, not just symbol presence.

### Not proven (explicit, as instructed)

These four items stay as written. None is upgraded to proven:

1. **d3d11 lavfi 4K under occlusion.** Attempts 1 and 2 FAILED, with 3 and 5 VO drops. The example window was covered for most of each run (foreground 592/1775 and 472/1775 rows). Attempt 3 PASSED with the window in front (1777/1779) and the user hands-off. "Hands-off" is the user's statement, not a measurement. Foreground is only a proxy for "not occluded". This is one pass against two fails, and occlusion was never toggled within a run, so the occlusion-or-focus cause is attributed, not proven. The approved VER-04/SC4 wording makes the foreground condition explicit. Vulkan was never run occluded, so whether it also drops when covered is unknown.
2. **The ubuntu opengl soak is measured with `MALLOC_ARENA_MAX=1`** (b34a402). The arena setting was added after red runs were seen. With the default allocator the same code was red in 6 of 16 probe-free soaks (debug/ubuntu-soak-late-rss-growth.md: glibc arena retention, glibc in-use flat at 465 to 520 MiB). Under one arena, a deliberate 0.9 MiB-per-round leak was missed in 1 of 4 soaks. The rule and its thresholds are unchanged, but the measurement environment was chosen after the data was seen. The user accepted this through the SC4 wording.
3. **Real Linux GPU VRAM is unverified.** Only llvmpipe RSS exists.
4. **`lastControllerFrame=not-presented`** in every soak: RTX d3d11, vulkan and software, and every ubuntu run. It is recorded and never asserted. The likely explanation is the harness design, but that is not shown. Related (new in this verification): on the RTX, `resizeEvents` is 1 of 101 in all three soaks. So there is no evidence that the 100 recreated controllers ever allocated a target ring there (see coincidental_reliance_items).

### Plan must-haves (17-01..17-05)

| Plan | Truth (short) | Status | Evidence / note |
|---|---|---|---|
| 17-01 | Authorization and 4 decisions recorded before the first push | VERIFIED | `push-authorization.txt` (ci_mode=live, head_at_grant=5c22a6d) and `decisions.txt`; `git merge-base --is-ancestor 24a10fe 468f509` true |
| 17-01 | chain_precondition matches 14-11 | VERIFIED | `d3d11_interop.cpp:25` `{"vulkan", "d3d11"}`, switch.txt `decision=keep`, decisions.txt `kWindowsApiOrder=vulkan,d3d11 switch_decision=keep` |
| 17-01 | fault golden with 7 scenarios on 5 platforms + sanitizers + MSVC | VERIFIED | see SC1 |
| 17-01 | no product code change; constants_audit `CONSTANTS ok` | VERIFIED (late) | It was red during 17-01 (Phase 12 pins drifted by 0e792c8). Repinned by quick 261030-3pc (ba9af05, audit tool only). I re-ran it: `CONSTANTS ok`. `packages/` was unchanged during 17-01. |
| 17-01 | vk-flake measure-split, vk.txt byte-identical, timing-info per run, new manifest differs in one line | VERIFIED | `diff` of the 14-rcc and 17 manifests: only the golden_vk.cc line differs; 5/5 sha OK; macOS timing-info on 10 gated runs, wait 1000..1113 ms, backoff 103..169 ms, no mismatch (flake-timing.txt). "No mismatch" is not elimination. |
| 17-02 | Forced matrix on all three platforms | VERIFIED | SC2 |
| 17-02 | Hosted Windows vulkan cell asserted unavailable | VERIFIED | matrix.txt `PROBE-UNAVAILABLE {"api":"vulkan","reason":"vulkan/gpu-next unavailable: vkCreateInstance failed; ..."}` |
| 17-02 | softwareFallback delivered once to the first listener; real-plugin create-fail asserted | VERIFIED | SC1; `d3d11_device_lost_test.dart` asserts `message == 'rendering in software: $reason'` |
| 17-02 | MPV_KIT_REQUIRE_HWDEC guard + hosted negative leg | VERIFIED | SC3 |
| 17-02 | ANGLE gate green in the same CI run | VERIFIED | SC2 |
| 17-03 | Memory rule pre-registered with unit tests | VERIFIED | single commit 2296c9a (rule, 13 tests, soak, CI step) |
| 17-03 | Platform-independent 100-round soak, fixed rounds, forced api asserted | VERIFIED | `_soakRounds = 100` const; asserts rounds, >= 30 s, deviceLost 0, renderErrors < 10, idleSoak 0, apiMismatches 0, HWDEC software, RSS flat when `MPV_KIT_SOAK_MEMORY=rss` |
| 17-03 | Hosted ubuntu opengl soak flat | VERIFIED (with caveat 2) | final gate SOAK line; flaky without `MALLOC_ARENA_MAX=1` |
| 17-03 | RTX session tools gated, never-overwrite, ledger | VERIFIED | `rtx_run.sh` line 225 refuses to run on a failed gate; dryrun.txt; ledger rtx-runs.txt (15 lines) |
| 17-03 | Inputs traceable | VERIFIED | rtx-prep.txt (release run 40812562348, samples run, expect_reason_*), `native_equal=yes` |
| 17-04 | Session only after user confirmation; gate before every run | VERIFIED | rtx-session.txt `user_reply=start confirmed_at=07:56:34Z`, session gate pass; gating is enforced in code; per-run gate lines are stdout only (not persisted) |
| 17-04 | 3 forced probes with verbatim reason | VERIFIED | rtx-verdicts.txt probe lines expect_match=yes |
| 17-04 | Guard positive 8 ok, negative loud fail | VERIFIED | SC3 |
| 17-04 | 3 soaks pass with flat VRAM | VERIFIED (coincidental-reliance advisory) | SC4; the instrument caveat is below |
| 17-04 | d3d11 and Vulkan 4K 1800 s zero drops (unconditional) | PASSED (override) | Not met unconditionally (2 of 3 d3d11 attempts failed). Accepted under the approved conditional wording; see overrides |
| 17-05 | Perf doc tiered | VERIFIED | `## Verification tiers` separates hosted, RTX and unverified; no AMD/Intel claim; three sentences are stale (Residual risks 7) |
| 17-05 | Final full CI gate reproduces key lines | VERIFIED | run 41056455257/255/344 success, lines re-grepped by me |
| 17-05 | Closing audits all ok | VERIFIED | re-ran golden, constants, api_freeze, enum_line (1), native_unchanged, rtx_product_equal; PATCH-DRIFT OK and CHECK-MATRIX ok in the final log |
| 17-05 | Mapping, proposals, human check recorded; executor does not edit ROADMAP/REQUIREMENTS | VERIFIED (letter deviated) | `decision=phase17-close choice=approve` recorded verbatim. The executor did edit ROADMAP/REQUIREMENTS in 1084a7b, delegated by the orchestrator after the user's approval. I checked programmatically that all four approved texts appear verbatim in ROADMAP.md / REQUIREMENTS.md, so no unapproved wording was introduced. |

### Prohibitions (judgment tier; all human-resolved at the phase-close check, none silently passed)

- **17-01** (no golden edited to match output; frozen harness and goldens untouched; no live switch): honored. `git diff 5c22a6d HEAD` is empty for renderer_harness.h, golden_sw.cc, sw.txt and vk.txt. golden_vk.cc changed only under explicit consent. No live switch exists.
- **17-02** (no unavailable cell counted as pass; no continue-on-error or skip; no public API): honored. The api_freeze diff is empty and the enum line appears once.
- **17-03** ("MUST NOT change the rule or thresholds after any measured run"): honored by the letter. The measurement environment (`MALLOC_ARENA_MAX=1`) changed after red runs. Flagged; the user accepted it via the SC4 wording.
- **17-04** ("MUST NOT re-run until green"): attempt 3 came after the plan had closed with "no third attempt", as a user-approved supplementary run under a changed condition (window in front). It is recorded beside attempts 1 and 2, which stay failures. Flagged; user-approved.
- **17-05** ("MUST NOT mark any requirement complete"): broken by the letter in 1084a7b under the orchestrator's delegation after the user's approval. Flagged.

### Final CI runs (re-queried)

| Run | Workflow | headSha | Conclusion |
|---|---|---|---|
| 41056455257 | native-verify | c4a7158 (final gate) | success, 13/13 jobs |
| 41056455255 | flutter-plugin | c4a7158 | success, 3/3 jobs |
| 41056455344 | macos-route | c4a7158 | success |
| 41060074045 / 41060074053 / 41060073995 | native-verify / flutter-plugin / macos-route | bf153c2 | success |

The product code at HEAD equals the RTX-measured sha 9ae347f (`git diff 9ae347f HEAD -- packages example/lib example/integration_test native` is empty). Every commit after it is docs, evidence, CI or session tools.

### Requirements Coverage

| Req | Status | Evidence |
|---|---|---|
| VER-01 | SATISFIED (approved create-chain wording) | SC1 |
| VER-02 | SATISFIED | SC2 |
| VER-03 | SATISFIED | SC3 |
| VER-04 | SATISFIED (approved conditional wording) | SC4. Wording nuance: VER-04 says "每后端 100 轮 soak 且显存曲线平稳" with no carve-out, while SC4 explicitly marks opengl real VRAM as unverified (llvmpipe RSS stands in). SC4 is the contract. |

No orphaned requirements: REQUIREMENTS.md maps exactly VER-01..04 to Phase 17.

### Anti-Patterns Found

None blocking. There are no TBD/FIXME/XXX (or TODO/HACK) markers in the 30 product, test, CI and docs files changed since 5c22a6d.

## Residual Risks (accepted or tracked, non-blocking)

1. **Occlusion and d3d11 drops:** see "Not proven" item 1. The pass rests on a single run per condition.
2. **Allocator-dependent hosted soak:** see "Not proven" item 2. The rule is less sensitive than designed for the smallest frame size.
3. **Instrument validity on the RTX.** `GPUProcessMemory.DedicatedUsage` turned out to be cumulative for frame-presenting processes (tool-fix 2). The soak VRAM verdict still uses that counter, justified because the soaks barely present. Taken together with resizeEvents 1/101 and lastControllerFrame not-presented, the RTX soak VRAM verdict mostly shows that create/dispose without presentation is flat. It does not show that per-round ring churn is flat. The adapter column is independently flat inside each soak.
4. **Fault coverage is fake-backend and HRESULT-level only.** Real TDR/device loss, GL device loss, and a live backend switch (RBE-F1) are unverified (unverified.txt).
5. **Hardware breadth.** There is one RTX 4060 laptop. macOS real hardware, the arm64 real-plugin matrix, other GPU vendors, battery power, Vulkan-backend hwdec long runs, and a software 4K long run are all unverified (18 未验证 items in unverified.txt, including the ring-allocation row added in 0255e49).
6. **vk-gpu-timeout flake.** 10 macOS runs with no mismatch; the todo is closed but the flake is not shown to be eliminated.
7. **Housekeeping (info):**
   - Fixed in 0255e49 and checked by me:
     - Doc lines 22, 99 and 146 now say the wording was approved and applied in 1084a7b; no "pending" or "not applied" text is left.
     - `planning_files` is now accurate: c4a7158 and b426246 touch no ROADMAP/REQUIREMENTS/STATE file; 1084a7b touches ROADMAP and REQUIREMENTS, and bf153c2 touches ROADMAP and STATE.
     - The 17-05 SUMMARY now says three lavfi attempts plus the HEVC run.
     - unverified.txt has a new 未验证 row for the RTX soak ring-allocation finding (now 18 未验证 and 2 延后).
   - Still open:
     - `final-audit.txt` VER-01 说明 still carries the pre-approval sentence "written 部分证明 rather than 证明 because the wording proposals below are still pending-user-approval", next to 状态=证明 and the approval note.
     - ROADMAP Phase 17 is still `[ ]` (for the orchestrator).
     - The `mpv_kit_libs` stale `$target.ok` stamp (hook/build.dart:76) is still open.

## Gaps Summary

There are no gaps. Each roadmap SC is backed by re-queried CI logs, raw RTX logs and code that does what the SUMMARYs say. SC1 and SC4 are met only in their user-approved wording, and their original literal forms are not met: there is no runtime chain switch, and the d3d11 zero-drop result is conditional on the window being in front. The single unconditional plan truth that fails (17-04 d3d11 4K) is carried as an override with the user's recorded approval. The four caveats named in the request are kept unproven. The RTX soak's per-round allocation depth is raised as an advisory, not a gap, because the soak meets its pre-registered pass criteria and mirrors D-05 by design.

---

_Verified: 2026-10-30T13:39:44Z_
_Verifier: Claude (gsd-verifier)_

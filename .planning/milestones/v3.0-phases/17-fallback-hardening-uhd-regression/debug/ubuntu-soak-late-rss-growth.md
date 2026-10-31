---
status: diagnosed
trigger: "ubuntu opengl backend_soak_test intermittent late RSS growth (native-verify run 40993938470 on aac870d)"
created: 2026-10-30
updated: 2026-10-30
goal: find_root_cause_only (product-code change requires user approval)
---

# Debug: ubuntu-soak-late-rss-growth

## Symptoms

- **Expected:** `backend_soak_test` (MPV_KIT_VIDEO_API=opengl, MPV_KIT_SOAK_MEMORY=rss, 100 rounds, hosted ubuntu-24.04 xvfb + llvmpipe) ends with `rssVerdict: flat` under the pre-registered rule (late = c10 - c6; growth iff late > 32 MiB, or c6..c10 each step >= 1 MiB and late > 8 MiB).
- **Actual:** run 40993938470 (head aac870d, docs-only commit; product code identical to the green runs) job 123864853019:
  rssMiB [661.1, 946.8, 1158.5, 1230.5, 1297.1, 1309.0, 1347.5, 1385.4, 1429.9, 1526.1, 1567.3], rssLateMiB 219.8, rssVerdict growth.
  renderErrors 0, deviceLost 0, idleSoak 0, apiMismatches 0, lastControllerFrame not-presented, seconds 32.0.
  SOAK-CHECKPOINT `controllers` counts 1, 11, ..., 101 (meaning of this counter to be checked: cumulative created vs live).
- **Green comparison (same product code):**
  - 40989693698 (2296c9a): [657.6, 954.7, 1124.8, 1186.7, 1184.6, 1198.0, 1203.7, 1202.9, 1214.5, 1213.3, 1210.5] late +6.8 flat
  - 40991964430 (cbdab03): [657.3, 944.4, 1161.5, 1229.1, 1235.3, 1235.6, 1234.7, 1240.3, 1243.2, 1242.3, 1242.6] late +8.0 flat
  - All three runs grow ~+500 MiB over the first 30-50 rounds before plateauing (green) or continuing (red).
- **Errors:** test assertion `Expected: SoakMemoryVerdict.flat Actual: SoakMemoryVerdict.growth`; no native errors seen yet.
- **Timeline:** soak step added in 17-03 (2296c9a). 2 green, then 1 red out of 3 runs.
- **Reproduction:** native-verify workflow, job `integration-test (ubuntu-24.04, linux, ...)`, step after `Backend matrix`.

## Constraints

- Obey `.planning/.continue-here.md` BLOCKING CONSTRAINTS (protected user files, root pin, push-green-only, no tags, no force).
- First measure frequency by rerunning only the ubuntu integration-test job / workflow_dispatch WITHOUT changing product code.
- Any change to product code (packages/**, native/**) invalidates the 17-04 rtx-prep product sha (9ae347f) -> STOP and ask the user before making it.
- Instrumentation-only changes to test code are allowed on a plan-named scratch branch `ci/17-debug-soak` (delete at end), or kept local.

## Current Focus

hypothesis: CONFIRMED (b): glibc malloc arena retention. The hosted 4-vCPU runner caps glibc at 8 x 4 = 32 arenas while the process has ~44 live threads, so short-lived per-controller threads are spread round-robin over all 32 arenas and each leaves a ~29 MiB high-water of freed llvmpipe/GL ring memory behind; the pre-registered RSS rule then measures arena placement, not live memory. (a) leak and (c) Dart/harness growth eliminated.
test: done (4 scratch waves, 74 probed or CI-like soaks, see Evidence)
expecting: n/a
next_action: return ROOT CAUSE FOUND to the caller; fix choice (CI-only MALLOC_ARENA_MAX=1 vs accept/other) is the user's decision. Scratch branch deleted, protected files cmp-ok.

## Evidence

- timestamp: 2026-10-30T03:15Z
  checked: backend_soak_test.dart `_controllers`, `_create`, `_remountCycle`, `_checkpoint`
  found: `controllers` is CUMULATIVE created (`_controllers++` in `_create`): 1 + 100 rounds = 101. Live controllers are always 1 (unmount, setSize on the OUTGOING controller, dispose, create next). A controller is only sized at the very end of its life (the new one is never sized, only the outgoing one), so every controller renders at most one frame, at the moment it is about to be disposed.
  implication: `controllers` does not indicate a controller leak. Per round exactly one mpv render context + one EGL context + one ring (6 slots + private target) is created and destroyed.
- timestamp: 2026-10-30T03:15Z
  checked: the 3 known ubuntu job logs (downloaded to /tmp/soakdbg/logs/run<id>_a1.log)
  found: all three on the same runner image ubuntu-24.04 20261025.353.1, Flutter 3.47.9, llvmpipe LLVM 20.1.2 256 bits. `resizeEvents` (Dart-side count of delivered `resize` events across all 101 controllers) differs strongly: green 68 and 75, RED 30; in the red run resizeEvents stayed at 1 until round 20 (green: 3..5 by round 10 and 5..11 by round 30). Wall time per 10 rounds is the same (3.1..3.3 s) in all three.
  implication: the red run's render threads/event delivery were slower relative to the platform thread (scheduling/CPU contention on that VM). `resize` is emitted by the render thread in RenderOnce right after AllocTargets and is dropped by PostEvent when Dispose already set texture_id=-1, so resizeEvents is a race indicator, not an allocation count. The growth is NOT explained by "more rings allocated" (red allocated fewer observable rings).
- timestamp: 2026-10-30T03:20Z
  checked: packages/mpv_kit_video/linux/mpv_kit_video_plugin.cc Dispose + gl_interop.cc Bury/Orphan/DrainGraveyard + opengl_backend.cc FreeSlot
  found: GL ring slots are freed in two stages. Render thread (Release -> FreeAllTargets -> FreeSlot) deletes the export texture/FBO and calls `interop_->Bury(platform)`; the EGLImage and the Flutter-side texture are only destroyed in `GlInterop::DrainGraveyard`, which runs ONLY from `mpv_kit_gl_texture_populate` (raster thread, on a LIVE texture). After Dispose, the per-State graveyard is moved to the process-global `orphans` list by a g_timeout_add(1000 ms) `Orphan()`, and the global list is drained by the next populate of any live texture. llvmpipe keeps texture storage alive while the EGLImage exists, so storage of a disposed controller is retained for >= 1 s and until some later populate runs. In the soak the mounted controller is painted only a few times (it is never sized, so FrameReady is never called for it), so drain frequency depends on Flutter frame scheduling and raster thread timing.
  implication: leading structural candidate for a load/timing dependent retention (bounded by populate frequency, not a permanent leak). Needs measurement: smaps/mallinfo at checkpoints, plus an experiment that changes only allocator behaviour.

- timestamp: 2026-10-30T03:25Z
  checked: FREQUENCY. `gh run rerun <run> --job <ubuntu integration-test job>` once per known run (same sha/artifacts per run; attempt 2 job ids 123869802938 / 123869810701 / 123869819422). Logs saved in /tmp/soakdbg/logs/run<id>_a<attempt>.log
  found: 6 samples, 3 red / 3 green, i.e. ~50 percent red, far above any acceptable flake rate. Full table (rssMiB c0..c10, late = c10-c6):
    1. 40989693698 a1 (2296c9a, centralus) flat   [657.6, 954.7, 1124.8, 1186.7, 1184.6, 1198.0, 1203.7, 1202.9, 1214.5, 1213.3, 1210.5] late +6.8
    2. 40991964430 a1 (cbdab03, centralus) flat   [657.3, 944.4, 1161.5, 1229.1, 1235.3, 1235.6, 1234.7, 1240.3, 1243.2, 1242.3, 1242.6] late +8.0
    3. 40993938470 a1 (aac870d, eastus)    GROWTH [661.1, 946.8, 1158.5, 1230.5, 1297.1, 1309.0, 1347.5, 1385.4, 1429.9, 1526.1, 1567.3] late +219.8
    4. 40991964430 a2 (cbdab03, southcentralus) GROWTH (tail rule) [661.4, 938.5, 1161.9, 1231.9, 1223.7, 1222.8, 1228.7, 1231.0, 1232.1, 1237.1, 1258.2] late +29.5 (below the 32 MiB limit; red only because every tail step >= 1 MiB and late > 8)
    5. 40993938470 a2 (aac870d, westus)    flat   [667.8, 944.0, 1184.0, 1293.4, 1363.2, 1407.8, 1457.0, 1482.9, 1454.7, 1476.2, 1485.1] late +28.1 (green only because step 7->8 -28 MiB broke the "steady tail"; plateau level 1480 MiB is 250 MiB above samples 1/2)
    6. 40989693698 a2 (2296c9a, eastus)    GROWTH [660.7, 940.0, 1155.9, 1236.0, 1339.4, 1379.9, 1411.0, 1449.1, 1502.8, 1578.2, 1594.2] late +183.2
  Same product code in every sample (docs-only commits between 2296c9a/cbdab03/aac870d). Same runner image 20261025.353.1, Flutter 3.47.9, llvmpipe LLVM 20.1.2 256 bits, renderErrors 0, deviceLost 0 everywhere.
  implication: (1) the failure is not tied to a commit; it is a property of the run. (2) the late-growth value is continuous (+6.8 .. +220), not a clean leak/no-leak dichotomy: samples 4 and 5 sit at ~+29 and are classified opposite ways by the pre-registered rule purely on tail monotonicity. (3) the plateau level itself varies (1210..1670 MiB at c10) so the "warm-up" of ~500 MiB is not a constant either. (4) weak region correlation: centralus x2 flat, eastus x2 growth (+220, +183); needs CPU model logged (hosted pools differ by CPU SKU).

- timestamp: 2026-10-30T03:48Z
  checked: WAVE 1 on scratch branch ci/17-debug-soak (run 40998661008; workflow .github/workflows/soak-debug.yml, push-triggered; test code and workflow only, zero product files differ from aac870d; uses the libmpv artifact of the red run 40993938470 so the binaries are identical). Probe = example/integration_test/soak_debug_probe.dart (/proc/self/status, glibc mallinfo2, smaps) wired into backend_soak_test.dart behind MPV_KIT_SOAK_DEBUG=1; the pre-registered rule is untouched and still decides the verdict. 10 jobs x 1-2 soaks, logs in /tmp/soakdbg/w1/.
  found (verdicts by the unchanged rule, CPUs vary: EPYC 7763, EPYC 9V45, EPYC 9V74, Xeon 8370C, red on every CPU type):
    default allocator, probe observe-only: 8 soaks, 6 growth (+104.2, +141.4, +78.2, +140.3, +82.6, +109.9) and 2 flat (+21.7, +17.2). Together with the 6 CI samples: 9 red of 14.
    MALLOC_ARENA_MAX=1: 4 soaks (2 jobs, 2 CPU types), 4 flat, late -28.6 / -0.7 / +3.6 / +18.9, c10 RSS 777-919 MiB (default: 1245-1572).
    malloc_trim(0) after every checkpoint: 4 soaks, 4 flat (RSS falls by 215-390 MiB at each trim).
    MPV_KIT_VIDEO_API=software (no GL at all): 2 soaks, 2 flat (+21.3, -17.2), c10 ~890 MiB.
  decisive numbers (default allocator, red run base-1 rep1, MiB; same shape in every default run):
    round   0: RSS 702  RssAnon 514 RssFile 180 | malloc inUse 484 free  53 mmapped 50
    round  10: RSS 994  RssAnon 807 RssFile 180 | malloc inUse 471 free 724 mmapped  8
    round  30: RSS 1295 RssAnon 1108           | malloc inUse 471 free 927
    round 100: RSS 1572 RssAnon 1385           | malloc inUse 471 free 1032
  glibc "inUse" is FLAT at 465-520 MiB for all 100 rounds in every run (a per-round leak of even 0.88 MiB would add 88 MiB), mmapped flat 8-10 MiB, RssFile flat 180, Threads flat 41-45, open fds flat 25. All growth is "free" memory that glibc keeps (arena size 537 -> 1195 -> 1503 MiB). With one arena the same workload retains only ~270 MiB free (arena 743 MiB) and is flat.
  implication: the growth is allocator retention (multi-arena glibc fragmentation of freed GL/mpv/llvmpipe memory), NOT a live-object leak in the product, NOT thread or fd growth, NOT Dart heap growth (the Dart harness is identical in the arena1 runs, which are flat to +-20 MiB). Whether a run crosses the rule's threshold depends on how many arenas the churn of ~100 controller lifecycles ends up touching, which is scheduling dependent: that is why the same sha is red or green.

- timestamp: 2026-10-30T03:58Z
  checked: WAVE 2 (run 40999612293, 14 jobs x 2 soaks; logs /tmp/soakdbg/w2/). Same libmpv artifact and product code. Adds probe-off runs, arena limits 2/4, per-arena malloc_info, and a deliberate-leak sensitivity check.
  found:
    CI-like, probe OFF, default allocator (plain-1..3): 6 soaks, 5 flat (+13.9, -6.9, +4.2, -3.8, +1.0) and 1 GROWTH (+94.5). c10 RSS 1184..1548 MiB (the plateau level alone varies by 360 MiB between flat runs). With the 6 CI samples the probe-free default red rate is 4 of 12 (33 percent). With the probe ON the default-allocator red rate was 10 of 12 (the probe, which scans smaps/malloc_info and lists /proc/self/fd every checkpoint/round, evidently makes retention worse; probe-on rates are NOT the CI rate).
    MALLOC_ARENA_MAX=1, probe OFF (a1plain-1..3): 6 of 6 flat, late +2.6, -7.2, +6.4, -108.5, +3.0, +15.6, c10 RSS 751-901 MiB. With the 4 probe-on arena1 soaks of wave 1: 10 of 10 flat.
    MALLOC_ARENA_MAX=2: 3 flat, 1 growth (+41.3, tail rule). MALLOC_ARENA_MAX=4: 3 flat, 1 growth (+77.0). So fewer arenas helps monotonically but only 1 was reliably flat so far.
    sensitivity (MALLOC_ARENA_MAX=1 plus a deliberate 0.9 MiB/round leak = the 0.88 MiB 640x360 frame of the rule's design, 36 MiB over the 40 late rounds): 3 of 4 soaks report growth (+55.5, +72.7, +81.2), 1 reports flat (+22.0). So under one arena the unchanged rule still detects a leak of the smallest frame size most of the time and detects anything larger essentially always; the rule's own design margin (35 vs 32 MiB) explains the one miss.
  mechanism (malloc_info, default allocator, probe ON, base-d-1/base-d-2): glibc has n=32 arenas already at round 0 (limit = 8 x 4 vCPU; the process has ~44 threads, so every arena is attached to a long-lived thread and the free list is empty). New short-lived threads (each controller's render thread, the RunBound worker, mpv/llvmpipe helpers) are therefore placed round-robin on the 32 existing arenas (reused_arena). At round 10 about 25 arenas each hold ONE free block of ~29.2 MiB (rows [nr, system, free, subheaps] like [4, 29.2, 29.2, 1], [13, 29.2, 29.2, 1], [16, 29.2, 29.2, 1]) = ~730 MiB; by round 30 all 32 arenas are primed (free 914-927 MiB) which is the "warm-up plateau" of 930 MiB that every run shows. ~29 MiB is the size of one controller's ring (6-7 slots of 1280x720 RGBA = 3.5 MiB each plus the private target and llvmpipe state). The red runs additionally get arenas that grow extra sub-heaps late ([10, 114->147 MiB, 3 subheaps], [6, 50->126 MiB, 3 subheaps], [1, 30->122 MiB, 2 subheaps] between rounds 60 and 100): fragmentation of a primed arena by a long-lived allocation lets a later ring not fit into the 29 MiB hole, so the arena maps another 64 MiB sub-heap. Which arenas/rounds this happens in depends on thread scheduling, hence red or green on the same sha.
  implication: confirmed allocator retention, bounded by (arena count x per-controller working set) plus fragmentation sub-heaps. llvmpipe keeps GL texture storage in malloc memory, which is why this shows on hosted runners and not as GPU memory on real GPUs.

- timestamp: 2026-10-30T04:05Z
  checked: WAVE 3 (run 41000319009; logs /tmp/soakdbg/w3/): arena limit scaling, smaps categories, LP_NUM_THREADS=0.
  found: c10 RSS by MALLOC_ARENA_MAX, probe on (MiB): 1 -> ~780-920 | 2 -> ~860-900 | 4 -> ~890-950 | 8 -> 1037, 1053 | 16 -> 1208, 1180 | 32 (default on 4 vCPU) -> 1184..1622 | 64 -> 806, 773, 805, 807. NOT monotonic: with a limit of 64 the allocator creates only n=42 arenas (= peak number of simultaneously live threads, ~44) and the retained memory is small (heap64 rss 279 -> 388 MiB, free 23 -> 155 MiB). LP_NUM_THREADS=0 (llvmpipe without rasteriser worker threads, i.e. fewer live threads) also stays at ~790-820 MiB. smaps of a default red run (base-e-1 rep2, MiB): non-main arena heaps ("heap64", 64 MiB aligned rw-p anon) rss 251 (r0) -> 540 (r10) -> 839 (r30) -> 872 (r60) -> 978 (r100); [anon:dart-heap] flat 81-84 (101 at r100); libLLVM 57, kernel_blob 46, libflutter 20, RssFile 180 all flat.
  implication: ROOT CAUSE. glibc caps arenas at 8 x vCPU = 32 on the 4-vCPU hosted runner, but the process has ~44 threads (Flutter, Dart, mpv, llvmpipe rasteriser workers, GTK), so every arena stays attached to a long-lived thread and the free list is empty. The short-lived threads that each controller creates (render thread, RunBound worker) are then spread round-robin over all 32 arenas, and each leaves its ~29 MiB high-water (a controller's GL ring and llvmpipe state, which llvmpipe keeps in malloc memory) behind in the arena it landed on. ~32 rounds touch all 32 arenas (the 930 MiB warm-up plateau). Late growth in red runs comes from primed arenas that fragment and map extra 64 MiB sub-heaps. When the arena limit exceeds the live thread count (64) exiting threads release their arena to the free list and the next thread reuses it (no accumulation); with a limit of 1 all threads share one arena, so freed memory is reused. The pre-registered RSS rule therefore measures glibc arena placement, not memory the product holds.

- timestamp: 2026-10-30T04:15Z
  checked: WAVE 4 (run 41001199626, 16 jobs): reliability of the candidate CI-only change (the exact CI step plus MALLOC_ARENA_MAX=1, probe off) and a faithful default baseline (real_plugin_test + backend matrix run first, then the soak).
  found: arena limit 1, probe off: 22 of 22 flat (20 plain + 2 after the CI prefix), late -47.4 .. +9.2 MiB, c10 RSS 810-880 MiB. Over every arena=1 soak of the session (wave 1-4, probe on and off): 32 of 32 flat, late -108.5 .. +18.9, c10 RSS 751-919 MiB, versus default 1121-1623 MiB. Default allocator with the faithful prefix, probe off: 2 growth (+59.9, +123.4), 2 flat (+4.3, +24.5; one of the flat ones plateaued at 1563 MiB). All default-allocator probe-free soaks of the session including the 6 CI samples: 6 of 16 red (37.5 percent).
  implication: the candidate environment-only change removes the nondeterminism on this runner (0 of 32 red, rule of three upper bound about 9-10 percent at 95 percent confidence) without touching the rule, its thresholds, the test, or any product file; the unchanged rule still flags a deliberate 0.9 MiB/round leak under it in 3 of 4 soaks and anything larger reliably.
  files: raw logs /tmp/soakdbg/{logs,w1,w2,w3,w4} (Git Bash /tmp, outside the repo; may be cleared), kept copies in .planning/phases/17-fallback-hardening-uhd-regression/debug/ubuntu-soak-late-rss-growth.data/ (scratch-results.tsv = every scratch soak, scratch-probe.patch = test-code probe, soak-debug.yml.txt = scratch workflow)

## Eliminated

- hypothesis: the graveyard/orphans drain (EGLImage and Flutter-side texture of a disposed controller are freed only by a later populate, >= 1 s after dispose) retains ring storage under load
  evidence: retained storage would stay allocated, i.e. show as glibc "in use" (or mmapped) memory; in use is flat at 465-520 MiB in every probed soak while the growth is entirely free-but-retained chunks. (Its sizes are also far too small: one ring is ~25 MiB, the graveyard holds the last 1-3 controllers.)
  timestamp: 2026-10-30T04:15Z
- hypothesis: (a) real per-round native leak (frame ring, EGLImage/texture, GL interop, controller not freed) as cause of the red runs
  evidence: glibc inUse + mmapped are flat (+-20 MiB) over 100 rounds in all 28 probed soaks, threads and fds flat, and MALLOC_ARENA_MAX=1 (which changes no object lifetime) makes the same code flat 4/4. A leak of the smallest frame size would add 88 MiB. (wave 2 leak-N variants check that the rule still reports such a leak under MALLOC_ARENA_MAX=1)
  timestamp: 2026-10-30T03:48Z
- hypothesis: (c) Dart heap / test harness growth
  evidence: the harness is identical in the arena1 and software soaks, which are flat (+-30 MiB) after round 30; Dart-side objects per round (route, controller, subscriptions) cannot depend on the malloc arena limit.
  timestamp: 2026-10-30T03:48Z
- hypothesis: red is tied to a commit or to a particular runner CPU/region
  evidence: same product code in every sample; red seen on EPYC 7763, 9V45, 9V74 and Xeon 8370C and in eastus, southcentralus, westus3, centralus (faithful-1) - no clean split.
  timestamp: 2026-10-30T03:48Z

## Resolution

root_cause: glibc malloc arena retention on the 4-vCPU hosted runner, not a leak. glibc allows 8 x vCPU = 32 arenas; the process already has ~44 live threads (Flutter/Dart/GTK, mpv, llvmpipe rasteriser workers), so all arenas are attached and the free list is empty. Every controller's short-lived render/RunBound threads are therefore placed round-robin on the 32 arenas, and each leaves behind the ~29 MiB of freed GL ring and llvmpipe memory it allocated (llvmpipe keeps GL texture storage in malloc memory). After ~32 rounds every arena is primed (~930 MiB retained, the "warm-up"); late growth is primed arenas that fragment and map extra 64 MiB sub-heaps, which depends on thread scheduling, so the same sha is red 6 times in 16 probe-free default runs. Product memory in use is flat (glibc in-use 465-520 MiB over 100 rounds, mmapped, threads and fds flat). The pre-registered RSS rule measures arena placement on this runner, not what the product holds.
fix: NOT APPLIED (find_root_cause_only). Recommended, for the user to decide: (1) CI-only, no product code, no rule or threshold change: add `MALLOC_ARENA_MAX: '1'` to the env of the step "Backend soak (linux, MPV_KIT_VIDEO_API=opengl, VER-04)" in .github/workflows/native-verify.yml, with a comment that the RSS record is only meaningful with a single glibc arena on 4-vCPU runners. Measured 32 of 32 flat (late -108.5..+18.9 MiB, c10 750-920 MiB) against 6 of 16 red without it; a deliberate 0.9 MiB per round leak is still reported as growth in 3 of 4 soaks under it. (2) Alternatives that do not touch the product either: accept this step as a known flake with one allowed rerun (37 percent red makes that expensive), or ask the user to change the memory record (e.g. add glibc in-use bytes) which would amend the pre-registered rule and is therefore the user's call. (3) Product change (not recommended, not needed): `malloc_trim(0)` after VideoRenderer teardown in linux/mpv_kit_video_plugin.cc Dispose, or `mallopt(M_ARENA_MAX, n)` at plugin registration. That touches packages/mpv_kit_video/linux/** and invalidates the 17-04 product sha 9ae347f; it would only matter for software-GL (llvmpipe) hosts, since on real GPUs ring memory is not malloc memory.
verification: not applicable to a diagnosis; the candidate change was measured on a scratch branch (workflow-only differences, same libmpv artifact and product code as the red run): waves 1-4 in Evidence, results in ubuntu-soak-late-rss-growth.data/scratch-results.tsv.
files_changed: [] (product and repo files untouched; scratch branch ci/17-debug-soak deleted remotely and locally; only this debug file and ubuntu-soak-late-rss-growth.data/ were written)

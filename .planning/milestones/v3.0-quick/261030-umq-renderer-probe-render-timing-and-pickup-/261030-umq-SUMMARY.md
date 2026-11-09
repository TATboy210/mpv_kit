---
quick_id: 261030-umq
slug: renderer-probe-render-timing-and-pickup
status: complete
date: 2026-10-30
commits: 2
plan_head_before: 9cbc1e98355296f7edcac5a3fff4873d60d94249
plan_head_after: 48b92e36e029b4611b59624f4f78deb7c858557f
commit_list: [c07f5ba5d739b77ddd73f501ca61ee5565d36da6, 48b92e36e029b4611b59624f4f78deb7c858557f]
pushed: no
actuals:
  tasks: 3
  commits: 2
---

# Quick 261030-umq: renderer probe, render timing and compositor pickup

## Outcome

The two existing 120-frame probe lines now carry timing for mpv's render call and for the compositor's Describe/engine bind, log only, no behaviour change, no Dart API change. Four gated 135 s RTX 4060 runs measured the d3d11/vulkan x hwdec combos. Nothing is pushed.

- `render waits avg/over ...` gains `render=<ms>ms max_render=<ms>ms` at the end (time of `mpv_render_context_render`).
- `compositor pickup avg/over ...` gains `describes= describe= max_describe= handle_changes= binds= bind= max_bind=` (Windows plugin only; `char line[320]`).
- Commit 1 `c07f5ba`: video_renderer.h/.cc, windows plugin (CRLF kept), swap_test, docs/ARCHITECTURE.md, PLAN, local-tests log. Commit 2 `48b92e3`: RESULTS, measure.patch, four run logs and four smi CSVs (ten paths, all LF in git).

## RTX 4060 results (135 s each, times in ms)

| combo | effective drops (post warm-up) | dec_drops | render_med | render_max | done_med | pickup_med | describe_med | handle_change_ratio | bind_med | bind_max | gr_mhz med | util_gpu med | util_dec med | temp max |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| d3d11+d3d11va | 0 | 0 | 16.126 | 31.331 | 0.419 | 4.230 | 0.003 | 1.00 | 0.443 | 33.528 | 840 | 26 | 44 | 45 |
| vulkan+vulkan | 0 | 0 | 16.503 | 31.440 | 0.022 | 4.300 | 0.003 | 1.00 | 0.445 | 23.988 | 840 | 26 | 44 | 45 |
| vulkan+d3d11va-copy | 0 | 0 | 16.485 | 31.936 | 0.040 | 4.355 | 0.004 | 1.00 | 0.522 | 7.047 | 870 | 42 | 46.5 | 45 |
| d3d11+no | 0 | 0 | 16.536 | 32.722 | 0.003 | 4.605 | 0.003 | 1.00 | 0.471 | 12.079 | 750 | 39 | 0 | 45 |

All four combos took effect (api_ok=yes, hwdec_ok=yes, hwdec_seen equals the request). Gate pass, fg_start and fg_end = mpv_kit_example, alive_at_end=yes, standby=none, forensics=none for every run. 7440 describes and 7440 handle changes per run (ratio 1.00, Flutter's one-handle cache misses on every frame). render= sits at the 16.67 ms frame period because it includes mpv's wait for the target time (BLOCK_FOR_TARGET_TIME), so it is an upper bound. bind= (0.44-0.52 ms median) is the engine's per-handle surface recreate; its maxima are single-frame spikes. See RESULTS for notes and findings.

## TDD and integration (Task 1)

- RED: swap_test rc=1 in exactly four scenarios (fifo-jitter, fifo-cap-drop-q2, fifo-cap-drop-q4, fifo-repeat): "probe line does not end with render=<ms>ms max_render=<ms>ms".
- GREEN: swap_test `SWAP ok scenarios=10`; native suite `ALL rc=0` twice plus a fresh run; golden-freeze-17 sha256 OK.
- Integration: real_plugin_test=pass, d3d11_backend_test=pass.
- Harness smoke (30 s, d3d11+d3d11va and vulkan+vulkan): every probe and pickup line matched the full-tail regex.

## Sample provenance and deviation

No 3840x2160 59.94 fps H.264 file exists on the host (29 candidates probed) and none was placed in `build\umq\sample\`. The user replied `start`; fallback `Desktop\1145142.mp4` was used: avc1 3840x2160, 60.000 fps (not 59.94), 36.9 s, looped (`MPV_KIT_EXAMPLE_LOOP=1`, about three loop seeks per 135 s run). Not directly comparable with a 59.94 fps no-loop GTX 960M run.

## Deviations from Plan

1. [Sample] Fallback sample, as above (option b of the Task 2 checkpoint).
2. [Metric reading] The run lines' `drops=` is the last minus the 10th stats value; with the looped sample the mpv counter reset at the first loop wrap (6 and 8 startup drops before the 10th stats line, then 0), so the d3d11+d3d11va and vulkan+vulkan run lines show drops=-6 and drops=-8 and `effective=` negative. The RESULTS table adds `eff_post10` (sum of positive counter increments after the 10th stats line plus superseded), which is 0 for all four. Harness script untouched.
3. [Process] The commit-2 RESULTS file was first staged with CR bytes (draft lines CR-terminated); caught by the `i/lf` check, stripped, and the unpushed commit 2 amended once (sha `48b92e3`).
4. Planner addition beyond the request: the `bind=` bracket (Describe's return to the engine release callback), grounded in Flutter 3.47.8 `external_texture_d3d.cc:54-115`.

Auth gates: none. Stubs: none. Threat flags: none (log-only fields; nvidia-smi used only with `--query-gpu`).

## Pending / follow-ups

- CI only, not run here: meson build and swap_test on Linux, macOS, Windows MSYS2 (`-Werror`), ASan/UBSan job. The orchestrator decides about pushing.
- The same probe on the GTX 960M (the D3D-08 decision host).
- `d3d11va-zero-copy=yes` as a separate A/B.
- The engine's per-handle surface recreate could only be avoided by an engine-side cache or a stable handle, which is not planned.
- The measure.patch (example/lib/main.dart: forced hwdec, optional loop, hwdec/dec-drop on the stats line) is stored in the quick dir only; example/lib and pubspec.yaml are clean and no Dart file is in either commit.

## Self-Check: PASSED

Plan Task 3 automated gate rc=0; commits `c07f5ba` and `48b92e3` exist on feat/mpv-master-upgrade; no mpv_kit_example process left; product tree equals commit 1.

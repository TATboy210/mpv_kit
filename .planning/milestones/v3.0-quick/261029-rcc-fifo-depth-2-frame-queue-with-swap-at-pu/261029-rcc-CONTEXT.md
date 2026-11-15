# 261029-rcc context (orchestrator notes, 2026-10-29)

## Laptop evidence (GTX 960M + HD 530, Flutter on 960M, 4K 59.94 H.264, ~1374x773)
- Main package ade3eea (swap at compositor pickup): mpv frame-drop-count keeps rising (earlier runs: vulkan 3-6 %, d3d11 25-34 %).
- Control ade3eea_swapfix (swap at publish, newest-wins): mpv drops ~0 (vulkan 0, d3d11 10 total), but superseded= per 120 frames: vulkan avg ~12-13 (peaks 35-42) ≈ 10 %, d3d11 avg ~25 (peaks 44-46) ≈ 20 %. `compositor pickup avg` oscillates 3↔13 ms with ~7-window (~14 s) period; superseded peaks coincide with pickup avg ~3-4 ms (59.94 vs 60 Hz phase beat + Flutter acquire jitter).
- RTX 4060 (dev host) A/B earlier (quick 261029-nwm): base 0/0, swapfix superseded 123/128 per 150 s (~1.5 %).

## Decision (user, 2026-10-29): step 1 = FIFO depth-2 ready queue + report_swap at publish; keep video-sync=audio.
- Publish appends to a ready queue (cap 2; when full drop the oldest → counts as superseded/dropped).
- AcquireFront pops the oldest ready frame if any, else repeats the current one (count repeats, log-only).
- Ring needs one extra slot (ring_size_ = quarantine + 4); check allocation-failure retry path (ring 5 → 6?).
- Keep RBE-05 (report_swap only on render thread). Keep idle detection (last_acquire_).
- Log-only counters added to the 120-frame probe line: superseded= (existing), repeated= (new), queue depth stats optional.
- Expected: superseded≈0 except beat/cap drops, repeats ≈ 1 per ~16.7 s at 59.94/60, mpv frame-drop-count ≈0, pickup avg +~1 frame and steady, avsync same order.
- Step 2 (only if step 1 insufficient): timestamp picker (AVFoundation smoothed target-time, BSD) on the same queue.

## Why not display-resample: requires report_swap at real vblank (render.h:526-533 BLOCK_VSYNC); Flutter Windows vsync is synthetic timer (flutter_windows_engine.cc:740-765), acquire jitter; earlier 603-frame backlog (player.dart:79-84).

## Reusable artifacts
- build/nwm/fix-control.patch (swap-at-publish hunks vs ade3eea), build/nwm/video_renderer_swap_test.cc, build/nwm/run_ab.sh, ab_metrics.sh, relbuild.sh, make_pkg.sh, fin_pkg.sh, smoke.sh, power.ps1, build/nwm-tests/{build_all.bat,run_all.sh}.
- Community refs: /tmp/research16 (media-kit, fvp, iina, mpvqt, jellyfin clones); flutter/packages TextureBasedVideoPlayer.swift:133-160 (BSD); Chromium video_renderer_algorithm.cc FindBestFrameByCoverage (BSD); ExoPlayer VideoFrameReleaseHelper (Apache-2.0).

golden_refreeze: approved (user, 2026-10-29, via AskUserQuestion: vk.txt may change only by the extra ring image create/destroy lines and following serial renumbering; other four frozen files byte-identical)

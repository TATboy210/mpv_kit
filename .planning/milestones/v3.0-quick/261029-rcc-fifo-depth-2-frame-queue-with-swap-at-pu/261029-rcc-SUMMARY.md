---
quick_id: 261029-rcc
slug: fifo-depth-2-frame-queue-with-swap-at-publish
status: complete
date: 2026-10-29
commits: [0e792c8, 3e1139a]
ci: pending (push + hosted CI gate follow this summary; results in 14-10 evidence/ci-runs-14-fifo.txt)
---

# Quick 261029-rcc: FIFO depth-2 frame queue with the mpv swap reported at publish

## Outcome

`VideoRenderer` now keeps a ready queue of two published frames (cap 2, oldest dropped when full and counted as superseded). Every published frame gets exactly one `mpv_render_context_report_swap` on the render thread right after the publish, before `Interop::FrameReady`; `AcquireFront` pops the oldest ready frame, else repeats the current one. Ring size = quarantine + 4. Log-only probe counters `superseded= repeated= queued=` on the 120-frame line. RBE-05 holds (affinity and bind tests green with asserts on).

User decision (2026-10-29): step 1 = FIFO + swap at publish, keep video-sync=audio. Golden re-freeze approved by the user (only vk.txt, vk_fallback.txt, vk_retire_twice.txt changed, by the extra ring image lines; recorded in `evidence/golden-freeze-14-rcc.sha256`).

## RTX 4060 A/B (PASS, 261029-rcc-AB.txt)

Base (swap at pickup) vs FIFO, 150 s each: effective drops auto 1 vs 0, d3d11 1 vs 0; superseded 0 and 0; done wait 0.48/1.50 ms to 0.036/0.004 ms; pickup median 8.9/7.2 to 4.7/4.6 ms; avsync max about 1.8e-5; errors 0. The swap-at-publish control from 261029-nwm threw away 123/128 frames on this host; the FIFO turns them into shown frames. Local gates: real-plugin integration test, d3d11_backend test, flutter analyze, flutter test all pass; native tests in 261029-rcc-native-tests.log.

## Laptop results (package4, 0e792c8; GTX 960M + HD 530; ORCHESTRATOR-COMPUTED ESTIMATES from logs pasted 2026-10-29, durations not reported by the user)

GPU preference line `high-performance (AC power, battery saver off)`, adapter GTX 960M luid 00000000:000198A8 (luid changed after a reboot).

- auto vulkan: about 82 windows (about 164 s), mpv drops 24, all in ONE window with max_done 140 ms (single stall; 0 drops in all others), superseded about 25 total, effective about 0.5 percent (about 0.25 percent excluding the stall), queued 0-113 per window cycling with the beat, repeated 0, done about 0.03-0.1 ms, pickup avg 2.5-14 ms.
- forced d3d11: about 98 windows (about 196 s), mpv drops 7, superseded about 400 total (0-20 per window), effective about 3.5 percent, done avg 3-13 ms (max about 30), queued 6-119.
- Battery run: not yet done (user will re-test later), unverified.

## Commits

- 0e792c8 feat(video): FIFO ready queue of two frames, mpv swap reported at publish (`video_renderer.h/.cc`, `mpv_kit_video_plugin.cpp`, `native/tests/video_renderer_swap_test.cc` replacing `video_renderer_superseded_test.cc`, goldens, meson, ARCHITECTURE.md)
- 3e1139a docs(14-10): package4 provenance

## Open follow-ups

- CI pending: hosted native-verify and flutter-plugin runs for the FIFO chain (Linux/macOS plugins now call FrameReady from the compositor thread through lock-free mark posts; verified only by CI, not on hardware).
- Battery-branch laptop test (unverified).
- HUD backend label prints `vulkan` for forced d3d11 (14-11).
- d3d11 on Maxwell is slower than vulkan (about 3.5 percent vs about 0.5 percent effective): keep Vulkan first, 14-11 decision.
- Optional step 2 (smoothed timestamp picker on the same queue) only if the FIFO proves insufficient.

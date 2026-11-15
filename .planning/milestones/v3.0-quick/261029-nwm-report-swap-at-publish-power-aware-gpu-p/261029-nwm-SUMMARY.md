---
quick_id: 261029-nwm
slug: report-swap-at-publish-power-aware-gpu-preference
status: complete
date: 2026-10-29
commits: [6a712eb, ade3eea, 4be7678]
ci: pending (pushed together with the 261029-ljp and 261029-rcc chain; see 14-10 evidence/ci-runs-14-fifo.txt)
---

# Quick 261029-nwm: swap-at-publish experiment, log-only superseded counter, power-aware GPU preference

## Outcome

Status complete with a negative A/B on the main hypothesis. Swap-at-publish (newest-wins) FAILED its RTX 4060 A/B gate (`ab_gate=FAIL`, 261029-nwm-AB.txt): effective drops base 0/0 (auto/d3d11) vs fix 123/128 per 150 s (superseded about 1.5 percent of frames), mpv drops 0 vs 0 (auto) and 10 vs 0 (d3d11, first 10 s), pickup avg 8.8/7.9 to 4.6/4.7 ms. The plan's rule (not worse by more than 2 frames) could not pass because the baseline is already 0 on that host.

User decision (via orchestrator, 2026-10-29), option 3+4: commit ONLY the log-only `superseded=` instrumentation and ship the power-aware preference and hybrid hint; ship package3 (swap at pickup, unchanged) plus an experimental control package (swap at publish, uncommitted patch `build/nwm/fix-control.patch`) for the laptop comparison. The D-05 gate was overridden for packaging only.

## What shipped

- 6a712eb feat(video): log-only `superseded=` count in the 120-frame render probe line (`video_renderer.h/.cc`, `native/tests/video_renderer_superseded_test.cc`, `docs/ARCHITECTURE.md`); swap behaviour unchanged. The test file was later replaced by `video_renderer_swap_test.cc` in 261029-rcc.
- ade3eea feat(windows): example picks HighPerformancePreference only when GetSystemPowerStatus reports AC online and battery saver off (else NoPreference), logs `mpv_kit_example: GPU preference ...`; plugin writes one `mpv_kit: hybrid GPU hint` line when Flutter's adapter looks integrated and a discrete one exists (log only, reason strings unchanged); README and `docs/perf/d3d11-backend.md` carry the runner snippet and optional low-cost config.
- 4be7678 docs(14-10): package3 and package3-control provenance.

## Laptop results (GTX 960M + HD 530; ORCHESTRATOR-COMPUTED ESTIMATES from the logs pasted on 2026-10-29)

- package3 main (ade3eea, swap at pickup): drops keep rising (user).
- package3-control (swap at publish, newest-wins): auto mpv drops 0 but superseded avg about 12-13/120 (peaks 35-42), about 10 percent effective; d3d11 mpv drops 10, superseded avg about 25/120 (peaks 44-46), about 20 percent effective; compositor pickup avg oscillates 3 to 13 ms with about 14 s period (59.94/60 Hz beat).
- Conclusion carried into 261029-rcc: pure newest-wins hides the loss in superseded frames; a short FIFO queue is needed.

## Follow-ups

- Battery-power branch (NoPreference path) unverified on the laptop: the user will re-test later.
- Hybrid hint is log-only; HUD backend label bug stays with 14-11.
- CI for these commits was pending when this summary was written.

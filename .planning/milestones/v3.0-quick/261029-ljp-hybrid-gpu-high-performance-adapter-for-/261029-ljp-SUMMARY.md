---
quick_id: 261029-ljp
slug: hybrid-gpu-high-performance-adapter-for-example-runner
status: complete
date: 2026-10-29
commits: [824a69e, 0bf0bb6]
ci: pending (pushed together with the 261029-nwm and 261029-rcc chain; see 14-10 evidence/ci-runs-14-fifo.txt)
---

# Quick 261029-ljp: example runner prefers the high-performance GPU; plugin logs the compositor adapter

## Outcome

On the user's GTX 960M + HD 530 laptop, package1 (no preference) put Flutter and therefore the plugin's d3d11 device on the Intel HD 530 (dropped 477-3310, dec-drop 0; Windows per-app "High performance" did not move the adapter). The example runner now requests `flutter::GpuPreference::HighPerformancePreference`, and the plugin logs one line per D3D11Interop creation: `mpv_kit: compositor adapter "<name>" luid=<hi>:<lo>`. With package2 the compositor adapter was the GTX 960M.

## Commits

- 824a69e feat(windows): example prefers the high-performance GPU; plugin logs the compositor adapter (`example/windows/runner/main.cpp`, `packages/mpv_kit_video/windows/d3d11_interop.cpp`, README, `docs/perf/d3d11-backend.md`)
- 0bf0bb6 docs(14-10): package2 provenance in `evidence/laptop-package.txt`

## Verification

- package2 traceable: bundle_match=yes (24/24), angle_audit=ok (25/25), debug switches absent, adapter log line present in the Release DLL; smoke on the RTX 4060 dev host printed `compositor adapter "NVIDIA GeForce RTX 4060 Laptop GPU"` under auto and forced d3d11.
- Laptop results (ORCHESTRATOR-COMPUTED ESTIMATES from the logs pasted on 2026-10-29): compositor adapter "NVIDIA GeForce GTX 960M"; auto = vulkan gpu-next with hwdec vulkan, done 6-7 ms, pickup about 8 ms, mpv drops about 2.7-6 percent; forced d3d11 (hwdec d3d11va) done 8 to 15-17 ms, drops about 25-34 percent.
- No Dart file and no public API change.

## Follow-ups

- d3d11 on Maxwell is slower than vulkan: keep Vulkan first (14-11 decision).
- Battery-power behaviour was added later by 261029-nwm and is still unverified on the laptop.
- CI for this commit was pending when this summary was written.

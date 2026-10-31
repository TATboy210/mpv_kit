---
created: 2026-10-27T00:00:00.000Z
title: GTX 960 + iGPU laptop falls back to software rendering; 4K60 unusable
area: native
severity: major
resolves_phase: 14
resolved: 2026-10-29
resolved_by: 14-10 (+ quick 261029-ljp, 261029-nwm, 261029-rcc)
files:
  - packages/mpv_kit_video/src/vulkan_backend.cc
  - packages/mpv_kit_video/windows/d3d11_interop.cpp
---

## Problem

User ran the c7e9d12 Release demo on a hybrid-graphics laptop (Intel iGPU + GTX 960, Vulkan SDK not installed, driver version unknown) playing a 3840x2160 H.264 59.94 fps file:

```
backend=software reason=software (sw) on cpu; vulkan/gpu-next unavailable: no Vulkan 1.3 device shareable with the compositor; vulkan/gpu unavailable: no Vulkan 1.3 device shareable with the compositor compositor=ANGLE(DxgiShare...)
avsync=23.66 dropped=1046 dec-drop=0 hwdec=d3d11va-copy
```

Decode keeps up (dec-drop 0); every drop is the CPU software renderer missing 4K60 deadlines, and A/V drifts 23 s.

## Cause (not yet isolated)

`VulkanContext::PickDevice` (`vulkan_backend.cc:174-201`) rejects a device when `apiVersion < 1.3` or `Interop::AcceptDevice` (Flutter adapter LUID match) fails, and reports both as the same string. On a hybrid laptop the likely cause is the LUID mismatch (Flutter/ANGLE on the iGPU, Vulkan seeing the GTX 960), but an old driver capped at Vulkan 1.2 is also possible. Not reproducible on the RTX 4060 host.

## Direction (user decision 2026-10-27)

mpv_kit's own chain must not go through ANGLE. Flutter's own ANGLE compositor stays (engine-owned). This is Phase 14 (Windows native D3D11 backend): D3D11 device on the Flutter adapter LUID, no Vulkan 1.3 requirement.

## Solution

1. Phase 14 acceptance case: on a GTX 960 + iGPU laptop, 4K60 plays through a GPU backend (d3d11), never `software`, with dropped ~0.
2. Split the PickDevice reason into "Vulkan < 1.3 on <device>" vs "<device> is not the compositor adapter" so the cause is visible in the reason string (reason grammar per ADR 0004).
3. Separately consider whether the software fallback should cap render size for UHD sources (out of scope for Phase 14 unless planned).

## Resolution (Phase 14, 14-10)

Resolved 2026-10-29 by 14-10 with quick tasks 261029-ljp (HighPerformancePreference in the example runner + compositor adapter log line), 261029-nwm (log-only `superseded=` counter, power-aware preference, hybrid-GPU hint; swap-at-publish A/B FAILED and was not shipped) and 261029-rcc (FIFO ready queue of two frames, mpv swap reported at publish).

Verdict (`evidence/gtx960-laptop.txt`): `pass-with-drops-accepted`. The user's GTX 960M + HD 530 laptop never falls back to software any more. Numbers are orchestrator-computed estimates from the logs the user pasted on 2026-10-29 (durations not reported by the user):

- Cause isolated (split reason from 14-02): `vulkan/gpu-next unavailable: Vulkan 1.3 on Intel(R) HD Graphics 530, NVIDIA GeForce GTX 960M is not the compositor adapter`, so `cause=not-compositor-adapter`, not a Vulkan 1.2-only driver. Flutter ran on the HD 530; d3d11 (gpu-next) was built on that same adapter (package1, hwdec d3d11va, dec-drop 0).
- package1 (11b728a, no preference): dropped 477-561; 726-3310 with the Windows "High performance" per-app setting, which did not move the adapter. This HD-530-only case is a documented GPU-capability limitation.
- package2 (824a69e, HighPerformancePreference): compositor adapter GTX 960M. auto = vulkan gpu-next, mpv drops about 2.7-6 %; forced d3d11: drops about 25-34 %.
- package3-control (swap at publish, newest-wins): mpv drops 0 (auto) but about 10 % superseded; d3d11 about 20 % superseded.
- package4 (0e792c8, FIFO of two frames, final): auto vulkan about 82 windows (about 164 s), 24 mpv drops all in one 140 ms stall, effective about 0.5 % (about 0.25 % without the stall); forced d3d11 about 98 windows (about 196 s), 7 mpv drops, about 400 superseded, effective about 3.5 %.
- Before Phase 14 (software): dropped 1046, avsync 23.7 s.

Evidence: `.planning/phases/14-windows-native-d3d11-backend/evidence/gtx960-laptop.txt`, `laptop-package.txt`, quick dirs `261029-ljp`, `261029-nwm`, `261029-rcc`.

Open follow-ups: battery-power run on the laptop is unverified (user will re-test); HUD backend label prints `vulkan` for forced d3d11 (14-11); d3d11 on Maxwell is slower than vulkan, so 14-11 must keep Vulkan first for this GPU class; solution item 3 (cap software render size for UHD sources) stays unhandled and is out of Phase 14 scope.

---
created: 2026-10-27T00:00:00.000Z
title: GTX 960 + iGPU laptop falls back to software rendering; 4K60 unusable
area: native
severity: major
resolves_phase: 14
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

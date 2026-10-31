---
created: 2026-10-27T00:00:00.000Z
title: Example demo: larger top-left HUD panel showing more diagnostics
area: example
severity: minor
files:
  - example/lib/hud.dart
  - example/lib/main.dart
---

## Problem

User feedback on the c7e9d12 Release demo (2026-10-27): the top-left HUD panel is too small and should show more information. Long fields are truncated (for example `compositor=ANGLE(DxgiShare...` and `mistimed=-est-vf-fps` run together).

## Solution

For the next demo build: enlarge the HUD (bigger font / wider panel, no ellipsis on reason and compositor), and add more fields, e.g. full renderer reason, GPU adapter name, hwdec-current and zero-copy vs copy-back, display fps vs estimated-vf-fps, frame drop rate, A/V sync history, cache seconds, CPU-side render time. Example app only; no public API change.

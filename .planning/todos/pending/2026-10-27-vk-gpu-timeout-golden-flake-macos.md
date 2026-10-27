---
created: 2026-10-27T00:00:00.000Z
title: Stabilize the macOS vk-gpu-timeout golden flake (video_renderer_golden_vk)
area: testing
severity: minor
files:
  - native/tests/meson.build
  - .planning/phases/12-renderbackend-seam/evidence/golden-freeze.sha256
  - .planning/phases/12-renderbackend-seam/12-SECURITY.md
---

## Problem

native-verify run 40432973419 on docs-only commit 4d46d70 failed on job `macos (macos-15)`. The code tree of 4d46d70 is identical to the gated a3dc4c2.

```
video_renderer_golden_vk: GOLDEN mismatch scenario=vk-gpu-timeout line=13
```

The scenario injects a 1 s GPU timeout and then expects `event recovered` at line 13. The integration-test step was skipped after the failure.

At least four code-identical runs passed (a3dc4c2, d04ab96, c4214c0, 3b9ba73). This is a timing flake of the T-12-11 class (medium, non-blocking). T-12-11 stays CLOSED at L1 with this caveat (`12-SECURITY.md`, Notes c).

## Likely cause

Timing slack on the hosted macOS runner. The non-sanitizer slack is 250 ms (see `native/tests/meson.build`). A slow runner can push the recovery past that bound.

## Constraint

`golden_vk.cc` and `golden/vk.txt` are frozen (`.planning/phases/12-renderbackend-seam/evidence/golden-freeze.sha256`). A fix must either be a change outside the harness (for example, a larger meson slack argument for macOS) or come with an explicit unfreeze decision by the user.

## Solution

1. Run `gh run view 40432973419 --log-failed` and capture the actual vs expected trace around line 13.
2. Count reruns: rerun the macos job several times on the same SHA and record pass/fail counts.
3. If timing is confirmed, propose a macOS-only slack argument in `native/tests/meson.build` and keep the golden files byte-identical. Re-check with `sha256sum -c` against `golden-freeze.sha256`.

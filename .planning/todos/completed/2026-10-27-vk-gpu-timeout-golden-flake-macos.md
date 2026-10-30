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

## Resolution (Phase 17)

- **Decision:** `vk-flake = measure-split` (user, 2026-10-29, recorded in `.planning/phases/17-fallback-hardening-uhd-regression/evidence/decisions.txt`). The golden now judges the 1 s device wait and the 100 ms engine backoff separately, so a slow wait no longer eats the backoff bound; the combined-window failure (run 40679129407, mixed `retry-ms` 1396) is the mode this removes.
- **Files changed:** `native/tests/video_renderer_golden_vk.cc` only, with the user's explicit consent to re-freeze it (`evidence/golden-freeze-17.sha256`, only the `golden_vk.cc` line differs from the Phase 14 manifest); `golden/vk.txt`, `golden/sw.txt`, the harness and `golden_sw.cc` are byte-identical.
- **New manifest:** `.planning/phases/17-fallback-hardening-uhd-regression/evidence/golden-freeze-17.sha256` (5 files, `sha256sum -c` OK at the final audit).
- **Distribution** (`evidence/flake-timing.txt`, every run prints `GOLDEN timing-info scenario=vk-gpu-timeout`): macos-15, 10 runs, wait 1000..1113 ms, backoff 103..169 ms, 0 golden mismatches; linux x64, linux arm64 and sanitizers always wait 1000 ms and backoff 100 ms; windows jobs skip the Vulkan golden. See `final-audit.txt` (`flake summary`).
- **Caveat:** ten runs without a mismatch do not prove the flake is eliminated. Keep watching hosted macOS; reopen this todo on the first `GOLDEN mismatch scenario=vk-gpu-timeout`. Closed by the user at the Phase 17 human check (decision=phase17-close, "接受，关闭 flake 待办"); the caveat above stays: no mismatch is not the same as eliminated.

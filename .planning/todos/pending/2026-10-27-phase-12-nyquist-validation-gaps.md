---
created: 2026-10-27T00:00:00.000Z
title: Fill Phase 12 Nyquist validation gaps (RBE-01/03/04/05/07/08)
area: testing
severity: minor
files:
  - .planning/phases/12-renderbackend-seam/12-VALIDATION.md
  - packages/mpv_kit_video/src/video_renderer.h
  - native/tests/meson.build
  - example/integration_test/real_plugin_test.dart
  - .github/workflows/native-verify.yml
  - tools/constants_audit.sh
---

## Problem

The Phase 12 validation audit (`12-VALIDATION.md`: status validated, nyquist_compliant: false) found five automation gaps. User decision (verbatim): "作为额外的待办事项，等整个阶段完成后再回过头来解决". Address these after the whole phase is complete.

## Gaps

1. ① RBE-05 / RBE-03, backend bind and call-order contract. Add `native/tests/video_renderer_bind_test.cc` (or `video_renderer_backend_contract_test.cc`). A test-only Interop injects a recording RenderBackend through the virtual `CreateBackend` / `BackendCandidates` (`packages/mpv_kit_video/src/video_renderer.h` ~:79, :85). Assert that render, report_swap and render_context_free run between BindThread and UnbindThread on the render thread. Assert the order Create → AllocTargets → FrameFor → Render → Wait → Release → destroy. Run: `meson test -C tests-out video_renderer_bind_test`.
2. ② RBE-07. Add `example/integration_test/backend_reason_test.dart`. It asserts the reason regex and that backend is one of {vulkan, software} on the real plugin. Add a native-verify integration-test step for it.
3. ③ RBE-08. Add `example/integration_test/api_override_test.dart`, run with `MPV_KIT_VIDEO_API=software`. Expect backend `software` and a reason that starts with `software (sw) on cpu`. Add it as a CI step on ubuntu, windows and macos.
4. ④ RBE-04. Add `tools/constants_audit.sh` and `sha256sum -c .planning/phases/12-renderbackend-seam/evidence/golden-freeze.sha256` to the native-verify patch-drift job (checkout with `fetch-depth: 0`).
5. ⑤ RBE-01. Add a scheduled / workflow_dispatch job that runs `impeller_smoke_test` in cycles mode for 100 rounds on lavapipe.

## Solution

Write each test so that it can fail, run it in CI, then set `nyquist_compliant: true` in `12-VALIDATION.md`. Related: `2026-10-27-diagnose-second-controller-first-frame-stall-in-resize-front.md` (RBE-01 real-GPU finding).

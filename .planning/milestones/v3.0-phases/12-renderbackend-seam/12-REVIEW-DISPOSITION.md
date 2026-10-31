---
phase: 12-renderbackend-seam
review: 12-REVIEW.md (commit ae5c286)
ui_review: 12-UI-REVIEW.md
decided: 2026-10-27
decision: "a"
followup_todo: .planning/todos/pending/2026-10-27-phase-12-code-review-followups.md
---

# Phase 12: Code Review Disposition

The user's decision, verbatim: **"a"**. That means: fix CR-01 now, with the same discipline as the earlier fixes (a new test RED locally, then a minimal fix, then the CI gate), and send the WARNING and INFO findings to a todo.

| Finding | Severity | Disposition | Where |
|---|---|---|---|
| CR-01 Software path frees retired pixels the last AcquireFront() handed out | critical | **fixed** in `025bdad` (RED `2b15969`, evidence `84e0952`) | `video_renderer.cc` `SoftwareBackend::AllocTargets` / `FreeRetired`; test `native/tests/video_renderer_sw_hold_front_test.cc` |
| WR-01 Deferred-release contract does not match either backend | warning | **fixed** in `025bdad` (comment now states each backend's real rule) | `render_backend.h` |
| WR-02 Reason fields not UTF-8 checked; engine trusts backend `why` | warning | deferred | followup todo |
| WR-03 Renderer tests inherit `MPV_KIT_VIDEO_API` | warning | deferred | followup todo |
| WR-04 Dispose frees software pixels during the last upload | warning | deferred | followup todo |
| WR-05 `SoftwareBackend::AllocTargets` can throw `bad_alloc` on the render thread | warning | deferred | followup todo |
| WR-06 `Start()` lets `std::system_error` escape | warning | deferred | followup todo |
| IN-01 Redundant `retired_front_` resets | info | deferred | followup todo |
| IN-02 Hard-coded "Vulkan" in generic log lines | info | deferred | followup todo |
| IN-03 `wire_name()` dereferences `render_backend_` unconditionally | info | deferred | followup todo |
| IN-04 Stale `video_renderer.h` file header | info | deferred | followup todo |
| IN-05 Stale line reference in `impeller_smoke_test.dart` | info | deferred | followup todo |
| IN-06 No echo test for `;`, control and non-ASCII bytes | info | deferred | followup todo |
| UI-W1 `MpvVideoBackend.vulkan` doc (means any GPU zero-copy API) | warning (UI) | deferred | followup todo |
| UI-W2 Package README ADR link pinned to `main` | warning (UI) | deferred | followup todo |
| UI-W3 No runtime hint when `MPV_KIT_VIDEO_API` is set | warning (UI) | deferred | followup todo |
| CR-01-R1 A frame from three generations back can still be freed early (found during the fix) | residual | deferred (needs a seam decision) | followup todo |
| CR-01-R2 Two retired generations held after resize, failed render, resize until the next resize | residual | deferred | followup todo |

"Followup todo" is `.planning/todos/pending/2026-10-27-phase-12-code-review-followups.md`.

## CR-01 fix scope

`SoftwareBackend` now keeps the generation retired by the previous reallocation for one more reallocation (`older_`), and `FreeRetired()` drops both generations. This covers both traces in the review:

1. resize, failed render, resize;
2. two resizes before the compositor takes a new frame, whether the frame it holds is a ring frame or the retired front.

A frame from three generations back (CR-01-R1) is not covered. Covering it precisely needs a seam change, which this fix was not allowed to make. Vulkan's behaviour is unchanged.

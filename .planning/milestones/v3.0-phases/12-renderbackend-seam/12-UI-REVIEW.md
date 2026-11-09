# Phase 12 — UI Review

**Audited:** 2026-10-27
**Baseline:** abstract 6-pillar standards (no UI-SPEC; phase is native renderer work)
**Screenshots:** not captured (Flutter desktop plugin; no web dev server on 3000/5173/8080)
**Interaction captures:** off (workflow.ui_interaction_capture is false)

Scope check: `git diff --stat 2ed9c80 HEAD -- '*.dart'` shows no changes under `example/lib` and no widget, layout or theme code. The only Dart change in shipped code is `packages/mpv_kit_video/lib/src/video_controller.dart` (private wire-name set, docs). The rest is tests. The user-visible surface is developer-facing text: the `reason` string (ADR 0004 grammar), dartdoc, and the two READMEs. Visuals, Color, Typography and Spacing therefore have no changed surface. They are scored N/A and leave the baseline unchanged. The total is out of the two pillars that were scored.

---

## Pillar Scores

| Pillar | Score | Key Finding |
|--------|-------|-------------|
| 1. Copywriting | 3/4 | `reason` grammar is precise and well documented; the `vulkan` enum name now covers D3D11/OpenGL, and the package README links to an ADR on `main` that does not exist there yet |
| 2. Visuals | N/A | No widget/layout change |
| 3. Color | N/A | No theme/color change |
| 4. Typography | N/A | No text-style change |
| 5. Spacing | N/A | No layout change |
| 6. Experience Design | 3/4 | Strict failure (`render_init`) is explicit and tested; the no-fallback `MPV_KIT_VIDEO_API` is a sharp edge if it leaks into shipped apps |

**Overall: 6/8 scored (4 pillars N/A, no change); 24-scale not meaningful for this phase**

---

## Top 3 Priority Fixes

1. **WARNING: `MpvVideoBackend.vulkan` now means "any GPU zero-copy API"** — a developer who reads `backend == vulkan` on a D3D11 path (Phase 14) is misled. The API freeze prevents a rename, so make the enum dartdoc lead with "GPU zero-copy (not necessarily Vulkan)". Also add a small helper in the docs or README showing `reason.split(' ').first` to get the real API.
2. **WARNING: package README links to `blob/main/docs/adr/0004-...`** (`packages/mpv_kit_video/README.md`). On pub.dev this link stays dead until the branch merges, and it points to whatever `main` says later, not to the published version. Pin the link to a tag or ship the grammar inline.
3. **WARNING: `MPV_KIT_VIDEO_API` has no runtime warning when set** — if an end user's environment sets it, `create` fails with no fallback. Today the only guardrail is "leave it unset" in the README. Have the one-line `debugPrint` say when the override is active, so the cause shows up in support logs.

---

## Detailed Findings

### Pillar 1: Copywriting (3/4)
- Good: the ADR 0004 grammar `api (renderer) on device *( "; " api/renderer unavailable: why )` is defined formally, with sanitising rules (`;` becomes `,`, control characters become spaces). It is quoted the same way in `README.md`, `packages/mpv_kit_video/README.md` and `video_controller.dart` (the `reason` dartdoc).
- WARNING: the enum dartdoc in `video_controller.dart` (above `enum MpvVideoBackend`) is Chinese-only, while the `reason` docs are English. That matches the file's mixed convention, but the redefinition of `vulkan` is the one fact English readers must not miss.
- WARNING: there is a dead or moving ADR link in the package README (Fix 2).
- Minor: `unknown renderer` contains a space inside the `renderer` token, so naive splitting on spaces breaks. Document it as a known case.

### Pillars 2–5: N/A
No `.dart` widget, theme, style or padding change in this phase (`example/lib` untouched). The baseline is unchanged and was not re-audited.

### Pillar 6: Experience Design (3/4)
- Good: an unknown wire name releases the texture and throws `PlatformException('render_init')`. It never silently downgrades. This is covered by `controller_channel_test.dart` (+100 lines), and the enum values are pinned in `video_controller_test.dart`.
- Good: software fallback is still reported as a typed event and as `reason` trails.
- WARNING: the strict `MPV_KIT_VIDEO_API` mode has no runtime signal that it is active (Fix 3).

---

## Files Audited
- packages/mpv_kit_video/lib/src/video_controller.dart
- README.md
- packages/mpv_kit_video/README.md
- docs/adr/0004-render-backend-reporting.md
- example/integration_test/* (diff stat only; tests, not shipped UI)
- packages/mpv_kit_video/test/controller_channel_test.dart, video_controller_test.dart (diff stat)

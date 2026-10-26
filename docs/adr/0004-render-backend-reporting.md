# ADR 0004 — Render backend reporting under the API freeze

Status: accepted
Date: 2026-10-26
Related: ADR 0003 (Windows composition path), `.planning/REQUIREMENTS.md`
RBE-07 / RBE-08, `.planning/research/SUMMARY.md` (Open Decisions 1 and 3).

## Context

`MpvVideoController.backend` is a public enum with exactly two values,
`MpvVideoBackend { vulkan, software }`. The public API is frozen: no member
may be added or removed. Applications are entitled to switch over it
exhaustively, so a third value would break their code at compile time.

v3.0 adds GPU zero-copy backends that are not Vulkan: native D3D11 on
Windows (Phase 14) and OpenGL on Linux (Phase 15). The application, the CI
and a support engineer still need to know which graphics API is actually in
use, and why earlier candidates were rejected.

Phase 2 (STAB-04) made the `create` response strictly validated: a
`backend` value the Dart side does not know is a protocol break and throws
`PlatformException(code: 'render_init')` after releasing the native
context. It is never treated as a silent downgrade to software. That rule
stays.

## Decision 1 — The public enum does not change

`MpvVideoBackend` keeps exactly `vulkan` and `software`, in that order.
`MpvVideoBackend.vulkan` is redefined as **the GPU zero-copy backend**: the
frame is rendered on the GPU and shared with the Flutter compositor without
a CPU copy, through Vulkan or a platform-native graphics API. The concrete
API is the first token of `MpvVideoController.reason`.
`MpvVideoBackend.software` stays CPU rendering (`MPV_RENDER_API_TYPE_SW`).

A test that runs without libmpv (`packages/mpv_kit_video/test/
video_controller_test.dart`) pins `MpvVideoBackend.values` to
`['vulkan', 'software']`.

## Decision 2 — Private wire names, exact match

The native plugins report one of exactly four private wire names in the
`backend` field of the `create` response:

| Wire name | `MpvVideoBackend` | Graphics API |
|---|---|---|
| `vulkan` | `vulkan` | Vulkan |
| `d3d11` | `vulkan` | Direct3D 11 (Phase 14, Windows) |
| `opengl` | `vulkan` | OpenGL (Phase 15, Linux) |
| `software` | `software` | CPU |

Matching is exact and case-sensitive. There is no case folding, no prefix
match and no catch-all. Any other value (`D3D11`, the empty string,
`metal`, `garbage`, …) is a protocol break. Dart releases the texture the
response named and throws `PlatformException(code: 'render_init')`. A
future backend has to be added to this set in Dart first.

The wire names are not public API. Applications read the enum and the
`reason` string.

## Decision 3 — `reason` grammar

```
reason = head *( "; " trail )
head = api " (" renderer ") on " device
trail = api "/" renderer " unavailable: " why
```

- `api` is one of the four wire names: `vulkan`, `d3d11`, `opengl`,
  `software`.
- `renderer` is `gpu-next`, `gpu`, `sw` or `unknown renderer`. The last one
  is used when the render context cannot say which renderer serves.
- The head of the software backend is always `software (sw) on cpu`.
- The trails list every candidate ranked before the winner, in
  candidate-chain order: each one either failed or was excluded by
  `MPV_KIT_VIDEO_API`. Candidates ranked after the winner do not appear.
- **Sanitising.** In `device` and in `why`, every `;` is replaced by `,`
  and every control character (U+0000–U+001F) by a space, so `"; "`
  always splits trails and the string is always one line.
- **`why` vocabulary.** A `why` is one of:
  - `mpv_render_context_create: <mpv_error_string>`
  - a device initialisation error verbatim, for example
    `Vulkan loader not found` or
    `no Vulkan 1.3 device shareable with the compositor`
  - `platform interop unavailable: <why>`
  - `platform has no Vulkan interop`
  - `excluded by MPV_KIT_VIDEO_API=<value>`

Examples:

```
vulkan (gpu-next) on NVIDIA GeForce RTX 4060
software (sw) on cpu; vulkan/gpu-next unavailable: Vulkan loader not found; vulkan/gpu unavailable: Vulkan loader not found
software (sw) on cpu; vulkan/gpu-next unavailable: excluded by MPV_KIT_VIDEO_API=software; vulkan/gpu unavailable: excluded by MPV_KIT_VIDEO_API=software
```

When every candidate fails there is no head. The plugin returns
`PlatformException(code: render_init, message: no usable render backend)`,
and its `details` are the trails joined with `"; "`.

The grammar is what later phases assert in CI by prefix: the native
assembly in 12-06 and the golden expectations under `native/tests/golden/`
follow this text.

## Decision 4 — `MPV_KIT_VIDEO_API` (native, strict)

`MPV_KIT_VIDEO_API` is a native environment variable that forces one
graphics API. It exists so that CI can verify each backend on its own. It
adds no Dart API.

- It is read once per `create`, in `VideoRenderer::Start`.
- Unset or empty means the full candidate chain.
- A value must match `^[a-z0-9-]{1,16}$`. Anything else is an unknown
  value. When it is echoed (in `excluded by MPV_KIT_VIDEO_API=<value>` or
  in an error), every character outside that set is replaced by `?` and the
  echo is truncated to 16 characters.
- Only candidates whose `api` equals the value are tried. There is **no
  fallback to any other API, software included**. If no candidate matches,
  or every matching candidate fails, the result is `render_init`. The
  excluded candidates appear as `excluded by MPV_KIT_VIDEO_API=<value>`
  trails.
- It intersects with the renderer selection made on the Dart side
  (`renderer:` / `MPV_KIT_VIDEO_RENDERER`). An empty intersection is also
  `render_init`. For example, `MPV_KIT_VIDEO_API=software` with
  `MPV_KIT_VIDEO_RENDERER=gpu-next` fails.
- Effective values in Phase 12, on all three platforms: `vulkan` and
  `software`. `d3d11` (Phase 14, Windows) and `opengl` (Phase 15, Linux)
  start to work as soon as those phases add their candidates to the chain.
  Until then they fail with `render_init`.

`MPV_KIT_VIDEO_RENDERER` is a graceful override: it still falls back to
software. `MPV_KIT_VIDEO_API` is a diagnostic switch: it fails loudly
rather than report a backend other than the one asked for.

## Decision 5 — `auto` order is data: renderer quality first, API second

`auto` tries candidates by renderer quality first and graphics API second.
gpu-next on any API comes before gpu on any API, and software is last. The
candidate chain is data supplied by the platform `Interop`, not control
flow. Adding or rolling back a backend means adding or removing one entry.
A platform moves its `auto` choice to a native API only when that API
offers the better renderer. For example, Windows prefers D3D11 over Vulkan
only once gpu-next runs on D3D11. Until then D3D11 is only a `gpu`-tier
candidate.

## Consequences

- Existing applications compile and behave unchanged. Code that checks
  `backend == MpvVideoBackend.vulkan` keeps meaning "GPU zero-copy, not the
  slow CPU path", which is the distinction it needed.
- The real API is visible only through `reason`. Callers that care parse
  its first token. This ADR fixes the grammar so that this is reliable.
- A newer plugin with a backend this Dart version does not know fails
  `create` with `render_init` instead of showing a misleading value. The
  plugin and Dart sides ship in lockstep (the workspace versions are
  pinned together), so this happens only when the versions are mixed.
- CI can prove each backend separately with `MPV_KIT_VIDEO_API` and a
  prefix check on `reason`, without depending on what `auto` happens to
  pick on a runner.

## Alternatives rejected

- **New enum values (`d3d11`, `opengl`).** This breaks exhaustive switches
  in user code and the API freeze test. Rejected under the freeze.
- **Relaxed validation** (unknown backend means software, or means GPU).
  This silently hides a protocol break, which is what STAB-04 removed.
- **Prefix or case-insensitive matching** (`d3d11*`, `D3D11`). This makes
  the accepted set open-ended and lets a malformed native value through.

## Re-evaluation triggers

- A major version that allows breaking API changes. The enum could then
  carry the API directly.
- Flutter gains a plugin API for reporting the texture's backend, which
  would make the private wire protocol redundant.

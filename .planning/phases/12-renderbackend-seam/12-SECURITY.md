---
phase: "12"
slug: "renderbackend-seam"
status: verified
# threats_open = count of OPEN threats at or above workflow.security_block_on severity (the blocking gate)
threats_open: 0
threats_total: 38
threats_closed: 38
asvs_level: 1
block_on: high
register_authored_at_plan_time: true
audited: "2026-10-27"
verdict: SECURED
created: "2026-10-27"
---

# Phase 12 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.
> Register built from the `<threat_model>` STRIDE tables in `12-01-PLAN.md` .. `12-12-PLAN.md` (authored at plan time).
> 38 register entries: 27 numbered threats (T-12-01 .. T-12-27; T-12-27 lives in 12-01) plus T-12-SC once per plan (x12).

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| Workflow edits → CI verdict (12-01) | Whoever edits a workflow can turn red into green without fixing anything | CI configuration / job conclusions |
| GitHub Release SHA256SUMS → pin check (12-01) | `pin_bundles --check` reads release checksums over the network | Public checksums (integrity data) |
| gh CLI output → ci_gate.sh verdict (12-01) | The gate decides from gh JSON and logs | Job conclusions |
| Push → `origin/feat/mpv-master-upgrade` (12-01) | RED commits must not trigger hosted runs without authorization | Commits / CI triggers |
| Probe image → composite verdict (12-02) | An image may lack the external texture; 0.0 is not a black frame | Pixel samples |
| diag/cycles modes → D-05 verdict (12-02) | Forensic-only modes must not reach `_classify` | Test verdicts |
| dart:ffi Win32 calls → harness process (12-02) | Window capture calls user32/gdi32/kernel32 directly | Native memory / handles |
| Native plugin → Dart create response (12-03, 12-10) | Version skew or bugs can yield arbitrary strings | `backend` / `reason` fields |
| Public Dart API → application code (12-03) | Enum value order is a contract for exhaustive switches | `MpvVideoBackend` |
| Harness output / local environment → run validity (12-04, 12-08, 12-12) | Hidden window, lock screen or GPU load invalidates data silently | Run ledgers |
| Golden files / fake timing → test verdict (12-05, 12-07) | Goldens must be read-only and frozen; timing asserts may flake | Expected traces |
| Driver / mpv strings → reason → CI asserts and UI (12-06) | Device names, HRESULT text, mpv errors may contain separators | Diagnostic strings (low sensitivity) |
| Render thread ↔ raster thread (12-07, 12-11) | Shared ring images and swap counts cross threads | Frame images / counters |
| Engine ↔ backend lifecycle (12-09, 12-11) | Render context must die before the device | Native object lifetimes |
| Process environment → backend selection (12-10) | `MPV_KIT_VIDEO_API` forces a backend; the value is echoed | Env var value (trusted local boundary) |
| Per-plan verification → phase verdict (12-12) | Only the final-HEAD full gate proves the combination | CI conclusions / audits |

---

## Threat Register

| Threat ID | Plan | Category | Component | Severity | Disposition | Mitigation / Evidence | Status |
|-----------|------|----------|-----------|----------|-------------|-----------------------|--------|
| T-12-01 | 12-01 | Repudiation | flutter-plugin.yml / native-verify.yml fixes | high | mitigate | One step reordered, one working directory changed; `tools/check_matrix.py` still audits continue-on-error; `ci_gate.sh` treats any non-success (incl. skipped) as failing and logs each verdict to `ci-runs.txt` | closed |
| T-12-02 | 12-01 | Tampering | `tools/pin_bundles.dart --check` network input | medium | accept | Tool only compares SHA256SUMS with committed pins, downloads/executes nothing; unchanged in Phase 12 (see Accepted Risks) | closed |
| T-12-27 | 12-01 | Elevation of Privilege | Push to `origin/feat/mpv-master-upgrade` (incl. RED commits) | high | mitigate | `push-authorization.txt`: push-green-only, `red_evidence=local-only`; no hosted run on RED commits f6df1fa, c452ccd, f9b559f, 149f0be, 029da25, 41bfa89; authorization record precedes the first gated SHA | closed |
| T-12-SC | 12-01 | Tampering | npm/pip/cargo installs | high | mitigate | No packages installed, no new third-party `uses:` actions; deviation: CI apt runtime libs only from the signed Ubuntu archive (bbb071e, see Notes a) | closed |
| T-12-03 | 12-02 | Repudiation | diag / cycles modes | high | mitigate | `impeller_smoke_modes.dart` never calls `_classify`; unknown modes throw `StateError` | closed |
| T-12-04 | 12-02 | Spoofing | Part 2 pixel probe | high | mitigate | `probe-control.txt`: readiness gate, three-way control, pass rule unchanged (`pass_rule_changed: false`) | closed |
| T-12-05 | 12-02 | Denial of Service | Window-capture native memory | low | mitigate | HeapAlloc/CreateDIBSection/DC released in `finally`; harness-only, exits at test end | closed |
| T-12-SC | 12-02 | Tampering | npm/pip/cargo installs | high | mitigate | No new pub dependencies (only `dart:ffi`, `dart:io`, `dart:ui`, Flutter test libs); no pubspec/manifest changes | closed |
| T-12-06 | 12-03 | Spoofing | `MpvVideoController.create` backend validation | high | mitigate | `video_controller.dart` `_gpuWireNames` strict, case-sensitive set; other values → render_init + textureId release; tests cover `D3D11`, empty, `metal`, `garbage`, concurrency | closed |
| T-12-07 | 12-03 | Tampering | Public enum `MpvVideoBackend` | medium | mitigate | Always-on enum value-order freeze test; `api_freeze_test.dart` byte-identical to 3a5f450 | closed |
| T-12-SC | 12-03 | Tampering | npm/pip/cargo installs | high | mitigate | No new pub dependencies | closed |
| T-12-08 | 12-04 | Repudiation | baseline-runs.txt / baseline doc | high | mitigate | Baseline/postfix/final run ledgers with `attempt` / `forensics` / `task3_verify` lines; blocking-human checkpoint confirmed run conditions | closed |
| T-12-09 | 12-04 | Spoofing | libmpv and native code under test | high | mitigate | Harness identity gate (resolvedPath == MPV_KIT_LIBMPV_PATH, backend == vulkan) kept; `git diff --quiet 3a5f450 <baseline_sha>` on the native render path before/after | closed |
| T-12-SC | 12-04 | Tampering | npm/pip/cargo installs | high | mitigate | No packages installed | closed |
| T-12-10 | 12-05 | Repudiation | Golden expectation files | high | mitigate | Golden harness read-only, no update mode; `evidence/golden-freeze.sha256` 5/5 OK | closed |
| T-12-11 | 12-05 | Denial of Service | Time-dependent assertions | medium | mitigate | Bounds-only asserts, expectations in golden, sanitizer slack 1000 ms, poke-sequence barriers; closed at L1 with the macOS flake caveat (Notes c) | closed |
| T-12-SC | 12-05 | Tampering | npm/pip/cargo installs | high | mitigate | No packages installed; vendored Vulkan headers/volk, stdlib and existing meson deps only | closed |
| T-12-12 | 12-06 | Tampering | reason assembly (device / why fields) | medium | mitigate | `SanitizeReasonField` maps `;` → `,` and control chars → space; golden + CI regex assert the grammar | closed |
| T-12-13 | 12-06 | Information Disclosure | Driver names / error text in reason | low | accept | GPU name, HRESULT, mpv error text only; no paths, user data or secrets; unchanged exposure (see Accepted Risks) | closed |
| T-12-SC | 12-06 | Tampering | npm/pip/cargo installs | high | mitigate | No packages installed | closed |
| T-12-14 | 12-07 | Elevation of Privilege | `VulkanContext::AllocateRing` retained slot (raster-thread UAF / double free) | high | mitigate | `vulkan_backend.cc` `*keep_retired = SharedImage{}` (e3ef12b); red-first proof in `red-local-12-07.log`; sanitizer job runs all goldens | closed |
| T-12-15 | 12-07 | Spoofing | FakeVulkanInterop destroy counting | medium | mitigate | Harness destroy registry (never freed), repeat destroy counted only; `USE AFTER DESTROY` checks on RetainFrame / AcquireFront | closed |
| T-12-SC | 12-07 | Tampering | npm/pip/cargo installs | high | mitigate | No packages installed | closed |
| T-12-16 | 12-08 | Repudiation | Soak abort conclusion | high | mitigate | Pre/post-fix ledgers with paired compare lines, same command and environment; blocking-human checkpoint | closed |
| T-12-17 | 12-08 | Tampering | Pre-relocation reference code state | medium | mitigate | native_diff_vs_baseline limited to video_renderer.cc/.h and vulkan_backend.cc; golden-freeze checked before/after runs | closed |
| T-12-SC | 12-08 | Tampering | npm/pip/cargo installs | high | mitigate | No packages installed | closed |
| T-12-18 | 12-09 | Tampering | Constants and reasons in the relocation commit | high | mitigate | `constants_audit.sh` ok vs 3a5f450; golden-freeze sha256 + golden traces compare reasons verbatim | closed |
| T-12-19 | 12-09 | Elevation of Privilege | Destructor order (Release → backend dtor) | high | mitigate | `render_backend.h` teardown contract; destructor join → Release → reset; teardown goldens under sanitizer | closed |
| T-12-SC | 12-09 | Tampering | npm/pip/cargo installs | high | mitigate | No packages, no new build sources | closed |
| T-12-20 | 12-10 | Tampering | `MPV_KIT_VIDEO_API` parsing | medium | mitigate | Whitelist `[a-z0-9-]`, max 16; malformed → no candidate; echo sanitized/truncated; `api_override.txt` | closed |
| T-12-21 | 12-10 | Repudiation | Forced-backend CI verdict | high | mitigate | Forced run never falls back to another API (test asserts no other creation call); trail reported as details | closed |
| T-12-22 | 12-10 | Spoofing | Plugin `backend` field | medium | mitigate | Produced only from the backend's `wire_name()`; Dart strict set (T-12-06) | closed |
| T-12-SC | 12-10 | Tampering | npm/pip/cargo installs | high | mitigate | No packages installed | closed |
| T-12-23 | 12-11 | Denial of Service | Swap drain ↔ flip_page coupling | medium | mitigate | Swaps reported on the render thread before update, no lock held across mpv calls; final-runs 0 drops vs the 12-08 reference | closed |
| T-12-24 | 12-11 | Elevation of Privilege | Render-thread free and destructor order | high | mitigate | Affinity test checks free exactly once after the last render; join before backend destruction; sanitizer runs all native tests | closed |
| T-12-SC | 12-11 | Tampering | npm/pip/cargo installs | high | mitigate | No packages installed | closed |
| T-12-25 | 12-12 | Repudiation | Phase close-out verdict | high | mitigate | Final full gate 15/15 on a3dc4c2 (`--jobs-success '.'`); final-audit 7/7 re-runnable and on disk; blocking-human checkpoint | closed |
| T-12-26 | 12-12 | Tampering | Cross-plan drift of constants, goldens, public API | high | mitigate | Close-out re-ran constants_audit (ok), golden-freeze (5/5 OK) and the API compare vs 3a5f450 | closed |
| T-12-SC | 12-12 | Tampering | npm/pip/cargo installs | high | mitigate | No packages installed; no new `uses:` actions; no pubspec/manifest changes | closed |

*Status: open · closed · open — below high threshold (non-blocking)*
*Severity: critical > high > medium > low — only open threats at or above workflow.security_block_on count toward threats_open*
*Disposition: mitigate (implementation required) · accept (documented risk) · transfer (third-party)*

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| AR-12-01 | T-12-02 (Tampering, medium) | `pin_bundles --check` reads SHA256SUMS over the network but only compares it with the committed pins; downloads/executes nothing; tool unchanged in Phase 12 | Plan 12-01 threat model (plan-time disposition) | 2026-10-27 |
| AR-12-02 | T-12-13 (Information Disclosure, low) | The reason string contains GPU name, HRESULT and mpv error text only; no paths, user data or secrets; same exposure as before Phase 12 | Plan 12-06 threat model (plan-time disposition) | 2026-10-27 |

*Accepted risks do not resurface in future audit runs.*

---

## Notes

a. **T-12-SC (12-01) wording deviation.** The plan stated that no packages are installed. The executed fix added CI apt installs of runtime libraries, sourced only from the signed Ubuntu archive (bbb071e). There are no npm/pip/cargo installs and no new third-party actions, so this is treated as within the mitigation's intent.

b. **User decisions that changed mitigations.**
   - RED evidence is local-only: RED commits were never pushed for hosted runs (`push-authorization.txt`, `red_evidence=local-only`).
   - Gates for 12-09, 12-10 and 12-11 were deferred; all were later recorded as CI-GATE ok.
   - windows-2025 `golden_vk` is accepted as OK-or-SKIP.

c. **Warning — macOS golden flake (T-12-11 class).** native-verify run 40432973419 on docs-only commit 4d46d70 (code tree identical to the gated a3dc4c2) FAILED on job macos (macos-15): `video_renderer_golden_vk` `GOLDEN mismatch scenario=vk-gpu-timeout line=13`; the integration-test step was then skipped. Code-identical runs on a3dc4c2, d04ab96, c4214c0 and 3b9ba73 were green, so this is a timing flake (medium, non-blocking). T-12-11 stays CLOSED at L1 with this caveat. Tracked in `.planning/todos/pending/2026-10-27-vk-gpu-timeout-golden-flake-macos.md`.

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-10-27 | 38 | 38 | 0 | Security Audit (gsd-security-auditor, ASVS L1, block_on high), verdict SECURED |

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-10-27

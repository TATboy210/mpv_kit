---
phase: 10-composition-spike
reviewed: 2026-10-25T03:10:00Z
depth: standard
files_reviewed: 4
files_reviewed_list:
  - .github/workflows/flutter-plugin.yml
  - docs/adr/0003-windows-composition-path.md
  - docs/reverse-engineering/03-flutter-windows-texture-consumption.md
  - example/integration_test/impeller_smoke_test.dart
findings:
  critical: 3
  warning: 7
  info: 9
  total: 19
status: issues_found
---

# Phase 10: Code Review Report

**Reviewed:** 2026-10-25T03:10:00Z
**Depth:** standard
**Files Reviewed:** 4
**Status:** issues_found

## Summary

Phase 10 ships three things: a Windows-only Impeller smoke harness, an ADR that
classifies the smoke pair as `inconclusive`, and a one-line CI version bump
(3.47.6 -> 3.47.8) plus the two evidence documents.

The ADR and the REA report are unusually careful: every RVA, hash, file size
and pseudocode claim I spot-checked against
`.planning/phases/10-composition-spike/evidence/` holds (function RVAs,
`SYMBOL_COUNT: 684430`, artifact sha256/size, the `0xc2cbe0` ICF note, the
`6f15aaf2-…` keyed-mutex `QueryInterface`, the `SurfaceD3D` `0x33a3`/`0x3200`
split, the `GL_RGBA8` gate at `0x8058`, `CompositorLatency() == 4`,
`kMaxQuarantine == 4`, ring 7, and the `docs/perf` baseline's missing renderer
line). The core technical conclusions are corroborated by the evidence.

The implementation does not match that quality bar:

1. The harness's only result channel (`stdout.writeln`) is not forwarded by
   `flutter test -d windows`, which the committed evidence itself proves. Every
   BENCH line — including the unconditionally emitted preflight line — is
   absent from both run logs while `debugPrint` output from the same process is
   present.
2. The harness's part-1 readiness predicate requires a `resize` event that the
   harness never causes, so the D-04 workload is unreachable in every run. The
   ADR records this, but the submitted code still contains it.
3. The CI step that is supposed to point the tests at the hook-bundle libmpv
   writes MSYS POSIX paths into `GITHUB_ENV`/`GITHUB_PATH`; the consuming
   Windows steps run under `pwsh`, where `/d/...` is not a usable path. With
   `MPV_KIT_REQUIRE_LIBMPV=1` that converts a missing library into a hard test
   failure.

The docs' substance is sound; their evidence paths are broken (they point at
`docs/.planning/...` and non-existent `evidence/` directories), and the ADR's
Phase 11 precondition omits the reporting-channel fix, so a "corrected" harness
would still be classified `inconclusive` under the phase's own rule.

## Narrative Findings (AI reviewer)

### CR-01: BENCH results are written to a channel the documented run transport drops

**File:** `example/integration_test/impeller_smoke_test.dart:52-54`
**Severity:** BLOCKER

**Issue:** `_emitBench` uses `stdout.writeln('BENCH impeller ...')`. The
committed evidence proves this channel does not reach the `flutter test -d
windows` log:

- `_emitBench({'stage': 'preflight', ...})` is called unconditionally at
  `run()` (`:118-124`) before any gate, and the catch block emits an
  `inconclusive` line (`:154-160`); both are unreachable only if the harness
  never starts.
- `.planning/phases/10-composition-spike/evidence/impeller-on.log` and
  `impeller-off.log` contain **zero** `BENCH` lines, yet both contain
  `debugPrint` output from the same app process
  (`mpv_kit_video: vulkan (vulkan (gpu-next) on NVIDIA GeForce RTX 4060 Laptop
  GPU)`), and `impeller-run-on.log` contains the engine's `IMPORTANT` log line.
- The sibling harness `example/integration_test/playback_bench_test.dart:113,
  133,163` uses `print('BENCH ...')`, and those lines are how
  `docs/perf/2026-10-24-baseline.md` got its numbers.

`stdout` bypasses the engine log; `print`/`debugPrint` go through it. The
harness's `soak-start`, `soak-progress`, and `complete` payloads (rounds,
seconds, `pixelProbe`, `result`) are therefore all lost — even on a successful
run. The ADR records "no BENCH line ... count 0" as an evidence gap but does
not diagnose that the channel itself is dead. The 10-03 rule "no BENCH line ⇒
inconclusive" can never be satisfied on this transport.

**Fix:** Use the engine log path (`print` or `debugPrint`), matching the
sibling harness, or write the JSON to a file whose path is supplied via an
environment variable and flush/close it:

```dart
void _emitBench(Map<String, Object?> payload) {
  print('BENCH impeller ${jsonEncode(payload)}');
}
```

Then re-run to prove the preflight line appears in the captured log.

---

### CR-02: Part-1 readiness gate is unsatisfiable — the D-04 workload can never run

**File:** `example/integration_test/impeller_smoke_test.dart:218-235`
**Severity:** BLOCKER

**Issue:** The part-1 predicate requires `_resizeEvents > resizeBaseline`, but
nothing calls `setSize` before part 1. `VideoRenderer::SetSize` is the only
writer of `width_`/`height_` (`packages/mpv_kit_video/src/video_renderer.cc:166-176`),
the renderer starts with `width_ == height_ == ring_w_ == ring_h_ == 0`, and
`resize` is emitted only when `w != ring_w_ || h != ring_h_`
(`video_renderer.cc:478-500`, emit at `:541`). With both sides zero the
condition is false, so no `resize` event can ever be produced in part 1. The
harness therefore throws at `:228-235` in every run, never reaches part 2/3,
the pixel probe, or any D-05 evidence.

This is confirmed by the committed evidence: both logs show
`part 1 readiness timeout: params=1920x1080 fps=30.000000000000018
resizeEvents=0`. The ADR names this as a harness defect and defers the fix to
Phase 11, but the submitted source still contains it, and the phase's stated
deliverable (an Impeller/control smoke pair exercising the workload) is
therefore not fulfilled — the pair exercises nothing.

Separately, `_parts['oneFrame'] = 'ok'` is set without ever verifying a
composed frame; the gate only checks mpv properties plus the impossible resize.

**Fix:** call `setSize` before the gate (and take the baseline beforehand), and
gate on a first composed frame as well:

```dart
final resizeBaseline = _resizeEvents;
await controller.setSize(1920, 1080); // video_renderer.cc:166 is the only writer
final part1Ready = await _waitUntil(() {
  final params = player.videoParams.value;
  final fps = player.mpv.tryGetProperty('estimated-vf-fps');
  return params?.width == 1920 &&
      params?.height == 1080 &&
      fps is num && fps > 0 &&
      _resizeEvents > resizeBaseline;
}, timeout: const Duration(seconds: 30));
```

Alternatively drop the resize condition and gate on `estimated-vf-fps > 0`
plus a first rendered frame, as the ADR itself proposes.

---

### CR-03: CI writes POSIX `/d/...` paths on the Windows runner; the consuming steps run under pwsh

**File:** `.github/workflows/flutter-plugin.yml:51-60`
**Severity:** BLOCKER

**Issue:** The step runs under `shell: bash` and computes
`dir=$(cd "$(dirname "$lib")" && pwd)`. In the Git-Bash (MSYS) environment used
on Windows runners this yields a POSIX path — verified on this checkout:
`pwd` prints `/d/mpv_kit` and `pwd -W` prints `D:/mpv_kit`. The step then
writes:

- `MPV_KIT_LIBMPV_PATH=/d/a/<repo>/.dart_tool/hooks_runner/.../libmpv-2.dll`
  into `$GITHUB_ENV` (`:58`), and
- `/d/a/<repo>/.dart_tool/hooks_runner/.../lib` into `$GITHUB_PATH` (`:59`).

The consuming steps (`Analyze plugin and example`, `:61-66`, and `Build
example`, `:67-69`) do not set `shell:`, so on Windows they run under the
default `pwsh` shell. MSYS path conversion only happens when an MSYS process
spawns a native process; the runner forwards the stored strings to
`flutter.bat`/`dart.exe` verbatim, where a leading `/d/` is resolved against
the current drive root (`C:\d\...`), not `D:\`. `MpvLibrary.open()` therefore
fails the explicit candidate and the default-name fallback is not on a usable
`PATH` either. Because the same step sets `MPV_KIT_REQUIRE_LIBMPV=1` (`:60`),
`packages/mpv_kit_video/test/controller_channel_test.dart:27-30` turns that
into `fail(...)` instead of a skip — the Windows leg fails deterministically
(and the comment on `:49-50` about pointing the tests at the hook bundle is
not actually achieved).

**Fix:** emit Windows-form paths when on Windows (`pwd -W` is a Git-Bash
builtin; it errors on Linux/macOS and falls back):

```bash
dir=$(cd "$(dirname "$lib")" && { pwd -W 2>/dev/null || pwd; })
```

and use the same converted value for `$GITHUB_PATH` (or `cygpath -w "$dir"`).
On Linux/macOS the fallback is unchanged.

---

### WR-01: The libmpv discovery step can select a stale bundle

**File:** `.github/workflows/flutter-plugin.yml:53-55`
**Severity:** WARNING

**Issue:** `find ... | head -1` picks an arbitrary match. In this checkout the
command returns the older
`.dart_tool/hooks_runner/shared/mpv_kit_libs/build/v0.1.0-dev.2/windows-x64/lib/libmpv-2.dll`
**before** the current `v0.1.0-dev.3` bundle (verified). Nothing pins the tag
or verifies the bundle hash; the selected path is only fed to the test process
and CI never checks `MpvLibrary.resolvedPath` (that gate exists only in the
smoke harness, which CI does not run). A cached/self-hosted runner or a
workspace that still has an older tag silently loads a different libmpv — the
"wrong DLL" incident class the project's OBS-04 gate was created for. The
baseline doc explicitly warns that the older DLL lacks the working Vulkan
render path.

**Fix:** select by the pinned tag rather than by `head -1`, e.g. read
`bundleTag` from `packages/mpv_kit_libs/lib/src/bundles.dart` and construct
`.../shared/mpv_kit_libs/build/$bundleTag/<target>/lib/<name>`, and assert the
file's sha256 (or at minimum `assert` the path contains the current tag).

---

### WR-02: Pixel probe reads the whole backing buffer instead of the ByteData view

**File:** `example/integration_test/impeller_smoke_test.dart:459`
**Severity:** WARNING

**Issue:** `final data = bytes.buffer.asUint8List();` ignores
`bytes.offsetInBytes` and `bytes.lengthInBytes`. `Image.toByteData` does not
guarantee a zero-offset, exactly-sized buffer; if it returns a view, the loop
scans unrelated memory and `nonBlackRatio` becomes meaningless. The pixel probe
is the *only* non-black evidence in the pass criterion, so a garbage ratio can
produce a false `pass` — the one outcome the ADR says the harness must never
fabricate.

**Fix:**

```dart
final data = bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
```

and keep `pixels == data.length ~/ 4` as an assertion before computing the
ratio.

---

### WR-03: The pixel probe has no control, so a black read-out is ambiguous

**File:** `example/integration_test/impeller_smoke_test.dart:445-477`
**Severity:** WARNING

**Issue:** `_probePixels` captures a `RepaintBoundary` whose only content is
the external `Texture`. If the raster path does not capture the texture layer
(engine/raster limitation, not a renderer failure), the probe returns
`supported: true, nonBlackRatio: 0`; `_classify` (`:411-429`) then returns
`failed`, attributing the harness's blind spot to the renderer. A real
`GL_RGBA8` format cliff produces the exact same signature (the ADR calls it a
"silent black texture"). There is no signal that distinguishes "the renderer
produced black" from "the probe could not see the texture".

**Fix:** put a known non-black marker inside the same probe boundary (e.g. a
16x16 coloured `Container` next to the texture) and require the marker's pixels
to be non-black before treating blackness in the texture area as a renderer
result. If the marker is black, report `supported: false` /
`reason: 'probe cannot capture the layer tree'`.

---

### WR-04: ">= 30 s continuous playback" is wall-clock only and unverified

**File:** `example/integration_test/impeller_smoke_test.dart:272-314`
**Severity:** WARNING

**Issue:** `_soakSeconds()` measures elapsed wall time around the 100-round
loop, and every round tears the render context down and recreates it
(`:289-293`), so part of each round renders nothing. Nothing asserts that
playback actually progressed: no `time-pos` delta, no `estimated-vf-fps`
sample, no frame/swap counter is captured during the soak. A stalled or
soft-broken mpv core can still satisfy `rounds == 100 && seconds >= 30`, which
is D-05's "continuous playback" half.

**Fix:** record `player.position.value` (or `mpv.tryGetProperty('time-pos')`) at
soak start and end, require monotonic advance, and sample `estimated-vf-fps > 0`
during the loop; include all three in the `complete` payload.

---

### WR-05: The soak idle metric is vacuous in the normal case and unfair in the top-up case

**File:** `example/integration_test/impeller_smoke_test.dart:284-306, 388-398`
**Severity:** WARNING

**Issue:** Idle counts only when the texture has been continuously mounted for
`>= 500 ms` (`_idleTimeout`, matching native `kIdleTimeout`). Each round keeps
it mounted for `_nextFrame` (<= 100 ms) + 250 ms, i.e. roughly 250-350 ms, so
the native renderer cannot emit an idle event during the rounds at all —
`_idleSoak == 0` is trivially satisfied whenever the loop already exceeded
30 s (no top-up). Conversely, when the loop finishes early and the top-up holds
the texture mounted (`:309-312`), an idle caused by an occluded, minimised or
background window is counted as a renderer failure even though the harness has
no way to verify the window is visible (and the evidence files do not record
window visibility, although the ADR claims "a visible desktop window"). The
criterion therefore both misses real soak idles and misattributes
environmental ones.

**Fix:** after the 100 rounds, hold the final texture mounted for a fixed
sustained window (>= 2 s) and evaluate idle there; record window/lifecycle
state (`WidgetsBinding.instance.lifecycleState`, native window visibility) in
the payload, and treat idle in a non-visible window as `inconclusive`, not
`failed`.

---

### WR-06: Evidence paths in both documents do not resolve; the "committed alongside" claim is false

**File:** `docs/reverse-engineering/03-flutter-windows-texture-consumption.md:17,47,54,555`;
`docs/adr/0003-windows-composition-path.md:66-72,125,319-324`
**Severity:** WARNING

**Issue:** From `docs/reverse-engineering/`, the report's
`../.planning/phases/10-composition-spike/evidence/decompilation.txt` (`:17`)
resolves to `docs/.planning/...`, which does not exist; it needs
`../../.planning/...`. Every `evidence/...` reference (`:47`, `:54`, `:555`;
ADR `:66-72`, `:125`, `:319-324`) implies an `evidence/` directory beside the
document, but neither `docs/reverse-engineering/evidence/` nor
`docs/adr/evidence/` exists — the only copies are under
`.planning/phases/10-composition-spike/evidence/` (verified; the files are
tracked there). `:555`'s "Evidence files committed alongside this report" is
therefore false. Since the whole point of the REA is reproducibility, a reader
following these paths finds nothing.

**Fix:** use repository-root-relative paths
(`.planning/phases/10-composition-spike/evidence/...`) consistently in both
documents, or add links relative to each document's directory.

---

### WR-07: The ADR's Phase 11 precondition omits the reporting-channel fix

**File:** `docs/adr/0003-windows-composition-path.md:233-236`
**Severity:** WARNING

**Issue:** The precondition says only "fix the harness gate (call `setSize`
before the part-1 gate ...)". Given CR-01, a harness corrected exactly that way
would still emit nothing on its documented channel; 10-03's own classification
rule treats "no BENCH line" as `inconclusive`, so Phase 11 would repeat Phase
10's outcome after doing the prescribed work. The ADR's own evidence ("No BENCH
line ... count 0") is the proof, but the remedy is not carried into the
precondition.

**Fix:** extend the precondition to "the harness must emit a `preflight` BENCH
line into the captured log before any workload, and a `complete` line on the
success path", and state which transport carries it (`print`/file).

---

### IN-01: The final `expect` is a tautology

**File:** `example/integration_test/impeller_smoke_test.dart:343-347`
**Severity:** INFO

**Issue:** `_classify` only ever returns `'pass'`, `'inconclusive'` or
`'failed'`, so `expect(result, isIn(['pass', 'inconclusive', 'failed']))`
cannot fail. It adds no protection; the real failure path is the rethrow.

**Fix:** remove it, or replace it with an assertion that can fail (e.g. the
`complete` payload was emitted, or `nonBlackRatio` is within `[0, 1]`).

---

### IN-02: Doc 03 still lists Q1 as open although this phase answered it

**File:** `docs/reverse-engineering/03-flutter-windows-texture-consumption.md:546`
**Severity:** INFO

**Issue:** §7 says "Whether `flutter test -d windows` forwards the engine log
line — **Open**, owned by plan 10-03 (smoke)", while the same phase's ADR
answers it ("Answered: no") and both run logs confirm the answer. The two
phase documents contradict each other on a closed question.

**Fix:** update the row to "Answered: no — `flutter-run` fallback used" and
cite the ADR/evidence.

---

### IN-03: Line citations in the ADR and evidence drift from the source

**File:** `docs/adr/0003-windows-composition-path.md:131-134`;
`.planning/phases/10-composition-spike/evidence/impeller-bench.txt` (`reason:`)
**Severity:** INFO

**Issue:** `VideoRenderer::SetSize` is at
`packages/mpv_kit_video/src/video_renderer.cc:166-176` (line 178 starts
`SetIccProfile`), not `166-179`; the resize condition is at `:478` and `:500`,
not `:499` (the emit is `:541`). The evidence file repeats the same numbers.
Minor, but these citations are the audit trail for the recorded defect.

**Fix:** correct to `166-176` and `478/500/541` in both places.

---

### IN-04: The 500 ms idle constant is duplicated from native code by comment only

**File:** `example/integration_test/impeller_smoke_test.dart:39-44`
**Severity:** INFO

**Issue:** `_idleTimeout` mirrors `VideoRenderer::kIdleTimeout`
(`video_renderer.h:171`). Nothing fails if the native constant changes; the
harness would silently use the wrong threshold, weakening WR-05's already-fragile
idle classification.

**Fix:** expose the native value through the event/plugin contract (or a
test seam) and assert equality in a unit test.

---

### IN-05: The probe samples a 720p boundary, not the 4K target

**File:** `example/integration_test/impeller_smoke_test.dart:129-148, 445-477`
**Severity:** INFO

**Issue:** Part 2 requests a 3840x2160 render target, but the `RepaintBoundary`
wraps a `SizedBox(width: 1280, height: 720)`, so `pixelProbe.width/height` are
1280x720 and the ratio describes the downscaled composition. That is adequate
for detecting the black-format cliff, but the payload/ADR should not claim the
probe proves a non-black *4K* frame.

**Fix:** state the sampled size in the payload/reason, or size the boundary to
the target when a 4K proof is intended.

---

### IN-06: The try/catch does not cover preflight or `pumpWidget`

**File:** `example/integration_test/impeller_smoke_test.dart:115-165`
**Severity:** INFO

**Issue:** The header promises "A harness-side failure emits
`result=inconclusive`, never silence", but only `_execute` is wrapped. A failure
in `tester.pumpWidget` (`:129-148`) or in the preflight `_emitBench` call would
produce no result line at all. (Today the channel is dead anyway — CR-01.)

**Fix:** wrap `pumpWidget`/preflight in the same catch or emit the
`inconclusive` line from a `try` that starts before the first pump.

---

### IN-07: The ADR's top-level `identity: proven` applies to the fallback pair only

**File:** `docs/adr/0003-windows-composition-path.md:3-5, 63-82`
**Severity:** INFO

**Issue:** Identity was established with `flutter run -d windows`, not with the
two `flutter test` smoke runs; the body says this explicitly, but the header
field `identity: proven` is unscoped and can be quoted downstream as if the
measured runs' renderer were identified. The harness itself correctly records
`engineRenderer: 'unresolved-by-harness'`.

**Fix:** label the header value, e.g.
`identity: proven (flutter-run fallback pair; smoke transport unresolved)`.

---

### IN-08: The CI bump leaves the project's documented pin stale

**File:** `.github/workflows/flutter-plugin.yml:17`
**Severity:** INFO

**Issue:** The version bump to 3.47.8 is correct per the plan, but
`.claude/CLAUDE.md` still states "CI pins `FLUTTER_VERSION: 3.47.6`". Future
contributors will treat the stale document as authoritative.

**Fix:** update the pin in `.claude/CLAUDE.md` in the same change.

---

### IN-09: Actions are pinned to moving major tags

**File:** `.github/workflows/flutter-plugin.yml:33,40`
**Severity:** INFO

**Issue:** `actions/checkout@v5` and `subosito/flutter-action@v2` are mutable
tags; a compromised or retagged release executes in a job that builds and
publishes artifacts. This is a supply-chain hardening note, not a bug in this
phase.

**Fix:** pin both actions by commit SHA (with the tag in a comment).

---

_Reviewed: 2026-10-25T03:10:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_

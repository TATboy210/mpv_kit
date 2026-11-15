---
last_mapped_commit: cd47d6761925b8ccb49e153864bf9789dc3f5039
last_mapped_at: 2026-10-27
---
# Testing Patterns

**Analysis Date:** 2026-10-27

## Test Framework

**Runner:**
- Dart: `package:test` (^1.25, resolved 1.31.1) for `packages/mpv_kit` and `packages/mpv_kit_libs`; config `packages/mpv_kit/dart_test.yaml`.
- Flutter: `flutter_test` for `packages/mpv_kit_video/test/` and `example/test/`; `integration_test` for `example/integration_test/`.
- Native: Meson test suite `native/tests/meson.build` (C11/C++17, `-Werror`).

**Assertion Library:**
- `package:test` / `flutter_test` matchers (`expect`, `throwsA`, `isA<>`).
- Native: exact line comparison against golden traces plus invariant checks in `native/tests/renderer_harness.h`.

**Run Commands:**
```bash
cd packages/mpv_kit && dart test                                   # default suite (format/lifecycle excluded)
cd packages/mpv_kit && dart test -t failure-injection              # failure-path suite
cd packages/mpv_kit && dart test test/lifecycle_test.dart -t lifecycle --run-skipped   # RSS soak
dart pub global run coverage:test_with_coverage                    # coverage -> coverage/lcov.info
cd packages/mpv_kit_video && flutter test --coverage               # channel tests + coverage
cd example && flutter test integration_test/real_plugin_test.dart -d linux|macos|windows
meson setup tests-out native/tests && meson test -C tests-out --print-errorlogs --verbose
```
Set `MPV_KIT_LIBMPV_PATH` to a built libmpv for anything that loads libmpv.

## Test File Organization

**Location:**
- Separate `test/` per package; integration tests in `example/integration_test/`; native tests in `native/tests/`.

**Naming:**
- `<subject>_test.dart`; native `video_renderer_<kind>.cc`, golden `native/tests/golden/<variant>.txt`.

**Structure:**
```
packages/mpv_kit/test/          api_freeze, api_surface, audio_devices, failure_injection,
                                format_matrix, library, lifecycle, models, mpv, options,
                                player, stream_bridge; fixtures/dispose_with_children.dart
packages/mpv_kit_libs/test/     bundle_test.dart
packages/mpv_kit_video/test/    controller_channel_test.dart, video_controller_test.dart
example/test/                   hud_test.dart (pure widgets)
example/integration_test/       real_plugin, seek_recovery, playback_bench,
                                uhd_endurance, impeller_smoke(_modes)
native/tests/                   render_vk_smoke.c, stream_bridge_test.c, renderer_harness.h,
                                video_renderer_golden_{sw,vk,vk_fallback,sw_retire_twice,vk_retire_twice}.cc,
                                video_renderer_{api,affinity,sw_hold_front}_test.cc, golden/*.txt
```

## Test Structure

**Suite Organization:**
```dart
// High-level Player tests (headless, vo=null).
@TestOn('vm')
library;

const _lavfi = 'av://lavfi:testsrc2=size=320x240:rate=30:duration=2';

Future<T> _until<T>(MpvState<T> s, bool Function(T) ok) => ok(s.value)
    ? Future.value(s.value)
    : s.stream.firstWhere(ok).timeout(const Duration(seconds: 10));

void main() {
  late Player player;
  setUp(() => player = Player(options: const {'vo': 'null', 'ao': 'null'}));
  tearDown(() => player.dispose());
  test('open exposes tracks, video params and position', () async { ... });
}
```
(`packages/mpv_kit/test/player_test.dart`)

**Patterns:**
- Header comment states what is proven, how to run, env vars, skip semantics.
- Headless media: lavfi URLs (`av://lavfi:testsrc2=...`) or generated files (`_writeSilentWav`) in `Directory.systemTemp.createTempSync`, removed in `tearDownAll`.
- Teardown always disposes `Player`/controllers and unregisters mock handlers.
- Every wait bounded with `.timeout(...)`.
- Tags in `packages/mpv_kit/dart_test.yaml`: `format` (needs `MPV_KIT_FORMAT_SAMPLES`), `failure-injection`, `lifecycle` (skipped by default; RSS soak must run alone).
- Optional-feature guards skip with an explicit reason (e.g. stream-bridge patch absent via `providesSymbol('mpv_kit_stream_add')` in `failure_injection_test.dart`); a missing libmpv fails loudly when `MPV_KIT_REQUIRE_LIBMPV` is set.

## Mocking

**Framework:** No mocking library. Hand-written fakes only.

**Patterns:**
```dart
messenger.setMockMethodCallHandler(_channel, (call) async {
  calls.add(call);
  if (call.method == 'create') {
    return {'textureId': 7, 'backend': 'vulkan', 'reason': 'vulkan (x)'};
  }
  return null;
});
```
(`packages/mpv_kit_video/test/controller_channel_test.dart` — fake platform channel, real headless libmpv)

- Native: `native/tests/renderer_harness.h` provides `FakeMpv` (fills the nine-pointer `mpv_kit::MpvApi` table so `VideoRenderer` runs without linking libmpv), `FakeInterop`/`FakeVulkanInterop` (real images on the runner's Vulkan 1.3 device), and a never-freed `FakeImages` registry that records `DOUBLE DESTROY` / `USE AFTER DESTROY` as invariant violations.
- `video_renderer_sw_hold_front_test.cc` replaces global `operator new/delete` to watch buffer liveness without a use-after-free.

**What to Mock:**
- The Flutter method channel in unit tests; libmpv inside native renderer tests; mpv's GPU work (timeline signals).

**What NOT to Mock:**
- libmpv in Dart tests — use the real headless library (`vo=null`, `ao=null`).
- The real plugin in `example/integration_test/real_plugin_test.dart` — project rule: mock channels never substitute for real plugin verification on CI runners.
- The renderer state machine and `VulkanContext` — always the real `packages/mpv_kit_video/src/*.cc` sources (same list as the plugin CMake builds).

## Fixtures and Factories

**Test Data:**
```dart
final _fab = HudSnapshot.fabricated();   // example/test/hud_test.dart
```
- Golden traces: `native/tests/golden/{sw,vk,vk_fallback,sw_retire_twice,vk_retire_twice,api_override}.txt` — `[scenario]` sections, exact line vocabulary (`start ok backend=...`, `render buf=...`, `acquire index=...`, `quiesce ...`, `teardown frees=...`) documented at the top of each file. Traces contain only renderer decisions, never timestamps/thread IDs; timing is asserted as expectation + `--slack-ms` (250, or 1000 under sanitizers).
- Golden files are read-only; no regenerate mode. Changes only in reviewed commits.

**Frozen set:** `.planning/phases/12-renderbackend-seam/evidence/golden-freeze.sha256` pins `native/tests/renderer_harness.h`, `video_renderer_golden_sw.cc`, `video_renderer_golden_vk.cc`, `golden/sw.txt`, `golden/vk.txt`. Never modify them; add new scenarios as a new binary + golden file + `meson.build` entry (the pattern followed by `vk_fallback`, `retire_twice`, `api`, `affinity`, `sw_hold_front`). Verify with `shasum -a 256 -c` against that file — no CI step checks it.

**Location:**
- `packages/mpv_kit/test/fixtures/`, `native/tests/golden/`.

## Coverage

**Requirements:** 80% line coverage, enforced by awk over `coverage/lcov.info` in `.github/workflows/native-verify.yml` for `mpv_kit`, `mpv_kit_libs` and (job `flutter-video-coverage`) `mpv_kit_video`. No coverage for C/C++.

**View Coverage:**
```bash
dart pub global run coverage:test_with_coverage
awk -F: '/^LF:/{a+=$2} /^LH:/{b+=$2} END{print 100*b/a}' coverage/lcov.info
```

## Test Types

**Unit Tests:**
- Dart against real headless libmpv (`mpv_test`, `player_test`, `models_test`, `stream_bridge_test`); pure tests (`bundle_test`, `hud_test`, `options_test`); API-surface guards (`api_freeze_test.dart` via `dart:mirrors`, `api_surface_test.dart`) enforce the frozen public API.

**Integration Tests:**
- Native: `render_vk_smoke` (gpu-next and gpu) and `stream_bridge_test` against the patched libmpv; renderer golden/api/affinity/hold-front tests. Exit 0 pass, 1 fail, 77 skip (no Vulkan 1.3 device).
- `example/integration_test/real_plugin_test.dart` (VERIFY-01) on Linux (xvfb), macOS, Windows CI runners.

**E2E / Soak (manual, Windows):**
- `uhd_endurance_test.dart` (`MPV_KIT_BENCH_SIZE/SECONDS/LABEL/RENDER`), `playback_bench_test.dart`, `seek_recovery_test.dart`, `impeller_smoke_test.dart` (`--enable-impeller` vs `--no-enable-impeller`). `@TestOn('windows')`, window must stay visible; gates are fixed and reported as `BENCH` JSON, inconclusive never reported as pass.

**CI:**
- `.github/workflows/native-verify.yml`: patch drift + matrix audit, libmpv build, ABI audit, `meson test` (lavapipe / MoltenVK / Windows lavapipe), Dart tests + coverage, failure-injection and lifecycle soak, Flutter coverage, real-plugin integration on three OSes, `sanitizers` job (ASan+UBSan libmpv and native tests, `--timeout-multiplier 3`).
- `.github/workflows/flutter-plugin.yml`: build example per desktop target, `flutter analyze --fatal-infos`, plugin tests.

## Common Patterns

**Async Testing:**
```dart
final tracks = await _until(player.tracks, (t) => t.isNotEmpty);
```

**Error Testing:**
- `runZonedGuarded` captures listener errors escaping sync broadcast controllers; body failures are rethrown (`packages/mpv_kit/test/failure_injection_test.dart`).
- `expect(() => ..., throwsA(isA<MpvException>()))` for typed failures.
- Native harness waits are bounded (`kWaitTimeout{10000}`) so a broken renderer fails instead of hanging.

---

*Testing analysis: 2026-10-27*

// Shared guard of the Windows D3D11 integration tests (not a test itself).
//
// The tests point MPV_KIT_LIBMPV_PATH at the libmpv the verify tier built
// (the one with the D3D11 render API). MpvLibrary.open() falls through to the
// next candidate when that load fails, and the next candidate is the
// mpv_kit_libs bundle next to the executable, which has no D3D11 render
// API. The symptom is then a misleading "mpv_render_context_create:
// operation not implemented" long after the real cause (CI run 40617697855:
// the staged libharfbuzz-0.dll was shadowed by the bundled one, and the
// artifact's libpangowin32 could not find hb_directwrite_face_create). This
// guard turns that into a failure that names the cause.
library;

import 'dart:io' show Platform;

import 'package:flutter_test/flutter_test.dart';
import 'package:mpv_kit/mpv_kit.dart';

/// Fails unless the libmpv this process loaded is the one named by
/// MPV_KIT_LIBMPV_PATH (no-op when the variable is unset). Call it once a
/// Player exists: creating it is what opens the library.
void expectConfiguredLibmpv() {
  final wanted = Platform.environment['MPV_KIT_LIBMPV_PATH'];
  if (wanted == null || wanted.isEmpty) return;
  expect(
    MpvLibrary.resolvedPath,
    wanted,
    reason:
        'MPV_KIT_LIBMPV_PATH did not load; the loader fell through to '
        '${MpvLibrary.resolvedPath}. Failed candidates: '
        '${MpvLibrary.lastOpenAttempts}. A dependency DLL next to the '
        'executable probably shadows the one the library needs: point the '
        'mpv_kit_libs hook (libmpv_bundle) at the same bundle.',
  );
}

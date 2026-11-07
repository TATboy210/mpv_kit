/// Test-only seam for injecting an event decode failure.
///
/// Internal (`src/`, not exported by `package:mpv_kit/mpv_kit.dart`): real
/// libmpv never produces an event this binding cannot decode, so the drain's
/// failure containment is only testable through this hook.
library;

import 'dart:ffi';

import '../ffi/bindings.dart';

/// When set, [MpvEventData.decode] calls it first and throws a non-null
/// result instead of decoding the event.
Object? Function(Pointer<MpvEvent> event)? debugEventDecodeFailure;

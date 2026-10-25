/// Child-process scenario for `mpv_test.dart`: dispose the owner while child
/// clients are still alive.
///
/// `mpv_terminate_destroy` waits until every client of the core (weak ones
/// included) is gone. A child created with `Mpv.createClient` can only be
/// destroyed from this isolate, so if the owner does not dispose it first the
/// synchronous FFI call blocks forever. A hang cannot be timed out in-process,
/// which is why the test runs this script as a separate process and kills it
/// on timeout.
///
/// Exit code 0 means the owner's dispose returned and took every derived
/// client (child, weak child, grandchild) down with it; 1 means it returned
/// but left a client alive or usable. Requires libmpv through
/// `MPV_KIT_LIBMPV_PATH` or the loader path, like the in-process tests.
library;

import 'dart:io';

import 'package:mpv_kit/mpv_kit.dart';

void main() {
  final mpv = Mpv.create(
    options: const {
      'vo': 'null',
      'ao': 'null',
      'idle': 'yes',
      'terminal': 'no',
    },
  );
  final child = mpv.createClient('child');
  final weak = mpv.createClient('weak-child', weak: true);
  // Created from a child, not from the owner: disposal must recurse.
  final grandchild = child.createClient('grandchild');

  mpv.dispose();

  final failures = <String>[];
  for (final (name, client) in [
    ('child', child),
    ('weak child', weak),
    ('grandchild', grandchild),
  ]) {
    if (!client.isDisposed) failures.add('$name is not disposed');
    try {
      client.getProperty('volume');
      failures.add('$name still accepts calls');
    } on StateError {
      // Expected: the post-dispose guard rejects the call before FFI.
    }
  }
  if (failures.isNotEmpty) {
    stderr.writeln(failures.join('\n'));
    exitCode = 1;
    return;
  }
  stdout.writeln('ok');
}

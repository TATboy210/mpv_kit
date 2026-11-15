// Decode micro-benchmark (PERF-02): measures `MpvEventData.decode` over
// synthetic propertyChange events built in an Arena — no libmpv required.
//
// Run from packages/mpv_kit (so package:mpv_kit resolves):
//   dart run ../tools/bench_decode.dart
//
// Output is one greppable line per shape for before/after comparison:
//   BENCH decode-double <ns/op> <ops/s> <iterations>
//   BENCH decode-map    <ns/op> <ops/s> <iterations>
//
// The double shape mirrors the `time-pos` hot path (PERF-01/04); the map
// shape stands in for track-list-like structured payloads.
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:mpv_kit/mpv_kit.dart';

void main() {
  using((a) {
    // time-pos shape: a double node.
    final doubleProp = a<MpvEventProperty>();
    doubleProp.ref
      ..name = 'time-pos'.toNativeUtf8(allocator: a)
      ..format = MpvFormat.node
      ..data = writeNode(1.234, a).cast();
    final doubleEvent = a<MpvEvent>();
    doubleEvent.ref
      ..eventId = MpvEventId.propertyChange
      ..error = 0
      ..replyUserdata = 1
      ..data = doubleProp.cast();

    // track-list shape: a small map node.
    final mapProp = a<MpvEventProperty>();
    mapProp.ref
      ..name = 'track-list'.toNativeUtf8(allocator: a)
      ..format = MpvFormat.node
      ..data = writeNode([
        {'id': 1, 'type': 'video'},
        {'id': 2, 'type': 'audio'},
      ], a).cast();
    final mapEvent = a<MpvEvent>();
    mapEvent.ref
      ..eventId = MpvEventId.propertyChange
      ..error = 0
      ..replyUserdata = 2
      ..data = mapProp.cast();

    // Defeat dead-code elimination: fold decoded names into a sink.
    var sink = 0;
    void run(Pointer<MpvEvent> e, int iterations) {
      for (var i = 0; i < iterations; i++) {
        final ev = MpvEventData.decode(e);
        if (ev is PropertyChangeEvent) sink += ev.name.length;
      }
    }

    const iterations = 200000;
    // Warm-up: JIT and allocator growth must not pollute the measurement.
    run(doubleEvent, 20000);
    run(mapEvent, 20000);

    final swDouble = Stopwatch()..start();
    run(doubleEvent, iterations);
    swDouble.stop();
    final swMap = Stopwatch()..start();
    run(mapEvent, iterations);
    swMap.stop();

    void report(String shape, Stopwatch sw) {
      final ns = sw.elapsedMicroseconds * 1000 / iterations;
      final ops = iterations / (sw.elapsedMicroseconds / 1e6);
      print('BENCH decode-$shape ${ns.toStringAsFixed(0)} ns/op '
          '${ops.round()} ops/s $iterations iterations');
    }

    report('double', swDouble);
    report('map', swMap);
    if (sink < 0) print('unreachable: $sink');
  });
}

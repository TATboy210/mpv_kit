/// Custom stream protocols served from Dart (`mpv_kit_stream_*`, patch 0006).
///
/// mpv reads custom streams synchronously on its demuxer thread, which Dart
/// cannot answer directly. libmpv's stream bridge turns each read/seek into a
/// request that is delivered here through a `NativeCallable.listener` and
/// blocks the mpv thread until [_StreamBridge] completes it, so a source may
/// answer asynchronously (file, network, decryption, ...).
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../ffi/bindings.dart';
import 'errors.dart';
import 'node.dart';

/// A readable byte stream behind a custom protocol, see
/// `Mpv.registerStreamProtocol`.
///
/// mpv calls one method at a time per stream (from its demuxer thread), and
/// waits for each returned future, so implementations need no locking.
abstract interface class MpvStreamSource {
  /// Total size in bytes, or null if unknown (live streams). Seeking and
  /// duration estimates need a size.
  int? get size;

  /// Returns up to [maxBytes] bytes from the current position; an empty
  /// list signals end of stream.
  FutureOr<Uint8List> read(int maxBytes);

  /// Moves to [offset] and returns the new position. Throw
  /// [UnsupportedError] for non-seekable streams.
  FutureOr<int> seek(int offset);

  /// Releases resources. Called once; no other call follows.
  FutureOr<void> close();
}

/// Opens [uri] (including the `protocol://` prefix); null rejects it.
typedef MpvStreamOpener = FutureOr<MpvStreamSource?> Function(String uri);

/// [MpvStreamSource] over bytes already in memory.
final class MpvMemoryStreamSource implements MpvStreamSource {
  MpvMemoryStreamSource(this.bytes);

  final Uint8List bytes;
  var _pos = 0;

  @override
  int get size => bytes.length;

  @override
  Uint8List read(int maxBytes) {
    final end = math.min(bytes.length, _pos + maxBytes);
    final chunk = Uint8List.sublistView(bytes, _pos, end);
    _pos = end;
    return chunk;
  }

  @override
  int seek(int offset) => _pos = offset.clamp(0, bytes.length);

  @override
  void close() {}
}

// Request kinds, mirrors mpv_kit_stream_op in include/mpv/stream_bridge.h.
const _opOpen = 1, _opRead = 2, _opSeek = 3, _opClose = 4;

typedef _RequestFn =
    Void Function(Pointer<Void>, Uint64, Int32, Uint64, Pointer<Void>, Int64);

/// Optional symbols of the bridge (absent from stock libmpv).
final class _BridgeBindings {
  _BridgeBindings(DynamicLibrary lib)
    : add = lib
          .lookupFunction<
            Int32 Function(
              Pointer<MpvHandle>,
              Pointer<Utf8>,
              Pointer<NativeFunction<_RequestFn>>,
              Pointer<Void>,
              Pointer<Uint64>,
            ),
            int Function(
              Pointer<MpvHandle>,
              Pointer<Utf8>,
              Pointer<NativeFunction<_RequestFn>>,
              Pointer<Void>,
              Pointer<Uint64>,
            )
          >('mpv_kit_stream_add'),
      begin = lib.lookupFunction<Int32 Function(Uint64), int Function(int)>(
        'mpv_kit_stream_begin',
      ),
      complete = lib
          .lookupFunction<
            Void Function(Uint64, Int64, Int64),
            void Function(int, int, int)
          >('mpv_kit_stream_complete'),
      shutdown = lib.lookupFunction<Void Function(Uint64), void Function(int)>(
        'mpv_kit_stream_shutdown',
      );

  final int Function(
    Pointer<MpvHandle>,
    Pointer<Utf8>,
    Pointer<NativeFunction<_RequestFn>>,
    Pointer<Void>,
    Pointer<Uint64>,
  )
  add;
  final int Function(int) begin;
  final void Function(int, int, int) complete;
  final void Function(int) shutdown;

  static bool isAvailable(DynamicLibrary lib) =>
      lib.providesSymbol('mpv_kit_stream_add');
}

/// One registered protocol. Owned by `Mpv`, which calls [shutdown] before
/// destroying the handle and [close] afterwards.
final class StreamBridge {
  StreamBridge._(this._b, this._open);

  /// Registers [protocol] on [handle]. Throws [UnsupportedError] if the
  /// loaded libmpv lacks the mpv_kit stream bridge.
  static StreamBridge register(
    MpvBindings bindings,
    Pointer<MpvHandle> handle,
    String protocol,
    MpvStreamOpener open,
  ) {
    if (!_BridgeBindings.isAvailable(bindings.library)) {
      throw UnsupportedError(
        'This libmpv has no mpv_kit stream bridge (mpv_kit patch 0006)',
      );
    }
    final bridge = StreamBridge._(_BridgeBindings(bindings.library), open);
    bridge._callable = NativeCallable<_RequestFn>.listener(bridge._onRequest);
    using((a) {
      final out = a<Uint64>();
      final rc = bridge._b.add(
        handle,
        protocol.toNativeUtf8(allocator: a),
        bridge._callable.nativeFunction,
        nullptr,
        out,
      );
      if (rc < 0) {
        bridge._callable.close();
        throw MpvException(
          rc,
          readUtf8(bindings.errorString(rc)),
          operation: 'stream_add($protocol)',
        );
      }
      bridge._registration = out.value;
    });
    return bridge;
  }

  final _BridgeBindings _b;
  final MpvStreamOpener _open;
  late final NativeCallable<_RequestFn> _callable;
  late final int _registration;
  final _sources = <int, MpvStreamSource>{};
  var _nextStream = 1;
  var _shutdown = false;

  /// Fails every pending request; afterwards no request buffer is touched.
  void shutdown() {
    if (_shutdown) return;
    _shutdown = true;
    _b.shutdown(_registration);
    for (final s in _sources.values) {
      unawaited(Future.sync(s.close).catchError((Object _) {}));
    }
    _sources.clear();
  }

  /// Releases the callback. Only after the core can no longer call it.
  void close() {
    shutdown();
    _callable.close();
  }

  void _onRequest(
    Pointer<Void> _,
    int request,
    int op,
    int stream,
    Pointer<Void> data,
    int arg,
  ) {
    if (_shutdown) return;
    if (op == _opClose) {
      final s = _sources.remove(stream);
      if (s != null) unawaited(Future.sync(s.close).catchError((Object _) {}));
      return;
    }
    // Claim the request first: only then do data and the mpv thread's wait
    // stay valid until we complete it.
    if (_b.begin(request) == 0) return;
    switch (op) {
      case _opOpen:
        unawaited(_handleOpen(request, data.cast<Utf8>().toDartString()));
      case _opRead:
        unawaited(_handleRead(request, stream, data.cast<Uint8>(), arg));
      case _opSeek:
        unawaited(_handleSeek(request, stream, arg));
      default:
        _b.complete(request, MpvError.notImplemented.code, -1);
    }
  }

  Future<void> _handleOpen(int request, String uri) async {
    MpvStreamSource? source;
    try {
      source = await _open(uri);
    } on Object {
      source = null;
    }
    if (_shutdown) {
      if (source != null) await Future.sync(source.close);
      return;
    }
    if (source == null) {
      _b.complete(request, MpvError.loadingFailed.code, -1);
      return;
    }
    final id = _nextStream++;
    _sources[id] = source;
    _b.complete(request, id, source.size ?? -1);
  }

  Future<void> _handleRead(
    int request,
    int stream,
    Pointer<Uint8> buffer,
    int capacity,
  ) async {
    final source = _sources[stream];
    var result = -1;
    Uint8List? chunk;
    try {
      chunk = source == null ? null : await source.read(capacity);
    } on Object {
      chunk = null;
    }
    // After shutdown the buffer may be gone: never write into it then.
    if (_shutdown) return;
    if (chunk != null) {
      final n = math.min(chunk.length, capacity);
      buffer.asTypedList(n).setRange(0, n, chunk);
      result = n;
    }
    _b.complete(request, result, 0);
  }

  Future<void> _handleSeek(int request, int stream, int offset) async {
    final source = _sources[stream];
    int result;
    try {
      result = source == null
          ? MpvError.generic.code
          : await source.seek(offset);
    } on UnsupportedError {
      result = MpvError.unsupported.code;
    } on Object {
      result = MpvError.generic.code;
    }
    if (_shutdown) return;
    _b.complete(request, result, 0);
  }
}

/// Custom stream protocols served from Dart (`mpv_kit_stream_*`, patch 0006).
///
/// mpv reads custom streams synchronously on its demuxer thread, which Dart
/// cannot answer directly. libmpv's stream bridge turns each read/seek into a
/// request that is delivered here through a `NativeCallable.listener` and
/// blocks the mpv thread until [_StreamBridge] completes it, so a source may
/// answer asynchronously (file, network, decryption, ...).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:meta/meta.dart';

import '../ffi/bindings.dart';
import 'errors.dart';
import 'node.dart';

/// A readable byte stream behind a custom protocol, see
/// `Mpv.registerStreamProtocol`.
///
/// mpv calls one method at a time per stream (from its demuxer thread), and
/// waits for each returned future, so implementations need no locking.
///
/// `close` may arrive while an open/read/seek is still pending (shutdown or
/// teardown race): implementations must guarantee their futures eventually
/// complete, or accept that abandoned calls never do.
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
///
/// An opener that has not answered after 30 s fails the load with
/// `loadingFailed` (libmpv cannot cancel a pending open); a source it
/// returns afterwards is closed unused.
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

  /// How long an OPEN may wait for the opener before it fails with
  /// `loading_failed`; a source that arrives later is closed unused.
  ///
  /// libmpv cannot cancel an OPEN (no stream exists yet), so without a bound
  /// an opener that never answers freezes `stop`/`loadfile` until dispose.
  /// Costs of the bound: `stop` can still wait up to this long, and a
  /// legitimately slower opener (e.g. a network handshake) now fails. A hung
  /// READ still blocks `stop`: it must stay claimed while mpv owns the
  /// buffer it writes into.
  @visibleForTesting
  static Duration openTimeout = const Duration(seconds: 30);

  /// Decodes the NUL-terminated OPEN URI. Never throws, so a request that was
  /// already claimed is always answered: invalid UTF-8 becomes U+FFFD (the
  /// opener then simply rejects the URI) and nullptr the empty string.
  @visibleForTesting
  static String decodeUri(Pointer<Utf8> data) => data == nullptr
      ? ''
      : utf8.decode(
          data.cast<Uint8>().asTypedList(data.length),
          allowMalformed: true,
        );

  final _BridgeBindings _b;
  final MpvStreamOpener _open;
  late final NativeCallable<_RequestFn> _callable;
  late final int _registration;
  final _sources = <int, MpvStreamSource>{};
  var _nextStream = 1;
  var _shutdown = false;

  /// Invoked when a source's open/read/seek/close throws. The mpv-facing
  /// error codes are unchanged; reporting is purely additive (OBS-01).
  /// `Mpv.registerStreamProtocol` wires this to `Mpv.onSourceError`.
  void Function(String operation, Object error, StackTrace stackTrace)?
      onSourceError;

  /// Delivers a swallowed source exception to [onSourceError] without ever
  /// letting the report (or a throwing consumer) break request completion.
  void _report(String operation, Object error, StackTrace stackTrace) {
    final sink = onSourceError;
    if (sink == null) return;
    try {
      sink(operation, error, stackTrace);
    } on Object {
      // A failing consumer must not become an uncaught async error.
    }
  }

  /// Fails every pending request; afterwards no request buffer is touched.
  void shutdown() {
    if (_shutdown) return;
    _shutdown = true;
    _b.shutdown(_registration);
    for (final s in _sources.values) {
      unawaited(
        Future.sync(s.close).catchError(
          (Object e, StackTrace s) => _report('close', e, s),
        ),
      );
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
      if (s != null) {
        unawaited(
          Future.sync(s.close).catchError(
            (Object e, StackTrace st) => _report('close', e, st),
          ),
        );
      }
      return;
    }
    // Claim the request first: only then do data and the mpv thread's wait
    // stay valid until we complete it.
    if (_b.begin(request) == 0) return;
    switch (op) {
      case _opOpen:
        unawaited(_handleOpen(request, decodeUri(data.cast<Utf8>())));
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
    // Set once mpv has its stream id; any other exit answers loading_failed.
    var answered = false;
    try {
      try {
        source = await _openBounded(uri);
      } on Object catch (e, s) {
        // Null rejects the URI; a throw (or the open timeout) is a real
        // source failure — report it (OBS-01) and keep the mpv-facing
        // loading_failed semantics.
        source = null;
        _report('open', e, s);
      }
      if (_shutdown) {
        // `_onRequest` runs this method under `unawaited`, so a throwing close
        // would escape as an unhandled async error after `dispose()` returned.
        // Contain it exactly like the `shutdown()` sweep.
        if (source != null) {
          await Future.sync(source.close).catchError(
            (Object e, StackTrace st) => _report('close', e, st),
          );
        }
        return;
      }
      if (source == null) return;
      // Read before registering: a throwing getter must not leave a stream
      // id behind that mpv never learns about.
      final size = source.size;
      final id = _nextStream++;
      _sources[id] = source;
      answered = true;
      _b.complete(request, id, size ?? -1);
    } on Object catch (e, s) {
      // Only `source.size` can get here; report it like an open failure.
      _report('open', e, s);
    } finally {
      // The request was claimed in `_onRequest`, so mpv's demuxer thread
      // waits for this answer (OPEN cannot be cancelled natively). After
      // shutdown native has already released it: complete nothing then.
      if (!answered && !_shutdown) {
        _b.complete(request, MpvError.loadingFailed.code, -1);
        if (source != null) unawaited(_closeContained(source));
      }
    }
  }

  /// Runs the opener bounded by [openTimeout]; on timeout the returned future
  /// fails with [TimeoutException]. Nobody waits for the opener after that,
  /// so a source it yields later is closed and a later error is reported.
  Future<MpvStreamSource?> _openBounded(String uri) {
    final opening = Future.sync(() => _open(uri));
    final timeout = openTimeout;
    return opening.timeout(
      timeout,
      onTimeout: () {
        unawaited(
          opening.then<void>(
            (lateSource) async {
              if (lateSource != null) await _closeContained(lateSource);
            },
            onError: (Object e, StackTrace s) => _report('open', e, s),
          ),
        );
        throw TimeoutException('stream opener did not answer', timeout);
      },
    );
  }

  /// Closes [source], reporting instead of throwing a close failure: callers
  /// run under `unawaited`, where a throw would be an unhandled async error.
  Future<void> _closeContained(MpvStreamSource source) =>
      Future.sync(source.close).catchError(
        (Object e, StackTrace st) => _report('close', e, st),
      );

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
    } on Object catch (e, s) {
      chunk = null;
      _report('read', e, s);
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
    } on UnsupportedError catch (e, s) {
      result = MpvError.unsupported.code;
      _report('seek', e, s);
    } on Object catch (e, s) {
      result = MpvError.generic.code;
      _report('seek', e, s);
    }
    if (_shutdown) return;
    _b.complete(request, result, 0);
  }
}

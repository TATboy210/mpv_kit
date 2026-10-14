/// mpv_kit — libmpv 0.41 (client API 2.5) 的完整 Dart 绑定。
///
/// * [Mpv] — 1:1 low-level client API (commands, properties, observers,
///   async requests, hooks, logs, sub-clients).
/// * [MpvBindings] — raw symbol table for anything not wrapped.
library;

export 'src/core/errors.dart';
export 'src/core/events.dart';
export 'src/core/mpv.dart';
export 'src/core/node.dart' show readNode, writeNode;
export 'src/ffi/bindings.dart';
export 'src/ffi/library.dart';

/// libmpv 0.41 (client API 2.5) 原始 FFI 绑定 — 与 include/mpv/*.h 逐项对应。
///
/// Raw, hand-audited bindings for every exported libmpv symbol. Each
/// declaration mirrors the C header verbatim so `tools/rea_abi_audit`
/// can verify the shipped binary exports exactly this set (54 symbols).
///
/// Memory ownership follows the C API: strings/nodes returned by libmpv must
/// be released with [MpvBindings.free] / [MpvBindings.freeNodeContents].
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';

// ---------------------------------------------------------------------------
// Opaque handles
// ---------------------------------------------------------------------------

/// `mpv_handle` — 不透明客户端句柄。
final class MpvHandle extends Opaque {}

/// `mpv_render_context` — 不透明渲染上下文。
final class MpvRenderContext extends Opaque {}

// ---------------------------------------------------------------------------
// Enums (kept as int constants: the C ABI passes them as `int`)
// ---------------------------------------------------------------------------

/// `mpv_format` 取值。
abstract final class MpvFormat {
  static const none = 0;
  static const string = 1;
  static const osdString = 2;
  static const flag = 3;
  static const int64 = 4;
  static const double_ = 5;
  static const node = 6;
  static const nodeArray = 7;
  static const nodeMap = 8;
  static const byteArray = 9;
}

/// `mpv_event_id` 取值。
abstract final class MpvEventId {
  static const none = 0;
  static const shutdown = 1;
  static const logMessage = 2;
  static const getPropertyReply = 3;
  static const setPropertyReply = 4;
  static const commandReply = 5;
  static const startFile = 6;
  static const endFile = 7;
  static const fileLoaded = 8;
  static const idle = 11;
  static const tick = 14;
  static const clientMessage = 16;
  static const videoReconfig = 17;
  static const audioReconfig = 18;
  static const seek = 20;
  static const playbackRestart = 21;
  static const propertyChange = 22;
  static const queueOverflow = 24;
  static const hook = 25;
}

/// `mpv_render_param_type` 取值。
abstract final class MpvRenderParamType {
  static const invalid = 0;
  static const apiType = 1;
  static const openglInitParams = 2;
  static const openglFbo = 3;
  static const flipY = 4;
  static const depth = 5;
  static const iccProfile = 6;
  static const ambientLight = 7;
  static const x11Display = 8;
  static const wlDisplay = 9;
  static const advancedControl = 10;
  static const nextFrameInfo = 11;
  static const blockForTargetTime = 12;
  static const skipRendering = 13;
  static const drmDisplay = 14;
  static const drmDrawSurfaceSize = 15;
  static const drmDisplayV2 = 16;
  static const swSize = 17;
  static const swFormat = 18;
  static const swStride = 19;
  static const swPointer = 20;
}

// ---------------------------------------------------------------------------
// Structs
// ---------------------------------------------------------------------------

/// `mpv_node` 的 union 成员。
final class MpvNodeUnion extends Union {
  external Pointer<Utf8> string;
  @Int32()
  external int flag;
  @Int64()
  external int int64;
  @Double()
  external double double_;
  external Pointer<MpvNodeList> list;
  external Pointer<MpvByteArray> ba;
}

/// `mpv_node`。
final class MpvNode extends Struct {
  external MpvNodeUnion u;
  @Int32()
  external int format;
}

/// `mpv_node_list`。
final class MpvNodeList extends Struct {
  @Int32()
  external int num;
  external Pointer<MpvNode> values;
  external Pointer<Pointer<Utf8>> keys;
}

/// `mpv_byte_array`。
final class MpvByteArray extends Struct {
  external Pointer<Void> data;
  @Size()
  external int size;
}

/// `mpv_event`。
final class MpvEvent extends Struct {
  @Int32()
  external int eventId;
  @Int32()
  external int error;
  @Uint64()
  external int replyUserdata;
  external Pointer<Void> data;
}

/// `mpv_event_property`。
final class MpvEventProperty extends Struct {
  external Pointer<Utf8> name;
  @Int32()
  external int format;
  external Pointer<Void> data;
}

/// `mpv_event_log_message`。
final class MpvEventLogMessage extends Struct {
  external Pointer<Utf8> prefix;
  external Pointer<Utf8> level;
  external Pointer<Utf8> text;
  @Int32()
  external int logLevel;
}

/// `mpv_event_start_file`。
final class MpvEventStartFile extends Struct {
  @Int64()
  external int playlistEntryId;
}

/// `mpv_event_end_file`。
final class MpvEventEndFile extends Struct {
  @Int32()
  external int reason;
  @Int32()
  external int error;
  @Int64()
  external int playlistEntryId;
  @Int64()
  external int playlistInsertId;
  @Int32()
  external int playlistInsertNumEntries;
}

/// `mpv_event_client_message`。
final class MpvEventClientMessage extends Struct {
  @Int32()
  external int numArgs;
  external Pointer<Pointer<Utf8>> args;
}

/// `mpv_event_hook`。
final class MpvEventHook extends Struct {
  external Pointer<Utf8> name;
  @Uint64()
  external int id;
}

/// `mpv_event_command`。
final class MpvEventCommand extends Struct {
  external MpvNode result;
}

/// `mpv_render_param`。
final class MpvRenderParam extends Struct {
  @Int32()
  external int type;
  external Pointer<Void> data;
}

/// `mpv_stream_cb_info`。
final class MpvStreamCbInfo extends Struct {
  external Pointer<Void> cookie;
  external Pointer<NativeFunction<MpvStreamCbReadFn>> readFn;
  external Pointer<NativeFunction<MpvStreamCbSeekFn>> seekFn;
  external Pointer<NativeFunction<MpvStreamCbSizeFn>> sizeFn;
  external Pointer<NativeFunction<MpvStreamCbCloseFn>> closeFn;
  external Pointer<NativeFunction<MpvStreamCbCancelFn>> cancelFn;
}

// ---------------------------------------------------------------------------
// Callback typedefs
// ---------------------------------------------------------------------------

typedef MpvWakeupFn = Void Function(Pointer<Void> d);
typedef MpvRenderUpdateFn = Void Function(Pointer<Void> cbCtx);
typedef MpvStreamCbReadFn = Int64 Function(
    Pointer<Void> cookie, Pointer<Uint8> buf, Uint64 nbytes);
typedef MpvStreamCbSeekFn = Int64 Function(Pointer<Void> cookie, Int64 offset);
typedef MpvStreamCbSizeFn = Int64 Function(Pointer<Void> cookie);
typedef MpvStreamCbCloseFn = Void Function(Pointer<Void> cookie);
typedef MpvStreamCbCancelFn = Void Function(Pointer<Void> cookie);
typedef MpvStreamCbOpenRoFn = Int32 Function(
    Pointer<Void> userData, Pointer<Utf8> uri, Pointer<MpvStreamCbInfo> info);

// ---------------------------------------------------------------------------
// Function table
// ---------------------------------------------------------------------------

typedef _H = Pointer<MpvHandle>;
typedef _S = Pointer<Utf8>;

/// 全部 54 个 libmpv 导出函数的绑定表。
///
/// Lookups are lazy (`late final`) so a binary missing an optional symbol
/// only fails when that symbol is actually used; the ABI audit guarantees
/// release binaries export all of them.
final class MpvBindings {
  MpvBindings(this.library);

  /// 已打开的 libmpv 动态库。
  final DynamicLibrary library;

  // --- client.h: lifecycle & meta --------------------------------------
  late final clientApiVersion =
      library.lookupFunction<UnsignedLong Function(), int Function()>(
          'mpv_client_api_version');
  late final errorString =
      library.lookupFunction<_S Function(Int32), _S Function(int)>(
          'mpv_error_string');
  late final free = library.lookupFunction<Void Function(Pointer<Void>),
      void Function(Pointer<Void>)>('mpv_free');
  late final clientName =
      library.lookupFunction<_S Function(_H), _S Function(_H)>(
          'mpv_client_name');
  late final clientId =
      library.lookupFunction<Int64 Function(_H), int Function(_H)>(
          'mpv_client_id');
  late final create =
      library.lookupFunction<_H Function(), _H Function()>('mpv_create');
  late final initialize =
      library.lookupFunction<Int32 Function(_H), int Function(_H)>(
          'mpv_initialize');
  late final destroy =
      library.lookupFunction<Void Function(_H), void Function(_H)>(
          'mpv_destroy');
  late final terminateDestroy =
      library.lookupFunction<Void Function(_H), void Function(_H)>(
          'mpv_terminate_destroy');
  late final createClient =
      library.lookupFunction<_H Function(_H, _S), _H Function(_H, _S)>(
          'mpv_create_client');
  late final createWeakClient =
      library.lookupFunction<_H Function(_H, _S), _H Function(_H, _S)>(
          'mpv_create_weak_client');
  late final loadConfigFile =
      library.lookupFunction<Int32 Function(_H, _S), int Function(_H, _S)>(
          'mpv_load_config_file');
  late final getTimeNs =
      library.lookupFunction<Int64 Function(_H), int Function(_H)>(
          'mpv_get_time_ns');
  late final getTimeUs =
      library.lookupFunction<Int64 Function(_H), int Function(_H)>(
          'mpv_get_time_us');

  // --- client.h: nodes & options ----------------------------------------
  late final freeNodeContents = library.lookupFunction<
      Void Function(Pointer<MpvNode>),
      void Function(Pointer<MpvNode>)>('mpv_free_node_contents');
  late final setOption = library.lookupFunction<
      Int32 Function(_H, _S, Int32, Pointer<Void>),
      int Function(_H, _S, int, Pointer<Void>)>('mpv_set_option');
  late final setOptionString = library.lookupFunction<
      Int32 Function(_H, _S, _S), int Function(_H, _S, _S)>(
      'mpv_set_option_string');

  // --- client.h: commands ------------------------------------------------
  late final command = library.lookupFunction<
      Int32 Function(_H, Pointer<_S>),
      int Function(_H, Pointer<_S>)>('mpv_command');
  late final commandNode = library.lookupFunction<
      Int32 Function(_H, Pointer<MpvNode>, Pointer<MpvNode>),
      int Function(_H, Pointer<MpvNode>, Pointer<MpvNode>)>('mpv_command_node');
  late final commandRet = library.lookupFunction<
      Int32 Function(_H, Pointer<_S>, Pointer<MpvNode>),
      int Function(_H, Pointer<_S>, Pointer<MpvNode>)>('mpv_command_ret');
  late final commandString =
      library.lookupFunction<Int32 Function(_H, _S), int Function(_H, _S)>(
          'mpv_command_string');
  late final commandAsync = library.lookupFunction<
      Int32 Function(_H, Uint64, Pointer<_S>),
      int Function(_H, int, Pointer<_S>)>('mpv_command_async');
  late final commandNodeAsync = library.lookupFunction<
      Int32 Function(_H, Uint64, Pointer<MpvNode>),
      int Function(_H, int, Pointer<MpvNode>)>('mpv_command_node_async');
  late final abortAsyncCommand = library.lookupFunction<
      Void Function(_H, Uint64), void Function(_H, int)>(
      'mpv_abort_async_command');

  // --- client.h: properties ----------------------------------------------
  late final setProperty = library.lookupFunction<
      Int32 Function(_H, _S, Int32, Pointer<Void>),
      int Function(_H, _S, int, Pointer<Void>)>('mpv_set_property');
  late final setPropertyString = library.lookupFunction<
      Int32 Function(_H, _S, _S), int Function(_H, _S, _S)>(
      'mpv_set_property_string');
  late final delProperty =
      library.lookupFunction<Int32 Function(_H, _S), int Function(_H, _S)>(
          'mpv_del_property');
  late final setPropertyAsync = library.lookupFunction<
      Int32 Function(_H, Uint64, _S, Int32, Pointer<Void>),
      int Function(_H, int, _S, int, Pointer<Void>)>('mpv_set_property_async');
  late final getProperty = library.lookupFunction<
      Int32 Function(_H, _S, Int32, Pointer<Void>),
      int Function(_H, _S, int, Pointer<Void>)>('mpv_get_property');
  late final getPropertyString =
      library.lookupFunction<_S Function(_H, _S), _S Function(_H, _S)>(
          'mpv_get_property_string');
  late final getPropertyOsdString =
      library.lookupFunction<_S Function(_H, _S), _S Function(_H, _S)>(
          'mpv_get_property_osd_string');
  late final getPropertyAsync = library.lookupFunction<
      Int32 Function(_H, Uint64, _S, Int32),
      int Function(_H, int, _S, int)>('mpv_get_property_async');
  late final observeProperty = library.lookupFunction<
      Int32 Function(_H, Uint64, _S, Int32),
      int Function(_H, int, _S, int)>('mpv_observe_property');
  late final unobserveProperty = library.lookupFunction<
      Int32 Function(_H, Uint64), int Function(_H, int)>(
      'mpv_unobserve_property');

  // --- client.h: events --------------------------------------------------
  late final eventName =
      library.lookupFunction<_S Function(Int32), _S Function(int)>(
          'mpv_event_name');
  late final eventToNode = library.lookupFunction<
      Int32 Function(Pointer<MpvNode>, Pointer<MpvEvent>),
      int Function(Pointer<MpvNode>, Pointer<MpvEvent>)>('mpv_event_to_node');
  late final requestEvent = library.lookupFunction<
      Int32 Function(_H, Int32, Int32),
      int Function(_H, int, int)>('mpv_request_event');
  late final requestLogMessages =
      library.lookupFunction<Int32 Function(_H, _S), int Function(_H, _S)>(
          'mpv_request_log_messages');
  late final waitEvent = library.lookupFunction<
      Pointer<MpvEvent> Function(_H, Double),
      Pointer<MpvEvent> Function(_H, double)>('mpv_wait_event');
  late final wakeup =
      library.lookupFunction<Void Function(_H), void Function(_H)>(
          'mpv_wakeup');
  late final setWakeupCallback = library.lookupFunction<
      Void Function(_H, Pointer<NativeFunction<MpvWakeupFn>>, Pointer<Void>),
      void Function(_H, Pointer<NativeFunction<MpvWakeupFn>>,
          Pointer<Void>)>('mpv_set_wakeup_callback');
  late final waitAsyncRequests =
      library.lookupFunction<Void Function(_H), void Function(_H)>(
          'mpv_wait_async_requests');
  late final hookAdd = library.lookupFunction<
      Int32 Function(_H, Uint64, _S, Int32),
      int Function(_H, int, _S, int)>('mpv_hook_add');
  late final hookContinue = library.lookupFunction<
      Int32 Function(_H, Uint64), int Function(_H, int)>('mpv_hook_continue');
  late final getWakeupPipe =
      library.lookupFunction<Int32 Function(_H), int Function(_H)>(
          'mpv_get_wakeup_pipe');

  // --- render.h ----------------------------------------------------------
  late final renderContextCreate = library.lookupFunction<
      Int32 Function(
          Pointer<Pointer<MpvRenderContext>>, _H, Pointer<MpvRenderParam>),
      int Function(Pointer<Pointer<MpvRenderContext>>, _H,
          Pointer<MpvRenderParam>)>('mpv_render_context_create');
  late final renderContextSetParameter = library.lookupFunction<
      Int32 Function(Pointer<MpvRenderContext>, MpvRenderParam),
      int Function(Pointer<MpvRenderContext>,
          MpvRenderParam)>('mpv_render_context_set_parameter');
  late final renderContextGetInfo = library.lookupFunction<
      Int32 Function(Pointer<MpvRenderContext>, MpvRenderParam),
      int Function(
          Pointer<MpvRenderContext>, MpvRenderParam)>('mpv_render_context_get_info');
  late final renderContextSetUpdateCallback = library.lookupFunction<
      Void Function(Pointer<MpvRenderContext>,
          Pointer<NativeFunction<MpvRenderUpdateFn>>, Pointer<Void>),
      void Function(Pointer<MpvRenderContext>,
          Pointer<NativeFunction<MpvRenderUpdateFn>>,
          Pointer<Void>)>('mpv_render_context_set_update_callback');
  late final renderContextUpdate = library.lookupFunction<
      Uint64 Function(Pointer<MpvRenderContext>),
      int Function(Pointer<MpvRenderContext>)>('mpv_render_context_update');
  late final renderContextRender = library.lookupFunction<
      Int32 Function(Pointer<MpvRenderContext>, Pointer<MpvRenderParam>),
      int Function(Pointer<MpvRenderContext>,
          Pointer<MpvRenderParam>)>('mpv_render_context_render');
  late final renderContextReportSwap = library.lookupFunction<
      Void Function(Pointer<MpvRenderContext>),
      void Function(Pointer<MpvRenderContext>)>(
      'mpv_render_context_report_swap');
  late final renderContextFree = library.lookupFunction<
      Void Function(Pointer<MpvRenderContext>),
      void Function(Pointer<MpvRenderContext>)>('mpv_render_context_free');

  // --- stream_cb.h -------------------------------------------------------
  late final streamCbAddRo = library.lookupFunction<
      Int32 Function(_H, _S, Pointer<Void>,
          Pointer<NativeFunction<MpvStreamCbOpenRoFn>>),
      int Function(_H, _S, Pointer<Void>,
          Pointer<NativeFunction<MpvStreamCbOpenRoFn>>)>('mpv_stream_cb_add_ro');

  /// 全部绑定的 C 符号名（供 ABI 自检与测试使用）。
  static const symbols = <String>[
    'mpv_abort_async_command', 'mpv_client_api_version', 'mpv_client_id',
    'mpv_client_name', 'mpv_command', 'mpv_command_async', 'mpv_command_node',
    'mpv_command_node_async', 'mpv_command_ret', 'mpv_command_string',
    'mpv_create', 'mpv_create_client', 'mpv_create_weak_client',
    'mpv_del_property', 'mpv_destroy', 'mpv_error_string', 'mpv_event_name',
    'mpv_event_to_node', 'mpv_free', 'mpv_free_node_contents',
    'mpv_get_property', 'mpv_get_property_async',
    'mpv_get_property_osd_string', 'mpv_get_property_string',
    'mpv_get_time_ns', 'mpv_get_time_us', 'mpv_get_wakeup_pipe',
    'mpv_hook_add', 'mpv_hook_continue', 'mpv_initialize',
    'mpv_load_config_file', 'mpv_observe_property',
    'mpv_render_context_create', 'mpv_render_context_free',
    'mpv_render_context_get_info', 'mpv_render_context_render',
    'mpv_render_context_report_swap', 'mpv_render_context_set_parameter',
    'mpv_render_context_set_update_callback', 'mpv_render_context_update',
    'mpv_request_event', 'mpv_request_log_messages', 'mpv_set_option',
    'mpv_set_option_string', 'mpv_set_property', 'mpv_set_property_async',
    'mpv_set_property_string', 'mpv_set_wakeup_callback',
    'mpv_stream_cb_add_ro', 'mpv_terminate_destroy',
    'mpv_unobserve_property', 'mpv_wait_async_requests', 'mpv_wait_event',
    'mpv_wakeup',
  ];
}

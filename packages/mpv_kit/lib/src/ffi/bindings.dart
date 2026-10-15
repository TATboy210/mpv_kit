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
  /// `MPV_FORMAT_NONE` (0).
  static const none = 0;

  /// `MPV_FORMAT_STRING` (1).
  static const string = 1;

  /// `MPV_FORMAT_OSD_STRING` (2).
  static const osdString = 2;

  /// `MPV_FORMAT_FLAG` (3).
  static const flag = 3;

  /// `MPV_FORMAT_INT64` (4).
  static const int64 = 4;

  /// `MPV_FORMAT_DOUBLE` (5).
  static const double_ = 5;

  /// `MPV_FORMAT_NODE` (6).
  static const node = 6;

  /// `MPV_FORMAT_NODE_ARRAY` (7).
  static const nodeArray = 7;

  /// `MPV_FORMAT_NODE_MAP` (8).
  static const nodeMap = 8;

  /// `MPV_FORMAT_BYTE_ARRAY` (9).
  static const byteArray = 9;
}

/// `mpv_event_id` 取值。
abstract final class MpvEventId {
  /// `MPV_EVENT_NONE` (0).
  static const none = 0;

  /// `MPV_EVENT_SHUTDOWN` (1).
  static const shutdown = 1;

  /// `MPV_EVENT_LOG_MESSAGE` (2).
  static const logMessage = 2;

  /// `MPV_EVENT_GET_PROPERTY_REPLY` (3).
  static const getPropertyReply = 3;

  /// `MPV_EVENT_SET_PROPERTY_REPLY` (4).
  static const setPropertyReply = 4;

  /// `MPV_EVENT_COMMAND_REPLY` (5).
  static const commandReply = 5;

  /// `MPV_EVENT_START_FILE` (6).
  static const startFile = 6;

  /// `MPV_EVENT_END_FILE` (7).
  static const endFile = 7;

  /// `MPV_EVENT_FILE_LOADED` (8).
  static const fileLoaded = 8;

  /// `MPV_EVENT_IDLE` (11).
  static const idle = 11;

  /// `MPV_EVENT_TICK` (14).
  static const tick = 14;

  /// `MPV_EVENT_CLIENT_MESSAGE` (16).
  static const clientMessage = 16;

  /// `MPV_EVENT_VIDEO_RECONFIG` (17).
  static const videoReconfig = 17;

  /// `MPV_EVENT_AUDIO_RECONFIG` (18).
  static const audioReconfig = 18;

  /// `MPV_EVENT_SEEK` (20).
  static const seek = 20;

  /// `MPV_EVENT_PLAYBACK_RESTART` (21).
  static const playbackRestart = 21;

  /// `MPV_EVENT_PROPERTY_CHANGE` (22).
  static const propertyChange = 22;

  /// `MPV_EVENT_QUEUE_OVERFLOW` (24).
  static const queueOverflow = 24;

  /// `MPV_EVENT_HOOK` (25).
  static const hook = 25;
}

/// `mpv_render_param_type` 取值。
abstract final class MpvRenderParamType {
  /// `MPV_RENDER_PARAM_INVALID` (0).
  static const invalid = 0;

  /// `MPV_RENDER_PARAM_API_TYPE` (1).
  static const apiType = 1;

  /// `MPV_RENDER_PARAM_OPENGL_INIT_PARAMS` (2).
  static const openglInitParams = 2;

  /// `MPV_RENDER_PARAM_OPENGL_FBO` (3).
  static const openglFbo = 3;

  /// `MPV_RENDER_PARAM_FLIP_Y` (4).
  static const flipY = 4;

  /// `MPV_RENDER_PARAM_DEPTH` (5).
  static const depth = 5;

  /// `MPV_RENDER_PARAM_ICC_PROFILE` (6).
  static const iccProfile = 6;

  /// `MPV_RENDER_PARAM_AMBIENT_LIGHT` (7).
  static const ambientLight = 7;

  /// `MPV_RENDER_PARAM_X11_DISPLAY` (8).
  static const x11Display = 8;

  /// `MPV_RENDER_PARAM_WL_DISPLAY` (9).
  static const wlDisplay = 9;

  /// `MPV_RENDER_PARAM_ADVANCED_CONTROL` (10).
  static const advancedControl = 10;

  /// `MPV_RENDER_PARAM_NEXT_FRAME_INFO` (11).
  static const nextFrameInfo = 11;

  /// `MPV_RENDER_PARAM_BLOCK_FOR_TARGET_TIME` (12).
  static const blockForTargetTime = 12;

  /// `MPV_RENDER_PARAM_SKIP_RENDERING` (13).
  static const skipRendering = 13;

  /// `MPV_RENDER_PARAM_DRM_DISPLAY` (14).
  static const drmDisplay = 14;

  /// `MPV_RENDER_PARAM_DRM_DRAW_SURFACE_SIZE` (15).
  static const drmDrawSurfaceSize = 15;

  /// `MPV_RENDER_PARAM_DRM_DISPLAY_V2` (16).
  static const drmDisplayV2 = 16;

  /// `MPV_RENDER_PARAM_SW_SIZE` (17).
  static const swSize = 17;

  /// `MPV_RENDER_PARAM_SW_FORMAT` (18).
  static const swFormat = 18;

  /// `MPV_RENDER_PARAM_SW_STRIDE` (19).
  static const swStride = 19;

  /// `MPV_RENDER_PARAM_SW_POINTER` (20).
  static const swPointer = 20;
}

// ---------------------------------------------------------------------------
// Structs
// ---------------------------------------------------------------------------

/// `mpv_node` 的 union 成员。
final class MpvNodeUnion extends Union {
  /// C field `string`.
  external Pointer<Utf8> string;

  /// C field `flag`.
  @Int32()
  external int flag;

  /// C field `int64`.
  @Int64()
  external int int64;

  /// C field `double_`.
  @Double()
  external double double_;

  /// C field `list`.
  external Pointer<MpvNodeList> list;

  /// C field `ba`.
  external Pointer<MpvByteArray> ba;
}

/// `mpv_node`。
final class MpvNode extends Struct {
  /// C field `u`.
  external MpvNodeUnion u;

  /// C field `format`.
  @Int32()
  external int format;
}

/// `mpv_node_list`。
final class MpvNodeList extends Struct {
  /// C field `num`.
  @Int32()
  external int num;

  /// C field `values`.
  external Pointer<MpvNode> values;

  /// C field `keys`.
  external Pointer<Pointer<Utf8>> keys;
}

/// `mpv_byte_array`。
final class MpvByteArray extends Struct {
  /// C field `data`.
  external Pointer<Void> data;

  /// C field `size`.
  @Size()
  external int size;
}

/// `mpv_event`。
final class MpvEvent extends Struct {
  /// C field `event_id`.
  @Int32()
  external int eventId;

  /// C field `error`.
  @Int32()
  external int error;

  /// C field `reply_userdata`.
  @Uint64()
  external int replyUserdata;

  /// C field `data`.
  external Pointer<Void> data;
}

/// `mpv_event_property`。
final class MpvEventProperty extends Struct {
  /// C field `name`.
  external Pointer<Utf8> name;

  /// C field `format`.
  @Int32()
  external int format;

  /// C field `data`.
  external Pointer<Void> data;
}

/// `mpv_event_log_message`。
final class MpvEventLogMessage extends Struct {
  /// C field `prefix`.
  external Pointer<Utf8> prefix;

  /// C field `level`.
  external Pointer<Utf8> level;

  /// C field `text`.
  external Pointer<Utf8> text;

  /// C field `log_level`.
  @Int32()
  external int logLevel;
}

/// `mpv_event_start_file`。
final class MpvEventStartFile extends Struct {
  /// C field `playlist_entry_id`.
  @Int64()
  external int playlistEntryId;
}

/// `mpv_event_end_file`。
final class MpvEventEndFile extends Struct {
  /// C field `reason`.
  @Int32()
  external int reason;

  /// C field `error`.
  @Int32()
  external int error;

  /// C field `playlist_entry_id`.
  @Int64()
  external int playlistEntryId;

  /// C field `playlist_insert_id`.
  @Int64()
  external int playlistInsertId;

  /// C field `playlist_insert_num_entries`.
  @Int32()
  external int playlistInsertNumEntries;
}

/// `mpv_event_client_message`。
final class MpvEventClientMessage extends Struct {
  /// C field `num_args`.
  @Int32()
  external int numArgs;

  /// C field `args`.
  external Pointer<Pointer<Utf8>> args;
}

/// `mpv_event_hook`。
final class MpvEventHook extends Struct {
  /// C field `name`.
  external Pointer<Utf8> name;

  /// C field `id`.
  @Uint64()
  external int id;
}

/// `mpv_event_command`。
final class MpvEventCommand extends Struct {
  /// C field `result`.
  external MpvNode result;
}

/// `mpv_render_param`。
final class MpvRenderParam extends Struct {
  /// C field `type`.
  @Int32()
  external int type;

  /// C field `data`.
  external Pointer<Void> data;
}

/// `mpv_stream_cb_info`。
final class MpvStreamCbInfo extends Struct {
  /// C field `cookie`.
  external Pointer<Void> cookie;

  /// C field `read_fn`.
  external Pointer<NativeFunction<MpvStreamCbReadFn>> readFn;

  /// C field `seek_fn`.
  external Pointer<NativeFunction<MpvStreamCbSeekFn>> seekFn;

  /// C field `size_fn`.
  external Pointer<NativeFunction<MpvStreamCbSizeFn>> sizeFn;

  /// C field `close_fn`.
  external Pointer<NativeFunction<MpvStreamCbCloseFn>> closeFn;

  /// C field `cancel_fn`.
  external Pointer<NativeFunction<MpvStreamCbCancelFn>> cancelFn;
}

// ---------------------------------------------------------------------------
// Callback typedefs
// ---------------------------------------------------------------------------

/// Callback of `mpv_set_wakeup_callback`.
typedef MpvWakeupFn = Void Function(Pointer<Void> d);

/// Callback of `mpv_render_context_set_update_callback`.
typedef MpvRenderUpdateFn = Void Function(Pointer<Void> cbCtx);

/// `mpv_stream_cb_read_fn`.
typedef MpvStreamCbReadFn = Int64 Function(
    Pointer<Void> cookie, Pointer<Uint8> buf, Uint64 nbytes);

/// `mpv_stream_cb_seek_fn`.
typedef MpvStreamCbSeekFn = Int64 Function(Pointer<Void> cookie, Int64 offset);

/// `mpv_stream_cb_size_fn`.
typedef MpvStreamCbSizeFn = Int64 Function(Pointer<Void> cookie);

/// `mpv_stream_cb_close_fn`.
typedef MpvStreamCbCloseFn = Void Function(Pointer<Void> cookie);

/// `mpv_stream_cb_cancel_fn`.
typedef MpvStreamCbCancelFn = Void Function(Pointer<Void> cookie);

/// `mpv_stream_cb_open_ro_fn`.
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
  /// Binds the symbols of an opened libmpv [library].
  MpvBindings(this.library);

  /// 已打开的 libmpv 动态库。
  final DynamicLibrary library;

  // --- client.h: lifecycle & meta --------------------------------------
  /// `mpv_client_api_version`.
  late final clientApiVersion =
      library.lookupFunction<UnsignedLong Function(), int Function()>(
          'mpv_client_api_version');

  /// `mpv_error_string`.
  late final errorString =
      library.lookupFunction<_S Function(Int32), _S Function(int)>(
          'mpv_error_string');

  /// `mpv_free`.
  late final free = library.lookupFunction<Void Function(Pointer<Void>),
      void Function(Pointer<Void>)>('mpv_free');

  /// `mpv_client_name`.
  late final clientName =
      library.lookupFunction<_S Function(_H), _S Function(_H)>(
          'mpv_client_name');

  /// `mpv_client_id`.
  late final clientId =
      library.lookupFunction<Int64 Function(_H), int Function(_H)>(
          'mpv_client_id');

  /// `mpv_create`.
  late final create =
      library.lookupFunction<_H Function(), _H Function()>('mpv_create');

  /// `mpv_initialize`.
  late final initialize =
      library.lookupFunction<Int32 Function(_H), int Function(_H)>(
          'mpv_initialize');

  /// `mpv_destroy`.
  late final destroy =
      library.lookupFunction<Void Function(_H), void Function(_H)>(
          'mpv_destroy');

  /// `mpv_terminate_destroy`.
  late final terminateDestroy =
      library.lookupFunction<Void Function(_H), void Function(_H)>(
          'mpv_terminate_destroy');

  /// `mpv_create_client`.
  late final createClient =
      library.lookupFunction<_H Function(_H, _S), _H Function(_H, _S)>(
          'mpv_create_client');

  /// `mpv_create_weak_client`.
  late final createWeakClient =
      library.lookupFunction<_H Function(_H, _S), _H Function(_H, _S)>(
          'mpv_create_weak_client');

  /// `mpv_load_config_file`.
  late final loadConfigFile =
      library.lookupFunction<Int32 Function(_H, _S), int Function(_H, _S)>(
          'mpv_load_config_file');

  /// `mpv_get_time_ns`.
  late final getTimeNs =
      library.lookupFunction<Int64 Function(_H), int Function(_H)>(
          'mpv_get_time_ns');

  /// `mpv_get_time_us`.
  late final getTimeUs =
      library.lookupFunction<Int64 Function(_H), int Function(_H)>(
          'mpv_get_time_us');

  // --- client.h: nodes & options ----------------------------------------
  /// `mpv_free_node_contents`.
  late final freeNodeContents = library.lookupFunction<
      Void Function(Pointer<MpvNode>),
      void Function(Pointer<MpvNode>)>('mpv_free_node_contents');

  /// `mpv_set_option`.
  late final setOption = library.lookupFunction<
      Int32 Function(_H, _S, Int32, Pointer<Void>),
      int Function(_H, _S, int, Pointer<Void>)>('mpv_set_option');

  /// `mpv_set_option_string`.
  late final setOptionString = library.lookupFunction<
      Int32 Function(_H, _S, _S), int Function(_H, _S, _S)>(
      'mpv_set_option_string');

  // --- client.h: commands ------------------------------------------------
  /// `mpv_command`.
  late final command = library.lookupFunction<
      Int32 Function(_H, Pointer<_S>),
      int Function(_H, Pointer<_S>)>('mpv_command');

  /// `mpv_command_node`.
  late final commandNode = library.lookupFunction<
      Int32 Function(_H, Pointer<MpvNode>, Pointer<MpvNode>),
      int Function(_H, Pointer<MpvNode>, Pointer<MpvNode>)>('mpv_command_node');

  /// `mpv_command_ret`.
  late final commandRet = library.lookupFunction<
      Int32 Function(_H, Pointer<_S>, Pointer<MpvNode>),
      int Function(_H, Pointer<_S>, Pointer<MpvNode>)>('mpv_command_ret');

  /// `mpv_command_string`.
  late final commandString =
      library.lookupFunction<Int32 Function(_H, _S), int Function(_H, _S)>(
          'mpv_command_string');

  /// `mpv_command_async`.
  late final commandAsync = library.lookupFunction<
      Int32 Function(_H, Uint64, Pointer<_S>),
      int Function(_H, int, Pointer<_S>)>('mpv_command_async');

  /// `mpv_command_node_async`.
  late final commandNodeAsync = library.lookupFunction<
      Int32 Function(_H, Uint64, Pointer<MpvNode>),
      int Function(_H, int, Pointer<MpvNode>)>('mpv_command_node_async');

  /// `mpv_abort_async_command`.
  late final abortAsyncCommand = library.lookupFunction<
      Void Function(_H, Uint64), void Function(_H, int)>(
      'mpv_abort_async_command');

  // --- client.h: properties ----------------------------------------------
  /// `mpv_set_property`.
  late final setProperty = library.lookupFunction<
      Int32 Function(_H, _S, Int32, Pointer<Void>),
      int Function(_H, _S, int, Pointer<Void>)>('mpv_set_property');

  /// `mpv_set_property_string`.
  late final setPropertyString = library.lookupFunction<
      Int32 Function(_H, _S, _S), int Function(_H, _S, _S)>(
      'mpv_set_property_string');

  /// `mpv_del_property`.
  late final delProperty =
      library.lookupFunction<Int32 Function(_H, _S), int Function(_H, _S)>(
          'mpv_del_property');

  /// `mpv_set_property_async`.
  late final setPropertyAsync = library.lookupFunction<
      Int32 Function(_H, Uint64, _S, Int32, Pointer<Void>),
      int Function(_H, int, _S, int, Pointer<Void>)>('mpv_set_property_async');

  /// `mpv_get_property`.
  late final getProperty = library.lookupFunction<
      Int32 Function(_H, _S, Int32, Pointer<Void>),
      int Function(_H, _S, int, Pointer<Void>)>('mpv_get_property');

  /// `mpv_get_property_string`.
  late final getPropertyString =
      library.lookupFunction<_S Function(_H, _S), _S Function(_H, _S)>(
          'mpv_get_property_string');

  /// `mpv_get_property_osd_string`.
  late final getPropertyOsdString =
      library.lookupFunction<_S Function(_H, _S), _S Function(_H, _S)>(
          'mpv_get_property_osd_string');

  /// `mpv_get_property_async`.
  late final getPropertyAsync = library.lookupFunction<
      Int32 Function(_H, Uint64, _S, Int32),
      int Function(_H, int, _S, int)>('mpv_get_property_async');

  /// `mpv_observe_property`.
  late final observeProperty = library.lookupFunction<
      Int32 Function(_H, Uint64, _S, Int32),
      int Function(_H, int, _S, int)>('mpv_observe_property');

  /// `mpv_unobserve_property`.
  late final unobserveProperty = library.lookupFunction<
      Int32 Function(_H, Uint64), int Function(_H, int)>(
      'mpv_unobserve_property');

  // --- client.h: events --------------------------------------------------
  /// `mpv_event_name`.
  late final eventName =
      library.lookupFunction<_S Function(Int32), _S Function(int)>(
          'mpv_event_name');

  /// `mpv_event_to_node`.
  late final eventToNode = library.lookupFunction<
      Int32 Function(Pointer<MpvNode>, Pointer<MpvEvent>),
      int Function(Pointer<MpvNode>, Pointer<MpvEvent>)>('mpv_event_to_node');

  /// `mpv_request_event`.
  late final requestEvent = library.lookupFunction<
      Int32 Function(_H, Int32, Int32),
      int Function(_H, int, int)>('mpv_request_event');

  /// `mpv_request_log_messages`.
  late final requestLogMessages =
      library.lookupFunction<Int32 Function(_H, _S), int Function(_H, _S)>(
          'mpv_request_log_messages');

  /// `mpv_wait_event`.
  late final waitEvent = library.lookupFunction<
      Pointer<MpvEvent> Function(_H, Double),
      Pointer<MpvEvent> Function(_H, double)>('mpv_wait_event');

  /// `mpv_wakeup`.
  late final wakeup =
      library.lookupFunction<Void Function(_H), void Function(_H)>(
          'mpv_wakeup');

  /// `mpv_set_wakeup_callback`.
  late final setWakeupCallback = library.lookupFunction<
      Void Function(_H, Pointer<NativeFunction<MpvWakeupFn>>, Pointer<Void>),
      void Function(_H, Pointer<NativeFunction<MpvWakeupFn>>,
          Pointer<Void>)>('mpv_set_wakeup_callback');

  /// `mpv_wait_async_requests`.
  late final waitAsyncRequests =
      library.lookupFunction<Void Function(_H), void Function(_H)>(
          'mpv_wait_async_requests');

  /// `mpv_hook_add`.
  late final hookAdd = library.lookupFunction<
      Int32 Function(_H, Uint64, _S, Int32),
      int Function(_H, int, _S, int)>('mpv_hook_add');

  /// `mpv_hook_continue`.
  late final hookContinue = library.lookupFunction<
      Int32 Function(_H, Uint64), int Function(_H, int)>('mpv_hook_continue');

  /// `mpv_get_wakeup_pipe`.
  late final getWakeupPipe =
      library.lookupFunction<Int32 Function(_H), int Function(_H)>(
          'mpv_get_wakeup_pipe');

  // --- render.h ----------------------------------------------------------
  /// `mpv_render_context_create`.
  late final renderContextCreate = library.lookupFunction<
      Int32 Function(
          Pointer<Pointer<MpvRenderContext>>, _H, Pointer<MpvRenderParam>),
      int Function(Pointer<Pointer<MpvRenderContext>>, _H,
          Pointer<MpvRenderParam>)>('mpv_render_context_create');

  /// `mpv_render_context_set_parameter`.
  late final renderContextSetParameter = library.lookupFunction<
      Int32 Function(Pointer<MpvRenderContext>, MpvRenderParam),
      int Function(Pointer<MpvRenderContext>,
          MpvRenderParam)>('mpv_render_context_set_parameter');

  /// `mpv_render_context_get_info`.
  late final renderContextGetInfo = library.lookupFunction<
      Int32 Function(Pointer<MpvRenderContext>, MpvRenderParam),
      int Function(
          Pointer<MpvRenderContext>, MpvRenderParam)>('mpv_render_context_get_info');

  /// `mpv_render_context_set_update_callback`.
  late final renderContextSetUpdateCallback = library.lookupFunction<
      Void Function(Pointer<MpvRenderContext>,
          Pointer<NativeFunction<MpvRenderUpdateFn>>, Pointer<Void>),
      void Function(Pointer<MpvRenderContext>,
          Pointer<NativeFunction<MpvRenderUpdateFn>>,
          Pointer<Void>)>('mpv_render_context_set_update_callback');

  /// `mpv_render_context_update`.
  late final renderContextUpdate = library.lookupFunction<
      Uint64 Function(Pointer<MpvRenderContext>),
      int Function(Pointer<MpvRenderContext>)>('mpv_render_context_update');

  /// `mpv_render_context_render`.
  late final renderContextRender = library.lookupFunction<
      Int32 Function(Pointer<MpvRenderContext>, Pointer<MpvRenderParam>),
      int Function(Pointer<MpvRenderContext>,
          Pointer<MpvRenderParam>)>('mpv_render_context_render');

  /// `mpv_render_context_report_swap`.
  late final renderContextReportSwap = library.lookupFunction<
      Void Function(Pointer<MpvRenderContext>),
      void Function(Pointer<MpvRenderContext>)>(
      'mpv_render_context_report_swap');

  /// `mpv_render_context_free`.
  late final renderContextFree = library.lookupFunction<
      Void Function(Pointer<MpvRenderContext>),
      void Function(Pointer<MpvRenderContext>)>('mpv_render_context_free');

  // --- stream_cb.h -------------------------------------------------------
  /// `mpv_stream_cb_add_ro`.
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

/// `Mpv` — libmpv client API 的 1:1 低层封装。
///
/// Thread model: all methods are synchronous FFI calls that libmpv documents
/// as thread-safe. Events are delivered on the owning isolate's event loop:
/// mpv's wakeup callback (any native thread) posts to a
/// `NativeCallable.listener`, which drains `mpv_wait_event(0)` until empty.
library;

import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:meta/meta.dart';

import '../ffi/bindings.dart';
import '../ffi/library.dart';
import '../generated/option_types.dart';
import 'errors.dart';
import 'events.dart';
import 'node.dart';
import 'stream_bridge.dart';

/// 一个 mpv 客户端（主句柄或通过 [createClient] 派生的子客户端）。
final class Mpv {
  Mpv._(this.bindings, this.handle, {required bool owner}) : _owner = owner {
    _wakeup = NativeCallable<MpvWakeupFn>.listener(_onWakeup);
    bindings.setWakeupCallback(handle, _wakeup.nativeFunction, nullptr);
  }

  /// 创建一个未初始化的 mpv 实例（对应 `mpv_create`）。
  ///
  /// [options] are applied before `mpv_initialize` (only init-time options
  /// such as `config`, `vo`, `hwdec` need this). Pass `initialize: false` to
  /// set further options with [setOption] before calling [initialize].
  /// Secure defaults: `load-scripts=no`, `ytdl=no`, `config=no`,
  /// `input-default-bindings=no`, `osc=no` — external code execution must be
  /// re-enabled explicitly by the caller.
  factory Mpv.create({
    String? libraryPath,
    Map<String, String> options = const {},
    bool secureDefaults = true,
    bool initialize = true,
  }) {
    final b = MpvLibrary.open(path: libraryPath);
    final h = b.create();
    if (h == nullptr) {
      throw const MpvException(
        -2,
        'mpv_create returned NULL',
        operation: 'create',
      );
    }
    final mpv = Mpv._(b, h, owner: true);
    try {
      if (secureDefaults) {
        for (final e in secureDefaultOptions.entries) {
          if (options.containsKey(e.key)) continue;
          try {
            mpv.setOptionString(e.key, e.value);
          } on MpvException catch (err) {
            // Builds without Lua have no `ytdl`/`osc` options: the feature is
            // absent, so there is nothing to disable.
            if (err.error != MpvError.optionNotFound) rethrow;
          }
        }
      }
      for (final e in options.entries) {
        try {
          mpv.setOptionString(e.key, e.value);
        } on MpvException catch (err) {
          // The option pack (see Player) carries enhancement options that
          // newer mpv versions added; an older libmpv — or a build with the
          // feature compiled out — reports optionNotFound. The feature is
          // absent, so there is nothing to set: keep the rest and continue
          // (same contract as secureDefaults above).
          if (err.error != MpvError.optionNotFound) rethrow;
        }
      }
      if (initialize) mpv.initialize();
    } on Object {
      mpv.dispose();
      rethrow;
    }
    return mpv;
  }

  /// 默认关闭的“执行外部代码/读取用户配置”类选项。
  static const secureDefaultOptions = <String, String>{
    'config': 'no',
    'load-scripts': 'no',
    'ytdl': 'no',
    'input-default-bindings': 'no',
    'input-vo-keyboard': 'no',
    'osc': 'no',
  };

  /// 底层绑定表（高级用法：直接调用未封装的符号）。
  final MpvBindings bindings;

  /// 原始 `mpv_handle*`，可传给渲染插件等原生代码。
  final Pointer<MpvHandle> handle;

  final bool _owner;
  late final NativeCallable<MpvWakeupFn> _wakeup;
  final _events = StreamController<MpvEventData>.broadcast(sync: true);
  final _pending = <int, Completer<Object?>>{};
  final _observers = <int, StreamController<Object?>>{};
  final _streamBridges = <StreamBridge>[];
  var _nextId = 1;
  var _disposed = false;
  var _nativeEntries = 0;

  /// 全部事件流（广播）。
  Stream<MpvEventData> get events => _events.stream;

  /// 句柄是否已销毁。
  bool get isDisposed => _disposed;

  /// 通过存活检查、进入 native 边界的调用次数（仅测试使用）。
  ///
  /// It increments only after the `_disposed` check passes, so a rejected
  /// post-dispose call can never be mistaken for a native entry.
  @visibleForTesting
  int get nativeEntriesForTesting => _nativeEntries;

  // ---------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------

  /// `mpv_initialize`。
  void initialize() {
    _ensureAlive();
    _check(bindings.initialize(handle), 'initialize');
  }

  /// `mpv_client_name`。
  String get clientName {
    _ensureAlive();
    return readUtf8(bindings.clientName(handle));
  }

  /// `mpv_client_id`。
  int get clientId {
    _ensureAlive();
    return bindings.clientId(handle);
  }

  /// `mpv_get_time_ns`（mpv 内部单调时钟）。
  int get timeNs {
    _ensureAlive();
    return bindings.getTimeNs(handle);
  }

  /// `mpv_create_client` / `mpv_create_weak_client`：派生共享同一核心的子客户端。
  Mpv createClient(String name, {bool weak = false}) {
    _ensureAlive();
    final h = using((a) {
      final n = name.toNativeUtf8(allocator: a);
      return weak
          ? bindings.createWeakClient(handle, n)
          : bindings.createClient(handle, n);
    });
    if (h == nullptr) {
      throw const MpvException(
        -2,
        'client creation failed',
        operation: 'create_client',
      );
    }
    return Mpv._(bindings, h, owner: false);
  }

  /// `mpv_load_config_file`。
  void loadConfigFile(String path) {
    _ensureAlive();
    using(
      (a) => _check(
        bindings.loadConfigFile(handle, path.toNativeUtf8(allocator: a)),
        'load_config_file($path)',
      ),
    );
  }

  /// 销毁句柄。主句柄使用 `mpv_terminate_destroy` 终止核心。
  ///
  /// Idempotent. Pending futures complete with an error and observer streams
  /// are closed.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    // Order matters: null the wakeup callback while the handle is still alive
    // (calling it after `mpv_terminate_destroy` would be a use-after-free),
    // then let mpv threads blocked on Dart stream sources return, then destroy
    // the core, and only then close the `NativeCallable` — once the core is
    // gone no native thread can invoke it any more.
    bindings.setWakeupCallback(handle, nullptr, nullptr);
    // Unblock mpv threads waiting on Dart stream sources, or destroying the
    // core would wait for them forever (this isolate is busy right here).
    for (final b in _streamBridges) {
      b.shutdown();
    }
    (_owner ? bindings.terminateDestroy : bindings.destroy)(handle);
    _wakeup.close();
    for (final b in _streamBridges) {
      b.close();
    }
    _streamBridges.clear();
    for (final c in _pending.values) {
      c.completeError(StateError('mpv handle disposed'));
    }
    _pending.clear();
    // Closing an observer controller runs its `onCancel`, which removes the
    // entry from `_observers`; iterate a snapshot so that mutation cannot
    // corrupt the iteration.
    for (final c in _observers.values.toList()) {
      _closeIfOpen(c);
    }
    _observers.clear();
    _closeIfOpen(_events);
  }

  // ---------------------------------------------------------------------
  // Options
  // ---------------------------------------------------------------------

  /// `mpv_set_option_string`。
  void setOptionString(String name, String value) {
    _ensureAlive();
    using(
      (a) => _check(
        bindings.setOptionString(
          handle,
          name.toNativeUtf8(allocator: a),
          value.toNativeUtf8(allocator: a),
        ),
        'set_option($name)',
      ),
    );
  }

  /// `mpv_set_option`（MPV_FORMAT_NODE）。
  void setOption(String name, Object? value) {
    _ensureAlive();
    using(
      (a) => _check(
        bindings.setOption(
          handle,
          name.toNativeUtf8(allocator: a),
          MpvFormat.node,
          writeNode(value, a).cast(),
        ),
        'set_option($name)',
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Commands
  // ---------------------------------------------------------------------

  /// `mpv_command_node`：执行命令并返回结果。
  ///
  /// [args] may be a positional list (`['loadfile', path]`) or a named map
  /// (`{'name': 'loadfile', 'url': path}`).
  Object? command(Object args) {
    _ensureAlive();
    return using((a) {
      final result = a<MpvNode>();
      _check(
        bindings.commandNode(handle, writeNode(args, a), result),
        'command(${_describe(args)})',
      );
      try {
        return readNode(result);
      } finally {
        bindings.freeNodeContents(result);
      }
    });
  }

  /// `mpv_command_string`：解析 input.conf 语法的命令串。
  void commandString(String command) {
    _ensureAlive();
    using(
      (a) => _check(
        bindings.commandString(handle, command.toNativeUtf8(allocator: a)),
        'command_string($command)',
      ),
    );
  }

  /// `mpv_command_node_async`：异步命令，结果经 COMMAND_REPLY 事件返回。
  ///
  /// Returns a [MpvAsyncCommand] whose `abort()` maps to
  /// `mpv_abort_async_command`.
  MpvAsyncCommand commandAsync(Object args) {
    _ensureAlive();
    final id = _allocId();
    final c = Completer<Object?>();
    _pending[id] = c;
    using((a) {
      final rc = bindings.commandNodeAsync(handle, id, writeNode(args, a));
      if (rc < 0) {
        _pending.remove(id);
        c.completeError(_error(rc, 'command_async(${_describe(args)})'));
      }
    });
    return MpvAsyncCommand._(this, id, c.future);
  }

  // ---------------------------------------------------------------------
  // Properties
  // ---------------------------------------------------------------------

  /// `mpv_set_property`（MPV_FORMAT_NODE，自动类型转换）。
  void setProperty(String name, Object? value) {
    _ensureAlive();
    using(
      (a) => _check(
        bindings.setProperty(
          handle,
          name.toNativeUtf8(allocator: a),
          MpvFormat.node,
          writeNode(value, a).cast(),
        ),
        'set_property($name)',
      ),
    );
  }

  /// `mpv_set_property_string`。
  void setPropertyString(String name, String value) {
    _ensureAlive();
    using(
      (a) => _check(
        bindings.setPropertyString(
          handle,
          name.toNativeUtf8(allocator: a),
          value.toNativeUtf8(allocator: a),
        ),
        'set_property($name)',
      ),
    );
  }

  /// `mpv_del_property`。
  void deleteProperty(String name) {
    _ensureAlive();
    using(
      (a) => _check(
        bindings.delProperty(handle, name.toNativeUtf8(allocator: a)),
        'del_property($name)',
      ),
    );
  }

  /// `mpv_get_property`（MPV_FORMAT_NODE）。
  Object? getProperty(String name) {
    _ensureAlive();
    return using((a) {
      final node = a<MpvNode>();
      _check(
        bindings.getProperty(
          handle,
          name.toNativeUtf8(allocator: a),
          MpvFormat.node,
          node.cast(),
        ),
        'get_property($name)',
      );
      try {
        return readNode(node);
      } finally {
        bindings.freeNodeContents(node);
      }
    });
  }

  /// 读取属性，不可用/不存在时返回 null 而不是抛错。
  Object? tryGetProperty(String name) {
    // Guard at this entry too: the inner `on MpvException` must not be able to
    // convert a post-dispose StateError into a silent null.
    _ensureAlive();
    try {
      return getProperty(name);
    } on MpvException catch (e) {
      if (e.error == MpvError.propertyUnavailable ||
          e.error == MpvError.propertyNotFound) {
        return null;
      }
      rethrow;
    }
  }

  /// `mpv_get_property_string` / `mpv_get_property_osd_string`。
  String? getPropertyString(String name, {bool osd = false}) {
    _ensureAlive();
    return using((a) {
      final n = name.toNativeUtf8(allocator: a);
      final p = osd
          ? bindings.getPropertyOsdString(handle, n)
          : bindings.getPropertyString(handle, n);
      if (p == nullptr) return null;
      try {
        return readUtf8(p);
      } finally {
        bindings.free(p.cast());
      }
    });
  }

  /// `mpv_set_property_async`。
  Future<void> setPropertyAsync(String name, Object? value) {
    _ensureAlive();
    final id = _allocId();
    final c = Completer<Object?>();
    _pending[id] = c;
    using((a) {
      final rc = bindings.setPropertyAsync(
        handle,
        id,
        name.toNativeUtf8(allocator: a),
        MpvFormat.node,
        writeNode(value, a).cast(),
      );
      if (rc < 0) {
        _pending.remove(id);
        c.completeError(_error(rc, 'set_property_async($name)'));
      }
    });
    return c.future;
  }

  /// `mpv_get_property_async`。
  Future<Object?> getPropertyAsync(String name) {
    _ensureAlive();
    final id = _allocId();
    final c = Completer<Object?>();
    _pending[id] = c;
    using((a) {
      final rc = bindings.getPropertyAsync(
        handle,
        id,
        name.toNativeUtf8(allocator: a),
        MpvFormat.node,
      );
      if (rc < 0) {
        _pending.remove(id);
        c.completeError(_error(rc, 'get_property_async($name)'));
      }
    });
    return c.future;
  }

  /// `mpv_observe_property`：返回属性值变化流（立即推送一次当前值）。
  ///
  /// Cancelling the last subscription calls `mpv_unobserve_property`.
  Stream<Object?> observeProperty(String name) {
    _ensureAlive();
    final id = _allocId();
    late final StreamController<Object?> controller;
    controller = StreamController<Object?>(
      sync: true,
      onListen: () {
        // A stream created before dispose but listened to afterwards must not
        // enter native code: the handle has already been destroyed.
        if (_disposed) {
          controller.addError(StateError('Mpv has been disposed'));
          unawaited(controller.close());
          return;
        }
        // Past the check: this subscription is the native entry point.
        _nativeEntries++;
        using((a) {
          final rc = bindings.observeProperty(
            handle,
            id,
            name.toNativeUtf8(allocator: a),
            MpvFormat.node,
          );
          if (rc < 0) {
            controller.addError(_error(rc, 'observe_property($name)'));
            unawaited(controller.close());
          } else {
            _observers[id] = controller;
          }
        });
      },
      onCancel: () {
        if (_observers.remove(id) != null && !_disposed) {
          bindings.unobserveProperty(handle, id);
        }
      },
    );
    return controller.stream;
  }

  /// Reads [option] (see `MpvOptions`) as its Dart type; null when the
  /// value is unavailable (e.g. `no` for an optional number).
  T? getOptionValue<T extends Object>(MpvOption<T> option) {
    _ensureAlive();
    final Object? v = switch (option.type) {
      MpvOptionType.flag => switch (tryGetProperty(option.name)) {
        final bool b => b,
        _ => null,
      },
      MpvOptionType.integer => switch (tryGetProperty(option.name)) {
        final int i => i,
        final double d => d.round(),
        _ => null,
      },
      MpvOptionType.real => switch (tryGetProperty(option.name)) {
        final num n => n.toDouble(),
        _ => null,
      },
      MpvOptionType.choice ||
      MpvOptionType.string => getPropertyString(option.name),
    };
    return v is T ? v : null;
  }

  /// Sets [option] at runtime after checking the declared choices/range.
  /// Init-only options must be passed to [Mpv.create] instead.
  void setOptionValue<T extends Object>(MpvOption<T> option, T value) {
    _ensureAlive();
    option.check(value);
    switch (value) {
      case final String s:
        setPropertyString(option.name, s);
      default:
        setProperty(option.name, value);
    }
  }

  /// Serves `protocol://` URIs from Dart: mpv asks [open] for a
  /// [MpvStreamSource] whenever such a URI is loaded (e.g. `loadfile
  /// dart://movie`). Useful for encrypted files, in-memory media or custom
  /// network transports. One registration per protocol and core.
  ///
  /// Throws [UnsupportedError] if the loaded libmpv lacks the mpv_kit stream
  /// bridge, [MpvException] if the protocol is taken.
  void registerStreamProtocol(String protocol, MpvStreamOpener open) {
    _ensureAlive();
    _streamBridges.add(StreamBridge.register(bindings, handle, protocol, open));
  }

  // ---------------------------------------------------------------------
  // Events, logs, hooks
  // ---------------------------------------------------------------------

  /// `mpv_request_log_messages`（`no`/`fatal`/`error`/`warn`/`info`/`v`/`debug`/`trace`）。
  void requestLogMessages(String minLevel) {
    _ensureAlive();
    using(
      (a) => _check(
        bindings.requestLogMessages(handle, minLevel.toNativeUtf8(allocator: a)),
        'request_log_messages($minLevel)',
      ),
    );
  }

  /// `mpv_request_event`：启用/禁用某类事件。
  void requestEvent(int eventId, {required bool enable}) {
    _ensureAlive();
    _check(
      bindings.requestEvent(handle, eventId, enable ? 1 : 0),
      'request_event($eventId)',
    );
  }

  /// `mpv_hook_add`：注册 hook（如 `on_load`）；在 [events] 上收到
  /// [HookEvent] 后必须调用 [hookContinue]。
  void hookAdd(String name, {int priority = 0}) {
    _ensureAlive();
    using(
      (a) => _check(
        bindings.hookAdd(
          handle,
          _allocId(),
          name.toNativeUtf8(allocator: a),
          priority,
        ),
        'hook_add($name)',
      ),
    );
  }

  /// `mpv_hook_continue`。
  void hookContinue(int id) {
    _ensureAlive();
    _check(bindings.hookContinue(handle, id), 'hook_continue');
  }

  /// `mpv_wakeup`：打断阻塞中的 wait_event。
  void wakeup() {
    _ensureAlive();
    bindings.wakeup(handle);
  }

  /// `mpv_wait_async_requests`：阻塞直到所有异步请求完成（慎用：阻塞当前 isolate）。
  void waitAsyncRequests() {
    _ensureAlive();
    bindings.waitAsyncRequests(handle);
  }

  /// `mpv_error_string`。
  String errorString(int code) {
    _ensureAlive();
    return readUtf8(bindings.errorString(code));
  }

  /// `mpv_event_name`。
  String eventName(int eventId) {
    _ensureAlive();
    return readUtf8(bindings.eventName(eventId));
  }

  // ---------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------

  /// Rejects calls against a destroyed handle before any FFI entry.
  ///
  /// Every public method that can reach the native handle starts with this
  /// check, so a late timer or widget callback becomes a catchable
  /// [StateError] instead of a process-level use-after-free. The counter is
  /// incremented only past the check: a rejected call is never a native entry.
  void _ensureAlive() {
    if (_disposed) throw StateError('Mpv has been disposed');
    _nativeEntries++;
  }

  int _allocId() => _nextId++;

  /// 唤醒回调：在本 isolate 上排空事件队列（非阻塞）。
  void _onWakeup(Pointer<Void> _) {
    while (!_disposed) {
      final p = bindings.waitEvent(handle, 0);
      if (p == nullptr || p.ref.eventId == MpvEventId.none) return;
      _dispatch(MpvEventData.decode(p));
    }
  }

  void _dispatch(MpvEventData event) {
    switch (event) {
      case PropertyChangeEvent(:final replyUserdata, :final value):
        // The controller may already be closed by teardown while a late event
        // is still draining; adding to it would throw into the event loop.
        _addIfOpen(_observers[replyUserdata], value);
      case GetPropertyReplyEvent(
        :final replyUserdata,
        :final error,
        :final value,
        :final name,
      ):
        _complete(replyUserdata, error, value, 'get_property_async($name)');
      case SetPropertyReplyEvent(:final replyUserdata, :final error):
        _complete(replyUserdata, error, null, 'set_property_async');
      case CommandReplyEvent(:final replyUserdata, :final error, :final result):
        _complete(replyUserdata, error, result, 'command_async');
      default:
        break;
    }
    if (!_events.isClosed) _events.add(event);
  }

  /// Adds [value] to [observer] unless teardown already closed it.
  static void _addIfOpen(
    StreamController<Object?>? observer,
    Object? value,
  ) {
    if (observer != null && !observer.isClosed) observer.add(value);
  }

  /// Closes [controller] unless it is already closed.
  ///
  /// [dispose] may be re-entered from a synchronous [events] listener, i.e.
  /// while the sync broadcast controller is still firing. Dart rejects
  /// `close()` at that moment with a [StateError] and leaves the controller
  /// open — and because `_disposed` is already true, a second [dispose] cannot
  /// retry. Catch only that error and retry once on the next microtask, after
  /// the dispatch has unwound; this is the single close path allowed to retry.
  static void _closeIfOpen<T>(StreamController<T> controller) {
    if (controller.isClosed) return;
    try {
      unawaited(controller.close());
    } on StateError {
      scheduleMicrotask(() {
        if (!controller.isClosed) unawaited(controller.close());
      });
    }
  }

  void _complete(int id, int err, Object? value, String op) {
    final c = _pending.remove(id);
    if (c == null) return;
    if (err < 0) {
      c.completeError(_error(err, op));
    } else {
      c.complete(value);
    }
  }

  MpvException _error(int code, String op) =>
      MpvException(code, readUtf8(bindings.errorString(code)), operation: op);

  void _check(int rc, String op) {
    if (rc < 0) throw _error(rc, op);
  }

  static String _describe(Object args) => switch (args) {
    final List<Object?> l when l.isNotEmpty => '${l.first}',
    final Map<String, Object?> m => '${m['name']}',
    _ => '?',
  };
}

/// 进行中的异步命令。
final class MpvAsyncCommand {
  MpvAsyncCommand._(this._mpv, this.id, this.result);

  final Mpv _mpv;

  /// reply_userdata。
  final int id;

  /// 命令结果（失败时以 [MpvException] 完成）。
  final Future<Object?> result;

  /// `mpv_abort_async_command`：尽力中止（结果仍会以错误或成功完成）。
  void abort() {
    if (!_mpv.isDisposed) _mpv.bindings.abortAsyncCommand(_mpv.handle, id);
  }
}

/// mpv 事件的 Dart 强类型表示（mpv_event_id 全覆盖）。
library;

import 'dart:ffi';

import '../ffi/bindings.dart';
import 'node.dart';

/// 所有 mpv 事件的基类；对 [MpvEventId] 每个取值都有对应子类。
sealed class MpvEventData {
  const MpvEventData(this.replyUserdata, this.error);

  /// 请求时传入的 reply_userdata（无关事件为 0）。
  final int replyUserdata;

  /// 事件携带的 mpv 错误码（>=0 为成功）。
  final int error;

  /// 从 libmpv 拥有的事件指针解码（指针仅在下次 wait_event 前有效，故立即深拷贝）。
  static MpvEventData decode(Pointer<MpvEvent> p) {
    final e = p.ref;
    final ud = e.replyUserdata;
    final err = e.error;
    final data = e.data;
    return switch (e.eventId) {
      MpvEventId.shutdown => ShutdownEvent(ud, err),
      MpvEventId.logMessage => _log(data.cast(), ud, err),
      MpvEventId.getPropertyReply => GetPropertyReplyEvent(
        ud,
        err,
        _prop(data.cast()).$1,
        _prop(data.cast()).$2,
      ),
      MpvEventId.setPropertyReply => SetPropertyReplyEvent(ud, err),
      MpvEventId.commandReply => CommandReplyEvent(
        ud,
        err,
        data == nullptr ? null : readNode(data.cast<MpvEventCommand>().cast()),
      ),
      MpvEventId.startFile => StartFileEvent(
        ud,
        err,
        data.cast<MpvEventStartFile>().ref.playlistEntryId,
      ),
      MpvEventId.endFile => _endFile(data.cast(), ud, err),
      MpvEventId.fileLoaded => FileLoadedEvent(ud, err),
      MpvEventId.idle => IdleEvent(ud, err),
      MpvEventId.tick => TickEvent(ud, err),
      MpvEventId.clientMessage => _clientMessage(data.cast(), ud, err),
      MpvEventId.videoReconfig => VideoReconfigEvent(ud, err),
      MpvEventId.audioReconfig => AudioReconfigEvent(ud, err),
      MpvEventId.seek => SeekEvent(ud, err),
      MpvEventId.playbackRestart => PlaybackRestartEvent(ud, err),
      MpvEventId.propertyChange => PropertyChangeEvent(
        ud,
        err,
        _prop(data.cast()).$1,
        _prop(data.cast()).$2,
      ),
      MpvEventId.queueOverflow => QueueOverflowEvent(ud, err),
      MpvEventId.hook => HookEvent(
        ud,
        err,
        readUtf8(data.cast<MpvEventHook>().ref.name),
        data.cast<MpvEventHook>().ref.id,
      ),
      final id => UnknownEvent(ud, err, id),
    };
  }

  static (String, Object?) _prop(Pointer<MpvEventProperty> p) {
    final ref = p.ref;
    // 仅以 MPV_FORMAT_NODE 订阅，因此 data 指向 mpv_node；NONE 表示属性不可用
    final value = ref.format == MpvFormat.node
        ? readNode(ref.data.cast())
        : null;
    return (readUtf8(ref.name), value);
  }

  static LogMessageEvent _log(Pointer<MpvEventLogMessage> p, int ud, int err) {
    final r = p.ref;
    return LogMessageEvent(
      ud,
      err,
      readUtf8(r.prefix),
      readUtf8(r.level),
      readUtf8(r.text),
      r.logLevel,
    );
  }

  static EndFileEvent _endFile(Pointer<MpvEventEndFile> p, int ud, int err) {
    final r = p.ref;
    return EndFileEvent(
      ud,
      err,
      EndFileReason.fromCode(r.reason),
      r.error,
      r.playlistEntryId,
      r.playlistInsertId,
      r.playlistInsertNumEntries,
    );
  }

  static ClientMessageEvent _clientMessage(
    Pointer<MpvEventClientMessage> p,
    int ud,
    int err,
  ) {
    final r = p.ref;
    return ClientMessageEvent(ud, err, [
      for (var i = 0; i < r.numArgs; i++) readUtf8((r.args + i).value),
    ]);
  }
}

/// 核心即将退出，客户端必须尽快销毁句柄。
final class ShutdownEvent extends MpvEventData {
  /// Creates the event; [ud] is the reply userdata and [err] the mpv
  /// error code of the raw `mpv_event`.
  const ShutdownEvent(super.ud, super.err);
}

/// 日志消息（需先 requestLogMessages）。
final class LogMessageEvent extends MpvEventData {
  /// Creates the event from the raw `mpv_event_log_message` fields.
  const LogMessageEvent(
    super.ud,
    super.err,
    this.prefix,
    this.level,
    this.text,
    this.logLevel,
  );

  /// Module that logged the message (e.g. `cplayer`, `vo`).
  final String prefix;

  /// Log level name (`fatal`, `error`, `warn`, `info`, `v`, `debug`,
  /// `trace`).
  final String level;

  /// Message text, usually ending with a newline.
  final String text;

  /// `mpv_log_level` 数值（10=fatal … 70=trace）。
  final int logLevel;
}

/// 异步 get_property 的应答。
final class GetPropertyReplyEvent extends MpvEventData {
  /// Creates the event; [ud] is the reply userdata and [err] the mpv
  /// error code of the raw `mpv_event`.
  const GetPropertyReplyEvent(super.ud, super.err, this.name, this.value);

  /// Property or hook name.
  final String name;

  /// Value converted from `mpv_node`, null if unavailable.
  final Object? value;
}

/// 异步 set_property 的应答。
final class SetPropertyReplyEvent extends MpvEventData {
  /// Creates the event; [ud] is the reply userdata and [err] the mpv
  /// error code of the raw `mpv_event`.
  const SetPropertyReplyEvent(super.ud, super.err);
}

/// 异步命令的应答。
final class CommandReplyEvent extends MpvEventData {
  /// Creates the event; [ud] is the reply userdata and [err] the mpv
  /// error code of the raw `mpv_event`.
  const CommandReplyEvent(super.ud, super.err, this.result);

  /// Command result converted from `mpv_node`.
  final Object? result;
}

/// 开始加载文件。
final class StartFileEvent extends MpvEventData {
  /// Creates the event; [ud] is the reply userdata and [err] the mpv
  /// error code of the raw `mpv_event`.
  const StartFileEvent(super.ud, super.err, this.playlistEntryId);

  /// Playlist entry id (`playlist/N/id`) of the file.
  final int playlistEntryId;
}

/// `mpv_end_file_reason`。
enum EndFileReason {
  /// The end of the file was reached.
  eof(0),

  /// Playback was stopped or another file was loaded.
  stop(2),

  /// The player is shutting down.
  quit(3),

  /// The file failed to load or play; see [EndFileEvent.fileError].
  error(4),

  /// The file was a playlist or redirect and was replaced by its
  /// entries.
  redirect(5),

  /// A reason this binding does not know.
  unknown(-1);

  /// Creates a reason with its C value.
  const EndFileReason(this.code);

  /// C value of `mpv_end_file_reason`.
  final int code;

  /// Looks up [c]; unknown values map to [unknown].
  static EndFileReason fromCode(int c) =>
      values.firstWhere((e) => e.code == c, orElse: () => unknown);
}

/// 文件结束或被中断。
final class EndFileEvent extends MpvEventData {
  /// Creates the event from the raw `mpv_event_end_file` fields.
  const EndFileEvent(
    super.ud,
    super.err,
    this.reason,
    this.fileError,
    this.playlistEntryId,
    this.playlistInsertId,
    this.playlistInsertNumEntries,
  );

  /// Why the file ended.
  final EndFileReason reason;

  /// reason==error 时的 mpv 错误码。
  final int fileError;

  /// Playlist entry id (`playlist/N/id`) of the file.
  final int playlistEntryId;

  /// With [EndFileReason.redirect]: id of the first inserted
  /// playlist entry.
  final int playlistInsertId;

  /// With [EndFileReason.redirect]: number of inserted entries.
  final int playlistInsertNumEntries;
}

/// 文件已加载、解码开始。
final class FileLoadedEvent extends MpvEventData {
  /// Creates the event; [ud] is the reply userdata and [err] the mpv
  /// error code of the raw `mpv_event`.
  const FileLoadedEvent(super.ud, super.err);
}

/// 进入空闲（无文件）。已弃用于 mpv，保留以完整覆盖。
final class IdleEvent extends MpvEventData {
  /// Creates the event; [ud] is the reply userdata and [err] the mpv
  /// error code of the raw `mpv_event`.
  const IdleEvent(super.ud, super.err);
}

/// 已弃用的 tick 事件，保留以完整覆盖。
final class TickEvent extends MpvEventData {
  /// Creates the event; [ud] is the reply userdata and [err] the mpv
  /// error code of the raw `mpv_event`.
  const TickEvent(super.ud, super.err);
}

/// `script-message` 投递到本客户端的消息。
final class ClientMessageEvent extends MpvEventData {
  /// Creates the event; [ud] is the reply userdata and [err] the mpv
  /// error code of the raw `mpv_event`.
  const ClientMessageEvent(super.ud, super.err, this.args);

  /// Message arguments.
  final List<String> args;
}

/// 视频输出参数变化。
final class VideoReconfigEvent extends MpvEventData {
  /// Creates the event; [ud] is the reply userdata and [err] the mpv
  /// error code of the raw `mpv_event`.
  const VideoReconfigEvent(super.ud, super.err);
}

/// 音频输出参数变化。
final class AudioReconfigEvent extends MpvEventData {
  /// Creates the event; [ud] is the reply userdata and [err] the mpv
  /// error code of the raw `mpv_event`.
  const AudioReconfigEvent(super.ud, super.err);
}

/// 开始 seek。
final class SeekEvent extends MpvEventData {
  /// Creates the event; [ud] is the reply userdata and [err] the mpv
  /// error code of the raw `mpv_event`.
  const SeekEvent(super.ud, super.err);
}

/// seek/加载后播放重新开始。
final class PlaybackRestartEvent extends MpvEventData {
  /// Creates the event; [ud] is the reply userdata and [err] the mpv
  /// error code of the raw `mpv_event`.
  const PlaybackRestartEvent(super.ud, super.err);
}

/// 被观察属性的值变化。
final class PropertyChangeEvent extends MpvEventData {
  /// Creates the event; [ud] is the reply userdata and [err] the mpv
  /// error code of the raw `mpv_event`.
  const PropertyChangeEvent(super.ud, super.err, this.name, this.value);

  /// Property or hook name.
  final String name;

  /// Value converted from `mpv_node`, null if unavailable.
  final Object? value;
}

/// 事件队列溢出，部分事件丢失。
final class QueueOverflowEvent extends MpvEventData {
  /// Creates the event; [ud] is the reply userdata and [err] the mpv
  /// error code of the raw `mpv_event`.
  const QueueOverflowEvent(super.ud, super.err);
}

/// 已注册的 hook 触发，处理后必须调用 hookContinue。
final class HookEvent extends MpvEventData {
  /// Creates the event; [ud] is the reply userdata and [err] the mpv
  /// error code of the raw `mpv_event`.
  const HookEvent(super.ud, super.err, this.name, this.id);

  /// Property or hook name.
  final String name;

  /// Id to pass to `Mpv.hookContinue`.
  final int id;
}

/// 本绑定不认识的事件 id（前向兼容）。
final class UnknownEvent extends MpvEventData {
  /// Creates the event; [ud] is the reply userdata and [err] the mpv
  /// error code of the raw `mpv_event`.
  const UnknownEvent(super.ud, super.err, this.eventId);

  /// Raw `mpv_event_id`.
  final int eventId;
}

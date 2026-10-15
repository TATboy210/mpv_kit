/// mpv 错误码映射。
library;

/// libmpv 调用返回负错误码时抛出。
final class MpvException implements Exception {
  const MpvException(this.code, this.message, {this.operation});

  /// `mpv_error` 原始错误码（< 0）。
  final int code;

  /// `mpv_error_string` 给出的描述。
  final String message;

  /// 触发错误的操作，例如 `set_property(volume)`。
  final String? operation;

  /// 对应的强类型错误枚举。
  MpvError get error => MpvError.fromCode(code);

  @override
  String toString() =>
      'MpvException(${error.name}${operation == null ? '' : ' @ $operation'}): '
      '$message';
}

/// `mpv_error` 枚举（client.h:278）。
enum MpvError {
  success(0),
  eventQueueFull(-1),
  nomem(-2),
  uninitialized(-3),
  invalidParameter(-4),
  optionNotFound(-5),
  optionFormat(-6),
  optionError(-7),
  propertyNotFound(-8),
  propertyFormat(-9),
  propertyUnavailable(-10),
  propertyError(-11),
  command(-12),
  loadingFailed(-13),
  aoInitFailed(-14),
  voInitFailed(-15),
  nothingToPlay(-16),
  unknownFormat(-17),
  unsupported(-18),
  notImplemented(-19),
  generic(-20),

  /// 未来版本新增、本绑定尚不认识的错误码。
  unknown(-9999);

  const MpvError(this.code);

  /// C 侧数值。
  final int code;

  /// 由数值查找；未知值返回 [unknown]。
  static MpvError fromCode(int code) =>
      values.firstWhere((e) => e.code == code, orElse: () => unknown);
}

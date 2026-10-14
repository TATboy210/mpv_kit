/// mpv 文档目录条目（由 tools/gen_catalog.dart 生成数据）。
library;

/// One documented property, command or option of the bundled mpv version.
final class MpvCatalogEntry {
  const MpvCatalogEntry(this.name, this.summary, {this.writable = false});

  /// Name as used with `Mpv.getProperty` / `Mpv.command`.
  final String name;

  /// First sentence of mpv's documentation.
  final String summary;

  /// Whether the property is documented as writable (RW). Always true for
  /// options; not meaningful for commands.
  final bool writable;

  @override
  String toString() => name;
}

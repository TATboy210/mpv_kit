/// 最小 tar(ustar) 解包器：仅接受普通文件，拒绝路径穿越。
///
/// Release bundles are produced by our own CI (`tar -czf`), so only the
/// subset needed for them is implemented. Anything unexpected — links,
/// devices, absolute paths, `..` segments — is rejected instead of skipped,
/// because a bundle that does not match what CI produces is not trusted.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// 解包失败（格式错误或不安全的条目）。
final class TarFormatException implements Exception {
  TarFormatException(this.message);

  final String message;

  @override
  String toString() => 'TarFormatException: $message';
}

/// One regular file of an archive.
final class TarEntry {
  TarEntry(this.path, this.bytes);

  /// Normalised relative path using `/` separators (no leading `./`).
  final String path;
  final Uint8List bytes;
}

const _block = 512;

/// Parses an uncompressed tar archive held in memory.
List<TarEntry> readTar(Uint8List data) {
  final entries = <TarEntry>[];
  String? longName; // GNU 'L' long-name record for the next entry
  var offset = 0;
  while (offset + _block <= data.length) {
    final header = Uint8List.sublistView(data, offset, offset + _block);
    if (header.every((b) => b == 0)) break; // end-of-archive marker
    _checkChecksum(header);
    final size = _octal(header, 124, 12);
    final type = header[156];
    final bodyStart = offset + _block;
    final bodyEnd = bodyStart + size;
    if (bodyEnd > data.length) {
      throw TarFormatException('truncated entry at offset $offset');
    }
    final body = Uint8List.sublistView(data, bodyStart, bodyEnd);
    offset = bodyStart + (size + _block - 1) ~/ _block * _block;

    switch (type) {
      case 0x4c: // 'L': GNU long name for the following entry
        longName = _cString(body, 0, body.length);
        continue;
      case 0x78 || 0x67: // 'x' / 'g': pax headers carry no file data we use
        continue;
      case 0x35: // '5': directory
        longName = null;
        continue;
      case 0 || 0x30: // regular file
        final name = longName ?? _ustarName(header);
        longName = null;
        entries.add(TarEntry(_safePath(name), Uint8List.fromList(body)));
      default:
        throw TarFormatException(
          'unsupported entry type ${String.fromCharCode(type)} '
          '(${longName ?? _ustarName(header)})',
        );
    }
  }
  return entries;
}

/// Decompresses and parses a `.tar.gz` file.
List<TarEntry> readTarGz(File file) =>
    readTar(Uint8List.fromList(gzip.decode(file.readAsBytesSync())));

String _ustarName(Uint8List h) {
  final name = _cString(h, 0, 100);
  final magic = _cString(h, 257, 6);
  final prefix = magic.startsWith('ustar') ? _cString(h, 345, 155) : '';
  return prefix.isEmpty ? name : '$prefix/$name';
}

/// Rejects absolute paths and parent references; strips `./`.
String _safePath(String raw) {
  final parts = raw.replaceAll('\\', '/').split('/')
    ..removeWhere((p) => p.isEmpty || p == '.');
  if (raw.startsWith('/') ||
      raw.contains(':') ||
      parts.contains('..') ||
      parts.isEmpty) {
    throw TarFormatException('unsafe path in archive: $raw');
  }
  return parts.join('/');
}

String _cString(Uint8List b, int start, int length) {
  var end = start;
  while (end < start + length && b[end] != 0) {
    end++;
  }
  return utf8.decode(b.sublist(start, end));
}

int _octal(Uint8List b, int start, int length) {
  final s = _cString(b, start, length).trim();
  if (s.isEmpty) return 0;
  final v = int.tryParse(s, radix: 8);
  if (v == null || v < 0) throw TarFormatException('bad octal field "$s"');
  return v;
}

void _checkChecksum(Uint8List h) {
  final expected = _octal(h, 148, 8);
  var sum = 0;
  for (var i = 0; i < _block; i++) {
    // The checksum field itself counts as spaces.
    sum += (i >= 148 && i < 156) ? 0x20 : h[i];
  }
  if (sum != expected) throw TarFormatException('header checksum mismatch');
}

/// `mpv_node` ↔ Dart 值的双向转换。
///
/// Dart side value model (closed set):
/// `null` · `String` · `bool` · `int` · `double` · `List<Object?>` ·
/// `Map<String, Object?>` · `Uint8List` (byte array).
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../ffi/bindings.dart';

/// 读取 libmpv 拥有的节点（不释放、不修改）。
Object? readNode(Pointer<MpvNode> node) {
  final n = node.ref;
  switch (n.format) {
    case MpvFormat.none:
      return null;
    case MpvFormat.string || MpvFormat.osdString:
      return readUtf8(n.u.string);
    case MpvFormat.flag:
      return n.u.flag != 0;
    case MpvFormat.int64:
      return n.u.int64;
    case MpvFormat.double_:
      return n.u.double_;
    case MpvFormat.nodeArray:
      final list = n.u.list.ref;
      return List<Object?>.generate(
        list.num,
        (i) => readNode(list.values + i),
        growable: false,
      );
    case MpvFormat.nodeMap:
      final list = n.u.list.ref;
      return <String, Object?>{
        for (var i = 0; i < list.num; i++)
          readUtf8((list.keys + i).value): readNode(list.values + i),
      };
    case MpvFormat.byteArray:
      final ba = n.u.ba.ref;
      return Uint8List.fromList(ba.data.cast<Uint8>().asTypedList(ba.size));
    default:
      throw UnsupportedError('Unknown mpv_format ${n.format}');
  }
}

/// 以 UTF-8 解码 C 字符串（mpv 保证 UTF-8，非法序列替换为 U+FFFD）。
String readUtf8(Pointer<Utf8> p) {
  if (p == nullptr) return '';
  return utf8.decode(
    p.cast<Uint8>().asTypedList(p.length),
    allowMalformed: true,
  );
}

/// 在 [arena] 中构造与 [value] 等价的 `mpv_node`；arena 释放时整体回收。
///
/// The produced tree is owned by Dart: never pass it to
/// `mpv_free_node_contents`.
Pointer<MpvNode> writeNode(Object? value, Arena arena) {
  final node = arena<MpvNode>();
  _fill(node, value, arena);
  return node;
}

void _fill(Pointer<MpvNode> node, Object? value, Arena arena) {
  final n = node.ref;
  switch (value) {
    case null:
      n.format = MpvFormat.none;
    case final String s:
      n.format = MpvFormat.string;
      n.u.string = s.toNativeUtf8(allocator: arena);
    case final bool b:
      n.format = MpvFormat.flag;
      n.u.flag = b ? 1 : 0;
    case final int i:
      n.format = MpvFormat.int64;
      n.u.int64 = i;
    case final double d:
      n.format = MpvFormat.double_;
      n.u.double_ = d;
    case final Uint8List bytes:
      n.format = MpvFormat.byteArray;
      final ba = arena<MpvByteArray>();
      final data = arena<Uint8>(bytes.isEmpty ? 1 : bytes.length);
      data.asTypedList(bytes.length).setAll(0, bytes);
      ba.ref
        ..data = data.cast()
        ..size = bytes.length;
      n.u.ba = ba;
    case final List<Object?> items:
      n.format = MpvFormat.nodeArray;
      n.u.list = _list(items, null, arena);
    case final Map<String, Object?> map:
      n.format = MpvFormat.nodeMap;
      n.u.list = _list(map.values.toList(), map.keys.toList(), arena);
    default:
      throw ArgumentError.value(
        value,
        'value',
        'Unsupported type ${value.runtimeType} for mpv_node',
      );
  }
}

Pointer<MpvNodeList> _list(
  List<Object?> values,
  List<String>? keys,
  Arena arena,
) {
  final list = arena<MpvNodeList>();
  final count = values.length;
  // calloc(0) 可能返回 nullptr，分配至少 1 个元素保持指针有效
  final nodes = arena<MpvNode>(count == 0 ? 1 : count);
  for (var i = 0; i < count; i++) {
    _fill(nodes + i, values[i], arena);
  }
  list.ref
    ..num = count
    ..values = nodes
    ..keys = nullptr;
  if (keys != null) {
    final keyPtrs = arena<Pointer<Utf8>>(count == 0 ? 1 : count);
    for (var i = 0; i < count; i++) {
      (keyPtrs + i).value = keys[i].toNativeUtf8(allocator: arena);
    }
    list.ref.keys = keyPtrs;
  }
  return list;
}

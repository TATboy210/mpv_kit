#!/usr/bin/env python3
"""libmpv PE ABI 审计 — 解析导出表/导入 DLL，并与期望符号清单比对。

用法:
  python -I pe_audit.py <libmpv-2.dll> [--expect expected_symbols.txt]
                        [--forbid-gpl] [--forbid-angle]

--forbid-angle: mpv_kit 在 Windows 上自己的渲染链路禁止 ANGLE/EGL (ADR 0003)。
  检查导入表 (静态依赖) 与整个文件的字节 (ASCII 与 UTF-16LE), 后者覆盖
  延迟加载与按名 LoadLibrary/GetProcAddress 的动态加载 (mpv 自己的 ANGLE
  上下文就是按名动态加载)。与 --forbid-gpl 相互独立。

退出码: 0 = 通过; 1 = 缺失期望符号或检出禁止依赖; 2 = 文件格式错误。
纯标准库实现, 可在任意平台 CI 上运行 (仅解析, 从不加载/执行目标)。
"""
from __future__ import annotations

import argparse
import struct
import sys
from pathlib import Path

# 与 LGPL 构建冲突的已知 GPL-only 依赖 (出现在导入表即判失败)
GPL_DLL_MARKERS = ("libx264", "libx265", "libxvid", "librubberband", "libvidstab")


# ANGLE/EGL 禁令: 导入表中的 DLL 名 (小写比较) 与文件字节中的引用。
ANGLE_IMPORT_DLLS = ("libegl.dll", "libglesv2.dll")
# 区分大小写的符号名 (EGL 扩展入口, ANGLE 用它按平台选后端)。
ANGLE_CASE_TOKENS = ("eglGetPlatformDisplayEXT",)
# DLL 名对文件字节做 ASCII 小写后匹配, 因此 token 本身必须是小写。
ANGLE_DLL_TOKENS = ANGLE_IMPORT_DLLS


class PEError(Exception):
    pass


def _rva_to_off(sections, rva: int) -> int:
    for va, vsize, raw, rsize in sections:
        if va <= rva < va + max(vsize, rsize):
            return rva - va + raw
    raise PEError(f"RVA 0x{rva:x} 不在任何节内")


def _cstr(data: bytes, off: int) -> str:
    end = data.index(b"\0", off)
    return data[off:end].decode("ascii", "replace")


def parse_pe(data: bytes) -> tuple[list[str], list[str]]:
    """返回 (导出名列表, 导入 DLL 名列表)。"""
    if data[:2] != b"MZ":
        raise PEError("缺少 MZ 头")
    pe = struct.unpack_from("<I", data, 0x3C)[0]
    if data[pe:pe + 4] != b"PE\0\0":
        raise PEError("缺少 PE 签名")
    nsec = struct.unpack_from("<H", data, pe + 6)[0]
    opt_size = struct.unpack_from("<H", data, pe + 20)[0]
    opt = pe + 24
    magic = struct.unpack_from("<H", data, opt)[0]
    # PE32+ 数据目录在 opt+112, PE32 在 opt+96
    dd = opt + (112 if magic == 0x20B else 96)
    exp_rva = struct.unpack_from("<I", data, dd)[0]
    imp_rva = struct.unpack_from("<I", data, dd + 8)[0]
    sec_off = opt + opt_size
    sections = []
    for i in range(nsec):
        s = sec_off + i * 40
        vsize, va, rsize, raw = struct.unpack_from("<IIII", data, s + 8)
        sections.append((va, vsize, raw, rsize))

    exports: list[str] = []
    if exp_rva:
        e = _rva_to_off(sections, exp_rva)
        # IMAGE_EXPORT_DIRECTORY: NumberOfNames@+24, AddressOfNames@+32
        n_names = struct.unpack_from("<I", data, e + 24)[0]
        names_rva = struct.unpack_from("<I", data, e + 32)[0]
        names_off = _rva_to_off(sections, names_rva)
        for i in range(n_names):
            nrva = struct.unpack_from("<I", data, names_off + 4 * i)[0]
            exports.append(_cstr(data, _rva_to_off(sections, nrva)))

    imports: list[str] = []
    if imp_rva:
        d = _rva_to_off(sections, imp_rva)
        while True:
            name_rva = struct.unpack_from("<I", data, d + 12)[0]
            if name_rva == 0:
                break
            imports.append(_cstr(data, _rva_to_off(sections, name_rva)))
            d += 20
    return exports, imports


def _angle_references(data: bytes) -> list[str]:
    """扫描整个文件字节, 返回 `<token> (<ascii|utf16>)` 形式的命中列表。

    bytes.lower() 只改 A-Z, 对 UTF-16LE 的 `L<NUL>I<NUL>B<NUL>` 同样有效, 因此 DLL 名
    (Windows 上不区分大小写) 在 ASCII 与 UTF-16LE 两种编码下都能命中;
    eglGetPlatformDisplayEXT 区分大小写, 直接匹配原始字节。
    """
    lowered = data.lower()
    hits: list[str] = []
    for tok in ANGLE_CASE_TOKENS:
        if tok.encode("ascii") in data:
            hits.append(f"{tok} (ascii)")
        if tok.encode("utf-16-le") in data:
            hits.append(f"{tok} (utf16)")
    for tok in ANGLE_DLL_TOKENS:
        if tok.encode("ascii") in lowered:
            hits.append(f"{tok} (ascii)")
        if tok.encode("utf-16-le") in lowered:
            hits.append(f"{tok} (utf16)")
    return hits


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("dll", type=Path)
    ap.add_argument("--expect", type=Path, help="每行一个必须导出的符号")
    ap.add_argument("--forbid-gpl", action="store_true")
    ap.add_argument("--forbid-angle", action="store_true",
                    help="导入表或文件字节中出现 libEGL/libGLESv2/eglGetPlatformDisplayEXT 即失败")
    ap.add_argument("--dump", action="store_true", help="打印全部 mpv_* 导出")
    a = ap.parse_args()
    try:
        raw = a.dll.read_bytes()
        exports, imports = parse_pe(raw)
    except (PEError, struct.error, ValueError) as e:
        print(f"FORMAT ERROR: {e}", file=sys.stderr)
        return 2
    mpv = sorted(x for x in exports if x.startswith("mpv_"))
    print(f"exports(mpv_*): {len(mpv)}  imports: {len(imports)}")
    print("imports:", " ".join(sorted(imports)))
    if a.dump:
        print("\n".join(mpv))
    ok = True
    if a.expect:
        want = {l.strip() for l in a.expect.read_text().splitlines() if l.strip() and not l.startswith("#")}
        missing = sorted(want - set(mpv))
        if missing:
            ok = False
            print("MISSING:", " ".join(missing))
    if a.forbid_gpl:
        bad = [i for i in imports if i.lower().startswith(GPL_DLL_MARKERS)]
        if bad:
            ok = False
            print("GPL DEPENDENCY:", " ".join(bad))
    if a.forbid_angle:
        angle_ok = True
        # 全部命中都打印, 任一命中即失败; 打印顺序不影响判定。
        for name in imports:
            if name.lower() in ANGLE_IMPORT_DLLS:
                angle_ok = False
                print(f"ANGLE IMPORT: {name}")
        for ref in _angle_references(raw):
            angle_ok = False
            print(f"ANGLE REFERENCE: {ref}")
        if angle_ok:
            print(f"ANGLE-FREE {a.dll}")
        else:
            ok = False
    print("RESULT:", "PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())

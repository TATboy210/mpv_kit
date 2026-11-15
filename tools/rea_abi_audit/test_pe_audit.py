#!/usr/bin/env python3
"""pe_audit.py --forbid-angle 的回归测试 (D3D-02)。

用合成的最小 PE32+ 样本证明 ANGLE 禁令「会变红」: 违规样本必须以 1 退出,
干净样本 / 无导入目录样本 / 近似名样本必须以 0 退出。测试本身为绿, 因此可以
在 CI 上运行, 红色结果只存在于被审计的合成样本里。

只用标准库; 不 import pe_audit, 而是用 `sys.executable -I` 以子进程调用它
(-I 不会把脚本目录加入 sys.path, 与 CI 中审计的实际调用方式一致)。

用法:
  python -I tools/rea_abi_audit/test_pe_audit.py          # 运行全部测试
  python -I tools/rea_abi_audit/test_pe_audit.py --emit D # 只把样本文件写到目录 D
"""
from __future__ import annotations

import struct
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

AUDIT = Path(__file__).resolve().parent / "pe_audit.py"

# 合成 PE 布局常量: DOS 头 64 字节, PE 签名在 0x40, 可选头 (PE32+) 240 字节,
# 唯一的节头紧随其后, 节的原始数据放在文件偏移 0x200, 虚拟地址 0x1000。
_PE_OFFSET = 0x40
_OPT_SIZE = 240  # 112 字节固定部分 + 16 个数据目录 x 8 字节
_SECTION_VA = 0x1000
_SECTION_RAW = 0x200
_IMPORT_DIR_INDEX = 1  # 数据目录第 1 项是导入表


def build_pe(imports: list[str], payload: bytes = b"") -> bytes:
    """生成最小 PE32+: 一个 .rdata 节, 可选的导入描述符与 DLL 名, 以及任意载荷。

    imports 为空时导入目录 RVA 写 0 (「无导入目录」样本)。
    """
    section = bytearray()
    import_rva = 0
    if imports:
        import_rva = _SECTION_VA
        desc_size = 20 * (len(imports) + 1)  # 末尾一个全零终止描述符
        names = bytearray()
        descs = bytearray()
        for dll in imports:
            name_rva = _SECTION_VA + desc_size + len(names)
            # IMAGE_IMPORT_DESCRIPTOR: Name 在 +12, 其余字段本审计不读取。
            descs += struct.pack("<IIIII", 0, 0, 0, name_rva, 0)
            names += dll.encode("ascii") + b"\0"
        descs += b"\0" * 20
        section += descs + names
    section += payload
    # 至少 0x200 字节原始数据, 并保证节内 RVA 查找覆盖全部内容。
    section += b"\0" * (-len(section) % 0x200 or 0)
    if not section:
        section = bytearray(0x200)

    dos = bytearray(64)
    dos[0:2] = b"MZ"
    struct.pack_into("<I", dos, 0x3C, _PE_OFFSET)
    coff = struct.pack(
        "<HHIIIHH", 0x8664, 1, 0, 0, 0, _OPT_SIZE, 0x2022  # AMD64, 1 节, DLL
    )
    opt = bytearray(_OPT_SIZE)
    struct.pack_into("<H", opt, 0, 0x20B)  # PE32+ 魔数
    dd = 112
    struct.pack_into("<II", opt, dd + 8 * _IMPORT_DIR_INDEX, import_rva, 40 if imports else 0)
    # 节头: 名称 8 字节, VirtualSize, VirtualAddress, SizeOfRawData, PointerToRawData。
    sec_hdr = struct.pack(
        "<8sIIIIIIHHI", b".rdata", len(section), _SECTION_VA, len(section),
        _SECTION_RAW, 0, 0, 0, 0, 0x40000040,
    )
    head = bytes(dos) + b"PE\0\0" + coff + bytes(opt) + sec_hdr
    head += b"\0" * (_SECTION_RAW - len(head))
    return head + bytes(section)


# 样本名 -> (字节, 期望退出码)。
SAMPLES: dict[str, tuple[bytes, int]] = {
    "violation_import_libegl": (build_pe(["libEGL.dll"]), 1),
    "violation_import_upper": (build_pe(["LIBGLESV2.DLL"]), 1),
    "violation_string_ascii": (
        build_pe(["kernel32.dll"], b"eglGetPlatformDisplayEXT\0"), 1),
    "violation_string_utf16": (
        build_pe(["kernel32.dll"], "libEGL.dll".encode("utf-16-le") + b"\0\0"), 1),
    "clean_kernel32": (build_pe(["kernel32.dll"]), 0),
    "clean_no_imports": (build_pe([]), 0),
    "near_miss": (build_pe(["libEGLfoo.dll"]), 0),
    "multi": (build_pe(["libEGL.dll"], b"eglGetPlatformDisplayEXT\0"), 1),
}


def run_audit(path: Path) -> tuple[int, str]:
    """以 `python -I pe_audit.py <path> --forbid-angle` 运行并返回 (退出码, 输出)。"""
    proc = subprocess.run(
        [sys.executable, "-I", str(AUDIT), str(path), "--forbid-angle"],
        capture_output=True, text=True, timeout=60,
    )
    return proc.returncode, proc.stdout + proc.stderr


class ForbidAngleTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls._tmp = tempfile.TemporaryDirectory()
        cls.dir = Path(cls._tmp.name)
        for name, (data, _) in SAMPLES.items():
            (cls.dir / f"{name}.dll").write_bytes(data)

    @classmethod
    def tearDownClass(cls) -> None:
        cls._tmp.cleanup()

    def audit(self, name: str) -> tuple[int, str]:
        return run_audit(self.dir / f"{name}.dll")

    def test_violations_exit_1(self) -> None:
        for name in ("violation_import_libegl", "violation_import_upper",
                     "violation_string_ascii", "violation_string_utf16"):
            with self.subTest(sample=name):
                code, out = self.audit(name)
                self.assertEqual(code, 1, out)
                self.assertIn("ANGLE", out)
                self.assertNotIn("ANGLE-FREE", out)

    def test_import_is_reported_with_original_name(self) -> None:
        _, out = self.audit("violation_import_libegl")
        self.assertIn("ANGLE IMPORT: libEGL.dll", out)
        _, out = self.audit("violation_import_upper")
        self.assertIn("ANGLE IMPORT: LIBGLESV2.DLL", out)

    def test_string_only_samples_name_the_token_and_encoding(self) -> None:
        _, out = self.audit("violation_string_ascii")
        self.assertIn("ANGLE REFERENCE: eglGetPlatformDisplayEXT (ascii)", out)
        self.assertNotIn("ANGLE IMPORT", out)
        _, out = self.audit("violation_string_utf16")
        self.assertIn("ANGLE REFERENCE: libegl.dll (utf16)", out)
        self.assertNotIn("ANGLE IMPORT", out)

    def test_clean_samples_exit_0(self) -> None:
        # 近似名 libEGLfoo.dll 与无导入目录都不得误判。
        for name in ("clean_kernel32", "clean_no_imports", "near_miss"):
            with self.subTest(sample=name):
                code, out = self.audit(name)
                self.assertEqual(code, 0, out)
                self.assertIn("ANGLE-FREE", out)
                self.assertNotIn("ANGLE IMPORT", out)
                self.assertNotIn("ANGLE REFERENCE", out)

    def test_multiple_violations_all_reported(self) -> None:
        code, out = self.audit("multi")
        self.assertEqual(code, 1, out)
        self.assertIn("ANGLE IMPORT: libEGL.dll", out)
        self.assertIn("ANGLE REFERENCE: eglGetPlatformDisplayEXT (ascii)", out)

    def test_flag_is_opt_in(self) -> None:
        # 不带 --forbid-angle 时审计行为不变 (不检查 ANGLE, 也不打印 ANGLE-FREE)。
        proc = subprocess.run(
            [sys.executable, "-I", str(AUDIT), str(self.dir / "violation_import_libegl.dll")],
            capture_output=True, text=True, timeout=60,
        )
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        self.assertNotIn("ANGLE", proc.stdout)

    def test_every_sample_matches_expected_exit(self) -> None:
        for name, (_, want) in SAMPLES.items():
            with self.subTest(sample=name):
                code, out = self.audit(name)
                self.assertEqual(code, want, out)


def emit(directory: Path) -> None:
    """只把合成样本写到 directory, 供本机对样本手工运行审计取证。"""
    directory.mkdir(parents=True, exist_ok=True)
    for name, (data, _) in SAMPLES.items():
        (directory / f"{name}.dll").write_bytes(data)
        print(f"wrote {directory / (name + '.dll')}")


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--emit":
        emit(Path(sys.argv[2]))
    else:
        unittest.main()

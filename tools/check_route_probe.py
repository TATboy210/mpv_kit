#!/usr/bin/env python3
"""Parity verdict for the macOS route probe (Phase 13, MAC-02).

Compares the final ROUTE-PIXEL reading of the HEAD plugin with the one of the
pre-Phase-12 plugin (3a5f450), both measured by `macos_route_test.dart` on the
same runner, with the same libmpv, Flutter SDK and test file.

Usage (repo root):
  python tools/check_route_probe.py HEAD_LOG PRE12_LOG
  python tools/check_route_probe.py --self-test

Exit codes: 0 ok, 1 verdict failed, 2 usage error.
"""
import json
import sys

# RED stub: the comparison is not implemented yet, so every self-test case
# that expects a real verdict fails. Replaced by the GREEN commit.


def compare_pixel(head_text, pre12_text):
    """Returns (ok, line)."""
    return False, "ROUTE-PARITY FAIL not implemented"


def pixel_line(tree, read, final, visibility, tex=None):
    """Builds one ROUTE-PIXEL line the way the Dart test prints it."""
    region = None
    if tex is not None:
        non_black, mean_r, mean_g, mean_b = tex
        region = {
            "nonBlackRatio": non_black,
            "greenFraction": 0.0,
            "meanR": mean_r,
            "meanG": mean_g,
            "meanB": mean_b,
        }
    record = {
        "tree": tree,
        "read": read,
        "final": final,
        "visibility": visibility,
        "texture": region,
        "control": {"nonBlackRatio": 1.0},
        "background": {"nonBlackRatio": 1.0},
        "image": "640x360",
    }
    return "ROUTE-PIXEL " + json.dumps(record, separators=(",", ":"))


def log_of(tree, visibility, tex=None, with_final=True):
    """A three-read log; the third read is the final one unless omitted."""
    lines = ["flutter: noise line"]
    for read in (1, 2, 3):
        final = with_final and read == 3
        lines.append(pixel_line(tree, read, final, visibility, tex))
    return "\n".join(lines) + "\n"


VISIBLE = (0.99, 100.0, 110.0, 120.0)
VISIBLE_G5 = (0.99, 100.0, 115.0, 120.0)

# (name, head log, pre12 log, expected exit code, expected line prefix)
CASES_PIXEL = [
    ("visible-identical", log_of("head", "texture-visible", VISIBLE),
     log_of("pre12", "texture-visible", VISIBLE), 0,
     "ROUTE-PARITY ok head=texture-visible pre12=texture-visible "
     "informative=yes"),
    ("black-vs-visible", log_of("head", "texture-composited-black", VISIBLE),
     log_of("pre12", "texture-visible", VISIBLE), 1,
     "ROUTE-PARITY FAIL visibility head=texture-composited-black "
     "pre12=texture-visible"),
    ("not-composited-both", log_of("head", "texture-not-composited"),
     log_of("pre12", "texture-not-composited"), 0,
     "ROUTE-PARITY ok head=texture-not-composited "
     "pre12=texture-not-composited informative=no"),
    ("missing-final", log_of("head", "texture-visible", VISIBLE),
     log_of("pre12", "texture-visible", VISIBLE, with_final=False), 1,
     "ROUTE-PARITY FAIL missing final ROUTE-PIXEL"),
    ("mean-delta", log_of("head", "texture-visible", VISIBLE),
     log_of("pre12", "texture-visible", VISIBLE_G5), 1,
     "ROUTE-PARITY FAIL mean"),
    ("indeterminate", log_of("head", "indeterminate"),
     log_of("pre12", "texture-visible", VISIBLE), 1,
     "ROUTE-PARITY FAIL indeterminate"),
]


def self_test():
    failed = []
    for name, head, pre12, want_rc, want_prefix in CASES_PIXEL:
        ok, line = compare_pixel(head, pre12)
        rc = 0 if ok else 1
        if rc != want_rc or not line.startswith(want_prefix):
            failed.append(f"{name}: rc={rc} line={line!r}")
    if failed:
        for entry in failed:
            print(f"ROUTE-PARITY self-test FAIL {entry}")
        return 1
    print(f"ROUTE-PARITY self-test ok cases={len(CASES_PIXEL)}")
    return 0


def main(argv):
    if argv == ["--self-test"]:
        return self_test()
    if len(argv) != 2:
        print(__doc__)
        return 2
    with open(argv[0], encoding="utf-8", errors="replace") as f:
        head = f.read()
    with open(argv[1], encoding="utf-8", errors="replace") as f:
        pre12 = f.read()
    ok, line = compare_pixel(head, pre12)
    print(line)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

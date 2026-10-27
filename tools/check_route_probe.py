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

# Parity tolerances for the toImage channel. Both trees run the same libmpv,
# the same Flutter SDK, the same test file and the same paused first frame at
# the same scale, so their texture regions should be almost pixel-identical;
# the tolerances only absorb sampling differences. They were committed before
# the first CI run and must not be adjusted after seeing a result (a changed
# tolerance needs the observed values and a user decision on record).
PARITY_MAX_NONBLACK_DELTA = 0.02
PARITY_MAX_MEAN_DELTA = 4.0

TEXTURE_VISIBLE = "texture-visible"
INDETERMINATE = "indeterminate"
MEAN_KEYS = ("meanR", "meanG", "meanB")


def raw_json_after(line, label):
    """Parses the JSON object that follows `label ` in `line`, or None."""
    at = line.find(label + " ")
    if at < 0:
        return None
    brace = line.find("{", at + len(label))
    if brace < 0:
        return None
    try:
        value, _ = json.JSONDecoder().raw_decode(line[brace:])
    except ValueError:
        return None
    return value if isinstance(value, dict) else None


def final_pixel_record(text, tree):
    """The single `"final": true` ROUTE-PIXEL record of `tree`, or an error.

    Returns (record, None) or (None, reason).
    """
    finals = []
    for line in text.splitlines():
        record = raw_json_after(line, "ROUTE-PIXEL")
        if record is not None and record.get("final") is True:
            finals.append(record)
    if not finals:
        return None, f"missing final ROUTE-PIXEL in the {tree} log"
    if len(finals) > 1:
        return None, f"{len(finals)} final ROUTE-PIXEL records in the {tree} log"
    if finals[0].get("tree") != tree:
        return None, (f"final ROUTE-PIXEL of the {tree} log has "
                      f"tree={finals[0].get('tree')!r}")
    return finals[0], None


def fmt(value):
    return f"{value:.4f}"


def pixel_verdict(head_text, pre12_text):
    """Returns (ok, line, informative) for the toImage channel."""
    head, why = final_pixel_record(head_text, "head")
    if head is None:
        return False, f"ROUTE-PARITY FAIL {why}", False
    pre12, why = final_pixel_record(pre12_text, "pre12")
    if pre12 is None:
        return False, f"ROUTE-PARITY FAIL {why}", False
    head_vis = head.get("visibility")
    pre12_vis = pre12.get("visibility")
    if INDETERMINATE in (head_vis, pre12_vis):
        return (False, f"ROUTE-PARITY FAIL indeterminate head={head_vis} "
                f"pre12={pre12_vis}", False)
    if head_vis != pre12_vis:
        return (False, f"ROUTE-PARITY FAIL visibility head={head_vis} "
                f"pre12={pre12_vis}", False)
    if head_vis != TEXTURE_VISIBLE:
        # Same classification, but the toImage channel does not see the
        # macOS external texture: consistency is NOT proven on this channel.
        return (True, f"ROUTE-PARITY ok head={head_vis} pre12={pre12_vis} "
                "informative=no dNonBlack=n/a dMeanMax=n/a", False)
    head_tex = head.get("texture") or {}
    pre12_tex = pre12.get("texture") or {}
    try:
        d_non_black = abs(head_tex["nonBlackRatio"] - pre12_tex["nonBlackRatio"])
        d_means = {k: abs(head_tex[k] - pre12_tex[k]) for k in MEAN_KEYS}
    except (KeyError, TypeError):
        return (False, "ROUTE-PARITY FAIL texture statistics missing from a "
                "texture-visible record", False)
    d_mean_max = max(d_means.values())
    if d_non_black > PARITY_MAX_NONBLACK_DELTA:
        return (False, f"ROUTE-PARITY FAIL nonBlack dNonBlack={fmt(d_non_black)} "
                f"limit={PARITY_MAX_NONBLACK_DELTA}", False)
    if d_mean_max > PARITY_MAX_MEAN_DELTA:
        worst = max(d_means, key=d_means.get)
        return (False, f"ROUTE-PARITY FAIL mean {worst} "
                f"dMeanMax={fmt(d_mean_max)} limit={PARITY_MAX_MEAN_DELTA}",
                False)
    return (True, f"ROUTE-PARITY ok head={head_vis} pre12={pre12_vis} "
            f"informative=yes dNonBlack={fmt(d_non_black)} "
            f"dMeanMax={fmt(d_mean_max)}", True)


def compare_pixel(head_text, pre12_text):
    """Returns (ok, line)."""
    ok, line, _ = pixel_verdict(head_text, pre12_text)
    return ok, line


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


STATS = (0.99, 100.0, 110.0, 120.0)
STATS_G5 = (0.99, 100.0, 115.0, 120.0)

# (name, head log, pre12 log, expected exit code, expected line prefix)
CASES_PIXEL = [
    ("visible-identical", log_of("head", "texture-visible", STATS),
     log_of("pre12", "texture-visible", STATS), 0,
     "ROUTE-PARITY ok head=texture-visible pre12=texture-visible "
     "informative=yes"),
    ("black-vs-visible", log_of("head", "texture-composited-black", STATS),
     log_of("pre12", "texture-visible", STATS), 1,
     "ROUTE-PARITY FAIL visibility head=texture-composited-black "
     "pre12=texture-visible"),
    ("not-composited-both", log_of("head", "texture-not-composited"),
     log_of("pre12", "texture-not-composited"), 0,
     "ROUTE-PARITY ok head=texture-not-composited "
     "pre12=texture-not-composited informative=no"),
    ("missing-final", log_of("head", "texture-visible", STATS),
     log_of("pre12", "texture-visible", STATS, with_final=False), 1,
     "ROUTE-PARITY FAIL missing final ROUTE-PIXEL"),
    ("mean-delta", log_of("head", "texture-visible", STATS),
     log_of("pre12", "texture-visible", STATS_G5), 1,
     "ROUTE-PARITY FAIL mean"),
    ("indeterminate", log_of("head", "indeterminate"),
     log_of("pre12", "texture-visible", STATS), 1,
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

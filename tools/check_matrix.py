#!/usr/bin/env python3
"""Six-target matrix guard (VERIFY-02).

Asserts that the supported-target matrices stay complete in both CI tiers
and that no step hides failures behind continue-on-error (the two allowed
exceptions are documented inline: the msys2 setup retry pattern and the
purely informational Vulkan loader diagnostics).

Run from the repo root:  python tools/check_matrix.py
"""
import re
import sys

try:
    import yaml
except ImportError:  # pragma: no cover
    print("CHECK-MATRIX FAIL: PyYAML is required (preinstalled on CI runners)")
    sys.exit(1)

ROOT = "."
failures = []


def fail(msg):
    failures.append(msg)
    print(f"CHECK-MATRIX FAIL: {msg}")


def ok(msg):
    print(f"CHECK-MATRIX ok {msg}")


def load(path):
    with open(path, encoding="utf-8") as f:
        return yaml.safe_load(f)


# --- native-verify.yml: 3 OS x 2 arch runners ---
nv = load(f"{ROOT}/.github/workflows/native-verify.yml")
linux = nv["jobs"]["linux"]["strategy"]["matrix"]["runner"]
if set(linux) == {"ubuntu-24.04", "ubuntu-24.04-arm"}:
    ok("native-verify linux runners (x64+arm64)")
else:
    fail(f"native-verify linux matrix changed: {linux}")

macos = nv["jobs"]["macos"]["strategy"]["matrix"]["runner"]
if set(macos) == {"macos-15", "macos-15-intel"}:
    ok("native-verify macos runners (arm64+x64)")
else:
    fail(f"native-verify macos matrix changed: {macos}")

win = nv["jobs"]["windows"]["strategy"]["matrix"]["include"]
win_msystems = {e["msystem"] for e in win}
if win_msystems == {"CLANG64", "CLANGARM64"}:
    ok("native-verify windows msystems (x64+arm64)")
else:
    fail(f"native-verify windows matrix changed: {win_msystems}")

# --- release.yml: exactly the six bundle targets ---
rel = load(f"{ROOT}/.github/workflows/release.yml")
targets = set()
for job in ("linux", "macos", "windows"):
    for entry in rel["jobs"][job]["strategy"]["matrix"]["include"]:
        targets.add(entry["target"])
expected = {
    "linux-x64", "linux-arm64",
    "macos-arm64", "macos-x64",
    "windows-x64", "windows-arm64",
}
if targets == expected:
    ok(f"release.yml six targets ({len(targets)})")
else:
    fail(f"release.yml targets drifted: {sorted(targets)} vs {sorted(expected)}")

# --- continue-on-error audit across both tiers ---
ALLOWED = {
    # Retry pattern: an immediate second attempt follows; double failure
    # fails the job. Not failure suppression.
    ("native-verify.yml", "msys2/setup-msys2@v2"),
    # Purely informational vulkaninfo tail.
    ("native-verify.yml", "Vulkan loader diagnostics"),
}


def audit(path, doc):
    for job_id, job in doc["jobs"].items():
        for step in job.get("steps", []):
            if "continue-on-error" not in step:
                continue
            name = step.get("name") or step.get("uses") or "<unnamed>"
            key = (path.split("/")[-1], name if isinstance(name, str) else str(name))
            uses = step.get("uses")
            allowed = (path.split("/")[-1], uses) in ALLOWED or key in ALLOWED
            if allowed:
                ok(f"{path} continue-on-error allowed: {name}")
            else:
                fail(f"{path} job '{job_id}' step '{name}' uses "
                     f"continue-on-error without an allowed exception")


audit(f"{ROOT}/.github/workflows/native-verify.yml", nv)
audit(f"{ROOT}/.github/workflows/release.yml", rel)

if failures:
    print(f"CHECK-MATRIX: {len(failures)} failure(s)")
    sys.exit(1)
print("CHECK-MATRIX: all targets present, no unauthorized continue-on-error")

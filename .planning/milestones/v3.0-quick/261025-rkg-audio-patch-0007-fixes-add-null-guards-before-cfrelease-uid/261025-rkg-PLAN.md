---
phase: quick-261025-rkg
plan: 261025-rkg
type: execute
depends_on: []
files_modified:
  - native/mpv/audio/out/ao_coreaudio_utils.c
  - native/mpv/audio/out/ao_coreaudio_properties.c
  - native/patches/0007-audio-out-fix-device-enumeration-crashes.patch
  - native/patches/UPSTREAM.md
autonomous: true
---

# 261025-rkg: 0007: CoreAudio NULL guards; note WASAPI vs upstream 4dfee61

Audit facts (confirm in Task 1): `ca_select_device` releases `uid` from
`cfstr_from_cstr`, which returns NULL for invalid UTF-8; `ca_get_str` releases a
possibly NULL string; `CFRelease(NULL)` crashes. Upstream 4dfee616d0fd
("ao_wasapi: hold an MTA reference for the hotplug instance") fixes the same
COM-lifetime bug as 0007's hotplug part.

## Task 1: applicability result (checked 2026-10-25, done)
- Upstream 4dfee616d0fd conflicts with 0007 (all 3 hunks fail) because 0007
  already rewrote those lines. 0007 is a **superset**: `wasapi_com_init/uninit`
  (ao_wasapi.c ~303-322) take an MTA usage cookie and only `CoUninitialize` on
  the thread whose `CoInitializeEx` succeeded, for both the hotplug and the
  playback instance; upstream covers the hotplug instance only.
- Decision: **no WASAPI code change.** Our base does not contain 4dfee61, so
  reshaping now cannot reduce conflicts. Record in UPSTREAM.md (0007 row): at
  the next rebase onto a base containing 4dfee61, drop 0007's hotplug MTA lines
  in favour of upstream's `hotplug_mta` and keep the playback-path half.
- Still to confirm in Task 2: the CoreAudio NULL paths (`cfstr_from_cstr`
  returns NULL on invalid UTF-8; `ca_get_str` can release NULL).

## Task 2: edits
- `ca_select_device` (ao_coreaudio_utils.c ~90): a NULL `uid` must not reach
  `AudioObjectGetPropertyData` either; right after `cfstr_from_cstr` add
  `if (!uid) { err = kAudioHardwareBadDeviceError; goto coreaudio_error; }`
  (reuse the function's existing error path), and keep `CFRelease(uid)`
  reachable only with non-NULL `uid`.
- `ca_get_str` (ao_coreaudio_properties.c ~84-88): `ca_get` can return noErr
  with a NULL string; guard both lines:
  `*data = string ? cfstr_get_cstr(string) : NULL; if (string) CFRelease(string);`
  and check the callers cope with `*data == NULL` (else return an error).
- No WASAPI change (Task 1).

## Task 3: fold into 0007, UPSTREAM.md, verify
- Done = macOS CI build green + `check_patches.sh` prints `PATCH-DRIFT OK`.
  No test reaches the invalid-UTF-8 device name path; do not claim one.
- Commit: `fix(native): CoreAudio NULL CFRelease guards; note WASAPI vs upstream 4dfee61`.

## Review revisions (2026-10-25, plan-checker pass; these are authoritative and supersede any conflicting text above)
- Before editing, run `grep -l ao_coreaudio_properties native/patches/*.patch`;
  if 0007 does not touch that file yet, add a new section diffed against the
  HEAD content.

**Host facts:** this host is Windows (MSYS Git Bash, MSVC on PATH, no meson/ninja),
so libmpv and `native/tests` cannot be built locally; native build/tests run on
CI (`.github/workflows/native-verify.yml`, incl. the ASan/UBSan job). Dart
tests run locally with `MPV_KIT_LIBMPV_PATH=D:/mpv_kit/bt/libmpv-2.dll`
(mpv v0.41.0-689, an older local build without this branch's patches; tests
that need patched native behaviour must skip locally and run on CI).

**Patch regeneration (shared rule, see native/patches/UPSTREAM.md):** the vendored
tree must equal base + `native/patches/0*.patch` applied in order with GNU
`patch -p1`. To fold a vendored edit into its owning patch: for files the
owning patch *creates*, replace that file's section with a `/dev/null` diff of
the new content (keep its CRLF/LF bytes exactly: `git ls-files --eol`); for
upstream files, add/replace the file section with `diff -u` against the base
content (= content before this item when no other patch touches the file;
confirm with `grep -l <file> native/patches/*.patch`). Preserve each patch's
existing line endings (some are `i/mixed`). Then run
`bash tools/check_patches.sh` (needs network; runnable on this Windows/MSYS
host) and require `PATCH-DRIFT OK`.

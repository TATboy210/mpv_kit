# Quick Task 261027-or3: Linux release build vs libdrm >= 2.4.114 - Research

**Researched:** 2026-10-27
**Confidence:** HIGH on the root cause and the runtime hazard, MEDIUM on the BIND_NOW detail (see A1).

## User Constraints (task brief, verbatim intent)
- Actually fix the Linux release build and keep VA-API through DRM render nodes. Do NOT switch to `-Ddrm=auto`.
- Bundle must run on glibc 2.35+ hosts (Ubuntu 22.04, libdrm 2.4.113). libdrm stays a HOST library (allowlisted in package.sh, never bundled).
- LGPL-only; patch set reviewable (`native/patches/` + `UPSTREAM.md`); minimal, independently revertible; keep edits local to the Linux arm (Phase 15 moves -Dgl/-Degl into per-platform arms).
- No edits outside the RESEARCH.md here; do not touch `.planning/config.json`, `state.json`, `tmp/`, `ui-reviews/`, `engine_repo_embedder.cc`.

## Summary

mpv raised its libdrm floor in upstream commit `4bed99f6a` (2026-03-28) "meson: bump minimum libdrm version to 2.4.114": "We'll use the dumb buffer helpers added in 2.4.114 and GEM_CLOSE wrapper added in 2.4.108" [VERIFIED: `gh api search/commits repo:mpv-player/mpv`]. The release job runs in `container: ubuntu:22.04` (release.yml:37), so its libdrm is 2.4.113, not the host runner's.

I diffed every `drm*()` function called anywhere under `native/mpv/{video,audio,osdep,options,player,common}` (40 distinct functions) against the libdrm 2.4.113 `xf86drm.h`/`xf86drmMode.h`. Exactly three are absent in 2.4.113 and present in 2.4.114 [VERIFIED: gitlab raw `libdrm-2.4.113/xf86drmMode.h` has no "DumbBuffer"; `libdrm-2.4.114/xf86drmMode.h:509,519,530`]:

```
drmModeCreateDumbBuffer   drmModeDestroyDumbBuffer   drmModeMapDumbBuffer
```
They are real exported functions (not macros) and are used only in `native/mpv/video/out/vo_drm.c` (lines 78, 92, 140), the `--vo=drm` console output that mpv_kit never selects. Everything else the floor might touch is fine on 2.4.113: `drmCloseBufferHandle`, `drmGetRenderDeviceNameFromFd` (xf86drm.h:837,840 in 2.4.113), `drmIsKMS` (xf86drmMode.h in 2.4.113), and the only libdrm macro added in 2.4.114, `DRM_FORMAT_P030`, is already `#ifdef`-guarded in `video/out/hwdec/dmabuf_interop_gl.c:239` ("Format added in a newer libdrm version than minimum"). The `DRM_MODE_COLORIMETRY_*` / `DRM_OPTS_*` names are mpv-internal (drm_common.h), not libdrm.

The 2.4.114 implementations are three thin `drmIoctl` wrappers (`xf86drmMode.c` 2.4.114: `DRM_IOCTL_MODE_CREATE_DUMB` / `DESTROY_DUMB` / `MAP_DUMB`), so the floor is a convenience, not a capability.

**Primary recommendation:** Option (b): new downstream patch `0010-drm-build-against-libdrm-2.4.113.patch` that lowers the meson floor to `>= 2.4.113` and replaces the 3 helper calls in `vo_drm.c` with static ioctl shims. No new dependency, no libdrm bundling, libmpv.so.2 then references only symbols present in 2.4.113, build.sh keeps `-Ddrm=enabled`.

## Runtime compatibility (question 2)
- libdrm.so ships SONAME `libdrm.so.2` (library `version: '2.4.0'`), `gnu_symbol_visibility: 'hidden'`, and **no ELF symbol versioning** [VERIFIED: libdrm-2.4.114 meson.build `library('drm', ... kwargs: {'version': '2.4.0'}, gnu_symbol_visibility: 'hidden')`; a core-symbols.txt check, no version script]. Consequence: a libmpv built against 2.4.114+ gets three plain undefined `drmMode*DumbBuffer` references, not versioned ones, and nothing records "needs 2.4.114".
- On a 2.4.113 host those three are unresolved. With eager binding (`-z now`, plausibly the default of the Ubuntu 22.04 toolchain for hardened builds) `dlopen("libmpv.so.2")` fails entirely, which is fatal for the Dart `MpvLibrary.open`. With lazy binding it loads and crashes (symbol lookup error, process abort) only the first time `vo=drm` runs. Either way it is an unacceptable latent defect [A1: BIND_NOW default not verified in this session; check with `readelf -d libmpv.so.2 | grep -E 'FLAGS|BIND_NOW'`].
- So option (a) below is NOT runtime-safe on Ubuntu 22.04 hosts, and it also makes the in-CI smoke test lie: `LD_LIBRARY_PATH=prefix/lib` (release.yml render_vk step) would pick up the prefix libdrm 2.4.114 and hide the missing host symbols.

## Options (question 3)

| Option | Verdict | Why |
|--------|---------|-----|
| (a) Build libdrm >= 2.4.114 into PREFIX, link `libdrm.so.2`, don't bundle | Reject | Build passes but libmpv gains 3 undefined symbols missing on 2.4.113 hosts (above). Also a second libdrm in the process via LD_LIBRARY_PATH during tests. Static-linking libdrm.a into libmpv avoids it but breaks the "libdrm is a host library" rule and needs `--exclude-libs` to avoid interposing libva's libdrm. More machinery than (b). |
| **(b) Patch: floor 2.4.113 + ioctl shims in vo_drm.c** | **Recommend** | Only 3 symbols, one file, behavior identical to libdrm's own implementation. Result links against 2.4.113 and runs on anything >= 2.4.113. LGPL unaffected. |
| (b') Patch that only drops vo_drm.c from the build | Reject | Touches meson sources and the `vo.c` driver table (`#if HAVE_DRM`, vo.c:112); larger and removes a feature. |
| (c) PPA/backport libdrm in the 22.04 container | Reject | Same symbol problem as (a) (build against newer libdrm), plus a third-party trust surface. |
| (c) ubuntu:24.04 container/runner for the build | Reject | glibc 2.39 on the build image breaks the glibc 2.35 baseline (package.sh/NEEDED); the point of the 22.04 container is exactly that. |

Cost of (b): the vendored tree gets two small deltas that upstream may someday drop; mpv itself deliberately requires 2.4.114 (Debian 12 / Ubuntu 24.04 era), so this is not upstreamable as-is [A2]. Revert = delete the patch, restore the two files, nothing else depends on it.

## Integration points (question 4)

Provenance rule: `tools/check_patches.sh` requires `native/mpv` to be byte-identical to base + `native/patches/0*.patch` (name order; `native-verify.yml` job `patch-drift`). So the implementer must (1) edit the vendored files, (2) generate `0010-...patch` from that delta (base = commit in `native/mpv/MPV_VERSION`, GNU `diff -u`/`git diff --no-index`, `-p1` paths like the existing 0008), (3) run `bash tools/check_patches.sh`. 0005 is an intentional gap; use the next free number 0010 (0009 exists).

1. `native/mpv/meson.build:1011`
   ```diff
   -drm = dependency('libdrm', version: '>= 2.4.114', required: get_option('drm'))
   +drm = dependency('libdrm', version: '>= 2.4.113', required: get_option('drm'))
   ```
   (add a one-line comment: mpv_kit builds on the Ubuntu 22.04 libdrm; vo_drm.c carries ioctl shims.)
2. `native/mpv/video/out/vo_drm.c`: add three `static` helpers near the top (after includes), then change the 3 call sites (lines 78, 92, 140) to them. Reference body (equivalent to libdrm 2.4.114 `xf86drmMode.c`):
   ```c
   // libdrm 2.4.113 (Ubuntu 22.04) lacks drmMode*DumbBuffer (added in 2.4.114);
   // they are thin wrappers over these ioctls.
   static int mp_drm_create_dumb(int fd, uint32_t w, uint32_t h, uint32_t bpp,
                                 uint32_t flags, uint32_t *handle,
                                 uint32_t *pitch, uint64_t *size)
   {
       struct drm_mode_create_dumb c = {.width = w, .height = h, .bpp = bpp, .flags = flags};
       int ret = drmIoctl(fd, DRM_IOCTL_MODE_CREATE_DUMB, &c);
       if (ret) return ret;
       *handle = c.handle; *pitch = c.pitch; *size = c.size;
       return 0;
   }
   static int mp_drm_destroy_dumb(int fd, uint32_t handle)
   {
       struct drm_mode_destroy_dumb d = {.handle = handle};
       return drmIoctl(fd, DRM_IOCTL_MODE_DESTROY_DUMB, &d);
   }
   static int mp_drm_map_dumb(int fd, uint32_t handle, uint64_t *offset)
   {
       struct drm_mode_map_dumb m = {.handle = handle};
       int ret = drmIoctl(fd, DRM_IOCTL_MODE_MAP_DUMB, &m);
       if (ret) return ret;
       *offset = m.offset;
       return 0;
   }
   ```
   `drmIoctl` is declared in 2.4.113 `xf86drm.h`; the structs/ioctl numbers come from `drm.h`/`drm_mode.h`, which `xf86drmMode.h` already pulls in (confirm the include compiles; add `#include <drm_mode.h>` only if not). Types/arg order match the existing call sites.
3. `native/patches/UPSTREAM.md`: new section "0010 libdrm 2.4.113 floor": cites `4bed99f6a`, states "downstream only, not upstreamed; drop on next rebase if the release container moves to libdrm >= 2.4.114".
4. `native/build/build.sh`: **no change**; `-Ddrm=enabled` at line 30 stays. `native/build/deps.sh`: no change. `release.yml`: no install change (`libdrm-dev` already at line 47; 22.04 provides 2.4.113 and `hwdata`/libdisplay-info are already handled by deps.sh:137-143).
5. `release.yml`, new step after "Build FFmpeg and libmpv" (before smoke test; Linux-only workflow section, so no cross-platform leakage). Authoritative runtime-floor guard, because the container's libdrm IS the 2.4.113 floor:
   ```yaml
   - name: libmpv resolves against the container libdrm (2.4.113 floor)
     run: |
       unresolved=$(LD_LIBRARY_PATH="$PWD/prefix/lib" ldd -r prefix/lib/libmpv.so.2 2>&1 | grep 'undefined symbol: drm' || true)
       if [ -n "$unresolved" ]; then echo "$unresolved" >&2; exit 1; fi
       nm -D --undefined-only prefix/lib/libmpv.so.2 | grep -E ' drm(Mode)?[A-Za-z]+' | sort -u   # evidence in the log
   ```
   Caveat: `prefix/lib` must not contain a libdrm (it does not under option (b); deps.sh builds none).
6. `native-verify.yml`: it runs on bare `ubuntu-24.04` (libdrm 2.4.120), so forcing drm there will NOT catch a 2.4.113 regression; only the 22.04 release container can. Still, adding `-Ddrm=enabled` to the Linux job's `meson setup` line (native-verify.yml:72 only, NOT to the shared `MESON_ARGS`, which macOS/Windows jobs also use) turns a silent `drm` drop (e.g. missing libdisplay-info) into a hard failure. Optional follow-up; not required for the fix, and only after one scratch run shows it configures (the job's apt list has `libdrm-dev` but not libva-dev; do not also force vaapi there) [A3: whether drm is currently enabled or dropped in that job was not checked].

## Don't Hand-Roll
Do not write a new libdrm wrapper layer or version-detect macros: libdrm has no version macro, so unconditional ioctl shims (identical to libdrm's own code) are simplest.

## Common Pitfalls
- Editing `native/mpv` without regenerating the patch: `patch-drift` fails. Run `bash tools/check_patches.sh`.
- Making the shims conditional on `drm.version()`: the vendored build env may differ; keep them unconditional.
- Verifying only on `ubuntu-24.04`: passes either way (libdrm 2.4.120); the 22.04 container is the real test.
- `ldd -r` check run with a libdrm in PREFIX masks the host: keep PREFIX libdrm-free.
- Phase 15: touching the Linux arm of build.sh for drm would conflict; this fix deliberately does not touch build.sh.

## Verification (question 5)
1. Local, no Linux needed: `bash tools/check_patches.sh` (patch-drift) after generating 0010.
2. Dispatch `release.yml` on a scratch branch `ci/14-*` (e.g. continue `ci/14-angle`); expected: linux-x64 and linux-arm64 pass `meson setup` (`Dependency libdrm found: YES 2.4.113`), build, the new `ldd -r`/`nm -D` step, render_vk smoke, and package.sh's NEEDED walk (libdrm is allowlisted, `package.sh:45`, so it is never copied and cannot appear in the bundle `lib/`).
3. Bundle check: `ls dist/libmpv-linux-*/lib | grep -c libdrm` must be 0; `objdump -p lib/libmpv.so.2 | grep NEEDED` still lists `libdrm.so.2` and `libva*`.
4. Floor audit beyond ldd: `nm -D --undefined-only libmpv.so.2 | grep drm` must contain none of `drmModeCreateDumbBuffer|drmModeDestroyDumbBuffer|drmModeMapDumbBuffer`.
5. Optional: on the dispatch run, `strings`/`meson-logs` should show `drm: YES` and `vaapi-drm: YES`, `vaapi: YES` (proves the user's "keep VA-API" constraint).
Note: the earlier run `40476764990` also showed windows green; this change touches Linux only.

## Assumptions Log

| # | Claim | Risk if Wrong |
|---|-------|---------------|
| A1 | Ubuntu 22.04 gcc defaults to `-z now` for shared libs so a missing symbol fails dlopen | Only changes failure mode (load failure vs later crash); option (b) removes both |
| A2 | The libdrm-floor patch would not be accepted upstream | Low: only affects whether UPSTREAM.md says "not upstreamed" |
| A3 | native-verify.yml linux job's drm state (enabled vs silently dropped) was not inspected | The optional `-Ddrm=enabled` hardening may need libdisplay-info from deps.sh to configure |

## Environment Availability
Linux build and `ldd`/`readelf` are not available on this Windows MINGW64 host; all verification above runs in CI (consistent with the project constraint "real behavior verified on CI runners"). Network/gh/curl were available and used.

## Sources
- mpv commit `4bed99f6a` "meson: bump minimum libdrm version to 2.4.114" (2026-03-28), via `gh api search/commits`.
- libdrm `libdrm-2.4.113` vs `libdrm-2.4.114` files (`xf86drm.h`, `xf86drmMode.h`, `xf86drmMode.c`, `meson.build`, `include/drm/drm_fourcc.h`), gitlab.freedesktop.org/mesa/drm raw tags.
- Repo: `native/mpv/meson.build:1011-1028,1497-1526`, `native/mpv/video/out/vo_drm.c:78,92,140`, `native/mpv/video/out/hwdec/dmabuf_interop_gl.c:239`, `native/build/build.sh:24-32`, `native/build/deps.sh:137-143`, `native/build/package.sh:45`, `.github/workflows/release.yml:37-48,66-76`, `.github/workflows/native-verify.yml:17-24,28,72`, `tools/check_patches.sh`, `native/patches/UPSTREAM.md`.
- Fallback data if (a) is ever wanted: libdrm 2.4.114 tarball `https://dri.freedesktop.org/libdrm/libdrm-2.4.114.tar.xz` sha256 `3049cf843a47d12e5eeefbc3be3496d782fa09f42346bf0b7defe3d1e598d026` (computed locally from the download, not from an upstream signature).

**Valid until:** 2026-11-27 (or next mpv rebase).

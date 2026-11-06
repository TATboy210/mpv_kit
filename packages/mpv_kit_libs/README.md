# mpv_kit_libs

Prebuilt **GPL-3.0+** libmpv for [mpv_kit](https://pub.dev/packages/mpv_kit):
mpv 0.42.0 with the mpv_kit Vulkan render patch, FFmpeg 8.1.3 (LGPL) and the
full optical-disc stack — CD-DA, DVD-Video menus, DVD-Audio, Blu-ray/UHD
HDMV — plus the libcurl HTTP/2 backend.

> **License:** the bundled libmpv is GPL-3.0-or-later (mpv is GPLv2+, and
> libcdio is GPLv3). An application that ships this bundle must be
> GPL-compatible and provide its own source. The Dart packages themselves
> remain MIT. If you need an LGPL libmpv, build it yourself with
> `MPV_KIT_FLAVOR=lgpl` and load it with `MPV_KIT_LIBMPV_PATH` (see below).

```yaml
dependencies:
  mpv_kit: ^0.1.0-dev.9
  mpv_kit_libs: ^0.1.0-dev.9
```

The package's build hook downloads the release bundle for the target
platform from GitHub Releases, verifies the archive against a sha256 pinned
in this package and every file against the bundle's own manifest, and
bundles the libraries into the app (next to the executable on Windows and
Linux, as frameworks on macOS). Nothing is executed during the build.

Each bundle ships `LICENSE.GPL`, `LICENSE.LGPL`, the third-party licenses,
`SOURCE.txt` (corresponding-source offer) and the mpv_kit patches.

## Using your own libmpv

Point the hook at a local bundle (a `libmpv-<target>.tar.gz` produced by
`native/build/package.sh`, or its extracted directory containing `lib/`)
in the application's `pubspec.yaml`:

```yaml
hooks:
  user_defines:
    mpv_kit_libs:
      libmpv_bundle: third_party/libmpv-windows-x64
```

For a pure Dart app that depends on `mpv_kit` alone, you can instead skip
this package and set `MPV_KIT_LIBMPV_PATH` (or rely on a system libmpv).

A Flutter app cannot skip the package: `mpv_kit_video` depends on it, so
`pub` always fetches its (small) source, and the build hook downloads the
pinned bundle. `MPV_KIT_LIBMPV_PATH` only changes which library the runtime
loads; it does not stop the hook. To avoid the bundle download, point the
hook at a local bundle with the `libmpv_bundle` user define shown above.

## Building the LGPL flavor yourself

`native/build/build.sh` and `package.sh` accept `MPV_KIT_FLAVOR=lgpl`:
the build keeps `-Dgpl=false` and omits the GPL disc libraries, so the
result can be linked by closed-source applications. The release pipeline
only publishes the GPL full flavor.

## License

The hook code is MIT. The bundled libraries are GPL-3.0-or-later (libmpv
and the CD/DVD stack), LGPL-2.1-or-later (FFmpeg, libbluray, libudfread,
libaacs, libbdplus, libgcrypt, libgpg-error) or permissive (libcurl,
nghttp2, mbedTLS, libxml2). See `LICENSE.GPL`, `LICENSE.LGPL`, the
`share/licenses/` directory and `SOURCE.txt` in each bundle.

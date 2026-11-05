# mpv_kit_libs

Prebuilt LGPL libmpv for [mpv_kit](https://pub.dev/packages/mpv_kit):
mpv 0.41.0 with the mpv_kit Vulkan render patch, FFmpeg 8.1.3 built from
source without GPL/nonfree components, for Windows, Linux and macOS on x64
and arm64.

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

## License

The hook code is MIT. The bundled libraries are LGPL-2.1-or-later (libmpv,
FFmpeg) or permissive; each bundle contains `LICENSE.LGPL` and the mpv
patch it was built with.

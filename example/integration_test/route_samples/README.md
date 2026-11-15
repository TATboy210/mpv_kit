# Route samples

Test media for `integration_test/macos_route_test.dart` (Phase 13, HWD-04).
This directory is declared as an asset directory in `example/pubspec.yaml`,
so it must exist on every platform checkout; only this README is tracked.

The media files are generated, never committed:

- `h264-8bit.mp4` - libx264, yuv420p
- `hevc-8bit.mp4` - libx265, yuv420p
- `hevc-10bit.mp4` - libx265, yuv420p10le (Main10)

All three are 640x360, 30 fps, 4 s, one keyframe per 30 frames, at most
1 MiB. The `Generate route samples` step of `.github/workflows/macos-route.yml`
creates them on the macos-15 runner with Homebrew ffmpeg and records the
ffmpeg version plus each file's codec, pix_fmt and byte count as
`ROUTE-SAMPLES` lines. To run the test locally on a Mac, generate the files
with the same commands as that step.

The samples are plain test media. They are encoded with GPL encoders
(x264/x265) on purpose and never enter the LGPL libmpv bundle.

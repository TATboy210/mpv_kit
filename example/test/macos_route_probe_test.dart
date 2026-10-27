// Unit tests of the macOS route probe's pure helpers (Phase 13, MAC-02):
// region statistics and the visibility decision table. No plugin and no
// libmpv: the 640x360 RGBA images are built byte by byte.
library;

import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import '../integration_test/macos_route_probe.dart';

const _width = 640;
const _height = 360;

/// Fills [region] (whole pixels) of [rgba] with an opaque colour.
void _fill(Uint8List rgba, Rect region, int r, int g, int b) {
  for (var y = region.top.toInt(); y < region.bottom.toInt(); y++) {
    for (var x = region.left.toInt(); x < region.right.toInt(); x++) {
      final i = (y * _width + x) * 4;
      rgba[i] = r;
      rgba[i + 1] = g;
      rgba[i + 2] = b;
      rgba[i + 3] = 255;
    }
  }
}

/// A probe image: everything black, the control patch red and the background
/// region green, plus an optional fill of the texture region.
Uint8List _probeImage({
  (int, int, int)? texture,
  (int, int, int) control = (255, 0, 0),
}) {
  final rgba = Uint8List(_width * _height * 4);
  _fill(rgba, routeControlRegion, control.$1, control.$2, control.$3);
  _fill(rgba, routeBackgroundRegion, 0, 200, 0);
  if (texture != null) {
    _fill(rgba, routeTextureRegion, texture.$1, texture.$2, texture.$3);
  }
  return rgba;
}

/// Classifies [rgba] the way the integration test does (scale 1.0).
String _classify(Uint8List rgba) {
  RouteRegionStats? stats(Rect region) => routeRegionStats(
    rgba,
    width: _width,
    height: _height,
    region: region,
    sx: 1,
    sy: 1,
  );
  return routeVisibility(
    texture: stats(routeTextureRegion),
    control: stats(routeControlRegion),
    background: stats(routeBackgroundRegion),
  );
}

void main() {
  group('route probe visibility', () {
    test('black texture region with visible control is composited-black', () {
      expect(_classify(_probeImage()), 'texture-composited-black');
    });

    test('texture region still background green is not-composited', () {
      expect(
        _classify(_probeImage(texture: (0, 200, 0))),
        'texture-not-composited',
      );
    });

    test('black control patch makes the probe indeterminate', () {
      expect(
        _classify(_probeImage(texture: (200, 100, 50), control: (0, 0, 0))),
        'indeterminate',
      );
    });

    test('coloured texture region is texture-visible', () {
      expect(
        _classify(_probeImage(texture: (200, 100, 50))),
        'texture-visible',
      );
    });
  });

  group('route probe region statistics', () {
    test('region outside the scaled image yields null and indeterminate', () {
      final rgba = _probeImage(texture: (200, 100, 50));
      // A scale of 2 pushes the control patch (right edge 640) to 1280 px,
      // beyond the 640 px wide image.
      final outside = routeRegionStats(
        rgba,
        width: _width,
        height: _height,
        region: routeControlRegion,
        sx: 2,
        sy: 2,
      );
      expect(outside, isNull);
      expect(
        routeVisibility(
          texture: routeRegionStats(
            rgba,
            width: _width,
            height: _height,
            region: routeTextureRegion,
            sx: 1,
            sy: 1,
          ),
          control: outside,
          background: routeRegionStats(
            rgba,
            width: _width,
            height: _height,
            region: routeBackgroundRegion,
            sx: 1,
            sy: 1,
          ),
        ),
        'indeterminate',
      );
    });
  });
}

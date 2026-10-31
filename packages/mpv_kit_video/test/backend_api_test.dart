// backendApiName: the startup log line prints the real graphics API (first
// token of the ADR 0004 reason), not the frozen two-value enum name. Pure
// function — no libmpv, runs everywhere.
import 'package:flutter_test/flutter_test.dart';
import 'package:mpv_kit_video/src/backend_api.dart';

void main() {
  test('returns the first token of a known API reason', () {
    expect(
      backendApiName('d3d11 (gpu-next) on NVIDIA GeForce GTX 960M', 'vulkan'),
      'd3d11',
    );
    expect(backendApiName('vulkan (gpu-next) on gpu', 'vulkan'), 'vulkan');
    expect(backendApiName('opengl (gpu) on gpu', 'vulkan'), 'opengl');
    expect(
      backendApiName(
        'software (sw) on cpu; vulkan/gpu-next unavailable: x',
        'software',
      ),
      'software',
    );
  });

  test('falls back to the enum name for empty or unparsable reasons', () {
    expect(backendApiName('', 'vulkan'), 'vulkan');
    expect(backendApiName('metal (gpu) on gpu', 'vulkan'), 'vulkan');
    expect(backendApiName('D3D11 (gpu-next)', 'vulkan'), 'vulkan');
  });
}

/// Derives the real graphics API name from an ADR 0004 backend reason.
///
/// Internal helper (not exported by the barrel): [MpvVideoBackend] is frozen
/// at `{vulkan, software}`, so the GPU zero-copy backends (D3D11, OpenGL,
/// Vulkan) all report `vulkan` there and the real API only appears as the
/// first token of `MpvVideoController.reason`.
library;

/// API tokens that ADR 0004 allows at the start of a reason string.
const _knownApis = {'d3d11', 'opengl', 'vulkan', 'software'};

/// First token of [reason] when it is a known API name, else [fallback].
///
/// The reason grammar is `api (renderer) on device[; trail ...]`, so the API
/// is everything before the first space. Empty or unrecognised reasons (a
/// plugin that predates ADR 0004, a garbage string) fall back to [fallback]
/// — the frozen enum's name — instead of printing a made-up API.
String backendApiName(String reason, String fallback) {
  final api = reason.split(' ').first;
  return _knownApis.contains(api) ? api : fallback;
}

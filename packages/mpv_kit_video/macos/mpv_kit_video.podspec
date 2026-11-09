# mpv_kit_video macOS plugin: renders mpv through MoltenVK into IOSurface
# backed CVPixelBuffers that Flutter's Metal compositor samples directly.
Pod::Spec.new do |s|
  s.name             = 'mpv_kit_video'
  s.version          = '0.1.0'
  s.summary          = 'Zero-copy Vulkan video output for mpv_kit.'
  s.homepage         = 'https://github.com/TATboy210/mpv_kit'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'mpv_kit authors' => 'https://github.com/TATboy210/mpv_kit' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.public_header_files = 'Classes/MpvKitVideoPlugin.h'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '12.0'
  s.frameworks = 'Metal', 'CoreVideo', 'IOSurface'
  # Shared renderer, mpv headers and vendored Vulkan headers/volk live next
  # to this directory in the package.
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'HEADER_SEARCH_PATHS' => [
      '"${PODS_TARGET_SRCROOT}/../src"',
      '"${PODS_TARGET_SRCROOT}/../src/include"',
      '"${PODS_TARGET_SRCROOT}/../third_party/vulkan-headers/include"',
      '"${PODS_TARGET_SRCROOT}/../third_party/volk"',
    ].join(' '),
    # ObjC++ (.mm) does not auto-link modules, so FlutterMacOS must be
    # linked explicitly (flutter_tools only adds its search path).
    'OTHER_LDFLAGS' => '$(inherited) -framework FlutterMacOS',
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) VK_NO_PROTOTYPES=1 VK_USE_PLATFORM_METAL_EXT=1',
  }
  s.swift_version = '5.0'
end

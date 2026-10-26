// macOS plugin: one Flutter texture per mpv instance.
//
// Method channel "mpv_kit_video" (same contract as Windows/Linux):
//   create  {symbols: List<int>, handle: int, renderer: String}
//           -> {textureId: int, backend: "d3d11"|"opengl"|"vulkan"|"software",
//               reason: String}
//           backend is the winning backend's own wire name
//           (VideoRenderer::wire_name(), ADR 0004 Decision 2). When no
//           backend works: error render_init / "no usable render backend",
//           details: String, the reason trails (why each candidate failed).
//   setSize {textureId: int, width: int, height: int}
//   setIccProfile {textureId: int, profile: Uint8List} (empty: clear)
//   dispose {textureId: int}
// Native -> Dart:
//   event   {textureId: int, kind: String, message: String}
#import "MpvKitVideoPlugin.h"

#include <cstring>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

#include "metal_interop.h"

using mpv_kit::Backend;
using mpv_kit::Frame;
using mpv_kit::MetalInterop;
using mpv_kit::MpvApi;
using mpv_kit::ParseRendererChoice;
using mpv_kit::VideoRenderer;

/// Texture object retained by the engine; may outlive dispose, so every
/// callback checks [dead_] under [mutex_].
@interface MpvKitTexture : NSObject <FlutterTexture>
- (instancetype)initWithInterop:(std::unique_ptr<MetalInterop>)interop
                       renderer:(std::unique_ptr<VideoRenderer>)renderer;
- (VideoRenderer*)renderer;
- (void)shutdown;
@end

@implementation MpvKitTexture {
  std::mutex _mutex;
  bool _dead;
  std::unique_ptr<MetalInterop> _interop;
  std::unique_ptr<VideoRenderer> _renderer;
  // Software backend: pool of IOSurface buffers and the last one filled.
  CVPixelBufferPoolRef _swPool;
  int _swPoolWidth, _swPoolHeight;
  CVPixelBufferRef _swBuffer;
  int _swFrame;
}

- (instancetype)initWithInterop:(std::unique_ptr<MetalInterop>)interop
                       renderer:(std::unique_ptr<VideoRenderer>)renderer {
  if ((self = [super init])) {
    _dead = false;
    _interop = std::move(interop);
    _renderer = std::move(renderer);
    _swPool = nullptr;
    _swPoolWidth = _swPoolHeight = 0;
    _swBuffer = nullptr;
    _swFrame = -1;
  }
  return self;
}

- (void)dealloc {
  [self shutdown];
}

- (VideoRenderer*)renderer {
  return _renderer.get();
}

- (void)shutdown {
  {
    // Once dead is set, copyPixelBuffer returns early, so the (possibly
    // slow) teardown below runs without blocking the raster thread.
    std::lock_guard<std::mutex> lock(_mutex);
    if (_dead) return;
    _dead = true;
  }
  _renderer.reset();  // joins the render thread, frees the image ring
  _interop.reset();
  if (_swBuffer) CVPixelBufferRelease(_swBuffer);
  _swBuffer = nullptr;
  if (_swPool) CVPixelBufferPoolRelease(_swPool);
  _swPool = nullptr;
}

/// Raster thread. Returns an owned (+1) reference, as the protocol requires.
- (CVPixelBufferRef)copyPixelBuffer {
  std::lock_guard<std::mutex> lock(_mutex);
  if (_dead) return nullptr;
  const Frame f = _renderer->AcquireFront();
  if (_renderer->backend() == Backend::kVulkan) {
    // Already retained for us in AcquireFront (MetalInterop::RetainFrame).
    return static_cast<CVPixelBufferRef>(f.platform);
  }
  if (!f.pixels) return nullptr;
  return [self copySoftwareFrame:f];
}

- (CVPixelBufferRef)copySoftwareFrame:(const Frame&)f {
  // Same frame as last time: hand out the buffer it was copied into.
  if (f.index == _swFrame && _swBuffer &&
      CVPixelBufferGetWidth(_swBuffer) == size_t(f.width) &&
      CVPixelBufferGetHeight(_swBuffer) == size_t(f.height))
    return CVPixelBufferRetain(_swBuffer);
  // A pool recycles only buffers Flutter has released, so a frame is never
  // written while the compositor samples it.
  if (!_swPool || _swPoolWidth != f.width || _swPoolHeight != f.height) {
    if (_swPool) CVPixelBufferPoolRelease(_swPool);
    _swPool = nullptr;
    NSDictionary* attrs = @{
      (id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA),
      (id)kCVPixelBufferWidthKey : @(f.width),
      (id)kCVPixelBufferHeightKey : @(f.height),
      (id)kCVPixelBufferIOSurfacePropertiesKey : @{},
      (id)kCVPixelBufferMetalCompatibilityKey : @YES,
    };
    if (CVPixelBufferPoolCreate(kCFAllocatorDefault, nullptr,
                                (__bridge CFDictionaryRef)attrs,
                                &_swPool) != kCVReturnSuccess)
      return nullptr;
    _swPoolWidth = f.width;
    _swPoolHeight = f.height;
  }
  CVPixelBufferRef pb = nullptr;
  if (CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, _swPool, &pb) !=
      kCVReturnSuccess)
    return nullptr;
  CVPixelBufferLockBaseAddress(pb, 0);
  auto* dst = static_cast<uint8_t*>(CVPixelBufferGetBaseAddress(pb));
  const size_t dst_stride = CVPixelBufferGetBytesPerRow(pb);
  const size_t row = size_t(f.width) * 4;
  for (int y = 0; y < f.height; y++)
    std::memcpy(dst + y * dst_stride, f.pixels + y * row, row);
  CVPixelBufferUnlockBaseAddress(pb, 0);
  if (_swBuffer) CVPixelBufferRelease(_swBuffer);
  _swBuffer = CVPixelBufferRetain(pb);  // ours; the +1 from the pool is Flutter's
  _swFrame = f.index;
  return pb;
}

@end

@implementation MpvKitVideoPlugin {
  FlutterMethodChannel* _channel;
  NSObject<FlutterTextureRegistry>* _textures;
  NSMutableDictionary<NSNumber*, MpvKitTexture*>* _instances;
}

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  FlutterMethodChannel* channel =
      [FlutterMethodChannel methodChannelWithName:@"mpv_kit_video"
                                  binaryMessenger:registrar.messenger];
  MpvKitVideoPlugin* plugin = [[MpvKitVideoPlugin alloc] init];
  plugin->_channel = channel;
  plugin->_textures = registrar.textures;
  plugin->_instances = [NSMutableDictionary dictionary];
  [registrar addMethodCallDelegate:plugin channel:channel];
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
  NSDictionary* args = [call.arguments isKindOfClass:NSDictionary.class]
                           ? call.arguments
                           : nil;
  if (!args) {
    result([FlutterError errorWithCode:@"bad_args" message:@"expected a map" details:nil]);
    return;
  }
  if ([call.method isEqualToString:@"create"]) {
    [self create:args result:result];
    return;
  }
  NSNumber* textureId = args[@"textureId"];
  MpvKitTexture* texture = textureId ? _instances[textureId] : nil;
  if (!texture) {
    result([FlutterError errorWithCode:@"no_texture" message:@"unknown textureId" details:nil]);
  } else if ([call.method isEqualToString:@"setSize"]) {
    texture.renderer->SetSize([args[@"width"] intValue], [args[@"height"] intValue]);
    result(nil);
  } else if ([call.method isEqualToString:@"setIccProfile"]) {
    FlutterStandardTypedData* p =
        [args[@"profile"] isKindOfClass:FlutterStandardTypedData.class]
            ? args[@"profile"]
            : nil;
    const auto* bytes = static_cast<const uint8_t*>(p.data.bytes);
    texture.renderer->SetIccProfile(
        p ? std::vector<uint8_t>(bytes, bytes + p.data.length)
          : std::vector<uint8_t>());
    result(nil);
  } else if ([call.method isEqualToString:@"dispose"]) {
    [_instances removeObjectForKey:textureId];
    [texture shutdown];
    [_textures unregisterTexture:textureId.longLongValue];
    result(nil);
  } else {
    result(FlutterMethodNotImplemented);
  }
}

- (void)create:(NSDictionary*)args result:(FlutterResult)result {
  NSArray* symbols = [args[@"symbols"] isKindOfClass:NSArray.class] ? args[@"symbols"] : nil;
  NSNumber* handle = [args[@"handle"] isKindOfClass:NSNumber.class] ? args[@"handle"] : nil;
  if (!symbols || !handle || handle.longLongValue == 0) {
    result([FlutterError errorWithCode:@"bad_args" message:@"symbols/handle" details:nil]);
    return;
  }
  std::vector<int64_t> addrs;
  for (id v in symbols) {
    addrs.push_back([v isKindOfClass:NSNumber.class] ? [v longLongValue] : 0);
  }
  MpvApi api;
  if (!api.Load(addrs.data(), static_cast<int>(addrs.size()))) {
    result([FlutterError errorWithCode:@"bad_symbols"
                               message:@"libmpv symbol table incomplete"
                               details:nil]);
    return;
  }
  NSString* rendererName =
      [args[@"renderer"] isKindOfClass:NSString.class] ? args[@"renderer"] : @"auto";
  const auto choice = ParseRendererChoice(rendererName.UTF8String);

  // The texture id is only known after registration; the render thread
  // reads it through this shared cell.
  auto textureIdCell = std::make_shared<std::atomic<int64_t>>(-1);
  __weak NSObject<FlutterTextureRegistry>* weakTextures = _textures;
  auto interop = std::make_unique<MetalInterop>([textureIdCell, weakTextures] {
    const int64_t tid = textureIdCell->load();
    if (tid >= 0) [weakTextures textureFrameAvailable:tid];
  });
  __weak FlutterMethodChannel* weakChannel = _channel;
  auto renderer = std::make_unique<VideoRenderer>(
      api, reinterpret_cast<mpv_handle*>(static_cast<intptr_t>(handle.longLongValue)),
      interop.get(), [](const std::string& msg) { NSLog(@"%s", msg.c_str()); },
      [textureIdCell, weakChannel](const char* kind, const std::string& msg) {
        // Render thread: the channel may only be used on the main thread.
        const int64_t tid = textureIdCell->load();
        if (tid < 0) return;
        NSString* k = [NSString stringWithUTF8String:kind];
        NSString* m = [NSString stringWithUTF8String:msg.c_str()] ?: @"";
        dispatch_async(dispatch_get_main_queue(), ^{
          [weakChannel invokeMethod:@"event"
                          arguments:@{@"textureId" : @(tid), @"kind" : k, @"message" : m}];
        });
      });
  if (!renderer->Start(choice)) {
    // The trails say why every candidate was unavailable.
    NSString* trails = [NSString stringWithUTF8String:renderer->backend_reason().c_str()];
    result([FlutterError errorWithCode:@"render_init"
                               message:@"no usable render backend"
                               details:trails ?: @""]);
    return;
  }
  NSString* wire = [NSString stringWithUTF8String:renderer->wire_name()];
  NSString* reason = [NSString stringWithUTF8String:renderer->backend_reason().c_str()];

  MpvKitTexture* texture = [[MpvKitTexture alloc] initWithInterop:std::move(interop)
                                                         renderer:std::move(renderer)];
  const int64_t tid = [_textures registerTexture:texture];
  textureIdCell->store(tid);
  _instances[@(tid)] = texture;
  result(@{
    @"textureId" : @(tid),
    @"backend" : wire,
    @"reason" : reason ?: @"",
  });
}

@end

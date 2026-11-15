// d3d11_caps_probe.cpp - read-only D3D11 capability probe (Phase 14, plan 14-01).
//
// Purpose: replace guesses about the D3D11 runtime behaviour that the Windows
// D3D11 render backend depends on with measured data. For every DXGI adapter
// (software adapters included) and once more for D3D_DRIVER_TYPE_WARP, one
// "CAPS" line is printed on stdout:
//
//   CAPS host=<--host> adapter="<description>" luid=<hex> driver=<kind> key=value ...
//
//   driver=hardware  an enumerated adapter without DXGI_ADAPTER_FLAG_SOFTWARE
//   driver=basic     an enumerated software adapter (Microsoft Basic Render Driver;
//                    this is what Flutter gets on hosted Windows runners)
//   driver=warp      a device created with D3D_DRIVER_TYPE_WARP (adapter == nullptr)
//
// Keys (HRESULTs are printed as 0x%08X; composite values are joined with '/'
// so that every line stays machine-splittable on spaces):
//   dedicated_vram_mib, software_adapter
//   create_bgra_video   BGRA_SUPPORT|VIDEO_SUPPORT, FL 11_1 then 11_0: hr/fl
//   create_bgra         BGRA_SUPPORT only:                           hr/fl
//   test_device         which of the two devices the remaining keys used
//   multithread_iface   QueryInterface for ID3D10Multithread
//   device5, create_fence, create_fence_shared, context4
//   fence_wait          Signal(1) + Flush + SetEventOnCompletion, 1000 ms wait
//   query_event         D3D11_QUERY_EVENT End + GetData polled for 1000 ms
//   bgra8_rt_srv        CheckFormatSupport(B8G8R8A8_UNORM): yes|no/hr/mask
//   bgra8_typed_uav_store  FORMAT_SUPPORT2 UAV_TYPED_STORE bit: yes|no/hr
//   shared_4k, shared_8k       BGRA8 RENDER_TARGET|SHADER_RESOURCE MISC_SHARED
//                              texture: create hr / GetSharedHandle hr
//   open_shared_4k, open_shared_8k  OpenSharedResource of that KMT handle on a
//                              second device of the same adapter (what the
//                              Flutter/ANGLE side does)
//   shared_uav_4k       as shared_4k plus UNORDERED_ACCESS (data only)
//   dim_16384, dim_16385  16384x16 / 16385x16 BGRA8 texture creation hr
//   req_dim_const       D3D11_REQ_TEXTURE2D_U_OR_V_DIMENSION compile-time value
//
// The probe only collects data: every failed step is recorded and the next
// one runs; the exit code is always 0. It writes no files.
//
// Build (MSVC, from a vcvars64 prompt):
//   cl /nologo /EHsc /std:c++17 /W4 /WX /O2 tools\d3d11_probe\d3d11_caps_probe.cpp ^
//      d3d11.lib dxgi.lib /Fe:d3d11_caps_probe.exe
// Build (MSYS2 clang++, CLANG64 / CLANGARM64):
//   clang++ -std=c++17 -O1 tools/d3d11_probe/d3d11_caps_probe.cpp -ld3d11 -ldxgi \
//      -o d3d11_caps_probe.exe
// Run:
//   d3d11_caps_probe.exe --host rtx4060-local

#ifndef NOMINMAX
#define NOMINMAX
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>

#include <d3d10_1.h>  // pulls in d3d10.h (ID3D10Multithread) in the order SAL tools expect
#include <d3d11_4.h>
#include <dxgi1_4.h>

#include <cstdarg>
#include <cstdio>
#include <cstring>
#include <string>

namespace {

// 4K / 8K UHD BGRA8 targets, the sizes the render backend must be able to share.
constexpr UINT k4kWidth = 3840;
constexpr UINT k4kHeight = 2160;
constexpr UINT k8kWidth = 7680;
constexpr UINT k8kHeight = 4320;
// Dimension boundary: the FL 11 limit and one past it; the other side is thin.
constexpr UINT kDimLimit = 16384;
constexpr UINT kDimThin = 16;
// Upper wait for fence / query completion on an idle device.
constexpr DWORD kWaitMs = 1000;
constexpr UINT64 kMiB = 1024ull * 1024ull;

// Minimal COM smart pointer (no WRL so that MSVC and MinGW clang both build).
template <class T>
class Com {
 public:
  Com() = default;
  ~Com() { Reset(); }
  Com(const Com&) = delete;
  Com& operator=(const Com&) = delete;
  // Releases the held pointer and returns the slot for an out-parameter.
  T** Put() {
    Reset();
    return &ptr_;
  }
  void** PutVoid() { return reinterpret_cast<void**>(Put()); }
  T* Get() const { return ptr_; }
  T* operator->() const { return ptr_; }
  explicit operator bool() const { return ptr_ != nullptr; }
  void Reset() {
    if (ptr_) {
      ptr_->Release();
      ptr_ = nullptr;
    }
  }

 private:
  T* ptr_ = nullptr;
};

std::string Fmt(const char* format, ...) {
  char buffer[512];
  va_list args;
  va_start(args, format);
  vsnprintf(buffer, sizeof(buffer), format, args);
  va_end(args);
  return buffer;
}

std::string Hr(HRESULT hr) { return Fmt("0x%08X", static_cast<unsigned>(hr)); }

const char* FeatureLevelName(D3D_FEATURE_LEVEL level) {
  switch (level) {
    case D3D_FEATURE_LEVEL_11_1: return "11_1";
    case D3D_FEATURE_LEVEL_11_0: return "11_0";
    case D3D_FEATURE_LEVEL_10_1: return "10_1";
    case D3D_FEATURE_LEVEL_10_0: return "10_0";
    default: return "other";
  }
}

// Space-separated key=value list; values must not contain spaces.
class Fields {
 public:
  void Add(const char* key, const std::string& value) {
    text_ += " ";
    text_ += key;
    text_ += "=";
    text_ += value;
  }
  const std::string& Text() const { return text_; }

 private:
  std::string text_;
};

// How a device is created, kept so a second identical device can be made.
struct DeviceSpec {
  IDXGIAdapter* adapter = nullptr;  // nullptr for D3D_DRIVER_TYPE_WARP
  D3D_DRIVER_TYPE type = D3D_DRIVER_TYPE_UNKNOWN;
  UINT flags = 0;
};

struct Device {
  Com<ID3D11Device> device;
  Com<ID3D11DeviceContext> context;
  D3D_FEATURE_LEVEL level = D3D_FEATURE_LEVEL_11_0;
};

HRESULT MakeDevice(const DeviceSpec& spec, Device& out) {
  const D3D_FEATURE_LEVEL levels[] = {D3D_FEATURE_LEVEL_11_1,
                                      D3D_FEATURE_LEVEL_11_0};
  return D3D11CreateDevice(spec.adapter, spec.type, nullptr, spec.flags, levels,
                           static_cast<UINT>(sizeof(levels) / sizeof(levels[0])),
                           D3D11_SDK_VERSION, out.device.Put(), &out.level,
                           out.context.Put());
}

std::string Utf8(const wchar_t* wide) {
  char buffer[256] = {};
  WideCharToMultiByte(CP_UTF8, 0, wide, -1, buffer, sizeof(buffer) - 1, nullptr,
                      nullptr);
  std::string text = buffer;
  for (char& c : text) {
    if (c == '"') c = '\'';  // keep the quoted adapter="..." field parseable
  }
  return text;
}

struct AdapterInfo {
  std::string name = "unknown";
  std::string luid = "0000000000000000";
  unsigned long long vram_mib = 0;
  bool software = false;
};

AdapterInfo DescribeAdapter(IDXGIAdapter* adapter) {
  AdapterInfo info;
  Com<IDXGIAdapter1> adapter1;
  if (!adapter || FAILED(adapter->QueryInterface(__uuidof(IDXGIAdapter1),
                                                 adapter1.PutVoid())))
    return info;
  DXGI_ADAPTER_DESC1 desc{};
  if (FAILED(adapter1->GetDesc1(&desc))) return info;
  info.name = Utf8(desc.Description);
  info.luid = Fmt("%08X%08X", static_cast<unsigned>(desc.AdapterLuid.HighPart),
                  static_cast<unsigned>(desc.AdapterLuid.LowPart));
  info.vram_mib = desc.DedicatedVideoMemory / kMiB;
  info.software = (desc.Flags & DXGI_ADAPTER_FLAG_SOFTWARE) != 0;
  return info;
}

// The adapter a (WARP) device actually runs on.
AdapterInfo DescribeDeviceAdapter(ID3D11Device* device) {
  Com<IDXGIDevice> dxgi_device;
  Com<IDXGIAdapter> adapter;
  if (!device ||
      FAILED(device->QueryInterface(__uuidof(IDXGIDevice),
                                    dxgi_device.PutVoid())) ||
      FAILED(dxgi_device->GetAdapter(adapter.Put())))
    return AdapterInfo{};
  return DescribeAdapter(adapter.Get());
}

// --- Device creation ---------------------------------------------------------

// Creates the VIDEO_SUPPORT device and the BGRA-only device. Both results are
// recorded because the backend must know whether it needs a retry without
// VIDEO_SUPPORT on the Basic Render Driver.
void ProbeCreation(const DeviceSpec& base, Device& video, Device& bgra,
                   Fields& fields) {
  DeviceSpec spec = base;
  spec.flags = D3D11_CREATE_DEVICE_BGRA_SUPPORT |
               D3D11_CREATE_DEVICE_VIDEO_SUPPORT;
  const HRESULT hr_video = MakeDevice(spec, video);
  fields.Add("create_bgra_video",
             Hr(hr_video) + "/" +
                 (SUCCEEDED(hr_video) ? FeatureLevelName(video.level) : "none"));

  spec.flags = D3D11_CREATE_DEVICE_BGRA_SUPPORT;
  const HRESULT hr_bgra = MakeDevice(spec, bgra);
  fields.Add("create_bgra",
             Hr(hr_bgra) + "/" +
                 (SUCCEEDED(hr_bgra) ? FeatureLevelName(bgra.level) : "none"));
}

// --- Threading interface and GPU/CPU synchronisation ----------------------------

void ProbeMultithread(Device& dev, Fields& fields) {
  Com<ID3D10Multithread> multithread;
  const HRESULT hr = dev.device->QueryInterface(__uuidof(ID3D10Multithread),
                                                multithread.PutVoid());
  fields.Add("multithread_iface", Hr(hr));
}

// Signals the fence from the GPU timeline and waits for it with an event.
std::string WaitOnFence(Device& dev, ID3D11Fence* fence) {
  Com<ID3D11DeviceContext4> context4;
  if (FAILED(dev.context->QueryInterface(__uuidof(ID3D11DeviceContext4),
                                         context4.PutVoid())))
    return "no_context4";
  HANDLE event = CreateEventW(nullptr, FALSE, FALSE, nullptr);
  if (!event) return "no_event";
  std::string result = "ok";
  const HRESULT signal_hr = context4->Signal(fence, 1);
  dev.context->Flush();
  const HRESULT event_hr = fence->SetEventOnCompletion(1, event);
  if (FAILED(signal_hr)) {
    result = "signal:" + Hr(signal_hr);
  } else if (FAILED(event_hr)) {
    result = "seteventoncompletion:" + Hr(event_hr);
  } else if (WaitForSingleObject(event, kWaitMs) != WAIT_OBJECT_0) {
    result = "wait_timeout";
  }
  CloseHandle(event);
  return result;
}

void ProbeFence(Device& dev, Fields& fields) {
  Com<ID3D11Device5> device5;
  const HRESULT hr5 = dev.device->QueryInterface(__uuidof(ID3D11Device5),
                                                 device5.PutVoid());
  fields.Add("device5", Hr(hr5));
  Com<ID3D11DeviceContext4> context4;
  fields.Add("context4",
             Hr(dev.context->QueryInterface(__uuidof(ID3D11DeviceContext4),
                                            context4.PutVoid())));
  if (FAILED(hr5)) {
    fields.Add("create_fence", "skipped");
    fields.Add("create_fence_shared", "skipped");
    fields.Add("fence_wait", "skipped");
    return;
  }
  Com<ID3D11Fence> plain;
  const HRESULT hr_plain = device5->CreateFence(
      0, D3D11_FENCE_FLAG_NONE, __uuidof(ID3D11Fence), plain.PutVoid());
  fields.Add("create_fence", Hr(hr_plain));
  Com<ID3D11Fence> shared;
  const HRESULT hr_shared = device5->CreateFence(
      0, D3D11_FENCE_FLAG_SHARED, __uuidof(ID3D11Fence), shared.PutVoid());
  fields.Add("create_fence_shared", Hr(hr_shared));
  ID3D11Fence* usable = plain ? plain.Get() : shared.Get();
  fields.Add("fence_wait", usable ? WaitOnFence(dev, usable) : "skipped");
}

// The fallback synchronisation path: an event query polled to completion.
void ProbeQuery(Device& dev, Fields& fields) {
  D3D11_QUERY_DESC desc{};
  desc.Query = D3D11_QUERY_EVENT;
  Com<ID3D11Query> query;
  const HRESULT hr = dev.device->CreateQuery(&desc, query.Put());
  if (FAILED(hr)) {
    fields.Add("query_event", "create:" + Hr(hr));
    return;
  }
  dev.context->End(query.Get());
  dev.context->Flush();
  const ULONGLONG deadline = GetTickCount64() + kWaitMs;
  std::string result = "timeout";
  for (;;) {
    BOOL done = FALSE;
    const HRESULT data_hr =
        dev.context->GetData(query.Get(), &done, sizeof(done), 0);
    if (data_hr == S_OK) {
      result = "ok";
      break;
    }
    if (FAILED(data_hr)) {
      result = "getdata:" + Hr(data_hr);
      break;
    }
    if (GetTickCount64() >= deadline) break;
    Sleep(1);
  }
  fields.Add("query_event", result);
}

// --- Format support ------------------------------------------------------------

void ProbeFormats(Device& dev, Fields& fields) {
  UINT support = 0;
  const HRESULT hr = dev.device->CheckFormatSupport(DXGI_FORMAT_B8G8R8A8_UNORM,
                                                    &support);
  const UINT needed = D3D11_FORMAT_SUPPORT_TEXTURE2D |
                      D3D11_FORMAT_SUPPORT_RENDER_TARGET |
                      D3D11_FORMAT_SUPPORT_SHADER_SAMPLE;
  const bool ok = SUCCEEDED(hr) && (support & needed) == needed;
  fields.Add("bgra8_rt_srv", Fmt("%s/%s/mask=0x%X", ok ? "yes" : "no",
                                 Hr(hr).c_str(), support));

  D3D11_FEATURE_DATA_FORMAT_SUPPORT2 support2{};
  support2.InFormat = DXGI_FORMAT_B8G8R8A8_UNORM;
  const HRESULT hr2 = dev.device->CheckFeatureSupport(
      D3D11_FEATURE_FORMAT_SUPPORT2, &support2, sizeof(support2));
  const bool typed_store =
      SUCCEEDED(hr2) &&
      (support2.OutFormatSupport2 & D3D11_FORMAT_SUPPORT2_UAV_TYPED_STORE) != 0;
  fields.Add("bgra8_typed_uav_store",
             Fmt("%s/%s", typed_store ? "yes" : "no", Hr(hr2).c_str()));
}

// --- Shared textures -----------------------------------------------------------

struct SharedTexture {
  Com<ID3D11Texture2D> texture;
  HANDLE handle = nullptr;
  HRESULT create_hr = E_FAIL;
  HRESULT handle_hr = E_FAIL;
};

// Creates a BGRA8 MISC_SHARED texture and reads its legacy (KMT) handle, the
// same way d3d11_interop.cpp shares textures with Flutter.
void MakeShared(ID3D11Device* device, UINT width, UINT height, UINT bind_flags,
                SharedTexture& out) {
  D3D11_TEXTURE2D_DESC desc{};
  desc.Width = width;
  desc.Height = height;
  desc.MipLevels = 1;
  desc.ArraySize = 1;
  desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
  desc.SampleDesc.Count = 1;
  desc.Usage = D3D11_USAGE_DEFAULT;
  desc.BindFlags = bind_flags;
  desc.MiscFlags = D3D11_RESOURCE_MISC_SHARED;
  out.create_hr = device->CreateTexture2D(&desc, nullptr, out.texture.Put());
  if (FAILED(out.create_hr)) return;
  Com<IDXGIResource> resource;
  out.handle_hr = out.texture->QueryInterface(__uuidof(IDXGIResource),
                                              resource.PutVoid());
  if (SUCCEEDED(out.handle_hr)) out.handle_hr = resource->GetSharedHandle(&out.handle);
}

// Shared texture of one size plus its OpenSharedResource on the second device.
void ProbeSharedSize(ID3D11Device* creator, ID3D11Device* opener,
                     const char* shared_key, const char* open_key, UINT width,
                     UINT height, Fields& fields) {
  SharedTexture shared;
  MakeShared(creator, width, height,
             D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE, shared);
  fields.Add(shared_key, Hr(shared.create_hr) + "/" + Hr(shared.handle_hr));
  if (!opener || !shared.handle) {
    fields.Add(open_key, opener ? "skipped" : "no_second_device");
    return;
  }
  Com<ID3D11Texture2D> opened;
  const HRESULT hr = opener->OpenSharedResource(
      shared.handle, __uuidof(ID3D11Texture2D), opened.PutVoid());
  fields.Add(open_key, Hr(hr));
}

void ProbeShared(const DeviceSpec& spec, Device& dev, Fields& fields) {
  Device second;
  const HRESULT second_hr = MakeDevice(spec, second);
  ID3D11Device* opener = SUCCEEDED(second_hr) ? second.device.Get() : nullptr;
  ProbeSharedSize(dev.device.Get(), opener, "shared_4k", "open_shared_4k",
                  k4kWidth, k4kHeight, fields);

  SharedTexture uav;
  MakeShared(dev.device.Get(), k4kWidth, k4kHeight,
             D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE |
                 D3D11_BIND_UNORDERED_ACCESS,
             uav);
  fields.Add("shared_uav_4k", Hr(uav.create_hr) + "/" + Hr(uav.handle_hr));
  uav.texture.Reset();

  ProbeSharedSize(dev.device.Get(), opener, "shared_8k", "open_shared_8k",
                  k8kWidth, k8kHeight, fields);
}

// --- Dimension boundary --------------------------------------------------------

HRESULT CreatePlainTexture(ID3D11Device* device, UINT width, UINT height) {
  D3D11_TEXTURE2D_DESC desc{};
  desc.Width = width;
  desc.Height = height;
  desc.MipLevels = 1;
  desc.ArraySize = 1;
  desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
  desc.SampleDesc.Count = 1;
  desc.Usage = D3D11_USAGE_DEFAULT;
  desc.BindFlags = D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE;
  Com<ID3D11Texture2D> texture;
  return device->CreateTexture2D(&desc, nullptr, texture.Put());
}

void ProbeDimensions(Device& dev, Fields& fields) {
  fields.Add("dim_16384",
             Hr(CreatePlainTexture(dev.device.Get(), kDimLimit, kDimThin)));
  fields.Add("dim_16385",
             Hr(CreatePlainTexture(dev.device.Get(), kDimLimit + 1, kDimThin)));
  fields.Add("req_dim_const",
             Fmt("%u", static_cast<unsigned>(D3D11_REQ_TEXTURE2D_U_OR_V_DIMENSION)));
}

// --- Per-adapter driver --------------------------------------------------------

void PrintLine(const char* host, const AdapterInfo& info, const char* driver,
               const Fields& head, const Fields& body) {
  printf("CAPS host=%s adapter=\"%s\" luid=%s driver=%s%s%s\n", host,
         info.name.c_str(), info.luid.c_str(), driver, head.Text().c_str(),
         body.Text().c_str());
  fflush(stdout);
}

// Probes one adapter (or the WARP driver when `adapter` is null) and prints
// exactly one CAPS line, whatever fails along the way.
void ProbeOne(const char* host, IDXGIAdapter* adapter, D3D_DRIVER_TYPE type,
              const char* driver) {
  DeviceSpec base;
  base.adapter = adapter;
  base.type = type;
  Fields body;
  Device video;
  Device bgra;
  ProbeCreation(base, video, bgra, body);

  // Prefer the VIDEO_SUPPORT device; the BGRA-only device is the fallback.
  Device* test = video.device ? &video : (bgra.device ? &bgra : nullptr);
  const AdapterInfo info =
      adapter ? DescribeAdapter(adapter)
              : DescribeDeviceAdapter(test ? test->device.Get() : nullptr);
  Fields head;
  head.Add("dedicated_vram_mib", Fmt("%llu", info.vram_mib));
  head.Add("software_adapter", info.software ? "1" : "0");
  if (!test) {
    body.Add("test_device", "none");
    PrintLine(host, info, driver, head, body);
    return;
  }
  DeviceSpec test_spec = base;
  test_spec.flags = D3D11_CREATE_DEVICE_BGRA_SUPPORT |
                    (test == &video ? D3D11_CREATE_DEVICE_VIDEO_SUPPORT : 0u);
  body.Add("test_device", test == &video ? "bgra_video" : "bgra");
  ProbeMultithread(*test, body);
  ProbeFence(*test, body);
  ProbeQuery(*test, body);
  ProbeFormats(*test, body);
  ProbeShared(test_spec, *test, body);
  ProbeDimensions(*test, body);
  PrintLine(host, info, driver, head, body);
}

}  // namespace

int main(int argc, char** argv) {
  const char* host = "unknown";
  for (int i = 1; i + 1 < argc; ++i) {
    if (std::strcmp(argv[i], "--host") == 0) host = argv[i + 1];
  }

  Com<IDXGIFactory1> factory;
  const HRESULT factory_hr =
      CreateDXGIFactory1(__uuidof(IDXGIFactory1), factory.PutVoid());
  if (FAILED(factory_hr)) {
    // Still run WARP below; record why no adapter was enumerated.
    printf("CAPS host=%s adapter=\"none\" luid=0000000000000000 driver=none "
           "factory=%s\n",
           host, Hr(factory_hr).c_str());
    fflush(stdout);
  } else {
    Com<IDXGIAdapter1> adapter;
    // Ends on DXGI_ERROR_NOT_FOUND, or on any other enumeration failure.
    for (UINT index = 0; SUCCEEDED(factory->EnumAdapters1(index, adapter.Put()));
         ++index) {
      const AdapterInfo info = DescribeAdapter(adapter.Get());
      ProbeOne(host, adapter.Get(), D3D_DRIVER_TYPE_UNKNOWN,
               info.software ? "basic" : "hardware");
    }
  }
  ProbeOne(host, nullptr, D3D_DRIVER_TYPE_WARP, "warp");
  return 0;
}

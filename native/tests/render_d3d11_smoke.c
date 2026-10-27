// render_d3d11 smoke test: renders one frame of a two-colour lavfi source
// (red top half, blue bottom half) through MPV_RENDER_API_TYPE_D3D11 into a
// host BGRA8 texture, reads it back and checks the pixels. Runs headless on
// a Windows runner without a GPU (the Basic Render Driver / WARP is enough)
// - no window, no swap chain.
//
// What it proves: the D3D11 render API of libmpv renders with the requested
// renderer ("gpu-next" through libplacebo's pl_d3d11, or "gpu" through
// ra_d3d11), draws the right colours, and does not flip the picture. The
// renderer reported by mpv_render_context_get_info() must match the one that
// was asked for; a silent fallback is a failure.
//
// Exit codes: 0 pass, 1 failure, 77 skipped (meson "skip"). The test is only
// skipped when no D3D11 device can be created at all: every Windows machine,
// hosted runners included, has at least the Basic Render Driver, so a skip on
// CI is a failure of the gate (which requires the OK line).
//
// Arguments: [gpu-next|gpu]  the renderer (default gpu-next).

#define COBJMACROS
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <d3d11.h>
#include <dxgi.h>

#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include <mpv/client.h>
#include <mpv/render_d3d11.h>
#include <mpv/render_vk.h> // MPV_RENDER_PARAM_VULKAN_RENDERER (renderer select/report)

#define W 64
#define H 64

// Result codes of the helpers below: they double as the process exit code.
#define RESULT_OK 0
#define RESULT_FAIL 1
#define RESULT_SKIP 77

#define FAIL(...) do { fprintf(stderr, "FAIL: " __VA_ARGS__); fputc('\n', stderr); return RESULT_FAIL; } while (0)
#define HR(x) do { HRESULT hr_ = (x); if (FAILED(hr_)) FAIL("%s -> 0x%08lx", #x, (unsigned long)hr_); } while (0)

// Wait bounds. A frame has to appear well within this, even on WARP, where the
// first shader compilation (D3DCompile of the generated HLSL) is slow.
#define FRAME_TIMEOUT_MS 60000
#define POLL_MS 10

// Pixel checks (BGRA byte order). The source is pure red / pure blue, which
// goes through a YUV round trip and dithering, hence the tolerances.
#define CHANNEL_HIGH 192
#define CHANNEL_LOW 64
#define BLACK_MAX 8
#define MIN_NON_BLACK_RATIO 0.99

// Progress markers go to unbuffered stderr so CI logs show how far we got
// even if a driver aborts the process.
static void step(const char *what) { fprintf(stderr, "[smoke] %s\n", what); }

static double now_ms(void)
{
    LARGE_INTEGER freq, t;
    QueryPerformanceFrequency(&freq);
    QueryPerformanceCounter(&t);
    return (double)t.QuadPart * 1000.0 / (double)freq.QuadPart;
}

typedef struct {
    ID3D11Device *dev;
    ID3D11DeviceContext *ctx;
    char adapter[128];
    const char *how; // which creation attempt succeeded
} Device;

// Creates the host device the way the plugin does: BGRA (+video decoding
// support when the adapter has it) on the hardware adapter, the software
// adapter as the last resort. Never the single-threaded flag, which mpv's
// decoder thread cannot work with.
static bool create_device(Device *d)
{
    static const struct {
        D3D_DRIVER_TYPE type;
        UINT flags;
        const char *name;
    } tries[] = {
        { D3D_DRIVER_TYPE_HARDWARE,
          D3D11_CREATE_DEVICE_BGRA_SUPPORT | D3D11_CREATE_DEVICE_VIDEO_SUPPORT,
          "hardware bgra+video" },
        { D3D_DRIVER_TYPE_HARDWARE, D3D11_CREATE_DEVICE_BGRA_SUPPORT,
          "hardware bgra" },
        { D3D_DRIVER_TYPE_WARP, D3D11_CREATE_DEVICE_BGRA_SUPPORT, "warp bgra" },
    };
    static const D3D_FEATURE_LEVEL levels[] = {
        D3D_FEATURE_LEVEL_11_1,
        D3D_FEATURE_LEVEL_11_0,
    };

    for (size_t i = 0; i < sizeof(tries) / sizeof(tries[0]); i++) {
        ID3D11Device *dev = NULL;
        ID3D11DeviceContext *ctx = NULL;
        HRESULT hr = D3D11CreateDevice(NULL, tries[i].type, NULL, tries[i].flags,
                                       levels, 2, D3D11_SDK_VERSION, &dev,
                                       NULL, &ctx);
        // A runtime without feature level 11_1 rejects the whole list.
        if (hr == E_INVALIDARG)
            hr = D3D11CreateDevice(NULL, tries[i].type, NULL, tries[i].flags,
                                   levels + 1, 1, D3D11_SDK_VERSION, &dev,
                                   NULL, &ctx);
        if (FAILED(hr)) {
            fprintf(stderr, "[smoke] device attempt '%s' failed: 0x%08lx\n",
                    tries[i].name, (unsigned long)hr);
            continue;
        }
        d->dev = dev;
        d->ctx = ctx;
        d->how = tries[i].name;
        snprintf(d->adapter, sizeof(d->adapter), "unknown");
        IDXGIDevice *dxgi = NULL;
        if (SUCCEEDED(ID3D11Device_QueryInterface(dev, &IID_IDXGIDevice, (void **)&dxgi))) {
            IDXGIAdapter *adapter = NULL;
            if (SUCCEEDED(IDXGIDevice_GetAdapter(dxgi, &adapter))) {
                DXGI_ADAPTER_DESC desc;
                if (SUCCEEDED(IDXGIAdapter_GetDesc(adapter, &desc)))
                    WideCharToMultiByte(CP_UTF8, 0, desc.Description, -1,
                                        d->adapter, (int)sizeof(d->adapter),
                                        NULL, NULL);
                IDXGIAdapter_Release(adapter);
            }
            IDXGIDevice_Release(dxgi);
        }
        return true;
    }
    return false;
}

static void release_device(Device *d)
{
    if (d->ctx)
        ID3D11DeviceContext_Release(d->ctx);
    if (d->dev)
        ID3D11Device_Release(d->dev);
    *d = (Device){0};
}

// The pixel at (x, y) of the mapped BGRA readback.
static const uint8_t *pixel(const D3D11_MAPPED_SUBRESOURCE *m, int x, int y)
{
    return (const uint8_t *)m->pData + (size_t)y * m->RowPitch + (size_t)x * 4;
}

// Red top half, blue bottom half, and not black anywhere.
static int check_pixels(const D3D11_MAPPED_SUBRESOURCE *m)
{
    // Sample the middle of each half, away from the seam at H / 2.
    const uint8_t *top = pixel(m, W / 2, H / 8);
    const uint8_t *bottom = pixel(m, W / 2, H - H / 8);
    printf("top pixel BGRA = %u %u %u %u\n", top[0], top[1], top[2], top[3]);
    printf("bottom pixel BGRA = %u %u %u %u\n", bottom[0], bottom[1], bottom[2], bottom[3]);

    int non_black = 0;
    for (int y = 0; y < H; y++) {
        for (int x = 0; x < W; x++) {
            const uint8_t *p = pixel(m, x, y);
            if (p[0] > BLACK_MAX || p[1] > BLACK_MAX || p[2] > BLACK_MAX)
                non_black++;
        }
    }
    double ratio = (double)non_black / (W * H);
    printf("non-black ratio = %.4f\n", ratio);

    if (!(top[2] > CHANNEL_HIGH && top[1] < CHANNEL_LOW && top[0] < CHANNEL_LOW))
        FAIL("top half is not red (BGRA %u %u %u %u)", top[0], top[1], top[2], top[3]);
    if (!(bottom[0] > CHANNEL_HIGH && bottom[1] < CHANNEL_LOW && bottom[2] < CHANNEL_LOW))
        FAIL("bottom half is not blue (BGRA %u %u %u %u)", bottom[0], bottom[1],
             bottom[2], bottom[3]);
    if (ratio < MIN_NON_BLACK_RATIO)
        FAIL("only %.4f of the pixels are non-black", ratio);
    return RESULT_OK;
}

// Everything between device and teardown for one renderer. The render
// context is always freed before mpv, and both before the device.
static int run(const char *renderer)
{
    Device dev = {0};
    step("create device");
    if (!create_device(&dev)) {
        fprintf(stderr, "SKIP: no D3D11 device\n");
        return RESULT_SKIP;
    }
    fprintf(stderr, "[smoke] device %s (%s)\n", dev.adapter, dev.how);

    // --- Render target + readback texture -----------------------------------
    // Same shape as the plugin's shared textures.
    step("create render target");
    D3D11_TEXTURE2D_DESC td = {
        .Width = W,
        .Height = H,
        .MipLevels = 1,
        .ArraySize = 1,
        .Format = DXGI_FORMAT_B8G8R8A8_UNORM,
        .SampleDesc = { 1, 0 },
        .Usage = D3D11_USAGE_DEFAULT,
        .BindFlags = D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE,
        .MiscFlags = D3D11_RESOURCE_MISC_SHARED,
    };
    ID3D11Texture2D *target = NULL;
    HR(ID3D11Device_CreateTexture2D(dev.dev, &td, NULL, &target));

    D3D11_TEXTURE2D_DESC sd = td;
    sd.Usage = D3D11_USAGE_STAGING;
    sd.BindFlags = 0;
    sd.MiscFlags = 0;
    sd.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
    ID3D11Texture2D *staging = NULL;
    HR(ID3D11Device_CreateTexture2D(dev.dev, &sd, NULL, &staging));

    // --- mpv -----------------------------------------------------------------
    step("create mpv");
    mpv_handle *mpv = mpv_create();
    if (!mpv)
        FAIL("mpv_create");
    mpv_set_option_string(mpv, "vo", "libmpv");
    mpv_set_option_string(mpv, "ao", "null");
    mpv_set_option_string(mpv, "config", "no");
    mpv_set_option_string(mpv, "terminal", "yes");
    mpv_set_option_string(mpv, "msg-level", "all=warn,vo=v");
    // The hosted layer only proves the rendering path, not decoding on a GPU.
    mpv_set_option_string(mpv, "hwdec", "no");
    // Keep the user's cache directory out of the test.
    mpv_set_option_string(mpv, "gpu-shader-cache", "no");
    if (mpv_initialize(mpv) < 0)
        FAIL("mpv_initialize");

    mpv_d3d11_init_params init = { .device = dev.dev };
    int advanced = 1; // like the plugin
    mpv_render_param params[] = {
        { MPV_RENDER_PARAM_API_TYPE, (void *)MPV_RENDER_API_TYPE_D3D11 },
        { MPV_RENDER_PARAM_D3D11_INIT_PARAMS, &init },
        { MPV_RENDER_PARAM_VULKAN_RENDERER, (void *)renderer },
        { MPV_RENDER_PARAM_ADVANCED_CONTROL, &advanced },
        { 0 },
    };
    fprintf(stderr, "[smoke] renderer: %s\n", renderer);
    step("create render context");
    mpv_render_context *rc = NULL;
    int err = mpv_render_context_create(&rc, mpv, params);
    if (err < 0)
        FAIL("mpv_render_context_create: %s", mpv_error_string(err));

    // An older libmpv or a silent fallback reports another renderer (or
    // NOT_IMPLEMENTED): both are failures.
    const char *active = NULL;
    mpv_render_param info = { MPV_RENDER_PARAM_VULKAN_RENDERER, &active };
    err = mpv_render_context_get_info(rc, info);
    if (err < 0)
        FAIL("get_info(renderer): %s", mpv_error_string(err));
    if (!active || strcmp(active, renderer) != 0)
        FAIL("renderer mismatch requested=%s active=%s", renderer, active ? active : "(null)");
    fprintf(stderr, "[smoke] active renderer: %s\n", active);

    // One source: 64x32 red above 64x32 blue. Multi-stream lavfi graphs need
    // output labels; the single video output is [out0].
    const char *cmd[] = {
        "loadfile",
        "av://lavfi:color=c=red:s=64x32:r=30[top];"
        "color=c=blue:s=64x32:r=30[bottom];[top][bottom]vstack[out0]",
        NULL,
    };
    if (mpv_command(mpv, cmd) < 0)
        FAIL("loadfile");

    step("wait for frame");
    bool have_frame = false;
    double start = now_ms();
    while (!have_frame && now_ms() - start < FRAME_TIMEOUT_MS) {
        mpv_event *ev;
        while ((ev = mpv_wait_event(mpv, 0))->event_id != MPV_EVENT_NONE) {
            if (ev->event_id == MPV_EVENT_END_FILE)
                FAIL("playback ended before a frame was rendered");
        }
        have_frame = mpv_render_context_update(rc) & MPV_RENDER_UPDATE_FRAME;
        if (!have_frame)
            Sleep(POLL_MS);
    }
    if (!have_frame)
        FAIL("no frame within %d s", FRAME_TIMEOUT_MS / 1000);

    // A redraw must not wait for a vsync report.
    mpv_d3d11_fbo fbo = { .tex = target };
    int no_block = 0;
    mpv_render_param rparams[] = {
        { MPV_RENDER_PARAM_D3D11_FBO, &fbo },
        { MPV_RENDER_PARAM_BLOCK_FOR_TARGET_TIME, &no_block },
        { 0 },
    };
    step("render");
    err = mpv_render_context_render(rc, rparams);
    if (err < 0)
        FAIL("mpv_render_context_render: %s", mpv_error_string(err));
    mpv_render_context_report_swap(rc);

    // --- Read back -----------------------------------------------------------
    step("read back");
    ID3D11DeviceContext_CopyResource(dev.ctx, (ID3D11Resource *)staging,
                                     (ID3D11Resource *)target);
    D3D11_MAPPED_SUBRESOURCE mapped;
    HR(ID3D11DeviceContext_Map(dev.ctx, (ID3D11Resource *)staging, 0,
                               D3D11_MAP_READ, 0, &mapped));
    int result = check_pixels(&mapped);
    ID3D11DeviceContext_Unmap(dev.ctx, (ID3D11Resource *)staging, 0);

    step("teardown");
    // The render context must go before mpv, and both before the device.
    mpv_render_context_free(rc);
    mpv_terminate_destroy(mpv);
    ID3D11Texture2D_Release(staging);
    ID3D11Texture2D_Release(target);
    release_device(&dev);
    return result;
}

int main(int argc, char **argv)
{
    setvbuf(stdout, NULL, _IONBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);

    const char *renderer = "gpu-next";
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "gpu-next") == 0 || strcmp(argv[i], "gpu") == 0)
            renderer = argv[i];
        else
            FAIL("unknown argument '%s'", argv[i]);
    }

    int result = run(renderer);
    if (result == RESULT_OK)
        printf("PASS\n");
    return result;
}

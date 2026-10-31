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
// Arguments: [gpu-next|gpu] [--cache-dir=<dir>]
//   renderer     the renderer to use (default gpu-next).
//   --cache-dir  persistent shader cache test (gpu-next only): mpv and the
//                device are created twice in a row on the same cache
//                directory. The first run must write at least one shader_*
//                file (the compiled DXBC); the second must write no new file
//                and log at least one cache_load_obj with a non-zero size.
//                D3DCompile is slow, so a persistent cache that does not hit
//                is a stutter on every start.

#define COBJMACROS
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <d3d11.h>
#include <dxgi.h>

#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
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

// Shader cache files are shader_<16 hex digits> (vo_gpu_next.c).
#define CACHE_FILE_PATTERN "shader_*"
#define MAX_CACHE_FILES 512
#define PATH_MAX_LEN 1024

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
// context is always freed before mpv, and both before the device. With a
// cache_dir the persistent shader cache is on and mpv logs at debug level to
// log_path; otherwise the cache is off. first_frame_ms receives the time from
// loadfile to the first frame being ready (informational).
static int run(const char *renderer, const char *cache_dir,
               const char *log_path, double *first_frame_ms)
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
    if (cache_dir) {
        mpv_set_option_string(mpv, "gpu-shader-cache", "yes");
        mpv_set_option_string(mpv, "gpu-shader-cache-dir", cache_dir);
        // The log file is written at debug level whatever msg-level says,
        // without the event queue's bound: it is where cache_load_obj shows.
        mpv_set_option_string(mpv, "log-file", log_path);
    } else {
        // Keep the user's cache directory out of the test.
        mpv_set_option_string(mpv, "gpu-shader-cache", "no");
    }
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
    double start = now_ms();
    if (mpv_command(mpv, cmd) < 0)
        FAIL("loadfile");

    step("wait for frame");
    bool have_frame = false;
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
    *first_frame_ms = now_ms() - start;

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

// --- Persistent shader cache ---------------------------------------------------

typedef struct {
    char names[MAX_CACHE_FILES][64];
    int count;
} FileList;

// Joins dir and name with a backslash into out (PATH_MAX_LEN bytes).
static bool join_path(char *out, const char *dir, const char *name)
{
    int n = snprintf(out, PATH_MAX_LEN, "%s\\%s", dir, name);
    return n > 0 && n < PATH_MAX_LEN;
}

// Lists the plain files of dir matching pattern, in the file system's order
// (sorted on NTFS, so two listings of the same set compare equal).
static bool list_files(const char *dir, const char *pattern, FileList *out)
{
    char glob[PATH_MAX_LEN];
    out->count = 0;
    if (!join_path(glob, dir, pattern))
        return false;
    WIN32_FIND_DATAA fd;
    HANDLE h = FindFirstFileA(glob, &fd);
    if (h == INVALID_HANDLE_VALUE)
        return GetLastError() == ERROR_FILE_NOT_FOUND;
    do {
        if ((fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) ||
            out->count >= MAX_CACHE_FILES)
            continue;
        snprintf(out->names[out->count++], sizeof(out->names[0]), "%s",
                 fd.cFileName);
    } while (FindNextFileA(h, &fd));
    FindClose(h);
    return true;
}

// Creates dir if needed and removes the plain files in it, so the first run
// starts without a cache.
static bool reset_cache_dir(const char *dir)
{
    if (!CreateDirectoryA(dir, NULL) && GetLastError() != ERROR_ALREADY_EXISTS)
        return false;
    static FileList files; // large; keep off the stack
    if (!list_files(dir, "*", &files))
        return false;
    for (int i = 0; i < files.count; i++) {
        char path[PATH_MAX_LEN];
        if (!join_path(path, dir, files.names[i]) || !DeleteFileA(path))
            return false;
    }
    return true;
}

// Number of cache_load_obj lines in the debug log that carry a non-zero
// size: those are the shaders read back from the cache. Returns -1 when the
// log cannot be read.
static int count_cache_hits(const char *log_path)
{
    FILE *f = fopen(log_path, "rb");
    if (!f)
        return -1;
    int hits = 0;
    char line[2048];
    while (fgets(line, sizeof(line), f)) {
        if (!strstr(line, "cache_load_obj"))
            continue;
        const char *size = strstr(line, "size(");
        if (size && atol(size + 5) > 0)
            hits++;
    }
    fclose(f);
    return hits;
}

static bool same_files(const FileList *a, const FileList *b)
{
    if (a->count != b->count)
        return false;
    for (int i = 0; i < a->count; i++) {
        if (strcmp(a->names[i], b->names[i]) != 0)
            return false;
    }
    return true;
}

// Two complete runs (new device, new mpv) on one cache directory.
static int run_cache_test(const char *renderer, const char *cache_dir)
{
    if (strcmp(renderer, "gpu-next") != 0)
        FAIL("--cache-dir needs the gpu-next renderer");
    if (!reset_cache_dir(cache_dir))
        FAIL("cannot prepare cache directory '%s'", cache_dir);

    char log1[PATH_MAX_LEN], log2[PATH_MAX_LEN];
    snprintf(log1, sizeof(log1), "%s-pass1.log", cache_dir);
    snprintf(log2, sizeof(log2), "%s-pass2.log", cache_dir);

    double ms1 = 0, ms2 = 0;
    step("cache pass 1 (cold)");
    int result = run(renderer, cache_dir, log1, &ms1);
    if (result != RESULT_OK)
        return result;

    static FileList after1, after2; // large; keep off the stack
    if (!list_files(cache_dir, CACHE_FILE_PATTERN, &after1))
        FAIL("cannot list '%s'", cache_dir);
    printf("pass 1 wrote %d cache files\n", after1.count);
    if (after1.count < 1)
        FAIL("no cache files written");

    step("cache pass 2 (warm)");
    result = run(renderer, cache_dir, log2, &ms2);
    if (result != RESULT_OK)
        return result;

    if (!list_files(cache_dir, CACHE_FILE_PATTERN, &after2))
        FAIL("cannot list '%s'", cache_dir);
    printf("pass 2 left %d cache files\n", after2.count);
    if (!same_files(&after1, &after2))
        FAIL("pass 2 wrote new cache entries (%d -> %d files)", after1.count, after2.count);

    int hits = count_cache_hits(log2);
    printf("pass 2 cache hits (cache_load_obj, size > 0) = %d\n", hits);
    if (hits < 0)
        FAIL("cannot read the pass 2 log '%s'", log2);
    if (hits < 1)
        FAIL("no cache hits logged");

    // Informational only: the point of the cache is the second start.
    printf("first frame: cold %.0f ms, warm %.0f ms\n", ms1, ms2);
    return RESULT_OK;
}

int main(int argc, char **argv)
{
    setvbuf(stdout, NULL, _IONBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);

    const char *renderer = "gpu-next";
    const char *cache_dir = NULL;
    static const char cache_arg[] = "--cache-dir=";
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "gpu-next") == 0 || strcmp(argv[i], "gpu") == 0)
            renderer = argv[i];
        else if (strncmp(argv[i], cache_arg, sizeof(cache_arg) - 1) == 0)
            cache_dir = argv[i] + sizeof(cache_arg) - 1;
        else
            FAIL("unknown argument '%s'", argv[i]);
    }
    if (cache_dir && !cache_dir[0])
        FAIL("empty --cache-dir");

    double first_frame_ms = 0;
    int result = cache_dir ? run_cache_test(renderer, cache_dir)
                           : run(renderer, NULL, NULL, &first_frame_ms);
    if (result == RESULT_OK)
        printf("PASS\n");
    return result;
}

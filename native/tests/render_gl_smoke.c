// render_gl smoke test: renders one frame of a solid red lavfi source through
// the upstream MPV_RENDER_API_TYPE_OPENGL into a host FBO, reads it back and
// checks the pixel colour. The GL context is a standalone, surfaceless EGL
// context (EGL_MESA_platform_surfaceless, Mesa llvmpipe works): no window, no
// X server, no swapchain.
//
// It also proves which renderer serves the GL render API: mpv reports it
// through mpv_render_context_get_info(MPV_RENDER_PARAM_VULKAN_RENDERER), and
// it must be "gpu" (the GL render API is never served by gpu-next).
//
// Exit codes: 0 pass, 1 failure, 77 skipped (no EGL surfaceless display, or
// no context of the requested API; meson "skip"). Every skip prints one
// "RENDER_GL SKIP: <reason>" line first, so CI can tell a skip from a pass.
// Argument: the API, "gl" (desktop OpenGL, the default) or "gles" (OpenGL ES 3).
//
// FLIP_Y is 0 here: the test only reads one solid-colour pixel, so image
// orientation is not examined (the Linux backend's own spike decides it).

#define _POSIX_C_SOURCE 200809L
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include <epoxy/egl.h>
#include <epoxy/gl.h>

#include <mpv/client.h>
#include <mpv/render_gl.h>
#include <mpv/render_vk.h>

#define W 64
#define H 64
#define FAIL(...) do { fprintf(stderr, "FAIL: " __VA_ARGS__); fputc('\n', stderr); return 1; } while (0)
#define SKIP(...) do { fputs("RENDER_GL SKIP: ", stdout); printf(__VA_ARGS__); fputc('\n', stdout); return 77; } while (0)

// Progress markers go to unbuffered stderr so CI logs show how far we got
// even if a driver aborts the process.
static void step(const char *what) { fprintf(stderr, "[gl-smoke] %s\n", what); }

static void sleep_ms(int ms)
{
    struct timespec ts = { .tv_sec = ms / 1000, .tv_nsec = (ms % 1000) * 1000000L };
    nanosleep(&ts, NULL);
}

// True if `name` is one of the space-separated tokens of an EGL extension
// string (a plain strstr would also match prefixes of longer names).
static bool has_ext(const char *list, const char *name)
{
    if (!list)
        return false;
    size_t n = strlen(name);
    for (const char *p = list; (p = strstr(p, name)); p += n) {
        bool start = p == list || p[-1] == ' ';
        bool end = p[n] == '\0' || p[n] == ' ';
        if (start && end)
            return true;
    }
    return false;
}

// mpv resolves every GL function through this callback and links no GL
// library itself. The function pointer goes through memcpy because ISO C has
// no function-pointer to void* conversion (-Wpedantic, werror).
static void *get_proc_address(void *ctx, const char *name)
{
    (void)ctx;
    void (*fn)(void) = eglGetProcAddress(name);
    void *p;
    memcpy(&p, &fn, sizeof p);
    return p;
}

int main(int argc, char **argv)
{
    setvbuf(stdout, NULL, _IONBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);

    const char *api = argc > 1 ? argv[1] : "gl";
    bool gles;
    if (strcmp(api, "gl") == 0)
        gles = false;
    else if (strcmp(api, "gles") == 0)
        gles = true;
    else
        FAIL("unknown API '%s' (expected gl or gles)", api);

    // --- EGL: surfaceless display ----------------------------------------------
    step("create EGL surfaceless display");
    const char *client_ext = eglQueryString(EGL_NO_DISPLAY, EGL_EXTENSIONS);
    if (!has_ext(client_ext, "EGL_EXT_platform_base") ||
        !has_ext(client_ext, "EGL_MESA_platform_surfaceless"))
        SKIP("EGL_MESA_platform_surfaceless not available");
    EGLDisplay dpy = eglGetPlatformDisplayEXT(EGL_PLATFORM_SURFACELESS_MESA,
                                              EGL_DEFAULT_DISPLAY, NULL);
    if (dpy == EGL_NO_DISPLAY)
        SKIP("no surfaceless EGL display");
    EGLint major, minor;
    if (!eglInitialize(dpy, &major, &minor))
        SKIP("eglInitialize failed (0x%x)", (unsigned)eglGetError());
    const char *dpy_ext = eglQueryString(dpy, EGL_EXTENSIONS);
    if (!has_ext(dpy_ext, "EGL_KHR_surfaceless_context"))
        SKIP("EGL_KHR_surfaceless_context not available");

    if (!eglBindAPI(gles ? EGL_OPENGL_ES_API : EGL_OPENGL_API))
        SKIP("eglBindAPI(%s) failed", gles ? "OpenGL ES" : "OpenGL");

    // --- EGL: config and context -------------------------------------------------
    // Prefer a config-less context (EGL_KHR_no_config_context); otherwise
    // pick a config for the API. EGL_SURFACE_TYPE is don't-care: surfaceless
    // displays do not offer window-capable configs.
    step("create EGL context");
    EGLConfig cfg = (EGLConfig)0;
    if (!has_ext(dpy_ext, "EGL_KHR_no_config_context")) {
        const EGLint cattr[] = {
            EGL_RENDERABLE_TYPE, gles ? EGL_OPENGL_ES3_BIT : EGL_OPENGL_BIT,
            EGL_SURFACE_TYPE, EGL_DONT_CARE,
            EGL_NONE,
        };
        EGLint ncfg = 0;
        if (!eglChooseConfig(dpy, cattr, &cfg, 1, &ncfg) || ncfg < 1)
            SKIP("no EGL config for %s", api);
    }
    EGLContext ctx = EGL_NO_CONTEXT;
    if (gles) {
        const EGLint attr[] = { EGL_CONTEXT_MAJOR_VERSION, 3, EGL_NONE };
        ctx = eglCreateContext(dpy, cfg, EGL_NO_CONTEXT, attr);
    } else {
        // 3.3 core first (what a modern host asks for); the default version
        // (compatibility) when the driver refuses.
        const EGLint attr[] = {
            EGL_CONTEXT_MAJOR_VERSION, 3, EGL_CONTEXT_MINOR_VERSION, 3,
            EGL_CONTEXT_OPENGL_PROFILE_MASK, EGL_CONTEXT_OPENGL_CORE_PROFILE_BIT,
            EGL_NONE,
        };
        ctx = eglCreateContext(dpy, cfg, EGL_NO_CONTEXT, attr);
        if (ctx == EGL_NO_CONTEXT) {
            const EGLint plain[] = { EGL_NONE };
            ctx = eglCreateContext(dpy, cfg, EGL_NO_CONTEXT, plain);
        }
    }
    if (ctx == EGL_NO_CONTEXT)
        SKIP("no %s context (0x%x)", api, (unsigned)eglGetError());
    if (!eglMakeCurrent(dpy, EGL_NO_SURFACE, EGL_NO_SURFACE, ctx))
        SKIP("surfaceless eglMakeCurrent failed (0x%x)", (unsigned)eglGetError());

    // --- Host render target: a 64x64 RGBA8 texture behind an FBO -----------------
    step("create render target");
    GLuint tex = 0, fbo = 0;
    glGenTextures(1, &tex);
    glBindTexture(GL_TEXTURE_2D, tex);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, W, H, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glGenFramebuffers(1, &fbo);
    glBindFramebuffer(GL_FRAMEBUFFER, fbo);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, tex, 0);
    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE)
        FAIL("host FBO is not complete");
    char gl_version[128], gl_renderer[128];
    snprintf(gl_version, sizeof gl_version, "%s", (const char *)glGetString(GL_VERSION));
    snprintf(gl_renderer, sizeof gl_renderer, "%s", (const char *)glGetString(GL_RENDERER));
    fprintf(stderr, "[gl-smoke] api=%s GL_VERSION=\"%s\" GL_RENDERER=\"%s\"\n",
            api, gl_version, gl_renderer);

    // --- mpv ---------------------------------------------------------------------
    step("create mpv");
    mpv_handle *mpv = mpv_create();
    if (!mpv)
        FAIL("mpv_create");
    mpv_set_option_string(mpv, "vo", "libmpv");
    mpv_set_option_string(mpv, "ao", "null");
    mpv_set_option_string(mpv, "config", "no");
    mpv_set_option_string(mpv, "terminal", "yes");
    mpv_set_option_string(mpv, "msg-level", "all=warn,vo=v");
    if (mpv_initialize(mpv) < 0)
        FAIL("mpv_initialize");

    mpv_opengl_init_params glp = { .get_proc_address = get_proc_address };
    int advanced = 1;  // same promise the plugin makes (update + render discipline)
    mpv_render_param params[] = {
        { MPV_RENDER_PARAM_API_TYPE, (void *)MPV_RENDER_API_TYPE_OPENGL },
        { MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, &glp },
        { MPV_RENDER_PARAM_ADVANCED_CONTROL, &advanced },
        { 0 },
    };
    step("create render context");
    mpv_render_context *rc;
    int err = mpv_render_context_create(&rc, mpv, params);
    if (err < 0)
        FAIL("mpv_render_context_create: %s", mpv_error_string(err));

    // The GL render API is served by vo_gpu's renderer, never gpu-next.
    step("query active renderer");
    const char *renderer = NULL;
    mpv_render_param info = { MPV_RENDER_PARAM_VULKAN_RENDERER, &renderer };
    err = mpv_render_context_get_info(rc, info);
    if (err < 0)
        FAIL("get_info(VULKAN_RENDERER): %s", mpv_error_string(err));
    if (!renderer || strcmp(renderer, "gpu") != 0)
        FAIL("active renderer is '%s', expected 'gpu'", renderer ? renderer : "(null)");

    const char *cmd[] = { "loadfile", "av://lavfi:color=c=red:s=64x64:r=30", NULL };
    if (mpv_command(mpv, cmd) < 0)
        FAIL("loadfile");

    step("wait for frame");
    // Wait (<= 10 s) until mpv has a frame ready to render.
    bool have_frame = false;
    for (int i = 0; i < 1000 && !have_frame; i++) {
        mpv_event *ev;
        while ((ev = mpv_wait_event(mpv, 0))->event_id != MPV_EVENT_NONE) {
            if (ev->event_id == MPV_EVENT_END_FILE)
                FAIL("playback ended before a frame was rendered");
        }
        have_frame = mpv_render_context_update(rc) & MPV_RENDER_UPDATE_FRAME;
        if (!have_frame)
            sleep_ms(10);
    }
    if (!have_frame)
        FAIL("no frame within 10 s");

    step("render");
    mpv_opengl_fbo target = { .fbo = (int)fbo, .w = W, .h = H, .internal_format = GL_RGBA8 };
    int flip_y = 0;
    int no_block = 0;  // a smoke render must not wait for a vsync report
    mpv_render_param rparams[] = {
        { MPV_RENDER_PARAM_OPENGL_FBO, &target },
        { MPV_RENDER_PARAM_FLIP_Y, &flip_y },
        { MPV_RENDER_PARAM_BLOCK_FOR_TARGET_TIME, &no_block },
        { 0 },
    };
    err = mpv_render_context_render(rc, rparams);
    if (err < 0)
        FAIL("mpv_render_context_render: %s", mpv_error_string(err));
    glFinish();

    // --- Read the centre pixel back -----------------------------------------------
    step("read back");
    unsigned char px[4] = { 0, 0, 0, 0 };
    glBindFramebuffer(GL_FRAMEBUFFER, fbo);
    glReadPixels(W / 2, H / 2, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, px);
    GLenum gl_err = glGetError();
    if (gl_err != GL_NO_ERROR)
        FAIL("glReadPixels: GL error 0x%x", (unsigned)gl_err);

    // --- Teardown (context current: mpv frees its GL objects here) ---------------
    step("teardown");
    mpv_render_context_free(rc);
    mpv_terminate_destroy(mpv);
    glDeleteFramebuffers(1, &fbo);
    glDeleteTextures(1, &tex);
    eglMakeCurrent(dpy, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    eglDestroyContext(dpy, ctx);
    eglTerminate(dpy);

    // Solid red: R high, G and B low. Black (nothing rendered) fails.
    if (!(px[0] > 200 && px[1] < 60 && px[2] < 60))
        FAIL("rendered pixel is not red: %u,%u,%u", px[0], px[1], px[2]);
    printf("RENDER_GL ok api=%s renderer=%s gl_version=\"%s\" gl_renderer=\"%s\" pixel=%u,%u,%u\n",
           api, renderer, gl_version, gl_renderer, px[0], px[1], px[2]);
    return 0;
}

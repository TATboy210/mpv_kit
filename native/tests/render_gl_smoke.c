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
// The render part reads one solid-colour pixel with FLIP_Y 0 (orientation is
// not examined there). It is followed by a HANDOFF phase that replays what the
// Linux OpenGLBackend does per frame, on the same EGL display:
//   mpv renders into a private texture P (FBO_P)  ->  glBlitFramebuffer into a
//   separate export texture E (FBO_E)  ->  an EGLImage created from E only  ->
//   EGL fence wait on the producer  ->  a second thread with a GLES 2 context
//   that shares no objects with the producer (the same kind of context the
//   Flutter engine owns) imports the image with glEGLImageTargetTexture2DOES
//   and reads it back.
// The EGLImage is deliberately never created from P, the texture mpv renders
// into: on some Mesa drivers (media-kit#1463) an EGLImage taken from the
// render target reads back black, a blit into a plain export texture avoids it.
// The source is 64x32 red stacked on 64x32 blue; every round (FLIP_Y 0 and 1)
// prints which colour sits in texture row 0 (the first row in memory), which
// is mpv's side of the FLIP_Y decision.
// In this version the handoff results are only REPORTED (one "RENDER_GL
// handoff" line per round); the exit code still reflects the render part, a
// crash or a hang. Which variants become hard assertions is decided from CI
// evidence (evidence/spike-gl.txt).

#ifndef _GNU_SOURCE
#define _GNU_SOURCE  // pthread_timedjoin_np: the consumer join must be bounded
#endif
#include <stdbool.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
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

// --- Handoff phase ---------------------------------------------------------------
// Time limits: the producer waits at most one second on the EGL fence and the
// consumer thread is joined with a 10 s ceiling; the thread itself makes no
// blocking calls.
#define FENCE_TIMEOUT_NS 1000000000ULL
#define JOIN_TIMEOUT_S 10
// Rounds (100 ms apart) allowed for the stacked source to reach the FBO after
// "loadfile replace"; mpv may still deliver one more frame of the old source.
#define SOURCE_RETRIES 50

// Everything the producer side needs for one round.
typedef struct {
    EGLDisplay dpy;
    EGLContext ctx;
    const char *dpy_ext;
    const char *api;
    mpv_render_context *rc;
    GLuint fbo_p;   // private render target mpv draws into (FBO of texture P)
    GLuint fbo_e;   // FBO of the export texture E
    GLuint tex_e;   // export texture: the only source of EGLImages
} handoff_env;

// What the consumer thread is given and what it reports back. `image` is
// EGL_NO_IMAGE_KHR for the capability probe (no import attempted).
typedef struct {
    EGLDisplay dpy;
    EGLImageKHR image;
    bool oes_egl_image;  // GL_OES_EGL_image present in the consumer's context
    bool read;           // row0 / last below are valid
    char import_status[64];
    unsigned char row0[4], last[4];
} consumer_job;

static const char *egl_error_name(EGLint e)
{
    switch (e) {
    case EGL_SUCCESS: return "EGL_SUCCESS";
    case EGL_BAD_ACCESS: return "EGL_BAD_ACCESS";
    case EGL_BAD_ALLOC: return "EGL_BAD_ALLOC";
    case EGL_BAD_ATTRIBUTE: return "EGL_BAD_ATTRIBUTE";
    case EGL_BAD_CONTEXT: return "EGL_BAD_CONTEXT";
    case EGL_BAD_CONFIG: return "EGL_BAD_CONFIG";
    case EGL_BAD_DISPLAY: return "EGL_BAD_DISPLAY";
    case EGL_BAD_MATCH: return "EGL_BAD_MATCH";
    case EGL_BAD_PARAMETER: return "EGL_BAD_PARAMETER";
    case EGL_BAD_SURFACE: return "EGL_BAD_SURFACE";
    case EGL_BAD_NATIVE_PIXMAP: return "EGL_BAD_NATIVE_PIXMAP";
    case EGL_NOT_INITIALIZED: return "EGL_NOT_INITIALIZED";
    default: return "EGL_OTHER";
    }
}

// red/blue: dominant channel > 160 and the other two < 90; black: all < 16.
static const char *classify(const unsigned char *p)
{
    if (p[0] > 160 && p[1] < 90 && p[2] < 90)
        return "red";
    if (p[2] > 160 && p[0] < 90 && p[1] < 90)
        return "blue";
    if (p[0] < 16 && p[1] < 16 && p[2] < 16)
        return "black";
    return "other";
}

// Reads texture row 0 (the first row in memory = glReadPixels y 0) and the
// last row, at the horizontal centre, of the given framebuffer.
static void read_rows(GLuint fbo, unsigned char row0[4], unsigned char last[4])
{
    memset(row0, 0, 4);
    memset(last, 0, 4);
    glBindFramebuffer(GL_FRAMEBUFFER, fbo);
    glReadPixels(W / 2, 0, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, row0);
    glReadPixels(W / 2, H - 1, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, last);
}

// Consumer thread (stands in for the Flutter raster thread): its own GLES 2
// context, no share group with the producer, surfaceless.
static void *consumer_main(void *arg)
{
    consumer_job *c = arg;
    EGLContext ctx = EGL_NO_CONTEXT;
    EGLConfig cfg = (EGLConfig)0;
    EGLint ncfg = 0;
    GLuint tex = 0, fbo = 0;
    GLenum glerr, fbo_status;
    const EGLint cattr[] = {
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT, EGL_SURFACE_TYPE, EGL_DONT_CARE, EGL_NONE,
    };
    // EGL_CONTEXT_CLIENT_VERSION 2 is what the Flutter engine asks for.
    const EGLint attr[] = { EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE };

    snprintf(c->import_status, sizeof c->import_status, "failed:setup");
    // eglBindAPI is per thread: the main thread's choice does not carry over.
    if (!eglBindAPI(EGL_OPENGL_ES_API)) {
        snprintf(c->import_status, sizeof c->import_status, "failed:bindapi");
        goto done;
    }
    if (!eglChooseConfig(c->dpy, cattr, &cfg, 1, &ncfg) || ncfg < 1) {
        snprintf(c->import_status, sizeof c->import_status, "failed:no-gles2-config");
        goto done;
    }
    // EGL_NO_CONTEXT as share context: nothing is shared with the producer.
    ctx = eglCreateContext(c->dpy, cfg, EGL_NO_CONTEXT, attr);
    if (ctx == EGL_NO_CONTEXT ||
        !eglMakeCurrent(c->dpy, EGL_NO_SURFACE, EGL_NO_SURFACE, ctx)) {
        snprintf(c->import_status, sizeof c->import_status, "failed:context-%s",
                 egl_error_name(eglGetError()));
        goto done;
    }
    // epoxy aborts on a missing entry point, so test the extension first.
    c->oes_egl_image = epoxy_has_gl_extension("GL_OES_EGL_image");
    if (!c->oes_egl_image) {
        snprintf(c->import_status, sizeof c->import_status, "failed:no-GL_OES_EGL_image");
        goto done;
    }
    if (c->image == EGL_NO_IMAGE_KHR) {
        snprintf(c->import_status, sizeof c->import_status, "probe");
        goto done;
    }
    while (glGetError() != GL_NO_ERROR) {}
    glGenTextures(1, &tex);
    glBindTexture(GL_TEXTURE_2D, tex);
    glEGLImageTargetTexture2DOES(GL_TEXTURE_2D, (GLeglImageOES)c->image);
    glerr = glGetError();
    if (glerr != GL_NO_ERROR) {
        snprintf(c->import_status, sizeof c->import_status, "failed:glerr-0x%x", (unsigned)glerr);
        goto done;
    }
    glGenFramebuffers(1, &fbo);
    glBindFramebuffer(GL_FRAMEBUFFER, fbo);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, tex, 0);
    fbo_status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
    if (fbo_status != GL_FRAMEBUFFER_COMPLETE) {
        snprintf(c->import_status, sizeof c->import_status, "failed:fbo-status-0x%x",
                 (unsigned)fbo_status);
        goto done;
    }
    read_rows(fbo, c->row0, c->last);
    c->read = true;
    snprintf(c->import_status, sizeof c->import_status, "ok");
done:
    if (ctx != EGL_NO_CONTEXT) {
        // Objects are deleted while the context is still current.
        if (fbo)
            glDeleteFramebuffers(1, &fbo);
        if (tex)
            glDeleteTextures(1, &tex);
        eglMakeCurrent(c->dpy, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
        eglDestroyContext(c->dpy, ctx);
    }
    eglReleaseThread();
    return NULL;
}

// Runs the consumer on its own thread and joins it with a ceiling. Returns
// false when the thread did not finish in time (a hang is a failure).
static bool run_consumer(consumer_job *c)
{
    pthread_t th;
    if (pthread_create(&th, NULL, consumer_main, c) != 0) {
        snprintf(c->import_status, sizeof c->import_status, "failed:pthread_create");
        return true;
    }
    struct timespec dl;
    clock_gettime(CLOCK_REALTIME, &dl);
    dl.tv_sec += JOIN_TIMEOUT_S;
    return pthread_timedjoin_np(th, NULL, &dl) == 0;
}

// Prints the EGL extension list and whether a GLES 2 consumer can import
// EGLImages; both are inputs to the spike decision. False if the probe hung.
static bool print_extensions(const handoff_env *e, const char *gl_version)
{
    static const char *const wanted[] = {
        "EGL_KHR_surfaceless_context", "EGL_KHR_image_base",
        "EGL_KHR_gl_texture_2D_image", "EGL_KHR_fence_sync", "EGL_KHR_wait_sync",
        "EGL_EXT_create_context_robustness",
    };
    char list[512] = "";
    for (size_t i = 0; i < sizeof wanted / sizeof wanted[0]; i++) {
        if (!has_ext(e->dpy_ext, wanted[i]))
            continue;
        size_t used = strlen(list);
        snprintf(list + used, sizeof list - used, "%s%s", used ? "," : "", wanted[i]);
    }
    consumer_job probe = { .dpy = e->dpy, .image = EGL_NO_IMAGE_KHR };
    bool joined = run_consumer(&probe);
    printf("RENDER_GL ext api=%s egl=\"%s\" consumer_oes_egl_image=%s gl_version=\"%s\"\n",
           e->api, list, probe.oes_egl_image ? "yes" : "no", gl_version);
    return joined;
}

// Waits (<= 10 s) for mpv to report a new frame; false on timeout or error.
static bool wait_for_new_frame(mpv_handle *mpv, mpv_render_context *rc)
{
    for (int i = 0; i < 1000; i++) {
        mpv_event *ev;
        while ((ev = mpv_wait_event(mpv, 0))->event_id != MPV_EVENT_NONE) {
            // Replacing the file ends the old one with reason "stop"; only
            // an error counts as a failure.
            if (ev->event_id == MPV_EVENT_END_FILE &&
                ((mpv_event_end_file *)ev->data)->reason == MPV_END_FILE_REASON_ERROR)
                return false;
        }
        if (mpv_render_context_update(rc) & MPV_RENDER_UPDATE_FRAME)
            return true;
        sleep_ms(10);
    }
    return false;
}

// mpv renders into the private texture P with the given FLIP_Y.
static int render_into_p(const handoff_env *e, int flip_y)
{
    mpv_opengl_fbo target = { .fbo = (int)e->fbo_p, .w = W, .h = H, .internal_format = GL_RGBA8 };
    int no_block = 0;  // a smoke render must not wait for a vsync report
    mpv_render_param rparams[] = {
        { MPV_RENDER_PARAM_OPENGL_FBO, &target },
        { MPV_RENDER_PARAM_FLIP_Y, &flip_y },
        { MPV_RENDER_PARAM_BLOCK_FOR_TARGET_TIME, &no_block },
        { 0 },
    };
    return mpv_render_context_render(e->rc, rparams);
}

// Renders until P holds both a red and a blue end (the stacked source has
// replaced the solid red one), or the retries run out; `p0` / `pl` are P's
// row 0 / last row. False only if mpv_render_context_render failed.
static bool render_stacked(const handoff_env *e, int flip_y, unsigned char p0[4], unsigned char pl[4])
{
    for (int i = 0; i < SOURCE_RETRIES; i++) {
        mpv_render_context_update(e->rc);  // also clears the pending-frame flag
        if (render_into_p(e, flip_y) < 0)
            return false;
        glFinish();
        read_rows(e->fbo_p, p0, pl);
        const char *a = classify(p0), *b = classify(pl);
        if ((!strcmp(a, "red") && !strcmp(b, "blue")) || (!strcmp(a, "blue") && !strcmp(b, "red")))
            return true;
        sleep_ms(100);
    }
    return true;  // the report line shows whatever P holds
}

// Blit P -> E, EGLImage from E only, fence. Fills the image and sync status
// strings; returns the image (EGL_NO_IMAGE_KHR if it could not be made).
static EGLImageKHR export_image(const handoff_env *e, char *image_st, char *sync_st, size_t n)
{
    // mpv leaves arbitrary GL state behind; the blit must not be scissored.
    glDisable(GL_SCISSOR_TEST);
    glBindFramebuffer(GL_READ_FRAMEBUFFER, e->fbo_p);
    glBindFramebuffer(GL_DRAW_FRAMEBUFFER, e->fbo_e);
    glBlitFramebuffer(0, 0, W, H, 0, 0, W, H, GL_COLOR_BUFFER_BIT, GL_NEAREST);
    glBindFramebuffer(GL_FRAMEBUFFER, 0);

    snprintf(image_st, n, "failed:unsupported");
    snprintf(sync_st, n, "failed:unsupported");
    EGLImageKHR image = EGL_NO_IMAGE_KHR;
    if (has_ext(e->dpy_ext, "EGL_KHR_image_base") &&
        has_ext(e->dpy_ext, "EGL_KHR_gl_texture_2D_image")) {
        const EGLint iattr[] = { EGL_IMAGE_PRESERVED_KHR, EGL_TRUE, EGL_NONE };
        // The source is the export texture E, never P (see the file header).
        image = eglCreateImageKHR(e->dpy, e->ctx, EGL_GL_TEXTURE_2D_KHR,
                                  (EGLClientBuffer)(uintptr_t)e->tex_e, iattr);
        if (image == EGL_NO_IMAGE_KHR)
            snprintf(image_st, n, "failed:%s", egl_error_name(eglGetError()));
        else
            snprintf(image_st, n, "ok");
    }
    if (has_ext(e->dpy_ext, "EGL_KHR_fence_sync")) {
        EGLSyncKHR sync = eglCreateSyncKHR(e->dpy, EGL_SYNC_FENCE_KHR, NULL);
        glFlush();  // the fence only signals once its commands are submitted
        if (sync == EGL_NO_SYNC_KHR) {
            snprintf(sync_st, n, "failed:%s", egl_error_name(eglGetError()));
        } else {
            EGLint w = eglClientWaitSyncKHR(e->dpy, sync, EGL_SYNC_FLUSH_COMMANDS_BIT_KHR,
                                            FENCE_TIMEOUT_NS);
            snprintf(sync_st, n, "%s", w == EGL_CONDITION_SATISFIED_KHR ? "ok"
                                       : w == EGL_TIMEOUT_EXPIRED_KHR ? "timeout" : "failed:wait");
            eglDestroySyncKHR(e->dpy, sync);
        }
    } else {
        glFinish();  // no fence extension: the best the producer can do
    }
    return image;
}

// One round of the handoff for one FLIP_Y value; prints the report line.
// False only when the consumer thread hung.
static bool handoff_round(const handoff_env *e, int flip_y)
{
    unsigned char p0[4], pl[4];
    char image_st[64], sync_st[64];
    consumer_job job = { .dpy = e->dpy, .image = EGL_NO_IMAGE_KHR };
    snprintf(job.import_status, sizeof job.import_status, "skipped");
    if (!render_stacked(e, flip_y, p0, pl)) {
        printf("RENDER_GL handoff api=%s flip_y=%d image=failed:render sync=failed:render "
               "import=skipped row0=none last=none\n", e->api, flip_y);
        return true;
    }
    job.image = export_image(e, image_st, sync_st, sizeof image_st);
    bool joined = true;
    if (job.image != EGL_NO_IMAGE_KHR) {
        joined = run_consumer(&job);
        eglDestroyImageKHR(e->dpy, job.image);
    }
    // fbo_row0/fbo_last: what mpv put into the private texture P (reference).
    printf("RENDER_GL handoff api=%s flip_y=%d image=%s sync=%s import=%s row0=%s last=%s "
           "fbo_row0=%s fbo_last=%s\n",
           e->api, flip_y, image_st, sync_st, job.import_status,
           job.read ? classify(job.row0) : "none", job.read ? classify(job.last) : "none",
           classify(p0), classify(pl));
    return joined;
}

// Creates the export texture E and FBO_E. False if the FBO is incomplete.
static bool create_export_target(handoff_env *e)
{
    glGenTextures(1, &e->tex_e);
    glBindTexture(GL_TEXTURE_2D, e->tex_e);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, W, H, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glGenFramebuffers(1, &e->fbo_e);
    glBindFramebuffer(GL_FRAMEBUFFER, e->fbo_e);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, e->tex_e, 0);
    return glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE;
}

// Replaces the solid red source with 64x32 red above 64x32 blue. Multi-stream
// lavfi graphs need output labels; the single video output is [out0].
static bool load_stacked_source(mpv_handle *mpv, mpv_render_context *rc)
{
    const char *cmd[] = {
        "loadfile",
        "av://lavfi:color=c=red:s=64x32:r=30[top];"
        "color=c=blue:s=64x32:r=30[bottom];[top][bottom]vstack[out0]",
        "replace", NULL,
    };
    return mpv_command(mpv, cmd) >= 0 && wait_for_new_frame(mpv, rc);
}

// The whole handoff phase. Returns 0, or 1 on a setup failure or a hang.
static int run_handoff(mpv_handle *mpv, handoff_env *e, const char *gl_version)
{
    step("handoff: export target");
    if (!create_export_target(e))
        FAIL("export FBO is not complete");
    step("handoff: capability probe");
    if (!print_extensions(e, gl_version))
        FAIL("consumer probe thread did not finish");
    step("handoff: stacked source");
    if (!load_stacked_source(mpv, e->rc))
        FAIL("stacked source: no frame");
    for (int flip_y = 0; flip_y <= 1; flip_y++) {
        step(flip_y ? "handoff: FLIP_Y=1" : "handoff: FLIP_Y=0");
        if (!handoff_round(e, flip_y))
            FAIL("consumer thread did not finish within %d s", JOIN_TIMEOUT_S);
    }
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    glDeleteFramebuffers(1, &e->fbo_e);
    glDeleteTextures(1, &e->tex_e);
    return 0;
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

    // Solid red: R high, G and B low. Black (nothing rendered) fails. The
    // verdict is taken now but reported after teardown, as before.
    const bool is_red = px[0] > 200 && px[1] < 60 && px[2] < 60;

    // --- Handoff: what the OpenGLBackend does per frame (results are reported) ---
    if (is_red) {
        handoff_env env = {
            .dpy = dpy, .ctx = ctx, .dpy_ext = dpy_ext, .api = api, .rc = rc, .fbo_p = fbo,
        };
        if (run_handoff(mpv, &env, gl_version) != 0)
            return 1;
    }

    // --- Teardown (context current: mpv frees its GL objects here) ---------------
    step("teardown");
    mpv_render_context_free(rc);
    mpv_terminate_destroy(mpv);
    glDeleteFramebuffers(1, &fbo);
    glDeleteTextures(1, &tex);
    eglMakeCurrent(dpy, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    eglDestroyContext(dpy, ctx);
    eglTerminate(dpy);

    if (!is_red)
        FAIL("rendered pixel is not red: %u,%u,%u", px[0], px[1], px[2]);
    printf("RENDER_GL ok api=%s renderer=%s gl_version=\"%s\" gl_renderer=\"%s\" pixel=%u,%u,%u\n",
           api, renderer, gl_version, gl_renderer, px[0], px[1], px[2]);
    return 0;
}

// render_vk smoke test: renders one frame of a solid red lavfi source through
// MPV_RENDER_API_TYPE_VULKAN into a host VkImage, reads it back and checks
// the pixel colour. Runs headless (lavapipe works) — no window, no swapchain.
//
// Exit codes: 0 pass, 1 failure, 77 skipped (no Vulkan device; meson "skip").
// Optional argument: renderer ("gpu-next", the default, or "gpu").
// Optional second argument "--drm" (Phase 16, HWD-03): also passes
// MPV_RENDER_PARAM_DRM_DISPLAY_V2 (render_fd = -1, the shape a host without a
// render node uses) and reads mpv's verbose log. Under gpu-next the log must
// show that the drm_params_v2 native resource was registered (patch 0004;
// the gpu renderer registers it in upstream code and logs nothing). The
// VA-API lines are only reported ("vaapi=..."): on a hosted runner
// (llvmpipe/lavapipe, no /dev/dri) they say nothing about real interop.

#define _POSIX_C_SOURCE 200809L
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#ifdef __APPLE__
#include <dlfcn.h>
#endif
#include <time.h>

#include <mpv/client.h>
#include <mpv/render_gl.h>
#include <mpv/render_vk.h>
#include <vulkan/vulkan.h>

#define W 64
#define H 64
#define FAIL(...) do { fprintf(stderr, "FAIL: " __VA_ARGS__); fputc('\n', stderr); return 1; } while (0)
#define VK(x) do { VkResult r_ = (x); if (r_ != VK_SUCCESS) FAIL("%s -> %d", #x, r_); } while (0)

static pthread_mutex_t queue_lock = PTHREAD_MUTEX_INITIALIZER;

// libplacebo and this test share one VkQueue, so serialise submissions.
static void lock_queue(void *ctx, uint32_t qf, uint32_t qi) { (void)ctx; (void)qf; (void)qi; pthread_mutex_lock(&queue_lock); }
static void unlock_queue(void *ctx, uint32_t qf, uint32_t qi) { (void)ctx; (void)qf; (void)qi; pthread_mutex_unlock(&queue_lock); }

// Progress markers go to unbuffered stderr so CI logs show how far we got
// even if a driver aborts the process.
static void step(const char *what) { fprintf(stderr, "[smoke] %s\n", what); }

static void sleep_ms(int ms)
{
    struct timespec ts = { .tv_sec = ms / 1000, .tv_nsec = (ms % 1000) * 1000000L };
    nanosleep(&ts, NULL);
}

// --drm: what mpv's verbose log said about the DRM native resource and VA-API.
struct drm_scan {
    bool registered;    // "gpu-next: native resource drm_params_v2" (0004)
    bool no_display;    // hwdec_vaapi: "Could not create a VA display."
    bool no_interop;    // hwdec_vaapi: no OpenGL/Vulkan dma-buf interop
};

static void scan_log(struct drm_scan *s, const mpv_event *ev)
{
    if (ev->event_id != MPV_EVENT_LOG_MESSAGE)
        return;
    const mpv_event_log_message *m = ev->data;
    if (strstr(m->text, "native resource drm_params_v2"))
        s->registered = true;
    if (strstr(m->text, "Could not create a VA display."))
        s->no_display = true;
    if (strstr(m->text, "VAAPI hwdec only works with OpenGL or Vulkan backends."))
        s->no_interop = true;
}

// Reads queued events for at most `ms` milliseconds, scanning log messages.
// Stops early once the queue has been idle for 50 ms.
static void drain_logs(mpv_handle *mpv, struct drm_scan *s, int ms)
{
    struct timespec t0, now;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    for (;;) {
        mpv_event *ev = mpv_wait_event(mpv, 0.05);
        if (ev->event_id == MPV_EVENT_NONE)
            return;
        scan_log(s, ev);
        clock_gettime(CLOCK_MONOTONIC, &now);
        if ((now.tv_sec - t0.tv_sec) * 1000 + (now.tv_nsec - t0.tv_nsec) / 1000000 >= ms)
            return;
    }
}

static int find_memory(VkPhysicalDevice pd, uint32_t bits, VkMemoryPropertyFlags want)
{
    VkPhysicalDeviceMemoryProperties mp;
    vkGetPhysicalDeviceMemoryProperties(pd, &mp);
    for (uint32_t i = 0; i < mp.memoryTypeCount; i++) {
        if ((bits & (1u << i)) && (mp.memoryTypes[i].propertyFlags & want) == want)
            return (int)i;
    }
    return -1;
}

int main(int argc, char **argv)
{
    setvbuf(stdout, NULL, _IONBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);
#ifdef __APPLE__
    // MoltenVK aborts the process (instead of failing) without a Metal
    // device, e.g. on GPU-less VMs. Probe Metal first.
    void *metal = dlopen("/System/Library/Frameworks/Metal.framework/Metal", RTLD_LAZY);
    void *(*create_dev)(void) = metal ? (void *(*)(void))dlsym(metal, "MTLCreateSystemDefaultDevice") : NULL;
    if (!create_dev || !create_dev()) {
        fprintf(stderr, "SKIP: no Metal device\n");
        return 77;
    }
#endif
    step("create instance");
    // --- Vulkan instance / device ------------------------------------------
    VkApplicationInfo app = {
        .sType = VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .apiVersion = VK_API_VERSION_1_3,
    };
    VkInstanceCreateInfo ici = {
        .sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pApplicationInfo = &app,
#ifdef __APPLE__
        .flags = VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR,
        .enabledExtensionCount = 1,
        .ppEnabledExtensionNames = (const char *[]){ VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME },
#endif
    };
    VkInstance inst;
    if (vkCreateInstance(&ici, NULL, &inst) != VK_SUCCESS) {
        fprintf(stderr, "SKIP: no Vulkan instance\n");
        return 77;
    }

    step("enumerate devices");
    uint32_t npd = 0;
    vkEnumeratePhysicalDevices(inst, &npd, NULL);
    if (!npd) {
        fprintf(stderr, "SKIP: no Vulkan physical device\n");
        return 77;
    }
    VkPhysicalDevice pds[16];
    npd = npd > 16 ? 16 : npd;
    vkEnumeratePhysicalDevices(inst, &npd, pds);
    VkPhysicalDevice pd = pds[0];
    VkPhysicalDeviceProperties props;
    vkGetPhysicalDeviceProperties(pd, &props);
    fprintf(stderr, "[smoke] device: %s (api %u.%u)\n", props.deviceName,
            VK_API_VERSION_MAJOR(props.apiVersion), VK_API_VERSION_MINOR(props.apiVersion));
    if (props.apiVersion < VK_API_VERSION_1_3) {
        fprintf(stderr, "SKIP: device lacks Vulkan 1.3\n");
        return 77;
    }

    uint32_t nqf = 0;
    vkGetPhysicalDeviceQueueFamilyProperties(pd, &nqf, NULL);
    VkQueueFamilyProperties qfp[32];
    nqf = nqf > 32 ? 32 : nqf;
    vkGetPhysicalDeviceQueueFamilyProperties(pd, &nqf, qfp);
    uint32_t qf = UINT32_MAX;
    for (uint32_t i = 0; i < nqf; i++) {
        if (qfp[i].queueFlags & VK_QUEUE_GRAPHICS_BIT) { qf = i; break; }
    }
    if (qf == UINT32_MAX)
        FAIL("no graphics queue");

    // libplacebo requires timeline semaphores and benefits from sync2.
    VkPhysicalDeviceVulkan13Features f13 = {
        .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
        .synchronization2 = VK_TRUE,
    };
    VkPhysicalDeviceVulkan12Features f12 = {
        .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
        .pNext = &f13,
        .timelineSemaphore = VK_TRUE,
        .hostQueryReset = VK_TRUE,
    };
    VkPhysicalDeviceFeatures2 feats = {
        .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2,
        .pNext = &f12,
    };
    float prio = 1.0f;
    VkDeviceQueueCreateInfo qci = {
        .sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
        .queueFamilyIndex = qf,
        .queueCount = 1,
        .pQueuePriorities = &prio,
    };
#ifdef __APPLE__
    const char *exts[] = { "VK_KHR_portability_subset" };
    const int nexts = 1;
#else
    const char **exts = NULL;
    const int nexts = 0;
#endif
    VkDeviceCreateInfo dci = {
        .sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .pNext = &feats,
        .queueCreateInfoCount = 1,
        .pQueueCreateInfos = &qci,
        .enabledExtensionCount = (uint32_t)nexts,
        .ppEnabledExtensionNames = exts,
    };
    step("create device");
    VkDevice dev;
    VK(vkCreateDevice(pd, &dci, NULL, &dev));
    VkQueue queue;
    vkGetDeviceQueue(dev, qf, 0, &queue);

    // --- Render target + readback buffer -------------------------------------
    step("create render target");
    VkImage img;
    VK(vkCreateImage(dev, &(VkImageCreateInfo){
        .sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .imageType = VK_IMAGE_TYPE_2D,
        .format = VK_FORMAT_R8G8B8A8_UNORM,
        .extent = { W, H, 1 },
        .mipLevels = 1,
        .arrayLayers = 1,
        .samples = VK_SAMPLE_COUNT_1_BIT,
        .tiling = VK_IMAGE_TILING_OPTIMAL,
        .usage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT |
                 VK_IMAGE_USAGE_TRANSFER_SRC_BIT |
                 VK_IMAGE_USAGE_TRANSFER_DST_BIT,
        .initialLayout = VK_IMAGE_LAYOUT_UNDEFINED,
    }, NULL, &img));
    VkMemoryRequirements mr;
    vkGetImageMemoryRequirements(dev, img, &mr);
    VkDeviceMemory img_mem;
    VK(vkAllocateMemory(dev, &(VkMemoryAllocateInfo){
        .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .allocationSize = mr.size,
        .memoryTypeIndex = (uint32_t)find_memory(pd, mr.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT),
    }, NULL, &img_mem));
    VK(vkBindImageMemory(dev, img, img_mem, 0));

    VkBuffer buf;
    VK(vkCreateBuffer(dev, &(VkBufferCreateInfo){
        .sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .size = W * H * 4,
        .usage = VK_BUFFER_USAGE_TRANSFER_DST_BIT,
    }, NULL, &buf));
    vkGetBufferMemoryRequirements(dev, buf, &mr);
    int host_type = find_memory(pd, mr.memoryTypeBits,
        VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
    if (host_type < 0)
        FAIL("no host-visible memory");
    VkDeviceMemory buf_mem;
    VK(vkAllocateMemory(dev, &(VkMemoryAllocateInfo){
        .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .allocationSize = mr.size,
        .memoryTypeIndex = (uint32_t)host_type,
    }, NULL, &buf_mem));
    VK(vkBindBufferMemory(dev, buf, buf_mem, 0));

    // first: frame 1 -> frame 2; done: frame 2 -> read back.
    VkSemaphore first, done;
    VK(vkCreateSemaphore(dev, &(VkSemaphoreCreateInfo){
        .sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO }, NULL, &first));
    VK(vkCreateSemaphore(dev, &(VkSemaphoreCreateInfo){
        .sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO }, NULL, &done));

    // --- mpv -----------------------------------------------------------------
    step("create mpv");
    mpv_handle *mpv = mpv_create();
    if (!mpv)
        FAIL("mpv_create");
    mpv_set_option_string(mpv, "vo", "libmpv");
    mpv_set_option_string(mpv, "ao", "null");
    mpv_set_option_string(mpv, "config", "no");
    mpv_set_option_string(mpv, "terminal", "yes");
    const bool drm = argc > 2 && strcmp(argv[2], "--drm") == 0;
    struct drm_scan scan = { 0 };
    // --drm needs the verbose render-context and VA-API lines. Only those
    // modules go verbose: mpv's log queue drops the OLDEST entries when it
    // overflows, and the registration line comes first.
    mpv_set_option_string(mpv, "msg-level",
        drm ? "all=warn,vo=v,libmpv_render=v,vaapi=v" : "all=warn,vo=v");
    if (mpv_initialize(mpv) < 0)
        FAIL("mpv_initialize");
    if (drm)
        mpv_request_log_messages(mpv, "v");

    mpv_vulkan_init_params vkp = {
        .instance = inst,
        .get_instance_proc_addr = vkGetInstanceProcAddr,
        .api_version = VK_API_VERSION_1_3,
        .physical_device = pd,
        .device = dev,
        .extensions = exts,
        .num_extensions = nexts,
        .features = &feats,
        .queue_graphics = { qf, 1 },
        .queue_compute = { qf, 1 },
        .queue_transfer = { qf, 1 },
        .lock_queue = lock_queue,
        .unlock_queue = unlock_queue,
    };
    const char *renderer = argc > 1 ? argv[1] : "gpu-next";
    // A host without a DRM render node: fds invalid, so VA-API cannot create
    // a display, but the parameter must still be accepted and registered.
    mpv_opengl_drm_params_v2 drm_params = {
        .fd = -1, .crtc_id = 0, .connector_id = 0,
        .atomic_request_ptr = NULL, .render_fd = -1,
    };
    // Without --drm the 4th entry has type INVALID (0): it ends the list.
    mpv_render_param params[] = {
        { MPV_RENDER_PARAM_API_TYPE, (void *)MPV_RENDER_API_TYPE_VULKAN },
        { MPV_RENDER_PARAM_VULKAN_INIT_PARAMS, &vkp },
        { MPV_RENDER_PARAM_VULKAN_RENDERER, (void *)renderer },
        { drm ? MPV_RENDER_PARAM_DRM_DISPLAY_V2 : MPV_RENDER_PARAM_INVALID, &drm_params },
        { 0 },
    };
    fprintf(stderr, "[smoke] renderer: %s\n", renderer);
    step("create render context");
    mpv_render_context *rc;
    int err = mpv_render_context_create(&rc, mpv, params);
    if (err < 0)
        FAIL("mpv_render_context_create: %s", mpv_error_string(err));
    if (drm) {
        drain_logs(mpv, &scan, 2000);
        if (strcmp(renderer, "gpu-next") == 0 && !scan.registered)
            FAIL("gpu-next did not register the drm_params_v2 native resource");
    }

    const char *cmd[] = { "loadfile", "av://lavfi:color=c=red:s=64x64:r=30", NULL };
    if (mpv_command(mpv, cmd) < 0)
        FAIL("loadfile");

    step("wait for frame");
    // Wait (≤10 s) until mpv has a frame ready to render.
    bool have_frame = false;
    for (int i = 0; i < 1000 && !have_frame; i++) {
        mpv_event *ev;
        while ((ev = mpv_wait_event(mpv, 0))->event_id != MPV_EVENT_NONE) {
            scan_log(&scan, ev);
            if (ev->event_id == MPV_EVENT_END_FILE)
                FAIL("playback ended before a frame was rendered");
        }
        have_frame = mpv_render_context_update(rc) & MPV_RENDER_UPDATE_FRAME;
        if (!have_frame)
            sleep_ms(10);
    }
    if (!have_frame)
        FAIL("no frame within 10 s");

    mpv_vulkan_image target = {
        .image = img,
        .format = VK_FORMAT_R8G8B8A8_UNORM,
        .usage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT |
                 VK_IMAGE_USAGE_TRANSFER_SRC_BIT |
                 VK_IMAGE_USAGE_TRANSFER_DST_BIT,
        .width = W,
        .height = H,
        // Like the plugin: the image is always handed over to/from the
        // external queue family, starting with discardable contents.
        .layout = VK_IMAGE_LAYOUT_UNDEFINED,
        .final_layout = VK_IMAGE_LAYOUT_GENERAL,
        .queue_family = VK_QUEUE_FAMILY_EXTERNAL,
        .signal_semaphore = first,
    };
    // Two renders into one image; a redraw must not wait for a vsync report.
    int no_block = 0;
    mpv_render_param rparams[] = {
        { MPV_RENDER_PARAM_VULKAN_IMAGE, &target },
        { MPV_RENDER_PARAM_BLOCK_FOR_TARGET_TIME, &no_block },
        { 0 },
    };
    // A target without a signal semaphore is rejected up front (libplacebo
    // would assert when handing the image back); the frame stays queued.
    step("render without signal_semaphore is rejected");
    target.signal_semaphore = VK_NULL_HANDLE;
    err = mpv_render_context_render(rc, rparams);
    if (err != MPV_ERROR_INVALID_PARAMETER)
        FAIL("render without signal_semaphore: got %d (%s)", err, mpv_error_string(err));
    target.signal_semaphore = first;

    step("render");
    err = mpv_render_context_render(rc, rparams);
    if (err < 0)
        FAIL("mpv_render_context_render: %s", mpv_error_string(err));

    // Second frame: acquire from EXTERNAL again (paired with the release of
    // frame 1), preserving contents, then end in the read-back layout.
    step("render again into the same image");
    target.layout = VK_IMAGE_LAYOUT_GENERAL;
    target.final_layout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
    target.wait_semaphore = first;
    target.signal_semaphore = done;
    err = mpv_render_context_render(rc, rparams);
    if (err < 0)
        FAIL("second mpv_render_context_render: %s", mpv_error_string(err));

    // --- Read back: copy after mpv's signal --------------------------------
    VkCommandPool pool;
    VK(vkCreateCommandPool(dev, &(VkCommandPoolCreateInfo){
        .sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .queueFamilyIndex = qf,
    }, NULL, &pool));
    VkCommandBuffer cb;
    VK(vkAllocateCommandBuffers(dev, &(VkCommandBufferAllocateInfo){
        .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = pool,
        .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = 1,
    }, &cb));
    VK(vkBeginCommandBuffer(cb, &(VkCommandBufferBeginInfo){
        .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
    }));
    // Acquire the image from the external queue family mpv released it to.
    vkCmdPipelineBarrier(cb, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
        VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, NULL, 0, NULL, 1,
        &(VkImageMemoryBarrier){
            .sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
            .dstAccessMask = VK_ACCESS_TRANSFER_READ_BIT,
            .oldLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
            .newLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
            .srcQueueFamilyIndex = VK_QUEUE_FAMILY_EXTERNAL,
            .dstQueueFamilyIndex = qf,
            .image = img,
            .subresourceRange = { VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1 },
        });
    vkCmdCopyImageToBuffer(cb, img, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, buf, 1,
        &(VkBufferImageCopy){
            .imageSubresource = { VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1 },
            .imageExtent = { W, H, 1 },
        });
    VK(vkEndCommandBuffer(cb));
    VkFence fence;
    VK(vkCreateFence(dev, &(VkFenceCreateInfo){
        .sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO }, NULL, &fence));
    VkPipelineStageFlags wait_stage = VK_PIPELINE_STAGE_TRANSFER_BIT;
    pthread_mutex_lock(&queue_lock);
    VkResult qr = vkQueueSubmit(queue, 1, &(VkSubmitInfo){
        .sType = VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .waitSemaphoreCount = 1,
        .pWaitSemaphores = &done,
        .pWaitDstStageMask = &wait_stage,
        .commandBufferCount = 1,
        .pCommandBuffers = &cb,
    }, fence);
    pthread_mutex_unlock(&queue_lock);
    VK(qr);
    VK(vkWaitForFences(dev, 1, &fence, VK_TRUE, 10ull * 1000 * 1000 * 1000));

    uint8_t *px;
    VK(vkMapMemory(dev, buf_mem, 0, VK_WHOLE_SIZE, 0, (void **)&px));
    const uint8_t *c = px + ((H / 2) * W + W / 2) * 4;
    printf("center pixel RGBA = %u %u %u %u\n", c[0], c[1], c[2], c[3]);
    // Pure red after YUV round-trip and dithering; allow a small tolerance.
    bool ok = c[0] >= 230 && c[1] <= 25 && c[2] <= 25;
    vkUnmapMemory(dev, buf_mem);

    step("teardown");
    // --- Teardown (render context must go before the device) -----------------
    mpv_render_context_free(rc);
    mpv_terminate_destroy(mpv);
    vkDestroyFence(dev, fence, NULL);
    vkDestroyCommandPool(dev, pool, NULL);
    vkDestroySemaphore(dev, done, NULL);
    vkDestroySemaphore(dev, first, NULL);
    vkDestroyBuffer(dev, buf, NULL);
    vkFreeMemory(dev, buf_mem, NULL);
    vkDestroyImage(dev, img, NULL);
    vkFreeMemory(dev, img_mem, NULL);
    vkDestroyDevice(dev, NULL);
    vkDestroyInstance(inst, NULL);

    if (!ok)
        FAIL("rendered pixel is not red");
    if (drm) {
        // Information only: llvmpipe/lavapipe without /dev/dri cannot show
        // that VA-API interop works (research Pitfall 4).
        printf("RENDER_VK drm ok renderer=%s native_resource=%s vaapi=%s\n", renderer,
               strcmp(renderer, "gpu-next") == 0 ? "registered" : "upstream",
               scan.no_interop ? "interop-unavailable"
                               : scan.no_display ? "display-not-created" : "no-log");
    }
    printf("PASS\n");
    return 0;
}

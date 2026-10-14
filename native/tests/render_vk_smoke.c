// render_vk smoke test: renders one frame of a solid red lavfi source through
// MPV_RENDER_API_TYPE_VULKAN into a host VkImage, reads it back and checks
// the pixel colour. Runs headless (lavapipe works) — no window, no swapchain.
//
// Exit codes: 0 pass, 1 failure, 77 skipped (no Vulkan device; meson "skip").

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

int main(void)
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

    VkSemaphore done;
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
    mpv_set_option_string(mpv, "msg-level", "all=warn,vo=v");
    if (mpv_initialize(mpv) < 0)
        FAIL("mpv_initialize");

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
    mpv_render_param params[] = {
        { MPV_RENDER_PARAM_API_TYPE, (void *)MPV_RENDER_API_TYPE_VULKAN },
        { MPV_RENDER_PARAM_VULKAN_INIT_PARAMS, &vkp },
        { 0 },
    };
    step("create render context");
    mpv_render_context *rc;
    int err = mpv_render_context_create(&rc, mpv, params);
    if (err < 0)
        FAIL("mpv_render_context_create: %s", mpv_error_string(err));

    const char *cmd[] = { "loadfile", "av://lavfi:color=c=red:s=64x64:r=30", NULL };
    if (mpv_command(mpv, cmd) < 0)
        FAIL("loadfile");

    step("wait for frame");
    // Wait (≤10 s) until mpv has a frame ready to render.
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

    mpv_vulkan_image target = {
        .image = img,
        .format = VK_FORMAT_R8G8B8A8_UNORM,
        .usage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT |
                 VK_IMAGE_USAGE_TRANSFER_SRC_BIT |
                 VK_IMAGE_USAGE_TRANSFER_DST_BIT,
        .width = W,
        .height = H,
        .layout = VK_IMAGE_LAYOUT_UNDEFINED,
        .final_layout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
        .queue_family = VK_QUEUE_FAMILY_IGNORED,
        .signal_semaphore = done,
    };
    mpv_render_param rparams[] = {
        { MPV_RENDER_PARAM_VULKAN_IMAGE, &target },
        { 0 },
    };
    step("render");
    err = mpv_render_context_render(rc, rparams);
    if (err < 0)
        FAIL("mpv_render_context_render: %s", mpv_error_string(err));

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
    vkDestroyBuffer(dev, buf, NULL);
    vkFreeMemory(dev, buf_mem, NULL);
    vkDestroyImage(dev, img, NULL);
    vkFreeMemory(dev, img_mem, NULL);
    vkDestroyDevice(dev, NULL);
    vkDestroyInstance(inst, NULL);

    if (!ok)
        FAIL("rendered pixel is not red");
    printf("PASS\n");
    return 0;
}

/* Copyright (C) 2026 the mpv_kit developers
 *
 * Permission to use, copy, modify, and/or distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 */

#ifndef MPV_CLIENT_API_RENDER_VK_H_
#define MPV_CLIENT_API_RENDER_VK_H_

#include "render.h"

#include <vulkan/vulkan.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Vulkan backend for the render API (mpv_kit extension).
 * ======================================================
 *
 * Select it with MPV_RENDER_PARAM_API_TYPE = MPV_RENDER_API_TYPE_VULKAN and
 * pass MPV_RENDER_PARAM_VULKAN_INIT_PARAMS to mpv_render_context_create().
 *
 * The API user owns the Vulkan instance and device; mpv imports them via
 * libplacebo (pl_vulkan_import). This lets the host enable the platform
 * interop extensions it needs (external memory / semaphores for sharing the
 * rendered images with a compositor or UI toolkit). For hardware decoding
 * with --hwdec=vulkan, the device should additionally have a video decode
 * queue and the VK_KHR_video_* extensions enabled.
 *
 * Rendering: pass MPV_RENDER_PARAM_VULKAN_IMAGE to mpv_render_context_render().
 * mpv waits on wait_semaphore before touching the image, renders, transitions
 * the image to final_layout, and signals signal_semaphore when done. The
 * call does not block on GPU completion.
 *
 * Threading: all Vulkan queue submissions made by mpv happen on the thread
 * calling mpv_render_context_render(), plus the hwdec thread. If the host
 * shares queues with other code, supply lock_queue/unlock_queue.
 */

#define MPV_RENDER_API_TYPE_VULKAN "vulkan"

/**
 * Render parameter types for the Vulkan backend. They live in a private
 * range so they can never collide with future upstream enum values.
 */
#define MPV_RENDER_PARAM_VULKAN_INIT_PARAMS ((mpv_render_param_type)0x6d6b0001)
#define MPV_RENDER_PARAM_VULKAN_IMAGE       ((mpv_render_param_type)0x6d6b0002)
/**
 * Optional for mpv_render_context_create(): the renderer to use, as a
 * const char* (the data pointer is the string itself, like
 * MPV_RENDER_PARAM_API_TYPE).
 *  - "gpu-next" (default): libplacebo's renderer, as used by --vo=gpu-next.
 *    Better HDR/tone mapping and color management, persistent shader and
 *    ICC caches.
 *  - "gpu": mpv's older gl_video renderer, as used by --vo=gpu.
 */
#define MPV_RENDER_PARAM_VULKAN_RENDERER    ((mpv_render_param_type)0x6d6b0003)

/** Queue family selection, mirrors libplacebo's pl_vulkan_queue. */
typedef struct mpv_vulkan_queue {
    uint32_t index; /** queue family index */
    uint32_t count; /** number of queues created in this family (>= 1) */
} mpv_vulkan_queue;

/**
 * For MPV_RENDER_PARAM_VULKAN_INIT_PARAMS. All handles must stay valid until
 * mpv_render_context_free() returns.
 */
typedef struct mpv_vulkan_init_params {
    VkInstance instance;
    PFN_vkGetInstanceProcAddr get_instance_proc_addr;
    /** Vulkan API version the instance was created with (VK_MAKE_API_VERSION). */
    uint32_t api_version;
    VkPhysicalDevice physical_device;
    VkDevice device;
    /** Device extensions enabled on `device` (required for correct feature use). */
    const char *const *extensions;
    int num_extensions;
    /** Features enabled on `device` (VkPhysicalDeviceFeatures2 chain), may be NULL. */
    const VkPhysicalDeviceFeatures2 *features;
    /** Queue families; compute/transfer may equal graphics or have count 0. */
    mpv_vulkan_queue queue_graphics;
    mpv_vulkan_queue queue_compute;
    mpv_vulkan_queue queue_transfer;
    /** Optional external queue locking (both NULL or both set). */
    void (*lock_queue)(void *ctx, uint32_t qf, uint32_t qidx);
    void (*unlock_queue)(void *ctx, uint32_t qf, uint32_t qidx);
    void *queue_ctx;
} mpv_vulkan_init_params;

/**
 * For MPV_RENDER_PARAM_VULKAN_IMAGE: the render target of one frame.
 *
 * The image must be a 2D, single-mip, single-layer color image created with
 * at least VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT (STORAGE/TRANSFER usages let
 * mpv choose faster paths). The image is wrapped only for the duration of the
 * call, so the host may destroy it once signal_semaphore has been reached.
 *
 * Semaphores may be binary (value ignored, use 0) or timeline (value used).
 * VK_NULL_HANDLE disables the corresponding wait/signal.
 */
typedef struct mpv_vulkan_image {
    VkImage image;
    VkFormat format;
    VkImageUsageFlags usage;
    int width, height;
    /** Current layout of the image when the host hands it to mpv. */
    VkImageLayout layout;
    /** Layout the image is transitioned to after rendering. */
    VkImageLayout final_layout;
    /** Queue family that currently owns the image, or VK_QUEUE_FAMILY_IGNORED. */
    uint32_t queue_family;
    VkSemaphore wait_semaphore;
    uint64_t wait_value;
    VkSemaphore signal_semaphore;
    uint64_t signal_value;
} mpv_vulkan_image;

#ifdef __cplusplus
}
#endif

#endif

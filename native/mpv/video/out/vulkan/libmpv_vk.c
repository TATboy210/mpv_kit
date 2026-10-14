/*
 * This file is part of mpv.
 *
 * mpv is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * mpv is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with mpv.  If not, see <http://www.gnu.org/licenses/>.
 */

// Vulkan backend for the libmpv render API (MPV_RENDER_API_TYPE_VULKAN).
//
// Structure mirrors video/out/opengl/libmpv_gl.c: the host owns the device,
// we import it into libplacebo, expose it as a ra (ra_pl) so the regular
// gl_video renderer (and hwdec_vulkan) work unchanged, and wrap the host's
// VkImage as the render target for each frame.

#include <inttypes.h>
#include <sys/stat.h>

#include <libplacebo/cache.h>

#include "common.h"
#include "context.h"
#include "misc/io_utils.h"
#include "misc/path_utils.h"
#include "mpv/render_vk.h"
#include "options/m_config.h"
#include "options/path.h"
#include "osdep/io.h"
#include "stream/stream.h"
#include "video/out/gpu/libmpv_gpu.h"
#include "video/out/gpu/ra.h"
#include "video/out/gpu/video.h"
#include "video/out/placebo/ra_pl.h"
#include "video/out/placebo/utils.h"

// Persistent libplacebo object cache (compiled shaders/pipelines).
//
// gl_video's own shader cache needs ra->fns to return cached program blobs,
// which ra_pl never does, so on this backend it is a no-op. Attaching a
// pl_cache to the imported pl_gpu caches the SPIR-V compilation and pipeline
// objects instead. Files use vo_gpu_next's layout ("shader_<key>" in the
// --gpu-shader-cache-dir directory), so both renderers can share a cache.
struct shader_cache {
    struct mp_log *log;
    struct mpv_global *global;
    char *dir;
    pl_cache cache;
};

struct priv {
    struct shader_cache shader_cache;
    struct mpvk_ctx vk;
    // libplacebo never reads this; it only exists so that mpv code using
    // mpvk_ctx->vkinst (hwdec_vulkan) sees the host's instance.
    struct pl_vk_inst_t inst;
    struct ra_ctx *ra_ctx;

    // Per-frame state between wrap_fbo() and done_frame().
    pl_tex target;
    struct ra_tex target_ra;
    mpv_vulkan_image image;
};

static char *cache_path(void *ta_ctx, const char *dir, uint64_t key)
{
    return mp_path_join(ta_ctx, dir,
                        talloc_asprintf(ta_ctx, "shader_%016" PRIx64, key));
}

static pl_cache_obj cache_load_obj(void *priv, uint64_t key)
{
    struct shader_cache *c = priv;
    void *ta_ctx = talloc_new(NULL);
    pl_cache_obj obj = {0};

    char *path = cache_path(ta_ctx, c->dir, key);
    struct stat st;
    if (path && !stat(path, &st)) {
        struct bstr data = stream_read_file(path, ta_ctx, c->global,
                                            STREAM_MAX_READ_SIZE);
        if (data.len) {
            obj = (pl_cache_obj) {
                .key = key,
                .data = talloc_steal(NULL, data.start),
                .size = data.len,
                .free = talloc_free,
            };
        }
    }
    talloc_free(ta_ctx);
    return obj;
}

static void cache_save_obj(void *priv, pl_cache_obj obj)
{
    struct shader_cache *c = priv;
    void *ta_ctx = talloc_new(NULL);

    char *path = cache_path(ta_ctx, c->dir, obj.key);
    struct stat st;
    if (path && (!obj.data || !obj.size)) {
        unlink(path);
    } else if (path && (stat(path, &st) || st.st_size != obj.size)) {
        if (!mp_save_to_file(path, obj.data, obj.size))
            MP_WARN(c, "Failed writing shader cache file %s\n", path);
    }
    talloc_free(ta_ctx);
}

// Honours --gpu-shader-cache / --gpu-shader-cache-dir. Leaves the cache
// disabled (with a log line) when no directory can be resolved, e.g. for
// libmpv with config=no and no explicit --gpu-shader-cache-dir.
static void shader_cache_init(struct libmpv_gpu_context *ctx, struct priv *p)
{
    struct gl_video_opts *opts =
        mp_get_config_group(p, ctx->global, &gl_video_conf);
    if (!opts->shader_cache)
        return;

    char *dir = NULL;
    if (opts->shader_cache_dir && opts->shader_cache_dir[0]) {
        dir = mp_get_user_path(p, ctx->global, opts->shader_cache_dir);
    } else {
        dir = mp_find_user_file(p, ctx->global, "cache", "");
    }
    if (!dir || !dir[0]) {
        MP_VERBOSE(ctx, "No shader cache directory; set --gpu-shader-cache-dir "
                        "to cache compiled shaders across runs.\n");
        return;
    }
    mp_mkdirp(dir);

    p->shader_cache = (struct shader_cache) {
        .log = ctx->log,
        .global = ctx->global,
        .dir = dir,
    };
    p->shader_cache.cache = pl_cache_create(pl_cache_params(
        .log = p->vk.pllog,
        .max_total_size = 10 << 20,
        .get = cache_load_obj,
        .set = cache_save_obj,
        .priv = &p->shader_cache,
    ));
    if (p->shader_cache.cache) {
        pl_gpu_set_cache(p->vk.gpu, p->shader_cache.cache);
        MP_VERBOSE(ctx, "Shader cache: %s\n", dir);
    }
}

static int init(struct libmpv_gpu_context *ctx, mpv_render_param *params)
{
    ctx->priv = talloc_zero(NULL, struct priv);
    struct priv *p = ctx->priv;

    mpv_vulkan_init_params *ip =
        get_mpv_render_param(params, MPV_RENDER_PARAM_VULKAN_INIT_PARAMS, NULL);
    if (!ip || !ip->instance || !ip->get_instance_proc_addr ||
        !ip->physical_device || !ip->device || !ip->queue_graphics.count)
    {
        MP_FATAL(ctx, "MPV_RENDER_PARAM_VULKAN_INIT_PARAMS missing or incomplete.\n");
        return MPV_ERROR_INVALID_PARAMETER;
    }
    if (!ip->lock_queue != !ip->unlock_queue) {
        MP_FATAL(ctx, "lock_queue and unlock_queue must be set together.\n");
        return MPV_ERROR_INVALID_PARAMETER;
    }

    p->vk.pllog = mppl_log_create(p, ctx->log);
    if (!p->vk.pllog)
        return MPV_ERROR_GENERIC;

    p->inst = (struct pl_vk_inst_t) {
        .instance = ip->instance,
        .api_version = ip->api_version,
        .get_proc_addr = ip->get_instance_proc_addr,
    };
    p->vk.vkinst = &p->inst;

    p->vk.vulkan = pl_vulkan_import(p->vk.pllog, pl_vulkan_import_params(
        .instance = ip->instance,
        .get_proc_addr = ip->get_instance_proc_addr,
        .phys_device = ip->physical_device,
        .device = ip->device,
        .extensions = (const char **) ip->extensions,
        .num_extensions = ip->num_extensions,
        .features = ip->features,
        .queue_graphics = { ip->queue_graphics.index, ip->queue_graphics.count },
        .queue_compute = { ip->queue_compute.index, ip->queue_compute.count },
        .queue_transfer = { ip->queue_transfer.index, ip->queue_transfer.count },
        .lock_queue = ip->lock_queue,
        .unlock_queue = ip->unlock_queue,
        .queue_ctx = ip->queue_ctx,
    ));
    if (!p->vk.vulkan) {
        MP_FATAL(ctx, "Failed importing the host Vulkan device.\n");
        return MPV_ERROR_UNSUPPORTED;
    }
    p->vk.gpu = p->vk.vulkan->gpu;
    p->vk.num_imported_extensions = ip->num_extensions;
    p->vk.imported_extensions = talloc_array(p, const char *, ip->num_extensions);
    for (int i = 0; i < ip->num_extensions; i++)
        p->vk.imported_extensions[i] = talloc_strdup(p, ip->extensions[i]);

    // Before ra_create_pl(): every shader compiled from here on is cached.
    shader_cache_init(ctx, p);

    p->ra_ctx = talloc_zero(p, struct ra_ctx);
    p->ra_ctx->log = ctx->log;
    p->ra_ctx->global = ctx->global;
    p->ra_ctx->opts = (struct ra_ctx_opts) { .allow_sw = true };
    p->ra_ctx->ra = ra_create_pl(p->vk.gpu, ctx->log);
    if (!p->ra_ctx->ra)
        return MPV_ERROR_UNSUPPORTED;

    // Expose the device through ra_vk_ctx_get() so --hwdec=vulkan works.
    ra_vk_ctx_init_external(p->ra_ctx, &p->vk);

    ctx->ra_ctx = p->ra_ctx;
    return 0;
}

// Return the current target to the host (transition + signal) and drop the
// wrapper. Destruction is deferred by libplacebo until the GPU is done.
static void release_target(struct libmpv_gpu_context *ctx)
{
    struct priv *p = ctx->priv;
    if (!p->target)
        return;

    bool ok = pl_vulkan_hold_ex(p->vk.gpu, pl_vulkan_hold_params(
        .tex = p->target,
        .layout = p->image.final_layout,
        .qf = p->image.queue_family,
        .semaphore = {
            .sem = p->image.signal_semaphore,
            .value = p->image.signal_value,
        },
    ));
    if (!ok)
        MP_ERR(ctx, "Failed returning the render target to the host.\n");

    pl_tex_destroy(p->vk.gpu, &p->target);
    p->target_ra = (struct ra_tex) {0};
}

static bool same_image(const mpv_vulkan_image *a, const mpv_vulkan_image *b)
{
    return a->image == b->image && a->width == b->width &&
           a->height == b->height && a->format == b->format &&
           a->wait_semaphore == b->wait_semaphore &&
           a->wait_value == b->wait_value;
}

static int wrap_fbo(struct libmpv_gpu_context *ctx, mpv_render_param *params,
                    struct ra_tex **out)
{
    struct priv *p = ctx->priv;

    mpv_vulkan_image *img =
        get_mpv_render_param(params, MPV_RENDER_PARAM_VULKAN_IMAGE, NULL);
    if (!img || !img->image || img->width <= 0 || img->height <= 0)
        return MPV_ERROR_INVALID_PARAMETER;
    if (!(img->usage & VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT)) {
        MP_FATAL(ctx, "Render target lacks VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT.\n");
        return MPV_ERROR_INVALID_PARAMETER;
    }

    // vo_libmpv calls wrap_fbo() twice per frame (get_target_size, then
    // render) with a single done_frame(). Re-wrapping would wait on the host
    // semaphore twice, so reuse the pending wrapper for the same image.
    if (p->target) {
        if (same_image(&p->image, img)) {
            *out = &p->target_ra;
            return 0;
        }
        // A previous target was never rendered (e.g. aborted frame); still
        // honour its signal so the host does not deadlock waiting on it.
        release_target(ctx);
    }

    // Wrapping per frame keeps lifetime trivially safe for the host (it may
    // recreate images on resize at will); creating views is negligible next
    // to rendering a frame.
    pl_tex tex = pl_vulkan_wrap(p->vk.gpu, pl_vulkan_wrap_params(
        .image = img->image,
        .width = img->width,
        .height = img->height,
        .format = img->format,
        .usage = img->usage,
    ));
    if (!tex) {
        MP_ERR(ctx, "Failed wrapping the render target image.\n");
        return MPV_ERROR_UNSUPPORTED;
    }

    // Hand ownership to libplacebo; it waits on the host semaphore before use.
    pl_vulkan_release_ex(p->vk.gpu, pl_vulkan_release_params(
        .tex = tex,
        .layout = img->layout,
        .qf = img->queue_family,
        .semaphore = { .sem = img->wait_semaphore, .value = img->wait_value },
    ));

    if (!mppl_wrap_tex(p->ra_ctx->ra, tex, &p->target_ra)) {
        pl_tex_destroy(p->vk.gpu, &tex);
        return MPV_ERROR_UNSUPPORTED;
    }

    p->target = tex;
    p->image = *img;
    *out = &p->target_ra;
    return 0;
}

static void done_frame(struct libmpv_gpu_context *ctx, bool ds)
{
    // Submits pending work, transitions to final_layout and signals the host
    // semaphore once rendering completes.
    release_target(ctx);
}

static void destroy(struct libmpv_gpu_context *ctx)
{
    struct priv *p = ctx->priv;
    if (!p)
        return;

    if (p->vk.gpu) {
        release_target(ctx);
        pl_gpu_finish(p->vk.gpu);
    }
    if (p->ra_ctx) {
        ra_vk_ctx_uninit_external(p->ra_ctx);
        if (p->ra_ctx->ra)
            p->ra_ctx->ra->fns->destroy(p->ra_ctx->ra);
        p->ra_ctx->ra = NULL;
    }
    // Imported devices are not destroyed by libplacebo, only its wrapper.
    // The gpu references the cache, so it goes first.
    pl_vulkan_destroy(&p->vk.vulkan);
    pl_cache_destroy(&p->shader_cache.cache);
    pl_log_destroy(&p->vk.pllog);
}

const struct libmpv_gpu_context_fns libmpv_gpu_context_vk = {
    .api_name = MPV_RENDER_API_TYPE_VULKAN,
    .init = init,
    .wrap_fbo = wrap_fbo,
    .done_frame = done_frame,
    .destroy = destroy,
};

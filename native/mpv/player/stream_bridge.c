/*
 * Asynchronous custom stream bridge (mpv_kit extension), see
 * include/mpv/stream_bridge.h.
 *
 * Built only on the public client API (mpv_stream_cb_add_ro): each callback
 * that mpv issues on its demuxer thread is turned into a request, posted to
 * the host, and awaited on a condition variable.
 *
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

#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

#include "mpv/client.h"
#include "mpv/stream_bridge.h"
#include "mpv/stream_cb.h"
#include "osdep/threads.h"

struct registration {
    uint64_t id;
    mpv_kit_stream_request_fn fn;
    void *user_data;
    bool shutdown;
    int calls;        // request_fn invocations in progress
    struct registration *next;
};

struct bridge_stream {
    struct registration *reg;
    uint64_t id;      // host-side stream id
    int64_t size;     // < 0: unknown
    bool cancelled;
};

enum request_state { REQ_PENDING, REQ_BEGUN, REQ_DONE };

struct request {
    uint64_t id;
    struct registration *reg;
    struct bridge_stream *stream; // NULL for OPEN
    enum request_state state;
    int64_t result, aux;
    struct request *next;
};

// One lock for all bridge state: requests are rare relative to the work
// they wait for, so contention is irrelevant.
static mp_static_mutex lock = MP_STATIC_MUTEX_INITIALIZER;
static mp_cond wakeup = MP_STATIC_COND_INITIALIZER;
static struct registration *registrations;
static struct request *requests;
static uint64_t next_id = 1;

static struct request *find_request(uint64_t id)
{
    for (struct request *r = requests; r; r = r->next) {
        if (r->id == id)
            return r;
    }
    return NULL;
}

static void unlink_request(struct request *req)
{
    for (struct request **p = &requests; *p; p = &(*p)->next) {
        if (*p == req) {
            *p = req->next;
            return;
        }
    }
}

// Whether a waiting request must give up without the host's answer.
static bool abandoned(const struct request *req)
{
    if (req->reg->shutdown)
        return true;
    // A begun request keeps its buffer until the host completes it.
    return req->state == REQ_PENDING && req->stream && req->stream->cancelled;
}

static void end_call(struct registration *reg)
{
    if (--reg->calls == 0)
        mp_cond_broadcast(&wakeup); // shutdown may wait for this
}

// Posts one request and blocks until it is answered or abandoned.
static int64_t call_host(struct registration *reg, struct bridge_stream *stream,
                         int op, void *data, int64_t arg, int64_t *aux)
{
    mp_mutex_lock(&lock);
    if (reg->shutdown || (stream && stream->cancelled)) {
        mp_mutex_unlock(&lock);
        return MPV_ERROR_GENERIC;
    }
    struct request *req = calloc(1, sizeof(*req));
    if (!req) {
        mp_mutex_unlock(&lock);
        return MPV_ERROR_NOMEM;
    }
    req->id = next_id++;
    req->reg = reg;
    req->stream = stream;
    req->state = REQ_PENDING;
    req->next = requests;
    requests = req;
    const uint64_t id = req->id;
    reg->calls++;
    mp_mutex_unlock(&lock);

    // Outside the lock: the host may answer synchronously from here.
    reg->fn(reg->user_data, id, op, stream ? stream->id : 0, data, arg);

    mp_mutex_lock(&lock);
    end_call(reg);
    while (req->state != REQ_DONE && !abandoned(req))
        mp_cond_wait(&wakeup, &lock);
    const bool done = req->state == REQ_DONE;
    const int64_t result = done ? req->result : MPV_ERROR_GENERIC;
    if (aux)
        *aux = done ? req->aux : -1;
    unlink_request(req);
    mp_mutex_unlock(&lock);
    free(req);
    return result;
}

static int64_t bridge_read(void *cookie, char *buf, uint64_t nbytes)
{
    struct bridge_stream *s = cookie;
    int64_t n = call_host(s->reg, s, MPV_KIT_STREAM_READ, buf,
                          (int64_t)nbytes, NULL);
    // The read API only knows -1 for errors; clamp a broken host reply.
    if (n < 0 || (uint64_t)n > nbytes)
        return -1;
    return n;
}

static int64_t bridge_seek(void *cookie, int64_t offset)
{
    struct bridge_stream *s = cookie;
    int64_t pos = call_host(s->reg, s, MPV_KIT_STREAM_SEEK, NULL, offset, NULL);
    return pos < 0 ? (pos == MPV_ERROR_UNSUPPORTED ? pos : MPV_ERROR_GENERIC)
                   : pos;
}

static int64_t bridge_size(void *cookie)
{
    struct bridge_stream *s = cookie;
    return s->size >= 0 ? s->size : MPV_ERROR_UNSUPPORTED;
}

static void bridge_cancel(void *cookie)
{
    struct bridge_stream *s = cookie;
    mp_mutex_lock(&lock);
    s->cancelled = true;
    mp_cond_broadcast(&wakeup);
    mp_mutex_unlock(&lock);
}

static void bridge_close(void *cookie)
{
    struct bridge_stream *s = cookie;
    struct registration *reg = s->reg;
    mp_mutex_lock(&lock);
    const bool notify = !reg->shutdown;
    if (notify)
        reg->calls++; // keeps shutdown from returning during the call
    mp_mutex_unlock(&lock);
    if (notify) {
        reg->fn(reg->user_data, 0, MPV_KIT_STREAM_CLOSE, s->id, NULL, 0);
        mp_mutex_lock(&lock);
        end_call(reg);
        mp_mutex_unlock(&lock);
    }
    free(s);
}

static int bridge_open(void *user_data, char *uri, mpv_stream_cb_info *info)
{
    struct registration *reg = user_data;
    int64_t size = -1;
    int64_t id = call_host(reg, NULL, MPV_KIT_STREAM_OPEN, uri, 0, &size);
    if (id <= 0)
        return MPV_ERROR_LOADING_FAILED;
    struct bridge_stream *s = calloc(1, sizeof(*s));
    if (!s)
        return MPV_ERROR_NOMEM;
    s->reg = reg;
    s->id = (uint64_t)id;
    s->size = size;
    info->cookie = s;
    info->read_fn = bridge_read;
    info->seek_fn = bridge_seek;
    info->size_fn = bridge_size;
    info->close_fn = bridge_close;
    info->cancel_fn = bridge_cancel;
    return 0;
}

int mpv_kit_stream_add(mpv_handle *ctx, const char *protocol,
                       mpv_kit_stream_request_fn request_fn, void *user_data,
                       uint64_t *out_registration)
{
    if (!ctx || !protocol || !request_fn || !out_registration)
        return MPV_ERROR_INVALID_PARAMETER;
    struct registration *reg = calloc(1, sizeof(*reg));
    if (!reg)
        return MPV_ERROR_NOMEM;
    reg->fn = request_fn;
    reg->user_data = user_data;
    mp_mutex_lock(&lock);
    reg->id = next_id++;
    mp_mutex_unlock(&lock);
    int err = mpv_stream_cb_add_ro(ctx, protocol, reg, bridge_open);
    if (err < 0) {
        free(reg);
        return err;
    }
    // mpv keeps user_data until the core is destroyed, and the bridge cannot
    // observe that, so registrations are never freed (a few bytes each).
    mp_mutex_lock(&lock);
    reg->next = registrations;
    registrations = reg;
    mp_mutex_unlock(&lock);
    *out_registration = reg->id;
    return 0;
}

int mpv_kit_stream_begin(uint64_t request)
{
    mp_mutex_lock(&lock);
    struct request *req = find_request(request);
    int ok = req && req->state == REQ_PENDING && !abandoned(req);
    if (ok)
        req->state = REQ_BEGUN;
    mp_mutex_unlock(&lock);
    return ok;
}

void mpv_kit_stream_complete(uint64_t request, int64_t result, int64_t aux)
{
    mp_mutex_lock(&lock);
    struct request *req = find_request(request);
    if (req && req->state != REQ_DONE) {
        req->state = REQ_DONE;
        req->result = result;
        req->aux = aux;
        mp_cond_broadcast(&wakeup);
    }
    mp_mutex_unlock(&lock);
}

void mpv_kit_stream_shutdown(uint64_t registration)
{
    mp_mutex_lock(&lock);
    for (struct registration *r = registrations; r; r = r->next) {
        if (r->id == registration)
            r->shutdown = true;
    }
    mp_cond_broadcast(&wakeup);
    // request_fn must never run after we return: wait out calls in flight
    // (they only enqueue, so this is brief).
    for (struct registration *r = registrations; r; r = r->next) {
        while (r->id == registration && r->calls > 0)
            mp_cond_wait(&wakeup, &lock);
    }
    mp_mutex_unlock(&lock);
}

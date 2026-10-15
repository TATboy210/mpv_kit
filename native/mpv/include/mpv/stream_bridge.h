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

#ifndef MPV_CLIENT_API_STREAM_BRIDGE_H_
#define MPV_CLIENT_API_STREAM_BRIDGE_H_

#include "client.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Asynchronous custom streams (mpv_kit extension).
 * ================================================
 *
 * mpv_stream_cb_add_ro() needs callbacks that answer synchronously on mpv's
 * demuxer thread. Hosts that can only be called asynchronously (a Dart
 * isolate through NativeCallable.listener, a JavaScript event loop, ...)
 * register a protocol here instead. Every stream operation becomes a
 * request: the bridge posts it to request_fn and blocks the mpv thread until
 * the host answers with mpv_kit_stream_complete().
 *
 * Buffer lifetime: for MPV_KIT_STREAM_READ, data points into mpv's buffer.
 * The host calls mpv_kit_stream_begin() first; if it returns 1 the mpv
 * thread keeps waiting (and the buffer stays valid) until the matching
 * mpv_kit_stream_complete(), even if the stream is cancelled meanwhile.
 * Only mpv_kit_stream_shutdown() releases begun requests early: after it
 * returns, the host must not touch any request buffer again.
 *
 * request_fn is never called after mpv_kit_stream_shutdown() returns.
 */

typedef enum mpv_kit_stream_op {
    /** data: the URI (char*). Reply: result = stream id > 0 (or < 0 to
     *  fail), aux = size in bytes (or < 0 if unknown). */
    MPV_KIT_STREAM_OPEN = 1,
    /** data: buffer, arg: capacity. Reply: bytes read, 0 at EOF, < 0 error. */
    MPV_KIT_STREAM_READ = 2,
    /** arg: absolute offset. Reply: new offset, or MPV_ERROR_UNSUPPORTED. */
    MPV_KIT_STREAM_SEEK = 3,
    /** No reply expected (request is 0). */
    MPV_KIT_STREAM_CLOSE = 4,
} mpv_kit_stream_op;

/**
 * Called from mpv threads; must not block. [stream] is 0 for OPEN.
 */
typedef void (*mpv_kit_stream_request_fn)(void *user_data, uint64_t request,
                                          int op, uint64_t stream, void *data,
                                          int64_t arg);

/**
 * Registers [protocol] (e.g. "dart" for dart:// URIs) on ctx's core.
 * [out_registration] receives the handle for mpv_kit_stream_shutdown().
 * The registration stays valid until the process exits.
 */
MPV_EXPORT int mpv_kit_stream_add(mpv_handle *ctx, const char *protocol,
                                  mpv_kit_stream_request_fn request_fn,
                                  void *user_data,
                                  uint64_t *out_registration);

/** Claims [request] before using its buffer: 1 = proceed, 0 = abandoned. */
MPV_EXPORT int mpv_kit_stream_begin(uint64_t request);

/** Answers [request]; ignored if the request no longer exists. */
MPV_EXPORT void mpv_kit_stream_complete(uint64_t request, int64_t result,
                                        int64_t aux);

/**
 * Fails every pending and future request of [registration] immediately.
 * Call before destroying the core or invalidating request_fn.
 */
MPV_EXPORT void mpv_kit_stream_shutdown(uint64_t registration);

#ifdef __cplusplus
}
#endif

#endif

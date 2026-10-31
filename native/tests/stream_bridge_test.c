// stream_bridge test: exercises the asynchronous custom-stream bridge
// (include/mpv/stream_bridge.h) through the public client API only.
//
//  1. "membridge://" serves a small in-memory WAV. request_fn only enqueues;
//     a separate host thread answers every request (mpv_kit_stream_begin +
//     mpv_kit_stream_complete), like a Dart isolate would. Playback must
//     reach MPV_EVENT_END_FILE with reason EOF and no error.
//     Every successful OPEN must be followed by exactly one CLOSE.
//  2. A host that rejects OPEN (id <= 0) makes the load fail cleanly.
//  3. loadfile + immediate stop, repeated: the stop cancel races the stream
//     close (the cancel-after-close use-after-free shows up under ASan).
//  4. "pending://" never answers. While mpv's demuxer thread is blocked on
//     the OPEN request, mpv_kit_stream_shutdown() must release it (load
//     fails cleanly), request_fn must never run afterwards, and stale
//     request ids must be ignored.
//
// Runs headless (vo=null, ao=null); meant to run under ASan/UBSan too.
// Exit codes: 0 pass, 1 failure.

#define _POSIX_C_SOURCE 200809L
#include <inttypes.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <mpv/client.h>
#include <mpv/stream_bridge.h>

// --- Minimal portable threading (Win32 or pthreads) ------------------------
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
typedef CRITICAL_SECTION t_mutex;
typedef CONDITION_VARIABLE t_cond;
typedef HANDLE t_thread;
static void mutex_init(t_mutex *m) { InitializeCriticalSection(m); }
static void mutex_destroy(t_mutex *m) { DeleteCriticalSection(m); }
static void mutex_lock(t_mutex *m) { EnterCriticalSection(m); }
static void mutex_unlock(t_mutex *m) { LeaveCriticalSection(m); }
static void cond_init(t_cond *c) { InitializeConditionVariable(c); }
static void cond_destroy(t_cond *c) { (void)c; }
static void cond_signal(t_cond *c) { WakeAllConditionVariable(c); }
static void cond_wait(t_cond *c, t_mutex *m) { SleepConditionVariableCS(c, m, INFINITE); }
// Waits at most [ms]; spurious wakeups are handled by the callers' loops.
static void cond_wait_ms(t_cond *c, t_mutex *m, int ms) { SleepConditionVariableCS(c, m, (DWORD)ms); }
static void (*thread_entry)(void);
static DWORD WINAPI thread_trampoline(LPVOID arg) { (void)arg; thread_entry(); return 0; }
static bool thread_start(t_thread *t, void (*fn)(void))
{
    thread_entry = fn;
    *t = CreateThread(NULL, 0, thread_trampoline, NULL, 0, NULL);
    return *t != NULL;
}
static void thread_join(t_thread t) { WaitForSingleObject(t, INFINITE); CloseHandle(t); }
#else
#include <pthread.h>
#include <time.h>
typedef pthread_mutex_t t_mutex;
typedef pthread_cond_t t_cond;
typedef pthread_t t_thread;
static void mutex_init(t_mutex *m) { pthread_mutex_init(m, NULL); }
static void mutex_destroy(t_mutex *m) { pthread_mutex_destroy(m); }
static void mutex_lock(t_mutex *m) { pthread_mutex_lock(m); }
static void mutex_unlock(t_mutex *m) { pthread_mutex_unlock(m); }
static void cond_init(t_cond *c) { pthread_cond_init(c, NULL); }
static void cond_destroy(t_cond *c) { pthread_cond_destroy(c); }
static void cond_signal(t_cond *c) { pthread_cond_broadcast(c); }
static void cond_wait(t_cond *c, t_mutex *m) { pthread_cond_wait(c, m); }
static void cond_wait_ms(t_cond *c, t_mutex *m, int ms)
{
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    ts.tv_sec += ms / 1000;
    ts.tv_nsec += (long)(ms % 1000) * 1000000L;
    if (ts.tv_nsec >= 1000000000L) {
        ts.tv_sec++;
        ts.tv_nsec -= 1000000000L;
    }
    pthread_cond_timedwait(c, m, &ts);
}
static void (*thread_entry)(void);
static void *thread_trampoline(void *arg) { (void)arg; thread_entry(); return NULL; }
static bool thread_start(t_thread *t, void (*fn)(void))
{
    thread_entry = fn;
    return pthread_create(t, NULL, thread_trampoline, NULL) == 0;
}
static void thread_join(t_thread t) { pthread_join(t, NULL); }
#endif

#define FAIL(...) do { fprintf(stderr, "FAIL: " __VA_ARGS__); fputc('\n', stderr); return 1; } while (0)
static void step(const char *what) { fprintf(stderr, "[stream_bridge] %s\n", what); }

// --- In-memory WAV ----------------------------------------------------------
#define WAV_RATE 8000
#define WAV_SAMPLES (WAV_RATE / 4)          // 250 ms of mono s16
#define WAV_DATA_BYTES (WAV_SAMPLES * 2)
#define WAV_BYTES (44 + WAV_DATA_BYTES)
static unsigned char wav[WAV_BYTES];

static void put_le(unsigned char *p, uint32_t v, int n)
{
    for (int i = 0; i < n; i++)
        p[i] = (unsigned char)(v >> (8 * i));
}

static void make_wav(void)
{
    unsigned char *h = wav;
    memcpy(h, "RIFF", 4);       put_le(h + 4, WAV_BYTES - 8, 4);
    memcpy(h + 8, "WAVEfmt ", 8); put_le(h + 16, 16, 4);
    put_le(h + 20, 1, 2);       // PCM
    put_le(h + 22, 1, 2);       // mono
    put_le(h + 24, WAV_RATE, 4);
    put_le(h + 28, WAV_RATE * 2, 4);
    put_le(h + 32, 2, 2);       // block align
    put_le(h + 34, 16, 2);      // bits per sample
    memcpy(h + 36, "data", 4);  put_le(h + 40, WAV_DATA_BYTES, 4);
    // Square wave so the payload is not trivially all zeros.
    for (int i = 0; i < WAV_SAMPLES; i++) {
        int16_t s = (i / 20) % 2 ? 4000 : -4000;
        put_le(h + 44 + 2 * i, (uint16_t)s, 2);
    }
}

// --- Host side: request queue answered by a separate thread ----------------
struct pending_req {
    uint64_t id;
    int op;
    uint64_t stream;
    void *data;
    int64_t arg;
    bool uri_ok;   // OPEN: URI checked in request_fn (data dies with the request)
};

#define QUEUE_CAP 64
#define MAX_STREAMS 32
static t_mutex host_lock;
static t_cond host_cond;
static struct pending_req queue[QUEUE_CAP];
static int queue_len;
static bool host_quit;
static bool queue_overflow;
static int64_t stream_pos[MAX_STREAMS];   // indexed by host stream id
static bool stream_open[MAX_STREAMS];
static uint64_t next_stream = 1;
static int opens, reads;
static int closes;
static int64_t bytes_served;

static void mem_request(void *user_data, uint64_t request, int op,
                        uint64_t stream, void *data, int64_t arg)
{
    (void)user_data;
    mutex_lock(&host_lock);
    if (op == MPV_KIT_STREAM_CLOSE) {
        // No reply expected; bookkeeping only (must not block).
        if (stream > 0 && stream < MAX_STREAMS)
            stream_open[stream] = false;
        closes++;
    } else if (queue_len < QUEUE_CAP) {
        // The OPEN URI may be freed as soon as the request is released, so
        // inspect it now instead of on the host thread.
        const bool uri_ok = op == MPV_KIT_STREAM_OPEN && data &&
                            strncmp(data, "membridge://", 12) == 0;
        queue[queue_len++] = (struct pending_req){ request, op, stream, data, arg, uri_ok };
        cond_signal(&host_cond);
    } else {
        queue_overflow = true;
    }
    mutex_unlock(&host_lock);
}

// Answers one request outside host_lock (mirrors an async host).
static void answer(const struct pending_req *r)
{
    switch (r->op) {
    case MPV_KIT_STREAM_OPEN: {
        int64_t id = -1;
        mutex_lock(&host_lock);
        if (r->uri_ok && next_stream < MAX_STREAMS) {
            id = (int64_t)next_stream++;
            stream_pos[id] = 0;
            stream_open[id] = true;
            opens++;
        }
        mutex_unlock(&host_lock);
        mpv_kit_stream_complete(r->id, id, WAV_BYTES);
        break;
    }
    case MPV_KIT_STREAM_READ: {
        if (!mpv_kit_stream_begin(r->id))
            return; // abandoned: the buffer must not be touched
        int64_t n = -1;
        mutex_lock(&host_lock);
        if (r->stream > 0 && r->stream < MAX_STREAMS && stream_open[r->stream]) {
            int64_t pos = stream_pos[r->stream];
            n = WAV_BYTES - pos;
            if (n > r->arg)
                n = r->arg;
            if (n < 0)
                n = 0;
            memcpy(r->data, wav + pos, (size_t)n);
            stream_pos[r->stream] = pos + n;
            reads++;
            bytes_served += n;
        }
        mutex_unlock(&host_lock);
        mpv_kit_stream_complete(r->id, n, 0);
        break;
    }
    case MPV_KIT_STREAM_SEEK: {
        int64_t res = MPV_ERROR_GENERIC;
        mutex_lock(&host_lock);
        if (r->stream > 0 && r->stream < MAX_STREAMS && stream_open[r->stream] &&
            r->arg >= 0 && r->arg <= WAV_BYTES) {
            stream_pos[r->stream] = r->arg;
            res = r->arg;
        }
        mutex_unlock(&host_lock);
        mpv_kit_stream_complete(r->id, res, 0);
        break;
    }
    default:
        mpv_kit_stream_complete(r->id, MPV_ERROR_UNSUPPORTED, 0);
    }
}

static void host_thread(void)
{
    mutex_lock(&host_lock);
    for (;;) {
        while (!queue_len && !host_quit)
            cond_wait(&host_cond, &host_lock);
        if (!queue_len && host_quit)
            break;
        struct pending_req r = queue[0];
        memmove(queue, queue + 1, (size_t)(queue_len - 1) * sizeof(queue[0]));
        queue_len--;
        mutex_unlock(&host_lock);
        answer(&r);
        mutex_lock(&host_lock);
    }
    mutex_unlock(&host_lock);
}

// --- "pending://": requests are recorded but never answered ----------------
static uint64_t pending_request;   // last request id seen
static volatile int pending_calls;  // observed in a debugger only
static bool pending_shutdown_done; // set after mpv_kit_stream_shutdown returned
static int pending_late_calls;     // request_fn calls after shutdown (must be 0)

static void pending_request_fn(void *user_data, uint64_t request, int op,
                               uint64_t stream, void *data, int64_t arg)
{
    (void)user_data; (void)op; (void)stream; (void)data; (void)arg;
    mutex_lock(&host_lock);
    if (pending_shutdown_done)
        pending_late_calls++;
    if (request)
        pending_request = request;
    pending_calls++;
    cond_signal(&host_cond);
    mutex_unlock(&host_lock);
}

// --- mpv helpers -----------------------------------------------------------
// Waits for the next END_FILE; *loaded tells whether FILE_LOADED preceded it.
static int wait_end_file(mpv_handle *mpv, double timeout_s,
                         mpv_event_end_file *out, bool *loaded)
{
    const int64_t deadline = mpv_get_time_us(mpv) + (int64_t)(timeout_s * 1e6);
    if (loaded)
        *loaded = false;
    while (mpv_get_time_us(mpv) < deadline) {
        mpv_event *ev = mpv_wait_event(mpv, 0.25);
        if (ev->event_id == MPV_EVENT_LOG_MESSAGE) {
            mpv_event_log_message *m = ev->data;
            fprintf(stderr, "  mpv[%s] %s: %s", m->level, m->prefix, m->text);
        } else if (ev->event_id == MPV_EVENT_FILE_LOADED) {
            if (loaded)
                *loaded = true;
        } else if (ev->event_id == MPV_EVENT_END_FILE) {
            *out = *(mpv_event_end_file *)ev->data;
            return 0;
        } else if (ev->event_id == MPV_EVENT_SHUTDOWN) {
            return -1;
        }
    }
    return -1;
}

// Waits for the next START_FILE (playback of the entry has begun, so a later
// stop is guaranteed to end it with END_FILE).
static int wait_start_file(mpv_handle *mpv, double timeout_s)
{
    const int64_t deadline = mpv_get_time_us(mpv) + (int64_t)(timeout_s * 1e6);
    while (mpv_get_time_us(mpv) < deadline) {
        mpv_event *ev = mpv_wait_event(mpv, 0.25);
        if (ev->event_id == MPV_EVENT_LOG_MESSAGE) {
            mpv_event_log_message *m = ev->data;
            fprintf(stderr, "  mpv[%s] %s: %s", m->level, m->prefix, m->text);
        }
        if (ev->event_id == MPV_EVENT_START_FILE)
            return 0;
        if (ev->event_id == MPV_EVENT_SHUTDOWN)
            return -1;
    }
    return -1;
}

static int loadfile(mpv_handle *mpv, const char *url)
{
    const char *cmd[] = { "loadfile", url, NULL };
    return mpv_command(mpv, cmd);
}

// Waits until every opened membridge stream was closed (the CLOSE request can
// trail END_FILE slightly); returns whether opens == closes.
static bool closes_balanced(void)
{
    bool balanced = false;
    mutex_lock(&host_lock);
    for (int i = 0; i < 50 && !(balanced = opens == closes); i++)
        cond_wait_ms(&host_cond, &host_lock, 100);
    mutex_unlock(&host_lock);
    return balanced;
}

int main(void)
{
    setvbuf(stdout, NULL, _IONBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);
    make_wav();
    mutex_init(&host_lock);
    cond_init(&host_cond);

    mpv_handle *mpv = mpv_create();
    if (!mpv)
        FAIL("mpv_create");
    mpv_set_option_string(mpv, "vo", "null");
    mpv_set_option_string(mpv, "ao", "null");
    mpv_set_option_string(mpv, "ao-null-untimed", "yes");
    mpv_set_option_string(mpv, "idle", "yes");
    mpv_set_option_string(mpv, "demuxer-lavf-format", "wav");
    if (mpv_initialize(mpv) < 0)
        FAIL("mpv_initialize");
    mpv_request_log_messages(mpv, "warn");

    t_thread host;
    if (!thread_start(&host, host_thread))
        FAIL("host thread");

    // --- 1. playback through an asynchronously answered stream -------------
    step("register membridge");
    uint64_t mem_reg = 0;
    int err = mpv_kit_stream_add(mpv, "membridge", mem_request, NULL, &mem_reg);
    if (err < 0)
        FAIL("mpv_kit_stream_add(membridge): %s", mpv_error_string(err));
    if (mpv_kit_stream_add(mpv, NULL, mem_request, NULL, &mem_reg) !=
        MPV_ERROR_INVALID_PARAMETER)
        FAIL("mpv_kit_stream_add accepted a NULL protocol");

    step("play membridge://tone.wav");
    if ((err = loadfile(mpv, "membridge://tone.wav")) < 0)
        FAIL("loadfile: %s", mpv_error_string(err));
    mpv_event_end_file ef;
    bool loaded = false;
    if (wait_end_file(mpv, 20.0, &ef, &loaded) < 0)
        FAIL("timeout waiting for END_FILE (membridge)");
    mutex_lock(&host_lock);
    const int o = opens, r = reads;
    const int64_t served = bytes_served;
    const bool overflow = queue_overflow;
    mutex_unlock(&host_lock);
    fprintf(stderr, "[stream_bridge] reason=%d error=%d loaded=%d opens=%d reads=%d bytes=%" PRId64 "\n",
            (int)ef.reason, ef.error, (int)loaded, o, r, served);
    if (overflow)
        FAIL("host request queue overflowed");
    if (ef.reason != MPV_END_FILE_REASON_EOF || ef.error != 0)
        FAIL("membridge playback ended with reason %d error %s", (int)ef.reason,
             mpv_error_string(ef.error));
    if (!loaded || o < 1 || r < 1 || served <= 44)
        FAIL("membridge stream was not actually played");
    if (!closes_balanced())
        FAIL("membridge: %d open(s) but %d close(s)", opens, closes);

    // --- 2. host rejects OPEN ----------------------------------------------
    // mem_request only accepts membridge:// URIs; answer() replies id -1.
    step("rejected OPEN fails the load");
    uint64_t rej_reg = 0;
    if ((err = mpv_kit_stream_add(mpv, "rejectbridge", mem_request, NULL, &rej_reg)) < 0)
        FAIL("mpv_kit_stream_add(rejectbridge): %s", mpv_error_string(err));
    if ((err = loadfile(mpv, "rejectbridge://x.wav")) < 0)
        FAIL("loadfile: %s", mpv_error_string(err));
    if (wait_end_file(mpv, 20.0, &ef, &loaded) < 0)
        FAIL("timeout waiting for END_FILE (rejectbridge)");
    if (ef.reason != MPV_END_FILE_REASON_ERROR || loaded)
        FAIL("rejected open should fail, got reason %d loaded %d", (int)ef.reason, (int)loaded);
    if (!closes_balanced())
        FAIL("rejected open: %d open(s) but %d close(s)", opens, closes);

    // --- 3. stop races the stream close ------------------------------------
    step("loadfile + stop loop");
    const char *stop_cmd[] = { "stop", NULL };
    // Host stream ids are never recycled (MAX_STREAMS caps them), so keep the
    // loop short enough to leave ids for the playbacks that follow.
    for (int i = 0; i < 10; i++) {
        if ((err = loadfile(mpv, "membridge://stop.wav")) < 0)
            FAIL("loadfile: %s", mpv_error_string(err));
        // A stop processed before the entry starts would clear the playlist
        // without any END_FILE; start first, then stop while it opens/reads.
        if (wait_start_file(mpv, 20.0) < 0)
            FAIL("timeout waiting for START_FILE (stop loop %d)", i);
        if ((err = mpv_command(mpv, stop_cmd)) < 0)
            FAIL("stop: %s", mpv_error_string(err));
        if (wait_end_file(mpv, 20.0, &ef, &loaded) < 0)
            FAIL("timeout waiting for END_FILE (stop loop %d)", i);
    }
    if (!closes_balanced())
        FAIL("stop loop: %d open(s) but %d close(s)", opens, closes);
    mutex_lock(&host_lock);
    const int used = opens;
    mutex_unlock(&host_lock);
    if (used > MAX_STREAMS - 4)
        FAIL("stop loop used %d of %d host stream ids", used, MAX_STREAMS - 1);

    // --- 4. shutdown while a request is pending ----------------------------
    step("register pending");
    uint64_t pend_reg = 0;
    if ((err = mpv_kit_stream_add(mpv, "pending", pending_request_fn, NULL, &pend_reg)) < 0)
        FAIL("mpv_kit_stream_add(pending): %s", mpv_error_string(err));
    if (pend_reg == mem_reg)
        FAIL("registration ids are not unique");

    step("load pending://never and wait for the OPEN request");
    if ((err = loadfile(mpv, "pending://never")) < 0)
        FAIL("loadfile: %s", mpv_error_string(err));
    mutex_lock(&host_lock);
    for (int i = 0; i < 200 && !pending_request; i++)
        cond_wait_ms(&host_cond, &host_lock, 100);
    const uint64_t stale = pending_request;
    mutex_unlock(&host_lock);
    if (!stale)
        FAIL("pending:// OPEN request never arrived");

    step("mpv_kit_stream_shutdown while the request is pending");
    mpv_kit_stream_shutdown(pend_reg);
    mutex_lock(&host_lock);
    pending_shutdown_done = true;
    mutex_unlock(&host_lock);
    if (wait_end_file(mpv, 20.0, &ef, &loaded) < 0)
        FAIL("timeout: shutdown did not release the pending request");
    if (ef.reason != MPV_END_FILE_REASON_ERROR || loaded)
        FAIL("pending load should fail, got reason %d loaded %d", (int)ef.reason, (int)loaded);

    // Stale ids must be ignored (the request object is gone).
    if (mpv_kit_stream_begin(stale) != 0)
        FAIL("mpv_kit_stream_begin accepted a released request");
    mpv_kit_stream_complete(stale, 1, 0);
    mpv_kit_stream_shutdown(pend_reg); // idempotent

    step("load after shutdown fails without calling request_fn");
    if ((err = loadfile(mpv, "pending://again")) < 0)
        FAIL("loadfile: %s", mpv_error_string(err));
    if (wait_end_file(mpv, 20.0, &ef, &loaded) < 0)
        FAIL("timeout after shutdown");
    if (ef.reason != MPV_END_FILE_REASON_ERROR)
        FAIL("load after shutdown should fail, got reason %d", (int)ef.reason);
    mutex_lock(&host_lock);
    const int late = pending_late_calls;
    mutex_unlock(&host_lock);
    if (late)
        FAIL("request_fn ran %d time(s) after mpv_kit_stream_shutdown", late);

    // The other registration is unaffected by shutting down "pending".
    step("membridge still works after the other registration shut down");
    if ((err = loadfile(mpv, "membridge://again.wav")) < 0)
        FAIL("loadfile: %s", mpv_error_string(err));
    if (wait_end_file(mpv, 20.0, &ef, &loaded) < 0)
        FAIL("timeout waiting for END_FILE (membridge again)");
    if (ef.reason != MPV_END_FILE_REASON_EOF || ef.error != 0 || !loaded)
        FAIL("second membridge playback: reason %d error %s", (int)ef.reason,
             mpv_error_string(ef.error));

    // --- teardown: stop the host (it may hold begun request buffers), then
    // release anything still pending, then destroy the core.
    step("teardown");
    mutex_lock(&host_lock);
    host_quit = true;
    cond_signal(&host_cond);
    mutex_unlock(&host_lock);
    thread_join(host);
    mpv_kit_stream_shutdown(mem_reg);
    mpv_kit_stream_shutdown(rej_reg);
    mpv_terminate_destroy(mpv);
    cond_destroy(&host_cond);
    mutex_destroy(&host_lock);
    step("PASS");
    return 0;
}

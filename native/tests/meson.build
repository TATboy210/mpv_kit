project('mpv_kit_native_tests', ['c', 'cpp'],
        default_options: ['c_std=c11', 'cpp_std=c++17', 'warning_level=3',
                          'werror=true'])

# Links against the libmpv built from ../mpv (found via pkg-config).
mpv = dependency('mpv', version: '>= 2.5')
vulkan = dependency('vulkan')
threads = dependency('threads')

smoke = executable('render_vk_smoke', 'render_vk_smoke.c',
                   dependencies: [mpv, vulkan, threads])
test('render_vk_smoke', smoke, timeout: 60)  # gpu-next (default)
test('render_vk_smoke_gpu', smoke, args: ['gpu'], timeout: 60)

# Asynchronous custom-stream bridge (include/mpv/stream_bridge.h): playback
# through a host thread that answers requests, plus shutdown while pending.
bridge = executable('stream_bridge_test', 'stream_bridge_test.c',
                    dependencies: [mpv, threads])
test('stream_bridge', bridge, timeout: 90)

# --- Renderer golden tests ---------------------------------------------------
#
# The shared plugin renderer (packages/mpv_kit_video/src), compiled from the
# same sources as the Windows/Linux plugin CMake builds and driven by a fake
# libmpv (renderer_harness.h). Neither libmpv nor a Vulkan loader is linked:
# volk resolves the loader at runtime, and the software golden never asks it.
# The sources live outside this project's source root, which meson allows
# for plain files and include directories.
plugin = '../../packages/mpv_kit_video'

renderer_defines = ['-DVK_NO_PROTOTYPES']
if host_machine.system() == 'windows'
  renderer_defines += ['-DWIN32_LEAN_AND_MEAN', '-DNOMINMAX']
endif

vulkan_inc = include_directories(plugin / 'third_party/vulkan-headers/include',
                                 plugin / 'third_party/volk')

# Third-party C, built without our warning flags (as in the plugin builds).
volk = static_library('mpv_kit_volk', plugin / 'third_party/volk/volk.c',
                      include_directories: vulkan_inc,
                      c_args: renderer_defines,
                      dependencies: dependency('dl', required: false),
                      override_options: ['warning_level=0', 'werror=false'])

renderer_inc = include_directories(plugin / 'src', plugin / 'src/include')

# Must list the shared sources of packages/mpv_kit_video/{windows,linux}/
# CMakeLists.txt: the golden tests the code the plugin compiles. -Wall
# -Werror, the strength of the plugin builds.
renderer = static_library('mpv_kit_renderer',
                          [plugin / 'src/video_renderer.cc',
                           plugin / 'src/vulkan_backend.cc'],
                          include_directories: [renderer_inc, vulkan_inc],
                          cpp_args: renderer_defines,
                          link_with: volk,
                          dependencies: threads,
                          override_options: ['warning_level=1'])

# Upper tolerance of timing expectations: sanitizer builds run several times
# slower. b_sanitize is a combo string on older meson and an array on newer;
# formatting it covers both.
sanitize = '@0@'.format(get_option('b_sanitize'))
slack = (sanitize.contains('address') or sanitize.contains('undefined')
         or sanitize.contains('thread')) ? '1000' : '250'

golden_sw = executable('video_renderer_golden_sw',
                       'video_renderer_golden_sw.cc',
                       include_directories: [renderer_inc, vulkan_inc],
                       cpp_args: renderer_defines,
                       link_with: renderer,
                       dependencies: threads)
test('video_renderer_golden_sw', golden_sw,
     args: [files('golden/sw.txt'), '--slack-ms=' + slack], timeout: 120)

# Vulkan path: the real VulkanContext on the runner's Vulkan 1.3 device
# (lavapipe / MoltenVK), images from a fake platform interop. Exits 77
# (skipped) with `GOLDEN skip:` only when no loader, instance or Vulkan 1.3
# device exists. volk dlopens the loader by its plain name; Homebrew's
# libdir is not on macOS's default search path, so the loader's pkg-config
# libdir is added to the fallback path rather than letting macOS skip.
golden_vk_env = environment()
if host_machine.system() == 'darwin'
  vulkan_libdir = vulkan.get_variable(pkgconfig: 'libdir', default_value: '')
  if vulkan_libdir != ''
    golden_vk_env.prepend('DYLD_FALLBACK_LIBRARY_PATH', vulkan_libdir)
  endif
endif
golden_vk = executable('video_renderer_golden_vk',
                       'video_renderer_golden_vk.cc',
                       include_directories: [renderer_inc, vulkan_inc],
                       cpp_args: renderer_defines,
                       link_with: renderer,
                       dependencies: threads)
test('video_renderer_golden_vk', golden_vk,
     args: [files('golden/vk.txt'), '--slack-ms=' + slack],
     env: golden_vk_env, timeout: 120)

# Ring fallback after a resize (latency 4): a separate binary because the
# golden_vk set above is frozen. Same device, probe and skip semantics.
golden_vk_fallback = executable('video_renderer_golden_vk_fallback',
                                'video_renderer_golden_vk_fallback.cc',
                                include_directories: [renderer_inc, vulkan_inc],
                                cpp_args: renderer_defines,
                                link_with: renderer,
                                dependencies: threads)
test('video_renderer_golden_vk_fallback', golden_vk_fallback,
     args: [files('golden/vk_fallback.txt'), '--slack-ms=' + slack],
     env: golden_vk_env, timeout: 120)

# A resize that follows a resize without a frame (the retired front of two
# generations ago): separate binaries because the golden set above is
# frozen. The Vulkan one has golden_vk's device, probe and skip semantics;
# the software one runs everywhere, like golden_sw.
golden_vk_retire_twice = executable('video_renderer_golden_vk_retire_twice',
                                    'video_renderer_golden_vk_retire_twice.cc',
                                    include_directories: [renderer_inc,
                                                          vulkan_inc],
                                    cpp_args: renderer_defines,
                                    link_with: renderer,
                                    dependencies: threads)
test('video_renderer_golden_vk_retire_twice', golden_vk_retire_twice,
     args: [files('golden/vk_retire_twice.txt'), '--slack-ms=' + slack],
     env: golden_vk_env, timeout: 120)
golden_sw_retire_twice = executable('video_renderer_golden_sw_retire_twice',
                                    'video_renderer_golden_sw_retire_twice.cc',
                                    include_directories: [renderer_inc,
                                                          vulkan_inc],
                                    cpp_args: renderer_defines,
                                    link_with: renderer,
                                    dependencies: threads)
test('video_renderer_golden_sw_retire_twice', golden_sw_retire_twice,
     args: [files('golden/sw_retire_twice.txt'), '--slack-ms=' + slack],
     timeout: 120)

# The software frame of the last AcquireFront() stays valid until the next
# one (video_renderer.h), across a second reallocation (code review CR-01):
# a separate binary because the golden set above is frozen. It holds the
# frame like a compositor and watches its buffer through its own global
# operator new/delete; it runs everywhere, like golden_sw.
sw_hold_front_test = executable('video_renderer_sw_hold_front_test',
                                'video_renderer_sw_hold_front_test.cc',
                                include_directories: [renderer_inc,
                                                      vulkan_inc],
                                cpp_args: renderer_defines,
                                link_with: renderer,
                                dependencies: threads)
test('video_renderer_sw_hold_front_test', sw_hold_front_test,
     args: ['--slack-ms=' + slack], timeout: 120)

# MPV_KIT_VIDEO_API (ADR 0004 Decision 4): a separate binary because the
# golden set above is frozen. Its scenarios run everywhere except
# api-vulkan, which needs golden_vk's Vulkan 1.3 device and is skipped on
# its own (the binary still passes) without one.
api_test = executable('video_renderer_api_test',
                      'video_renderer_api_test.cc',
                      include_directories: [renderer_inc, vulkan_inc],
                      cpp_args: renderer_defines,
                      link_with: renderer,
                      dependencies: threads)
test('video_renderer_api_test', api_test,
     args: [files('golden/api_override.txt'), '--slack-ms=' + slack],
     env: golden_vk_env, timeout: 120)

# Thread affinity of the mpv_render_* calls (render.h, "Threading"): a
# separate binary because the golden set above is frozen. A raster thread
# takes frames while the test checks, from the fake's call log, that swaps,
# renders, updates, parameters and the final free all run on the render
# thread. The software scenario runs everywhere; the Vulkan one needs
# golden_vk's Vulkan 1.3 device and is skipped on its own without one.
affinity_test = executable('video_renderer_affinity_test',
                           'video_renderer_affinity_test.cc',
                           include_directories: [renderer_inc, vulkan_inc],
                           cpp_args: renderer_defines,
                           link_with: renderer,
                           dependencies: threads)
test('video_renderer_affinity_test', affinity_test, env: golden_vk_env,
     timeout: 120)

# Candidate chain with platform-provided backends (Phase 14, D3D-07): a
# separate binary because the golden set above is frozen. Fake "d3d11" and
# "vulkan" backends behind Interop::CreateBackend prove the interleaved
# candidate order, the device-failure trails and propagation, MPV_KIT_VIDEO_API
# without fallback, and exactly one device_lost event. No Vulkan device or
# libmpv is needed: it runs on every platform and under the sanitizers.
chain_test = executable('video_renderer_chain_test',
                        'video_renderer_chain_test.cc',
                        include_directories: [renderer_inc, vulkan_inc],
                        cpp_args: renderer_defines,
                        link_with: renderer,
                        dependencies: threads)
test('video_renderer_chain_test', chain_test,
     args: [files('golden/chain.txt'), '--slack-ms=' + slack], timeout: 120)

# --- D3D11 render API (Windows only) -------------------------------------------
#
# Renders a red-over-blue lavfi frame through MPV_RENDER_API_TYPE_D3D11 into a
# host texture on whatever D3D11 device exists (WARP on the hosted runners)
# and reads it back. The tests are serial (is_parallel: false): WARP runs the
# shaders on the CPU and parallel renders would only slow each other down and
# make the timeouts flaky. render_vk.h is needed for the renderer
# select/report parameter, hence the Vulkan headers.
if host_machine.system() == 'windows'
  cc = meson.get_compiler('c')
  d3d11_libs = [cc.find_library('d3d11'), cc.find_library('dxgi'),
                cc.find_library('dxguid')]
  d3d11_smoke = executable('render_d3d11_smoke', 'render_d3d11_smoke.c',
                           dependencies: [mpv, vulkan] + d3d11_libs)
  test('render_d3d11_smoke', d3d11_smoke, timeout: 120,  # gpu-next (default)
       is_parallel: false)
  test('render_d3d11_smoke_gpu', d3d11_smoke, args: ['gpu'], timeout: 120,
       is_parallel: false)
  # Persistent shader cache (the compiled DXBC): two runs on one directory;
  # the second must read the first's files and write none of its own.
  test('render_d3d11_smoke_cache', d3d11_smoke,
       args: ['gpu-next',
              '--cache-dir=' + meson.current_build_dir() / 'd3d11-shader-cache'],
       timeout: 240, is_parallel: false)
endif

# --- OpenGL render API (Linux only) ----------------------------------------------
#
# Renders a solid red lavfi frame through MPV_RENDER_API_TYPE_OPENGL into a
# host FBO on a standalone surfaceless EGL context (Mesa llvmpipe on the
# hosted runners) and reads it back; mpv must report the "gpu" renderer. The
# other platforms have no EGL in mpv_kit's chain, so nothing is built there.
# The release and sanitizer jobs run it too. `gl` is desktop OpenGL, `gles`
# OpenGL ES 3; exit 77 (skipped) only without an EGL surfaceless display, a
# context of that API or (gles) libGLESv2.so.2 (package libgles2: epoxy aborts
# without it; the gl variant then reports its handoff as skipped). epoxy is required on Linux (a missing package is a
# configure error, not a silent skip); system include keeps its headers out
# of warning_level=3/werror.
if host_machine.system() == 'linux'
  epoxy = dependency('epoxy', include_type: 'system')
  # dlopen probe for libGLESv2 (in libc since glibc 2.34, libdl before).
  dl = meson.get_compiler('c').find_library('dl', required: false)
  gl_smoke = executable('render_gl_smoke', 'render_gl_smoke.c',
                        dependencies: [mpv, epoxy, vulkan, threads, dl])
  test('render_gl_smoke', gl_smoke, args: ['gl'], timeout: 60)
  test('render_gl_smoke_gles', gl_smoke, args: ['gles'], timeout: 60)
endif

# Linux candidate chain (Phase 15, GLX-04): a separate binary because the
# golden set above is frozen. LinuxBackendCandidates (linux_candidates.h) is
# portable data, so this runs on every platform and under the sanitizers: a
# fake "opengl" backend behind Interop::CreateBackend proves the auto/gpu/
# gpu-next/software chains, the opengl trails, MPV_KIT_VIDEO_API=opengl and
# the honest renderer in the reason head. Its Vulkan scenario needs
# golden_vk's Vulkan 1.3 device and is skipped on its own without one.
linux_chain_test = executable('video_renderer_linux_chain_test',
                              'video_renderer_linux_chain_test.cc',
                              include_directories: [renderer_inc, vulkan_inc],
                              cpp_args: renderer_defines,
                              link_with: renderer,
                              dependencies: threads)
test('video_renderer_linux_chain_test', linux_chain_test,
     args: [files('golden/linux_chain.txt'), '--slack-ms=' + slack],
     env: golden_vk_env, timeout: 120)

# Binding of the mpv_render_* calls to a backend's thread (Phase 15, GLX-03;
# render.h "Threading"): a separate binary because the golden set above is
# frozen. A fake backend with an OpenGL-like thread model (RunBound on a
# thread of its own, a thread-local "context is current" flag) checks every
# mpv_render_* call: create-time calls on the RunBound thread, the rest on the
# render thread, the RunBound thread unbound before the render thread binds,
# one free. Needs no GPU or libmpv: it runs on every platform and under the
# sanitizers.
bind_test = executable('video_renderer_bind_test',
                       'video_renderer_bind_test.cc',
                       include_directories: [renderer_inc, vulkan_inc],
                       cpp_args: renderer_defines,
                       link_with: renderer,
                       dependencies: threads)
test('video_renderer_bind_test', bind_test, timeout: 120)

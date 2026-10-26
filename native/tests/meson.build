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

project('mpv_kit_native_tests', 'c',
        default_options: ['c_std=c11', 'warning_level=3', 'werror=true'])

# Links against the libmpv built from ../mpv (found via pkg-config).
mpv = dependency('mpv', version: '>= 2.5')
vulkan = dependency('vulkan')
threads = dependency('threads')

smoke = executable('render_vk_smoke', 'render_vk_smoke.c',
                   dependencies: [mpv, vulkan, threads])
test('render_vk_smoke', smoke, timeout: 60)

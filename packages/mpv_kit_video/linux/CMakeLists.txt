cmake_minimum_required(VERSION 3.14)
set(PROJECT_NAME "mpv_kit_video")
project(${PROJECT_NAME} LANGUAGES C CXX)

set(PLUGIN_NAME "mpv_kit_video_plugin")

# Vulkan headers + volk (runtime loader): pinned by tag and sha256, same as
# Windows. libvulkan.so.1 is loaded at runtime, so systems without Vulkan
# fall back to the software backend instead of failing to start.
include(FetchContent)
if(POLICY CMP0169)
  cmake_policy(SET CMP0169 OLD)
endif()
if(POLICY CMP0135)
  cmake_policy(SET CMP0135 NEW)
endif()
FetchContent_Declare(vulkan_headers
  URL https://github.com/KhronosGroup/Vulkan-Headers/archive/refs/tags/vulkan-sdk-1.4.363.0.tar.gz
  URL_HASH SHA256=4a078be12bef21cfebc09d878b77a63cff9d68f899254a0b00d0e37ef73e7f7e)
FetchContent_Declare(volk
  URL https://github.com/zeux/volk/archive/refs/tags/vulkan-sdk-1.4.363.0.tar.gz
  URL_HASH SHA256=1547d8d74395d4048fb3f4a6313da56db626e89b55db238d0d7e8944c8a645f3)
FetchContent_GetProperties(vulkan_headers)
if(NOT vulkan_headers_POPULATED)
  FetchContent_Populate(vulkan_headers)
endif()
FetchContent_GetProperties(volk)
if(NOT volk_POPULATED)
  FetchContent_Populate(volk)
endif()

find_package(PkgConfig REQUIRED)
find_package(Threads REQUIRED)
# Flutter's engine already depends on libepoxy for GL/EGL dispatch.
pkg_check_modules(EPOXY REQUIRED IMPORTED_TARGET epoxy)

set(SHARED_SRC "${CMAKE_CURRENT_SOURCE_DIR}/../src")

# Third-party C, built without Flutter's -Wall -Werror settings.
add_library(mpv_kit_volk STATIC "${volk_SOURCE_DIR}/volk.c")
target_include_directories(mpv_kit_volk PUBLIC
  "${vulkan_headers_SOURCE_DIR}/include" "${volk_SOURCE_DIR}")
target_compile_definitions(mpv_kit_volk PUBLIC VK_NO_PROTOTYPES)
set_target_properties(mpv_kit_volk PROPERTIES POSITION_INDEPENDENT_CODE ON)
target_link_libraries(mpv_kit_volk PUBLIC ${CMAKE_DL_LIBS})

add_library(${PLUGIN_NAME} SHARED
  "mpv_kit_video_plugin.cc"
  "gl_interop.cc"
  "${SHARED_SRC}/video_renderer.cc"
  "${SHARED_SRC}/vulkan_backend.cc"
)

apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES CXX_VISIBILITY_PRESET hidden)
target_compile_features(${PLUGIN_NAME} PRIVATE cxx_std_17)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_include_directories(${PLUGIN_NAME} PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
  "${SHARED_SRC}"
  "${SHARED_SRC}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE
  flutter PkgConfig::GTK PkgConfig::EPOXY mpv_kit_volk Threads::Threads)

# libmpv itself is provided by mpv_kit_libs (or MPV_KIT_LIBMPV_PATH).
set(mpv_kit_video_bundled_libraries "" PARENT_SCOPE)

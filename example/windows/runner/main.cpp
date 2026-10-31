#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <cstdio>

#include "flutter_window.h"
#include "utils.h"

namespace {

// SYSTEM_POWER_STATUS::ACLineStatus: 0 offline (battery), 1 online,
// 255 unknown.
constexpr BYTE kAcLineOnline = 1;
constexpr BYTE kAcLineOffline = 0;
// SYSTEM_POWER_STATUS::SystemStatusFlag bit 0: battery saver is on.
constexpr BYTE kBatterySaverOn = 1;

// Hybrid-GPU laptops: the engine picks its adapter once, before any plugin
// registers (Flutter 3.41+, flutter/flutter#177653), and mpv_kit_video
// renders on that adapter. On AC power with battery saver off ask for the
// high-performance GPU; otherwise NoPreference, so that Windows' per-app
// graphics setting decides. Decided once at startup; one line is logged.
flutter::GpuPreference ChooseGpuPreference() {
  SYSTEM_POWER_STATUS status{};
  const bool known = ::GetSystemPowerStatus(&status) != 0;
  const char* why = nullptr;
  if (!known || status.ACLineStatus != kAcLineOnline) {
    why = (known && status.ACLineStatus == kAcLineOffline)
              ? "on battery"
              : "power status unknown";
  } else if (status.SystemStatusFlag & kBatterySaverOn) {
    why = "battery saver on";
  }
  char line[160];
  if (why == nullptr) {
    snprintf(line, sizeof(line),
             "mpv_kit_example: GPU preference high-performance (AC power, "
             "battery saver off)\n");
  } else {
    snprintf(line, sizeof(line),
             "mpv_kit_example: GPU preference none (%s); Windows graphics "
             "settings decide\n",
             why);
  }
  ::OutputDebugStringA(line);
  if (stderr) fputs(line, stderr);
  return why == nullptr ? flutter::GpuPreference::HighPerformancePreference
                        : flutter::GpuPreference::NoPreference;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  // Power-aware choice of the GPU (see ChooseGpuPreference).
  project.set_gpu_preference(ChooseGpuPreference());

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"mpv_kit_example", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}

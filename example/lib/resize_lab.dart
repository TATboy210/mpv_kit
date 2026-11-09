// Resize lab: isolates whether window-edge drag jank comes from mpv_kit or from
// the host window setup. Everything here is opt-in through environment
// variables, so the default example behaves exactly as before.
//
//   MPV_EXAMPLE_FRAMELESS=1  hide the native title bar via nativeapi and draw
//                            a custom one (same window shape as simple_player)
//   MPV_EXAMPLE_VIDEO=0      do not mount MpvVideo (isolates the video surface)
//   MPV_EXAMPLE_METRICS=1    print frame timings after every resize drag
//                            (implied by MPV_EXAMPLE_FRAMELESS=1)
//
// Runner-side switches live in windows/runner/main.cpp:
//   MPV_EXAMPLE_THREADS=separate   unmerged platform/UI threads (as the player)
//   MPV_EXAMPLE_RENDERER=skia      disable Impeller
import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:nativeapi/nativeapi.dart' as na;

/// Opt-in experiment switches, read once from the environment.
abstract final class Lab {
  static final bool frameless = Platform.environment['MPV_EXAMPLE_FRAMELESS'] == '1';
  static final bool videoMounted = Platform.environment['MPV_EXAMPLE_VIDEO'] != '0';
  static final bool metrics =
      frameless || Platform.environment['MPV_EXAMPLE_METRICS'] == '1';
}

// --- Win32 lookup of the runner HWND ---------------------------------------
// WindowManager.getCurrent() is null while the window is hidden or when the UI
// isolate runs on its own thread, so locate the runner window by class name,
// scoped to this process.

final DynamicLibrary _user32 = DynamicLibrary.open('user32.dll');
final int Function(int, int, Pointer<Utf16>, Pointer<Utf16>) _findWindowEx =
    _user32.lookupFunction<
        IntPtr Function(IntPtr, IntPtr, Pointer<Utf16>, Pointer<Utf16>),
        int Function(int, int, Pointer<Utf16>, Pointer<Utf16>)>('FindWindowExW');
final int Function(int, Pointer<Uint32>) _windowProcessId = _user32.lookupFunction<
    Uint32 Function(IntPtr, Pointer<Uint32>),
    int Function(int, Pointer<Uint32>)>('GetWindowThreadProcessId');
final int Function() _currentProcessId = DynamicLibrary.open('kernel32.dll')
    .lookupFunction<Uint32 Function(), int Function()>('GetCurrentProcessId');

int _findRunnerWindow() => using((arena) {
      final className =
          'FLUTTER_RUNNER_WIN32_WINDOW'.toNativeUtf16(allocator: arena);
      final pid = arena<Uint32>();
      var hwnd = 0;
      while (true) {
        hwnd = _findWindowEx(0, hwnd, className, nullptr);
        if (hwnd == 0) return 0;
        _windowProcessId(hwnd, pid);
        if (pid.value == _currentProcessId()) return hwnd;
      }
    });

/// Hides the native title bar and returns the wrapped window (null if the
/// runner window cannot be found). Edge resize and Aero Snap stay native.
na.Window? setUpFramelessWindow() {
  if (!Platform.isWindows) return null;
  final hwnd = _findRunnerWindow();
  if (hwnd == 0) return null;
  final window =
      na.Window.createWithNativeWindow(Pointer<Void>.fromAddress(hwnd));
  if (window == null) return null;
  window.titleBarStyle = na.TitleBarStyle.hidden;
  window.minimumSize = const na.Size(width: 640, height: 360);
  return window;
}

/// 32px custom title bar: pan drags the window, double tap toggles maximize.
class FramelessTitleBar extends StatelessWidget {
  const FramelessTitleBar({super.key, required this.window});

  final na.Window window;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 32,
        child: ColoredBox(
          color: const Color(0xFF14161F),
          child: Row(children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (_) => window.startDragging(),
                onDoubleTap: window.performTitleBarDoubleClick,
                child: const Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: EdgeInsets.only(left: 12),
                    child: Text('mpv_kit resize lab',
                        style: TextStyle(fontSize: 12, color: Colors.white70)),
                  ),
                ),
              ),
            ),
            _TitleButton(Icons.minimize, window.minimize),
            _TitleButton(Icons.crop_square, window.performTitleBarDoubleClick),
            _TitleButton(Icons.close, window.close),
          ]),
        ),
      );
}

class _TitleButton extends StatelessWidget {
  const _TitleButton(this.icon, this.onTap);

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 36,
          height: 32,
          child: Icon(icon, size: 14, color: Colors.white70),
        ),
      );
}

// --- Frame timing around a resize drag -------------------------------------

/// Prints one `RESIZE_METRICS {json}` line after each resize drag settles.
///
/// A drag is the run of window-metric changes with gaps under [_settle];
/// frame timings arrive in batches, so the settle window is generous.
final class ResizeMeter with WidgetsBindingObserver {
  ResizeMeter._();

  static final ResizeMeter instance = ResizeMeter._();

  static const Duration _settle = Duration(milliseconds: 1000);
  static const int _jank60Us = 16667;
  static const int _jank30Us = 33333;

  final List<FrameTiming> _frames = <FrameTiming>[];
  Timer? _timer;
  bool _active = false;
  int _session = 0;
  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  @override
  void didChangeMetrics() {
    if (!_active) {
      _active = true;
      _frames.clear();
      _session++;
    }
    _timer?.cancel();
    _timer = Timer(_settle, _finish);
  }

  void _onTimings(List<FrameTiming> timings) {
    if (_active) _frames.addAll(timings);
  }

  void _finish() {
    _active = false;
    if (_frames.isEmpty) return;
    final build = _sorted((t) => t.buildDuration.inMicroseconds);
    final raster = _sorted((t) => t.rasterDuration.inMicroseconds);
    final total = _sorted((t) => t.totalSpan.inMicroseconds);
    int pct(List<int> v, double p) => v[((v.length * p).ceil() - 1).clamp(0, v.length - 1)];
    double ratio(int limit) =>
        total.where((v) => v > limit).length / total.length;
    debugPrint('RESIZE_METRICS ${jsonEncode(<String, Object>{
          'session': _session,
          'samples': total.length,
          'buildP50Us': pct(build, 0.5),
          'buildP95Us': pct(build, 0.95),
          'rasterP50Us': pct(raster, 0.5),
          'rasterP95Us': pct(raster, 0.95),
          'rasterMaxUs': raster.last,
          'totalP50Us': pct(total, 0.5),
          'totalP95Us': pct(total, 0.95),
          'jank30Ratio': ratio(_jank30Us),
          'jank60Ratio': ratio(_jank60Us),
        })}');
  }

  List<int> _sorted(int Function(FrameTiming) pick) =>
      (_frames.map(pick).toList()..sort());
}

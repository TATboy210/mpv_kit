// mpv_kit example: open a file (drag-and-drop, path argument, or the text
// field), show it through MpvVideo, and carry a toggleable debug HUD
// (F9) with five property groups and the live renderer-event overlay.
import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mpv_kit_video/mpv_kit_video.dart';

import 'hud.dart';

void main(List<String> args) {
  runApp(ExampleApp(initialPath: args.isNotEmpty ? args.first : null));
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key, this.initialPath});

  final String? initialPath;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'mpv_kit example',
        theme: ThemeData.dark(useMaterial3: true),
        home: PlayerPage(initialPath: initialPath),
      );
}

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, this.initialPath});

  final String? initialPath;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  final player = Player(options: {
    // hwdec: the example uses the Player's per-platform default (ADR 0006).
    // video-sync 用 Player 默认(audio):display-* 的相位调度与渲染桥
    // 异步发布链不合拍,实测积压 603 帧,见 Player 的 doc 注释。
    // MPV_KIT_EXAMPLE_AO=null: no audio device (automated runs; avoids the
    // click a forcibly killed audio stream makes in the speakers).
    'ao': ?Platform.environment['MPV_KIT_EXAMPLE_AO'],
    // MPV_KIT_EXAMPLE_LOG=<file>: verbose mpv log for diagnostics.
    if (Platform.environment['MPV_KIT_EXAMPLE_LOG'] case final log?) ...{
      'log-file': log,
      'msg-level': 'all=v',
    },
  });
  MpvVideoController? video;
  Object? error;
  late final TextEditingController path =
      TextEditingController(text: widget.initialPath ?? '');
  Timer? hudTimer;
  Timer? noticeTimer;
  bool hudVisible = true;
  bool dropHovering = false;
  HudSnapshot hud = HudSnapshot.fabricated();
  final hudEvents = HudEventLog();
  StreamSubscription<MpvVideoEvent>? videoEvents;

  @override
  void initState() {
    super.initState();
    unawaited(_init());
  }

  Future<void> _init() async {
    try {
      final v = await MpvVideoController.create(player);
      if (!mounted) return;
      setState(() => video = v);
      videoEvents = v.events.listen((e) {
        hudEvents.add(e.kind.name, e.message);
      });
      if (path.text.isNotEmpty) await player.open(path.text);
    } on Object catch (e) {
      if (mounted) setState(() => error = e);
    }
    hudTimer = Timer.periodic(const Duration(seconds: 1), (_) => _hudTick());
  }

  void _hudTick() {
    // The debugPrint line doubles as a CI-friendly one-line summary.
    debugPrint('mpv_kit_example: ${hud.sync['dropped']} dropped, '
        'avdiff=${hud.sync['avsync']}');
    if (!mounted) return;
    setState(() => hud = HudSnapshot.capture(player, video));
  }

  /// Shows [text] on the HUD for three seconds (non-video drops etc.).
  void showNotice(String text) {
    noticeTimer?.cancel();
    setState(() => hud = HudSnapshot(
          sync: hud.sync,
          cache: hud.cache,
          decode: hud.decode,
          render: hud.render,
          audio: hud.audio,
          notice: text,
        ));
    noticeTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => hud = HudSnapshot(
              sync: hud.sync,
              cache: hud.cache,
              decode: hud.decode,
              render: hud.render,
              audio: hud.audio,
            ));
      }
    });
  }

  void _openDropped(List<dynamic> files) {
    // desktop_drop hands us XFile-like objects with a .path.
    for (final f in files) {
      final p = f.path as String;
      if (isVideoPlayable(p)) {
        path.text = p;
        unawaited(player.open(p));
        return;
      }
    }
    final first = files.isEmpty ? '?' : (files.first.path as String);
    showNotice('ignored non-video file: ${first.split('/').last}');
  }

  @override
  void dispose() {
    hudTimer?.cancel();
    noticeTimer?.cancel();
    unawaited(videoEvents?.cancel());
    // Player.dispose frees the render context first (dispose hook).
    unawaited(player.dispose());
    path.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = video;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f9): () =>
            setState(() => hudVisible = !hudVisible),
        const SingleActivator(LogicalKeyboardKey.keyH): () =>
            setState(() => hudVisible = !hudVisible),
      },
      child: Scaffold(
        body: Column(children: [
          Expanded(
            child: DropTarget(
              onDragEntered: (_) => setState(() => dropHovering = true),
              onDragExited: (_) => setState(() => dropHovering = false),
              onDragDone: (details) {
                setState(() => dropHovering = false);
                _openDropped(details.files);
              },
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: dropHovering
                      ? Border.all(color: const Color(0xFF7EC8E3), width: 3)
                      : null,
                ),
                child: ColoredBox(
                  color: Colors.black,
                  child: Stack(children: [
                    if (v != null)
                      Positioned.fill(child: MpvVideo(controller: v)),
                    if (error != null)
                      Center(
                          child: Text('$error',
                              style:
                                  const TextStyle(color: Colors.red))),
                    DebugHud(
                      visible: hudVisible,
                      snapshot: hud,
                      events: hudEvents.items,
                    ),
                  ]),
                ),
              ),
            ),
          ),
          _Controls(player: player, path: path),
        ]),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.player, required this.path});

  final Player player;
  final TextEditingController path;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(8),
        child: Row(children: [
          StreamBuilder<bool>(
            stream: player.paused.stream,
            initialData: player.paused.value,
            builder: (_, s) => IconButton(
              icon: Icon(s.data ?? true ? Icons.play_arrow : Icons.pause),
              onPressed: player.playOrPause,
            ),
          ),
          Expanded(
            // Not a StreamBuilder on position: the position stream ticks at
            // frame rate (throttled to 100ms in Player), and a rebuild per
            // tick is UI churn next to a 4K decode. A 250 ms timer reads
            // the current value — 4 rebuilds/s is plenty smooth for a
            // seekbar and keeps the example copy-paste-safe.
            child: _PositionSlider(player: player),
          ),
          SizedBox(
            width: 360,
            child: TextField(
              controller: path,
              decoration: const InputDecoration(hintText: 'file path or URL'),
              onSubmitted: (s) => unawaited(player.open(s)),
            ),
          ),
        ]),
      );
}

/// Seekbar driven by a 250 ms timer instead of a per-tick stream rebuild
/// (see the comment at the call site).
class _PositionSlider extends StatefulWidget {
  const _PositionSlider({required this.player});

  final Player player;

  @override
  State<_PositionSlider> createState() => _PositionSliderState();
}

class _PositionSliderState extends State<_PositionSlider> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.player.duration.value.inMilliseconds;
    final p = widget.player.position.value.inMilliseconds;
    return Slider(
      value: d == 0 ? 0 : (p / d).clamp(0, 1).toDouble(),
      onChanged: d == 0
          ? null
          : (x) => unawaited(
              widget.player.seek(Duration(milliseconds: (x * d).round()))),
    );
  }
}

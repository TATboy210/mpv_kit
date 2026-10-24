// mpv_kit example: open a file (path as first argument or the text field),
// show it through MpvVideo and display live render/decode statistics.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mpv_kit_video/mpv_kit_video.dart';

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
    // Vulkan Video decoding where available, else the safe platform default.
    'hwdec': 'vulkan,d3d11va-copy,auto-safe',
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
  Timer? statsTimer;
  String stats = '';
  StreamSubscription<MpvVideoEvent>? videoEvents;
  final recentEvents = <String>[];

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
        // Keep the last few renderer events on screen for diagnostics.
        recentEvents.add('$e');
        if (recentEvents.length > 3) recentEvents.removeAt(0);
      });
      if (path.text.isNotEmpty) await player.open(path.text);
    } on Object catch (e) {
      if (mounted) setState(() => error = e);
    }
    statsTimer = Timer.periodic(const Duration(seconds: 1), (_) => _stats());
  }

  void _stats() {
    final m = player.mpv;
    String p(String name) => '${m.tryGetProperty(name) ?? '-'}';
    final line = 'hwdec=${p('hwdec-current')} size=${p('width')}x${p('height')} '
        'fps=${p('container-fps')} display-fps=${p('display-fps')} '
        'vsync=${p('video-sync')} dropped=${p('frame-drop-count')} '
        'dec-drop=${p('decoder-frame-drop-count')} '
        'delayed=${p('vo-delayed-frame-count')} '
        'avdiff=${p('avsync')}';
    debugPrint(line);
    setState(() {
      stats = 'backend ${video?.backend.name} (${video?.reason})\n'
          'hwdec ${p('hwdec-current')}  codec ${p('video-codec')}\n'
          'size ${p('width')}x${p('height')}  fps ${p('container-fps')}\n'
          'dropped ${p('frame-drop-count')}  decoder-dropped '
          '${p('decoder-frame-drop-count')}  delayed ${p('vo-delayed-frame-count')}'
          '${recentEvents.isEmpty ? '' : '\nevents ${recentEvents.join(' | ')}'}';
    });
  }

  @override
  void dispose() {
    statsTimer?.cancel();
    unawaited(videoEvents?.cancel());
    // Player.dispose frees the render context first (dispose hook).
    unawaited(player.dispose());
    path.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = video;
    return Scaffold(
      body: Column(children: [
        Expanded(
          child: ColoredBox(
            color: Colors.black,
            child: Stack(children: [
              if (v != null) Positioned.fill(child: MpvVideo(controller: v)),
              if (error != null)
                Center(
                    child: Text('$error',
                        style: const TextStyle(color: Colors.red))),
              Positioned(
                left: 8,
                top: 8,
                child: Text(stats,
                    style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 12)),
              ),
            ]),
          ),
        ),
        _Controls(player: player, path: path),
      ]),
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

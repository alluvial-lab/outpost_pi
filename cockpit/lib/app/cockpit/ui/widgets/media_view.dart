import 'dart:async';

import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Distinguish audio from media that requires a video surface.
enum MediaKind { audio, video }

/// Play audio or video within a file-viewer tab with explicit lifecycle ownership.
///
/// Creates [Player] and, for video, [VideoController] in `initState`, then
/// disposes them when the tab closes to prevent orphaned audio. Media opens
/// paused, pauses when [active] becomes false, and never auto-resumes on return.
class MediaView extends StatefulWidget {
  const MediaView({
    super.key,
    required this.path,
    required this.kind,
    required this.active,
  });

  final String path;
  final MediaKind kind;

  /// Indicate whether this tab is visible; becoming false pauses playback.
  final bool active;

  @override
  State<MediaView> createState() => _MediaViewState();
}

class _MediaViewState extends State<MediaView> {
  late final Player _player;
  VideoController? _controller;
  final List<StreamSubscription<dynamic>> _subs = [];

  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _volume = 100;
  double _lastVolume = 100;

  /// Track the seek target while dragging, or null outside a drag.
  double? _seekMs;

  @override
  void initState() {
    super.initState();
    _player = Player();
    if (widget.kind == MediaKind.video) {
      _controller = VideoController(_player);
    }
    _subs.add(
      _player.stream.playing.listen((v) {
        if (mounted) setState(() => _playing = v);
      }),
    );
    _subs.add(
      _player.stream.position.listen((v) {
        if (mounted) setState(() => _position = v);
      }),
    );
    _subs.add(
      _player.stream.duration.listen((v) {
        if (mounted) setState(() => _duration = v);
      }),
    );
    _subs.add(
      _player.stream.volume.listen((v) {
        if (mounted) setState(() => _volume = v);
      }),
    );
    // Open paused rather than autoplaying.
    _player.open(Media(widget.path), play: false);
  }

  @override
  void didUpdateWidget(MediaView old) {
    super.didUpdateWidget(old);
    // Pause when the tab becomes inactive, without auto-resuming on return.
    if (old.active && !widget.active) {
      _player.pause();
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  void _toggleMute() {
    if (_volume > 0) {
      _lastVolume = _volume;
      _player.setVolume(0);
    } else {
      _player.setVolume(_lastVolume <= 0 ? 100 : _lastVolume);
    }
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (widget.kind == MediaKind.video) {
      return ColoredBox(
        color: Colors.black,
        child: Column(
          children: [
            Expanded(
              child: Video(
                controller: _controller!,
                controls: NoVideoControls,
                fit: BoxFit.contain,
              ),
            ),
            _controls(context),
          ],
        ),
      );
    }
    // Center audio controls in a card without a video surface.
    final name = widget.path.split('/').where((p) => p.isNotEmpty).last;
    return ColoredBox(
      color: colors.panel,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Container(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
            decoration: BoxDecoration(
              color: colors.panel2,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.border),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.audiotrack, size: 40, color: colors.accent),
                const SizedBox(height: 14),
                Text(
                  name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.typo.body.copyWith(color: colors.text),
                ),
                const SizedBox(height: 10),
                _controls(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Build themed controls shared by audio and video.
  ///
  /// Includes play/pause, seek position, time, volume, and mute.
  Widget _controls(BuildContext context) {
    final colors = context.colors;
    final onDark = widget.kind == MediaKind.video;
    final fg = onDark ? Colors.white : colors.text;
    final fg2 = onDark ? Colors.white.withValues(alpha: 0.7) : colors.text3;

    final totalMs = _duration.inMilliseconds;
    final posMs = _seekMs ?? _position.inMilliseconds.toDouble();
    final maxMs = totalMs <= 0 ? 1.0 : totalMs.toDouble();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Tooltip(
            tooltip: (context) =>
                TooltipContainer(child: Text(_playing ? 'Pause' : 'Play')),
            child: IconButton.ghost(
              icon: Icon(
                _playing ? Icons.pause : Icons.play_arrow,
                size: 22,
                color: fg,
              ),
              onPressed: _player.playOrPause,
            ),
          ),
          Expanded(
            child: Slider(
              value: SliderValue.single(posMs.clamp(0, maxMs)),
              max: maxMs,
              onChanged: totalMs <= 0
                  ? null
                  : (v) => setState(() => _seekMs = v.value),
              onChangeEnd: totalMs <= 0
                  ? null
                  : (v) {
                      _player.seek(Duration(milliseconds: v.value.round()));
                      setState(() => _seekMs = null);
                    },
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '${_fmt(_position)} / ${_fmt(_duration)}',
            style: context.typo.mono.copyWith(fontSize: 11.5, color: fg2),
          ),
          const SizedBox(width: 4),
          Tooltip(
            tooltip: (context) =>
                TooltipContainer(child: Text(_volume <= 0 ? 'Unmute' : 'Mute')),
            child: IconButton.ghost(
              icon: Icon(
                _volume <= 0 ? Icons.volume_off : Icons.volume_up,
                size: 19,
                color: fg,
              ),
              onPressed: _toggleMute,
            ),
          ),
          SizedBox(
            width: 76,
            child: Slider(
              value: SliderValue.single(_volume.clamp(0, 100)),
              max: 100,
              onChanged: (v) => _player.setVolume(v.value),
            ),
          ),
        ],
      ),
    );
  }
}

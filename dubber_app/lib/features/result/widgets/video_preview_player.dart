import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart' as vp;

import '../../../app/theme/tokens.dart';

/// Full-featured video preview: tap to reveal controls, seek bar with
/// scrub preview, skip back/forward, mute, playback speed and fullscreen.
class VideoPreviewPlayer extends StatefulWidget {
  const VideoPreviewPlayer({
    super.key,
    required this.controller,
    this.isPortrait = true,
    this.maxHeight = 380,
  });

  final vp.VideoPlayerController controller;
  final bool isPortrait;
  final double maxHeight;

  @override
  State<VideoPreviewPlayer> createState() => _VideoPreviewPlayerState();
}

class _VideoPreviewPlayerState extends State<VideoPreviewPlayer> {
  bool _controlsVisible = true;
  bool _fullscreen = false;
  Timer? _hideTimer;
  double? _scrubValue;

  vp.VideoPlayerController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.addListener(_onTick);
    _scheduleHide();
  }

  @override
  void didUpdateWidget(covariant VideoPreviewPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTick);
      widget.controller.addListener(_onTick);
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _c.removeListener(_onTick);
    super.dispose();
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (!_c.value.isPlaying) return;
    _hideTimer = Timer(const Duration(milliseconds: 3200), () {
      if (mounted && _c.value.isPlaying) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHide();
  }

  void _togglePlay() {
    if (_c.value.isPlaying) {
      _c.pause();
      setState(() => _controlsVisible = true);
      _hideTimer?.cancel();
    } else {
      if (_c.value.position >= _c.value.duration) {
        _c.seekTo(Duration.zero);
      }
      _c.play();
      _scheduleHide();
    }
    setState(() {});
  }

  void _seekBy(int seconds) {
    final target = _c.value.position + Duration(seconds: seconds);
    final clamped = target < Duration.zero
        ? Duration.zero
        : (target > _c.value.duration ? _c.value.duration : target);
    _c.seekTo(clamped);
    setState(() => _controlsVisible = true);
    _scheduleHide();
  }

  void _toggleMute() {
    _c.setVolume(_c.value.volume > 0 ? 0 : 1);
    setState(() {});
    _scheduleHide();
  }

  void _cycleSpeed() {
    final next = switch (_c.value.playbackSpeed) {
      1.0 => 1.25,
      1.25 => 1.5,
      1.5 => 2.0,
      2.0 => 0.5,
      _ => 1.0,
    };
    _c.setPlaybackSpeed(next);
    setState(() {});
    _scheduleHide();
  }

  Future<void> _enterFullscreen() async {
    setState(() => _fullscreen = true);
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    if (!mounted) return;
    await Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<void>(
        opaque: true,
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (_, __, ___) => Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: Stack(
              children: [
                Center(
                  child: AspectRatio(
                    aspectRatio: _c.value.aspectRatio,
                    child: VideoPreviewPlayer(
                      controller: _c,
                      isPortrait: widget.isPortrait,
                      maxHeight: double.infinity,
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton(
                    tooltip: 'Exit fullscreen',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_fullscreen_rounded,
                        color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (mounted) setState(() => _fullscreen = false);
  }

  String _fmt(Duration d) {
    final total = d.inSeconds;
    final m = (total ~/ 60).toString().padLeft(2, '0');
    final s = (total % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final value = _c.value;
    final duration = value.duration;
    final position = value.position;
    final totalMs = duration.inMilliseconds.toDouble();
    final sliderMax = totalMs <= 0 ? 1.0 : totalMs;
    final sliderValue = _scrubValue ??
        position.inMilliseconds.toDouble().clamp(0.0, sliderMax);

    return LayoutBuilder(
      builder: (context, constraints) {
        final height = widget.maxHeight.isFinite
            ? widget.maxHeight
            : constraints.maxHeight;

        return ClipRRect(
          borderRadius: BorderRadius.circular(
            _fullscreen ? 0 : Tokens.radiusCard,
          ),
          child: Container(
            height: widget.maxHeight.isFinite ? height : null,
            width: double.infinity,
            color: Tokens.ink,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Video surface
                Center(
                  child: AspectRatio(
                    aspectRatio: value.aspectRatio == 0 ? 16 / 9 : value.aspectRatio,
                    child: vp.VideoPlayer(_c),
                  ),
                ),

                // Tap area
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _toggleControls,
                    onDoubleTap: _togglePlay,
                    child: const SizedBox.expand(),
                  ),
                ),

                // Buffering spinner
                if (value.isBuffering)
                  const SizedBox(
                    width: 40,
                    height: 40,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.6,
                      valueColor: AlwaysStoppedAnimation(Tokens.white),
                    ),
                  ),

                // Center play/pause
                AnimatedOpacity(
                  opacity: (_controlsVisible || !value.isPlaying) ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: IgnorePointer(
                    ignoring: !_controlsVisible && value.isPlaying,
                    child: GestureDetector(
                      onTap: _togglePlay,
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: const BoxDecoration(
                          color: Tokens.white,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          value.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          size: 34,
                          color: Tokens.clayButton,
                        ),
                      ),
                    ),
                  ),
                ),

                // Skip back / forward (visible with controls)
                AnimatedOpacity(
                  opacity: _controlsVisible ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: IgnorePointer(
                    ignoring: !_controlsVisible,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _SkipButton(
                          icon: Icons.replay_10_rounded,
                          label: 'Back 10s',
                          onTap: () => _seekBy(-10),
                        ),
                        const SizedBox(width: 96),
                        _SkipButton(
                          icon: Icons.forward_10_rounded,
                          label: 'Forward 10s',
                          onTap: () => _seekBy(10),
                        ),
                      ],
                    ),
                  ),
                ),

                // Bottom control bar
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: AnimatedOpacity(
                    opacity: _controlsVisible ? 1 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: IgnorePointer(
                      ignoring: !_controlsVisible,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(10, 22, 10, 6),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0x00000000), Color(0xCC000000)],
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Scrub bar
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 3,
                                activeTrackColor: Tokens.clay,
                                inactiveTrackColor: Colors.white24,
                                thumbColor: Tokens.white,
                                overlayColor: Tokens.clay.withValues(alpha: 0.2),
                                thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 6),
                                overlayShape: const RoundSliderOverlayShape(
                                    overlayRadius: 14),
                              ),
                              child: Slider(
                                min: 0,
                                max: sliderMax,
                                value: sliderValue.clamp(0.0, sliderMax),
                                onChangeStart: (v) {
                                  _hideTimer?.cancel();
                                  setState(() => _scrubValue = v);
                                },
                                onChanged: (v) =>
                                    setState(() => _scrubValue = v),
                                onChangeEnd: (v) {
                                  _c.seekTo(
                                      Duration(milliseconds: v.round()));
                                  setState(() => _scrubValue = null);
                                  _scheduleHide();
                                },
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              child: Row(
                                children: [
                                  Text(
                                    '${_fmt(position)} / ${_fmt(duration)}',
                                    style: AppText.caption.copyWith(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const Spacer(),
                                  _BarIcon(
                                    icon: value.volume > 0
                                        ? Icons.volume_up_rounded
                                        : Icons.volume_off_rounded,
                                    tooltip:
                                        value.volume > 0 ? 'Mute' : 'Unmute',
                                    onTap: _toggleMute,
                                  ),
                                  _BarIcon(
                                    text: '${_speedLabel(value.playbackSpeed)}x',
                                    tooltip: 'Playback speed',
                                    onTap: _cycleSpeed,
                                  ),
                                  _BarIcon(
                                    icon: _fullscreen
                                        ? Icons.close_fullscreen_rounded
                                        : Icons.fullscreen_rounded,
                                    tooltip: 'Fullscreen',
                                    onTap: _fullscreen
                                        ? () => Navigator.of(context).pop()
                                        : _enterFullscreen,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _speedLabel(double speed) =>
      speed == speed.roundToDouble() ? speed.toStringAsFixed(0) : speed.toString();
}

class _SkipButton extends StatelessWidget {
  const _SkipButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: IconButton(
        onPressed: onTap,
        iconSize: 34,
        tooltip: label,
        icon: Icon(icon, color: Colors.white),
      ),
    );
  }
}

class _BarIcon extends StatelessWidget {
  const _BarIcon({this.icon, this.text, required this.tooltip, required this.onTap});

  final IconData? icon;
  final String? text;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Tooltip(
          message: tooltip,
          child: Container(
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: icon != null
                ? Icon(icon, color: Colors.white, size: 20)
                : Text(
                    text ?? '',
                    style: AppText.caption.copyWith(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

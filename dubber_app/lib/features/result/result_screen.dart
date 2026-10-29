import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart' as vp;

import '../../app/providers.dart';
import '../../app/theme/tokens.dart';
import '../../core/api/api_error.dart';
import '../../core/api/video_saver.dart';
import '../../core/widgets/app_widgets.dart';
import '../../core/widgets/controls.dart';
import '../../core/widgets/dubber_character.dart';
import '../../core/widgets/status_chip.dart';
import '../projects/domain/models.dart';
import 'widgets/video_preview_player.dart';

/// Result: play the dubbed video, compare with the original, edit or export.
class ResultScreen extends ConsumerStatefulWidget {
  const ResultScreen({super.key, required this.projectId});

  final String projectId;

  @override
  ConsumerState<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends ConsumerState<ResultScreen> {
  Project? _project;
  ApiError? _error;
  bool _loading = true;
  bool _showDubbed = true;

  vp.VideoPlayerController? _dubbed;
  vp.VideoPlayerController? _original;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _dubbed?.removeListener(_onPlayerUpdate);
    _original?.removeListener(_onPlayerUpdate);
    _dubbed?.dispose();
    _original?.dispose();
    super.dispose();
  }

  void _onPlayerUpdate() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    try {
      final project = await ref.read(apiProvider).project(widget.projectId);
      if (!mounted) return;
      setState(() {
        _project = project;
        _loading = false;
      });
      _initPlayers(project);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiError ? e : const ApiError.unknown();
        _loading = false;
      });
    }
  }

  Future<void> _initPlayers(Project project) async {
    final dubbedFullUrl = resolveMediaUrl(project.dubbedUrl);
    if (dubbedFullUrl.isNotEmpty) {
      try {
        final controller = vp.VideoPlayerController.networkUrl(
          Uri.parse(dubbedFullUrl),
        );
        await controller.initialize();
        controller.addListener(_onPlayerUpdate);
        if (!mounted) {
          await controller.dispose();
          return;
        }
        // Retry could land here while an old controller is alive: release it
        // first or it (and its native player) leaks.
        final old = _dubbed;
        setState(() => _dubbed = controller);
        if (old != null && old != controller) {
          old.removeListener(_onPlayerUpdate);
          await old.dispose();
        }
      } catch (err) {
        debugPrint('Error initializing dubbed video player: $err');
      }
    }
    final originalFullUrl = resolveMediaUrl(project.originalUrl);
    if (originalFullUrl.isNotEmpty) {
      try {
        final controller = vp.VideoPlayerController.networkUrl(
          Uri.parse(originalFullUrl),
        );
        await controller.initialize();
        controller.addListener(_onPlayerUpdate);
        if (!mounted) {
          await controller.dispose();
          return;
        }
        final old = _original;
        setState(() => _original = controller);
        if (old != null && old != controller) {
          old.removeListener(_onPlayerUpdate);
          await old.dispose();
        }
      } catch (err) {
        debugPrint('Error initializing original video player: $err');
      }
    }
  }

  /// Switches track while keeping the playback position.
  Future<void> _switchTrack(bool dubbed) async {
    final from = _showDubbed ? _dubbed : _original;
    final to = dubbed ? _dubbed : _original;
    if (to == null) return;

    final position = from?.value.position ?? Duration.zero;
    final wasPlaying = from?.value.isPlaying ?? false;
    await from?.pause();

    await to.seekTo(position);
    if (wasPlaying) await to.play();

    if (!mounted) return;
    setState(() => _showDubbed = dubbed);
  }

  @override
  Widget build(BuildContext context) {
    final project = _project;

    return Scaffold(
      backgroundColor: Tokens.ivory,
      body: SafeArea(
        bottom: true,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppBarRow(
                title: project?.title ?? 'Result',
                onBack: () => context.go('/projects'),
              ),
              const SizedBox(height: 12),
              if (_loading)
                const Expanded(
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  ),
                )
              else if (_error != null)
                Expanded(
                  child: StateView(
                    title: 'We could not load this video',
                    message: _error!.message,
                    mood: CharacterMood.worried,
                    actionLabel: 'Try again',
                    onAction: _load,
                  ),
                )
              else if (project != null)
                Expanded(child: _body(project)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(Project project) {
    final controller = _showDubbed ? _dubbed : _original;
    final canCompare = _dubbed != null && _original != null;

    final isPortrait = project.format == VideoFormat.portrait ||
        (controller?.value.isInitialized == true &&
            controller!.value.aspectRatio < 1.0);

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(Tokens.radiusCard),
            child: controller?.value.isInitialized == true
                ? VideoPreviewPlayer(
                    controller: controller!,
                    isPortrait: isPortrait,
                    maxHeight: isPortrait ? 380 : 210,
                  )
                : Container(
                    height: isPortrait ? 380 : 210,
                    width: double.infinity,
                    color: Tokens.ink,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            onPressed: () {
                              _initPlayers(project);
                            },
                            tooltip: 'Play',
                            iconSize: 64,
                            icon: const Icon(Icons.play_circle_fill_rounded,
                                color: Tokens.white),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Tap to load video',
                            style: AppText.caption.copyWith(color: Tokens.white),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 16),
          if (canCompare)
            SegmentedControl<bool>(
              value: _showDubbed,
              onChanged: _switchTrack,
              background: Tokens.border,
              semanticLabel: 'Audio track',
              options: [
                (
                  value: true,
                  label: 'Dubbed · ${project.targetLanguage?.toUpperCase() ?? ''}',
                  icon: null,
                ),
                (
                  value: false,
                  label:
                      'Original · ${project.sourceLanguage?.toUpperCase() ?? ''}',
                  icon: null,
                ),
              ],
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: PrimaryButton(
                  label: 'Download',
                  onPressed: _download,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SecondaryButton(
                  label: 'Share',
                  onPressed: _share,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const _ToggleRow(label: 'Show subtitles', value: true),
          const SizedBox(height: 12),
          const _ToggleRow(label: 'Keep background music', value: true),
          const SizedBox(height: 16),
          NeutralButton(
            label: 'Edit video',
            onPressed: () =>
                context.push('/projects/${project.id}/editor'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  void _download() {
    final project = _project;
    final url = project?.dubbedUrl ?? '';
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This video has not finished yet.')),
      );
      return;
    }
    downloadAndSaveVideo(
      context,
      ref,
      url: url.startsWith('http') ? url : resolveMediaUrl(url),
      fileName: 'dubber_${project!.id}.mp4',
    );
  }

  void _share() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sharing is not set up yet.')),
    );
  }
}

class _ToggleRow extends StatefulWidget {
  const _ToggleRow({required this.label, required this.value});

  final String label;
  final bool value;

  @override
  State<_ToggleRow> createState() => _ToggleRowState();
}

class _ToggleRowState extends State<_ToggleRow> {
  late bool _value = widget.value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Tokens.white,
        borderRadius: BorderRadius.circular(Tokens.radiusField),
        border: Border.all(color: Tokens.border),
      ),
      child: Row(
        children: [
          Expanded(child: Text(widget.label, style: AppText.body)),
          Switch(
            value: _value,
            onChanged: (v) => setState(() => _value = v),
            activeThumbColor: Tokens.white,
            activeTrackColor: Tokens.clayButton,
          ),
        ],
      ),
    );
  }
}

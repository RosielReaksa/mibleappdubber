import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme/tokens.dart';
import '../../core/api/api_error.dart';
import '../../core/api/video_saver.dart';
import '../../core/widgets/app_widgets.dart';
import '../../core/widgets/dubber_character.dart';
import '../../core/widgets/status_chip.dart';

/// Exporting → Video ready. Polls the export until it finishes.
class ExportScreen extends ConsumerStatefulWidget {
  const ExportScreen({
    super.key,
    required this.projectId,
    required this.exportId,
  });

  final String projectId;
  final String exportId;

  @override
  ConsumerState<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends ConsumerState<ExportScreen> {
  Timer? _timer;
  String _status = 'processing';
  int _percent = 0;
  String? _downloadUrl;
  String? _reason;
  ApiError? _error;

  @override
  void initState() {
    super.initState();
    _poll();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    try {
      final result = await ref.read(apiProvider).exportStatus(widget.exportId);
      if (!mounted) return;
      setState(() {
        _status = result.status;
        _percent = result.percent;
        _downloadUrl = result.downloadUrl;
        _reason = result.reason;
        _error = null;
      });
      if (result.status == 'done' || result.status == 'failed') {
        _timer?.cancel();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e is ApiError ? e : const ApiError.unknown());
    }
  }

  bool get _done => _status == 'done';
  bool get _failed => _status == 'failed';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Tokens.ivory,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppBarRow(
                title: _done ? 'Video ready' : 'Exporting',
                onBack: () => context.go('/projects'),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: DubberCharacter(
                          size: 250,
                          mood: _failed ? CharacterMood.worried : CharacterMood.happy,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_done) ...[
                        Text(
                          'Your video is ready',
                          textAlign: TextAlign.center,
                          style: AppText.display(28),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Download it or share it right away.',
                          textAlign: TextAlign.center,
                          style: AppText.bodyMuted,
                        ),
                        const SizedBox(height: 24),
                        PrimaryButton(
                          label: 'Download',
                          onPressed: _download,
                        ),
                        const SizedBox(height: 12),
                        SecondaryButton(label: 'Share', onPressed: _share),
                        const SizedBox(height: 12),
                        NeutralButton(
                          label: 'Edit again',
                          onPressed: () => context.pushReplacement(
                            '/projects/${widget.projectId}/editor',
                          ),
                        ),
                      ] else if (_failed) ...[
                        Text(
                          'Export did not finish',
                          textAlign: TextAlign.center,
                          style: AppText.display(26),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _reason ?? 'Something went wrong. Please try again.',
                          textAlign: TextAlign.center,
                          style: AppText.bodyMuted,
                        ),
                        const SizedBox(height: 24),
                        PrimaryButton(
                          label: 'Try again',
                          onPressed: () => context.pushReplacement(
                            '/projects/${widget.projectId}/editor',
                          ),
                        ),
                      ] else ...[
                        Center(
                          child: Text('$_percent%', style: AppText.percent(48)),
                        ),
                        const SizedBox(height: 16),
                        Semantics(
                          label: 'Export progress',
                          value: '$_percent percent',
                          child: ClipRRect(
                            borderRadius:
                                BorderRadius.circular(Tokens.radiusPill),
                            child: LinearProgressIndicator(
                              value: _percent / 100,
                              minHeight: 10,
                              backgroundColor: Tokens.oat,
                              valueColor:
                                  const AlwaysStoppedAnimation(Tokens.clay),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'You can close the app. We will send a notification when it is ready.',
                          style: AppText.labelMuted.copyWith(height: 1.5),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _error!.message,
                            style:
                                AppText.caption.copyWith(color: Tokens.clayDeep),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _download() {
    final url = _downloadUrl ?? '';
    downloadAndSaveVideo(
      context,
      ref,
      url: url.startsWith('http') ? url : resolveMediaUrl(url),
      fileName: 'dubber_export_${DateTime.now().millisecondsSinceEpoch}.mp4',
    );
  }

  void _share() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sharing is not set up yet.')),
    );
  }
}

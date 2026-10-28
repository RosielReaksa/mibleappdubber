import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme/tokens.dart';
import '../../core/api/api_error.dart';
import '../../core/widgets/app_widgets.dart';
import '../../core/widgets/dubber_character.dart';
import '../../core/widgets/status_chip.dart';
import '../projects/application/projects_controller.dart';
import '../projects/domain/models.dart';

/// Dubbing progress: steps, percent, and the animated character.
class ProgressScreen extends ConsumerStatefulWidget {
  const ProgressScreen({super.key, required this.projectId});

  final String projectId;

  @override
  ConsumerState<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends ConsumerState<ProgressScreen> {
  Timer? _timer;
  Project? _project;
  ApiError? _error;
  bool _loading = true;

  static const _stepLabels = {
    'upload': 'Upload',
    'transcribe': 'Transcribe',
    'translate': 'Translate',
    'generate_voice': 'Generate voice',
    'mix_export': 'Mix and export',
  };

  @override
  void initState() {
    super.initState();
    _poll();
    // Poll every 1.5 s while dubbing so steps and completion update quickly.
    _timer = Timer.periodic(const Duration(milliseconds: 1500), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    try {
      final project = await ref.read(apiProvider).project(widget.projectId);
      if (!mounted) return;
      ref.read(projectsControllerProvider.notifier).upsert(project);
      setState(() {
        _project = project;
        _error = null;
        _loading = false;
      });
      if (project.status.isTerminal) _timer?.cancel();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiError ? e : const ApiError.unknown();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final project = _project;

    return Scaffold(
      backgroundColor: Tokens.ivory,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppBarRow(
                title: 'Dubbing',
                onBack: () => context.go('/projects'),
              ),
              const SizedBox(height: 20),
              if (_loading)
                const Expanded(
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  ),
                )
              else if (_error != null && project == null)
                Expanded(
                  child: StateView(
                    title: 'We lost the connection',
                    message: _error!.message,
                    mood: CharacterMood.worried,
                    actionLabel: 'Try again',
                    onAction: _poll,
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
    if (project.status == JobStatus.failed) {
      return StateView(
        title: 'Dubbing did not finish',
        message: _failMessage(project.failReason),
        mood: CharacterMood.worried,
        actionLabel: 'Try again',
        onAction: () => context.go('/new'),
      );
    }

    if (project.status == JobStatus.done) {
      // Move on to the result screen once the job completes.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.pushReplacement('/projects/${project.id}/result');
        }
      });
    }

    final currentStep = _currentStepIndex(project.step);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            project.title,
            style: AppText.label.copyWith(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${project.sourceLanguage?.toUpperCase() ?? ''} → '
            '${project.targetLanguage?.toUpperCase() ?? ''}',
            style: AppText.labelMuted,
          ),
          const SizedBox(height: 16),
          Center(child: DubberCharacter(size: 250)),
          const SizedBox(height: 8),
          Center(
            child: Text(
              '${project.percent}%',
              style: AppText.percent(48),
            ),
          ),
          const SizedBox(height: 16),
          Semantics(
            label: 'Dubbing progress',
            value: '${project.percent} percent',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Tokens.radiusPill),
              child: LinearProgressIndicator(
                value: project.percent / 100,
                minHeight: 10,
                backgroundColor: Tokens.oat,
                valueColor: const AlwaysStoppedAnimation(Tokens.clay),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _RotatingMessage(step: project.step),
          const SizedBox(height: 20),
          AppCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                for (final entry in _stepLabels.entries)
                  _StepRow(
                    label: entry.value,
                    state: _stepState(entry.key, project, currentStep),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'You can close the app. We will send a notification when it is ready.',
            style: AppText.labelMuted.copyWith(height: 1.5),
          ),
          const SizedBox(height: 24),
          SecondaryButton(
            label: 'Notify me when done',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('We will notify you when your video is ready.'),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  int _currentStepIndex(String? step) {
    final keys = _stepLabels.keys.toList();
    final i = keys.indexOf(step ?? '');
    return i < 0 ? 0 : i;
  }

  _StepState _stepState(String key, Project project, int current) {
    final index = _stepLabels.keys.toList().indexOf(key);
    if (project.status == JobStatus.done) return _StepState.done;
    if (index < current) return _StepState.done;
    if (index == current) return _StepState.active;
    return _StepState.pending;
  }

  String _failMessage(String? reason) => switch (reason) {
        'not_enough_credits' =>
          'You did not have enough credits. Your credits have been returned.',
        'unsupported_file' => 'That file type is not supported.',
        'connection_lost' =>
          'The connection dropped. Your credits have been returned.',
        _ => 'Something went wrong. Your credits have been returned.',
      };
}

enum _StepState { done, active, pending }

class _StepRow extends StatelessWidget {
  const _StepRow({required this.label, required this.state});

  final String label;
  final _StepState state;

  @override
  Widget build(BuildContext context) {
    final (bg, border, fg, weight, icon) = switch (state) {
      _StepState.done => (
          Tokens.clayButton,
          Tokens.clayButton,
          Tokens.ink,
          FontWeight.w400,
          Icons.check_rounded,
        ),
      _StepState.active => (
          Tokens.workingBg,
          Tokens.clay,
          Tokens.ink,
          FontWeight.w700,
          null,
        ),
      _StepState.pending => (
          Tokens.white,
          Tokens.borderStrong,
          Tokens.muted,
          FontWeight.w400,
          null,
        ),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: bg,
              shape: BoxShape.circle,
              border: Border.all(color: border, width: 2),
            ),
            child: icon == null
                ? null
                : Icon(icon, size: 14, color: Tokens.white),
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              fontFamily: Tokens.fontBody,
              fontSize: 16,
              fontWeight: weight,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

/// Rotating friendly messages, one every 3 seconds.
class _RotatingMessage extends StatefulWidget {
  const _RotatingMessage({this.step});

  final String? step;

  static const messages = [
    'Listening to your video…',
    'Translating the words…',
    'Teaching the voice to talk…',
    'Mixing the sound…',
  ];

  @override
  State<_RotatingMessage> createState() => _RotatingMessageState();
}

class _RotatingMessageState extends State<_RotatingMessage> {
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) {
        setState(() => _index = (_index + 1) % _RotatingMessage.messages.length);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    // With reduced motion, show one calm message instead of cycling.
    final message = reduceMotion
        ? 'Dubbing your video…'
        : _RotatingMessage.messages[_index];

    return SizedBox(
      height: 26,
      child: Center(
        child: AnimatedSwitcher(
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 260),
          child: Text(
            message,
            key: ValueKey(message),
            style: AppText.bodyMuted.copyWith(fontSize: 16),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

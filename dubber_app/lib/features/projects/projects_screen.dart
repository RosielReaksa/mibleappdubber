import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/dubber_tab_bar.dart';
import '../../app/tab_scaffold.dart';
import '../../app/theme/tokens.dart';
import '../../core/widgets/app_widgets.dart';
import '../../core/widgets/controls.dart';
import '../../core/widgets/dubber_character.dart';
import '../../core/widgets/status_chip.dart';
import '../account/app_update_checker.dart';
import '../auth/application/auth_controller.dart';
import 'application/projects_controller.dart';
import 'domain/models.dart';

class ProjectsScreen extends ConsumerStatefulWidget {
  const ProjectsScreen({super.key});

  @override
  ConsumerState<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends ConsumerState<ProjectsScreen> {
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(projectsControllerProvider.notifier).refresh(silent: true);
      ref.read(authControllerProvider.notifier).refreshMe();
      AppUpdateChecker.check(context, ref);
    });
    // Periodically refresh project status and credits
    _pollingTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      final state = ref.read(projectsControllerProvider);
      final hasActive = state.projects.any((p) => p.status.isActive);
      if (mounted) {
        if (hasActive) {
          ref.read(projectsControllerProvider.notifier).refresh(silent: true);
        }
        ref.read(authControllerProvider.notifier).refreshMe();
      }
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(projectsControllerProvider);
    final credits = ref.watch(authControllerProvider).session?.credits;

    return TabScaffold(
      title: 'My projects',
      trailing: TabHeaderActions(credits: credits),
      child: Column(
        children: [
          if (state.offline)
            const _OfflineBanner(),
          Expanded(child: _body(state)),
        ],
      ),
    );
  }

  Widget _body(ProjectsState state) {
    if (state.isEmpty && state.loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.4));
    }

    if (state.isEmpty) {
      if (state.error != null && !state.offline) {
        return StateView(
          title: 'We could not load your projects',
          message: state.error!.message,
          mood: CharacterMood.worried,
          actionLabel: 'Try again',
          onAction: () =>
              ref.read(projectsControllerProvider.notifier).refresh(),
        );
      }
      return StateView(
        title: 'No projects yet',
        message: 'Dub your first video in a few taps.',
        actionLabel: 'Create first project',
        onAction: () => context.go('/new'),
      );
    }

    return RefreshIndicator(
      onRefresh: () =>
          ref.read(projectsControllerProvider.notifier).refresh(silent: true),
      color: Tokens.clayButton,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        itemCount: state.projects.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          final project = state.projects[i];
          return _ProjectRow(
            project: project,
            onTap: () => _open(project),
            onDelete: () => _confirmDelete(project),
          );
        },
      ),
    );
  }

  void _open(Project project) {
    switch (project.status) {
      case JobStatus.done:
        context.push('/projects/${project.id}/result');
      case JobStatus.failed:
        context.push('/projects/${project.id}');
      case _:
        context.push('/projects/${project.id}');
    }
  }

  Future<void> _confirmDelete(Project project) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Tokens.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusCard),
        ),
        title: Text('Delete project?', style: AppText.pageTitle()),
        content: Text(
          '"${project.title}" and its videos will be removed. This cannot be undone.',
          style: AppText.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(foregroundColor: Tokens.muted),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Tokens.clayDeep),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    try {
      await ref.read(projectsControllerProvider.notifier).delete(project.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Project deleted')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete the project.')),
      );
    }
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Tokens.oat,
        borderRadius: BorderRadius.circular(Tokens.radiusButton),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, size: 18, color: Tokens.muted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'You are offline. Showing your saved projects.',
              style: AppText.caption.copyWith(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProjectRow extends StatelessWidget {
  const _ProjectRow({
    required this.project,
    required this.onTap,
    required this.onDelete,
  });

  final Project project;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return ListTileCard(
      onTap: onTap,
      onLongPress: onDelete,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Tokens.oat,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.play_arrow_rounded,
                size: 28, color: Tokens.clayButton),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  project.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.label.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    _languages(project),
                    _createdLabel(project.createdAt),
                  ].where((s) => s.isNotEmpty).join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.labelMuted,
                ),
                const SizedBox(height: 6),
                _statusChip(project),
              ],
            ),
          ),
          IconButton(
            onPressed: onDelete,
            tooltip: 'Delete project',
            icon: const Icon(Icons.more_horiz_rounded, color: Tokens.muted),
          ),
        ],
      ),
    );
  }

  String _languages(Project p) {
    final from = p.sourceLanguage?.toUpperCase();
    final to = p.targetLanguage?.toUpperCase();
    if (from == null || to == null) return '';
    return '$from → $to';
  }

  /// Short, friendly created date: "Today", "Yesterday", or "12 Oct".
  String _createdLabel(DateTime? date) {
    if (date == null) return '';
    final local = date.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(local.year, local.month, local.day);
    final days = today.difference(that).inDays;

    if (days == 0) return 'Today';
    if (days == 1) return 'Yesterday';
    if (days < 7) return '$days days ago';

    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final month = months[local.month - 1];
    if (local.year == now.year) return '${local.day} $month';
    return '${local.day} $month ${local.year}';
  }

  Widget _statusChip(Project p) {
    return switch (p.status) {
      JobStatus.done => const StatusPill(
          label: 'Done',
          background: Tokens.doneBg,
          foreground: Tokens.doneText,
          icon: Icons.check_circle_rounded,
        ),
      JobStatus.processing => StatusPill(
          label: 'Dubbing ${p.percent}%',
          background: Tokens.workingBg,
          foreground: Tokens.workingText,
          icon: Icons.autorenew_rounded,
        ),
      JobStatus.uploading => StatusPill(
          label: 'Uploading ${p.percent}%',
          background: Tokens.oat,
          foreground: Tokens.clayDeep,
          icon: Icons.cloud_upload_outlined,
        ),
      JobStatus.failed => const StatusPill(
          label: 'Failed',
          background: Tokens.softClay,
          foreground: Tokens.clayDeep,
          icon: Icons.warning_amber_rounded,
        ),
      JobStatus.queued => const StatusPill(
          label: 'Queued',
          background: Tokens.oat,
          foreground: Tokens.clayDeep,
          icon: Icons.more_horiz_rounded,
        ),
    };
  }
}

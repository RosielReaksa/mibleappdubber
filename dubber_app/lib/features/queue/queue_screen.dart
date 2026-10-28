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
import '../auth/application/auth_controller.dart';
import '../projects/domain/models.dart';
import 'application/queue_controller.dart';
import 'domain/queue_rules.dart';
import 'queue_add_sheet.dart';

/// Queue tab: what is dubbing now, what waits behind it, and what failed.
class QueueScreen extends ConsumerStatefulWidget {
  const QueueScreen({super.key});

  @override
  ConsumerState<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends ConsumerState<QueueScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(() {
      final controller = ref.read(queueControllerProvider.notifier);
      controller.setVisible(true);
      controller.refresh();
    });
  }

  @override
  void dispose() {
    // Leaving the tab drops back to the slow poll; the badge stays live.
    ref.read(queueControllerProvider.notifier).setVisible(false);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    ref
        .read(queueControllerProvider.notifier)
        .setForeground(state == AppLifecycleState.resumed);
  }

  @override
  Widget build(BuildContext context) {
    final queue = ref.watch(queueControllerProvider);
    final credits = ref.watch(authControllerProvider).session?.credits;

    // One grouped message when videos finish or fail together, never one each.
    ref.listen(queueControllerProvider.select((s) => s.justFinished.length),
        (previous, next) {
      if (next == 0) return;
      final failed = ref.read(queueControllerProvider).justFailed.length;
      final parts = <String>[];
      if (next > 0) {
        parts.add(next == 1 ? '1 video is ready' : '$next videos are ready');
      }
      if (failed > 0) {
        parts.add(failed == 1 ? '1 video failed' : '$failed videos failed');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${parts.join(' · ')}. See Projects.')),
      );
      ref.read(queueControllerProvider.notifier).clearNotices();
    });

    return TabScaffold(
      title: 'Queue',
      trailing: TabHeaderActions(credits: credits),
      child: Column(
        children: [
          if (queue.phase == QueuePhase.data || queue.phase == QueuePhase.empty)
            _addBar(queue),
          Expanded(child: _body(queue)),
        ],
      ),
    );
  }

  Widget _addBar(QueueState queue) {
    final full = queue.slotsLeft <= 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              full
                  ? 'Your queue is full'
                  : '${queue.slotsLeft} of $maxQueuePerUser slots free',
              style: AppText.caption,
            ),
          ),
          SecondaryButton(
            label: 'Add videos',
            icon: Icons.video_library_outlined,
            onPressed: full ? null : _openAddSheet,
          ),
        ],
      ),
    );
  }

  Future<void> _openAddSheet() async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Tokens.ivory,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Tokens.radiusCard)),
      ),
      builder: (_) => const QueueAddSheet(),
    );
    if (added == true) {
      await ref.read(queueControllerProvider.notifier).refresh();
    }
  }

  Widget _body(QueueState queue) {
    return switch (queue.phase) {
      QueuePhase.loading => const Center(
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
      QueuePhase.empty => StateView(
          title: 'Nothing in the queue',
          message: 'Add videos and they will dub one after another, while you '
              'keep using the app.',
          actionLabel: 'Add videos',
          onAction: _openAddSheet,
        ),
      QueuePhase.error => StateView(
          title: 'We could not load the queue',
          message: queue.error?.message ?? 'Please try again.',
          mood: CharacterMood.worried,
          actionLabel: 'Try again',
          onAction: () =>
              ref.read(queueControllerProvider.notifier).refresh(),
        ),
      QueuePhase.offline => StateView(
          title: 'You are offline',
          message: 'We will pick up your queue when you reconnect.',
          mood: CharacterMood.worried,
          actionLabel: 'Try again',
          onAction: () =>
              ref.read(queueControllerProvider.notifier).refresh(),
        ),
      QueuePhase.data => _list(queue),
    };
  }

  Widget _list(QueueState queue) {
    final now = queue.nowDubbing;

    return RefreshIndicator(
      onRefresh: () =>
          ref.read(queueControllerProvider.notifier).refresh(silent: true),
      color: Tokens.clayButton,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          if (now != null) ...[
            const _SectionLabel('Now dubbing'),
            const SizedBox(height: 8),
            _QueueRow(
              project: now,
              nowDubbing: true,
              busy: queue.busyIds.contains(now.id),
              onOpen: () => context.push('/projects/${now.id}'),
              onRemove: () => _confirmRemove(now),
            ),
            const SizedBox(height: 20),
          ],
          if (queue.upNext.isNotEmpty) ...[
            _SectionLabel(
              'Up next',
              trailing: '${queue.upNext.length}',
            ),
            const SizedBox(height: 8),
            _UpNextList(
              items: queue.upNext,
              busyIds: queue.busyIds,
              onOpen: (p) => context.push('/projects/${p.id}'),
              onRemove: _confirmRemove,
              onMoveTop: (p) => _moveTop(p),
              onReorder: (items) => _reorder(items),
            ),
            const SizedBox(height: 20),
          ],
          if (queue.failed.isNotEmpty) ...[
            const _SectionLabel('Failed'),
            const SizedBox(height: 8),
            for (final project in queue.failed) ...[
              _QueueRow(
                project: project,
                nowDubbing: false,
                busy: queue.busyIds.contains(project.id),
                onOpen: () => context.push('/projects/${project.id}'),
                onRetry: () => _retry(project),
                onRemove: () => _confirmRemove(project),
              ),
              const SizedBox(height: 10),
            ],
          ],
        ],
      ),
    );
  }

  Future<void> _confirmRemove(Project project) async {
    final failed = project.status == JobStatus.failed;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Tokens.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusCard),
        ),
        title: Text(
          failed ? 'Dismiss this video?' : 'Remove from queue?',
          style: AppText.pageTitle(),
        ),
        content: Text(
          failed
              ? '"${project.title}" will leave the queue. Its credits were already returned.'
              : '"${project.title}" will not be dubbed, and its credits will be returned.',
          style: AppText.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(foregroundColor: Tokens.muted),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Tokens.clayDeep),
            child: Text(failed ? 'Dismiss' : 'Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await ref.read(queueControllerProvider.notifier).remove(project);
      if (!mounted) return;
      if (!failed) {
        await ref.read(authControllerProvider.notifier).refreshMe();
        if (!mounted) return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(failed
              ? 'Dismissed.'
              : 'Removed. Credits returned.'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not remove it. Please try again.')),
      );
    }
  }

  Future<void> _moveTop(Project project) async {
    try {
      await ref.read(queueControllerProvider.notifier).moveToTop(project);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not move it. Please try again.')),
      );
    }
  }

  Future<void> _reorder(List<Project> items) async {
    try {
      await ref.read(queueControllerProvider.notifier).reorder(items);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save the new order.')),
      );
    }
  }

  Future<void> _retry(Project project) async {
    try {
      await ref.read(queueControllerProvider.notifier).retry(project);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Trying again.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not retry. Please try again.')),
      );
    }
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label, {this.trailing});

  final String label;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label, style: AppText.label.copyWith(fontWeight: FontWeight.w600)),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          Text(trailing!, style: AppText.caption),
        ],
      ],
    );
  }
}

/// The waiting list: numbered, draggable, with remove and move-to-top.
class _UpNextList extends StatelessWidget {
  const _UpNextList({
    required this.items,
    required this.busyIds,
    required this.onOpen,
    required this.onRemove,
    required this.onMoveTop,
    required this.onReorder,
  });

  final List<Project> items;
  final Set<String> busyIds;
  final void Function(Project) onOpen;
  final void Function(Project) onRemove;
  final void Function(Project) onMoveTop;
  final void Function(List<Project>) onReorder;

  @override
  Widget build(BuildContext context) {
    // A scrolling parent (the page ListView) owns the drag for the whole list,
    // so reordering uses explicit buttons rather than a nested reorderable.
    return Column(
      children: [
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _QueueRow(
              project: items[i],
              position: i + 1,
              nowDubbing: false,
              busy: busyIds.contains(items[i].id),
              onOpen: () => onOpen(items[i]),
              onRemove: () => onRemove(items[i]),
              onMoveTop: i == 0 ? null : () => onMoveTop(items[i]),
              onMoveUp: i == 0
                  ? null
                  : () => onReorder([...items]..insert(i - 1, items.removeAt(i))),
              onMoveDown: i == items.length - 1
                  ? null
                  : () => onReorder(
                      [...items]..insert(i + 1, items.removeAt(i))),
            ),
          ),
      ],
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({
    required this.project,
    required this.nowDubbing,
    required this.busy,
    required this.onOpen,
    required this.onRemove,
    this.position,
    this.onRetry,
    this.onMoveTop,
    this.onMoveUp,
    this.onMoveDown,
  });

  final Project project;
  final bool nowDubbing;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback onRemove;
  final int? position;
  final VoidCallback? onRetry;
  final VoidCallback? onMoveTop;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  @override
  Widget build(BuildContext context) {
    final failed = project.status == JobStatus.failed;

    // A failed job already had its credits returned; dismissing it is not
    // the same promise as removing a waiting job.
    Future<void> _confirmDismiss(Project project) async {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: Tokens.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Tokens.radiusCard),
          ),
          title: Text('Dismiss this video?', style: AppText.pageTitle()),
          content: Text(
            '"${project.title}" will leave the queue. Its credits were already returned.',
            style: AppText.body,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              style: TextButton.styleFrom(foregroundColor: Tokens.muted),
              child: const Text('Keep it'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Tokens.clayDeep),
              child: const Text('Dismiss'),
            ),
          ],
        ),
      );
      if (confirmed == true) onRemove();
    }

    return ListTileCard(
      onTap: onOpen,
      padding: const EdgeInsets.fromLTRB(12, 12, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Thumbnail(project: project, position: position),
              const SizedBox(width: 12),
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
                      _meta(project),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.labelMuted,
                    ),
                    const SizedBox(height: 6),
                    _statusChip(project),
                  ],
                ),
              ),
              if (nowDubbing && project.status == JobStatus.processing)
                SizedBox(
                  width: Tokens.minTouchTarget,
                  height: Tokens.minTouchTarget,
                  child: IconButton(
                    onPressed: busy ? null : onRemove,
                    tooltip: 'Cancel dubbing',
                    icon: const Icon(Icons.stop_circle_outlined,
                        size: 22, color: Tokens.muted),
                    padding: EdgeInsets.zero,
                  ),
                ),
              // A failed job needs a way out besides retrying it.
              if (failed)
                SizedBox(
                  width: Tokens.minTouchTarget,
                  height: Tokens.minTouchTarget,
                  child: IconButton(
                    onPressed: busy ? null : () => _confirmDismiss(project),
                    tooltip: 'Dismiss ${project.title}',
                    icon: const Icon(Icons.close_rounded,
                        size: 20, color: Tokens.muted),
                    padding: EdgeInsets.zero,
                  ),
                ),
            ],
          ),
          if (nowDubbing && project.status == JobStatus.processing) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(Tokens.radiusPill),
              child: LinearProgressIndicator(
                value: project.percent / 100,
                minHeight: 6,
                backgroundColor: Tokens.oat,
                valueColor: const AlwaysStoppedAnimation(Tokens.clay),
              ),
            ),
            if (project.step != null) ...[
              const SizedBox(height: 6),
              Text(_stepLabel(project.step!), style: AppText.caption),
            ],
          ],
          if (failed) ...[
            const SizedBox(height: 8),
            Text(
              _failMessage(project.failReason),
              style: AppText.caption.copyWith(color: Tokens.clayDeep),
            ),
            const SizedBox(height: 2),
            Text('Credits returned', style: AppText.caption),
          ],
          // Dismiss sits in the top corner, so the row keeps its primary action.
          const SizedBox(height: 4),
          Row(
            children: [
              if (failed && onRetry != null)
                TextButton(
                  onPressed: busy ? null : onRetry,
                  style: TextButton.styleFrom(
                    foregroundColor: Tokens.clayButton,
                    minimumSize: const Size(0, Tokens.minTouchTarget),
                    textStyle:
                        AppText.label.copyWith(fontWeight: FontWeight.w600),
                  ),
                  child: const Text('Try again'),
                )
              else if (!nowDubbing)
                TextButton(
                  onPressed: busy ? null : onRemove,
                  style: TextButton.styleFrom(
                    foregroundColor: Tokens.muted,
                    minimumSize: const Size(0, Tokens.minTouchTarget),
                    textStyle: AppText.label,
                  ),
                  child: Text(busy ? 'Working…' : 'Remove'),
                ),
              const Spacer(),
              if (!nowDubbing && onMoveTop != null)
                _IconAction(
                  icon: Icons.vertical_align_top_rounded,
                  tooltip: 'Move ${project.title} to the top',
                  onPressed: busy ? null : onMoveTop,
                ),
              if (!nowDubbing && onMoveUp != null)
                _IconAction(
                  icon: Icons.keyboard_arrow_up_rounded,
                  tooltip: 'Move ${project.title} up',
                  onPressed: busy ? null : onMoveUp,
                ),
              if (!nowDubbing && onMoveDown != null)
                _IconAction(
                  icon: Icons.keyboard_arrow_down_rounded,
                  tooltip: 'Move ${project.title} down',
                  onPressed: busy ? null : onMoveDown,
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _meta(Project p) {
    final from = p.sourceLanguage?.toUpperCase() ?? '';
    final to = p.targetLanguage?.toUpperCase() ?? '';
    final pair = from.isEmpty || to.isEmpty ? '' : '$from → $to';
    // A failed or finished job keeps no reserved credits; "0 credits" is noise.
    final credits = (p.credits == null || p.credits == 0 || !p.isActive)
        ? ''
        : '${p.credits} credits';
    return [pair, credits].where((s) => s.isNotEmpty).join(' · ');
  }

  String _stepLabel(String step) => switch (step) {
        'upload' => 'Uploading',
        'transcribe' => 'Transcribing',
        'translate' => 'Translating',
        'generate_voice' => 'Generating voice',
        'mix_export' => 'Mixing and exporting',
        _ => step,
      };

  Widget _statusChip(Project p) {
    return switch (p.status) {
      JobStatus.done => const StatusPill(
          label: 'Done',
          background: Tokens.doneBg,
          foreground: Tokens.doneText,
          icon: Icons.check_circle_rounded,
        ),
      // A job that is working but is not first in line is still queued.
      JobStatus.processing when nowDubbing => StatusPill(
          label: 'Dubbing ${p.percent}%',
          background: Tokens.workingBg,
          foreground: Tokens.workingText,
          icon: Icons.autorenew_rounded,
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
      JobStatus.queued => StatusPill(
          label: p.position == null ? 'Queued' : 'Waiting · ${p.position}',
          background: Tokens.oat,
          foreground: Tokens.clayDeep,
          icon: Icons.schedule_rounded,
        ),
    };
  }

  String _failMessage(String? reason) => switch (reason) {
        'not_enough_credits' => 'There were not enough credits.',
        'unsupported_file' => 'That file type is not supported.',
        'connection_lost' => 'The connection dropped.',
        'upload_failed' => 'The upload did not finish.',
        'max_queue_per_user' => 'Your queue was full.',
        _ => 'Something went wrong.',
      };
}

/// Small square thumbnail; shows the queue place on waiting items.
class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.project, this.position});

  final Project project;
  final int? position;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: Tokens.oat,
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: position == null
          ? const Icon(Icons.play_arrow_rounded,
              size: 26, color: Tokens.clayButton)
          : Text(
              '$position',
              style: AppText.display(22).copyWith(color: Tokens.clayButton),
            ),
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: Tokens.minTouchTarget,
      height: Tokens.minTouchTarget,
      child: IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        icon: Icon(icon, size: 20, color: Tokens.muted),
        padding: EdgeInsets.zero,
      ),
    );
  }
}
import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';
import 'app_widgets.dart';
import 'dubber_character.dart';

/// Project status chip. Always icon + text, never color alone.
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status, required this.label});

  final ProjectStatus status;
  final String label;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, icon) = switch (status) {
      ProjectStatus.done => (Tokens.doneBg, Tokens.doneText, Icons.check_rounded),
      ProjectStatus.working => (Tokens.workingBg, Tokens.workingText, Icons.autorenew_rounded),
      ProjectStatus.queued => (Tokens.oat, Tokens.clayDeep, Icons.schedule_rounded),
      ProjectStatus.failed => (Tokens.softClay, Tokens.clayDeep, Icons.error_outline_rounded),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(Tokens.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 5),
          Text(label, style: AppText.chip.copyWith(color: fg)),
        ],
      ),
    );
  }
}

enum ProjectStatus { queued, working, done, failed }

/// Rounded status pill used by the mockup ("Done", "Dubbing 64%").
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.background,
    required this.foreground,
    this.icon,
  });

  final String label;
  final Color background;
  final Color foreground;

  /// Icon shown before the label. State is never conveyed by color alone.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(icon == null ? 10 : 8, 3, 10, 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(Tokens.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: foreground),
            const SizedBox(width: 5),
          ],
          Text(label, style: AppText.chip.copyWith(color: foreground)),
        ],
      ),
    );
  }
}

/// Screen header: optional back button, title, optional trailing action.
class AppBarRow extends StatelessWidget {
  const AppBarRow({
    super.key,
    required this.title,
    this.onBack,
    this.trailing,
    this.titleSize = 22,
  });

  final String title;
  final VoidCallback? onBack;
  final Widget? trailing;
  final double titleSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (onBack != null)
          SizedBox(
            width: Tokens.minTouchTarget,
            height: Tokens.minTouchTarget,
            child: IconButton(
              onPressed: onBack,
              tooltip: 'Back',
              icon: const Icon(Icons.chevron_left, size: 26),
              color: Tokens.ink,
              padding: EdgeInsets.zero,
            ),
          ),
        Expanded(
          child: Text(
            title,
            style: AppText.display(titleSize),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// Empty / error / offline state: character + title + message + action.
class StateView extends StatelessWidget {
  const StateView({
    super.key,
    required this.title,
    required this.message,
    this.mood = CharacterMood.happy,
    this.actionLabel,
    this.onAction,
    this.compact = false,
  });

  final String title;
  final String message;
  final CharacterMood mood;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Tokens.screenPadding),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            DubberCharacter(size: compact ? 200 : 260, mood: mood),
            const SizedBox(height: 20),
            Text(title, style: AppText.display(24), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              message,
              style: AppText.bodyMuted,
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: 24),
              SizedBox(
                width: 240,
                child: PrimaryButton(label: actionLabel!, onPressed: onAction),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

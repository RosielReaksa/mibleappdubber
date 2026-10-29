import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/tokens.dart';
import '../../features/queue/application/queue_controller.dart';

/// Bottom navigation: Projects, New, Queue, Library.
class DubberTabBar extends ConsumerWidget {
  const DubberTabBar({super.key, required this.currentIndex});

  final int currentIndex;

  static const _tabs = [
    (label: 'Projects', icon: Icons.grid_view_rounded, path: '/projects'),
    (label: 'New', icon: Icons.add_circle_outline_rounded, path: '/new'),
    (label: 'Queue', icon: Icons.queue_rounded, path: '/queue'),
    (label: 'Library', icon: Icons.collections_bookmark_outlined, path: '/library'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The badge counts what is dubbing plus what waits behind it.
    final queued = ref.watch(queueControllerProvider.select((s) => s.badgeCount));

    return Container(
      decoration: const BoxDecoration(
        color: Tokens.white,
        border: Border(top: BorderSide(color: Tokens.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          child: Row(
            children: [
              for (var i = 0; i < _tabs.length; i++)
                Expanded(
                  child: _TabItem(
                    label: _tabs[i].label,
                    icon: _tabs[i].icon,
                    badge: i == 2 && queued > 0 ? queued : 0,
                    selected: i == currentIndex,
                    onTap: () => context.go(_tabs[i].path),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.badge = 0,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Tokens.clayButton : Tokens.muted;
    return Semantics(
      selected: selected,
      button: true,
      label: badge > 0 ? '$label, $badge active' : label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Tokens.radiusButton),
        splashColor: Tokens.clayButton.withValues(alpha: 0.1),
        highlightColor: Colors.transparent,
        child: SizedBox(
          height: 56,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedScale(
                scale: selected ? 1.08 : 1.0,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: Icon(icon, key: ValueKey('$icon-$selected'), size: 24, color: color),
                    ),
                    if (badge > 0)
                      Positioned(
                        right: -10,
                        top: -6,
                        child: Container(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          constraints: const BoxConstraints(minWidth: 16),
                          decoration: BoxDecoration(
                            color: Tokens.clayButton,
                            borderRadius: BorderRadius.circular(Tokens.radiusPill),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            badge > 9 ? '9+' : '$badge',
                            style: AppText.chip.copyWith(
                              color: Tokens.white,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: AppText.chip.copyWith(
                  fontSize: 12,
                  color: color,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
                child: Text(label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Credits pill + avatar, shown at the top right of the main tabs.
class TabHeaderActions extends StatelessWidget {
  const TabHeaderActions({
    super.key,
    required this.credits,
    this.onCredits,
    this.onAccount,
  });

  final int? credits;

  /// Defaults to the credits screen; Library passes its own only when it
  /// needs to disable the pill, so other tabs are unchanged.
  final VoidCallback? onCredits;
  final VoidCallback? onAccount;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          label: 'Credits',
          child: InkWell(
            onTap: onCredits ?? () => context.push('/account/credits'),
            borderRadius: BorderRadius.circular(Tokens.radiusPill),
            child: Container(
              height: Tokens.minTouchTarget,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Tokens.white,
                borderRadius: BorderRadius.circular(Tokens.radiusPill),
                border: Border.all(color: Tokens.borderStrong),
              ),
              child: Text(
                credits == null ? '— credits' : '$credits credits',
                style: AppText.label.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Semantics(
          button: true,
          label: 'Account',
          child: InkWell(
            onTap: onAccount ?? () => context.push('/account'),
            customBorder: const CircleBorder(),
            child: Container(
              width: Tokens.minTouchTarget,
              height: Tokens.minTouchTarget,
              decoration: const BoxDecoration(
                color: Tokens.softClay,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.person_rounded,
                size: 22,
                color: Tokens.clayButton,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

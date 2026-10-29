import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/tab_scaffold.dart';
import '../../app/providers.dart';
import '../../app/theme/tokens.dart';
import '../../core/widgets/app_widgets.dart';
import '../../core/widgets/dubber_character.dart';
import '../../core/widgets/status_chip.dart';
import '../auth/application/auth_controller.dart';
import '../projects/domain/models.dart';
import 'app_update_checker.dart';

class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  List<CreditPack> _packs = const [];
  bool _loadingPacks = true;

  @override
  void initState() {
    super.initState();
    _loadCredits();
  }

  Future<void> _loadCredits() async {
    try {
      final credits = await ref.read(apiProvider).credits();
      await ref.read(authControllerProvider.notifier).setCredits(credits.balance);
      if (!mounted) return;
      setState(() {
        _packs = credits.packs;
        _loadingPacks = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingPacks = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authControllerProvider).session;

    return TabScaffold(
      title: 'Account',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          AppCard(
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: const BoxDecoration(
                    color: Tokens.softClay,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.person_rounded,
                      color: Tokens.clayButton, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session?.name ?? 'Your account',
                        style: AppText.label.copyWith(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(session?.email ?? '', style: AppText.labelMuted),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Credits', style: AppText.label),
                    const Spacer(),
                    Text(
                      '${session?.credits ?? 0}',
                      style: AppText.display(28),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                PrimaryButton(
                  label: 'Buy credits',
                  onPressed: () => _showPacks(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          NeutralButton(
            label: 'Credit history',
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Credit history is coming soon.')),
            ),
          ),
          const SizedBox(height: 12),
          NeutralButton(
            label: 'Learn the editor',
            onPressed: () => context.push('/learn'),
          ),
          const SizedBox(height: 12),
          NeutralButton(
            label: 'Check for updates',
            onPressed: () async {
              await AppUpdateChecker.check(context, ref, manual: true);
              if (mounted) setState(() {});
            },
          ),
          const SizedBox(height: 12),
          NeutralButton(
            label: 'Sign out',
            onPressed: () async {
              await ref.read(authControllerProvider.notifier).logout();
              if (context.mounted) context.go('/login');
            },
          ),
          const SizedBox(height: 12),
          NeutralButton(
            label: 'Delete account',
            onPressed: () => _confirmDelete(context),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              AppUpdateChecker.currentVersion.isEmpty
                  ? 'Dubber'
                  : 'Dubber ${AppUpdateChecker.currentVersion}',
              style: AppText.caption,
            ),
          ),
        ],
      ),
    );
  }

  void _showPacks(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Tokens.ivory,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Tokens.borderStrong,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('Buy credits', style: AppText.sheetTitle()),
              const SizedBox(height: 4),
              Text(
                'Credits are used for each dubbing job.',
                style: AppText.bodyMuted,
              ),
              const SizedBox(height: 16),
              if (_loadingPacks)
                const Center(child: CircularProgressIndicator(strokeWidth: 2.4))
              else if (_packs.isEmpty)
                Text(
                  'Credit packs are not available right now.',
                  style: AppText.labelMuted,
                )
              else
                for (final pack in _packs)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: AppCard(
                      child: Row(
                        children: [
                          Text(
                            '${pack.credits}',
                            style: AppText.display(24),
                          ),
                          const SizedBox(width: 6),
                          Text('credits', style: AppText.labelMuted),
                          const Spacer(),
                          Text(
                            '${pack.currency}${pack.price}',
                            style: AppText.label.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              const SizedBox(height: 8),
              Text(
                'Purchases are completed in the App Store or Google Play.',
                style: AppText.caption,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Tokens.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusCard),
        ),
        title: Text('Delete account?', style: AppText.pageTitle()),
        content: const Text(
          'Your projects and videos will be deleted. This cannot be undone.',
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
    if (confirmed == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Account deletion is not set up yet.'),
        ),
      );
    }
  }
}

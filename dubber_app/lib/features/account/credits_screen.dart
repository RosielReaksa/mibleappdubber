import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme/tokens.dart';
import '../../core/widgets/app_widgets.dart';
import '../../core/widgets/dubber_character.dart';
import '../../core/widgets/status_chip.dart';
import '../auth/application/auth_controller.dart';
import '../projects/domain/models.dart';

/// Account > Credits: balance, packs and history.
class CreditsScreen extends ConsumerStatefulWidget {
  const CreditsScreen({super.key});

  @override
  ConsumerState<CreditsScreen> createState() => _CreditsScreenState();
}

class _CreditsScreenState extends ConsumerState<CreditsScreen> {
  List<CreditPack> _packs = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final credits = await ref.read(apiProvider).credits();
      await ref.read(authControllerProvider.notifier).setCredits(credits.balance);
      if (!mounted) return;
      setState(() {
        _packs = credits.packs;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final balance = ref.watch(authControllerProvider).session?.credits;

    return Scaffold(
      backgroundColor: Tokens.ivory,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: AppBarRow(
                title: 'Credits',
                onBack: () => context.pop(),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(strokeWidth: 2.4))
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      children: [
                        AppCard(
                          child: Row(
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Your balance', style: AppText.label),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${balance ?? 0}',
                                    style: AppText.display(40),
                                  ),
                                ],
                              ),
                              const Spacer(),
                              const Icon(Icons.toll_rounded,
                                  size: 40, color: Tokens.clay),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text('Buy credits', style: AppText.display(20)),
                        const SizedBox(height: 10),
                        if (_packs.isEmpty)
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
                                    Text('${pack.credits}',
                                        style: AppText.display(24)),
                                    const SizedBox(width: 6),
                                    Text('credits',
                                        style: AppText.labelMuted),
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
                        const SizedBox(height: 12),
                        Text(
                          'Purchases are completed in the App Store or Google Play.',
                          style: AppText.caption,
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

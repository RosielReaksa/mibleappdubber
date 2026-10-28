import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/tokens.dart';
import '../../core/widgets/app_widgets.dart';
import '../../core/widgets/controls.dart';
import '../../core/widgets/dubber_character.dart';
import '../../core/widgets/status_chip.dart';

/// Learn page: short guides in groups, with a progress bar.
/// Until `/tutorials` is connected, this uses the groups from the mockup.
class LearnScreen extends StatelessWidget {
  const LearnScreen({super.key});

  static const _groups = {
    'Getting started': [
      ('Upload your first video', '3 steps'),
      ('Pick a language and voice', '4 steps'),
    ],
    'Editing': [
      ('Add text and a logo', '5 steps'),
      ('Blur an old subtitle', '4 steps'),
    ],
    'Sound and export': [
      ('Balance the audio mix', '3 steps'),
      ('Export and share', '3 steps'),
    ],
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Tokens.ivory,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: AppBarRow(
                title: 'Learn',
                onBack: () => context.pop(),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                children: [
                  Center(child: DubberCharacter(size: 190)),
                  const SizedBox(height: 12),
                  Text(
                    'Short guides to get more from Dubber.',
                    textAlign: TextAlign.center,
                    style: AppText.bodyMuted,
                  ),
                  const SizedBox(height: 20),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(Tokens.radiusPill),
                    child: LinearProgressIndicator(
                      value: 0.0,
                      minHeight: 8,
                      backgroundColor: Tokens.oat,
                      valueColor: const AlwaysStoppedAnimation(Tokens.clay),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('0 of 6 guides complete', style: AppText.caption),
                  const SizedBox(height: 20),
                  for (final entry in _groups.entries) ...[
                    Text(entry.key, style: AppText.display(20)),
                    const SizedBox(height: 10),
                    for (final guide in entry.value)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: ListTileCard(
                          onTap: () => ScaffoldMessenger.of(context)
                              .showSnackBar(
                            const SnackBar(
                              content: Text('Guides are coming soon.'),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: Tokens.oat,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.play_circle_outline_rounded,
                                  color: Tokens.clayButton,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      guide.$1,
                                      style: AppText.label.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(guide.$2, style: AppText.caption),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right_rounded,
                                  color: Tokens.muted),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 14),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

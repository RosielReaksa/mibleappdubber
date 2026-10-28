import 'package:flutter/material.dart';

import 'theme/tokens.dart';

/// Shared scaffold used by the main tab screens.
class TabScaffold extends StatelessWidget {
  const TabScaffold({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.largeTitle = true,
  });

  final String title;
  final Widget child;
  final Widget? trailing;
  final bool largeTitle;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Tokens.ivory,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: AppText.display(largeTitle ? 28 : 22),
                    ),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

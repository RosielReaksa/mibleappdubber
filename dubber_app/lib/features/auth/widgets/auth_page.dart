import 'package:flutter/material.dart';

import '../../../app/theme/tokens.dart';

/// Ivory, safe-area aware, scrollable page frame for auth screens.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Tokens.ivory,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 40, 28, 32),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 72,
                ),
                child: IntrinsicHeight(child: child),
              ),
            );
          },
        ),
      ),
    );
  }
}

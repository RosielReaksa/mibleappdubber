import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'features/auth/application/auth_controller.dart';
import 'features/queue/application/queue_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: _Bootstrap()));
}

class _Bootstrap extends ConsumerStatefulWidget {
  const _Bootstrap();

  @override
  ConsumerState<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends ConsumerState<_Bootstrap>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Restore a saved session before the router decides where to go.
    Future.microtask(() async {
      await ref.read(authControllerProvider.notifier).restore();
      if (!mounted) return;
      if (ref.read(authControllerProvider).isLoggedIn) {
        // Watch the queue from launch so the tab badge and the finish
        // notification are live on every screen, not only on the Queue tab.
        ref.read(queueControllerProvider.notifier).setVisible(false);
        await ref.read(queueControllerProvider.notifier).refresh();
      }
    });
  }

  @override
  void dispose() {
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
  Widget build(BuildContext context) => const DubberApp();
}

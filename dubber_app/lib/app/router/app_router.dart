import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/account/credits_screen.dart';
import '../../features/account/account_screen.dart';
import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/forgot_password_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/signup_screen.dart';
import '../../features/editor/editor_screen.dart';
import '../../features/export/export_screen.dart';
import '../../features/jobs/progress_screen.dart';
import '../../features/library/library_screen.dart';
import '../../features/library/widgets/library_widgets.dart';
import '../../features/new_project/new_project_screen.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/projects/projects_screen.dart';
import '../../features/queue/queue_screen.dart';
import '../../features/result/result_screen.dart';
import '../../features/tutorials/learn_screen.dart';
import 'dubber_tab_bar.dart';

/// Router with a shell for the four tabs.
final routerProvider = Provider<GoRouter>((ref) {
  final auth = ValueNotifier<AuthState>(const AuthState());
  ref.listen(authControllerProvider, (_, next) => auth.value = next,
      fireImmediately: true);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: auth,
    redirect: (context, state) {
      final a = auth.value;
      final path = state.matchedLocation;
      final onAuthScreen = path == '/login' ||
          path == '/signup' ||
          path == '/forgot' ||
          path == '/onboarding';

      if (!a.checked) {
        return path == '/splash' ? null : '/splash';
      }
      if (path == '/splash') {
        return a.isLoggedIn ? '/projects' : '/login';
      }
      if (!a.isLoggedIn && !onAuthScreen) return '/login';
      if (a.isLoggedIn && onAuthScreen) return '/projects';
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const _SplashScreen()),
      GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/signup', builder: (_, __) => const SignupScreen()),
      GoRoute(path: '/forgot', builder: (_, __) => const ForgotPasswordScreen()),

      // Tabs
      ShellRoute(
        builder: (context, state, child) {
          final index = switch (state.matchedLocation) {
            final p when p.startsWith('/new') => 1,
            final p when p.startsWith('/queue') => 2,
            final p when p.startsWith('/library') => 3,
            _ => 0,
          };
          return Scaffold(
            backgroundColor: const Color(0xFFFAF9F5),
            body: child,
            bottomNavigationBar: DubberTabBar(currentIndex: index),
          );
        },
        routes: [
          GoRoute(path: '/projects', builder: (_, __) => const ProjectsScreen()),
          GoRoute(
            path: '/new',
            builder: (_, state) => NewProjectScreen(
              templateId: state.uri.queryParameters['template'],
              presetId: state.uri.queryParameters['preset'],
            ),
          ),
          GoRoute(path: '/queue', builder: (_, __) => const QueueScreen()),
          // /library replaced /templates. The old path redirects so any
          // existing link (including the template banner's "Change") works.
          GoRoute(
            path: '/templates',
            redirect: (_, __) => '/library',
          ),
          GoRoute(
            path: '/library',
            builder: (_, state) => LibraryScreen(
              section: LibrarySectionX.fromWire(
                state.uri.queryParameters['section'],
              ),
            ),
          ),
        ],
      ),

      // Account is pushed from the avatar, not a tab.
      GoRoute(
        path: '/account',
        builder: (_, __) => const AccountScreen(),
        routes: [
          GoRoute(
            path: 'credits',
            builder: (_, __) => const CreditsScreen(),
          ),
        ],
      ),

      // Full-screen routes
      GoRoute(
        path: '/projects/:id',
        builder: (_, state) => ProgressScreen(projectId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/projects/:id/result',
        builder: (_, state) => ResultScreen(projectId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/projects/:id/editor',
        builder: (_, state) => EditorScreen(projectId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/projects/:id/export/:exportId',
        builder: (_, state) => ExportScreen(
          projectId: state.pathParameters['id']!,
          exportId: state.pathParameters['exportId']!,
        ),
      ),
      GoRoute(path: '/learn', builder: (_, __) => const LearnScreen()),
    ],
  );
});

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFFFAF9F5),
      body: Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
      ),
    );
  }
}

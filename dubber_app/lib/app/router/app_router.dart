import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/tokens.dart';
import '../../core/widgets/app_widgets.dart';
import '../../core/widgets/dubber_character.dart';
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

/// Helper creating smooth iOS-style slide and subtle fade transitions between routes.
CustomTransitionPage<T> _buildSmoothPage<T>({
  required LocalKey key,
  required Widget child,
}) {
  return CustomTransitionPage<T>(
    key: key,
    child: child,
    transitionDuration: const Duration(milliseconds: 280),
    reverseTransitionDuration: const Duration(milliseconds: 240),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: Tween<double>(begin: 0.0, end: 1.0).animate(curved),
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.04, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Helper for tabs: quick smooth crossfade without horizontal sliding.
CustomTransitionPage<T> _buildTabPage<T>({
  required LocalKey key,
  required Widget child,
}) {
  return CustomTransitionPage<T>(
    key: key,
    child: child,
    transitionDuration: const Duration(milliseconds: 220),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: CurvedAnimation(
          parent: animation,
          curve: Curves.easeInOut,
        ),
        child: child,
      );
    },
  );
}

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
      GoRoute(
        path: '/splash',
        pageBuilder: (context, state) => _buildTabPage(
          key: state.pageKey,
          child: const _SplashScreen(),
        ),
      ),
      GoRoute(
        path: '/onboarding',
        pageBuilder: (context, state) => _buildSmoothPage(
          key: state.pageKey,
          child: const OnboardingScreen(),
        ),
      ),
      GoRoute(
        path: '/login',
        pageBuilder: (context, state) => _buildSmoothPage(
          key: state.pageKey,
          child: const LoginScreen(),
        ),
      ),
      GoRoute(
        path: '/signup',
        pageBuilder: (context, state) => _buildSmoothPage(
          key: state.pageKey,
          child: const SignupScreen(),
        ),
      ),
      GoRoute(
        path: '/forgot',
        pageBuilder: (context, state) => _buildSmoothPage(
          key: state.pageKey,
          child: const ForgotPasswordScreen(),
        ),
      ),

      // Persistent Tab Shell preserving widget tree state for instant switching
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return Scaffold(
            backgroundColor: const Color(0xFFFAF9F5),
            body: navigationShell,
            bottomNavigationBar: DubberTabBar(
              currentIndex: navigationShell.currentIndex,
              onTapTab: (index) {
                navigationShell.goBranch(
                  index,
                  initialLocation: index == navigationShell.currentIndex,
                );
              },
            ),
          );
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/projects',
                builder: (_, __) => const ProjectsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/new',
                builder: (_, state) => NewProjectScreen(
                  templateId: state.uri.queryParameters['template'],
                  presetId: state.uri.queryParameters['preset'],
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/queue',
                builder: (_, __) => const QueueScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/library',
                builder: (_, state) => LibraryScreen(
                  section: LibrarySectionX.fromWire(
                    state.uri.queryParameters['section'],
                  ),
                ),
              ),
              GoRoute(
                path: '/templates',
                redirect: (_, __) => '/library',
              ),
            ],
          ),
        ],
      ),

      // Account is pushed from the avatar, not a tab.
      GoRoute(
        path: '/account',
        pageBuilder: (context, state) => _buildSmoothPage(
          key: state.pageKey,
          child: const AccountScreen(),
        ),
        routes: [
          GoRoute(
            path: 'credits',
            pageBuilder: (context, state) => _buildSmoothPage(
              key: state.pageKey,
              child: const CreditsScreen(),
            ),
          ),
        ],
      ),

      // Full-screen routes
      GoRoute(
        path: '/projects/:id',
        pageBuilder: (context, state) => _buildSmoothPage(
          key: state.pageKey,
          child: ProgressScreen(projectId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/projects/:id/result',
        pageBuilder: (context, state) => _buildSmoothPage(
          key: state.pageKey,
          child: ResultScreen(projectId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/projects/:id/editor',
        pageBuilder: (context, state) => _buildSmoothPage(
          key: state.pageKey,
          child: EditorScreen(projectId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/projects/:id/export/:exportId',
        pageBuilder: (context, state) => _buildSmoothPage(
          key: state.pageKey,
          child: ExportScreen(
            projectId: state.pathParameters['id']!,
            exportId: state.pathParameters['exportId']!,
          ),
        ),
      ),
      GoRoute(
        path: '/learn',
        pageBuilder: (context, state) => _buildSmoothPage(
          key: state.pageKey,
          child: const LearnScreen(),
        ),
      ),
    ],
  );
});

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Tokens.ivory,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const DubberCharacter(size: 200),
              const SizedBox(height: 24),
              Text(
                'Dubber',
                style: AppText.display(32),
              ),
              const SizedBox(height: 6),
              Text(
                'Dub any video in a few taps',
                style: AppText.bodyMuted.copyWith(fontSize: 15),
              ),
              const SizedBox(height: 36),
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  valueColor: AlwaysStoppedAnimation(Tokens.clayButton),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

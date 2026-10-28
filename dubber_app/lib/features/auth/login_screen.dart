import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/tokens.dart';
import '../../core/widgets/app_widgets.dart';
import 'application/auth_controller.dart';
import 'widgets/auth_page.dart';
import 'widgets/brand_mark.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _fieldError;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _fieldError = 'Enter your email and password.');
      return;
    }
    setState(() => _fieldError = null);
    final ok = await ref
        .read(authControllerProvider.notifier)
        .login(email: email, password: password);
    if (ok && mounted) context.go('/projects');
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final serverError = auth.error;

    return AuthScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const BrandMark(),
          const SizedBox(height: 28),
          Text(
            'Dub any video into your language',
            style: AppText.display(32),
          ),
          const SizedBox(height: 12),
          Text(
            'Upload, pick a language, get your dubbed video back.',
            style: AppText.bodyMuted,
          ),
          const SizedBox(height: 28),
          AppTextField(
            label: 'Email',
            hint: 'you@email.com',
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            errorText: _fieldError,
            autofillHints: const [AutofillHints.email],
          ),
          const SizedBox(height: 16),
          AppTextField(
            label: 'Password',
            hint: 'Password',
            controller: _password,
            obscure: true,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.password],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => context.push('/forgot'),
              style: TextButton.styleFrom(
                foregroundColor: Tokens.clayButton,
                textStyle: AppText.label,
                minimumSize: const Size(0, Tokens.minTouchTarget),
              ),
              child: const Text('Forgot password?'),
            ),
          ),
          if (serverError != null) ...[
            const SizedBox(height: 4),
            Text(
              serverError.message,
              style: AppText.caption.copyWith(color: Tokens.clayDeep),
            ),
          ],
          const SizedBox(height: 8),
          PrimaryButton(
            label: 'Log in',
            loading: auth.loading,
            onPressed: _submit,
          ),
          const SizedBox(height: 16),
          NeutralButton(
            label: 'Continue with Google',
            onPressed: () => _showComingSoon(context),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('New here? ', style: AppText.labelMuted.copyWith(fontSize: 15)),
                GestureDetector(
                  onTap: () => context.push('/signup'),
                  child: Text(
                    'Create account',
                    style: AppText.label.copyWith(
                      fontSize: 15,
                      color: Tokens.clayButton,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showComingSoon(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Google sign-in is coming soon.')),
    );
  }
}

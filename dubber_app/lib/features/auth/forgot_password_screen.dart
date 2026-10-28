import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/tokens.dart';
import '../../core/widgets/app_widgets.dart';
import 'application/auth_controller.dart';
import 'widgets/auth_page.dart';
import 'widgets/brand_mark.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _email = TextEditingController();
  bool _sent = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    if (email.isEmpty) return;
    final ok = await ref
        .read(authControllerProvider.notifier)
        .forgotPassword(email);
    if (ok && mounted) setState(() => _sent = true);
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);

    return AuthScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const BrandMark(fontSize: 26),
          const SizedBox(height: 28),
          if (_sent) ...[
            Text('Check your email', style: AppText.display(32)),
            const SizedBox(height: 12),
            Text(
              'We sent a link to ${_email.text.trim()}. Open it to set a new password.',
              style: AppText.bodyMuted,
            ),
            const SizedBox(height: 28),
            PrimaryButton(
              label: 'Back to log in',
              onPressed: () => context.go('/login'),
            ),
          ] else ...[
            Text('Forgot your password?', style: AppText.display(32)),
            const SizedBox(height: 12),
            Text(
              'Enter your email and we will send you a reset link.',
              style: AppText.bodyMuted,
            ),
            const SizedBox(height: 28),
            AppTextField(
              label: 'Email',
              hint: 'you@email.com',
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.email],
            ),
            if (auth.error != null) ...[
              const SizedBox(height: 12),
              Text(
                auth.error!.message,
                style: AppText.caption.copyWith(color: Tokens.clayDeep),
              ),
            ],
            const SizedBox(height: 24),
            PrimaryButton(
              label: 'Send reset link',
              loading: auth.loading,
              onPressed: _submit,
            ),
          ],
          const Spacer(),
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: GestureDetector(
              onTap: () => context.go('/login'),
              child: Text(
                'Back to log in',
                textAlign: TextAlign.center,
                style: AppText.label.copyWith(
                  fontSize: 15,
                  color: Tokens.clayButton,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

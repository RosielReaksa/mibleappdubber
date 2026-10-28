import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/tokens.dart';
import '../../core/widgets/app_widgets.dart';
import 'application/auth_controller.dart';
import 'widgets/auth_page.dart';
import 'widgets/brand_mark.dart';

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _showPassword = false;
  bool _acceptedTerms = false;
  String? _fieldError;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final email = _email.text.trim();
    final password = _password.text;

    if (name.isEmpty || email.isEmpty || password.length < 8) {
      setState(() => _fieldError =
          'Enter your name, a valid email, and a password of 8 or more characters.');
      return;
    }
    if (!_acceptedTerms) {
      setState(() => _fieldError = 'Please accept the terms to continue.');
      return;
    }
    setState(() => _fieldError = null);

    final ok = await ref
        .read(authControllerProvider.notifier)
        .register(name: name, email: email, password: password);
    if (ok && mounted) context.go('/projects');
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);

    return AuthScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const BrandMark(),
          const SizedBox(height: 28),
          Text('Create your account', style: AppText.display(32)),
          const SizedBox(height: 12),
          Text(
            'Start dubbing videos in a few taps.',
            style: AppText.bodyMuted,
          ),
          const SizedBox(height: 28),
          AppTextField(
            label: 'Name',
            hint: 'Your name',
            controller: _name,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.name],
          ),
          const SizedBox(height: 16),
          AppTextField(
            label: 'Email',
            hint: 'you@email.com',
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email],
          ),
          const SizedBox(height: 16),
          AppTextField(
            label: 'Password',
            hint: 'At least 8 characters',
            controller: _password,
            obscure: !_showPassword,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.newPassword],
            trailing: IconButton(
              onPressed: () => setState(() => _showPassword = !_showPassword),
              tooltip: _showPassword ? 'Hide password' : 'Show password',
              icon: Icon(
                _showPassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: Tokens.muted,
              ),
            ),
          ),
          const SizedBox(height: 20),
          _TermsCheckbox(
            value: _acceptedTerms,
            onChanged: (v) => setState(() => _acceptedTerms = v),
          ),
          if (_fieldError != null) ...[
            const SizedBox(height: 12),
            Text(
              _fieldError!,
              style: AppText.caption.copyWith(color: Tokens.clayDeep),
            ),
          ],
          if (auth.error != null) ...[
            const SizedBox(height: 12),
            Text(
              auth.error!.message,
              style: AppText.caption.copyWith(color: Tokens.clayDeep),
            ),
          ],
          const SizedBox(height: 24),
          PrimaryButton(
            label: 'Create account',
            loading: auth.loading,
            onPressed: _submit,
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Already have an account? ',
                  style: AppText.labelMuted.copyWith(fontSize: 15),
                ),
                GestureDetector(
                  onTap: () => context.go('/login'),
                  child: Text(
                    'Log in',
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
}

class _TermsCheckbox extends StatelessWidget {
  const _TermsCheckbox({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      checked: value,
      label: 'I own this video or have permission to use it, and I accept the terms',
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(Tokens.radiusButton),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: Checkbox(
                  value: value,
                  onChanged: (v) => onChanged(v ?? false),
                  activeColor: Tokens.clayButton,
                  side: const BorderSide(color: Tokens.borderStrong, width: 1.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'I own this video or have permission to use it, and I accept the terms.',
                  style: AppText.labelMuted.copyWith(height: 1.4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

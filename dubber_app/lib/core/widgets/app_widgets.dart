import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';

/// Primary clay button: 52 high, full width, radius 14.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    return SizedBox(
      width: double.infinity,
      height: Tokens.buttonHeight,
      child: FilledButton(
        onPressed: enabled ? onPressed : null,
        style: FilledButton.styleFrom(
          backgroundColor: Tokens.clayButton,
          foregroundColor: Tokens.white,
          disabledBackgroundColor: Tokens.clayButton.withValues(alpha: 0.45),
          disabledForegroundColor: Tokens.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Tokens.radiusButton),
          ),
          textStyle: AppText.button,
          padding: EdgeInsets.zero,
        ),
        child: loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  valueColor: AlwaysStoppedAnimation(Tokens.white),
                ),
              )
            : Text(label),
      ),
    );
  }
}

/// Outlined button in clay, used for secondary actions ("Share", "Notify me").
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: Tokens.buttonHeight,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: Tokens.clayButton,
          side: const BorderSide(color: Tokens.clayButton, width: 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Tokens.radiusButton),
          ),
          textStyle: AppText.button,
          padding: const EdgeInsets.symmetric(horizontal: 20),
        ),
        child: icon == null
            ? Text(label)
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 20),
                  const SizedBox(width: 8),
                  Text(label),
                ],
              ),
      ),
    );
  }
}

/// Neutral button: white fill, ink text ("Continue with Google", "Edit video").
class NeutralButton extends StatelessWidget {
  const NeutralButton({super.key, required this.label, this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: Tokens.buttonHeight,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: Tokens.white,
          foregroundColor: Tokens.ink,
          side: const BorderSide(color: Tokens.borderStrong, width: 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Tokens.radiusButton),
          ),
          textStyle: AppText.button.copyWith(color: Tokens.ink),
        ),
        child: Text(label),
      ),
    );
  }
}

/// White card with a 20 radius and hairline border.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = Tokens.radiusCard,
    this.selected = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Tokens.white,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: selected ? Tokens.clayButton : Tokens.border,
          width: selected ? 2 : 1,
        ),
      ),
      child: child,
    );
  }
}

/// Text input styled like the mockup: 52 high, white, radius 14.
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.label,
    this.controller,
    this.hint,
    this.obscure = false,
    this.keyboardType,
    this.errorText,
    this.enabled = true,
    this.onChanged,
    this.trailing,
    this.textInputAction,
    this.autofillHints,
  });

  final String label;
  final TextEditingController? controller;
  final String? hint;
  final bool obscure;
  final TextInputType? keyboardType;
  final String? errorText;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final Widget? trailing;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppText.label),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboardType,
          enabled: enabled,
          onChanged: onChanged,
          textInputAction: textInputAction,
          autofillHints: autofillHints,
          style: AppText.body.copyWith(fontSize: 16),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: AppText.body.copyWith(color: Tokens.muted),
            filled: true,
            fillColor: Tokens.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14),
            suffixIcon: trailing,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Tokens.radiusField),
              borderSide: const BorderSide(color: Tokens.borderStrong),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Tokens.radiusField),
              borderSide: const BorderSide(color: Tokens.clayButton, width: 2),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Tokens.radiusField),
              borderSide: const BorderSide(color: Tokens.border),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Tokens.radiusField),
              borderSide: const BorderSide(color: Tokens.clayDeep),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Tokens.radiusField),
              borderSide: const BorderSide(color: Tokens.clayDeep, width: 2),
            ),
          ),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 6),
          Text(
            errorText!,
            style: AppText.caption.copyWith(color: Tokens.clayDeep),
          ),
        ],
      ],
    );
  }
}

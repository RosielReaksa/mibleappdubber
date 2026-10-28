import 'package:flutter/material.dart';

/// Design tokens taken from the Dubber mockup.
///
/// Only these colors may be used in the app. See section 5 of the build spec.
abstract final class Tokens {
  // Colors
  static const ivory = Color(0xFFFAF9F5);
  static const ink = Color(0xFF141413);
  static const muted = Color(0xFF66655E);
  static const clay = Color(0xFFD97757);
  static const clayButton = Color(0xFFB5502D);
  static const softClay = Color(0xFFF6E7DF);
  static const oat = Color(0xFFF0EEE6);
  static const border = Color(0xFFE8E5DA);
  static const borderStrong = Color(0xFFD9D6CB);
  static const white = Color(0xFFFFFFFF);

  static const doneText = Color(0xFF3F5B2A);
  static const doneBg = Color(0xFFE3EBD9);
  static const workingText = Color(0xFF7A4A12);
  static const workingBg = Color(0xFFF6E7C6);

  // Mockup-only accents (used by the mockup for upload/segment states).
  static const uploadBorder = Color(0xFFD9A58F);
  static const clayDeep = Color(0xFF8A3F22);
  static const segmentBg = Color(0xFFEDEAE0);
  static const bodyOnChip = Color(0xFF4A4943);

  // Shape
  static const radiusCard = 20.0;
  static const radiusButton = 14.0;
  static const radiusField = 14.0;
  static const radiusPill = 999.0;

  // Spacing
  static const screenPadding = 20.0;
  static const buttonHeight = 52.0;
  static const minTouchTarget = 44.0;

  // Type
  static const fontBody = 'Inter';
  static const fontHeading = 'Newsreader';
}

/// Text styles matching the mockup's type scale.
abstract final class AppText {
  static const _heading = TextStyle(
    fontFamily: Tokens.fontHeading,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.01,
    color: Tokens.ink,
    height: 1.15,
  );

  static TextStyle display(double size) => _heading.copyWith(fontSize: size);
  static TextStyle screenTitle() => _heading.copyWith(fontSize: 28);
  static TextStyle pageTitle() => _heading.copyWith(fontSize: 22);
  static TextStyle sheetTitle() => _heading.copyWith(fontSize: 24);
  static TextStyle percent(double size) =>
      _heading.copyWith(fontSize: size, height: 1.0);

  static const body = TextStyle(
    fontFamily: Tokens.fontBody,
    fontSize: 16,
    height: 1.5,
    color: Tokens.ink,
  );

  static const bodyMuted = TextStyle(
    fontFamily: Tokens.fontBody,
    fontSize: 16,
    height: 1.5,
    color: Tokens.muted,
  );

  static const label = TextStyle(
    fontFamily: Tokens.fontBody,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: Tokens.ink,
  );

  static const labelMuted = TextStyle(
    fontFamily: Tokens.fontBody,
    fontSize: 14,
    color: Tokens.muted,
  );

  static const caption = TextStyle(
    fontFamily: Tokens.fontBody,
    fontSize: 12,
    color: Tokens.muted,
  );

  static const button = TextStyle(
    fontFamily: Tokens.fontBody,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: Tokens.white,
  );

  static const chip = TextStyle(
    fontFamily: Tokens.fontBody,
    fontSize: 12,
    fontWeight: FontWeight.w600,
  );
}

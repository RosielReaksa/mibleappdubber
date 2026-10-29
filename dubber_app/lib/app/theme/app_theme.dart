import 'package:flutter/material.dart';

import 'tokens.dart';

/// App theme built from [Tokens]. The app is light-only by design.
ThemeData buildAppTheme() {
  final base = ThemeData.light(useMaterial3: true);

  return base.copyWith(
    scaffoldBackgroundColor: Tokens.ivory,
    colorScheme: const ColorScheme.light(
      primary: Tokens.clayButton,
      onPrimary: Tokens.white,
      secondary: Tokens.clay,
      onSecondary: Tokens.white,
      surface: Tokens.white,
      onSurface: Tokens.ink,
      error: Tokens.clayDeep,
      onError: Tokens.white,
      outline: Tokens.borderStrong,
    ),
    textTheme: base.textTheme.apply(
      fontFamily: Tokens.fontBody,
      bodyColor: Tokens.ink,
      displayColor: Tokens.ink,
    ),
    dividerColor: Tokens.border,
    splashFactory: InkSparkle.splashFactory,
    visualDensity: VisualDensity.standard,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
  );
}

import 'package:flutter/material.dart';

abstract final class AppColors {
  static const ink = Color(0xFF030303);
  static const panel = Color(0xFF101010);
  static const panelRaised = Color(0xFF191919);
  static const textPrimary = Color(0xFFF8F5F6);
  static const textMuted = Color(0xFFB7AEB1);
  static const accent = Color(0xFFE52B50);
  static const accentBright = Color(0xFFFF496A);
  static const cyan = Color(0xFFFF7188);
}

abstract final class AppTheme {
  static final dark = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.ink,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.accent,
      secondary: AppColors.cyan,
      surface: AppColors.panel,
      onSurface: AppColors.textPrimary,
    ),
    textTheme: const TextTheme(
      displaySmall: TextStyle(
        color: AppColors.textPrimary,
        fontSize: 38,
        height: 1.05,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.2,
      ),
      headlineSmall: TextStyle(
        color: AppColors.textPrimary,
        fontSize: 24,
        fontWeight: FontWeight.w700,
      ),
      titleLarge: TextStyle(
        color: AppColors.textPrimary,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: TextStyle(
        color: AppColors.textPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w700,
      ),
      bodyLarge: TextStyle(
        color: AppColors.textMuted,
        fontSize: 16,
        height: 1.45,
      ),
      bodyMedium: TextStyle(
        color: AppColors.textMuted,
        fontSize: 14,
        height: 1.35,
      ),
      labelLarge: TextStyle(
        color: AppColors.textPrimary,
        fontSize: 15,
        fontWeight: FontWeight.w700,
        letterSpacing: .2,
      ),
    ),
    visualDensity: VisualDensity.standard,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
  );
}

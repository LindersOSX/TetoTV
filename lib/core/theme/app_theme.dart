import 'package:flutter/material.dart';

abstract final class AppColors {
  static const ink = Color(0xFF030303);
  static const panel = Color(0xFF101010);
  static const panelRaised = Color(0xFF1B0E12);
  static const selectableSurface = Color(0xFF271016);
  static const selectableSurfaceHover = Color(0xFF3B131D);
  static const textPrimary = Color(0xFFF8F5F6);
  static const textMuted = Color(0xFFB7AEB1);
  static const accent = Color(0xFFE52B50);
  static const accentBright = Color(0xFFFF496A);
  static const focusRing = Color(0xFFFF5C78);
  static const focusGlow = Color(0x99FF365C);
  static const focusInnerKeyline = Color(0xE6000000);
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
    focusColor: AppColors.focusRing.withValues(alpha: .22),
    hoverColor: AppColors.accent.withValues(alpha: .18),
    highlightColor: AppColors.accent.withValues(alpha: .16),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.focused)
              ? AppColors.selectableSurfaceHover
              : AppColors.selectableSurface,
        ),
        side: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.focused)
              ? const BorderSide(color: AppColors.focusRing, width: 2)
              : BorderSide(color: AppColors.accent.withValues(alpha: .42)),
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        foregroundColor: const WidgetStatePropertyAll(Colors.white),
        overlayColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.focused)
              ? AppColors.focusRing.withValues(alpha: .22)
              : null,
        ),
        side: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.focused)
              ? const BorderSide(color: AppColors.focusRing, width: 2)
              : BorderSide.none,
        ),
      ),
    ),
  );
}

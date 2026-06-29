import 'package:flutter/material.dart';

import 'app_tokens.dart';

class AppTheme {
  // Brand Colors
  static const Color primaryBlue = Color(0xFF1565C0);
  static const Color darkBlue = Color(0xFF0D47A1);
  static const Color successGreen = Color(0xFF00C853);
  static const Color warningOrange = Color(0xFFFFA000);
  static const Color dangerRed = Color(0xFFD32F2F);

  static const Color background = Color(0xFFF5F7FA);
  static const Color cardColor = Colors.white;
  static const Color darkBackground = Color(0xFF121212);
  static const Color ink = Color(0xFF172033);
  static const Color mutedInk = Color(0xFF657083);
  static const Color surfaceTint = Color(0xFFEAF2FF);

  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: background,
    visualDensity: VisualDensity.standard,

    colorScheme: ColorScheme.fromSeed(
      seedColor: primaryBlue,
      primary: primaryBlue,
      secondary: successGreen,
      tertiary: warningOrange,
      error: dangerRed,
      surface: cardColor,
      surfaceContainerHighest: surfaceTint,
    ),

    textTheme: const TextTheme(
      headlineSmall: TextStyle(
        fontWeight: FontWeight.w800,
        color: ink,
      ),
      titleLarge: TextStyle(
        fontWeight: FontWeight.w800,
        color: ink,
      ),
      titleMedium: TextStyle(
        fontWeight: FontWeight.w700,
        color: ink,
      ),
      bodyMedium: TextStyle(
        color: ink,
      ),
      labelLarge: TextStyle(
        fontWeight: FontWeight.w700,
      ),
    ),

    appBarTheme: const AppBarTheme(
      backgroundColor: background,
      foregroundColor: ink,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      elevation: 0,
      titleTextStyle: TextStyle(
        color: ink,
        fontSize: 20,
        fontWeight: FontWeight.w800,
      ),
    ),

    cardTheme: CardThemeData(
      elevation: AppElevation.low,
      color: cardColor,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryBlue,
        foregroundColor: Colors.white,
        elevation: AppElevation.flat,
        minimumSize: const Size(double.infinity, 52),
        textStyle: const TextStyle(
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(120, 48),
        textStyle: const TextStyle(
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(120, 48),
        textStyle: const TextStyle(
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: const BorderSide(
          color: Color(0xFFD9E2F1),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: const BorderSide(
          color: Color(0xFFD9E2F1),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: const BorderSide(
          color: primaryBlue,
          width: 2,
        ),
      ),
    ),
  );

  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: darkBackground,
    visualDensity: VisualDensity.standard,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primaryBlue,
      brightness: Brightness.dark,
    ),
    cardTheme: CardThemeData(
      elevation: AppElevation.low,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
    ),
  );
}

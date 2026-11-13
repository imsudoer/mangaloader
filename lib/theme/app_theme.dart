import 'package:flutter/material.dart';
import 'package:mangaloader/theme/app_tokens.dart';

class AppTheme {
  // Brand Palette: ["#353535", "#ffffff", "#d2d7df", "#bdbbb0", "#8a897c"]
  static const colorCharcoal = AppTokens.border;
  static const colorWhite = Color(0xFFFFFFFF);
  static const colorCoolSilver = AppTokens.textPrimary;
  static const colorWarmStone = AppTokens.textSecondary;
  static const colorDeepSlate = AppTokens.accent;

  // Dark Theme specifics
  static const _darkBackground = Color(0xFF161616);
  static const _darkSurface = Color(0xFF202020);
  static const _darkSurfaceVariant = AppTokens.surfaceRaised;
  static const _darkOnSurface = Color(0xFFFFFFFF);
  static const _darkOnSurfaceVariant = AppTokens.textPrimary;
  
  // Accents
  static const _darkPrimary = AppTokens.textPrimary; // Accent 1 (Crisp Platinum)
  static const _darkPrimaryContainer = AppTokens.accent; // Deep Slate Accent
  static const _darkOnPrimary = Color(0xFF161616);
  static const _darkSecondary = AppTokens.textSecondary; // Accent 2 (Warm Stone)
  static const _darkSecondaryContainer = Color(0xFF3A3934);
  static const _darkOnSecondaryContainer = Color(0xFFFFFFFF);
  static const _darkTertiary = AppTokens.accent;
  static const _darkOnTertiary = Color(0xFFFFFFFF);
  static const _darkError = Color(0xFFFF6B6B);

  // Light Theme specifics
  static const _lightBackground = Color(0xFFF8F9FA);
  static const _lightSurface = Color(0xFFFFFFFF);
  static const _lightSurfaceVariant = Color(0xFFEDEFE4);
  static const _lightOnSurface = Color(0xFF222222);
  static const _lightOnSurfaceVariant = Color(0xFF6B6A62);
  static const _lightPrimary = AppTokens.border;
  static const _lightPrimaryContainer = AppTokens.textPrimary;
  static const _lightOnPrimary = Color(0xFFFFFFFF);
  static const _lightSecondary = AppTokens.accent;
  static const _lightSecondaryContainer = Color(0xFFEAE9E4);
  static const _lightOnSecondaryContainer = AppTokens.border;
  static const _lightTertiary = AppTokens.accent;
  static const _lightOnTertiary = Color(0xFFFFFFFF);
  static const _lightError = Color(0xFFD32F2F);

  static const List<String> _fontFallbacks = [
    'Segoe UI',
    'Roboto',
    'Helvetica Neue',
    'Arial',
    'sans-serif',
  ];

  static TextTheme _buildTextTheme(Color onSurface, Color onSurfaceVariant) {
    return TextTheme(
      displayLarge: TextStyle(
        fontFamilyFallback: _fontFallbacks,
        fontSize: 28,
        fontWeight: FontWeight.w800,
        color: onSurface,
        letterSpacing: -0.6,
      ),
      displayMedium: TextStyle(
        fontFamilyFallback: _fontFallbacks,
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: onSurface,
        letterSpacing: -0.4,
      ),
      headlineLarge: TextStyle(
        fontFamilyFallback: _fontFallbacks,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: onSurface,
        letterSpacing: -0.2,
      ),
      headlineMedium: TextStyle(
        fontFamilyFallback: _fontFallbacks,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: onSurface,
      ),
      titleLarge: TextStyle(
        fontFamilyFallback: _fontFallbacks,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: onSurface,
      ),
      titleMedium: TextStyle(
        fontFamilyFallback: _fontFallbacks,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: onSurface,
      ),
      titleSmall: TextStyle(
        fontFamilyFallback: _fontFallbacks,
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: onSurfaceVariant,
      ),
      bodyLarge: TextStyle(
        fontFamilyFallback: _fontFallbacks,
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: onSurface,
        height: 1.5,
      ),
      bodyMedium: TextStyle(
        fontFamilyFallback: _fontFallbacks,
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: onSurface,
        height: 1.5,
      ),
      bodySmall: TextStyle(
        fontFamilyFallback: _fontFallbacks,
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: onSurfaceVariant,
        height: 1.4,
      ),
      labelLarge: TextStyle(
        fontFamilyFallback: _fontFallbacks,
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: onSurface,
        letterSpacing: 0.3,
      ),
      labelMedium: TextStyle(
        fontFamilyFallback: _fontFallbacks,
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        color: onSurfaceVariant,
        letterSpacing: 0.2,
      ),
      labelSmall: TextStyle(
        fontFamilyFallback: _fontFallbacks,
        fontSize: 10,
        fontWeight: FontWeight.w500,
        color: onSurfaceVariant,
        letterSpacing: 0.4,
      ),
    );
  }

  static ThemeData get darkTheme {
    final textTheme = _buildTextTheme(_darkOnSurface, _darkOnSurfaceVariant);
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: _darkPrimary,
        onPrimary: _darkOnPrimary,
        primaryContainer: _darkPrimaryContainer,
        secondary: _darkSecondary,
        onSecondary: AppTokens.surfaceBase,
        secondaryContainer: _darkSecondaryContainer,
        onSecondaryContainer: _darkOnSecondaryContainer,
        tertiary: _darkTertiary,
        onTertiary: _darkOnTertiary,
        surface: _darkSurface,
        onSurface: _darkOnSurface,
        onSurfaceVariant: _darkOnSurfaceVariant,
        surfaceContainerHighest: _darkSurfaceVariant,
        error: _darkError,
      ),
      scaffoldBackgroundColor: _darkBackground,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: _darkBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        iconTheme: const IconThemeData(color: _darkOnSurface, size: 22),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: _darkBackground,
        elevation: 0,
        indicatorColor: AppTokens.accent.withValues(alpha: 0.35),
        indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.white);
          }
          return const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: AppTokens.textSecondary);
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: Colors.white, size: 22);
          }
          return const IconThemeData(color: AppTokens.textSecondary, size: 22);
        }),
      ),
      cardTheme: CardThemeData(
        color: _darkSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF333333), width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: _darkSurfaceVariant,
        labelStyle: textTheme.labelMedium!.copyWith(color: _darkOnSurface),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        side: const BorderSide(color: Color(0xFF3A3A3A), width: 0.8),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _darkSurfaceVariant,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppTokens.borderStrong, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppTokens.borderStrong, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _darkPrimaryContainer, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: textTheme.bodyMedium!.copyWith(color: const Color(0xFF8E8D85)),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return AppTokens.accent;
            return Colors.transparent;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return Colors.white;
            return AppTokens.textPrimary;
          }),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xFF222222),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFF383838)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _darkPrimaryContainer,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: _darkPrimaryContainer,
          foregroundColor: _darkOnTertiary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: _darkOnSurface,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFF2E2E2E),
        thickness: 1,
        space: 1,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: _darkPrimaryContainer,
        linearTrackColor: _darkSurfaceVariant,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: _darkSurfaceVariant,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static ThemeData get lightTheme {
    final textTheme = _buildTextTheme(_lightOnSurface, _lightOnSurfaceVariant);
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: const ColorScheme.light(
        primary: _lightPrimary,
        onPrimary: _lightOnPrimary,
        primaryContainer: _lightPrimaryContainer,
        secondary: _lightSecondary,
        onSecondary: Color(0xFFFFFFFF),
        secondaryContainer: _lightSecondaryContainer,
        onSecondaryContainer: _lightOnSecondaryContainer,
        tertiary: _lightTertiary,
        onTertiary: _lightOnTertiary,
        surface: _lightSurface,
        onSurface: _lightOnSurface,
        onSurfaceVariant: _lightOnSurfaceVariant,
        surfaceContainerHighest: _lightSurfaceVariant,
        error: _lightError,
      ),
      scaffoldBackgroundColor: _lightBackground,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: _lightBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        iconTheme: const IconThemeData(color: _lightOnSurface, size: 22),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: _lightBackground,
        elevation: 0,
        indicatorColor: AppTokens.accent.withValues(alpha: 0.25),
        indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      cardTheme: CardThemeData(
        color: _lightSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE2E4E8), width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: _lightSurfaceVariant,
        labelStyle: textTheme.labelMedium!.copyWith(color: _lightOnSurface),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _lightSurfaceVariant,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: textTheme.bodyMedium!.copyWith(color: _lightOnSurfaceVariant),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _lightPrimary,
          foregroundColor: _lightOnPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFFE4E7EC),
        thickness: 1,
        space: 1,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: _lightPrimary,
        linearTrackColor: _lightSurfaceVariant,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: _lightSurface,
        contentTextStyle: textTheme.bodyMedium,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static ThemeData get amoledTheme {
    final textTheme = _buildTextTheme(_darkOnSurface, _darkOnSurfaceVariant);
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: _darkPrimary,
        onPrimary: _darkOnPrimary,
        primaryContainer: _darkPrimaryContainer,
        secondary: _darkSecondary,
        onSecondary: Color(0xFF111111),
        secondaryContainer: AppTokens.surfaceBase,
        onSecondaryContainer: _darkOnSecondaryContainer,
        tertiary: _darkTertiary,
        onTertiary: _darkOnTertiary,
        surface: Color(0xFF0A0A0A),
        onSurface: _darkOnSurface,
        onSurfaceVariant: _darkOnSurfaceVariant,
        surfaceContainerHighest: Color(0xFF141414),
        error: _darkError,
      ),
      scaffoldBackgroundColor: const Color(0xFF000000),
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: const Color(0xFF000000),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        iconTheme: const IconThemeData(color: _darkOnSurface, size: 22),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFF000000),
        elevation: 0,
        indicatorColor: AppTokens.accent.withValues(alpha: 0.35),
        indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFF0A0A0A),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF222222), width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFF141414),
        labelStyle: textTheme.labelMedium!.copyWith(color: _darkOnSurface),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        side: const BorderSide(color: Color(0xFF262626), width: 0.8),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF0F0F0F),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF2A2A2A), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _darkPrimaryContainer, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: textTheme.bodyMedium!.copyWith(color: const Color(0xFF8E8D85)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _darkPrimaryContainer,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppTokens.surfaceBase,
        thickness: 1,
        space: 1,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: _darkPrimaryContainer,
        linearTrackColor: Color(0xFF1A1A1A),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xFF141414),
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

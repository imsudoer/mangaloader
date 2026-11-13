import 'package:flutter/widgets.dart';

/// Single source of truth for the surface palette, accent, radii, spacing and
/// motion. Values mirror the constants that were previously inlined across the UI,
/// so moving to tokens changes nothing visually while making a light/AMOLED variant
/// a one-file change instead of a repo-wide search.
class AppTokens {
  const AppTokens._();

  // Palette
  static const Color accent = Color(0xFF8A897C);
  static const Color surfaceBase = Color(0xFF1E1E1E);
  static const Color surfaceDeep = Color(0xFF181818);
  static const Color surfaceCard = Color(0xFF242424);
  static const Color surfaceRaised = Color(0xFF2C2C2C);
  static const Color border = Color(0xFF353535);
  static const Color borderStrong = Color(0xFF3E3E3E);
  static const Color textPrimary = Color(0xFFD2D7DF);
  static const Color textSecondary = Color(0xFFBDBBB0);
  static const Color warning = Color(0xFFE65100);

  // Radii
  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16;
  static const double radiusXl = 20;

  // Spacing
  static const double spaceXs = 4;
  static const double spaceSm = 8;
  static const double spaceMd = 12;
  static const double spaceLg = 16;
  static const double spaceXl = 24;

  // Motion
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 220);
  static const Duration slow = Duration(milliseconds: 320);
}
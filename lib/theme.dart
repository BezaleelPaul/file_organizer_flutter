import 'package:flutter/material.dart';

const seedColor = Color(0xFF6366F1);

abstract class StudioColors {
  static const obsidian = Color(0xFF0B0D13);
  static const darkSurface = Color(0xFF131622);
  static const darkCard = Color(0xFF181C2B);
  static const darkBorder = Color(0xFF262D42);
  
  static const electricIndigo = Color(0xFF6366F1);
  static const emeraldZen = Color(0xFF10B981);
  static const cyberAmber = Color(0xFFF59E0B);
  static const crimsonBurn = Color(0xFFF43F5E);
  static const radiantViolet = Color(0xFF8B5CF6);
  static const cyanBeam = Color(0xFF06B6D4);
}

ThemeData buildTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: seedColor,
    brightness: brightness,
    surface: isDark ? StudioColors.darkCard : Colors.white,
    surfaceContainerLow: isDark ? StudioColors.darkSurface : const Color(0xFFF1F3F9),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor:
        isDark ? StudioColors.obsidian : const Color(0xFFF6F8FC),
    appBarTheme: AppBarTheme(
      backgroundColor: isDark ? StudioColors.obsidian : const Color(0xFFF6F8FC),
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: isDark ? StudioColors.darkCard : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark ? StudioColors.darkBorder : const Color(0xFFE2E8F0),
          width: 1,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: isDark ? StudioColors.darkBorder : const Color(0xFFCBD5E1),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: isDark ? StudioColors.darkBorder : const Color(0xFFE2E8F0),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: seedColor, width: 1.5),
      ),
      filled: true,
      fillColor: isDark ? StudioColors.darkSurface : Colors.white,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Centralized design system for the LACRA Farm Mapping Tools app.
///
/// Every screen should pull colors, gradients, spacing, radii and shadows
/// from here instead of hardcoding values, so the whole app reads as one
/// consistent, branded product rather than a collection of default
/// Material widgets.
class AppTheme {
  // ---------------------------------------------------------------------
  // Brand color palette
  // ---------------------------------------------------------------------
  static const Color primaryGreen = Color(0xFF2E7D32);
  static const Color darkGreen = Color(0xFF1B5E20);
  static const Color mediumGreen = Color(0xFF43A047);
  static const Color lightGreen = Color(0xFF81C784);
  static const Color paleGreen = Color(0xFFE8F5E9);

  static const Color white = Color(0xFFFFFFFF);
  static const Color black = Color(0xFF000000);

  // Neutral / surface palette (matches the admin panel's slate tones)
  static const Color textPrimary = Color(0xFF1E293B); // slate-800
  static const Color textSecondary = Color(0xFF64748B); // slate-500
  static const Color textMuted = Color(0xFF94A3B8); // slate-400
  static const Color surface = Color(0xFFFFFFFF);
  static const Color background = Color(0xFFF4F7F5); // soft green-tinted grey
  static const Color border = Color(0xFFE2E8F0); // slate-200
  static const Color divider = Color(0xFFEEF2F0);

  // Legacy aliases kept so existing screens that reference these still work.
  static const Color grey = textSecondary;
  static const Color lightGrey = Color(0xFFF5F5F5);

  // Status colors (aligned with admin panel badge palette)
  static const Color success = Color(0xFF16A34A);
  static const Color successBg = Color(0xFFDCFCE7);
  static const Color warning = Color(0xFFD97706);
  static const Color warningBg = Color(0xFFFEF3C7);
  static const Color danger = Color(0xFFDC2626);
  static const Color dangerBg = Color(0xFFFEE2E2);
  static const Color info = Color(0xFF2563EB);
  static const Color infoBg = Color(0xFFDBEAFE);

  // ---------------------------------------------------------------------
  // Gradients
  // ---------------------------------------------------------------------
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [darkGreen, primaryGreen, mediumGreen],
  );

  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [darkGreen, primaryGreen],
  );

  // ---------------------------------------------------------------------
  // Spacing scale
  // ---------------------------------------------------------------------
  static const double spaceXs = 4;
  static const double spaceSm = 8;
  static const double spaceMd = 16;
  static const double spaceLg = 24;
  static const double spaceXl = 32;
  static const double spaceXxl = 48;

  // ---------------------------------------------------------------------
  // Radii
  // ---------------------------------------------------------------------
  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16;
  static const double radiusXl = 24;
  static const double radiusPill = 999;

  // ---------------------------------------------------------------------
  // Shadows
  // ---------------------------------------------------------------------
  static List<BoxShadow> get cardShadow => [
    BoxShadow(
      color: black.withValues(alpha: 0.06),
      blurRadius: 16,
      offset: const Offset(0, 4),
    ),
  ];

  static List<BoxShadow> get softShadow => [
    BoxShadow(
      color: black.withValues(alpha: 0.04),
      blurRadius: 8,
      offset: const Offset(0, 2),
    ),
  ];

  static List<BoxShadow> get elevatedShadow => [
    BoxShadow(
      color: primaryGreen.withValues(alpha: 0.18),
      blurRadius: 24,
      offset: const Offset(0, 10),
    ),
  ];

  // ---------------------------------------------------------------------
  // Status helpers - keeps color logic for badges in one place so every
  // screen (farmers list, farmer detail, drafts, etc.) renders identical
  // status pills.
  // ---------------------------------------------------------------------
  static Color statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'verified':
      case 'approved':
      case 'active':
      case 'synced':
      case 'valid':
        return success;
      case 'conflict':
      case 'rejected':
      case 'failed':
      case 'invalid':
        return danger;
      case 'pending':
      case 'unverified':
      case 'draft':
      case 'needs review':
        return warning;
      default:
        return info;
    }
  }

  static Color statusBgColor(String status) {
    switch (status.toLowerCase()) {
      case 'verified':
      case 'approved':
      case 'active':
      case 'synced':
      case 'valid':
        return successBg;
      case 'conflict':
      case 'rejected':
      case 'failed':
      case 'invalid':
        return dangerBg;
      case 'pending':
      case 'unverified':
      case 'draft':
      case 'needs review':
        return warningBg;
      default:
        return infoBg;
    }
  }

  // ---------------------------------------------------------------------
  // ThemeData
  // ---------------------------------------------------------------------
  static ThemeData get lightTheme {
    final baseTextTheme = GoogleFonts.poppinsTextTheme().apply(
      bodyColor: textPrimary,
      displayColor: textPrimary,
    );

    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: background,
      colorScheme: ColorScheme.light(
        primary: primaryGreen,
        secondary: mediumGreen,
        surface: surface,
        error: danger,
        onPrimary: white,
        onSecondary: white,
        onSurface: textPrimary,
        onError: white,
      ),
      textTheme: baseTextTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: primaryGreen,
        foregroundColor: white,
        elevation: 0,
        centerTitle: true,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: GoogleFonts.poppins(
          fontSize: 19,
          fontWeight: FontWeight.w600,
          color: white,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryGreen,
          foregroundColor: white,
          disabledBackgroundColor: primaryGreen.withValues(alpha: 0.5),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          minimumSize: const Size(0, 48),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          textStyle: GoogleFonts.poppins(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryGreen,
          side: const BorderSide(color: primaryGreen, width: 1.4),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          textStyle: GoogleFonts.poppins(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryGreen,
          textStyle: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: background,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: primaryGreen, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: danger, width: 1.8),
        ),
        labelStyle: GoogleFonts.poppins(fontSize: 13, color: textSecondary),
        hintStyle: GoogleFonts.poppins(color: textMuted, fontSize: 13),
        prefixIconColor: textSecondary,
        suffixIconColor: textSecondary,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: surface,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          side: BorderSide(color: border),
        ),
      ),
      dividerTheme: DividerThemeData(color: divider, thickness: 1, space: 1),
      tabBarTheme: TabBarThemeData(
        labelColor: white,
        unselectedLabelColor: white.withValues(alpha: 0.7),
        indicatorColor: white,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: GoogleFonts.poppins(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: GoogleFonts.poppins(
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: textPrimary,
        contentTextStyle: GoogleFonts.poppins(color: white, fontSize: 13),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
        ),
        titleTextStyle: GoogleFonts.poppins(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),
        contentTextStyle: GoogleFonts.poppins(
          fontSize: 14,
          color: textSecondary,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: paleGreen,
        labelStyle: GoogleFonts.poppins(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: darkGreen,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusPill),
        ),
        side: BorderSide.none,
      ),
    );
  }
}

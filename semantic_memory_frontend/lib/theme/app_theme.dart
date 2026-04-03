import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Semantic Memory color palette — extracted from the design system image.
class AppColors {
  AppColors._();

  // ── Core palette ──────────────────────────────────────────────
  static const Color primary      = Color(0xFF00E5FF); // bright cyan
  static const Color secondary    = Color(0xFF1A237E); // deep navy
  static const Color tertiary     = Color(0xFF78909C); // blue-grey
  static const Color neutral      = Color(0xFF0A0E14); // near-black bg

  // ── Surfaces ──────────────────────────────────────────────────
  static const Color surface      = Color(0xFF141B2D); // card / panel
  static const Color surfaceLight = Color(0xFF1C2538); // elevated surface
  static const Color surfaceBright= Color(0xFF243047); // hover / active

  // ── Semantic accents ──────────────────────────────────────────
  static const Color pdfRed       = Color(0xFFEF5350);
  static const Color pptOrange    = Color(0xFFFFA726);
  static const Color docBlue      = Color(0xFF42A5F5);
  static const Color txtGreen     = Color(0xFF66BB6A);
  static const Color imgPurple    = Color(0xFFAB47BC);

  // ── Text ──────────────────────────────────────────────────────
  static const Color textPrimary  = Color(0xFFECEFF1); // almost white
  static const Color textSecondary= Color(0xFF90A4AE); // muted
  static const Color textHint     = Color(0xFF546E7A); // very muted
}

/// Build the full dark-mode [ThemeData] used across the app.
ThemeData buildAppTheme() {
  final base = ThemeData.dark(useMaterial3: true);

  final textTheme = GoogleFonts.interTextTheme(base.textTheme).apply(
    bodyColor: AppColors.textPrimary,
    displayColor: AppColors.textPrimary,
  );

  final colorScheme = ColorScheme.dark(
    primary: AppColors.primary,
    onPrimary: AppColors.neutral,
    secondary: AppColors.secondary,
    onSecondary: AppColors.textPrimary,
    tertiary: AppColors.tertiary,
    surface: AppColors.surface,
    onSurface: AppColors.textPrimary,
    surfaceContainerHighest: AppColors.surfaceLight,
    error: AppColors.pdfRed,
  );

  return base.copyWith(
    colorScheme: colorScheme,
    scaffoldBackgroundColor: AppColors.neutral,
    textTheme: textTheme,

    // ── AppBar ────────────────────────────────────────────────
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: GoogleFonts.inter(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: AppColors.primary,
        letterSpacing: -0.5,
      ),
      iconTheme: const IconThemeData(color: AppColors.primary),
    ),

    // ── Cards ─────────────────────────────────────────────────
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.tertiary.withValues(alpha: 0.15)),
      ),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    ),

    // ── Input fields ──────────────────────────────────────────
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceLight,
      hintStyle: GoogleFonts.inter(color: AppColors.textHint, fontSize: 15),
      prefixIconColor: AppColors.tertiary,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: BorderSide(color: AppColors.tertiary.withValues(alpha: 0.2)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
    ),

    // ── Segmented / toggle buttons ────────────────────────────
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.primary.withValues(alpha: 0.15);
          }
          return AppColors.surfaceLight;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.primary;
          }
          return AppColors.textSecondary;
        }),
        side: WidgetStateProperty.all(
          BorderSide(color: AppColors.tertiary.withValues(alpha: 0.2)),
        ),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        ),
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
      ),
    ),

    // ── Snackbar ──────────────────────────────────────────────
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.surfaceLight,
      contentTextStyle: GoogleFonts.inter(color: AppColors.textPrimary),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      behavior: SnackBarBehavior.floating,
    ),

    // ── Divider ───────────────────────────────────────────────
    dividerTheme: DividerThemeData(
      color: AppColors.tertiary.withValues(alpha: 0.15),
      thickness: 1,
    ),

    // ── Misc ──────────────────────────────────────────────────
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.primary,
    ),
    splashColor: AppColors.primary.withValues(alpha: 0.08),
    highlightColor: AppColors.primary.withValues(alpha: 0.05),
  );
}

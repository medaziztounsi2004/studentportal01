import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ═══════════════════════════════════════════════════════════════════
// ░░░  AURORA GLASS — Premium Admin Design System  ░░░
// ═══════════════════════════════════════════════════════════════════

/// Aurora Glass color palette — Deep midnight navy + Electric sapphire
class AppColors {
  // ── Primary — Electric Sapphire ──
  static const Color primary = Color(0xFF2563EB);       // Sapphire 600
  static const Color primaryDark = Color(0xFF1D4ED8);   // Sapphire 700
  static const Color primaryLight = Color(0xFF60A5FA);  // Sapphire 400
  static const Color primarySoft = Color(0xFFEFF6FF);   // Sapphire 50

  // ── Secondary — Vivid Violet ──
  static const Color secondary = Color(0xFF7C3AED);     // Violet 600
  static const Color secondaryLight = Color(0xFFA78BFA); // Violet 400

  // ── Accent — Warm Coral ──
  static const Color accent = Color(0xFFF97316);        // Orange 500
  static const Color accentSoft = Color(0xFFFFF7ED);    // Orange 50

  // ── Sidebar — Deep Midnight Glass ──
  static const Color sidebarBg = Color(0xFF070B14);     // Near black navy
  static const Color sidebarHover = Color(0xFF111827);  // Gray 900
  static const Color sidebarText = Color(0xFF9CA3AF);   // Gray 400
  static const Color sidebarTextActive = Color(0xFFFFFFFF);
  static const Color sidebarActive = Color(0xFF3B82F6); // Blue 500
  static const Color sidebarDivider = Color(0xFF1F2937); // Gray 800

  // ── Background — Cool Pearl ──
  static const Color background = Color(0xFFF0F4F8);    // Cool blue-gray
  static const Color backgroundAlt = Color(0xFFE8EDF2);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceElevated = Color(0xFFFFFFFF);

  // ── Text — Deep Navy ──
  static const Color textPrimary = Color(0xFF111827);   // Gray 900
  static const Color textSecondary = Color(0xFF6B7280); // Gray 500
  static const Color textTertiary = Color(0xFF9CA3AF);  // Gray 400
  static const Color textOnPrimary = Color(0xFFFFFFFF);

  // ── Status — Vivid tones ──
  static const Color success = Color(0xFF059669);       // Emerald 600
  static const Color successSoft = Color(0xFFECFDF5);
  static const Color warning = Color(0xFFD97706);       // Amber 600
  static const Color warningSoft = Color(0xFFFFFBEB);
  static const Color error = Color(0xFFDC2626);         // Red 600
  static const Color errorSoft = Color(0xFFFEF2F2);
  static const Color info = Color(0xFF2563EB);          // Blue 600
  static const Color infoSoft = Color(0xFFEFF6FF);

  // ── Borders — Soft frost ──
  static const Color border = Color(0xFFE5E7EB);       // Gray 200
  static const Color borderLight = Color(0xFFF3F4F6);  // Gray 100
  static const Color divider = Color(0xFFE5E7EB);

  // ── Shadows ──
  static const Color shadow = Color(0x08060E1F);
  static const Color shadowMedium = Color(0x12060E1F);

  // ── Neutral Gray Scale ──
  static const Color slate50 = Color(0xFFF9FAFB);
  static const Color slate100 = Color(0xFFF3F4F6);
  static const Color slate200 = Color(0xFFE5E7EB);
  static const Color slate300 = Color(0xFFD1D5DB);
  static const Color slate400 = Color(0xFF9CA3AF);
  static const Color slate500 = Color(0xFF6B7280);
  static const Color slate600 = Color(0xFF4B5563);
  static const Color slate700 = Color(0xFF374151);
  static const Color slate800 = Color(0xFF1F2937);
  static const Color slate900 = Color(0xFF111827);

  // ── Extended palette ──
  static const Color violet500 = Color(0xFF8B5CF6);
  static const Color violet600 = Color(0xFF7C3AED);

  // ── Chart — Vibrant 6-color rainbow ──
  static const Color chart1 = Color(0xFF2563EB); // Sapphire
  static const Color chart2 = Color(0xFF059669); // Emerald
  static const Color chart3 = Color(0xFFF97316); // Orange
  static const Color chart4 = Color(0xFFEC4899); // Pink
  static const Color chart5 = Color(0xFF8B5CF6); // Violet
  static const Color chart6 = Color(0xFF06B6D4); // Cyan

  // ── Gradient presets ──
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF2563EB), Color(0xFF7C3AED)],
  );

  static const LinearGradient successGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF059669), Color(0xFF10B981)],
  );

  static const LinearGradient warningGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFD97706), Color(0xFFF59E0B)],
  );

  static const LinearGradient errorGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFDC2626), Color(0xFFF43F5E)],
  );

  static const LinearGradient sidebarGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF070B14), Color(0xFF0F172A)],
  );

  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF97316), Color(0xFFFB923C)],
  );

  static const LinearGradient glassGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0x18FFFFFF), Color(0x08FFFFFF)],
  );
}

/// Spacing
class AppSpacing {
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
  static const double xxl = 48.0;
  static const double xxxl = 64.0;
}

/// Border radii — larger for the glass-card aesthetic
class AppRadius {
  static const double xs = 6.0;
  static const double sm = 10.0;
  static const double md = 14.0;
  static const double lg = 18.0;
  static const double xl = 22.0;
  static const double xxl = 28.0;
  static const double full = 9999.0;
}

/// Layered shadow system
class AppShadows {
  static List<BoxShadow> get sm => [
    BoxShadow(color: AppColors.shadow, blurRadius: 6, offset: const Offset(0, 2)),
  ];

  static List<BoxShadow> get md => [
    BoxShadow(color: AppColors.shadow, blurRadius: 10, offset: const Offset(0, 4)),
    BoxShadow(color: AppColors.shadowMedium, blurRadius: 4, offset: const Offset(0, 1)),
  ];

  static List<BoxShadow> get lg => [
    BoxShadow(color: AppColors.shadowMedium, blurRadius: 20, offset: const Offset(0, 6)),
  ];

  static List<BoxShadow> get xl => [
    BoxShadow(color: AppColors.shadowMedium, blurRadius: 32, offset: const Offset(0, 10)),
  ];

  static List<BoxShadow> get card => [
    BoxShadow(
      color: const Color(0xFF2563EB).withOpacity(0.04),
      blurRadius: 16,
      offset: const Offset(0, 4),
    ),
    BoxShadow(
      color: Colors.black.withOpacity(0.03),
      blurRadius: 6,
      offset: const Offset(0, 2),
    ),
  ];

  static List<BoxShadow> get cardHover => [
    BoxShadow(
      color: const Color(0xFF2563EB).withOpacity(0.10),
      blurRadius: 28,
      offset: const Offset(0, 8),
    ),
    BoxShadow(
      color: Colors.black.withOpacity(0.05),
      blurRadius: 10,
      offset: const Offset(0, 4),
    ),
  ];

  static List<BoxShadow> get glow => [
    BoxShadow(
      color: AppColors.primary.withOpacity(0.35),
      blurRadius: 24,
      offset: const Offset(0, 6),
    ),
  ];

  /// Colored glow for status cards
  static List<BoxShadow> coloredGlow(Color color) => [
    BoxShadow(
      color: color.withOpacity(0.25),
      blurRadius: 20,
      offset: const Offset(0, 6),
    ),
  ];
}

/// Glass-morphism helper decoration
class GlassDecoration {
  static BoxDecoration frosted({
    double borderRadius = 18,
    double opacity = 0.65,
    Color? borderColor,
  }) {
    return BoxDecoration(
      color: Colors.white.withOpacity(opacity),
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(
        color: borderColor ?? Colors.white.withOpacity(0.25),
        width: 1.0,
      ),
      boxShadow: AppShadows.card,
    );
  }

  static BoxDecoration darkFrosted({
    double borderRadius = 18,
    double opacity = 0.12,
  }) {
    return BoxDecoration(
      color: Colors.white.withOpacity(opacity),
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(
        color: Colors.white.withOpacity(0.08),
        width: 1.0,
      ),
    );
  }
}

class AppTheme {
  static ThemeData get lightTheme {
    final baseTextTheme = GoogleFonts.plusJakartaSansTextTheme();

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      primaryColor: AppColors.primary,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        secondary: AppColors.secondary,
        surface: AppColors.surface,
        error: AppColors.error,
        onPrimary: AppColors.textOnPrimary,
        onSecondary: AppColors.textOnPrimary,
        onSurface: AppColors.textPrimary,
        onError: AppColors.textOnPrimary,
      ),
      textTheme: baseTextTheme.copyWith(
        displayLarge: baseTextTheme.displayLarge?.copyWith(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w800,
          letterSpacing: -1.5,
        ),
        displayMedium: baseTextTheme.displayMedium?.copyWith(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w700,
          letterSpacing: -1.0,
        ),
        displaySmall: baseTextTheme.displaySmall?.copyWith(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
        headlineLarge: baseTextTheme.headlineLarge?.copyWith(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.8,
        ),
        headlineMedium: baseTextTheme.headlineMedium?.copyWith(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
        headlineSmall: baseTextTheme.headlineSmall?.copyWith(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        titleLarge: baseTextTheme.titleLarge?.copyWith(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        titleMedium: baseTextTheme.titleMedium?.copyWith(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
        titleSmall: baseTextTheme.titleSmall?.copyWith(
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: baseTextTheme.bodyLarge?.copyWith(
          color: AppColors.textPrimary,
          height: 1.6,
        ),
        bodyMedium: baseTextTheme.bodyMedium?.copyWith(
          color: AppColors.textSecondary,
          height: 1.5,
        ),
        bodySmall: baseTextTheme.bodySmall?.copyWith(
          color: AppColors.textTertiary,
          height: 1.5,
        ),
        labelLarge: baseTextTheme.labelLarge?.copyWith(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
        ),
        labelMedium: baseTextTheme.labelMedium?.copyWith(
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
        labelSmall: baseTextTheme.labelSmall?.copyWith(
          color: AppColors.textTertiary,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.plusJakartaSans(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: AppColors.border.withOpacity(0.6), width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.slate50,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: AppColors.border.withOpacity(0.5)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: AppColors.border.withOpacity(0.5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.error, width: 2),
        ),
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        hintStyle: const TextStyle(color: AppColors.textTertiary),
        floatingLabelStyle: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.textOnPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          textStyle: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          side: BorderSide(color: AppColors.primary.withOpacity(0.4)),
          textStyle: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          textStyle: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: AppColors.textSecondary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textOnPrimary,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.primarySoft,
        labelStyle: GoogleFonts.plusJakartaSans(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.primary,
        ),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      ),
      dividerTheme: DividerThemeData(
        color: AppColors.divider.withOpacity(0.6),
        thickness: 1,
        space: 1,
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStateProperty.all(AppColors.slate50),
        dataRowColor: WidgetStateProperty.all(AppColors.surface),
        headingTextStyle: GoogleFonts.plusJakartaSans(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
          letterSpacing: 0.3,
        ),
        dataTextStyle: GoogleFonts.plusJakartaSans(
          fontSize: 14,
          color: AppColors.textPrimary,
        ),
        dividerThickness: 1,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xxl),
        ),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFF1F5F9)),
        ),
        headerBackgroundColor: Colors.white,
        headerForegroundColor: const Color(0xFF1E293B),
        headerHeadlineStyle: GoogleFonts.plusJakartaSans(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF1E293B),
        ),
        headerHelpStyle: GoogleFonts.plusJakartaSans(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: const Color(0xFF64748B),
        ),
        weekdayStyle: GoogleFonts.plusJakartaSans(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: const Color(0xFF64748B),
        ),
        dayStyle: GoogleFonts.plusJakartaSans(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: const Color(0xFF1E293B),
        ),
        dayForegroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          if (states.contains(WidgetState.disabled)) return const Color(0xFFCBD5E1);
          return const Color(0xFF1E293B);
        }),
        dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return const Color(0xFF6D4CF6);
          return Colors.transparent;
        }),
        todayForegroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          return const Color(0xFF6D4CF6);
        }),
        todayBorder: const BorderSide(color: Color(0xFF6D4CF6), width: 1.5),
        yearStyle: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600),
        cancelButtonStyle: TextButton.styleFrom(
          foregroundColor: const Color(0xFF6B7280),
          textStyle: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        confirmButtonStyle: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF6D4CF6),
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFF1F5F9)),
        ),
        hourMinuteColor: const Color(0xFFF5F3FF),
        hourMinuteTextColor: const Color(0xFF6D4CF6),
        hourMinuteTextStyle: GoogleFonts.plusJakartaSans(
          fontSize: 32,
          fontWeight: FontWeight.w800,
        ),
        hourMinuteShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        dayPeriodColor: const Color(0xFFF5F3FF),
        dayPeriodTextColor: const Color(0xFF6D4CF6),
        dayPeriodShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        dialBackgroundColor: const Color(0xFFF8FAFC),
        dialHandColor: const Color(0xFF6D4CF6),
        dialTextColor: const Color(0xFF1E293B),
        dialTextStyle: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600),
        entryModeIconColor: const Color(0xFF6D4CF6),
        cancelButtonStyle: TextButton.styleFrom(
          foregroundColor: const Color(0xFF6B7280),
          textStyle: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        confirmButtonStyle: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF6D4CF6),
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.slate900,
        contentTextStyle: GoogleFonts.plusJakartaSans(color: AppColors.surface),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(100),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.slate900,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        textStyle: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppColors.surface),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbVisibility: const WidgetStatePropertyAll(false),
        trackVisibility: const WidgetStatePropertyAll(false),
        thickness: const WidgetStatePropertyAll(6),
        radius: const Radius.circular(10),
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.hovered)) {
            return AppColors.slate400;
          }
          return AppColors.slate300.withOpacity(0.5);
        }),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.primary;
          return Colors.transparent;
        }),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        side: BorderSide(color: AppColors.border, width: 1.5),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.surface;
          return AppColors.textTertiary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.primary;
          return AppColors.border;
        }),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.textSecondary,
        labelStyle: GoogleFonts.plusJakartaSans(
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: GoogleFonts.plusJakartaSans(
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        indicator: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AppColors.primary, width: 2.5),
          ),
        ),
        dividerHeight: 0,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
        linearTrackColor: AppColors.primarySoft,
      ),
    );
  }
}

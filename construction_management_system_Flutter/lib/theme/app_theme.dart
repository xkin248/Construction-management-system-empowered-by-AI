import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  /// Global dark-mode switch. Set by the app when the system brightness changes.
  /// A ValueNotifier so root pages can listen and rebuild with the new palette
  /// without resetting the Navigator stack.
  static final ValueNotifier<bool> darkMode = ValueNotifier<bool>(false);
  static bool get isDark => darkMode.value;
  static set isDark(bool v) => darkMode.value = v;

  // ── Core palette (light / dark variants) ──
  static Color get sidebarBg => isDark ? const Color(0xFF0B0F16) : const Color(0xFF10141C);
  static Color get sidebarHover => isDark ? const Color(0xFF1A212E) : const Color(0xFF1F2634);
  static Color get accent => const Color(0xFFE8490F);
  static Color get accentLight => const Color(0xFFFFF3E8);
  static Color get accentDark => const Color(0xFFCA3D0A);
  static Color get bgMain => isDark ? const Color(0xFF0F131A) : const Color(0xFFF4F6FB);
  static Color get bgCard => isDark ? const Color(0xFF171C26) : const Color(0xFFFFFFFF);
  static Color get textPrimary => isDark ? const Color(0xFFF2F4F8) : const Color(0xFF1A1F2E);
  static Color get textSecondary => isDark ? const Color(0xFFB7BFD0) : const Color(0xFF4B5563);
  static Color get textMuted => isDark ? const Color(0xFF8A93A6) : const Color(0xFF6B7280);
  static Color get textSidebar => const Color(0xFFC8CDD8);
  static Color get textSidebarMuted => isDark ? const Color(0xFF9AA3B5) : const Color(0xFF757E90);
  static Color get border => isDark ? const Color(0xFF242C3D) : const Color(0xFFE8ECF4);
  static Color get borderLight => isDark ? const Color(0xFF1C2230) : const Color(0xFFF0F4FB);
  static Color get green => const Color(0xFF22C55E);
  static Color get greenLight => const Color(0xFFDCFCE7);
  static Color get yellow => const Color(0xFFEAB308);
  static Color get yellowLight => const Color(0xFFFEF9C3);
  static Color get red => const Color(0xFFEF4444);
  static Color get redLight => const Color(0xFFFEE2E2);
  static Color get blue => const Color(0xFF3B82F6);
  static Color get blueLight => const Color(0xFFDBEAFE);
  static Color get purple => const Color(0xFF8B5CF6);
  static Color get purpleLight => const Color(0xFFF3E8FF);

  // Sidebar width for adaptive layout
  static const double sidebarWidth = 240.0;

  // ── Backward-compatibility aliases ──
  static Color get primary => const Color(0xFFE8490F);
  static Color get primaryLight => const Color(0xFFFB923C);
  static Color get primaryDark => const Color(0xFFCA3D0A);
  static Color get accentOrange => const Color(0xFFE8490F);
  static Color get accentOrangeLight => const Color(0xFFFB923C);
  static Color get success => const Color(0xFF22C55E);
  static Color get successLight => const Color(0xFFDCFCE7);
  static Color get warning => const Color(0xFFEAB308);
  static Color get danger => const Color(0xFFEF4444);
  static Color get info => const Color(0xFF3B82F6);
  static Color get bgColor => bgMain;
  static Color get cardColor => bgCard;
  static Color get sidebarColor => sidebarBg;
  static Color get borderColor => border;

  static LinearGradient get primaryGradient => const LinearGradient(
        colors: [Color(0xFFE8490F), Color(0xFFFB923C)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
  static LinearGradient get accentGradient => const LinearGradient(
        colors: [Color(0xFFE8490F), Color(0xFFFB923C)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
  static LinearGradient get successGradient => const LinearGradient(
        colors: [Color(0xFF22C55E), Color(0xFF86EFAC)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
}

Color get primary => AppColors.accent;
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
final navigatorKey = GlobalKey<NavigatorState>();

void toast(String msg) {
  scaffoldMessengerKey.currentState
      ?.showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
}

String initials(String n) {
  final parts = n.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty || parts.first.isEmpty) return '?';
  if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
  return (parts[0][0] + parts[1][0]).toUpperCase();
}

final List<Color> avatarPalette = [
  AppColors.accent,
  AppColors.blue,
  AppColors.purple,
  AppColors.green,
  AppColors.yellow,
];
Color avatarColor(String seed) =>
    avatarPalette[seed.codeUnits.fold(0, (a, b) => a + b) % avatarPalette.length];

final Map<String, Color> _statusColor = {
  'checked_in': AppColors.green,
  'present': AppColors.green,
  'completed': AppColors.green,
  'active': AppColors.green,
  'resolved': AppColors.green,
  'on_track': AppColors.green,
  'checked_out': AppColors.blue,
  'in_progress': AppColors.blue,
  'left_early': AppColors.yellow,
  'late': AppColors.yellow,
  'pending': AppColors.yellow,
  'at_risk': AppColors.yellow,
  'absent': AppColors.red,
  'rejected': AppColors.red,
  'open': AppColors.red,
  'high': AppColors.red,
  'critical': AppColors.red,
  'delayed': AppColors.red,
  'medium': AppColors.yellow,
  'low': AppColors.blue,
};
final Map<String, Color> _statusBg = {
  'checked_in': AppColors.greenLight,
  'present': AppColors.greenLight,
  'completed': AppColors.greenLight,
  'active': AppColors.greenLight,
  'resolved': AppColors.greenLight,
  'on_track': AppColors.greenLight,
  'checked_out': AppColors.blueLight,
  'in_progress': AppColors.blueLight,
  'left_early': AppColors.yellowLight,
  'late': AppColors.yellowLight,
  'pending': AppColors.yellowLight,
  'at_risk': AppColors.yellowLight,
  'absent': AppColors.redLight,
  'rejected': AppColors.redLight,
  'open': AppColors.redLight,
  'high': AppColors.redLight,
  'critical': AppColors.redLight,
  'delayed': AppColors.redLight,
  'medium': AppColors.yellowLight,
  'low': AppColors.blueLight,
};
Color statusFg(String s) => _statusColor[s.toLowerCase()] ?? AppColors.textMuted;
Color statusBgOf(String s) => _statusBg[s.toLowerCase()] ?? AppColors.border;

Widget statusPill(String status, {String? label}) {
  final s = status.toLowerCase();
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: statusBgOf(s),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      (label ?? status).replaceAll('_', ' ').toUpperCase(),
      style: TextStyle(
        color: statusFg(s),
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.3,
      ),
    ),
  );
}

Widget sectionCard({
  required Widget child,
  EdgeInsetsGeometry? padding,
  EdgeInsetsGeometry? margin,
}) =>
    Container(
      margin: margin,
      padding: padding ?? const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );

Widget initialsAvatar(String name, {double radius = 18, String? seed}) =>
    CircleAvatar(
      radius: radius,
      backgroundColor: avatarColor(seed ?? name),
      child: Text(
        initials(name),
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: radius * 0.62,
        ),
      ),
    );

Widget statCard({
  required String label,
  required String value,
  String? sub,
  IconData? icon,
  Color? iconColor,
}) {
  return sectionCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (icon != null)
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: (iconColor ?? AppColors.accent).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 15, color: iconColor ?? AppColors.accent),
            ),
        ]),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        if (sub != null) ...[
          const SizedBox(height: 2),
          Text(sub, style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
        ],
      ],
    ),
  );
}

TextTheme _buildTextTheme(TextTheme base) {
  return GoogleFonts.outfitTextTheme(base).copyWith(
    displayLarge: GoogleFonts.outfit(fontSize: 32, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
    displayMedium: GoogleFonts.outfit(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
    headlineLarge: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
    headlineMedium: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
    headlineSmall: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
    titleLarge: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
    titleMedium: GoogleFonts.outfit(fontSize: 14.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
    bodyLarge: GoogleFonts.outfit(fontSize: 15, color: AppColors.textPrimary),
    bodyMedium: GoogleFonts.outfit(fontSize: 14, color: AppColors.textSecondary),
    bodySmall: GoogleFonts.outfit(fontSize: 13, color: AppColors.textMuted),
    labelLarge: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w700),
    labelSmall: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.4),
  );
}

ThemeData buildAppTheme() => ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.bgMain,
      colorScheme: ColorScheme.fromSeed(seedColor: AppColors.accent).copyWith(
        primary: AppColors.accent,
        secondary: AppColors.accentDark,
        surface: AppColors.bgCard,
      ),
      textTheme: _buildTextTheme(ThemeData.light().textTheme),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.bgCard,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: GoogleFonts.outfit(
          color: AppColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
        iconTheme: IconThemeData(color: AppColors.textPrimary),
      ),
      cardTheme: CardThemeData(
        color: AppColors.bgCard,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: AppColors.border),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: BorderSide(color: AppColors.border),
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.accent,
          textStyle: GoogleFonts.outfit(fontWeight: FontWeight.w700),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.bgMain,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.accent, width: 1.6),
        ),
        labelStyle: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 14),
        hintStyle: GoogleFonts.outfit(color: AppColors.textMuted, fontSize: 14),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.bgCard,
        selectedItemColor: AppColors.accent,
        unselectedItemColor: AppColors.textMuted,
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
        elevation: 10,
      ),
      dividerTheme: DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        side: BorderSide(color: AppColors.border),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.accent,
        unselectedLabelColor: AppColors.textSecondary,
        indicatorColor: AppColors.accent,
        labelStyle: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 14),
      ),
    );

ThemeData buildDarkTheme() => ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.bgMain,
      colorScheme: ColorScheme.dark(
        primary: AppColors.accent,
        secondary: AppColors.accentDark,
        surface: AppColors.bgCard,
      ),
      textTheme: _buildTextTheme(ThemeData.dark().textTheme),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.bgCard,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: GoogleFonts.outfit(
          color: AppColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
        iconTheme: IconThemeData(color: AppColors.textPrimary),
      ),
      cardTheme: CardThemeData(
        color: AppColors.bgCard,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: AppColors.border),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: BorderSide(color: AppColors.border),
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.accent,
          textStyle: GoogleFonts.outfit(fontWeight: FontWeight.w700),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.bgMain,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.accent, width: 1.6),
        ),
        labelStyle: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 14),
        hintStyle: GoogleFonts.outfit(color: AppColors.textMuted, fontSize: 14),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.bgCard,
        selectedItemColor: AppColors.accent,
        unselectedItemColor: AppColors.textMuted,
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
        elevation: 10,
      ),
      dividerTheme: DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        side: BorderSide(color: AppColors.border),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.accent,
        unselectedLabelColor: AppColors.textSecondary,
        indicatorColor: AppColors.accent,
        labelStyle: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 14),
      ),
    );

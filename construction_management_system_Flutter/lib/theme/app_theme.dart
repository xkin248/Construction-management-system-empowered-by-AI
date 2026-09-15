import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ---------------------------------------------------------------------------
// Radius tokens - one shared scale for every surface in the app.
// ---------------------------------------------------------------------------
class AppRadius {
  AppRadius._();

  /// One unified surface radius for every card, panel, control and sheet.
  static const double xs = 16;
  static const double sm = 16;
  static const double md = 16;
  static const double lg = 16;
  static const double xl = 16;
  static const double pill = 999;

  /// Hairline radius - reserved for 2-3px thin bars (progress tracks) where a
  /// 16px radius would exceed the element height.
  static const double hair = 2;

  static const BorderRadius rXs = BorderRadius.all(Radius.circular(xs));
  static const BorderRadius rSm = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius rMd = BorderRadius.all(Radius.circular(md));
  static const BorderRadius rLg = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius rXl = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius rPill = BorderRadius.all(Radius.circular(pill));
  static const BorderRadius rHair = BorderRadius.all(Radius.circular(hair));

  /// Top-only rounding used by chart bars.
  static const BorderRadius topXs = BorderRadius.vertical(top: Radius.circular(md));

  /// Control radius shared by buttons, inputs and snackbars.
  static const double control = 16;
  static const BorderRadius rBtn = BorderRadius.all(Radius.circular(control));
  static const BorderRadius bInput = BorderRadius.all(Radius.circular(control));

  /// Dialog and bottom-sheet rounding.
  static const double dialog = 16;
  static const double sheet = 16;
  static const BorderRadius rSheet = BorderRadius.all(Radius.circular(dialog));
  static const BorderRadius bSheet = BorderRadius.vertical(top: Radius.circular(sheet));
}

// ---------------------------------------------------------------------------
// Elevation tokens - three levels, resolved per brightness at call time.
// ---------------------------------------------------------------------------
class AppShadows {
  AppShadows._();

  /// Level 1 - soft ambient lift: cards, list rows, KPI tiles.
  static List<BoxShadow> get sm => AppColors.isDark
      ? const [BoxShadow(color: Color(0x3D000000), blurRadius: 8, offset: Offset(0, 2))]
      : const [BoxShadow(color: Color(0x0A0F172A), blurRadius: 8, offset: Offset(0, 2))];

  /// Level 2 - raised: floating nav bars, panels, sheets.
  static List<BoxShadow> get md => AppColors.isDark
      ? const [BoxShadow(color: Color(0x52000000), blurRadius: 20, offset: Offset(0, 8))]
      : const [BoxShadow(color: Color(0x140F172A), blurRadius: 20, offset: Offset(0, 8))];

  /// Level 3 - hero: dialogs, hero panels, sticky headers.
  static List<BoxShadow> get lg => AppColors.isDark
      ? const [BoxShadow(color: Color(0x66000000), blurRadius: 32, offset: Offset(0, 16))]
      : const [BoxShadow(color: Color(0x1A0F172A), blurRadius: 32, offset: Offset(0, 16))];

  /// Accent-tinted glow for brand blocks and primary calls to action.
  static List<BoxShadow> accent(
    Color color, {
    double alpha = 0.30,
    double blur = 18,
    double dy = 8,
  }) =>
      [BoxShadow(color: color.withValues(alpha: alpha), blurRadius: blur, offset: Offset(0, dy))];

  /// Fixed dark shadow for always-dark screens (login / splash).
  static const List<BoxShadow> darkMd = [
    BoxShadow(color: Color(0x80000000), blurRadius: 24, offset: Offset(0, 10)),
  ];
}

// ---------------------------------------------------------------------------
// Motion tokens - shared durations and easing for token-driven transitions.
// ---------------------------------------------------------------------------
class AppDuration {
  AppDuration._();

  static const Duration fast = Duration(milliseconds: 150);
  static const Duration base = Duration(milliseconds: 220);
  static const Duration slow = Duration(milliseconds: 320);

  static const Curve ease = Curves.easeOutCubic;
}

class AppColors {
  /// Global dark-mode switch. Set by the app when the system brightness changes.
  /// A ValueNotifier so root pages can listen and rebuild with the new palette
  /// without resetting the Navigator stack.
  static final ValueNotifier<bool> darkMode = ValueNotifier<bool>(false);
  static bool get isDark => darkMode.value;
  static set isDark(bool v) => darkMode.value = v;

  // ── Core palette ──
  // Swiss Modernism 2.0: industrial-gray structure + a single safety-orange
  // action colour. Every value below is resolved per brightness at call time.
  //   light: bg #F8FAFC / card #FFFFFF / body #334155 / border #E2E8F0
  //   dark : bg #0F172A / card #1E293B / body #E2E8F0 / border #334155
  static const Color accentSolid = Color(0xFFF97316);
  static const Color accentSolidDark = Color(0xFFEA580C);

  static Color get sidebarBg => isDark ? const Color(0xFF0F172A) : const Color(0xFF334155);
  static Color get sidebarHover => isDark ? const Color(0xFF1E293B) : const Color(0xFF475569);
  static Color get accent => accentSolid;
  static Color get accentDark => accentSolidDark;
  /// Soft accent wash: solid tint in light mode, ~15% translucent in dark mode.
  static Color get accentLight => isDark ? const Color(0x26F97316) : const Color(0xFFFFF1E6);
  static Color get bgMain => isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
  static Color get bgCard => isDark ? const Color(0xFF1E293B) : const Color(0xFFFFFFFF);
  static Color get textPrimary => isDark ? const Color(0xFFE2E8F0) : const Color(0xFF334155);
  static Color get textSecondary => isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
  static Color get textMuted => isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8);
  static Color get textSidebar => const Color(0xFFE2E8F0);
  static Color get textSidebarMuted => isDark ? const Color(0xFF94A3B8) : const Color(0xFFCBD5E1);
  static Color get border => isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
  static Color get borderLight => isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9);
  // Semantic colors. The "Light" variants are solid tints in light mode and a
  // ~16% translucent wash in dark mode, so status chips never glare on dark.
  static Color get green => const Color(0xFF16A34A);
  static Color get greenLight => isDark ? const Color(0x2916A34A) : const Color(0xFFDCFCE7);
  static Color get yellow => const Color(0xFFF59E0B);
  static Color get yellowLight => isDark ? const Color(0x29F59E0B) : const Color(0xFFFEF3C7);
  static Color get red => const Color(0xFFEF4444);
  static Color get redLight => isDark ? const Color(0x29EF4444) : const Color(0xFFFEE2E2);
  static Color get blue => const Color(0xFF2563EB);
  static Color get blueLight => isDark ? const Color(0x292563EB) : const Color(0xFFDBEAFE);
  static Color get purple => const Color(0xFF7C3AED);
  static Color get purpleLight => isDark ? const Color(0x297C3AED) : const Color(0xFFF3E8FF);

  // Fixed dark-surface palette. Always-dark screens (login, splash, error
  // screens) read these constants so they never flip with the theme mode.
  static const Color darkBg = Color(0xFF0F172A);
  static const Color darkSurface = Color(0xFF1E293B);
  static const Color darkBorder = Color(0xFF334155);
  static const Color darkTextPrimary = Color(0xFFE2E8F0);
  static const Color darkTextSecondary = Color(0xFF94A3B8);
  static const Color darkTextMuted = Color(0xFF64748B);

  // Always-dark auth backdrop gradient stops (login / worker register).
  static const Color authBgTop = Color(0xFF0F172A);
  static const Color authBgMid = Color(0xFF131C2E);
  static const Color authBgBottom = Color(0xFF1E293B);

  // ── Neutral / overlay tokens ──
  // Keeps the UI layer free of raw Colors.* literals while staying const-safe.
  static const Color onAccent = Color(0xFFFFFFFF);
  static const Color onAccentStrong = Color(0xE6FFFFFF);
  static const Color onAccentSoft = Color(0xD9FFFFFF);
  static const Color onAccentMuted = Color(0xB3FFFFFF);
  static const Color onAccentVeryFaint = Color(0x40FFFFFF);
  static const Color onAccentWash = Color(0x2EFFFFFF);
  static const Color onAccentFaint = Color(0x1FFFFFFF);
  static const Color ink = Color(0xFF000000);
  static const Color scrim = Color(0x4D000000);
  static const Color transparent = Color(0x00000000);

  // Sidebar width for adaptive layout
  static const double sidebarWidth = 240.0;

  // ── Backward-compatibility aliases ──
  static Color get primary => const Color(0xFF64748B);
  static Color get primaryLight => const Color(0xFF94A3B8);
  static Color get primaryDark => const Color(0xFF475569);
  static Color get accentOrange => accentSolid;
  static Color get accentOrangeLight => const Color(0xFFFB923C);
  static Color get success => const Color(0xFF16A34A);
  static Color get successLight => greenLight;
  static Color get warning => const Color(0xFFF59E0B);
  static Color get danger => const Color(0xFFEF4444);
  static Color get info => const Color(0xFF2563EB);
  static Color get bgColor => bgMain;
  static Color get cardColor => bgCard;
  static Color get sidebarColor => sidebarBg;
  static Color get borderColor => border;

  /// Brand gradient (accent -> accentDark) used by logo blocks and CTA buttons.
  static LinearGradient get brandGradient => const LinearGradient(
        colors: [accentSolid, accentSolidDark],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
  static LinearGradient get primaryGradient => const LinearGradient(
        colors: [accentSolid, accentSolidDark],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
  static LinearGradient get accentGradient => const LinearGradient(
        colors: [accentSolid, accentSolidDark],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
  static LinearGradient get successGradient => const LinearGradient(
        colors: [Color(0xFF16A34A), Color(0xFF4ADE80)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
  /// Always-dark backdrop used by the auth screens.
  static const LinearGradient authGradient = LinearGradient(
        colors: [authBgTop, authBgMid, authBgBottom],
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

// Base semantic color for a status key, or null when the key is unknown.
Color? _statusBase(String s) {
  switch (s) {
    case 'checked_in':
    case 'present':
    case 'completed':
    case 'active':
    case 'resolved':
    case 'on_track':
      return AppColors.green;
    case 'checked_out':
    case 'in_progress':
    case 'low':
      return AppColors.blue;
    case 'left_early':
    case 'late':
    case 'pending':
    case 'at_risk':
    case 'medium':
      return AppColors.yellow;
    case 'absent':
    case 'rejected':
    case 'open':
    case 'high':
    case 'critical':
    case 'delayed':
      return AppColors.red;
    default:
      return null;
  }
}

// Chip background for a status. The semantic "Light" getters resolve to a solid
// tint in light mode and a ~16% translucent wash in dark mode, so the same call
// renders correctly in both brightness modes.
Color _statusWash(String s) {
  switch (s) {
    case 'checked_in':
    case 'present':
    case 'completed':
    case 'active':
    case 'resolved':
    case 'on_track':
      return AppColors.greenLight;
    case 'checked_out':
    case 'in_progress':
    case 'low':
      return AppColors.blueLight;
    case 'left_early':
    case 'late':
    case 'pending':
    case 'at_risk':
    case 'medium':
      return AppColors.yellowLight;
    case 'absent':
    case 'rejected':
    case 'open':
    case 'high':
    case 'critical':
    case 'delayed':
      return AppColors.redLight;
    default:
      return AppColors.border;
  }
}

Color statusFg(String s) => _statusBase(s.toLowerCase()) ?? AppColors.textMuted;
Color statusBgOf(String s) => _statusWash(s.toLowerCase());

Widget statusPill(String status, {String? label}) {
  final s = status.toLowerCase();
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: statusBgOf(s),
      borderRadius: AppRadius.rPill,
    ),
    child: Text(
      (label ?? status).replaceAll('_', ' ').toUpperCase(),
      style: TextStyle(
        color: statusFg(s),
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.3,
      ),
    ),
  );
}

// Translucent surface used by cards. Light mode: hairline border + soft lift.
// Dark mode: same recipe with a stronger shadow so depth survives on dark bg.
Widget sectionCard({
  required Widget child,
  EdgeInsetsGeometry? padding,
  EdgeInsetsGeometry? margin,
}) =>
    Container(
      margin: margin,
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: AppRadius.rLg,
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.sm,
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
          color: AppColors.onAccent,
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
                letterSpacing: 0.1,
              ),
            ),
          ),
          if (icon != null)
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: (iconColor ?? AppColors.accent).withValues(alpha: 0.12),
                borderRadius: AppRadius.rSm,
              ),
              child: Icon(icon, size: 16, color: iconColor ?? AppColors.accent),
            ),
        ]),
        const SizedBox(height: 12),
        Text(
          value,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            height: 1.1,
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
  // Slightly looser line heights keep dense data screens readable.
  return GoogleFonts.interTextTheme(base).copyWith(
    displayLarge: GoogleFonts.inter(fontSize: 34, fontWeight: FontWeight.w800, height: 1.2, color: AppColors.textPrimary),
    displayMedium: GoogleFonts.inter(fontSize: 26, fontWeight: FontWeight.w800, height: 1.2, color: AppColors.textPrimary),
    headlineLarge: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w700, height: 1.25, color: AppColors.textPrimary),
    headlineMedium: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w700, height: 1.3, color: AppColors.textPrimary),
    headlineSmall: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w700, height: 1.3, color: AppColors.textPrimary),
    titleLarge: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w700, height: 1.3, color: AppColors.textPrimary),
    titleMedium: GoogleFonts.inter(fontSize: 14.5, fontWeight: FontWeight.w600, height: 1.35, color: AppColors.textPrimary),
    bodyLarge: GoogleFonts.inter(fontSize: 15, height: 1.4, color: AppColors.textPrimary),
    bodyMedium: GoogleFonts.inter(fontSize: 14, height: 1.4, color: AppColors.textSecondary),
    bodySmall: GoogleFonts.inter(fontSize: 13, height: 1.4, color: AppColors.textMuted),
    labelLarge: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, height: 1.3),
    labelSmall: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.4, height: 1.3),
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
        scrolledUnderElevation: 0,
        surfaceTintColor: AppColors.transparent,
        titleTextStyle: GoogleFonts.inter(
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
          borderRadius: AppRadius.rLg,
          side: BorderSide(color: AppColors.border),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: AppColors.onAccent,
          disabledBackgroundColor: AppColors.accent.withValues(alpha: 0.45),
          disabledForegroundColor: AppColors.onAccent,
          elevation: 0,
          minimumSize: const Size(0, 50),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.rBtn),
          textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: BorderSide(color: AppColors.border),
          minimumSize: const Size(0, 50),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.rBtn),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.accent,
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.bgMain,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: AppRadius.bInput,
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.bInput,
          borderSide: BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.bInput,
          borderSide: BorderSide(color: AppColors.accent, width: 1.6),
        ),
        labelStyle: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 14),
        hintStyle: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 14),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.bgCard,
        selectedItemColor: AppColors.accent,
        unselectedItemColor: AppColors.textMuted,
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
        elevation: 0,
      ),
      // Material 3 navigation bar: selected pill + accent icon/label.
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.bgCard,
        surfaceTintColor: AppColors.transparent,
        indicatorColor: AppColors.accentLight,
        elevation: 0,
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith((s) => GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: s.contains(WidgetState.selected) ? AppColors.accent : AppColors.textMuted,
            )),
        iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
              size: 22,
              color: s.contains(WidgetState.selected) ? AppColors.accent : AppColors.textMuted,
            )),
      ),
      dividerTheme: DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: AppRadius.rPill),
        side: BorderSide(color: AppColors.border),
        backgroundColor: AppColors.bgCard,
        selectedColor: AppColors.accentLight,
        labelStyle: GoogleFonts.inter(
          fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.bgCard,
        surfaceTintColor: AppColors.transparent,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.rSheet),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.accent,
        unselectedLabelColor: AppColors.textSecondary,
        indicatorColor: AppColors.accent,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: AppColors.transparent,
        indicator: BoxDecoration(
          color: AppColors.accentLight,
          borderRadius: AppRadius.rPill,
        ),
        labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14),
        unselectedLabelStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      // ── Shared component polish (kept in sync across light & dark) ──
      iconTheme: IconThemeData(color: AppColors.textSecondary),
      listTileTheme: ListTileThemeData(
        iconColor: AppColors.textSecondary,
        textColor: AppColors.textPrimary,
        titleTextStyle: GoogleFonts.inter(
          color: AppColors.textPrimary, fontSize: 14.5, fontWeight: FontWeight.w600,
        ),
        subtitleTextStyle: GoogleFonts.inter(
          color: AppColors.textMuted, fontSize: 13, fontWeight: FontWeight.w400,
        ),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.rSm),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.darkSurface,
        contentTextStyle: GoogleFonts.inter(color: AppColors.onAccent, fontSize: 13.5, fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.rBtn),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.bgCard,
        surfaceTintColor: AppColors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.rMd,
          side: BorderSide(color: AppColors.border),
        ),
        textStyle: GoogleFonts.inter(color: AppColors.textPrimary, fontSize: 14),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? AppColors.onAccent : AppColors.textMuted),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? AppColors.accent : AppColors.border),
        trackOutlineColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? AppColors.accent : AppColors.border),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? AppColors.accent : AppColors.transparent),
        side: BorderSide(color: AppColors.textMuted, width: 1.6),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.rXs),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? AppColors.accent : AppColors.textMuted),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: AppColors.accent,
        linearTrackColor: AppColors.border,
        circularTrackColor: AppColors.border,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AppColors.bgCard,
        surfaceTintColor: AppColors.transparent,
        showDragHandle: true,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.bSheet),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => AppColors.border),
        radius: const Radius.circular(8),
        thickness: const WidgetStatePropertyAll(6),
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
        scrolledUnderElevation: 0,
        surfaceTintColor: AppColors.transparent,
        titleTextStyle: GoogleFonts.inter(
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
          borderRadius: AppRadius.rLg,
          side: BorderSide(color: AppColors.border),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: AppColors.onAccent,
          disabledBackgroundColor: AppColors.accent.withValues(alpha: 0.45),
          disabledForegroundColor: AppColors.onAccent,
          elevation: 0,
          minimumSize: const Size(0, 50),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.rBtn),
          textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: BorderSide(color: AppColors.border),
          minimumSize: const Size(0, 50),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.rBtn),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.accent,
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.bgMain,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: AppRadius.bInput,
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.bInput,
          borderSide: BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.bInput,
          borderSide: BorderSide(color: AppColors.accent, width: 1.6),
        ),
        labelStyle: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 14),
        hintStyle: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 14),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.bgCard,
        selectedItemColor: AppColors.accent,
        unselectedItemColor: AppColors.textMuted,
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
        elevation: 0,
      ),
      // Material 3 navigation bar: selected pill + accent icon/label.
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.bgCard,
        surfaceTintColor: AppColors.transparent,
        indicatorColor: AppColors.accentLight,
        elevation: 0,
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith((s) => GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: s.contains(WidgetState.selected) ? AppColors.accent : AppColors.textMuted,
            )),
        iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
              size: 22,
              color: s.contains(WidgetState.selected) ? AppColors.accent : AppColors.textMuted,
            )),
      ),
      dividerTheme: DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: AppRadius.rPill),
        side: BorderSide(color: AppColors.border),
        backgroundColor: AppColors.bgCard,
        selectedColor: AppColors.accentLight,
        labelStyle: GoogleFonts.inter(
          fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.bgCard,
        surfaceTintColor: AppColors.transparent,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.rSheet),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.accent,
        unselectedLabelColor: AppColors.textSecondary,
        indicatorColor: AppColors.accent,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: AppColors.transparent,
        indicator: BoxDecoration(
          color: AppColors.accentLight,
          borderRadius: AppRadius.rPill,
        ),
        labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14),
        unselectedLabelStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      // ── Shared component polish (kept in sync across light & dark) ──
      iconTheme: IconThemeData(color: AppColors.textSecondary),
      listTileTheme: ListTileThemeData(
        iconColor: AppColors.textSecondary,
        textColor: AppColors.textPrimary,
        titleTextStyle: GoogleFonts.inter(
          color: AppColors.textPrimary, fontSize: 14.5, fontWeight: FontWeight.w600,
        ),
        subtitleTextStyle: GoogleFonts.inter(
          color: AppColors.textMuted, fontSize: 13, fontWeight: FontWeight.w400,
        ),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.rSm),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.darkSurface,
        contentTextStyle: GoogleFonts.inter(color: AppColors.onAccent, fontSize: 13.5, fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.rBtn),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.bgCard,
        surfaceTintColor: AppColors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.rMd,
          side: BorderSide(color: AppColors.border),
        ),
        textStyle: GoogleFonts.inter(color: AppColors.textPrimary, fontSize: 14),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? AppColors.onAccent : AppColors.textMuted),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? AppColors.accent : AppColors.border),
        trackOutlineColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? AppColors.accent : AppColors.border),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? AppColors.accent : AppColors.transparent),
        side: BorderSide(color: AppColors.textMuted, width: 1.6),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.rXs),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? AppColors.accent : AppColors.textMuted),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: AppColors.accent,
        linearTrackColor: AppColors.border,
        circularTrackColor: AppColors.border,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AppColors.bgCard,
        surfaceTintColor: AppColors.transparent,
        showDragHandle: true,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.bSheet),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => AppColors.border),
        radius: const Radius.circular(8),
        thickness: const WidgetStatePropertyAll(6),
      ),
    );

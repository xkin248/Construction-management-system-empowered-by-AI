import 'package:flutter/material.dart';
import '../constants/colors.dart';
import '../constants/styles.dart';

class AppTheme {
  static ThemeData light() => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary, brightness: Brightness.light,
      primary: AppColors.primary, onPrimary: Colors.white, secondary: AppColors.accentOrange,
      onSecondary: Colors.white, surface: AppColors.cardColor, error: AppColors.danger),
    primaryColor: AppColors.primary,
    scaffoldBackgroundColor: AppColors.bgColor,
    fontFamily: 'Inter',

    appBarTheme: const AppBarTheme(backgroundColor: Colors.white, foregroundColor: AppColors.textPrimary,
      elevation: 0, scrolledUnderElevation: 1, centerTitle: false,
      titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: -0.2),
      iconTheme: IconThemeData(color: AppColors.textPrimary, size: 22)),

    elevatedButtonTheme: ElevatedButtonThemeData(style: ElevatedButton.styleFrom(
      backgroundColor: AppColors.primary, foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
      shape: RoundedRectangleBorder(borderRadius: AppStyles.radius12), elevation: 0,
      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.2))),

    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(
      foregroundColor: AppColors.primary, side: const BorderSide(color: AppColors.borderColor),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
      shape: RoundedRectangleBorder(borderRadius: AppStyles.radius12),
      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),

    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(
      foregroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
      shape: RoundedRectangleBorder(borderRadius: AppStyles.radius8),
      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),

    inputDecorationTheme: InputDecorationTheme(
      filled: true, fillColor: AppColors.bgColor,
      border: OutlineInputBorder(borderRadius: AppStyles.radius12, borderSide: const BorderSide(color: AppColors.borderColor, width: 1)),
      enabledBorder: OutlineInputBorder(borderRadius: AppStyles.radius12, borderSide: const BorderSide(color: AppColors.borderColor, width: 1)),
      focusedBorder: OutlineInputBorder(borderRadius: AppStyles.radius12, borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), isDense: true,
      hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 14)),

    // ✅ CardTheme → CardThemeData
    cardTheme: const CardThemeData(color: AppColors.cardColor, elevation: 0, margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: AppStyles.radius16, side: BorderSide(color: AppColors.borderLight))),

    dividerTheme: const DividerThemeData(color: AppColors.borderLight, thickness: 1, space: 24),

    navigationRailTheme: NavigationRailThemeData(backgroundColor: AppColors.sidebarColor, elevation: 0,
      indicatorColor: AppColors.primary.withValues(alpha: 0.15), indicatorShape: RoundedRectangleBorder(borderRadius: AppStyles.radius12),
      selectedLabelTextStyle: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
      unselectedLabelTextStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13, fontWeight: FontWeight.w500),
      selectedIconTheme: const IconThemeData(color: Colors.white, size: 20),
      unselectedIconTheme: const IconThemeData(color: Color(0xFF94A3B8), size: 20)),

    navigationBarTheme: NavigationBarThemeData(backgroundColor: Colors.white,
      indicatorColor: AppColors.primary.withValues(alpha: 0.12), height: 64,
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(fontSize: 11,
        fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
        color: s.contains(WidgetState.selected) ? AppColors.primary : AppColors.textMuted)),
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(size: 22,
        color: s.contains(WidgetState.selected) ? AppColors.primary : AppColors.textMuted))),

    chipTheme: ChipThemeData(backgroundColor: AppColors.bgColor, selectedColor: AppColors.primary.withValues(alpha: 0.12),
      disabledColor: AppColors.borderLight, labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      shape: RoundedRectangleBorder(borderRadius: AppStyles.radius8), side: BorderSide.none),

    // ✅ DialogTheme → DialogThemeData
    dialogTheme: const DialogThemeData(backgroundColor: Colors.white, elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: AppStyles.radius16), titleTextStyle: AppStyles.h3),

    // ✅ 删除不存在的 margin 参数
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: AppStyles.radius12),
      backgroundColor: AppColors.textPrimary,
      contentTextStyle: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
      actionTextColor: AppColors.accentOrangeLight),

    progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.primary, linearMinHeight: 6, circularTrackColor: AppColors.borderLight),

    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.primary : Colors.white),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.primary.withValues(alpha: 0.5) : AppColors.borderColor)),
  );
}
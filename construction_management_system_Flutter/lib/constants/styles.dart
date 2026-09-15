import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Legacy style constants — kept for backward compatibility with *_screen.dart files.
class AppStyles {
  static const BorderRadius radius4 = BorderRadius.all(Radius.circular(AppRadius.md));
  static const BorderRadius radius8 = BorderRadius.all(Radius.circular(AppRadius.md));
  static const BorderRadius radius10 = BorderRadius.all(Radius.circular(AppRadius.md));
  static const BorderRadius radius12 = BorderRadius.all(Radius.circular(AppRadius.md));
  static const BorderRadius radius16 = BorderRadius.all(Radius.circular(AppRadius.md));
  static const BorderRadius radius24 = BorderRadius.all(Radius.circular(AppRadius.md));

  static TextStyle get h1 => TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w800,
        color: AppColors.textPrimary,
        height: 1.2,
        letterSpacing: -0.5,
      );
  static TextStyle get h2 => TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
        height: 1.3,
        letterSpacing: -0.3,
      );
  static TextStyle get h3 => TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
        height: 1.4,
      );
  static TextStyle get h4 => TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
        height: 1.4,
      );
  static TextStyle get body => TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: AppColors.textPrimary,
        height: 1.5,
      );
  static TextStyle get bodySecondary => TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: AppColors.textSecondary,
        height: 1.5,
      );
  static TextStyle get caption => TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: AppColors.textMuted,
        height: 1.4,
        letterSpacing: 0.2,
      );
  static TextStyle get label => TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppColors.textSecondary,
        height: 1.4,
        letterSpacing: 0.1,
      );

  static List<BoxShadow> get cardShadow => AppShadows.sm;
  static List<BoxShadow> get cardShadowLg => AppShadows.md;

  static InputDecoration inputDecoration({String? hint, Widget? prefixIcon, Widget? suffixIcon}) =>
      InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 14),
        prefixIcon: prefixIcon,
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: AppColors.bgColor,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: radius12,
          borderSide: BorderSide(color: AppColors.borderColor, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: radius12,
          borderSide: BorderSide(color: AppColors.borderColor, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radius12,
          borderSide: BorderSide(color: AppColors.primary, width: 1.5),
        ),
        isDense: true,
      );
}

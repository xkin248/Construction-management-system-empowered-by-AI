import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';

/// Global app settings (language + theme mode).
///
/// - [lang] drives UI language: 'en' (English), 'zh' (中文), 'ms' (Bahasa Melayu)
/// - [themeMode] drives MaterialApp.themeMode: light / dark / system
/// - Both are persisted in SharedPreferences and shared across every page.
class AppSettings {
  static const _kLangKey = 'app_lang';
  static const _kThemeKey = 'app_theme_mode';

  static final ValueNotifier<String> lang = ValueNotifier<String>('en');
  static final ValueNotifier<String> themeMode = ValueNotifier<String>('system');

  /// Translate helper: t('English', '中文', 'Bahasa Melayu').
  /// Falls back to English when a translation is missing.
  static String t(String en, [String? zh, String? ms]) {
    switch (lang.value) {
      case 'zh':
        return zh ?? en;
      case 'ms':
        return ms ?? en;
      default:
        return en;
    }
  }

  static bool get isDark {
    final m = themeMode.value;
    if (m == 'light') return false;
    if (m == 'dark') return true;
    // system
    return AppColors.darkMode.value;
  }

  /// Load persisted settings at startup (called once from main()).
  static Future<void> init() async {
    final sp = await SharedPreferences.getInstance();
    final savedLang = sp.getString(_kLangKey) ?? 'en';
    final savedTheme = sp.getString(_kThemeKey) ?? 'system';
    lang.value = ['en', 'zh', 'ms'].contains(savedLang) ? savedLang : 'en';
    themeMode.value = ['light', 'dark', 'system'].contains(savedTheme) ? savedTheme : 'system';
    // Apply theme to AppColors immediately so root pages rebuild correctly.
    _applyThemeToAppColors();
    lang.addListener(_persist);
    themeMode.addListener(() {
      _persist();
      _applyThemeToAppColors();
    });
  }

  static void _applyThemeToAppColors() {
    final m = themeMode.value;
    if (m == 'light') {
      AppColors.darkMode.value = false;
    } else if (m == 'dark') {
      AppColors.darkMode.value = true;
    }
    // 'system' keeps AppColors.darkMode driven by platform brightness (main.dart observer).
  }

  static Future<void> _persist() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kLangKey, lang.value);
    await sp.setString(_kThemeKey, themeMode.value);
  }

  /// Sync AppColors when the OS brightness changes while themeMode == 'system'.
  static void onSystemBrightnessChanged(bool dark) {
    if (themeMode.value == 'system') {
      AppColors.darkMode.value = dark;
    }
  }
}

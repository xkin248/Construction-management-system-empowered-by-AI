import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/app_settings.dart';
import '../theme/app_theme.dart';
import '../l10n/app_strings.dart';

/// Language + Theme switcher shown in every page's app bar.
/// A single popup menu exposes:
///   - Language: English / Bahasa Melayu
///   - Theme mode: Light / Dark / System
class AppSettingsActions extends StatelessWidget {
  const AppSettingsActions({super.key});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: AppStrings.t('settings.title'),
      icon: Icon(Icons.settings_suggest_rounded, color: AppColors.textPrimary, size: 21),
      color: AppColors.bgCard,
      surfaceTintColor: Colors.transparent,
      onSelected: (v) {
        if (v == 'lang_en') AppSettings.lang.value = 'en';
        if (v == 'lang_ms') AppSettings.lang.value = 'ms';
        if (v == 'theme_light') AppSettings.themeMode.value = 'light';
        if (v == 'theme_dark') AppSettings.themeMode.value = 'dark';
        if (v == 'theme_system') AppSettings.themeMode.value = 'system';
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'lang_en',
          child: _row(Icons.language_rounded, AppStrings.t('settings.english'),
              checked: AppSettings.lang.value == 'en'),
        ),
        PopupMenuItem(
          value: 'lang_ms',
          child: _row(Icons.language_rounded, AppStrings.t('settings.bm'),
              checked: AppSettings.lang.value == 'ms'),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'theme_light',
          child: _row(Icons.light_mode_rounded, AppStrings.t('settings.lightTheme'),
              checked: AppSettings.themeMode.value == 'light'),
        ),
        PopupMenuItem(
          value: 'theme_dark',
          child: _row(Icons.dark_mode_rounded, AppStrings.t('settings.darkTheme'),
              checked: AppSettings.themeMode.value == 'dark'),
        ),
        PopupMenuItem(
          value: 'theme_system',
          child: _row(Icons.brightness_auto_rounded, AppStrings.t('settings.system'),
              checked: AppSettings.themeMode.value == 'system'),
        ),
      ],
    );
  }

  Widget _row(IconData icon, String label, {required bool checked}) {
    return Row(
      children: [
        Icon(icon, size: 18, color: checked ? AppColors.green : AppColors.textMuted),
        const SizedBox(width: 10),
        Expanded(
          child: Text(label,
              style: GoogleFonts.outfit(
                fontSize: 14,
                color: AppColors.textPrimary,
                fontWeight: checked ? FontWeight.w700 : FontWeight.w500,
              )),
        ),
        if (checked) Icon(Icons.check_rounded, size: 16, color: AppColors.green),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/app_settings.dart';
import '../theme/app_theme.dart';
import '../l10n/app_strings.dart';

/// Theme + Language switcher shown in every page's app bar.
/// Two independent buttons:
///   - Theme: moon icon when dark / sun icon when light, tap to toggle
///   - Language: "EN" / "BM" text button, tap to switch
class AppSettingsActions extends StatefulWidget {
  const AppSettingsActions({super.key});

  @override
  State<AppSettingsActions> createState() => _AppSettingsActionsState();
}

class _AppSettingsActionsState extends State<AppSettingsActions> {
  @override
  void initState() {
    super.initState();
    // Listen to the theme / language notifiers directly so the buttons
    // rebuild in place on every toggle — otherwise the icon/label snapshot
    // goes stale after the first tap and the switch looks one-way only.
    AppColors.darkMode.addListener(_onChanged);
    AppSettings.lang.addListener(_onChanged);
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    AppColors.darkMode.removeListener(_onChanged);
    AppSettings.lang.removeListener(_onChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.darkMode.value;
    final lang = AppSettings.lang.value;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Theme toggle: dark -> moon (tap to go light), light -> sun (tap to go dark)
        IconButton(
          tooltip: AppStrings.t('settings.darkTheme'),
          icon: Icon(
            dark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
            color: AppColors.textPrimary,
            size: 21,
          ),
          onPressed: () =>
              AppSettings.themeMode.value = dark ? 'light' : 'dark',
        ),
        // Language toggle: EN <-> BM
        TextButton(
          onPressed: () => AppSettings.lang.value = lang == 'en' ? 'ms' : 'en',
          style: TextButton.styleFrom(
            minimumSize: const Size(40, 32),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            lang == 'en' ? 'EN' : 'BM',
            style: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../l10n/app_strings.dart';

/// Greeting header: who the user is plus a one-line hint about the page.
///
/// Reads only the profile map handed in by the page — no global state.
class WelcomeCard extends StatelessWidget {
  final Map me;

  const WelcomeCard({super.key, required this.me});

  @override
  Widget build(BuildContext context) {
    final name = (me['full_name'] ?? me['name'] ?? '').toString().trim();
    final hour = DateTime.now().hour;
    final greetKey = hour < 12
        ? 'dash.goodMorning'
        : hour < 18
            ? 'dash.goodAfternoon'
            : 'dash.goodEvening';
    final greeting = name.isEmpty
        ? AppStrings.t(greetKey)
        : '${AppStrings.t(greetKey)}, ${name.split(' ').first}';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: AppRadius.rLg,
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.sm,
      ),
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: AppColors.accentLight, shape: BoxShape.circle),
          child: Icon(Icons.waving_hand_rounded, size: 22, color: AppColors.accent),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              greeting,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                  fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 4),
            Text(
              AppStrings.t('dash.welcomeHint'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(fontSize: 12.5, color: AppColors.textSecondary),
            ),
          ]),
        ),
      ]),
    );
  }
}

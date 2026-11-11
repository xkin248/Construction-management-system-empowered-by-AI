import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/app_settings.dart';
import '../theme/app_theme.dart';

/// One recognisable introduction for every BuildSmart work area.
///
/// It never reads the API or stores state. Consequently it is safe to use in
/// supervisor and worker pages, including pages embedded in a shell. Copy is
/// supplied in all three supported languages by the screen that owns it.
class AppPageIntro extends StatelessWidget {
  final IconData icon;
  final String enTitle;
  final String msTitle;
  final String zhTitle;
  final String enSubtitle;
  final String msSubtitle;
  final String zhSubtitle;
  final bool worker;

  const AppPageIntro({
    super.key,
    required this.icon,
    required this.enTitle,
    required this.msTitle,
    required this.zhTitle,
    required this.enSubtitle,
    required this.msSubtitle,
    required this.zhSubtitle,
    this.worker = false,
  });

  @override
  Widget build(BuildContext context) {
    final title = AppSettings.t(enTitle, zhTitle, msTitle);
    final subtitle = AppSettings.t(enSubtitle, zhSubtitle, msSubtitle);
    final foreground = worker ? Colors.white : AppColors.textPrimary;
    final secondary = worker ? const Color(0xFFDBEAFE) : AppColors.textSecondary;
    final gradient = worker
        ? const LinearGradient(
            colors: [AppColors.navy, AppColors.navyDark],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
        : LinearGradient(
            colors: [AppColors.bgCard, AppColors.navyWash],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          );

    return Semantics(
      header: true,
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 98),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: AppRadius.rXl,
          border: Border.all(color: worker ? AppColors.navyBorder : AppColors.border),
          boxShadow: AppShadows.sm,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: worker ? const Color(0x26FFFFFF) : AppColors.navyWash,
                borderRadius: AppRadius.rLg,
                border: Border.all(
                  color: worker ? const Color(0x3DFFFFFF) : AppColors.navyBorder,
                ),
              ),
              child: Icon(icon, size: 28, color: worker ? AppColors.accentSolid : AppColors.navyText),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: worker ? 21 : 20,
                      fontWeight: FontWeight.w900,
                      height: 1.15,
                      color: foreground,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    subtitle,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: worker ? 14.5 : 13.5,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                      color: secondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
    final isPhone = MediaQuery.sizeOf(context).width < 600;
    return Container(
      height: isPhone ? 192 : 214,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: AppRadius.rXl,
        boxShadow: AppShadows.md,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const Image(
            image: AssetImage('assets/images/construction_dashboard_hero.png'),
            fit: BoxFit.cover,
            alignment: Alignment.centerRight,
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  AppColors.navyDeeper.withValues(alpha: 0.98),
                  AppColors.navy.withValues(alpha: 0.84),
                  AppColors.navy.withValues(alpha: 0.22),
                ],
                stops: const [0, 0.48, 1],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(isPhone ? 18 : 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.construction_rounded, color: Color(0xFFFBBF24), size: 15),
                    const SizedBox(width: 6),
                    Text(
                      'BUILDSMART',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 13),
                Text(
                  greeting,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: isPhone ? 25 : 30,
                    height: 1.08,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.65,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: isPhone ? 230 : 330,
                  child: Text(
                    AppStrings.t('dash.welcomeHint'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: isPhone ? 12.5 : 14,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.88),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

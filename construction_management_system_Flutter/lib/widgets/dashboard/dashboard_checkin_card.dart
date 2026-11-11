import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../l10n/app_strings.dart';

/// Supervisor quick check-in card. Fully controlled by the page: the location
/// lookup, API calls and permission flow all stay in the screen.
class SupervisorCheckInCard extends StatelessWidget {
  final bool checkedIn;
  final bool loading;
  final String message;
  final VoidCallback onCheckIn;
  final VoidCallback onCheckOut;

  const SupervisorCheckInCard({
    super.key,
    required this.checkedIn,
    required this.loading,
    required this.message,
    required this.onCheckIn,
    required this.onCheckOut,
  });

  @override
  Widget build(BuildContext context) {
    final accent = checkedIn ? AppColors.green : AppColors.accent;
    final bg = checkedIn ? AppColors.greenLight : AppColors.accentLight;
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
          width: 46,
          height: 46,
          decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
          child: Icon(
            checkedIn ? Icons.check_circle_rounded : Icons.location_on_rounded,
            color: accent,
            size: 24,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(checkedIn ? AppStrings.t('dash.onSite') : AppStrings.t('dash.quickCheckin'),
                style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            const SizedBox(height: 4),
            Text(message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(fontSize: 12.5, color: AppColors.textSecondary)),
          ]),
        ),
        const SizedBox(width: 12),
        loading
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5))
            : ElevatedButton.icon(
                onPressed: checkedIn ? onCheckOut : onCheckIn,
                icon: Icon(checkedIn ? Icons.logout_rounded : Icons.login_rounded, size: 16),
                label: Text(checkedIn ? AppStrings.t('att.checkOut') : AppStrings.t('att.checkIn')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: AppColors.accentInk,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
      ]),
    );
  }
}

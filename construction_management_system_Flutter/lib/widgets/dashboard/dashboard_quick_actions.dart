import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../l10n/app_strings.dart';
import '../a11y.dart';
import 'dashboard_section_parts.dart';

/// The three most common first steps of a new user, as one-tap tiles.
///
/// Every action is injected by the page so navigation stays in the screen.
class QuickActionsCard extends StatelessWidget {
  final VoidCallback onNewTask;
  final VoidCallback onAddWorker;
  final VoidCallback onNotifications;

  const QuickActionsCard({
    super.key,
    required this.onNewTask,
    required this.onAddWorker,
    required this.onNotifications,
  });

  @override
  Widget build(BuildContext context) {
    final actions = [
      (Icons.add_task_rounded, AppStrings.t('dash.actionNewTask'), onNewTask),
      (Icons.person_add_alt_1_rounded, AppStrings.t('dash.actionAddWorker'), onAddWorker),
      (Icons.notifications_active_outlined, AppStrings.t('dash.actionNotifications'), onNotifications),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionHeader(AppStrings.t('dash.quickActions')),
      const SizedBox(height: 10),
      Row(
        children: [
          for (var i = 0; i < actions.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(
              child: QuickActionTile(
                icon: actions[i].$1,
                label: actions[i].$2,
                onTap: actions[i].$3,
              ),
            ),
          ],
        ],
      ),
    ]);
  }
}

/// Single quick-action tile (icon + label, whole surface tappable).
class QuickActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const QuickActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return semanticTapTarget(
      label: label,
      child: Material(
      color: AppColors.bgCard,
      borderRadius: AppRadius.rMd,
      child: InkWell(
        borderRadius: AppRadius.rMd,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: AppRadius.rMd,
            border: Border.all(color: AppColors.border),
          ),
          child: Column(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: AppColors.accentLight, borderRadius: AppRadius.rSm),
              child: Icon(icon, size: 19, color: AppColors.accent),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                  fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            ),
          ]),
        ),
      )),
    );
  }
}

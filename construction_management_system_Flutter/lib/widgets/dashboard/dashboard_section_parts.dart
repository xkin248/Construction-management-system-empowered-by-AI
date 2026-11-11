import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../l10n/app_strings.dart';

/// Collapsible dashboard card: keeps secondary content one tap away instead of
/// pushing the first screen down. Collapsed by default.
class CollapsibleSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> children;

  const CollapsibleSection({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: AppRadius.rLg,
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.sm,
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        // Hide the default ExpansionTile divider lines.
        data: Theme.of(context).copyWith(dividerColor: AppColors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          iconColor: AppColors.accent,
          collapsedIconColor: AppColors.textMuted,
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: AppColors.accentLight, borderRadius: AppRadius.rSm),
            child: Icon(icon, size: 18, color: AppColors.accent),
          ),
          title: Text(
            title,
            style: GoogleFonts.inter(
                fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
          ),
          subtitle: Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(fontSize: 11.5, color: AppColors.textMuted),
          ),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }
}

/// Small accent-bar heading used inside dashboard sections.
class SectionHeader extends StatelessWidget {
  final String title;
  final String? sub;

  const SectionHeader(this.title, {super.key, this.sub});

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      Container(width: 3.5, height: 16, decoration: BoxDecoration(
        color: AppColors.accent,
        borderRadius: AppRadius.rPill,
      )),
      const SizedBox(width: 8),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          if (sub != null)
            Text(sub!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted)),
        ]),
      ),
    ]);
  }
}

/// Compact empty-state block used across dashboard list sections.
class DashboardEmptyBox extends StatelessWidget {
  final String message;
  final IconData icon;

  const DashboardEmptyBox(this.message, {super.key, this.icon = Icons.inbox_outlined});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: AppRadius.rMd,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(children: [
        Icon(icon, size: 26, color: AppColors.textMuted.withValues(alpha: 0.6)),
        const SizedBox(height: 8),
        Text(message,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted)),
      ]),
    );
  }
}

/// Inline warning banner shown when one or more dashboard endpoints failed.
class DashboardErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const DashboardErrorBanner({super.key, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.redLight,
        borderRadius: AppRadius.rSm,
        border: Border.all(color: AppColors.red.withValues(alpha: 0.35)),
      ),
      child: Row(children: [
        Icon(Icons.error_outline_rounded, size: 18, color: AppColors.red),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(fontSize: 12.5, color: AppColors.red),
          ),
        ),
        TextButton(
          onPressed: onRetry,
          style: TextButton.styleFrom(
            foregroundColor: AppColors.red,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          ),
          child: Text(AppStrings.t('common.retry')),
        ),
      ]),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../l10n/app_strings.dart';
import '../charts.dart';

/// Weekly attendance bar chart card.
class WeeklyAttendanceCard extends StatelessWidget {
  final List<double> data;
  final List<String> labels;

  const WeeklyAttendanceCard({super.key, required this.data, required this.labels});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: AppRadius.rLg,
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.sm,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Flexible(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(AppStrings.t('dash.weeklyAttendance'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              Text(AppStrings.t('dash.allProjectsCombined'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted)),
            ]),
          ),
          TextButton(
            onPressed: () {},
            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
            child: Text('${AppStrings.t('dash.viewAll')} →',
                style: GoogleFonts.inter(fontSize: 13, color: AppColors.accent, fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 16),
        if (data.isNotEmpty)
          // Always render the bar chart when the weekly payload exists, even if
          // all values are 0 (LabeledBarChart handles all-zero with 4px stubs).
          // Previously `data.any((v) => v > 0)` showed a "no data" placeholder
          // on phones, making the bar chart invisible whenever the week had no
          // attendance yet.
          LabeledBarChart(
              values: data,
              labels: labels,
              height: 150,
              color: AppColors.blue.withValues(alpha: 0.25),
              highlightColor: AppColors.blue)
        else
          Container(
            height: 150,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.bgCard,
              borderRadius: AppRadius.rSm,
              border: Border.all(color: AppColors.border),
            ),
            child: Text(AppStrings.t('dash.noAttendanceData'),
                style: GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted)),
          ),
      ]),
    );
  }
}

/// Task distribution donut card.
class TaskDistributionCard extends StatelessWidget {
  final int completedPct;
  final int inProgressPct;
  final int pendingPct;
  final bool hasTasks;

  const TaskDistributionCard({
    super.key,
    required this.completedPct,
    required this.inProgressPct,
    required this.pendingPct,
    this.hasTasks = true,
  });

  @override
  Widget build(BuildContext context) {
    final slices = hasTasks
        ? [
            DonutSlice(completedPct.toDouble(), AppColors.green, 'Completed'),
            DonutSlice(inProgressPct.toDouble(), AppColors.accent, 'In Progress'),
            DonutSlice(pendingPct.toDouble(), AppColors.border, 'Pending'),
          ]
        : [DonutSlice(1, AppColors.border, 'Empty')];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: AppRadius.rLg,
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.sm,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(AppStrings.t('dash.taskDistribution'),
            style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        const SizedBox(height: 4),
        Text(AppStrings.t('dash.allActiveProjects'),
            style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted)),
        const SizedBox(height: 16),
        Center(
          child: SimpleDonutChart(
            size: 118,
            slices: slices,
          ),
        ),
        const SizedBox(height: 16),
        if (hasTasks) ...[
          _LegendRow('Completed', '$completedPct%', AppColors.green),
          const SizedBox(height: 8),
          _LegendRow('In Progress', '$inProgressPct%', AppColors.accent),
          const SizedBox(height: 8),
          _LegendRow('Pending', '$pendingPct%', AppColors.textMuted),
        ] else
          Center(
            child: Text(AppStrings.t('dash.noTaskData'),
                style: GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted)),
          ),
      ]),
    );
  }
}

class _LegendRow extends StatelessWidget {
  final String label;
  final String pct;
  final Color color;

  const _LegendRow(this.label, this.pct, this.color);

  @override
  Widget build(BuildContext context) => Row(children: [
        Container(width: 9, height: 9, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary))),
        Text(pct, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
      ]);
}

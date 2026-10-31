import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../l10n/app_strings.dart';

/// Headline KPI block: three numbers only, so a first-time user understands the
/// site status without scrolling. Wide screens get one row, phones get a
/// full-width hero card plus compact metric rows.
class DashboardKpiRow extends StatelessWidget {
  final int onSite;
  final int totalWorkers;
  final int activeTasks;
  final int productivity;
  final int todayRate;
  final int present;
  final int late;
  final int absent;
  final int completed;
  final int inProgress;
  final int totalTasks;
  final int completedPct;

  const DashboardKpiRow({
    super.key,
    required this.onSite,
    required this.totalWorkers,
    required this.activeTasks,
    required this.productivity,
    required this.todayRate,
    required this.present,
    required this.late,
    required this.absent,
    required this.completed,
    required this.inProgress,
    required this.totalTasks,
    required this.completedPct,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, cs) {
      final isWide = cs.maxWidth > 600;
      final cards = [
        KpiCard(
          label: AppStrings.t('dash.todayAttendanceRate'),
          value: '$todayRate%',
          sub: '$onSite/$totalWorkers on site · $late late · $absent absent',
          icon: Icons.fact_check_rounded,
          iconColor: AppColors.accent,
        ),
        KpiCard(
          label: 'Active Tasks',
          value: '$activeTasks',
          // Show real completed + in-progress counts from the KPI response.
          sub: completed > 0 || inProgress > 0
              ? '$completed done · $inProgress in progress'
              : null,
          icon: Icons.assignment_rounded,
          iconColor: AppColors.blue,
        ),
        KpiCard(
          label: 'Overall Productivity',
          value: '$productivity%',
          // No reliable week-over-week delta from the API - omit rather than
          // show a fake '+4%' that misleads users.
          sub: totalTasks > 0 ? '$completedPct% tasks completed' : null,
          icon: Icons.trending_up_rounded,
          iconColor: AppColors.green,
          valueColor: AppColors.green,
        ),
      ];

      if (isWide) {
        return Row(
            children: cards
                .expand((c) => [Expanded(child: c), const SizedBox(width: 16)])
                .toList()
              ..removeLast());
      }
      // Mobile: full-width hero card + compact metric rows.
      // Single-column layout is kept on purpose - the previous 2x2 grid left
      // the whole dashboard blank after scrolling on Honor 50 (GPU/driver
      // related paint drop). Full-width cards do not trigger it.
      return Column(children: [
        HeroAttendanceCard(
          rate: todayRate,
          onSite: onSite,
          totalWorkers: totalWorkers,
          present: present,
          late: late,
          absent: absent,
        ),
        const SizedBox(height: 12),
        CompactMetricCard(
          label: 'Active Tasks',
          value: '$activeTasks',
          sub: totalTasks > 0 ? '$completed done · $inProgress in progress' : null,
          icon: Icons.assignment_rounded,
          iconColor: AppColors.blue,
        ),
        const SizedBox(height: 12),
        CompactMetricCard(
          label: 'Overall Productivity',
          value: '$productivity%',
          sub: totalTasks > 0 ? '$completedPct% of tasks completed' : null,
          icon: Icons.trending_up_rounded,
          iconColor: AppColors.green,
          valueColor: AppColors.green,
        ),
      ]);
    });
  }
}

/// Hero attendance card: the single most important number on the page.
class HeroAttendanceCard extends StatelessWidget {
  final int rate;
  final int onSite;
  final int totalWorkers;
  final int present;
  final int late;
  final int absent;

  const HeroAttendanceCard({
    super.key,
    required this.rate,
    required this.onSite,
    required this.totalWorkers,
    required this.present,
    required this.late,
    required this.absent,
  });

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
        Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.accentLight,
              borderRadius: AppRadius.rSm,
            ),
            child: Icon(Icons.fact_check_rounded, size: 20, color: AppColors.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              AppStrings.t('dash.todayAttendanceRate'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                  fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(width: 12),
          Text('$rate%',
              style: GoogleFonts.inter(
                  fontSize: 30, fontWeight: FontWeight.w800, color: AppColors.accent)),
        ]),
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: AppRadius.rXs,
          child: LinearProgressIndicator(
            value: rate.clamp(0, 100) / 100,
            minHeight: 8,
            backgroundColor: AppColors.border,
            valueColor: AlwaysStoppedAnimation(AppColors.accent),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(spacing: 8, runSpacing: 8, children: [
          MetricChip('$onSite/$totalWorkers on site', AppColors.accent),
          MetricChip('$present present', AppColors.green),
          MetricChip('$late late', AppColors.yellow),
          MetricChip('$absent absent', AppColors.red),
        ]),
      ]),
    );
  }
}

/// Small coloured pill used inside the hero attendance card.
class MetricChip extends StatelessWidget {
  final String text;
  final Color color;

  const MetricChip(this.text, this.color, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppRadius.rLg,
      ),
      child: Text(text,
          style: GoogleFonts.inter(
              fontSize: 11.5, fontWeight: FontWeight.w600, color: color)),
    );
  }
}

/// Compact single-line metric card (icon + label/sub + value on the right).
class CompactMetricCard extends StatelessWidget {
  final String label;
  final String value;
  final String? sub;
  final IconData icon;
  final Color iconColor;
  final Color? valueColor;

  const CompactMetricCard({
    super.key,
    required this.label,
    required this.value,
    this.sub,
    required this.icon,
    required this.iconColor,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: AppRadius.rLg,
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.sm,
      ),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.10),
            borderRadius: AppRadius.rSm,
          ),
          child: Icon(icon, size: 18, color: iconColor),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                    fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
            if (sub != null) ...[
              const SizedBox(height: 4),
              Text(sub!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(fontSize: 11.5, color: AppColors.textMuted)),
            ],
          ]),
        ),
        const SizedBox(width: 12),
        Text(value,
            style: GoogleFonts.inter(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: valueColor ?? AppColors.textPrimary)),
      ]),
    );
  }
}

/// Square KPI card used by the wide-screen row.
class KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final String? sub;
  final IconData icon;
  final Color iconColor;
  final Color? valueColor;

  const KpiCard({
    super.key,
    required this.label,
    required this.value,
    this.sub,
    required this.icon,
    required this.iconColor,
    this.valueColor,
  });

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
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Text(label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.10), borderRadius: AppRadius.rSm),
            child: Icon(icon, size: 16, color: iconColor),
          ),
        ]),
        const SizedBox(height: 12),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value,
              style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w800, color: valueColor ?? AppColors.textPrimary)),
        ),
        if (sub != null) ...[
          const SizedBox(height: 4),
          Text(sub!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted)),
        ],
      ]),
    );
  }
}

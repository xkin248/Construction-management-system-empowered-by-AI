import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_helper.dart';

/// One row of the "Productivity Trend by Project" list.
class ProjectProductivityRow extends StatelessWidget {
  final Map project;

  const ProjectProductivityRow({super.key, required this.project});

  @override
  Widget build(BuildContext context) {
    final progress = (project['progress'] as num? ?? 0).toDouble();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: AppRadius.rMd,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Expanded(
            child: Text(project['project_name'] ?? '-',
                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700),
                overflow: TextOverflow.ellipsis),
          ),
          Text('${progress.toStringAsFixed(0)}%',
              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.accent)),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: AppRadius.rXs,
          child: LinearProgressIndicator(
            value: progress / 100,
            minHeight: 6,
            backgroundColor: AppColors.border,
            valueColor: AlwaysStoppedAnimation(AppColors.accent),
          ),
        ),
      ]),
    );
  }
}

/// Card for a project whose end date is within 30 days (or already overdue).
class UpcomingProjectCard extends StatelessWidget {
  final Map project;

  const UpcomingProjectCard({super.key, required this.project});

  static String formatDate(String iso) {
    final dt = DateTime.tryParse(iso);
    return dt == null ? iso : DateHelper.formatShort(dt);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final end = DateTime.tryParse((project['end_date'] as String?) ?? '');
    int daysLeft = 0;
    if (end != null) {
      final endDay = DateTime(end.year, end.month, end.day);
      daysLeft = endDay.difference(today).inDays;
    }
    final overdue = daysLeft < 0;
    final dueToday = daysLeft == 0;
    final label =
        overdue ? '${-daysLeft} day(s) overdue' : (dueToday ? 'Due today' : '$daysLeft day(s) left');
    final color = overdue ? AppColors.red : (dueToday ? AppColors.yellow : AppColors.green);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: AppRadius.rMd,
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: AppRadius.rSm),
          child: Icon(
              overdue
                  ? Icons.event_busy_rounded
                  : (dueToday ? Icons.event_available_rounded : Icons.event_rounded),
              size: 18,
              color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(project['project_name'] ?? '-',
                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700),
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text('Due: ${formatDate((project['end_date'] as String?) ?? '')}',
                style: GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted)),
          ]),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: AppRadius.rMd),
          child: Text(label, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
        ),
      ]),
    );
  }
}

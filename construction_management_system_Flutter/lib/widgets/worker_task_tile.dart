import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';
import '../utils/date_helper.dart';

/// Task card shown to a worker.
///
/// Extracted from the worker dashboard so both the dashboard (collapsed
/// section) and the standalone Tasks tab render the exact same card — one
/// implementation, no drifting copy. Visual language matches the supervisor
/// task list: section chip + status pill + priority chip + progress bar.
class WorkerTaskTile extends StatelessWidget {
  final Map<String, dynamic> task;
  final bool inGrid;
  final VoidCallback? onTap;

  const WorkerTaskTile({
    super.key,
    required this.task,
    this.inGrid = false,
    this.onTap,
  });

  Color _priorityColor(String? p) {
    switch (p?.toLowerCase()) {
      case 'high':
        return AppColors.red;
      case 'medium':
        return AppColors.yellow;
      case 'low':
        return AppColors.blue;
      default:
        return AppColors.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = task['status']?.toString() ?? 'Pending';
    final priority = task['priority']?.toString() ?? 'Medium';
    final part = task['part_section']?.toString() ?? 'General Section';
    final instructions = task['work_instructions']?.toString() ?? '';
    final projectName = task['project_name']?.toString() ?? '';
    final rawPct = task['progress'];
    final pct = rawPct is num
        ? rawPct.round().clamp(0, 100)
        : (status.toLowerCase().replaceAll(' ', '_') == 'completed'
            ? 100
            : (status.toLowerCase().replaceAll(' ', '_') == 'in_progress' ? 50 : 0));
    final sKey = status.toLowerCase().replaceAll(' ', '_');
    final barColor = sKey == 'completed'
        ? AppColors.green
        : sKey == 'in_progress'
            ? AppColors.blue
            : AppColors.yellow;

    return Padding(
      padding: inGrid ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Material(
        color: AppColors.bgCard,
        borderRadius: AppRadius.rMd,
        child: InkWell(
          borderRadius: AppRadius.rMd,
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: AppRadius.rMd,
              border: Border.all(color: AppColors.border),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: AppColors.accentLight, borderRadius: AppRadius.rMd),
                      child: Row(children: [
                        Icon(Icons.layers_rounded, size: 11, color: AppColors.accent),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(part,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                  color: AppColors.accent, fontSize: 14, fontWeight: FontWeight.w800)),
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(width: 8),
                  statusPill(status),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _priorityColor(priority).withValues(alpha: 0.18),
                      borderRadius: AppRadius.rMd,
                    ),
                    child: Text(priority.toUpperCase(),
                        style: GoogleFonts.inter(
                          color: _priorityColor(priority),
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                        )),
                  ),
                ]),
                const SizedBox(height: 8),
                Text(task['task_name']?.toString() ?? 'Unnamed Task',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                        fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                if (task['description']?.toString().isNotEmpty ?? false) ...[
                  const SizedBox(height: 4),
                  Text(task['description'].toString(),
                      style: GoogleFonts.inter(fontSize: 14, color: AppColors.textSecondary, height: 1.4)),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (projectName.isNotEmpty)
                      _miniTag(Icons.apartment_rounded, projectName, AppColors.blue),
                    if (task['due_date'] != null)
                      _miniTag(
                          Icons.event_rounded,
                          'Due: ${DateHelper.tryFormatShort(task['due_date'], fallback: task['due_date'].toString().substring(0, 10))}',
                          AppColors.textSecondary),
                  ],
                ),
                if (instructions.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.blueLight,
                      borderRadius: AppRadius.rMd,
                      border: Border.all(color: AppColors.blue.withValues(alpha: 0.3)),
                    ),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(Icons.lightbulb_circle_rounded, size: 16, color: AppColors.blue),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(instructions,
                            style: GoogleFonts.inter(
                                fontSize: 13, color: AppColors.blue, height: 1.4, fontWeight: FontWeight.w600)),
                      ),
                    ]),
                  ),
                ],
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: AppRadius.rSm,
                      child: LinearProgressIndicator(
                        value: pct / 100,
                        minHeight: 6,
                        backgroundColor: AppColors.border,
                        valueColor: AlwaysStoppedAnimation<Color>(barColor),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text('$pct%',
                      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w800, color: barColor)),
                  const SizedBox(width: 2),
                  Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.accent),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _miniTag(IconData icon, String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: AppRadius.rMd),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 10.5, color: color),
          const SizedBox(width: 3.5),
          Text(label,
              style: GoogleFonts.inter(color: color, fontSize: 14, fontWeight: FontWeight.w700)),
        ]),
      );
}

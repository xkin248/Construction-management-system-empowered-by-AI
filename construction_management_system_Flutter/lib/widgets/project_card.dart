import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../utils/date_helper.dart';

/// A single project card, extracted out of [ProjectsPage] so the lazy list can
/// rebuild only the affected card instead of the whole page's builder closure.
///
/// Visuals are byte-for-byte identical to the inline card that used to live in
/// `projects_page.dart`; only the callbacks are injected from the parent.
class ProjectCard extends StatelessWidget {
  const ProjectCard({
    super.key,
    required this.project,
    this.inGrid = false,
    required this.onOpen,
    required this.onEdit,
    this.onMarkComplete,
  });

  final Map project;
  final bool inGrid;
  final VoidCallback onOpen;
  final VoidCallback onEdit;

  /// Only invoked when the card shows the "mark complete" affordance.
  final VoidCallback? onMarkComplete;

  @override
  Widget build(BuildContext context) {
    final p = project;
    final progress = (p['progress'] as num? ?? 0).toDouble();
    final workerCount = p['worker_count'] ?? p['tracked_workers'] ?? 0;
    final radius = (p['fence_radius'] as num? ?? 5000).toInt();
    final status = p['status'] ?? 'planning';

    return sectionCard(
      margin: inGrid ? EdgeInsets.zero : const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: AppRadius.rLg,
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Expanded(
                child: Text(p['project_name'] ?? '-',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 15),
                    overflow: TextOverflow.ellipsis),
              ),
              Row(mainAxisSize: MainAxisSize.min, children: [
                statusPill(status),
                if (status != 'completed' && progress >= 100) ...[
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: onMarkComplete,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: AppColors.greenLight,
                        borderRadius: AppRadius.rSm,
                      ),
                      child: Icon(Icons.check_circle_rounded,
                          size: 14, color: AppColors.green),
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                // Edit button
                GestureDetector(
                  onTap: onEdit,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppColors.bgMain,
                      borderRadius: AppRadius.rSm,
                    ),
                    child: Icon(Icons.edit_outlined, size: 14, color: AppColors.textMuted),
                  ),
                ),
              ]),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              Icon(Icons.place_outlined, size: 13, color: AppColors.textMuted),
              const SizedBox(width: 4),
              Expanded(child: Text(p['location_address'] ?? '-',
                  style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 14),
                  overflow: TextOverflow.ellipsis)),
            ]),
            const SizedBox(height: 12),
            // Geofence badge
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: AppColors.greenLight, borderRadius: AppRadius.rMd),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.gps_fixed_rounded, size: 11, color: AppColors.green),
                  const SizedBox(width: 4),
                  Text('Geofence: ${radius}m radius',
                      style: GoogleFonts.inter(fontSize: 14, color: AppColors.green, fontWeight: FontWeight.w700)),
                ]),
              ),
              if (workerCount > 0) ...[
                const SizedBox(width: 12),
                Text('$workerCount workers tracked',
                    style: GoogleFonts.inter(fontSize: 13, color: AppColors.accent, fontWeight: FontWeight.w600)),
              ],
            ]),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: AppRadius.rMd,
              child: LinearProgressIndicator(
                value: progress / 100,
                minHeight: 7, backgroundColor: AppColors.border,
                valueColor: AlwaysStoppedAnimation(AppColors.green),
              ),
            ),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('${progress.toStringAsFixed(0)}% complete',
                  style: GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted)),
              if (p['end_date'] != null)
                Text('Due ${DateHelper.tryFormatShort(p['end_date'])}',
                    style: GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted)),
            ]),
          ]),
        ),
      ),
    );
  }
}

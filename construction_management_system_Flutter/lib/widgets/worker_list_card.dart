import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import 'a11y.dart';

/// A single worker row/card, extracted out of [WorkersPage] so the lazy list
/// only rebuilds the card whose data actually changed.
///
/// Layout, colours and typography mirror the previous inline builder exactly.
class WorkerListCard extends StatelessWidget {
  const WorkerListCard({
    super.key,
    required this.worker,
    this.inGrid = false,
    this.onTap,
  });

  final Map worker;
  final bool inGrid;
  final VoidCallback? onTap;

  static String _fmtTime(Object? iso) {
    if (iso == null) return '';
    try {
      final d = DateTime.parse(iso.toString()).toLocal();
      return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = worker;
    // Tapping a card opens the read-only worker profile (P1: cards previously
    // had no entry point at all).
    return semanticTapTarget(
      label: '${w['name'] ?? '-'}, ${w['today_status'] ?? 'absent'}',
      child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: sectionCard(
        margin: inGrid ? EdgeInsets.zero : const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          initialsAvatar(w['name'] ?? '?', radius: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(w['name'] ?? '-',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 14.5),
                    overflow: TextOverflow.ellipsis)),
                semanticStatus(statusPill(w['today_status'] ?? 'absent'), (w['today_status'] ?? 'absent').toString()),
              ]),
              const SizedBox(height: 4),
              Row(children: [
                Icon(Icons.handyman_outlined, size: 13, color: AppColors.textMuted),
                const SizedBox(width: 4),
                Expanded(child: Text(w['trade'] ?? 'General Worker',
                    style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 13.5),
                    overflow: TextOverflow.ellipsis)),
              ]),
              if (w['project'] != null) ...[
                const SizedBox(height: 4),
                Row(children: [
                  Icon(Icons.location_on_outlined, size: 13, color: AppColors.textMuted),
                  const SizedBox(width: 4),
                  Expanded(child: Text(w['project']['project_name'] ?? '',
                      style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 13),
                      overflow: TextOverflow.ellipsis)),
                ]),
              ],
              if (w['check_in_time'] != null || w['hours_today'] != null) ...[
                const SizedBox(height: 8),
                Row(children: [
                  Icon(Icons.schedule_rounded, size: 13, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Expanded(child: Text(
                    [
                      if (w['check_in_time'] != null) 'In ${_fmtTime(w['check_in_time'])}',
                      if (w['check_out_time'] != null) 'Out ${_fmtTime(w['check_out_time'])}',
                      if (w['hours_today'] != null) '${w['hours_today']}h',
                    ].join(' · '),
                    style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  )),
                ]),
              ],
            ]),
          ),
        ]),
      ),
    ));
  }
}

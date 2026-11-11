import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../l10n/app_strings.dart';

// ── Timeline helpers ────────────────────────────────────────────────────────

String fmtLogTime(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  final dt = DateTime.tryParse(iso)?.toLocal();
  if (dt == null) return iso;
  String two(int v) => v.toString().padLeft(2, '0');
  return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
      '${two(dt.hour)}:${two(dt.minute)}';
}

String statusLabel(String? s) {
  switch (s) {
    case 'completed':
      return AppStrings.t('tasks.completed');
    case 'in_progress':
      return AppStrings.t('tasks.inProgress');
    default:
      return AppStrings.t('tasks.pending');
  }
}

/// One row of the task timeline: from -> to status, optional note, timestamp.
class TimelineTile extends StatelessWidget {
  const TimelineTile({
    super.key,
    required this.entry,
    required this.isFirst,
  });

  final Map entry;
  final bool isFirst;

  @override
  Widget build(BuildContext context) {
    final from = entry['from_status'] as String?;
    final to = entry['to_status'] as String?;
    final note = entry['note'] as String?;
    final time = fmtLogTime(entry['created_at'] as String?);
    final unchanged = from != null && from == to;

    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Dot + connector line
        SizedBox(
          width: 24,
          child: Column(children: [
            Container(
              width: 10, height: 10,
              margin: const EdgeInsets.only(top: 5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: to == 'completed' ? AppColors.green : AppColors.blue,
              ),
            ),
            if (!isFirst)
              Expanded(child: Container(width: 2, color: AppColors.border)),
          ]),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: isFirst ? 0 : 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text(
                    unchanged
                        ? AppStrings.t('tasks.noChange')
                        : '${statusLabel(from)} → ${statusLabel(to)}',
                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Spacer(),
                Text(time,
                    style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted)),
              ]),
              if (note != null && note.trim().isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(note,
                    style: GoogleFonts.inter(fontSize: 12.5, color: AppColors.textSecondary)),
              ],
            ]),
          ),
        ),
      ]),
    );
  }
}

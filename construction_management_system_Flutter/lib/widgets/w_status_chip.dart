import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';
import 'worker_ui.dart';

/// Canonical worker-visible status states.
///
/// Spec A5 / A7: a worker must never have to read a colour to know where a task
/// stands — every state is rendered as icon + word (colour is only a second cue).
enum WStatus { pending, inProgress, submitted, approved, rejected }

/// Maps any backend status string onto the five worker-facing states.
/// Unknown values fall back to [WStatus.pending] so the UI never shows a blank.
WStatus wStatusOf(dynamic raw) {
  switch (wStatusKey(raw)) {
    case 'in_progress':
    case 'inprogress':
    case 'working':
    case 'started':
      return WStatus.inProgress;
    case 'submitted':
    case 'pending_review':
    case 'review':
      return WStatus.submitted;
    case 'approved':
    case 'completed':
    case 'done':
    case 'verified':
      return WStatus.approved;
    case 'rejected':
    case 'declined':
    case 'redo':
      return WStatus.rejected;
    case 'pending':
    case 'new':
    case 'not_started':
    default:
      return WStatus.pending;
  }
}

IconData wStatusGlyph(WStatus s) {
  switch (s) {
    case WStatus.pending:
      return Icons.schedule_rounded;
    case WStatus.inProgress:
      return Icons.play_circle_fill_rounded;
    case WStatus.submitted:
      return Icons.upload_file_rounded;
    case WStatus.approved:
      return Icons.verified_rounded;
    case WStatus.rejected:
      return Icons.cancel_rounded;
  }
}

Color wStatusTint(WStatus s) {
  switch (s) {
    case WStatus.pending:
      return AppColors.yellow;
    case WStatus.inProgress:
      return AppColors.blue;
    case WStatus.submitted:
      return AppColors.purple;
    case WStatus.approved:
      return AppColors.green;
    case WStatus.rejected:
      return AppColors.red;
  }
}

/// Short status word — max two words in every language (low-literacy rule).
String wStatusWord(WStatus s) {
  switch (s) {
    case WStatus.pending:
      return wT(en: 'Pending', ms: 'Menunggu', zh: '待开始');
    case WStatus.inProgress:
      return wT(en: 'In Progress', ms: 'Sedang Kerja', zh: '进行中');
    case WStatus.submitted:
      return wT(en: 'Submitted', ms: 'Dihantar', zh: '已提交');
    case WStatus.approved:
      return wT(en: 'Approved', ms: 'Diluluskan', zh: '已通过');
    case WStatus.rejected:
      return wT(en: 'Rejected', ms: 'Ditolak', zh: '已退回');
  }
}

/// Icon + word pill. Used by task cards (A5), task details (A6) and
/// common-task cards (A7) so the vocabulary stays identical everywhere.
class WStatusChip extends StatelessWidget {
  final dynamic status;
  final bool compact;

  const WStatusChip({super.key, required this.status, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final s = wStatusOf(status);
    final tint = wStatusTint(s);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 12, vertical: compact ? 5 : 7),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.14),
        borderRadius: AppRadius.rPill,
        border: Border.all(color: tint.withValues(alpha: 0.45)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(wStatusGlyph(s), size: compact ? 16 : 18, color: tint),
        const SizedBox(width: 6),
        Text(
          wStatusWord(s),
          style: GoogleFonts.inter(
            fontSize: compact ? 13 : 14,
            fontWeight: FontWeight.w800,
            color: tint,
          ),
        ),
      ]),
    );
  }
}

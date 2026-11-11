import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';
import 'w_status_chip.dart';
import 'worker_ui.dart';

/// Common-task tile (spec A7).
///
/// The status is always icon + word — `done` is only used for the tint and for
/// blocking taps, never as the sole carrier of meaning.
class WCommonTaskCard extends StatelessWidget {
  final String kind;
  final bool done;
  final bool busy;

  /// Backend status string when the caller knows it (pending / in_progress /
  /// submitted / approved / rejected). Falls back to a value derived from
  /// [done] and [busy].
  final String? status;

  final VoidCallback? onTap;

  const WCommonTaskCard({
    super.key,
    required this.kind,
    required this.done,
    this.busy = false,
    this.status,
    this.onTap,
  });

  IconData get _icon {
    switch (kind) {
      case 'briefing':
        return Icons.groups_rounded;
      case 'toolbox':
        return Icons.handyman_rounded;
      case 'housekeeping':
        return Icons.cleaning_services_rounded;
      default:
        return Icons.assignment_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final effective = (status != null && status!.isNotEmpty)
        ? status!
        : (done ? 'approved' : (busy ? 'in_progress' : 'pending'));
    final s = wStatusOf(effective);
    final tint = wStatusTint(s);
    final tappable = onTap != null && !done && !busy;

    return Material(
      color: done ? AppColors.green.withValues(alpha: 0.10) : AppColors.bgCard,
      borderRadius: AppRadius.rLg,
      child: InkWell(
        borderRadius: AppRadius.rLg,
        onTap: tappable ? onTap : null,
        child: Container(
          constraints: const BoxConstraints(minHeight: 96),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: AppRadius.rLg,
            border: Border.all(
              color: done ? AppColors.green : (busy ? tint : AppColors.border),
              width: done ? 2 : 1,
            ),
          ),
          child: Row(children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(color: tint.withValues(alpha: 0.14), shape: BoxShape.circle),
              child: Icon(_icon, size: 28, color: tint),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  wCommonTaskTitle(kind),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                      fontSize: 19, fontWeight: FontWeight.w900, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  wCommonTaskHint(kind),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(fontSize: 14, color: AppColors.textMuted),
                ),
              ]),
            ),
            const SizedBox(width: 8),
            if (busy)
              const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(strokeWidth: 3),
              )
            else
              WStatusChip(status: effective, compact: true),
          ]),
        ),
      ),
    );
  }
}

IconData wCommonTaskIcon(String kind) {
  switch (kind) {
    case 'briefing':
      return Icons.groups_rounded;
    case 'toolbox':
      return Icons.handyman_rounded;
    case 'housekeeping':
      return Icons.cleaning_services_rounded;
    default:
      return Icons.assignment_rounded;
  }
}

String wCommonTaskTitle(String kind) {
  switch (kind) {
    case 'briefing':
      return wT(en: 'BRIEFING', ms: 'BRIEFING', zh: '早会简报');
    case 'toolbox':
      return wT(en: 'TOOLBOX', ms: 'TOOLBOX', zh: '工具领用');
    case 'housekeeping':
      return wT(en: 'CLEAN UP', ms: 'KEMAS', zh: '场地清理');
    default:
      return wT(en: 'JOB', ms: 'KERJA', zh: '任务');
  }
}

String wCommonTaskHint(String kind) {
  switch (kind) {
    case 'briefing':
      return wT(en: 'Safety talk', ms: 'Taklimat pagi', zh: '安全交底');
    case 'toolbox':
      return wT(en: 'Take & return', ms: 'Ambil & pulang', zh: '领取与归还');
    case 'housekeeping':
      return wT(en: 'Clean the site', ms: 'Kemas tapak', zh: '清理现场');
    default:
      return '';
  }
}

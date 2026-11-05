import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';
import 'worker_ui.dart';

/// Icon for one of the three daily jobs. One glyph per job so the card can be
/// recognised without reading the word underneath.
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

/// Short name of a daily job (max two words in every language).
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

/// One line that says what the job actually is, for the worker who can read a
/// little but not the site paperwork.
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

/// Large square card for one daily job.
///
/// A finished job is not shown by a ticked checkbox in small print: the whole
/// card turns green, the icon becomes a check and the tap is disabled, so the
/// "already done" state is readable at arm's length in the sun.
class WCommonTaskCard extends StatelessWidget {
  final String kind;
  final bool done;
  final bool busy;
  final VoidCallback? onTap;

  const WCommonTaskCard({
    super.key,
    required this.kind,
    required this.done,
    this.busy = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = done ? AppColors.green : AppColors.accent;
    final title = wCommonTaskTitle(kind);
    final hint = wCommonTaskHint(kind);

    return Material(
      color: done ? AppColors.greenLight : AppColors.bgCard,
      borderRadius: AppRadius.rLg,
      child: InkWell(
        borderRadius: AppRadius.rLg,
        onTap: done || busy ? null : onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 96),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: AppRadius.rLg,
            border: Border.all(
              color: done ? color : AppColors.border,
              width: done ? 2 : 1,
            ),
          ),
          child: Row(children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color.withValues(alpha: done ? 0.18 : 0.14),
                shape: BoxShape.circle,
              ),
              child: busy
                  ? Padding(
                      padding: const EdgeInsets.all(14),
                      child: CircularProgressIndicator(strokeWidth: 3, color: color),
                    )
                  : Icon(
                      done ? Icons.check_rounded : wCommonTaskIcon(kind),
                      size: 32,
                      color: color,
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (hint.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      hint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (done)
              Text(
                wT(en: 'DONE', ms: 'SIAP', zh: '已完成'),
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              )
            else
              Icon(Icons.chevron_right_rounded, size: 30, color: AppColors.textMuted),
            const SizedBox(width: 4),
          ]),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/app_settings.dart';
import '../theme/app_theme.dart';

/// Trilingual copy helper for the worker side (en / ms / zh).
///
/// Named arguments on purpose: [AppSettings.t] takes positional
/// (en, zh, ms), which is easy to get wrong — that mistake already produced
/// English-only screens once. Worker screens default to Bahasa Melayu.
String wT({required String en, required String ms, required String zh}) =>
    AppSettings.t(en, zh, ms);

/// Minimum tap height for a primary worker action (Material guidance is 48dp;
/// gloves + sunlight + low literacy need the extra room).
const double kWPrimaryTap = 72;

/// Minimum tap height for a list row.
const double kWRowTap = 72;

String wStatusKey(dynamic status) =>
    (status?.toString() ?? 'pending').toLowerCase().replaceAll(' ', '_');

Color wStatusColor(dynamic status) {
  switch (wStatusKey(status)) {
    case 'completed':
      return AppColors.green;
    case 'in_progress':
      return AppColors.blue;
    default:
      return AppColors.yellow;
  }
}

IconData wStatusIcon(dynamic status) {
  switch (wStatusKey(status)) {
    case 'completed':
      return Icons.check_rounded;
    case 'in_progress':
      return Icons.play_arrow_rounded;
    default:
      return Icons.flag_rounded;
  }
}

/// Short, icon-backed status word (max three words in every language).
String wStatusLabel(dynamic status) {
  switch (wStatusKey(status)) {
    case 'completed':
      return wT(en: 'DONE', ms: 'SIAP', zh: '已完成');
    case 'in_progress':
      return wT(en: 'WORKING', ms: 'KERJA', zh: '进行中');
    default:
      return wT(en: 'NEW', ms: 'BARU', zh: '待开始');
  }
}

int wProgress(Map<String, dynamic> task) {
  final raw = task['progress'];
  if (raw is num) return raw.round().clamp(0, 100);
  final s = wStatusKey(task['status']);
  if (s == 'completed') return 100;
  if (s == 'in_progress') return 50;
  return 0;
}

/// Full-width primary action: one icon, one short word, one colour.
class WBigAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final bool busy;
  final bool outlined;
  final double height;

  const WBigAction({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
    this.busy = false,
    this.outlined = false,
    this.height = 88,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null && !busy;
    final fg = outlined ? color : AppColors.onAccent;
    final child = SizedBox(
      height: height,
      child: Center(
        child: busy
            ? Row(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(strokeWidth: 3, color: fg),
                ),
                const SizedBox(width: 14),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                        fontSize: 20, fontWeight: FontWeight.w900, color: fg),
                  ),
                ),
              ])
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(icon, size: 34, color: fg),
                    const SizedBox(width: 12),
                    Text(
                      label,
                      maxLines: 1,
                      style: GoogleFonts.inter(
                          fontSize: 22, fontWeight: FontWeight.w900, color: fg, letterSpacing: 0.4),
                    ),
                  ]),
                ),
              ),
      ),
    );

    return Opacity(
      opacity: enabled || busy ? 1 : 0.55,
      child: Material(
        color: outlined ? Colors.transparent : color,
        borderRadius: AppRadius.rLg,
        child: InkWell(
          borderRadius: AppRadius.rLg,
          onTap: enabled ? onTap : null,
          child: Container(
            decoration: outlined
                ? BoxDecoration(
                    borderRadius: AppRadius.rLg,
                    border: Border.all(color: color.withValues(alpha: 0.55), width: 2),
                  )
                : null,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Small icon + word chip used for status detail (time, GPS, hours).
class WChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const WChip({super.key, required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppRadius.rMd,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 17, color: color),
        const SizedBox(width: 6),
        Text(label,
            style: GoogleFonts.inter(
                fontSize: 16, fontWeight: FontWeight.w800, color: color)),
      ]),
    );
  }
}

/// One big number with a word underneath — the only "statistics" a worker sees.
class WNumberTile extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const WNumberTile({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: AppRadius.rMd,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.14), shape: BoxShape.circle),
          child: Icon(icon, size: 24, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(fontSize: 30, fontWeight: FontWeight.w900, color: color)),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                    fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
          ]),
        ),
      ]),
    );
  }
}

/// One task row: colour bar + icon + task name + one big number.
class WTaskRow extends StatelessWidget {
  final Map<String, dynamic> task;
  final VoidCallback? onTap;

  const WTaskRow({super.key, required this.task, this.onTap});

  @override
  Widget build(BuildContext context) {
    final status = task['status'];
    final color = wStatusColor(status);
    final pct = wProgress(task);
    final name = (task['task_name'] ?? task['name'] ?? '').toString();

    return Material(
      color: AppColors.bgCard,
      borderRadius: AppRadius.rMd,
      child: InkWell(
        borderRadius: AppRadius.rMd,
        onTap: onTap,
        child: Container(
          height: kWRowTap,
          decoration: BoxDecoration(
            borderRadius: AppRadius.rMd,
            border: Border.all(color: AppColors.border),
          ),
          child: Row(children: [
            Container(
              width: 8,
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(10)),
              ),
            ),
            const SizedBox(width: 10),
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.14), shape: BoxShape.circle),
              child: Icon(wStatusIcon(status), size: 24, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                name.isEmpty ? wT(en: 'Task', ms: 'Tugasan', zh: '任务') : name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                    fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
              ),
            ),
            const SizedBox(width: 8),
            Text('$pct%',
                style: GoogleFonts.inter(
                    fontSize: 24, fontWeight: FontWeight.w900, color: color)),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right_rounded, size: 24, color: AppColors.textMuted),
            const SizedBox(width: 8),
          ]),
        ),
      ),
    );
  }
}

/// Error = icon + one sentence + what to do.
class WErrorHint extends StatelessWidget {
  final String title;
  final String hint;
  final VoidCallback? onRetry;
  final String? retryLabel;

  const WErrorHint({
    super.key,
    required this.title,
    required this.hint,
    this.onRetry,
    this.retryLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.redLight,
        borderRadius: AppRadius.rMd,
        border: Border.all(color: AppColors.red.withValues(alpha: 0.4)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.warning_amber_rounded, size: 30, color: AppColors.red),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: GoogleFonts.inter(
                    fontSize: 17, fontWeight: FontWeight.w900, color: AppColors.textPrimary)),
            const SizedBox(height: 2),
            Text(hint,
                style: GoogleFonts.inter(
                    fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textSecondary, height: 1.3)),
            if (onRetry != null) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: kWPrimaryTap,
                child: ElevatedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 26),
                  label: Text(retryLabel ?? wT(en: 'TRY AGAIN', ms: 'CUBA LAGI', zh: '再试一次'),
                      style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w900)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.red,
                    foregroundColor: AppColors.onAccent,
                    elevation: 0,
                    minimumSize: const Size.fromHeight(kWPrimaryTap),
                    shape: RoundedRectangleBorder(borderRadius: AppRadius.rMd),
                  ),
                ),
              ),
            ],
          ]),
        ),
      ]),
    );
  }
}

/// Empty block: one icon, one line, one big button.
class WEmpty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? actionLabel;
  final IconData actionIcon;
  final VoidCallback? onAction;

  const WEmpty({
    super.key,
    required this.icon,
    required this.title,
    this.actionLabel,
    this.actionIcon = Icons.refresh_rounded,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      const SizedBox(height: 16),
      Icon(icon, size: 60, color: AppColors.textMuted),
      const SizedBox(height: 12),
      Text(title,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
              fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.textSecondary)),
      const SizedBox(height: 16),
      if (actionLabel != null && onAction != null)
        WBigAction(
          icon: actionIcon,
          label: actionLabel!,
          color: AppColors.accent,
          height: kWPrimaryTap,
          onTap: onAction,
        ),
      const SizedBox(height: 8),
    ]);
  }
}

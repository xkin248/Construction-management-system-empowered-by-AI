import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../l10n/app_strings.dart';

// ── Worker tile used in the assign bottom sheet ──
class WorkerTile extends StatelessWidget {
  final Map worker;
  final bool selected;
  final VoidCallback onToggle;
  const WorkerTile({
    super.key,
    required this.worker,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final name = worker['name'] as String? ?? '?';
    final trade = worker['trade'] as String? ?? AppStrings.t('tasks.generalWorker');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgMain,
        borderRadius: AppRadius.rMd,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(children: [
        Row(children: [
          initialsAvatar(name, radius: 20),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(name, style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14), overflow: TextOverflow.ellipsis)),
            ]),
            Text(trade, style: GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted)),
          ])),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: onToggle,
            style: ElevatedButton.styleFrom(
              backgroundColor: selected ? AppColors.green : AppColors.accent,
              foregroundColor: AppColors.accentInk,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: AppRadius.rMd),
              minimumSize: const Size(70, 36),
            ),
            child: Text(selected ? '✓' : AppStrings.t('common.add'), style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700)),
          ),
        ]),
      ]),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_theme.dart';

/// Small "Demo Data" marker (spec PART F: sample records must be labelled so a
/// supervisor never mistakes them for real site data).
///
/// The backend seed distinguishes its sample rows only by their names, so the
/// badge is driven by [isDemoValue] rather than by a database flag.
class DemoDataBadge extends StatelessWidget {
  const DemoDataBadge({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 8, vertical: compact ? 2 : 3),
      decoration: BoxDecoration(
        color: AppColors.yellowLight,
        borderRadius: AppRadius.rSm,
        border: Border.all(color: AppColors.yellow.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.science_outlined, size: compact ? 10 : 12, color: AppColors.yellow),
          const SizedBox(width: 4),
          Text(
            'Demo Data',
            style: GoogleFonts.inter(
              fontSize: compact ? 9.5 : 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
              color: AppColors.yellow,
            ),
          ),
        ],
      ),
    );
  }
}

/// `true` when any of [keys] carries a name that the seed data uses for its
/// samples ("demo"/"test"/"sample"). Real records never contain those tokens.
bool looksLikeDemo(Map row, List<String> keys) {
  for (final k in keys) {
    if (isDemoValue(row[k]?.toString())) return true;
  }
  return false;
}

bool isDemoValue(String? value) {
  if (value == null || value.isEmpty) return false;
  final v = value.toLowerCase();
  return v.contains('demo') || v.contains('sample') || v.contains('dummy') || v == 'test' || v.contains('test ');
}

/// Badge for a single record, empty when the record is not sample data.
Widget demoBadgeFor(Map row, List<String> keys, {bool compact = true}) =>
    looksLikeDemo(row, keys)
        ? Padding(
            padding: const EdgeInsets.only(left: 6),
            child: DemoDataBadge(compact: compact),
          )
        : const SizedBox.shrink();

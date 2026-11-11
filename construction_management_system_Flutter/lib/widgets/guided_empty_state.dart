import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';

/// Beginner-friendly empty state used by every list page.
///
/// Structure: icon + one-line headline + one-sentence explanation + a single
/// primary action button (plus optional low-emphasis hint). Keeps new users on
/// a clear "what do I do next" path instead of a bare "No data" text.
class GuidedEmptyState extends StatelessWidget {
  /// Leading glyph inside a soft circular plate.
  final IconData icon;

  /// Headline, e.g. "No projects yet".
  final String title;

  /// One sentence that explains what this page holds and why to start.
  final String description;

  /// Label of the primary action. When null the button is hidden.
  final String? primaryLabel;

  /// Icon of the primary action button.
  final IconData primaryIcon;

  /// Tap handler of the primary action.
  final VoidCallback? onPrimary;

  /// Optional low-emphasis helper line shown under the button.
  final String? secondaryHint;

  /// Dense variant for use *inside* a card / list section (no Center, no
  /// scroll view, smaller plate) — otherwise the widget would demand infinite
  /// height inside an unbounded parent.
  final bool compact;

  const GuidedEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.primaryLabel,
    this.primaryIcon = Icons.add_rounded,
    this.onPrimary,
    this.secondaryHint,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final plate = compact ? 56.0 : 80.0;
    final content = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: plate,
            height: plate,
            decoration: BoxDecoration(
              color: AppColors.accentLight,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: compact ? 26 : 34, color: AppColors.accent),
          ),
          SizedBox(height: compact ? 12 : 20),
          Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: compact ? 14 : 16,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: compact ? 12.5 : 13,
              height: 1.5,
              color: AppColors.textSecondary,
            ),
          ),
          if (primaryLabel != null && onPrimary != null) ...[
            SizedBox(height: compact ? 14 : 20),
            ElevatedButton.icon(
              onPressed: onPrimary,
              icon: Icon(primaryIcon, size: compact ? 16 : 18),
              label: Text(
                primaryLabel!,
                style: GoogleFonts.inter(
                    fontSize: compact ? 12.5 : 13.5, fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.accentInk,
                elevation: 0,
                padding: EdgeInsets.symmetric(horizontal: compact ? 16 : 22, vertical: compact ? 11 : 14),
                shape: RoundedRectangleBorder(borderRadius: AppRadius.rSm),
              ),
            ),
          ],
          if (secondaryHint != null) ...[
            const SizedBox(height: 12),
            Text(
              secondaryHint!,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted),
            ),
          ],
        ],
      ),
    );

    if (compact) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(child: content),
      );
    }
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: content,
      ),
    );
  }
}

/// Empty state shown when a filter / search hides every row.
///
/// Same visual language as [GuidedEmptyState] but the action clears the filter
/// instead of creating data.
class FilteredEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final String clearLabel;
  final VoidCallback onClear;

  const FilteredEmptyState({
    super.key,
    this.icon = Icons.search_off_rounded,
    required this.title,
    required this.description,
    required this.clearLabel,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return GuidedEmptyState(
      icon: icon,
      title: title,
      description: description,
      primaryLabel: clearLabel,
      primaryIcon: Icons.filter_alt_off_rounded,
      onPrimary: onClear,
    );
  }
}

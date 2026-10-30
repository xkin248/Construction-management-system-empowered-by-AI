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

  const GuidedEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.primaryLabel,
    this.primaryIcon = Icons.add_rounded,
    this.onPrimary,
    this.secondaryHint,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppColors.accentLight,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 34, color: AppColors.accent),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                description,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  height: 1.5,
                  color: AppColors.textSecondary,
                ),
              ),
              if (primaryLabel != null && onPrimary != null) ...[
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: onPrimary,
                  icon: Icon(primaryIcon, size: 18),
                  label: Text(
                    primaryLabel!,
                    style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w700),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.accentInk,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
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
        ),
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

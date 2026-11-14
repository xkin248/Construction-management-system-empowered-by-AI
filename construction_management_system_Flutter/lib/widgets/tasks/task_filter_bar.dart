import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../l10n/app_strings.dart';

/// Search field + status segments + priority/project filter dropdowns of the
/// tasks list.
///
/// Purely presentational: the owning page keeps the filter values and receives
/// every change through the callbacks below.
///
/// Status is a segmented control (All / Pending / In Progress / Completed /
/// Overdue) because it is the filter supervisors touch most — a dropdown would
/// hide the counts of the other buckets. Priority and project stay dropdowns.
class TaskFilterBar extends StatelessWidget {
  final ValueChanged<String> onSearchChanged;
  final String statusFilter;
  final ValueChanged<String> onStatusChanged;
  final String priorityFilter;
  final ValueChanged<String> onPriorityChanged;
  final List projects;
  final int? selectedProjectId;
  final ValueChanged<int?> onProjectChanged;

  /// Optional per-segment counters (e.g. {'Overdue': 3}). Rendered as a small
  /// pill next to the label so the supervisor sees problem areas at a glance.
  final Map<String, int>? counts;

  const TaskFilterBar({
    super.key,
    required this.onSearchChanged,
    required this.statusFilter,
    required this.onStatusChanged,
    required this.priorityFilter,
    required this.onPriorityChanged,
    required this.projects,
    required this.selectedProjectId,
    required this.onProjectChanged,
    this.counts,
  });

  /// Filter values stay English (they drive the where-clause); only the labels
  /// are translated through [displayOf].
  static const statusSegments = [
    'All',
    'Pending',
    'In Progress',
    'Awaiting Review',
    'Completed',
    'Overdue',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // ── Search ──
      SizedBox(
        height: 46,
        child: TextField(
          onChanged: onSearchChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: AppStrings.t('tasks.searchHint'),
            hintStyle:
                GoogleFonts.inter(fontSize: 13.5, color: AppColors.textMuted),
            prefixIcon: Icon(Icons.search_rounded,
                size: 20, color: AppColors.textMuted),
            filled: true,
            fillColor: AppColors.bgCard,
            contentPadding: const EdgeInsets.symmetric(vertical: 0),
            border: OutlineInputBorder(
                borderRadius: AppRadius.rMd,
                borderSide: BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(
                borderRadius: AppRadius.rMd,
                borderSide: BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(
                borderRadius: AppRadius.rMd,
                borderSide: BorderSide(color: AppColors.accent, width: 1.4)),
          ),
        ),
      ),
      const SizedBox(height: 10),

      // ── Status segments ──
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final s in statusSegments) ...[
            _statusChip(s),
            const SizedBox(width: 8),
          ],
        ]),
      ),
      const SizedBox(height: 10),

      // ── Priority + project ──
      Wrap(spacing: 8, runSpacing: 8, children: [
        _dropdown(context, ['All', 'Low', 'Medium', 'High'], priorityFilter,
            (v) => onPriorityChanged(v!), AppStrings.t('tasks.priority')),
        if (projects.length > 1)
          _dropdown(
            context,
            projects.map<String>((p) => p['project_name'] as String).toList()
              ..insert(0, 'All'),
            selectedProjectId == null
                ? 'All'
                : (projects
                        .where((p) => p['project_id'] == selectedProjectId)
                        .isEmpty
                    ? 'All'
                    : projects.firstWhere((p) =>
                        p['project_id'] ==
                        selectedProjectId)['project_name'] as String),
            (v) {
              if (v == 'All') {
                onProjectChanged(null);
              } else {
                final found = projects.firstWhere((p) => p['project_name'] == v,
                    orElse: () => null);
                if (found != null) onProjectChanged(found['project_id']);
              }
            },
            AppStrings.t('tasks.projectLabel'),
          ),
      ]),
    ]);
  }

  Widget _statusChip(String s) {
    final active = s == statusFilter;
    final n = counts?[s];
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onStatusChanged(s),
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: active ? AppColors.navy : AppColors.bgCard,
            borderRadius: BorderRadius.circular(999),
            border:
                Border.all(color: active ? AppColors.navy : AppColors.border),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            // Overdue uses red so a non-zero count stands out even unselected.
            if (s == 'Overdue' && !active) ...[
              Icon(Icons.error_outline_rounded,
                  size: 14, color: AppColors.danger),
              const SizedBox(width: 5),
            ],
            Text(
              displayOf(s),
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                color: active ? Colors.white : AppColors.textSecondary,
              ),
            ),
            if (n != null && n > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: active
                      ? Colors.white.withValues(alpha: 0.24)
                      : AppColors.bgMain,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text('$n',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: active
                          ? Colors.white
                          : (s == 'Overdue'
                              ? AppColors.danger
                              : AppColors.textMuted),
                    )),
              ),
            ],
          ]),
        ),
      ),
    );
  }

  /// Localised display for status / priority filter values.
  /// The internal filter value stays in English so the filter logic is untouched.
  static String displayOf(String s) {
    switch (s) {
      case 'All':
        return AppStrings.t('common.all');
      case 'In Progress':
        return AppStrings.t('tasks.inProgress');
      case 'Completed':
        return AppStrings.t('tasks.completed');
      case 'Pending':
        return AppStrings.t('tasks.pending');
      case 'Overdue':
        return AppStrings.t('tasks.overdue');
      case 'High':
        return AppStrings.t('tasks.high');
      case 'Medium':
        return AppStrings.t('tasks.medium');
      case 'Low':
        return AppStrings.t('tasks.low');
      default:
        return s;
    }
  }

  Widget _dropdown(
    BuildContext context,
    List<String> items,
    String value,
    ValueChanged<String?> onChanged,
    String hint,
  ) {
    final v = items.contains(value) ? value : items.first;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      height: 42,
      width: 180,
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: AppRadius.rMd,
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButton<String>(
        value: v,
        underline: const SizedBox(),
        isExpanded: true,
        icon: Icon(Icons.keyboard_arrow_down_rounded,
            size: 18, color: AppColors.textMuted),
        style: GoogleFonts.inter(
            fontSize: 13.5,
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600),
        items: items
            .map((s) => DropdownMenuItem(
                  value: s,
                  child: Text('$hint: ${displayOf(s)}',
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                          fontSize: 13.5,
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600)),
                ))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }
}

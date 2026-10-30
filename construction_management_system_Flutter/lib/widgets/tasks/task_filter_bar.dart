import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../l10n/app_strings.dart';

/// Search field + status/priority/project filter dropdowns of the tasks list.
///
/// Purely presentational: the owning page keeps the filter values and receives
/// every change through the callbacks below.
class TaskFilterBar extends StatelessWidget {
  final ValueChanged<String> onSearchChanged;
  final String statusFilter;
  final ValueChanged<String> onStatusChanged;
  final String priorityFilter;
  final ValueChanged<String> onPriorityChanged;
  final List projects;
  final int? selectedProjectId;
  final ValueChanged<int?> onProjectChanged;

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
  });

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // Full-width search
      SizedBox(
        height: 44,
        child: TextField(
          onChanged: onSearchChanged,
          decoration: InputDecoration(
            hintText: 'Search tasks...',
            hintStyle: GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted),
            prefixIcon: Icon(Icons.search_rounded, size: 20, color: AppColors.textMuted),
            filled: true, fillColor: AppColors.bgCard,
            contentPadding: const EdgeInsets.symmetric(vertical: 0),
            border: OutlineInputBorder(borderRadius: AppRadius.rMd, borderSide: BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(borderRadius: AppRadius.rMd, borderSide: BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(borderRadius: AppRadius.rMd, borderSide: BorderSide(color: AppColors.accent)),
          ),
        ),
      ),
      const SizedBox(height: 8),
      // Filter chips row
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          _dropdown(context, ['All', 'In Progress', 'Completed', 'Pending'], statusFilter, (v) => onStatusChanged(v!), AppStrings.t('tasks.statusLabel')),
          const SizedBox(width: 8),
          _dropdown(context, ['All', 'Low', 'Medium', 'High'], priorityFilter, (v) => onPriorityChanged(v!), AppStrings.t('tasks.priority')),
          if (projects.length > 1) ...[
            const SizedBox(width: 8),
            _dropdown(
              context,
              projects.map<String>((p) => p['project_name'] as String).toList()..insert(0, 'All'),
              selectedProjectId == null
                  ? 'All'
                  : (projects.where((p) => p['project_id'] == selectedProjectId).isEmpty
                      ? 'All'
                      : projects.firstWhere((p) => p['project_id'] == selectedProjectId)['project_name'] as String),
              (v) {
                if (v == 'All') {
                  onProjectChanged(null);
                } else {
                  final found = projects.firstWhere((p) => p['project_name'] == v, orElse: () => null);
                  if (found != null) onProjectChanged(found['project_id']);
                }
              },
              AppStrings.t('tasks.projectLabel'),
            ),
          ],
        ]),
      ),
    ]);
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
      height: 48,
      width: 172,
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: AppRadius.rMd,
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButton<String>(
        value: v,
        underline: const SizedBox(),
        isExpanded: true,
        style: GoogleFonts.inter(fontSize: 14, color: AppColors.textPrimary, fontWeight: FontWeight.w600),
        items: items.map((s) => DropdownMenuItem(value: s, child: Text('$hint: ${displayOf(s)}'))).toList(),
        onChanged: onChanged,
      ),
    );
  }
}

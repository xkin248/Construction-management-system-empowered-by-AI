import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../l10n/app_strings.dart';
import '../services/api_service.dart';
import '../services/app_settings.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';
import '../widgets/guided_empty_state.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/failure_state.dart';
import '../widgets/worker_task_tile.dart';
import '../widgets/app_scrollbar.dart';
import 'worker_task_detail_page.dart';

/// Dedicated "Tasks" tab for the worker shell.
///
/// The dashboard only previews today's work; this page is the full list, so the
/// bottom navigation finally has a direct task entry (previously it lived
/// buried inside the dashboard card).
class WorkerTasksPage extends StatefulWidget {
  const WorkerTasksPage({super.key});

  @override
  State<WorkerTasksPage> createState() => _WorkerTasksPageState();
}

class _WorkerTasksPageState extends State<WorkerTasksPage> {
  /// Drives the always-available scrollbar of the task list.
  final ScrollController _scrollCtrl = ScrollController();

  bool _loading = true;
  bool _failed = false;
  List _tasks = [];
  String _lastUpdated = '';
  String _error = '';

  @override
  void initState() {
    super.initState();
    AppColors.darkMode.addListener(_rebuild);
    AppSettings.lang.addListener(_rebuild);
    _load();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    AppColors.darkMode.removeListener(_rebuild);
    AppSettings.lang.removeListener(_rebuild);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final r = await ApiService().workerTaskBoard(refresh: true);
      if (!mounted) return;
      setState(() {
        _tasks = (r['tasks'] as List?) ?? [];
        _lastUpdated = r['last_updated']?.toString() ?? '';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _openTask(Map<String, dynamic> task) async {
    final id = task['task_id'] ?? task['id'];
    final taskId = id is int ? id : int.tryParse(id?.toString() ?? '');
    if (taskId == null) {
      toast('Task id missing — cannot open details');
      return;
    }
    var changed = false;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => WorkerTaskDetailPage(
        taskId: taskId,
        initial: task,
        onChanged: () => changed = true,
      ),
    ));
    if (changed && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, constraints) {
      final isWide = constraints.maxWidth >= AppBreakpoints.phone;
      return Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppBreakpoints.maxContentWidth),
          child: SizedBox(
            width: double.infinity,
            child: RefreshIndicator(
              onRefresh: _load,
              child: _body(isWide),
            ),
          ),
        ),
      );
    });
  }

  Widget _body(bool isWide) {
    if (_loading) {
      return const SkeletonList(rows: 4, padding: EdgeInsets.all(AppSpacing.lg));
    }

    if (_failed) {
      return FailureState(
        error: _error,
        onRetry: _load,
        padding: const EdgeInsets.all(AppSpacing.lg),
      );
    }

    if (_tasks.isEmpty) {
      return AppScrollbar(
        controller: _scrollCtrl,
        child: ListView(
          controller: _scrollCtrl,
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            GuidedEmptyState(
              icon: Icons.assignment_outlined,
              title: AppStrings.t('worker.emptyTasksTitle'),
              description: AppStrings.t('worker.emptyTasksDesc'),
              primaryLabel: AppStrings.t('worker.emptyTasksAction'),
              primaryIcon: Icons.refresh_rounded,
              onPrimary: _load,
              secondaryHint: AppStrings.t('worker.noTasksHint'),
            ),
          ],
        ),
      );
    }

    Widget tileAt(int i) {
      final task = Map<String, dynamic>.from(_tasks[i] as Map);
      return WorkerTaskTile(
        key: ValueKey('worker-task-${task['id'] ?? i}'),
        task: task,
        inGrid: isWide,
        onTap: () => _openTask(task),
      );
    }

    // Lazy: rows are created on demand as the list scrolls.
    final sliverList = isWide
        ? SliverList.builder(
            itemCount: (_tasks.length / 2).ceil(),
            itemBuilder: (_, row) {
              final left = row * 2;
              final right = left + 1;
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: tileAt(left)),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: right < _tasks.length
                          ? tileAt(right)
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              );
            },
          )
        : SliverList.builder(
            itemCount: _tasks.length,
            itemBuilder: (_, i) => tileAt(i),
          );

    return AppScrollbar(
      controller: _scrollCtrl,
      child: CustomScrollView(
        controller: _scrollCtrl,
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 4),
            sliver: SliverList.list(
              children: [
                Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(AppStrings.t('worker.tasks'),
                          style: GoogleFonts.inter(
                              fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                      const SizedBox(height: 2),
                      Text(AppStrings.t('worker.tasksSectionSub'),
                          style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted)),
                    ]),
                  ),
                  if (_lastUpdated.length >= 16)
                    Text(_lastUpdated.substring(11, 16),
                        style: GoogleFonts.inter(
                            fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
                  IconButton(
                    icon: Icon(Icons.refresh_rounded, size: 18, color: AppColors.accent),
                    tooltip: AppStrings.t('worker.emptyTasksAction'),
                    onPressed: _load,
                  ),
                ]),
              ],
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
            sliver: sliverList,
          ),
        ],
      ),
    );
  }
}

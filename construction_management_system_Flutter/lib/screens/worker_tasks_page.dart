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
      return ListView(
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
      );
    }

    final tiles = _tasks.map((t) {
      final task = Map<String, dynamic>.from(t as Map);
      return WorkerTaskTile(
        task: task,
        inGrid: isWide,
        onTap: () => _openTask(task),
      );
    }).toList();

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
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
        const SizedBox(height: 4),
        if (isWide)
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            children: tiles
                .map((t) => SizedBox(
                      width: (MediaQuery.of(context).size.width - AppSpacing.lg * 2 - AppSpacing.md) / 2,
                      child: t,
                    ))
                .toList(),
          )
        else
          ...tiles,
      ],
    );
  }
}

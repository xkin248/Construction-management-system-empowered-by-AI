import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/api_service.dart';
import '../services/app_settings.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';
import '../widgets/app_scrollbar.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/worker_ui.dart';
import 'worker_task_detail_page.dart';

/// Worker "Tasks" tab — a plain list of rows.
///
/// Every row is only: status colour bar, status icon, task name, one big
/// number. Everything else (section, priority, due date, description,
/// instructions) lives on the detail page, because a worker who reads little
/// cannot scan four metadata chips per card.
class WorkerTasksPage extends StatefulWidget {
  const WorkerTasksPage({super.key});

  @override
  State<WorkerTasksPage> createState() => _WorkerTasksPageState();
}

class _WorkerTasksPageState extends State<WorkerTasksPage> {
  final ScrollController _scrollCtrl = ScrollController();

  bool _loading = true;
  bool _failed = false;
  List _tasks = [];

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
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  Future<void> _openTask(Map<String, dynamic> task) async {
    final id = task['task_id'] ?? task['id'];
    final taskId = id is int ? id : int.tryParse(id?.toString() ?? '');
    if (taskId == null) {
      toast(wT(en: 'NO TASK', ms: 'TIADA TUGASAN', zh: '无法打开'));
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
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppBreakpoints.maxContentWidth),
        child: SizedBox(
          width: double.infinity,
          child: RefreshIndicator(onRefresh: _load, child: _body()),
        ),
      ),
    );
  }

  /// Working tasks first, then new ones, finished ones last.
  List<Map<String, dynamic>> get _sorted {
    final list = _tasks.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    int rank(Map<String, dynamic> t) {
      switch (wStatusKey(t['status'])) {
        case 'in_progress':
          return 0;
        case 'completed':
          return 2;
        default:
          return 1;
      }
    }

    list.sort((a, b) => rank(a).compareTo(rank(b)));
    return list;
  }

  Widget _body() {
    if (_loading) {
      return const SkeletonList(rows: 4, padding: EdgeInsets.all(AppSpacing.lg));
    }

    if (_failed) {
      return AppScrollbar(
        controller: _scrollCtrl,
        child: ListView(
          controller: _scrollCtrl,
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            WErrorHint(
              title: wT(en: 'NO SIGNAL', ms: 'TIADA ISYARAT', zh: '网络不通'),
              hint: wT(en: 'Check internet. Try again.', ms: 'Semak internet. Cuba lagi.', zh: '检查网络后再试'),
              onRetry: _load,
            ),
          ],
        ),
      );
    }

    if (_tasks.isEmpty) {
      return AppScrollbar(
        controller: _scrollCtrl,
        child: ListView(
          controller: _scrollCtrl,
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            WEmpty(
              icon: Icons.check_circle_outline_rounded,
              title: wT(en: 'NO TASKS', ms: 'TIADA TUGASAN', zh: '暂无任务'),
              actionLabel: wT(en: 'REFRESH', ms: 'MUAT SEMULA', zh: '刷新'),
              onAction: _load,
            ),
          ],
        ),
      );
    }

    final tasks = _sorted;
    return AppScrollbar(
      controller: _scrollCtrl,
      child: ListView.separated(
        controller: _scrollCtrl,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        itemCount: tasks.length + 1,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (ctx, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 4, left: 2),
              child: Row(children: [
                Icon(Icons.list_alt_rounded, size: 22, color: AppColors.textSecondary),
                const SizedBox(width: 8),
                Text(
                  '${tasks.length} ${wT(en: 'TASKS', ms: 'TUGASAN', zh: '个任务')}',
                  style: GoogleFonts.inter(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textSecondary),
                ),
              ]),
            );
          }
          final task = tasks[i - 1];
          return WTaskRow(
            key: ValueKey('worker-task-${task['id'] ?? i}'),
            task: task,
            onTap: () => _openTask(task),
          );
        },
      ),
    );
  }
}

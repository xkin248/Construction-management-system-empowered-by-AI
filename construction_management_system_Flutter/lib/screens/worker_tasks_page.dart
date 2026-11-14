import 'package:flutter/material.dart';
import '../widgets/app_page_intro.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/api_service.dart';
import '../services/app_settings.dart';
import '../theme/app_theme.dart';
import '../widgets/app_scrollbar.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/w_status_chip.dart';
import '../widgets/worker_live_badge.dart';
import '../widgets/worker_ui.dart';
import 'worker_task_detail_page.dart';

/// Worker task list (spec A5).
///
/// Three buckets — Today / Upcoming / Completed — and inside each bucket the
/// order is fixed to In Progress -> Pending -> Completed so a worker always
/// finds "what to do right now" at the top of the screen.
class WorkerTasksPage extends StatefulWidget {
  const WorkerTasksPage({super.key});

  @override
  State<WorkerTasksPage> createState() => _WorkerTasksPageState();
}

class _WorkerTasksPageState extends State<WorkerTasksPage> {
  late final ScrollController _scrollCtrl;

  bool _loading = true;
  bool _failed = false;
  bool _refreshing = false;
  List<Map<String, dynamic>> _tasks = [];
  DateTime? _lastUpdated;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _scrollCtrl = ScrollController();
    AppColors.darkMode.addListener(_rebuild);
    AppSettings.lang.addListener(_rebuild);
    _load();
  }

  @override
  void dispose() {
    AppColors.darkMode.removeListener(_rebuild);
    AppSettings.lang.removeListener(_rebuild);
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    setState(() {
      _loading = _tasks.isEmpty;
      _refreshing = _tasks.isNotEmpty;
    });
    try {
      final r = await ApiService().workerTaskBoard(refresh: true);
      final raw = (r['tasks'] ?? []) as List;
      final list = raw
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _tasks = list;
        _failed = false;
        _lastUpdated = DateTime.now();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  void _openTask(Map<String, dynamic> task) {
    final id = task['task_id'] ?? task['id'];
    if (id is! num) {
      toast('NO TASK');
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => WorkerTaskDetailPage(
        taskId: id.toInt(),
        initial: task,
        onChanged: _load,
      ),
    ));
  }

  // ── bucketing ────────────────────────────────────────────────────────────

  bool _isCompleted(Map<String, dynamic> t) => wIsTerminalStatus(t['status']);

  DateTime? _due(Map<String, dynamic> t) {
    final raw = t['due_date'] ?? t['due'];
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString());
  }

  List<Map<String, dynamic>> _bucket(int tab) {
    final now = DateTime.now();
    final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);
    final out = <Map<String, dynamic>>[];
    for (final t in _tasks) {
      final completed = _isCompleted(t);
      final due = _due(t);
      if (tab == 2) {
        if (completed) out.add(t);
        continue;
      }
      if (completed) continue;
      final isToday = due == null || !due.isAfter(todayEnd);
      if (tab == 0 ? isToday : !isToday) out.add(t);
    }
    out.sort((a, b) {
      final ra = _rank(a);
      final rb = _rank(b);
      if (ra != rb) return ra.compareTo(rb);
      final da = _due(a);
      final db = _due(b);
      if (da != null && db != null) return da.compareTo(db);
      if (da != null) return -1;
      if (db != null) return 1;
      return 0;
    });
    return out;
  }

  /// In Progress (0) -> Pending (1) -> Submitted/Approved (2) -> Completed (3).
  int _rank(Map<String, dynamic> t) {
    switch (wStatusOf(t['status'])) {
      case WStatus.inProgress:
        return 0;
      case WStatus.pending:
        return 1;
      case WStatus.rejected:
        return 0;
      case WStatus.submitted:
        return 2;
      case WStatus.approved:
        return _isCompleted(t) ? 3 : 2;
    }
  }

  // ── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final visible = _bucket(_tab);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppPageIntro(
          icon: Icons.checklist_rounded,
          enTitle: 'MY WORK',
          msTitle: 'TUGAS SAYA',
          zhTitle: '我的任务',
          enSubtitle: 'Tap a job to see what to do',
          msSubtitle: 'Tekan tugas untuk lihat arahan',
          zhSubtitle: '点击任务查看工作步骤',
          worker: true,
        ),
        const SizedBox(height: 14),
        WorkerLiveBadge(
          failed: _failed,
          loading: _refreshing,
          lastUpdated: _lastUpdated,
          onRefresh: _load,
        ),
        const SizedBox(height: 12),
        _tabs(),
        const SizedBox(height: 12),
        Expanded(child: _body(visible)),
      ]),
    );
  }

  Widget _tabs() {
    final labels = [
      wT(en: 'TODAY', ms: 'HARI INI', zh: '今天'),
      wT(en: 'UPCOMING', ms: 'AKAN DATANG', zh: '即将'),
      wT(en: 'COMPLETED', ms: 'SIAP', zh: '已完成'),
    ];
    return Container(
      height: 60,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: AppRadius.rMd,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(children: [
        for (var i = 0; i < labels.length; i++)
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _tab = i),
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _tab == i ? AppColors.accentSolid : Colors.transparent,
                  borderRadius: AppRadius.rSm,
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '${labels[i]}  ${_bucket(i).length}',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: _tab == i
                          ? AppColors.onAccent
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _body(List<Map<String, dynamic>> visible) {
    if (_loading) return const SkeletonList();
    if (_failed && _tasks.isEmpty) {
      return AppScrollbar(
        controller: _scrollCtrl,
        child: ListView(controller: _scrollCtrl, children: [
          WErrorHint(
            title: wT(en: 'NO SIGNAL', ms: 'TIADA ISYARAT', zh: '无网络'),
            hint: wT(
                en: 'Check internet. Try again.',
                ms: 'Semak internet. Cuba lagi.',
                zh: '请检查网络后重试。'),
            onRetry: _load,
            retryLabel: wT(en: 'RETRY', ms: 'CUBA', zh: '重试'),
          ),
        ]),
      );
    }
    if (visible.isEmpty) {
      return AppScrollbar(
        controller: _scrollCtrl,
        child: ListView(controller: _scrollCtrl, children: [
          WEmpty(
            icon: _tab == 2 ? Icons.done_all_rounded : Icons.checklist_rounded,
            title: _tab == 2
                ? wT(
                    en: 'NOTHING FINISHED YET',
                    ms: 'TIADA YANG SIAP',
                    zh: '暂无已完成任务')
                : wT(en: 'NO TASKS', ms: 'TIADA TUGASAN', zh: '暂无任务'),
            actionLabel: wT(en: 'REFRESH', ms: 'MUAT SEMULA', zh: '刷新'),
            actionIcon: Icons.refresh_rounded,
            onAction: _load,
          ),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: AppScrollbar(
        controller: _scrollCtrl,
        child: ListView.separated(
          controller: _scrollCtrl,
          padding: const EdgeInsets.only(bottom: 24),
          itemCount: visible.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) => _TaskCard(
            task: visible[i],
            onTap: () => _openTask(visible[i]),
          ),
        ),
      ),
    );
  }
}

/// One task: name, project, due date and status (icon + word).
class _TaskCard extends StatelessWidget {
  final Map<String, dynamic> task;
  final VoidCallback? onTap;

  const _TaskCard({required this.task, this.onTap});

  DateTime? get _due {
    final raw = task['due_date'] ?? task['due'];
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString());
  }

  String get _dueText {
    final d = _due;
    if (d == null) {
      return wT(en: 'No deadline', ms: 'Tiada tarikh akhir', zh: '无截止时间');
    }
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${d.day} ${months[d.month - 1]}';
  }

  bool get _overdue {
    final d = _due;
    if (d == null) return false;
    if (wIsTerminalStatus(task['status'])) return false;
    final now = DateTime.now();
    return d.isBefore(DateTime(now.year, now.month, now.day));
  }

  @override
  Widget build(BuildContext context) {
    final name = (task['task_name'] ?? task['name'] ?? '').toString();
    final project = (task['project_name'] ?? '').toString();
    final tint = wStatusTint(wStatusOf(task['status']));

    return Material(
      color: AppColors.bgCard,
      borderRadius: AppRadius.rLg,
      child: InkWell(
        borderRadius: AppRadius.rLg,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 104),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: AppRadius.rLg,
            border: Border.all(color: AppColors.border),
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(
                  name.isEmpty ? wT(en: 'Task', ms: 'Tugasan', zh: '任务') : name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textPrimary),
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded,
                  size: 24, color: AppColors.textMuted),
            ]),
            const SizedBox(height: 6),
            if (project.isNotEmpty)
              Row(children: [
                Icon(Icons.location_city_rounded,
                    size: 18, color: AppColors.textMuted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    project,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                        fontSize: 15, color: AppColors.textSecondary),
                  ),
                ),
              ]),
            const SizedBox(height: 8),
            Row(children: [
              WStatusChip(status: task['status'], compact: true),
              const SizedBox(width: 10),
              Icon(
                _overdue ? Icons.warning_amber_rounded : Icons.event_rounded,
                size: 18,
                color: _overdue ? AppColors.red : AppColors.textMuted,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  _dueText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: _overdue ? FontWeight.w800 : FontWeight.w500,
                    color: _overdue ? AppColors.red : AppColors.textMuted,
                  ),
                ),
              ),
              const Spacer(),
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

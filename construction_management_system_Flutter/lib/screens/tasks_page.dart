import 'package:flutter/material.dart';
import '../widgets/app_page_intro.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';
import '../services/api_service.dart';
import '../services/app_settings.dart';
import '../services/project_cache.dart';
import '../services/task_status_notifier.dart';
import '../l10n/app_strings.dart';
import '../widgets/task_form.dart';
import '../widgets/guided_empty_state.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/failure_state.dart';
import '../widgets/app_scrollbar.dart';
import '../widgets/tasks/task_card.dart';
import '../widgets/tasks/task_filter_bar.dart';

// TaskDetailPage moved to its own file; re-exported so existing imports of
// this page keep resolving the class.
export 'task_detail_page.dart';

class TasksPage extends StatefulWidget {
  const TasksPage({super.key});
  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  bool ld = true;
  List projects = [];
  List tasks = [];
  Object? _loadError;
  int? pid;
  String _searchQuery = '';
  String _statusFilter = 'All';
  String _priorityFilter = 'All';

  /// Drives the always-visible scrollbar of the task list.
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    AppColors.darkMode.addListener(_rebuild);
    AppSettings.lang.addListener(_rebuild);
    TaskStatusNotifier.addListener(_onExternalTaskChange);
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
    TaskStatusNotifier.removeListener(_onExternalTaskChange);
    super.dispose();
  }

  /// Reloads when a task changed on another page (e.g. ProjectDetail quick
  /// status buttons). Pages live in an IndexedStack inside HomeShell, so
  /// initState does not run again when the user switches back to Tasks —
  /// without this signal the main list keeps showing the stale status.
  void _onExternalTaskChange() {
    _load();
  }

  Future<void> _load() async {
    setState(() {
      ld = true;
      _loadError = null;
    });
    try {
      // A project may have been removed while this tab remained alive in the
      // shell. Refresh the list before using its saved filter value.
      projects = await ProjectCache.get(ApiService(), forceRefresh: true);
      final validIds = projects
          .map((p) => p['project_id'])
          .whereType<int>()
          .toSet();
      if (pid != null && !validIds.contains(pid)) pid = null;
      if (projects.isNotEmpty) {
        // Default to ALL projects so a supervisor sees every task instead of
        // only the first project's tasks. A project filter dropdown is still
        // available when more than one project exists.
        tasks = await _loadTasks(pid);
      } else {
        tasks = [];
      }
    } catch (e) {
      _loadError = e;
      toast('Failed to load tasks: $e');
    } finally {
      if (mounted) setState(() => ld = false);
    }
  }

  // Loads tasks for one project (pid != null) or merges tasks from ALL
  // projects (pid == null). Previously a supervisor without a project
  // switcher only ever saw the first project's tasks.
  Future<List> _loadTasks(int? targetPid) async {
    if (targetPid != null) {
      return await ApiService().getTasks(targetPid);
    }
    final all = await Future.wait(
      projects.map((p) => ApiService().getTasks(p['project_id'] as int)),
    );
    return all.expand((t) => t).toList();
  }

  Future<void> _switchProject(int? newPid) async {
    setState(() { pid = newPid; ld = true; });
    try {
      tasks = await _loadTasks(newPid);
    } finally {
      if (mounted) setState(() => ld = false);
    }
  }

  void _openNewTask() async {
    if (projects.isEmpty) { toast('Create a project first'); return; }
    // pid may be null (viewing ALL projects); TaskForm falls back to the
    // first project and still lets the user switch projects inside the form.
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => TaskForm(initialProjectId: pid),
    );
    if (created == true) _load();
  }

  /// Empty states stay refreshable: the area is a scroll view with
  /// [AlwaysScrollableScrollPhysics] so pull-to-refresh works even with no rows,
  /// and the explicit refresh button covers mouse/keyboard users who never pull
  /// (e.g. after creating the first task elsewhere).
  Widget _refreshableEmpty(Widget child) {
    return RefreshIndicator(
      onRefresh: _load,
      child: LayoutBuilder(builder: (ctx, c) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: c.maxHeight,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  TextButton.icon(
                    onPressed: ld ? null : _load,
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: Text(AppStrings.t('common.retry')),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.accent,
                      textStyle: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w700),
                    ),
                  ),
                ]),
              ),
              Expanded(child: child),
            ]),
          ),
        );
      }),
    );
  }

  /// Saved status of a task, lower-cased.
  static String _statusOf(Map t) => (t['status'] as String? ?? '').toLowerCase();

  /// Derived "Overdue": the task is still open but its due date already passed.
  /// The backend Task model has no overdue column, so this single rule feeds the
  /// card tag, the list filter and the segment counter alike.
  static bool _isOverdue(Map t) {
    if (_statusOf(t) == 'completed') return false;
    final due = DateTime.tryParse((t['due_date'] ?? '').toString());
    if (due == null) return false;
    final now = DateTime.now();
    return due.isBefore(DateTime(now.year, now.month, now.day));
  }

  bool _matchesQuery(Map t) {
    final name = (t['task_name'] as String? ?? '').toLowerCase();
    final matchSearch =
        _searchQuery.isEmpty || name.contains(_searchQuery.toLowerCase());
    final matchPriority = _priorityFilter == 'All' ||
        (t['priority'] as String? ?? '') == _priorityFilter.toLowerCase();
    return matchSearch && matchPriority;
  }

  /// Segment values stay English (they drive the comparison); the labels are
  /// localised by [TaskFilterBar.displayOf].
  bool _matchesSegment(Map t, String segment) {
    switch (segment) {
      case 'All':
        return true;
      case 'Overdue':
        return _isOverdue(t);
      default:
        return _statusOf(t) == segment.toLowerCase().replaceAll(' ', '_');
    }
  }

  List get _filtered => tasks
      .where((t) => _matchesQuery(t) && _matchesSegment(t, _statusFilter))
      .toList();

  /// Counters for the status segments. They honour the current search and
  /// priority filters so each number describes the rows actually on screen.
  Map<String, int> get _segmentCounts {
    final base = tasks.where((t) => _matchesQuery(t)).toList();
    return {
      for (final s in TaskFilterBar.statusSegments)
        s: base.where((t) => _matchesSegment(t, s)).length,
    };
  }

  @override
  Widget build(BuildContext c) {
    return Scaffold(
      backgroundColor: AppColors.bgMain,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: const ValueKey('fab_tasks'),
        onPressed: _openNewTask,
        icon: const Icon(Icons.add),
        label: Text(AppStrings.t('tasks.newTask')),
        backgroundColor: AppColors.accent,
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppBreakpoints.maxContentWidth),
          child: SizedBox(
            width: double.infinity,
            child: Column(children: [
              AppPageIntro(
                icon: Icons.assignment_turned_in_rounded,
                enTitle: 'TASK MANAGEMENT',
                msTitle: 'PENGURUSAN TUGAS',
                zhTitle: '任务管理',
                enSubtitle: 'Assign, track and complete work',
                msSubtitle: 'Agih dan pantau tugasan',
                zhSubtitle: '分配、跟进与完成任务',
                worker: false,
              ),
              const SizedBox(height: 14),
                            // ── Search + Filters ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: TaskFilterBar(
                  onSearchChanged: (v) => setState(() => _searchQuery = v),
                  statusFilter: _statusFilter,
                  onStatusChanged: (v) => setState(() => _statusFilter = v),
                  counts: _segmentCounts,
                  priorityFilter: _priorityFilter,
                  onPriorityChanged: (v) => setState(() => _priorityFilter = v),
                  projects: projects,
                  selectedProjectId: pid,
                  onProjectChanged: _switchProject,
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // ── Task List ──
              Expanded(
                child: ld
                    ? const SkeletonList(rows: 6)
                    : (_loadError != null && tasks.isEmpty)
                        ? FailureState(error: _loadError, onRetry: _load)
                        : _filtered.isEmpty
                        ? _refreshableEmpty(
                            (_searchQuery.isEmpty &&
                                    _statusFilter == 'All' &&
                                    _priorityFilter == 'All')
                                ? GuidedEmptyState(
                                    icon: Icons.task_alt_rounded,
                                    title: AppStrings.t('empty.tasks.title'),
                                    description: AppStrings.t('empty.tasks.desc'),
                                    primaryLabel: AppStrings.t('empty.tasks.action'),
                                    onPrimary: _openNewTask,
                                  )
                                : FilteredEmptyState(
                                    title: AppStrings.t('empty.tasks.noMatch'),
                                    description:
                                        AppStrings.t('empty.tasks.noMatchDesc'),
                                    clearLabel: AppStrings.t('empty.clearFilters'),
                                    onClear: () => setState(() {
                                      _searchQuery = '';
                                      _statusFilter = 'All';
                                      _priorityFilter = 'All';
                                    }),
                                  ),
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: AppScrollbar(
                              controller: _scrollCtrl,
                              child: LayoutBuilder(builder: (ctx, constraints) {
                                // Two columns only when each card still gets a
                                // comfortable width. The card carries a status
                                // tag, a priority row and a skill/crew chip row,
                                // so a fixed mainAxisExtent is used instead of
                                // an aspect ratio to keep the taller content
                                // from overflowing.
                                final wide = constraints.maxWidth >= 900;
                                // Filter once per build; the lazy lists below
                                // only build the rows that become visible.
                                final rows = _filtered;
                                if (!wide) {
                                  return ListView.builder(
                                    controller: _scrollCtrl,
                                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                                    itemCount: rows.length,
                                    addAutomaticKeepAlives: false,
                                    itemBuilder: (ctx, i) => TaskCard(
                                      task: rows[i],
                                      onChanged: _load,
                                    ),
                                  );
                                }
                                return GridView.builder(
                                  controller: _scrollCtrl,
                                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2,
                                    mainAxisSpacing: AppSpacing.md,
                                    crossAxisSpacing: AppSpacing.md,
                                    mainAxisExtent: 272,
                                  ),
                                  itemCount: rows.length,
                                  addAutomaticKeepAlives: false,
                                  itemBuilder: (ctx, i) => TaskCard(
                                    task: rows[i],
                                    onChanged: _load,
                                    inGrid: true,
                                  ),
                                );
                              }),
                            ),
                          ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

}

// ──────────────── Task Card ────────────────

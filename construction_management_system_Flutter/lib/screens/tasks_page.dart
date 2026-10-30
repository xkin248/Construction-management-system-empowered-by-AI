import 'package:flutter/material.dart';
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
    setState(() => ld = true);
    try {
      projects = await ProjectCache.get(ApiService());
      if (projects.isNotEmpty) {
        // Default to ALL projects so a supervisor sees every task instead of
        // only the first project's tasks. A project filter dropdown is still
        // available when more than one project exists.
        tasks = await _loadTasks(pid);
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

  List get _filtered {
    return tasks.where((t) {
      final name = (t['task_name'] as String? ?? '').toLowerCase();
      final status = (t['status'] as String? ?? '');
      final priority = (t['priority'] as String? ?? '');
      final matchSearch = _searchQuery.isEmpty || name.contains(_searchQuery.toLowerCase());
      final matchStatus = _statusFilter == 'All' || status == _statusFilter.toLowerCase().replaceAll(' ', '_');
      final matchPriority = _priorityFilter == 'All' || priority == _priorityFilter.toLowerCase();
      return matchSearch && matchStatus && matchPriority;
    }).toList();
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
              // ── Search + Filters ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: TaskFilterBar(
                  onSearchChanged: (v) => setState(() => _searchQuery = v),
                  statusFilter: _statusFilter,
                  onStatusChanged: (v) => setState(() => _statusFilter = v),
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
                        ? ((_searchQuery.isEmpty && _statusFilter == 'All')
                            ? GuidedEmptyState(
                                icon: Icons.task_alt_rounded,
                                title: AppStrings.t('empty.tasks.title'),
                                description: AppStrings.t('empty.tasks.desc'),
                                primaryLabel: AppStrings.t('empty.tasks.action'),
                                onPrimary: _openNewTask,
                              )
                            : FilteredEmptyState(
                                title: AppStrings.t('empty.tasks.noMatch'),
                                description: AppStrings.t('empty.tasks.noMatchDesc'),
                                clearLabel: AppStrings.t('empty.clearFilters'),
                                onClear: () => setState(() {
                                  _searchQuery = '';
                                  _statusFilter = 'All';
                                }),
                              ))
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: AppScrollbar(
                              controller: _scrollCtrl,
                              child: LayoutBuilder(builder: (ctx, constraints) {
                                final wide = constraints.maxWidth >= AppBreakpoints.phone;
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
                                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2,
                                    mainAxisSpacing: AppSpacing.md,
                                    crossAxisSpacing: AppSpacing.md,
                                    childAspectRatio: constraints.maxWidth >= 900 ? 1.9 : 1.45,
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
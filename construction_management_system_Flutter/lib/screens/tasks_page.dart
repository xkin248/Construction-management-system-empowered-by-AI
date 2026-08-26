import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';
import '../services/api_service.dart';
import '../services/app_settings.dart';
import '../l10n/app_strings.dart';
import '../widgets/task_form.dart';

class TasksPage extends StatefulWidget {
  const TasksPage({super.key});
  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  bool ld = true;
  List projects = [];
  List tasks = [];
  int? pid;
  String _searchQuery = '';
  String _statusFilter = 'All';
  String _priorityFilter = 'All';

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
    setState(() => ld = true);
    try {
      projects = await ApiService().getProjects();
      if (projects.isNotEmpty) {
        // Default to ALL projects so a supervisor sees every task instead of
        // only the first project's tasks. A project filter dropdown is still
        // available when more than one project exists.
        tasks = await _loadTasks(pid);
      }
    } catch (e) {
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
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: AppColors.bgCard,
        elevation: 0,
        titleSpacing: 16,
        title: Text(AppStrings.t('tasks.title'), style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 18)),
        actions: const [],
      ),
      floatingActionButton: FloatingActionButton.extended(
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
                child: _buildFilterRow(),
              ),
              const SizedBox(height: AppSpacing.md),

              // ── Task List ──
              Expanded(
                child: ld
                    ? const Center(child: CircularProgressIndicator())
                    : _filtered.isEmpty
                        ? Center(child: Text(AppStrings.t('tasks.noTasks'), style: GoogleFonts.outfit(color: AppColors.textMuted)))
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: LayoutBuilder(builder: (ctx, constraints) {
                              final wide = constraints.maxWidth >= AppBreakpoints.phone;
                              if (!wide) {
                                return ListView.builder(
                                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                                  itemCount: _filtered.length,
                                  itemBuilder: (ctx, i) => _TaskCard(
                                    task: _filtered[i],
                                    onChanged: _load,
                                  ),
                                );
                              }
                              return GridView.builder(
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  mainAxisSpacing: AppSpacing.md,
                                  crossAxisSpacing: AppSpacing.md,
                                  childAspectRatio: constraints.maxWidth >= 900 ? 1.9 : 1.45,
                                ),
                                itemCount: _filtered.length,
                                itemBuilder: (ctx, i) => _TaskCard(
                                  task: _filtered[i],
                                  onChanged: _load,
                                  inGrid: true,
                                ),
                              );
                            }),
                          ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterRow() {
    return Column(children: [
      // Full-width search
      SizedBox(
        height: 44,
        child: TextField(
          onChanged: (v) => setState(() => _searchQuery = v),
          decoration: InputDecoration(
            hintText: 'Search tasks...',
            hintStyle: GoogleFonts.outfit(fontSize: 13, color: AppColors.textMuted),
            prefixIcon: Icon(Icons.search_rounded, size: 20, color: AppColors.textMuted),
            filled: true, fillColor: AppColors.bgCard,
            contentPadding: const EdgeInsets.symmetric(vertical: 0),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.accent)),
          ),
        ),
      ),
      const SizedBox(height: 8),
      // Filter chips row
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          _dropdown(['All', 'In Progress', 'Completed', 'Pending'], _statusFilter, (v) => setState(() => _statusFilter = v!), AppStrings.t('tasks.statusLabel')),
          const SizedBox(width: 8),
          _dropdown(['All', 'Low', 'Medium', 'High'], _priorityFilter, (v) => setState(() => _priorityFilter = v!), AppStrings.t('tasks.priority')),
          if (projects.length > 1) ...[
            const SizedBox(width: 8),
            _dropdown(
              projects.map<String>((p) => p['project_name'] as String).toList()..insert(0, 'All'),
              pid == null ? 'All' : (projects.where((p) => p['project_id'] == pid).isEmpty ? 'All' : projects.firstWhere((p) => p['project_id'] == pid)['project_name'] as String),
              (v) {
                if (v == 'All') {
                  _switchProject(null);
                } else {
                  final found = projects.firstWhere((p) => p['project_name'] == v, orElse: () => null);
                  if (found != null) _switchProject(found['project_id']);
                }
              }, AppStrings.t('tasks.projectLabel'),
            ),
          ],
        ]),
      ),
    ]);
  }

  /// Localised display for status / priority filter values.
  /// The internal filter value stays in English so existing logic is untouched.
  String _displayOf(String s) {
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

  Widget _dropdown(List<String> items, String value, ValueChanged<String?> onChanged, String hint) {
    final v = items.contains(value) ? value : items.first;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      height: 48,
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButton<String>(
        value: v,
        underline: const SizedBox(),
        isExpanded: true,
        style: GoogleFonts.outfit(fontSize: 14, color: AppColors.textPrimary, fontWeight: FontWeight.w600),
        items: items.map((s) => DropdownMenuItem(value: s, child: Text('$hint: ${_displayOf(s)}'))).toList(),
        onChanged: onChanged,
      ),
    );
  }
}

// ──────────────── Task Card ────────────────
class _TaskCard extends StatefulWidget {
  final Map task;
  final VoidCallback? onChanged;
  final bool inGrid;
  const _TaskCard({required this.task, this.onChanged, this.inGrid = false});

  @override
  State<_TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends State<_TaskCard> {
  late String _status;
  late String? _dueDate;

  @override
  void initState() {
    super.initState();
    _status = widget.task['status'] as String? ?? 'pending';
    _dueDate = widget.task['due_date'] as String?;
  }

  Color _dueColor() {
    if (_dueDate == null || _dueDate!.isEmpty) return AppColors.textMuted;
    final d = DateTime.tryParse(_dueDate!);
    if (d == null) return AppColors.textMuted;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dueDay = DateTime(d.year, d.month, d.day);
    if (dueDay.isBefore(today)) return AppColors.red;
    if (dueDay.isAtSameMomentAs(today)) return AppColors.primaryLight;
    return AppColors.green;
  }

  Widget _dueLabel() {
    if (_dueDate == null || _dueDate!.isEmpty) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.calendar_today_outlined,
            size: 12, color: AppColors.textMuted),
        const SizedBox(width: 4),
        Text(AppStrings.t('tasks.noDueDate'),
            style:
                GoogleFonts.outfit(fontSize: 13, color: AppColors.textMuted)),
      ]);
    }
    final parsed = DateTime.tryParse(_dueDate!);
    final display =
        parsed != null ? DateFormat('dd/MM/yy').format(parsed) : _dueDate!;
    final color = _dueColor();
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.calendar_today_outlined, size: 12, color: color),
      const SizedBox(width: 4),
      Text(display,
          style: GoogleFonts.outfit(
              fontSize: 13, fontWeight: FontWeight.w600, color: color)),
    ]);
  }

  Future<void> _editDueDate() async {
    final init =
        _dueDate != null ? DateTime.tryParse(_dueDate!) : null;
    final picked = await showDatePicker(
      context: context,
      initialDate: init ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    final newDate = picked.toIso8601String().split('T').first;
    try {
      await ApiService()
          .updateTask(widget.task['task_id'], {'due_date': newDate});
      setState(() => _dueDate = newDate);
      widget.task['due_date'] = newDate;
      toast(AppStrings.t('tasks.dueUpdated'));
    } catch (e) {
      toast(AppStrings.t('tasks.dueFailed'));
    }
  }

  Future<void> _setStatus(String newStatus) async {
    if (newStatus == _status) return;
    try {
      await ApiService()
          .updateTask(widget.task['task_id'], {'status': newStatus});
      setState(() => _status = newStatus);
      widget.task['status'] = newStatus;
      widget.onChanged?.call();
      toast(AppStrings.t('tasks.statusUpdated'));
    } catch (e) {
      toast(AppStrings.t('tasks.statusFailed'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final priority = widget.task['priority'] as String? ?? 'medium';
    final assignedRaw = widget.task['assigned_workers'];
    List<Map> workers = [];
    if (assignedRaw is List) {
      workers = assignedRaw.cast<Map>();
    } else {
      final single = widget.task['assigned_worker'] as Map?;
      if (single != null) workers = [single];
    }
    final progress = (widget.task['progress'] as num? ?? 0).toDouble();
    final isInProgress = _status == 'in_progress';
    final isCompleted = _status == 'completed';

    final leadIcon = isCompleted
        ? _SpinningOrIcon(
            icon: Icons.check_circle_rounded,
            color: AppColors.green,
            spin: false)
        : isInProgress
            ? _SpinningOrIcon(
                icon: Icons.settings_rounded,
                color: AppColors.blue,
                spin: true)
            : _SpinningOrIcon(
                icon: Icons.radio_button_unchecked_rounded,
                color: AppColors.textMuted,
                spin: false);

    final barColor =
        isCompleted ? AppColors.green : isInProgress ? AppColors.blue : AppColors.yellow;

    return Container(
      margin: widget.inGrid ? EdgeInsets.zero : const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Navigable section (header + progress + worker/due) ──
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () async {
            final changed = await Navigator.push<bool>(context,
                MaterialPageRoute(builder: (_) => TaskDetailPage(task: widget.task)));
            if (changed == true) widget.onChanged?.call();
          },
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Title row
            Row(children: [
              leadIcon,
              const SizedBox(width: 10),
              Expanded(
                child: Text(widget.task['task_name'] ?? '-',
                    style: GoogleFonts.outfit(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary),
                    overflow: TextOverflow.ellipsis),
              ),
              _PriorityBadge(priority: priority),
              const SizedBox(width: 8),
              Text('${progress.toStringAsFixed(0)}%',
                  style: GoogleFonts.outfit(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary)),
            ]),
            if (widget.task['project_name'] != null ||
                (widget.task['project'] != null)) ...[
              const SizedBox(height: 2),
              Padding(
                padding: const EdgeInsets.only(left: 28),
                child: Text(
                    widget.task['project_name'] ??
                        widget.task['project']?['project_name'] ??
                        '',
                    style: GoogleFonts.outfit(
                        fontSize: 13, color: AppColors.textMuted)),
              ),
            ],
            const SizedBox(height: 10),
            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress / 100,
                minHeight: 6,
                backgroundColor: AppColors.border,
                valueColor: AlwaysStoppedAnimation(barColor),
              ),
            ),
            // Trade badge
            if (widget.task['trade'] != null) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 28),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    (widget.task['trade'] as String)[0].toUpperCase() +
                        (widget.task['trade'] as String).substring(1),
                    style: GoogleFonts.outfit(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.accent),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            // Worker + due date row
            Row(children: [
              if (workers.isNotEmpty) ...[
                initialsAvatar(workers.first['name'] ?? '?', radius: 11),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    workers.length > 1
                        ? '${workers.first['name'] ?? ''} +${workers.length - 1} more'
                        : (workers.first['name'] ?? ''),
                    style: GoogleFonts.outfit(
                        fontSize: 14,
                        color: AppColors.accent,
                        fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ] else
                Text(AppStrings.t('tasks.unassigned'),
                    style:
                        GoogleFonts.outfit(fontSize: 14, color: AppColors.textMuted)),
              const Spacer(),
              // Tap due date to quickly edit
              GestureDetector(
                onTap: _editDueDate,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: _dueLabel(),
                ),
              ),
            ]),
          ]),
        ),
        const SizedBox(height: 10),
        // ── Status quick-toggle (does not navigate) ──
        Row(children: [
          _statusBtn(AppStrings.t('tasks.pending'), 'pending'),
          const SizedBox(width: 6),
          _statusBtn(AppStrings.t('tasks.inProgress'), 'in_progress'),
          const SizedBox(width: 6),
          _statusBtn(AppStrings.t('tasks.completed'), 'completed'),
        ]),
      ]),
    );
  }

  Widget _statusBtn(String label, String statusValue) {
    final active = _status == statusValue;
    Color bg;
    Color fg;
    switch (statusValue) {
      case 'completed':
        bg = active
            ? AppColors.green
            : AppColors.greenLight.withValues(alpha: 0.4);
        fg = active ? Colors.white : AppColors.green;
        break;
      case 'in_progress':
        bg = active
            ? AppColors.blue
            : AppColors.blueLight.withValues(alpha: 0.4);
        fg = active ? Colors.white : AppColors.blue;
        break;
      default:
        bg = active ? AppColors.textMuted : AppColors.border;
        fg = active ? Colors.white : AppColors.textMuted;
    }
    return Expanded(
      child: SizedBox(
        height: 32,
        child: ElevatedButton(
          onPressed: () => _setStatus(statusValue),
          style: ElevatedButton.styleFrom(
            backgroundColor: bg,
            foregroundColor: fg,
            padding: EdgeInsets.zero,
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
          ),
          child: Text(label,
              style: GoogleFonts.outfit(
                  fontSize: 13, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}

class _PriorityBadge extends StatelessWidget {
  final String priority;
  const _PriorityBadge({required this.priority});

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    final String label;
    switch (priority.toLowerCase()) {
      case 'high':
        label = AppStrings.t('tasks.high'); bg = AppColors.redLight; fg = AppColors.red; break;
      case 'medium':
        label = AppStrings.t('tasks.medium'); bg = AppColors.yellowLight; fg = AppColors.yellow; break;
      default:
        label = AppStrings.t('tasks.low'); bg = AppColors.blueLight; fg = AppColors.blue;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(label,
          style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700, color: fg)),
    );
  }
}

class _SpinningOrIcon extends StatefulWidget {
  final IconData icon;
  final Color color;
  final bool spin;
  const _SpinningOrIcon({required this.icon, required this.color, required this.spin});
  @override
  State<_SpinningOrIcon> createState() => _SpinningOrIconState();
}

class _SpinningOrIconState extends State<_SpinningOrIcon> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if (!widget.spin) return Icon(widget.icon, size: 20, color: widget.color);
    return RotationTransition(
      turns: _ctrl,
      child: Icon(widget.icon, size: 20, color: widget.color),
    );
  }
}

// ──────────────── Task Detail Page ────────────────
class TaskDetailPage extends StatefulWidget {
  final Map task;
  const TaskDetailPage({super.key, required this.task});
  @override
  State<TaskDetailPage> createState() => _TaskDetailPageState();
}

class _TaskDetailPageState extends State<TaskDetailPage> {
  List _assignedWorkers = [];    // currently-assigned workers (mutable)
  List _projectWorkers = [];     // all workers in the project
  late Map _task;

  @override
  void initState() {
    super.initState();
    _task = Map.from(widget.task);
    final raw = _task['assigned_workers'];
    if (raw is List && raw.isNotEmpty) {
      _assignedWorkers = raw.cast<Map>();
    } else {
      final single = _task['assigned_worker'] as Map?;
      if (single != null) _assignedWorkers = [single];
    }
    _loadWorkers();
  }

  Future<void> _loadWorkers() async {
    try {
      _projectWorkers = await ApiService().getWorkers();
    } catch (_) {}
  }

  Future<void> _saveAssignments(Set<int> workerIds) async {
    try {
      await ApiService().updateTask(_task['task_id'], {
        'worker_ids': workerIds.toList(),
      });
      // Restore selected objects using the full worker pool
      final pool = _projectWorkers;
      final selected = <Map>[];
      final seen = <int>{};
      for (final w in pool) {
        final id = w['worker_id'] as int?;
        if (id != null && workerIds.contains(id) && !seen.contains(id)) {
          seen.add(id);
          selected.add(w);
        }
      }
      setState(() => _assignedWorkers = selected);
      toast('${selected.length} ${AppStrings.t('tasks.assignedCount')}');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      toast('${AppStrings.t('tasks.assignFailed')}: $e');
    }
  }

  Future<void> _unassign() async {
    try {
      await ApiService().updateTask(_task['task_id'], {'worker_ids': []});
      setState(() => _assignedWorkers = []);
      toast(AppStrings.t('tasks.unassignAll'));
    } catch (e) {
      toast('${AppStrings.t('tasks.assignFailed')}: $e');
    }
  }

  void _openAssignSheet() {
    // Current set of assigned worker_ids (checkbox toggles inside the sheet; save replaces all)
    final currentIds = _assignedWorkers
        .map((w) => w['worker_id'] as int?)
        .whereType<int>()
        .toSet();
    final selectedIds = <int>{...currentIds};

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(builder: (ctx, setS) {
        return DraggableScrollableSheet(
          initialChildSize: 0.75,
          maxChildSize: 0.95,
          minChildSize: 0.4,
          builder: (_, sc) => Container(
            decoration: BoxDecoration(
              color: AppColors.bgCard,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Handle bar
                Center(
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    width: 36, height: 4,
                    decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                Expanded(
                  child: ListView(
                    controller: sc,
                    padding: const EdgeInsets.only(bottom: 16),
                    children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(AppStrings.t('tasks.assignWorkersTitle'), style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800)),
                    Text(_task['task_name'] ?? '', style: GoogleFonts.outfit(fontSize: 14, color: AppColors.textMuted), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ]),
                ),
                // All workers
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                  child: Text(AppStrings.t('tasks.allWorkers'), style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                ),
                ..._projectWorkers.map((w) => _WorkerTile(
                    worker: w,
                    selected: selectedIds.contains(w['worker_id']),
                    onToggle: () {
                      setS(() {
                        final id = w['worker_id'] as int?;
                        if (id == null) return;
                        if (!selectedIds.add(id)) selectedIds.remove(id);
                      });
                    },
                  )),
                    ],
                  ),
                ),
                // Save bar (replaces the entire assignment)
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                  decoration: BoxDecoration(
                    color: AppColors.bgCard,
                    border: Border(top: BorderSide(color: AppColors.border)),
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => _saveAssignments(selectedIds),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: Text('Save Assignment (${selectedIds.length})', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w800)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext c) {
    final t = _task;
    final progress = (t['progress'] as num? ?? 0).toDouble();
    final status = t['status'] as String? ?? 'pending';
    final priority = t['priority'] as String? ?? 'medium';

    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.t('tasks.taskDetails'), style: GoogleFonts.outfit(fontWeight: FontWeight.w800)),
        actions: [
          if (_assignedWorkers.isNotEmpty)
            TextButton(
              onPressed: _unassign,
              child: Text(AppStrings.t('tasks.unassign'), style: GoogleFonts.outfit(color: AppColors.red, fontWeight: FontWeight.w700, fontSize: 13)),
            ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        // Status + priority pills
        Row(children: [
          statusPill(status),
          const SizedBox(width: 8),
          statusPill(priority),
        ]),
        const SizedBox(height: 12),

        // Task name
        Text(t['task_name'] ?? '-',
            style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        if ((t['description'] as String? ?? '').isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(t['description'], style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 13.5, height: 1.5)),
        ],
        const SizedBox(height: 20),

        // Progress card
        sectionCard(margin: const EdgeInsets.only(bottom: 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.trending_up_rounded, size: 16, color: AppColors.blue),
            const SizedBox(width: 8),
            Text(AppStrings.t('tasks.progress'), style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700)),
            const Spacer(),
            Text('${progress.toStringAsFixed(0)}%', style: GoogleFonts.outfit(fontWeight: FontWeight.w800, color: AppColors.blue, fontSize: 15)),
          ]),
          const SizedBox(height: 10),
          ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(
            value: progress / 100, minHeight: 10, backgroundColor: AppColors.blueLight,
            valueColor: AlwaysStoppedAnimation(AppColors.blue),
          )),
        ])),

        // Due date
        if (t['due_date'] != null)
          sectionCard(margin: const EdgeInsets.only(bottom: 12), child: Row(children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(color: AppColors.yellowLight, borderRadius: BorderRadius.circular(8)),
              child: Icon(Icons.event_outlined, size: 16, color: AppColors.yellow),
            ),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(AppStrings.t('tasks.dueDate'), style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
              Text(t['due_date'], style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 14)),
            ]),
          ])),

        // Assigned worker card
        sectionCard(margin: const EdgeInsets.only(bottom: 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.person_outline_rounded, size: 16, color: AppColors.textMuted),
            const SizedBox(width: 6),
            Text(AppStrings.t('tasks.assignedWorker'), style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
          ]),
          const SizedBox(height: 12),
          if (_assignedWorkers.isNotEmpty) ...[
            ..._assignedWorkers.map((w) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(children: [
                initialsAvatar(w['name'] ?? '?', radius: 22),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(w['name'] ?? '-', style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 15)),
                  Text(w['trade'] ?? 'General Worker', style: GoogleFonts.outfit(color: AppColors.textMuted, fontSize: 14)),
                ])),
                Icon(Icons.check_circle_rounded, color: AppColors.green, size: 20),
              ]),
            )),
            const SizedBox(height: 6),
          ] else
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(color: AppColors.border, shape: BoxShape.circle),
                  child: Icon(Icons.person_add_outlined, color: AppColors.textMuted, size: 20),
                ),
                const SizedBox(width: 12),
                Text(AppStrings.t('tasks.noWorkerAssigned'), style: GoogleFonts.outfit(color: AppColors.textMuted, fontSize: 13)),
              ]),
            ),
          // Change / Assign button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _openAssignSheet,
              icon: Icon(
                _assignedWorkers.isNotEmpty ? Icons.swap_horiz_rounded : Icons.person_search_rounded,
                size: 18,
              ),
              label: Text(
                _assignedWorkers.isNotEmpty ? AppStrings.t('tasks.changeAssignment') : AppStrings.t('tasks.assignWorker'),
                style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 13),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.accent,
                side: BorderSide(color: AppColors.accent),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ])),
      ]),
    );
  }
}

// ── Worker tile used in the assign bottom sheet ──
class _WorkerTile extends StatelessWidget {
  final Map worker;
  final bool selected;
  final VoidCallback onToggle;
  const _WorkerTile({required this.worker, required this.selected, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final name = worker['name'] as String? ?? '?';
    final trade = worker['trade'] as String? ?? AppStrings.t('tasks.generalWorker');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgMain,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(children: [
        Row(children: [
          initialsAvatar(name, radius: 20),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(name, style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 14), overflow: TextOverflow.ellipsis)),
            ]),
            Text(trade, style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textMuted)),
          ])),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: onToggle,
            style: ElevatedButton.styleFrom(
              backgroundColor: selected ? AppColors.green : AppColors.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              minimumSize: const Size(70, 36),
            ),
            child: Text(selected ? '✓' : AppStrings.t('common.add'), style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700)),
          ),
        ]),
      ]),
    );
  }
}

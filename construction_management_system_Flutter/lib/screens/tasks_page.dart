import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
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
    _load();
  }

  Future<void> _load() async {
    setState(() => ld = true);
    try {
      projects = await ApiService().getProjects();
      if (projects.isNotEmpty) {
        pid ??= projects.first['project_id'];
        tasks = await ApiService().getTasks(pid!);
      }
    } catch (e) {
      toast('Failed to load tasks: $e');
    } finally {
      if (mounted) setState(() => ld = false);
    }
  }

  Future<void> _switchProject(int? newPid) async {
    setState(() { pid = newPid; ld = true; });
    try {
      tasks = newPid == null ? [] : await ApiService().getTasks(newPid);
    } finally {
      if (mounted) setState(() => ld = false);
    }
  }

  Future<void> _exportTasks() async {
    if (pid == null) { toast('Select a project first'); return; }
    try {
      final path = await ApiService().exportReport(pid!, 'tasks');
      toast('Tasks exported to $path');
      if (Platform.isWindows) {
        await Process.run('start', [path], runInShell: true);
      }
    } catch (e) {
      toast('Export failed: $e');
    }
  }

  Future<void> _aiAutoAssignAll() async {
    if (pid == null) { toast('Select a project first'); return; }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: AppColors.purpleLight, borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.smart_toy_outlined, color: AppColors.purple, size: 20),
          ),
          const SizedBox(width: 10),
          Text('AI Auto-Assign', style: GoogleFonts.outfit(fontWeight: FontWeight.w800)),
        ]),
        content: Text(
          'Gemini AI will analyse all unassigned tasks and match the best worker based on their trade, availability, and performance.\n\nProceed?',
          style: GoogleFonts.outfit(fontSize: 13.5, height: 1.5, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.auto_fix_high_rounded, size: 16),
            label: const Text('Auto-Assign'),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.purple, foregroundColor: Colors.white),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => ld = true);
    try {
      final result = await ApiService().aiAutoAssign(pid!, dryRun: false);
      final assignments = (result['assignments'] as List?) ?? [];
      final assigned = assignments.where((a) => a['assigned_worker_id'] != null).length;
      toast('AI assigned $assigned tasks successfully!');
      await _switchProject(pid);
    } catch (e) {
      toast('Auto-assign failed: $e');
      if (mounted) setState(() => ld = false);
    }
  }

  void _openNewTask() async {
    if (pid == null) { toast('Create a project first'); return; }
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
    final inProgress = tasks.where((t) => t['status'] == 'in_progress').length;
    final completed = tasks.where((t) => t['status'] == 'completed').length;
    final pending = tasks.where((t) => t['status'] == 'pending').length;

    return Scaffold(
      backgroundColor: AppColors.bgMain,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: AppColors.bgCard,
        elevation: 0,
        titleSpacing: 16,
        title: Text('Tasks', style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 18)),
        actions: [
          IconButton(
            onPressed: _exportTasks,
            icon: const Icon(Icons.download_rounded, size: 20),
            tooltip: 'Export',
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              onPressed: _aiAutoAssignAll,
              icon: const Icon(Icons.smart_toy_outlined, size: 17, color: AppColors.purple),
              label: Text('AI Assign', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.purple)),
              style: TextButton.styleFrom(
                backgroundColor: AppColors.purpleLight,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openNewTask,
        icon: const Icon(Icons.add),
        label: const Text('New Task'),
        backgroundColor: AppColors.accent,
      ),
      body: Column(children: [
        // ── Summary Cards ──
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(children: [
            Expanded(child: _summaryCard('In Progress', '$inProgress', AppColors.blue)),
            const SizedBox(width: 12),
            Expanded(child: _summaryCard('Completed', '$completed', AppColors.green)),
            const SizedBox(width: 12),
            Expanded(child: _summaryCard('Pending', '$pending', AppColors.yellow)),
          ]),
        ),
        const SizedBox(height: 14),

        // ── Search + Filters ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _buildFilterRow(),
        ),
        const SizedBox(height: 12),

        // ── Task List ──
        Expanded(
          child: ld
              ? const Center(child: CircularProgressIndicator())
              : _filtered.isEmpty
                  ? Center(child: Text('No tasks yet', style: GoogleFonts.outfit(color: AppColors.textMuted)))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                        itemCount: _filtered.length,
                        itemBuilder: (ctx, i) => _TaskCard(task: _filtered[i]),
                      ),
                    ),
        ),
      ]),
    );
  }

  Widget _summaryCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.w800, color: color)),
        const SizedBox(height: 2),
        Text(label, style: GoogleFonts.outfit(fontSize: 14, color: AppColors.textMuted)),
      ]),
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
            prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AppColors.textMuted),
            filled: true, fillColor: AppColors.bgCard,
            contentPadding: const EdgeInsets.symmetric(vertical: 0),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.accent)),
          ),
        ),
      ),
      const SizedBox(height: 8),
      // Filter chips row
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          _dropdown(['All', 'In Progress', 'Completed', 'Pending'], _statusFilter, (v) => setState(() => _statusFilter = v!), 'Status'),
          const SizedBox(width: 8),
          _dropdown(['All', 'Low', 'Medium', 'High'], _priorityFilter, (v) => setState(() => _priorityFilter = v!), 'Priority'),
          if (projects.length > 1) ...[
            const SizedBox(width: 8),
            _dropdown(
              projects.map<String>((p) => p['project_name'] as String).toList()..insert(0, 'All'),
              'All', (v) {
                if (v == 'All') {
                  _switchProject(null);
                } else {
                  final found = projects.firstWhere((p) => p['project_name'] == v, orElse: () => null);
                  if (found != null) _switchProject(found['project_id']);
                }
              }, 'Project',
            ),
          ],
        ]),
      ),
    ]);
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
        items: items.map((s) => DropdownMenuItem(value: s, child: Text('$hint: $s'))).toList(),
        onChanged: onChanged,
      ),
    );
  }
}

// ──────────────── Task Card ────────────────
class _TaskCard extends StatefulWidget {
  final Map task;
  const _TaskCard({required this.task});

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
        const Icon(Icons.calendar_today_outlined,
            size: 12, color: AppColors.textMuted),
        const SizedBox(width: 4),
        Text('No due date',
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
      toast('Due date updated');
    } catch (e) {
      toast('Failed to update due date');
    }
  }

  Future<void> _setStatus(String newStatus) async {
    if (newStatus == _status) return;
    try {
      await ApiService()
          .updateTask(widget.task['task_id'], {'status': newStatus});
      setState(() => _status = newStatus);
      widget.task['status'] = newStatus;
      toast('Status: ${newStatus.replaceAll('_', ' ')}');
    } catch (e) {
      toast('Failed to update status');
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
        ? const _SpinningOrIcon(
            icon: Icons.check_circle_rounded,
            color: AppColors.green,
            spin: false)
        : isInProgress
            ? const _SpinningOrIcon(
                icon: Icons.settings_rounded,
                color: AppColors.blue,
                spin: true)
            : const _SpinningOrIcon(
                icon: Icons.radio_button_unchecked_rounded,
                color: AppColors.textMuted,
                spin: false);

    final barColor =
        isCompleted ? AppColors.green : isInProgress ? AppColors.blue : AppColors.yellow;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => TaskDetailPage(task: widget.task))),
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
            const SizedBox(height: 10),
            // Worker + due date row
            Row(children: [
              if (workers.isNotEmpty) ...[
                initialsAvatar(workers.first['name'] ?? '?', radius: 11),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    workers.length > 1
                        ? '${workers.first['name'] ?? ''} +${workers.length - 1}'
                        : (workers.first['name'] ?? ''),
                    style: GoogleFonts.outfit(
                        fontSize: 14,
                        color: AppColors.accent,
                        fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ] else
                Text('Unassigned',
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
          _statusBtn('Pending', 'pending'),
          const SizedBox(width: 6),
          _statusBtn('In Progress', 'in_progress'),
          const SizedBox(width: 6),
          _statusBtn('Completed', 'completed'),
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
    switch (priority.toLowerCase()) {
      case 'high':
        bg = AppColors.redLight; fg = AppColors.red; break;
      case 'medium':
        bg = AppColors.yellowLight; fg = AppColors.yellow; break;
      default:
        bg = AppColors.blueLight; fg = AppColors.blue;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(priority[0].toUpperCase() + priority.substring(1),
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
  bool _loadingAI = false;
  List _aiWorkers = [];          // AI-suggested workers
  List _assignedWorkers = [];    // currently-assigned workers (mutable)
  List _projectWorkers = [];     // all workers in the project
  bool _sameProjectOnly = false; // restrict AI to same-project workers
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

  Future<void> _loadAI() async {
    final projectId = _task['project_id'] as int?;
    if (projectId == null) return;
    setState(() => _loadingAI = true);
    try {
      final result = await ApiService().aiAnalyzeTask(_task, projectId,
          sameProjectOnly: _sameProjectOnly);
      final suggestions = (result['suggested_workers'] as List?) ?? [];
      setState(() { _aiWorkers = suggestions; });
    } catch (e) {
      toast('AI error: $e');
    } finally {
      if (mounted) setState(() => _loadingAI = false);
    }
  }

  Future<void> _saveAssignments(Set<int> workerIds) async {
    try {
      await ApiService().updateTask(_task['task_id'], {
        'worker_ids': workerIds.toList(),
      });
      // 用完整工人池（项目工人 + AI 推荐）还原选中对象
      final pool = [..._projectWorkers, ..._aiWorkers];
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
      toast('${selected.length} worker(s) assigned');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      toast('Failed to assign: $e');
    }
  }

  Future<void> _unassign() async {
    try {
      await ApiService().updateTask(_task['task_id'], {'worker_ids': []});
      setState(() => _assignedWorkers = []);
      toast('All workers unassigned');
    } catch (e) {
      toast('Failed: $e');
    }
  }

  void _openAssignSheet() {
    // Load AI when the sheet opens
    if (_aiWorkers.isEmpty) _loadAI();

    // 当前已分配的 worker_id 集合（弹窗内可勾选/取消，保存时整体替换）
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
            decoration: const BoxDecoration(
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Assign Worker(s)', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800)),
                    Text(_task['task_name'] ?? '', style: GoogleFonts.outfit(fontSize: 14, color: AppColors.textMuted), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ]),
                ),
                // Same-project-only toggle
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: SwitchListTile(
                    value: _sameProjectOnly,
                    onChanged: (v) {
                      setState(() => _sameProjectOnly = v);
                      setS(() {});
                      if (_aiWorkers.isNotEmpty) _loadAI();
                    },
                    activeThumbColor: AppColors.purple,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    title: Text('仅限同项目', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700)),
                    subtitle: Text('AI 仅推荐绑定到当前项目的工人', style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textMuted)),
                  ),
                ),
                // AI section
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF7C3AED), Color(0xFF9F67FF)],
                        begin: Alignment.topLeft, end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(children: [
                      const Icon(Icons.smart_toy_outlined, color: Colors.white, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('AI Recommendations', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                          Text('Gemini matches workers by trade, attendance & performance', style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13)),
                        ]),
                      ),
                      if (_loadingAI)
                        const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      else if (_aiWorkers.isEmpty)
                        TextButton(
                          onPressed: () async { await _loadAI(); setS(() {}); },
                          style: TextButton.styleFrom(foregroundColor: Colors.white, backgroundColor: Colors.white24, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                          child: Text('Analyse', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700)),
                        ),
                    ]),
                  ),
                ),
                const SizedBox(height: 12),
                // AI suggestions (if loaded)
                if (_aiWorkers.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                    child: Row(children: [
                      Text('Top AI Picks', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.purple)),
                      const Spacer(),
                      TextButton(
                        onPressed: () {
                          setS(() {
                            for (final w in _aiWorkers.take(3)) {
                              final id = w['worker_id'] as int?;
                              if (id != null) selectedIds.add(id);
                            }
                          });
                        },
                        style: TextButton.styleFrom(foregroundColor: AppColors.purple, padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: const Size(0, 32)),
                        child: Text('Add All', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700)),
                      ),
                    ]),
                  ),
                  ..._aiWorkers.take(3).map((w) => _WorkerTile(
                    worker: w,
                    isAI: true,
                    selected: selectedIds.contains(w['worker_id']),
                    score: (w['score'] as num?)?.toDouble(),
                    reasons: (w['reasons'] as List?)?.cast<String>(),
                    onToggle: () {
                      setS(() {
                        final id = w['worker_id'] as int?;
                        if (id == null) return;
                        if (!selectedIds.add(id)) selectedIds.remove(id);
                      });
                    },
                  )),
                  const Divider(indent: 16, endIndent: 16),
                ],
                // All workers
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                  child: Text('All Workers', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: sc,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: _projectWorkers.length,
                    itemBuilder: (_, i) {
                      final w = _projectWorkers[i];
                      final alreadyAI = _aiWorkers.any((ai) => ai['worker_id'] == w['worker_id']);
                      if (alreadyAI) return const SizedBox.shrink();
                      return _WorkerTile(
                        worker: w,
                        isAI: false,
                        selected: selectedIds.contains(w['worker_id']),
                        onToggle: () {
                          setS(() {
                            final id = w['worker_id'] as int?;
                            if (id == null) return;
                            if (!selectedIds.add(id)) selectedIds.remove(id);
                          });
                        },
                      );
                    },
                  ),
                ),
                // Save bar (整体替换分配)
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                  decoration: const BoxDecoration(
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
        title: Text('Task Details', style: GoogleFonts.outfit(fontWeight: FontWeight.w800)),
        actions: [
          if (_assignedWorkers.isNotEmpty)
            TextButton(
              onPressed: _unassign,
              child: Text('Unassign', style: GoogleFonts.outfit(color: AppColors.red, fontWeight: FontWeight.w700, fontSize: 13)),
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
            const Icon(Icons.trending_up_rounded, size: 16, color: AppColors.blue),
            const SizedBox(width: 8),
            Text('Progress', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700)),
            const Spacer(),
            Text('${progress.toStringAsFixed(0)}%', style: GoogleFonts.outfit(fontWeight: FontWeight.w800, color: AppColors.blue, fontSize: 15)),
          ]),
          const SizedBox(height: 10),
          ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(
            value: progress / 100, minHeight: 10, backgroundColor: AppColors.blueLight,
            valueColor: const AlwaysStoppedAnimation(AppColors.blue),
          )),
        ])),

        // Due date
        if (t['due_date'] != null)
          sectionCard(margin: const EdgeInsets.only(bottom: 12), child: Row(children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(color: AppColors.yellowLight, borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.event_outlined, size: 16, color: AppColors.yellow),
            ),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Due Date', style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
              Text(t['due_date'], style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 14)),
            ]),
          ])),

        // Assigned worker card
        sectionCard(margin: const EdgeInsets.only(bottom: 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.person_outline_rounded, size: 16, color: AppColors.textMuted),
            const SizedBox(width: 6),
            Text('Assigned Worker', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
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
                const Icon(Icons.check_circle_rounded, color: AppColors.green, size: 20),
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
                  child: const Icon(Icons.person_add_outlined, color: AppColors.textMuted, size: 20),
                ),
                const SizedBox(width: 12),
                Text('No worker assigned yet', style: GoogleFonts.outfit(color: AppColors.textMuted, fontSize: 13)),
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
                _assignedWorkers.isNotEmpty ? 'Change Assignment' : 'Assign Worker (AI)',
                style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 13),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.purple,
                side: const BorderSide(color: AppColors.purple),
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
  final bool isAI;
  final bool selected;
  final double? score;
  final List<String>? reasons;
  final VoidCallback onToggle;
  const _WorkerTile({required this.worker, required this.isAI, required this.selected, required this.onToggle, this.score, this.reasons});

  @override
  Widget build(BuildContext context) {
    final name = worker['name'] as String? ?? '?';
    final trade = worker['trade'] as String? ?? 'General';
    final pct = score != null ? score! : 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isAI ? AppColors.purpleLight.withValues(alpha: 0.4) : AppColors.bgMain,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isAI ? AppColors.purple.withValues(alpha: 0.3) : AppColors.border),
      ),
      child: Column(children: [
        Row(children: [
          initialsAvatar(name, radius: 20),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(name, style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 14), overflow: TextOverflow.ellipsis)),
              if (isAI && score != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(color: AppColors.purple, borderRadius: BorderRadius.circular(8)),
                  child: Text('${pct.toInt()}% match', style: GoogleFonts.outfit(fontSize: 14, color: Colors.white, fontWeight: FontWeight.w700)),
                ),
            ]),
            Text(trade, style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textMuted)),
          ])),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: onToggle,
            style: ElevatedButton.styleFrom(
              backgroundColor: selected ? AppColors.green : (isAI ? AppColors.purple : AppColors.accent),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              minimumSize: const Size(70, 36),
            ),
            child: Text(selected ? '✓' : 'Add', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700)),
          ),
        ]),
        // AI reason chips
        if (isAI && reasons != null && reasons!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 6, runSpacing: 4,
              children: reasons!.map((r) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6), border: Border.all(color: AppColors.purple.withValues(alpha: 0.3))),
                child: Text(r, style: GoogleFonts.outfit(fontSize: 14, color: AppColors.purple)),
              )).toList(),
            ),
          ),
        ],
      ]),
    );
  }
}

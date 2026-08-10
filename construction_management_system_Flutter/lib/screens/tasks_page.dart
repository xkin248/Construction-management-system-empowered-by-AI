import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';

const _priorities = ['low', 'medium', 'high'];

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

  void _openNewTask() {
    if (pid == null) { toast('Create a project first'); return; }
    final title = TextEditingController();
    String priority = 'medium';
    DateTime? due;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        Future<void> pickDate() async {
          final d = await showDatePicker(context: ctx, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2035));
          if (d != null) setD(() => due = d);
        }
        final pad = MediaQuery.of(ctx).viewInsets.bottom;
        return Container(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + pad),
          decoration: const BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 36, height: 4,
                decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Text('New Task', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            const SizedBox(height: 16),
            Text('Task Title', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            TextField(
              controller: title,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'e.g. Foundation Pile Driving',
                hintStyle: GoogleFonts.outfit(color: AppColors.textMuted, fontSize: 13),
              ),
            ),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: priority,
                  decoration: const InputDecoration(labelText: 'Priority'),
                  items: _priorities.map((p) => DropdownMenuItem(value: p, child: Text(p[0].toUpperCase() + p.substring(1)))).toList(),
                  onChanged: (v) => setD(() => priority = v!),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: pickDate,
                  icon: const Icon(Icons.calendar_today_outlined, size: 16),
                  label: Text(due == null ? 'Due Date' : DateFormat('dd/MM/yy').format(due!),
                      style: GoogleFonts.outfit(fontSize: 13)),
                ),
              ),
            ]),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                if (title.text.trim().isEmpty) { toast('Enter a task title'); return; }
                try {
                  await ApiService().createTask({
                    'task_name': title.text.trim(), 'project_id': pid, 'priority': priority,
                    'status': 'pending', 'due_date': due?.toIso8601String().split('T').first,
                  });
                  if (ctx.mounted) Navigator.pop(ctx);
                  toast('Task created!');
                  _load();
                } on DioException catch (e) {
                  toast(e.message ?? 'Failed to create task');
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text('Create Task', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ]),
        );
      }),
    );
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
        Text(label, style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textMuted)),
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
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButton<String>(
        value: v,
        underline: const SizedBox(),
        isDense: true,
        style: GoogleFonts.outfit(fontSize: 12.5, color: AppColors.textPrimary, fontWeight: FontWeight.w600),
        items: items.map((s) => DropdownMenuItem(value: s, child: Text('$hint: $s'))).toList(),
        onChanged: onChanged,
      ),
    );
  }
}

// ──────────────── Task Card ────────────────
class _TaskCard extends StatelessWidget {
  final Map task;
  const _TaskCard({required this.task});

  @override
  Widget build(BuildContext context) {
    final status = task['status'] as String? ?? 'pending';
    final priority = task['priority'] as String? ?? 'medium';
    final worker = task['assigned_worker'] as Map?;
    final progress = (task['progress'] as num? ?? 0).toDouble();
    final isInProgress = status == 'in_progress';
    final isCompleted = status == 'completed';

    // Leading icon
    final leadIcon = isCompleted
        ? const _SpinningOrIcon(icon: Icons.check_circle_rounded, color: AppColors.green, spin: false)
        : isInProgress
            ? const _SpinningOrIcon(icon: Icons.settings_rounded, color: AppColors.blue, spin: true)
            : const _SpinningOrIcon(icon: Icons.radio_button_unchecked_rounded, color: AppColors.textMuted, spin: false);

    // Progress bar color
    final barColor = isCompleted ? AppColors.green : isInProgress ? AppColors.blue : AppColors.yellow;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => TaskDetailPage(task: task))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Title row
          Row(children: [
            leadIcon,
            const SizedBox(width: 10),
            Expanded(
              child: Text(task['task_name'] ?? '-',
                  style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                  overflow: TextOverflow.ellipsis),
            ),
            _PriorityBadge(priority: priority),
            const SizedBox(width: 8),
            Text('${progress.toStringAsFixed(0)}%',
                style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
          ]),
          if (task['project_name'] != null || (task['project'] != null)) ...[
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.only(left: 28),
              child: Text(task['project_name'] ?? task['project']?['project_name'] ?? '',
                  style: GoogleFonts.outfit(fontSize: 11.5, color: AppColors.textMuted)),
            ),
          ],
          const SizedBox(height: 10),
          // Progress bar
          Padding(
            padding: const EdgeInsets.only(left: 0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress / 100,
                minHeight: 6,
                backgroundColor: AppColors.border,
                valueColor: AlwaysStoppedAnimation(barColor),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Worker + due date row
          Row(children: [
            if (worker != null) ...[
              initialsAvatar(worker['name'] ?? '?', radius: 11),
              const SizedBox(width: 6),
              Text(worker['name'] ?? '',
                  style: GoogleFonts.outfit(fontSize: 12, color: AppColors.accent, fontWeight: FontWeight.w600)),
            ] else
              Text('Unassigned', style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textMuted)),
            const Spacer(),
            if (task['due_date'] != null) ...[
              const Icon(Icons.calendar_today_outlined, size: 12, color: AppColors.textMuted),
              const SizedBox(width: 4),
              Text(task['due_date'],
                  style: GoogleFonts.outfit(fontSize: 11.5, color: AppColors.textMuted)),
            ],
          ]),
        ]),
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
          style: GoogleFonts.outfit(fontSize: 10.5, fontWeight: FontWeight.w700, color: fg)),
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
  Map? _assignedWorker;          // currently-assigned worker (mutable)
  List _projectWorkers = [];     // all workers in the project
  late Map _task;

  @override
  void initState() {
    super.initState();
    _task = Map.from(widget.task);
    _assignedWorker = _task['assigned_worker'] as Map?;
    _loadWorkers();
  }

  Future<void> _loadWorkers() async {
    final projectId = _task['project_id'] as int?;
    if (projectId == null) return;
    try {
      _projectWorkers = await ApiService().getWorkers(pid: projectId);
    } catch (_) {}
  }

  Future<void> _loadAI() async {
    final projectId = _task['project_id'] as int?;
    if (projectId == null) return;
    setState(() => _loadingAI = true);
    try {
      final result = await ApiService().aiAnalyzeTask(_task, projectId);
      final suggestions = (result['suggested_workers'] as List?) ?? [];
      setState(() { _aiWorkers = suggestions; });
    } catch (e) {
      toast('AI error: $e');
    } finally {
      if (mounted) setState(() => _loadingAI = false);
    }
  }

  Future<void> _assignWorker(Map worker) async {
    try {
      await ApiService().updateTask(_task['task_id'], {
        'assigned_worker_id': worker['worker_id'],
      });
      setState(() => _assignedWorker = worker);
      toast('${worker['name']} assigned!');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      toast('Failed to assign: $e');
    }
  }

  Future<void> _unassign() async {
    try {
      await ApiService().updateTask(_task['task_id'], {'assigned_worker_id': null});
      setState(() => _assignedWorker = null);
      toast('Worker unassigned');
    } catch (e) {
      toast('Failed: $e');
    }
  }

  void _openAssignSheet() {
    // Load AI when the sheet opens
    if (_aiWorkers.isEmpty) _loadAI();

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
                    Text('Assign Worker', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800)),
                    Text(_task['task_name'] ?? '', style: GoogleFonts.outfit(fontSize: 12.5, color: AppColors.textMuted), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ]),
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
                          Text('Gemini matches workers by trade, attendance & performance', style: GoogleFonts.outfit(color: Colors.white70, fontSize: 11)),
                        ]),
                      ),
                      if (_loadingAI)
                        const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      else if (_aiWorkers.isEmpty)
                        TextButton(
                          onPressed: () async { await _loadAI(); setS(() {}); },
                          style: TextButton.styleFrom(foregroundColor: Colors.white, backgroundColor: Colors.white24, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                          child: Text('Analyse', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w700)),
                        ),
                    ]),
                  ),
                ),
                const SizedBox(height: 12),
                // AI suggestions (if loaded)
                if (_aiWorkers.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                    child: Text('Top AI Picks', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.purple)),
                  ),
                  ..._aiWorkers.take(3).map((w) => _WorkerTile(
                    worker: w,
                    isAI: true,
                    score: (w['score'] as num?)?.toDouble(),
                    reasons: (w['reasons'] as List?)?.cast<String>(),
                    onAssign: () { _assignWorker(w); setS(() {}); },
                  )),
                  const Divider(indent: 16, endIndent: 16),
                ],
                // All workers
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                  child: Text('All Workers', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
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
                        onAssign: () { _assignWorker(w); setS(() {}); },
                      );
                    },
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
          if (_assignedWorker != null)
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
              Text('Due Date', style: GoogleFonts.outfit(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
              Text(t['due_date'], style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 14)),
            ]),
          ])),

        // Assigned worker card
        sectionCard(margin: const EdgeInsets.only(bottom: 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.person_outline_rounded, size: 16, color: AppColors.textMuted),
            const SizedBox(width: 6),
            Text('Assigned Worker', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
          ]),
          const SizedBox(height: 12),
          if (_assignedWorker != null) ...[
            Row(children: [
              initialsAvatar(_assignedWorker!['name'] ?? '?', radius: 22),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_assignedWorker!['name'] ?? '-', style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 15)),
                Text(_assignedWorker!['trade'] ?? 'General Worker', style: GoogleFonts.outfit(color: AppColors.textMuted, fontSize: 12)),
              ])),
              const Icon(Icons.check_circle_rounded, color: AppColors.green, size: 20),
            ]),
            const SizedBox(height: 12),
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
                _assignedWorker != null ? Icons.swap_horiz_rounded : Icons.person_search_rounded,
                size: 18,
              ),
              label: Text(
                _assignedWorker != null ? 'Change Assignment' : 'Assign Worker (AI)',
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
  final double? score;
  final List<String>? reasons;
  final VoidCallback onAssign;
  const _WorkerTile({required this.worker, required this.isAI, required this.onAssign, this.score, this.reasons});

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
                  child: Text('${pct.toInt()}% match', style: GoogleFonts.outfit(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w700)),
                ),
            ]),
            Text(trade, style: GoogleFonts.outfit(fontSize: 11.5, color: AppColors.textMuted)),
          ])),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: onAssign,
            style: ElevatedButton.styleFrom(
              backgroundColor: isAI ? AppColors.purple : AppColors.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              minimumSize: const Size(70, 36),
            ),
            child: Text('Assign', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w700)),
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
                child: Text(r, style: GoogleFonts.outfit(fontSize: 10, color: AppColors.purple)),
              )).toList(),
            ),
          ),
        ],
      ]),
    );
  }
}

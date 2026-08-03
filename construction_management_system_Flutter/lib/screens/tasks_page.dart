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

  void _openNewTask() {
    if (pid == null) { toast('Create a project first'); return; }
    final title = TextEditingController();
    String priority = 'medium';
    DateTime? due;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        return AlertDialog(
          title: Text('New Task', style: GoogleFonts.outfit(fontWeight: FontWeight.w800)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(controller: title, decoration: const InputDecoration(labelText: 'Task Title', hintText: 'e.g. Foundation Pile Driving')),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: priority,
                    decoration: const InputDecoration(labelText: 'Priority'),
                    items: _priorities.map((p) => DropdownMenuItem(value: p, child: Text(p[0].toUpperCase() + p.substring(1)))).toList(),
                    onChanged: (v) => setD(() => priority = v!),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final d = await showDatePicker(context: ctx, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2035));
                      if (d != null) setD(() => due = d);
                    },
                    child: Text(due == null ? 'Due Date' : DateFormat('yyyy-MM-dd').format(due!),
                        style: GoogleFonts.outfit(fontSize: 13)),
                  ),
                ),
              ]),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (title.text.trim().isEmpty) { toast('Enter a task title'); return; }
                try {
                  await ApiService().createTask({
                    'task_name': title.text.trim(), 'project_id': pid, 'priority': priority,
                    'status': 'pending', 'due_date': due?.toIso8601String().split('T').first,
                  });
                  if (ctx.mounted) Navigator.pop(ctx);
                  toast('✅ Task created');
                  _load();
                } on DioException catch (e) {
                  toast(e.message ?? 'Failed to create task');
                }
              },
              child: const Text('Create Task'),
            ),
          ],
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

    return Column(children: [
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
    ]);
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
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        SizedBox(
          height: 40,
          width: 200,
          child: TextField(
            onChanged: (v) => setState(() => _searchQuery = v),
            decoration: InputDecoration(
              hintText: 'Search tasks...',
              hintStyle: GoogleFonts.outfit(fontSize: 12.5, color: AppColors.textMuted),
              prefixIcon: const Icon(Icons.search_rounded, size: 18, color: AppColors.textMuted),
              filled: true, fillColor: AppColors.bgCard,
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.accent)),
            ),
          ),
        ),
        _dropdown(['All', 'In Progress', 'Completed', 'Pending'], _statusFilter, (v) => setState(() => _statusFilter = v!), 'Status'),
        if (projects.length > 1)
          _dropdown(projects.map<String>((p) => p['project_name'] as String).toList()..insert(0, 'All'),
              'All', (v) {
            if (v == 'All') _switchProject(null);
            else {
              final found = projects.firstWhere((p) => p['project_name'] == v, orElse: () => null);
              if (found != null) _switchProject(found['project_id']);
            }
          }, 'Project'),
        _dropdown(['All', 'Low', 'Medium', 'High'], _priorityFilter, (v) => setState(() => _priorityFilter = v!), 'Priority'),
        ElevatedButton.icon(
          onPressed: _openNewTask,
          icon: const Icon(Icons.add, size: 16),
          label: const Text('New Task'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ],
    );
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
  double? matchScore;
  String? matchReason;

  @override
  void initState() {
    super.initState();
    _loadMatch();
  }

  Future<void> _loadMatch() async {
    final worker = widget.task['assigned_worker'];
    if (worker == null || worker['trade'] == null) return;
    try {
      final results = await ApiService().aiMatch(worker['trade'], widget.task['project_id']);
      final match = results.firstWhere((r) => r['worker_id'] == worker['worker_id'], orElse: () => null);
      if (match != null && mounted) {
        setState(() { matchScore = match['match_score']; matchReason = match['reason']; });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext c) {
    final t = widget.task;
    final worker = t['assigned_worker'];
    final progress = (t['progress'] as num? ?? 0).toDouble();
    return Scaffold(
      appBar: AppBar(title: Text('Task Details', style: GoogleFonts.outfit(fontWeight: FontWeight.w800))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [statusPill(t['status'] ?? 'pending'), const SizedBox(width: 8), statusPill(t['priority'] ?? 'medium')]),
        const SizedBox(height: 12),
        Text(t['task_name'] ?? '-',
            style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        if ((t['description'] as String? ?? '').isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(t['description'], style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 13.5, height: 1.4)),
        ],
        const SizedBox(height: 16),
        // Progress
        sectionCard(margin: const EdgeInsets.only(bottom: 10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Progress', style: GoogleFonts.outfit(fontSize: 12.5, fontWeight: FontWeight.w700)),
            Text('${progress.toStringAsFixed(0)}%', style: GoogleFonts.outfit(fontWeight: FontWeight.w800, color: AppColors.blue)),
          ]),
          const SizedBox(height: 8),
          ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(
            value: progress / 100, minHeight: 8, backgroundColor: AppColors.blueLight,
            valueColor: const AlwaysStoppedAnimation(AppColors.blue),
          )),
        ])),
        if (t['due_date'] != null)
          sectionCard(margin: const EdgeInsets.only(bottom: 10), child: Row(children: [
            const Icon(Icons.event_outlined, size: 16, color: AppColors.textMuted), const SizedBox(width: 8),
            Text('Due Date', style: GoogleFonts.outfit(fontSize: 12.5, color: AppColors.textSecondary)), const Spacer(),
            Text(t['due_date'], style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 12.5)),
          ])),
        if (worker != null)
          sectionCard(margin: const EdgeInsets.only(bottom: 10), child: Row(children: [
            initialsAvatar(worker['name'] ?? '?', radius: 18), const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(worker['name'] ?? '-', style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 13.5)),
              Text(worker['trade'] ?? '', style: GoogleFonts.outfit(color: AppColors.textMuted, fontSize: 11.5)),
            ])),
          ])),
        if (matchScore != null)
          sectionCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.smart_toy_outlined, size: 16, color: AppColors.purple), const SizedBox(width: 8),
              Text('AI Match Score', style: GoogleFonts.outfit(fontSize: 12.5, fontWeight: FontWeight.w700)), const Spacer(),
              Text('${(matchScore! * 100).toStringAsFixed(0)}%',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.w800, color: AppColors.purple)),
            ]),
            const SizedBox(height: 8),
            ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(
              value: matchScore, minHeight: 6, backgroundColor: AppColors.purpleLight,
              valueColor: const AlwaysStoppedAnimation(AppColors.purple),
            )),
            if (matchReason != null) ...[
              const SizedBox(height: 6),
              Text(matchReason!, style: GoogleFonts.outfit(fontSize: 11.5, color: AppColors.textMuted)),
            ],
          ])),
      ]),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../services/task_status_notifier.dart';
import '../utils/date_helper.dart';
import '../l10n/app_strings.dart';
import '../widgets/tasks/assign_worker_tile.dart';
import '../widgets/tasks/timeline_tile.dart';

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
  bool _autoAssigning = false;   // auto-assign request in flight
  bool _autoAssignSameProject = false; // restrict auto-assign to this project
  List _logs = [];               // task timeline entries (newest first)
  bool _logsLoading = true;      // timeline fetch in flight
  double _progressInput = 50;    // progress slider draft
  final _progressNoteCtrl = TextEditingController();

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
    final p = (_task['progress'] as num?)?.toDouble();
    if (p != null) _progressInput = p.clamp(0, 100).toDouble();
    _loadWorkers();
    _loadLogs();
  }

  @override
  void dispose() {
    _progressNoteCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadWorkers() async {
    try {
      _projectWorkers = await ApiService().getWorkers();
    } catch (_) {}
  }

  /// Fetch the task timeline (status/progress history), newest first.
  Future<void> _loadLogs() async {
    final tid = _task['task_id'];
    if (tid == null) return;
    try {
      final logs = await ApiService().getTaskLogs(tid);
      if (!mounted) return;
      setState(() {
        _logs = logs;
        _logsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _logsLoading = false);
    }
  }

  /// Push the draft progress (+optional note) to the backend and refresh.
  Future<void> _saveProgress() async {
    final tid = _task['task_id'];
    if (tid == null) return;
    final p = _progressInput.round().clamp(0, 100);
    final note = _progressNoteCtrl.text.trim();
    try {
      await ApiService().updateTask(tid, {
        'progress': p,
        if (note.isNotEmpty) 'note': note,
      });
      _progressNoteCtrl.clear();
      toast(AppStrings.t('tasks.progressSaved'));
      // Signal the main list so it refreshes instead of showing stale
      // progress (the list lives in an IndexedStack inside HomeShell and
      // does not re-run initState when this detail page is popped).
      TaskStatusNotifier.notify();
      await _refreshTaskFromServer();
      await _loadLogs();
    } catch (e) {
      toast(AppStrings.t('tasks.progressSaveFailed'));
    }
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
      TaskStatusNotifier.notify();
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
      TaskStatusNotifier.notify();
      toast(AppStrings.t('tasks.unassignAll'));
    } catch (e) {
      toast('${AppStrings.t('tasks.assignFailed')}: $e');
    }
  }

  /// Re-fetch this task from the server and sync its worker display.
  Future<void> _refreshTaskFromServer() async {
    final pid = _task['project_id'] as int?;
    final tid = _task['task_id'];
    if (pid == null || tid == null) return;
    try {
      final tasks = await ApiService().getTasks(pid);
      Map? fresh;
      for (final x in tasks) {
        if (x['task_id'] == tid) {
          fresh = Map.from(x);
          break;
        }
      }
      if (fresh == null || !mounted) return;
      List assigned = [];
      final raw = fresh['assigned_workers'];
      if (raw is List && raw.isNotEmpty) {
        assigned = raw.cast<Map>();
      } else {
        final single = fresh['assigned_worker'] as Map?;
        if (single != null) assigned = [single];
      }
      setState(() {
        _task = fresh!;
        _assignedWorkers = assigned;
      });
    } catch (_) {
      // Refresh is best-effort; keep showing the current (possibly stale) data.
    }
  }

  Future<void> _deleteTask() async {
    final tid = widget.task['task_id'];
    if (tid == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppStrings.t('tasks.deleteConfirm')),
        content: Text(AppStrings.t('tasks.deleteConfirmBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppStrings.t('common.cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.red),
            child: Text(AppStrings.t('common.delete')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ApiService().deleteTask(tid as int);
      toast(AppStrings.t('tasks.deleteSuccess'));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      toast('${AppStrings.t('tasks.deleteFailed')}: $e');
    }
  }

  Future<void> _autoAssign() async {
    if (_autoAssigning) return;
    final pid = _task['project_id'] as int?;
    final tid = _task['task_id'] as int?;
    if (pid == null || tid == null) {
      toast('Auto assign unavailable for this task');
      return;
    }
    setState(() => _autoAssigning = true);
    try {
      final result = await ApiService().aiAutoAssign(
            pid,
            taskIds: [tid],
            dryRun: false,
            sameProjectOnly: _autoAssignSameProject,
          );
      // Backend guards against mis-assignment: low-confidence/vague tasks are
      // skipped with a reason instead of being randomly assigned.
      Map? skipped;
      final assignments = result['assignments'];
      if (assignments is List && assignments.isNotEmpty) {
        for (final x in assignments) {
          if (x is Map && x['task_id'] == tid) {
            if (x['skipped'] == true) skipped = Map.from(x);
            break;
          }
        }
        skipped ??= (assignments.first is Map &&
                (assignments.first as Map)['skipped'] == true)
            ? Map.from(assignments.first as Map)
            : null;
      }
      if (skipped != null) {
        final reason = (skipped['skip_reason'] as String?) ??
            'task text is too vague or no matching trade worker is available';
        if (mounted) _showAutoAssignSkipped(reason);
        return;
      }
      await _refreshTaskFromServer();
      if (mounted) {
        toast('Auto assign done — worker refreshed');
      }
    } catch (e) {
      if (mounted) toast('Auto assign failed: $e');
    } finally {
      if (mounted) setState(() => _autoAssigning = false);
    }
  }

  void _showAutoAssignSkipped(String reason) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Not auto-assigned'),
        content: Text(
          '$reason\n\nEdit the task to select a Required Trade, or make the '
          'name/description more specific — Auto Assign will then match workers '
          'by trade and will never randomly assign.',
          style: GoogleFonts.inter(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
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
      backgroundColor: AppColors.transparent,
      builder: (_) => StatefulBuilder(builder: (ctx, setS) {
        return DraggableScrollableSheet(
          initialChildSize: 0.75,
          maxChildSize: 0.95,
          minChildSize: 0.4,
          builder: (_, sc) => Container(
            decoration: BoxDecoration(
              color: AppColors.bgCard,
              borderRadius: AppRadius.bSheet,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Handle bar
                Center(
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    width: 36, height: 4,
                    decoration: BoxDecoration(color: AppColors.border, borderRadius: AppRadius.rHair),
                  ),
                ),
                Expanded(
                  child: ListView(
                    controller: sc,
                    padding: const EdgeInsets.only(bottom: 16),
                    children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(AppStrings.t('tasks.assignWorkersTitle'), style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w800)),
                    Text(_task['task_name'] ?? '', style: GoogleFonts.inter(fontSize: 14, color: AppColors.textMuted), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ]),
                ),
                // All workers
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Text(AppStrings.t('tasks.allWorkers'), style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                ),
                ..._projectWorkers.map((w) => WorkerTile(
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
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
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
                        foregroundColor: AppColors.accentInk,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: AppRadius.rMd),
                      ),
                      child: Text('Save Assignment (${selectedIds.length})', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w800)),
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
        title: Text(AppStrings.t('tasks.taskDetails'), style: GoogleFonts.inter(fontWeight: FontWeight.w800)),
        actions: [
          if (_assignedWorkers.isNotEmpty)
            TextButton(
              onPressed: _unassign,
              child: Text(AppStrings.t('tasks.unassign'), style: GoogleFonts.inter(color: AppColors.red, fontWeight: FontWeight.w700, fontSize: 13)),
            ),
          IconButton(
            onPressed: _deleteTask,
            tooltip: AppStrings.t('common.delete'),
            icon: Icon(Icons.delete_outline_rounded, color: AppColors.red, size: 20),
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
            style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        if ((t['description'] as String? ?? '').isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(t['description'], style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 13.5, height: 1.5)),
        ],
        const SizedBox(height: 24),

        // Progress card
        sectionCard(margin: const EdgeInsets.only(bottom: 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.trending_up_rounded, size: 16, color: AppColors.blue),
            const SizedBox(width: 8),
            Text(AppStrings.t('tasks.progress'), style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700)),
            const Spacer(),
            Text('${progress.toStringAsFixed(0)}%', style: GoogleFonts.inter(fontWeight: FontWeight.w800, color: AppColors.blue, fontSize: 15)),
          ]),
          const SizedBox(height: 12),
          ClipRRect(borderRadius: AppRadius.rMd, child: LinearProgressIndicator(
            value: progress / 100, minHeight: 10, backgroundColor: AppColors.blueLight,
            valueColor: AlwaysStoppedAnimation(AppColors.blue),
          )),
        ])),

        // Progress update entry (only while the task is in progress)
        if (status == 'in_progress')
          sectionCard(margin: const EdgeInsets.only(bottom: 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.tune_rounded, size: 16, color: AppColors.blue),
              const SizedBox(width: 8),
              Text(AppStrings.t('tasks.updateProgress'), style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              Expanded(child: Slider(
                value: _progressInput,
                min: 0, max: 100, divisions: 20,
                label: '${_progressInput.round()}%',
                onChanged: (v) => setState(() => _progressInput = v),
              )),
              Text('${_progressInput.round()}%',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w800, color: AppColors.blue, fontSize: 14)),
            ]),
            TextField(
              controller: _progressNoteCtrl,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: AppStrings.t('tasks.progressNoteHint'),
                isDense: true,
                border: OutlineInputBorder(borderRadius: AppRadius.rMd),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(width: double.infinity, child: ElevatedButton(
              onPressed: _saveProgress,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.blue, foregroundColor: AppColors.accentInk,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: Text(AppStrings.t('tasks.saveProgress'),
                  style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13)),
            )),
          ])),

        // Timeline: automatic status/progress history
        sectionCard(margin: const EdgeInsets.only(bottom: 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.history_rounded, size: 16, color: AppColors.textMuted),
            const SizedBox(width: 8),
            Text(AppStrings.t('tasks.timeline'), style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 12),
          if (_logsLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
            ),
          if (!_logsLoading && _logs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(AppStrings.t('tasks.noTimeline'),
                  style: GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted)),
            ),
          ..._logs.asMap().entries.map((e) => TimelineTile(entry: e.value, isFirst: e.key == 0)),
        ])),

        // Due date
        if (t['due_date'] != null)
          sectionCard(margin: const EdgeInsets.only(bottom: 12), child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: AppColors.yellowLight, borderRadius: AppRadius.rMd),
              child: Icon(Icons.event_outlined, size: 16, color: AppColors.yellow),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(AppStrings.t('tasks.dueDate'), style: GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
                Text(DateHelper.tryFormatShort(t['due_date']),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14)),
              ]),
            ),
          ])),

        // Assigned worker card
        sectionCard(margin: const EdgeInsets.only(bottom: 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.person_outline_rounded, size: 16, color: AppColors.textMuted),
            const SizedBox(width: 8),
            Text(AppStrings.t('tasks.assignedWorker'), style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
          ]),
          const SizedBox(height: 12),
          if (_assignedWorkers.isNotEmpty) ...[
            ..._assignedWorkers.map((w) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(children: [
                initialsAvatar(w['name'] ?? '?', radius: 22),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(w['name'] ?? '-', style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 15)),
                  Text(w['trade'] ?? 'General Worker', style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 14)),
                ])),
                Icon(Icons.check_circle_rounded, color: AppColors.green, size: 20),
              ]),
            )),
            const SizedBox(height: 8),
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
                Text(AppStrings.t('tasks.noWorkerAssigned'), style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 13)),
              ]),
            ),
          // Auto Assign (AI suggestion) button
          if (!_autoAssigning) ...[
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _autoAssign,
                icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                label: const Text('Auto Assign Worker',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.accentInk,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: AppRadius.rMd),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(children: [
              Expanded(
                child: Text(AppStrings.t('tasks.autoAssignSameProject'),
                    style: GoogleFonts.inter(
                        fontSize: 12, color: AppColors.textSecondary)),
              ),
              SizedBox(
                height: 28,
                child: FittedBox(
                  child: Switch(
                    value: _autoAssignSameProject,
                    activeTrackColor: AppColors.green,
                    onChanged: (v) =>
                        setState(() => _autoAssignSameProject = v),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 8),
          ] else ...[
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: null,
                icon: SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentInk),
                ),
                label: const Text('Assigning…',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.accentInk,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: AppRadius.rMd),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
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
                style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.accent,
                side: BorderSide(color: AppColors.accent),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: AppRadius.rMd),
              ),
            ),
          ),
        ])),
      ]),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';
import '../services/api_service.dart';
import '../utils/date_helper.dart';
import '../l10n/app_strings.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/failure_state.dart';
import '../widgets/a11y.dart';

/// Worker-facing task detail page.
///
/// The worker task board used to render read-only tiles with no tap handler,
/// which left the whole start → progress → complete workflow unreachable.
/// This page closes that loop: it loads one fresh task record, exposes the
/// three allowed worker actions (start, submit progress, complete) against the
/// existing task API, and shows the task timeline for traceability.
class WorkerTaskDetailPage extends StatefulWidget {
  const WorkerTaskDetailPage({
    super.key,
    required this.taskId,
    this.initial,
    this.onChanged,
  });

  final int taskId;
  final Map<String, dynamic>? initial;
  final VoidCallback? onChanged;

  @override
  State<WorkerTaskDetailPage> createState() => _WorkerTaskDetailPageState();
}

class _WorkerTaskDetailPageState extends State<WorkerTaskDetailPage> {
  Map<String, dynamic>? _task;
  List _logs = [];
  bool _loading = true;
  bool _logsLoading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _task = widget.initial;
    _loading = widget.initial == null;
    _load();
  }

  String get _status => (_task?['status']?.toString() ?? 'pending').toLowerCase();

  int get _progress {
    final raw = _task?['progress'];
    if (raw is num) return raw.round().clamp(0, 100);
    return _status == 'completed' ? 100 : 0;
  }

  Future<void> _load() async {
    try {
      final task = await ApiService().getTask(widget.taskId);
      if (!mounted) return;
      setState(() {
        _task = Map<String, dynamic>.from(task);
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = widget.initial == null ? e.toString() : null;
      });
      if (widget.initial != null) toast('Refresh failed: $e');
    }
    await _loadLogs();
  }

  Future<void> _loadLogs() async {
    try {
      final logs = await ApiService().getTaskLogs(widget.taskId);
      if (!mounted) return;
      setState(() {
        _logs = logs;
        _logsLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _logsLoading = false);
    }
  }

  Future<void> _apply(Map<String, dynamic> payload, String okMsg) async {
    setState(() => _busy = true);
    try {
      await ApiService().updateTask(widget.taskId, payload);
      toast(okMsg);
      widget.onChanged?.call();
      await _load();
    } catch (e) {
      toast('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// pending -> in_progress
  Future<void> _startTask() => _apply(
        {'status': 'in_progress', 'note': 'Started by worker'},
        'Task started',
      );

  /// Progress-only update; the backend derives the status from the value.
  /// 100% is deliberately excluded here because completing a task requires a
  /// completion note and must go through [_completeTask] instead.
  Future<void> _submitProgress() async {
    var value = _progress.clamp(0, 99);
    final noteCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Submit Progress'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Progress: $value%',
                  style: GoogleFonts.inter(
                      fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              Slider(
                value: value.toDouble(),
                max: 99,
                divisions: 99,
                label: '$value%',
                onChanged: (v) => setLocal(() => value = v.round()),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: noteCtrl,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'What did you complete?',
                  hintText: 'e.g. Installed 12m of piping in block B',
                  border: OutlineInputBorder(borderRadius: AppRadius.rMd),
                ),
              ),
              const SizedBox(height: 8),
              Text('Use "Complete Task" when you reach 100%.',
                  style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted)),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            TextButton(
              onPressed: () {
                if (noteCtrl.text.trim().isEmpty) {
                  toast('A progress note is required');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              style: TextButton.styleFrom(foregroundColor: AppColors.accent),
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    await _apply(
      {'progress': value, 'note': noteCtrl.text.trim()},
      'Progress updated to $value%',
    );
  }

  /// in_progress -> completed (completion note is mandatory on both sides).
  Future<void> _completeTask() async {
    final noteCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Complete Task'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Describe the finished work. This note is stored with the task.',
                  style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary)),
              const SizedBox(height: 12),
              TextField(
                controller: noteCtrl,
                maxLines: 3,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Completion note (required)',
                  border: OutlineInputBorder(borderRadius: AppRadius.rMd),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            TextButton(
              onPressed: () {
                if (noteCtrl.text.trim().isEmpty) {
                  toast('A completion note is required');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              style: TextButton.styleFrom(foregroundColor: AppColors.green),
              child: const Text('Complete'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    await _apply(
      {
        'status': 'completed',
        'progress': 100,
        'completion_note': noteCtrl.text.trim(),
      },
      'Task completed',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.bgCard,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        surfaceTintColor: AppColors.transparent,
        shape: Border(bottom: BorderSide(color: AppColors.border)),
        centerTitle: false,
        title: Text(AppStrings.t('tasks.taskDetails'),
            style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _busy ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const SkeletonDetail()
          : _task == null
              ? FailureState(
                  error: _error,
                  title: _error == null ? 'Task not found' : null,
                  onRetry: _load,
                )
              : Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: AppBreakpoints.maxContentWidth),
                    child: RefreshIndicator(onRefresh: _load, child: _buildBody()),
                  ),
                ),
    );
  }

  Widget _buildBody() {
    final t = _task!;
    final priority = (t['priority']?.toString() ?? 'medium').toLowerCase();
    final part = t['part_section']?.toString() ?? 'General Section';
    final instructions = t['work_instructions']?.toString() ?? '';
    final description = t['description']?.toString() ?? '';
    final projectName = t['project_name']?.toString() ?? '';
    final due = t['due_date'];
    final pct = _progress;

    final pColor = _status == 'completed'
        ? AppColors.green
        : _status == 'in_progress'
            ? AppColors.blue
            : AppColors.yellow;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        sectionCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(t['task_name']?.toString() ?? 'Unnamed Task',
                    style: GoogleFonts.inter(
                        fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              ),
              const SizedBox(width: 8),
              semanticStatus(statusPill(_status), _status),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              _tag(Icons.layers_rounded, part, AppColors.accent),
              _tag(Icons.flag_rounded, priority.toUpperCase(), pColor),
              if (projectName.isNotEmpty) _tag(Icons.apartment_rounded, projectName, AppColors.blue),
              if (due != null)
                _tag(Icons.event_rounded,
                    'Due: ${DateHelper.tryFormatShort(due, fallback: due.toString().split(' ').first)}',
                    AppColors.textSecondary),
            ]),
            if (description.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(description,
                  style: GoogleFonts.inter(
                      fontSize: 14, height: 1.45, color: AppColors.textSecondary)),
            ],
          ]),
        ),
        const SizedBox(height: 16),

        sectionCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('Progress',
                  style: GoogleFonts.inter(
                      fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              const Spacer(),
              Text('$pct%',
                  style: GoogleFonts.inter(
                      fontSize: 14, fontWeight: FontWeight.w800, color: pColor)),
            ]),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: AppRadius.rSm,
              child: LinearProgressIndicator(
                value: pct / 100,
                minHeight: 8,
                backgroundColor: AppColors.border,
                valueColor: AlwaysStoppedAnimation<Color>(pColor),
              ),
            ),
            if (instructions.isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.blueLight,
                  borderRadius: AppRadius.rMd,
                  border: Border.all(color: AppColors.blue.withValues(alpha: 0.3)),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.lightbulb_circle_rounded, size: 16, color: AppColors.blue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(instructions,
                        style: GoogleFonts.inter(
                            fontSize: 13, height: 1.4, fontWeight: FontWeight.w600, color: AppColors.blue)),
                  ),
                ]),
              ),
            ],
            if ((t['completion_note']?.toString() ?? '').isNotEmpty) ...[
              const SizedBox(height: 14),
              Text('Completion note',
                  style: GoogleFonts.inter(
                      fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
              const SizedBox(height: 4),
              Text(t['completion_note'].toString(),
                  style: GoogleFonts.inter(fontSize: 13, color: AppColors.textPrimary, height: 1.4)),
            ],
          ]),
        ),
        const SizedBox(height: 16),

        _buildActions(),
        const SizedBox(height: 16),

        sectionCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Timeline',
                style: GoogleFonts.inter(
                    fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            if (_logsLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
              )
            else if (_logs.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('No activity recorded yet.',
                    style: GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted)),
              )
            else
              ..._logs.map((e) {
                final m = Map<String, dynamic>.from(e as Map);
                final from = (m['from_status'] ?? '').toString();
                final to = (m['to_status'] ?? '').toString();
                final note = (m['note'] ?? '').toString();
                final at = DateHelper.tryFormatShort(m['created_at'], fallback: '');
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.circle, size: 8, color: AppColors.accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(
                          from == to || from.isEmpty
                              ? to.replaceAll('_', ' ')
                              : '${from.replaceAll('_', ' ')} → ${to.replaceAll('_', ' ')}',
                          style: GoogleFonts.inter(
                              fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                        ),
                        if (note.isNotEmpty)
                          Text(note,
                              style: GoogleFonts.inter(fontSize: 12.5, color: AppColors.textSecondary, height: 1.35)),
                        if (at.isNotEmpty)
                          Text(at,
                              style: GoogleFonts.inter(fontSize: 11.5, color: AppColors.textMuted)),
                      ]),
                    ),
                  ]),
                );
              }),
          ]),
        ),
      ],
    );
  }

  Widget _buildActions() {
    if (_status == 'completed') {
      return sectionCard(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Icon(Icons.check_circle_rounded, color: AppColors.green, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text('This task is completed. Nothing left to submit.',
                style: GoogleFonts.inter(
                    fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          ),
        ]),
      );
    }

    final isPending = _status == 'pending';

    if (isPending) {
      return SizedBox(
        width: double.infinity,
        height: 50,
        child: ElevatedButton.icon(
          onPressed: _busy ? null : _startTask,
          icon: const Icon(Icons.play_arrow_rounded, size: 20),
          label: Text('Start Task',
              style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w800)),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.green,
            shape: RoundedRectangleBorder(borderRadius: AppRadius.rMd),
            elevation: 0,
          ),
        ),
      );
    }

    return Row(children: [
      Expanded(
        child: SizedBox(
          height: 46,
          child: OutlinedButton.icon(
            onPressed: _busy ? null : _submitProgress,
            icon: const Icon(Icons.trending_up_rounded, size: 18),
            label: const Text('Update Progress'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.accent,
              side: BorderSide(color: AppColors.accent.withValues(alpha: 0.5)),
              shape: RoundedRectangleBorder(borderRadius: AppRadius.rMd),
            ),
          ),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: SizedBox(
          height: 46,
          child: ElevatedButton.icon(
            onPressed: _busy ? null : _completeTask,
            icon: const Icon(Icons.check_rounded, size: 18),
            label: const Text('Complete Task'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.green,
              shape: RoundedRectangleBorder(borderRadius: AppRadius.rMd),
              elevation: 0,
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _tag(IconData icon, String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration:
            BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: AppRadius.rMd),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: GoogleFonts.inter(color: color, fontSize: 12.5, fontWeight: FontWeight.w700)),
        ]),
      );
}

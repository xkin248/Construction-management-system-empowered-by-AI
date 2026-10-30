import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../services/api_service.dart';
import '../../services/task_status_notifier.dart';
import '../../utils/date_helper.dart';
import '../../l10n/app_strings.dart';
import '../../widgets/a11y.dart';
import '../../screens/task_detail_page.dart';

// ──────────────── Task Card ────────────────
class TaskCard extends StatefulWidget {
  final Map task;
  final VoidCallback? onChanged;
  final bool inGrid;
  const TaskCard({
    super.key,
    required this.task,
    this.onChanged,
    this.inGrid = false,
  });

  @override
  State<TaskCard> createState() => TaskCardState();
}

class TaskCardState extends State<TaskCard> {
  late String _status;
  late String? _dueDate;

  @override
  void initState() {
    super.initState();
    _status = widget.task['status'] as String? ?? 'pending';
    _dueDate = widget.task['due_date'] as String?;
  }

  @override
  void didUpdateWidget(covariant TaskCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The parent reloads the task list after any status change (locally or
    // from another page via TaskStatusNotifier). The card State object is
    // reused by ListView/GridView, so sync our copies from the new task map;
    // otherwise the quick buttons keep showing the stale status.
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
        Flexible(
          child: Text(AppStrings.t('tasks.noDueDate'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted)),
        ),
      ]);
    }
    final parsed = DateTime.tryParse(_dueDate!);
    final display =
        parsed != null ? DateHelper.formatShort(parsed) : _dueDate!;
    final color = _dueColor();
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.calendar_today_outlined, size: 12, color: color),
      const SizedBox(width: 4),
      Flexible(
        child: Text(display,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
                fontSize: 13, fontWeight: FontWeight.w600, color: color)),
      ),
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
      TaskStatusNotifier.notify();
      toast(AppStrings.t('tasks.dueUpdated'));
    } catch (e) {
      toast(AppStrings.t('tasks.dueFailed'));
    }
  }

  Future<void> _setStatus(String newStatus) async {
    if (newStatus == _status) return;
    // Completing a task is a forward-only transition (the backend rejects
    // completed -> pending), so require an explicit confirmation first, and
    // the completion note is mandatory (the backend enforces it too).
    if (newStatus == 'completed') {
      final noteCtrl = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, _) => AlertDialog(
            title: Text(AppStrings.t('tasks.confirmCompleteTitle')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(AppStrings.t('tasks.confirmCompleteBody'),
                    style: GoogleFonts.inter(
                        fontSize: 13, color: AppColors.textSecondary)),
                const SizedBox(height: 12),
                TextField(
                  controller: noteCtrl,
                  autofocus: true,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: AppStrings.t('tasks.completionNoteLabel'),
                    hintText: AppStrings.t('tasks.completionNoteHint'),
                    border: OutlineInputBorder(borderRadius: AppRadius.rMd),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(AppStrings.t('common.cancel')),
              ),
              TextButton(
                onPressed: () {
                  if (noteCtrl.text.trim().isEmpty) {
                    toast(AppStrings.t('tasks.completionNoteRequired'));
                    return;
                  }
                  Navigator.pop(ctx, true);
                },
                style: TextButton.styleFrom(foregroundColor: AppColors.green),
                child: Text(AppStrings.t('common.confirm')),
              ),
            ],
          ),
        ),
      );
      if (ok != true || !mounted) return;
      try {
        await ApiService().updateTask(widget.task['task_id'], {
          'status': newStatus,
          'completion_note': noteCtrl.text.trim(),
        });
        setState(() => _status = newStatus);
        widget.task['status'] = newStatus;
        widget.onChanged?.call();
        TaskStatusNotifier.notify();
        toast(AppStrings.t('tasks.statusUpdated'));
      } catch (e) {
        toast(AppStrings.t('tasks.statusFailed'));
      }
      return;
    }
    try {
      await ApiService()
          .updateTask(widget.task['task_id'], {'status': newStatus});
      setState(() => _status = newStatus);
      widget.task['status'] = newStatus;
      widget.onChanged?.call();
      TaskStatusNotifier.notify();
      toast(AppStrings.t('tasks.statusUpdated'));
    } catch (e) {
      toast(AppStrings.t('tasks.statusFailed'));
    }
  }

  /// Reopen a completed task through the dedicated supervisor endpoint.
  ///
  /// `completed` is forward-only for [ApiService.updateTask] (the backend
  /// rejects the backward edge on PUT so a stray edit cannot undo a sign-off),
  /// therefore a mistaken completion needs this explicit, audited path: the
  /// dialog collects the mandatory reason that lands in the task timeline.
  Future<void> _reopenTask() async {
    final reasonCtrl = TextEditingController();
    var target = 'in_progress';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(AppStrings.t('tasks.reopenTitle')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(AppStrings.t('tasks.reopenBody'),
                  style: GoogleFonts.inter(
                      fontSize: 13, color: AppColors.textSecondary)),
              const SizedBox(height: 12),
              Text(AppStrings.t('tasks.reopenTargetLabel'),
                  style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 6),
              Row(children: [
                for (final opt in const ['in_progress', 'pending']) ...[
                  Expanded(
                    child: SizedBox(
                      height: 34,
                      child: ElevatedButton(
                        onPressed: () => setDialogState(() => target = opt),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: target == opt
                              ? AppColors.blue
                              : AppColors.border,
                          foregroundColor: target == opt
                              ? AppColors.onAccent
                              : AppColors.textMuted,
                          elevation: 0,
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                              borderRadius: AppRadius.rMd),
                        ),
                        child: Text(
                          opt == 'in_progress'
                              ? AppStrings.t('tasks.inProgress')
                              : AppStrings.t('tasks.pending'),
                          style: GoogleFonts.inter(
                              fontSize: 13, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ),
                  if (opt == 'in_progress') const SizedBox(width: 8),
                ],
              ]),
              const SizedBox(height: 12),
              TextField(
                controller: reasonCtrl,
                autofocus: true,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: AppStrings.t('tasks.reopenReasonLabel'),
                  hintText: AppStrings.t('tasks.reopenReasonHint'),
                  border: OutlineInputBorder(borderRadius: AppRadius.rMd),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(AppStrings.t('common.cancel')),
            ),
            TextButton(
              onPressed: () {
                if (reasonCtrl.text.trim().isEmpty) {
                  toast(AppStrings.t('tasks.reopenReasonRequired'));
                  return;
                }
                Navigator.pop(ctx, true);
              },
              style: TextButton.styleFrom(foregroundColor: AppColors.yellow),
              child: Text(AppStrings.t('common.confirm')),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final resp = await ApiService().reopenTask(
        widget.task['task_id'],
        reasonCtrl.text.trim(),
        targetStatus: target,
      );
      final newStatus = resp['to_status'] as String? ?? target;
      setState(() => _status = newStatus);
      widget.task['status'] = newStatus;
      if (resp['progress'] != null) widget.task['progress'] = resp['progress'];
      widget.onChanged?.call();
      TaskStatusNotifier.notify();
      toast(AppStrings.t('tasks.reopenDone'));
    } on DioException catch (e) {
      // 403 = not a supervisor; the backend is the authority here, so surface
      // the reason instead of a generic failure.
      toast(e.response?.statusCode == 403
          ? AppStrings.t('tasks.reopenSupervisorOnly')
          : AppStrings.t('tasks.reopenFailed'));
    } catch (e) {
      toast(AppStrings.t('tasks.reopenFailed'));
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
        borderRadius: AppRadius.rMd,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Navigable section (header + progress + worker/due) ──
        semanticTapTarget(
          label: (widget.task['task_name'] ?? 'Task').toString(),
          child: InkWell(
          borderRadius: AppRadius.rMd,
          onTap: () async {
            final changed = await Navigator.push<bool>(context,
                MaterialPageRoute(builder: (_) => TaskDetailPage(task: widget.task)));
            if (changed == true) widget.onChanged?.call();
          },
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Title row
            Row(children: [
              leadIcon,
              const SizedBox(width: 12),
              Expanded(
                child: Text(widget.task['task_name'] ?? '-',
                    style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary),
                    overflow: TextOverflow.ellipsis),
              ),
              _PriorityBadge(priority: priority),
              const SizedBox(width: 8),
              Text('${progress.toStringAsFixed(0)}%',
                  style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary)),
            ]),
            if (widget.task['project_name'] != null ||
                (widget.task['project'] != null)) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 24),
                child: Text(
                    widget.task['project_name'] ??
                        widget.task['project']?['project_name'] ??
                        '',
                    style: GoogleFonts.inter(
                        fontSize: 13, color: AppColors.textMuted)),
              ),
            ],
            const SizedBox(height: 12),
            // Progress bar
            ClipRRect(
              borderRadius: AppRadius.rMd,
              child: LinearProgressIndicator(
                value: progress / 100,
                minHeight: 6,
                backgroundColor: AppColors.border,
                valueColor: AlwaysStoppedAnimation(barColor),
              ),
            ),
            // Trade badge
            if (widget.task['trade'] != null) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 24),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.12),
                    borderRadius: AppRadius.rMd,
                  ),
                  child: Text(
                    (widget.task['trade'] as String)[0].toUpperCase() +
                        (widget.task['trade'] as String).substring(1),
                    style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.accent),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            // Worker + due date row
            Row(children: [
              if (workers.isNotEmpty) ...[
                initialsAvatar(workers.first['name'] ?? '?', radius: 11),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    workers.length > 1
                        ? '${workers.first['name'] ?? ''} +${workers.length - 1} more'
                        : (workers.first['name'] ?? ''),
                    style: GoogleFonts.inter(
                        fontSize: 14,
                        color: AppColors.accent,
                        fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ] else
                Text(AppStrings.t('tasks.unassigned'),
                    style:
                        GoogleFonts.inter(fontSize: 14, color: AppColors.textMuted)),
              const Spacer(),
              // Tap due date to quickly edit
              semanticTapTarget(
                label: 'Edit due date',
                child: GestureDetector(
                onTap: _editDueDate,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: _dueLabel(),
                ),
              )),
            ]),
          ]),
        )),
        const SizedBox(height: 12),
        // ── Status quick-toggle (does not navigate) ──
        // A completed task is forward-only for the normal status buttons, so
        // offering them would just produce a rejected request. Swap the row for
        // the audited reopen action instead.
        if (isCompleted)
          SizedBox(
            height: 32,
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _reopenTask,
              icon: const Icon(Icons.undo_rounded, size: 18),
              label: Text(AppStrings.t('tasks.reopen'),
                  style: GoogleFonts.inter(
                      fontSize: 13, fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.yellowLight,
                foregroundColor: AppColors.textPrimary,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: AppRadius.rMd),
              ),
            ),
          )
        else
          Row(children: [
            _statusBtn(AppStrings.t('tasks.pending'), 'pending'),
            const SizedBox(width: 8),
            _statusBtn(AppStrings.t('tasks.inProgress'), 'in_progress'),
            const SizedBox(width: 8),
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
        fg = active ? AppColors.onAccent : AppColors.green;
        break;
      case 'in_progress':
        bg = active
            ? AppColors.blue
            : AppColors.blueLight.withValues(alpha: 0.4);
        fg = active ? AppColors.onAccent : AppColors.blue;
        break;
      default:
        bg = active ? AppColors.textMuted : AppColors.border;
        fg = active ? AppColors.onAccent : AppColors.textMuted;
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
                borderRadius: AppRadius.rMd),
          ),
          child: Text(label,
              style: GoogleFonts.inter(
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: AppRadius.rMd),
      child: Text(label,
          style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: fg)),
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
  // Nullable on purpose: the controller (and its ticker) must only be created
  // from a live element. A `late final` initializer would run inside dispose()
  // when the widget never started spinning, and creating a ticker on an already
  // deactivated element throws "Looking up a deactivated widget's ancestor is
  // unsafe" (happens when the whole tree is destroyed on logout).
  AnimationController? _ctrl;

  // Same duration / repeat behaviour as before, created on first use.
  AnimationController get _controller =>
      _ctrl ??= AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();

  @override
  void dispose() {
    _ctrl?.dispose();
    _ctrl = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.spin) return Icon(widget.icon, size: 20, color: widget.color);
    return RotationTransition(
      turns: _controller,
      child: Icon(widget.icon, size: 20, color: widget.color),
    );
  }
}

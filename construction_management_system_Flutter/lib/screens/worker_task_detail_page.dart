import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../widgets/worker_ui.dart';
import '../theme/responsive.dart';
import '../services/api_service.dart';
import '../services/photo_capture.dart';

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
      });
    } catch (_) {
      // logs are best-effort; keep the page usable
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
  /// Progress-only update; the backend derives the status from the value.
  /// 100% is deliberately excluded here because completing a task requires a
  /// mandatory site photo and must go through [_completeTask] instead.
  Future<void> _submitProgress() async {
    var value = _progress.clamp(0, 99);
    final noteCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(wT(en: 'PROGRESS', ms: 'KEMAJUAN', zh: '\u66f4\u65b0\u8fdb\u5ea6'),
              style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w900)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('$value%',
                style: GoogleFonts.inter(
                    fontSize: 40, fontWeight: FontWeight.w900, color: AppColors.blue)),
            Slider(
              value: value.toDouble(),
              max: 99,
              divisions: 99,
              label: '$value%',
              onChanged: (v) => setLocal(() => value = v.round()),
            ),
            TextField(
              controller: noteCtrl,
              maxLines: 2,
              style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                labelText: wT(en: 'What next?', ms: 'Apa lagi?', zh: '\u505a\u4e86\u4ec0\u4e48\uff1f'),
                border: OutlineInputBorder(borderRadius: AppRadius.rMd),
              ),
            ),
          ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(wT(en: 'CANCEL', ms: 'BATAL', zh: '\u53d6\u6d88'),
                  style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(120, 56),
                backgroundColor: AppColors.blue,
                foregroundColor: AppColors.onAccent,
              ),
              child: Text(wT(en: 'SAVE', ms: 'SIMPAN', zh: '\u4fdd\u5b58'),
                  style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w900)),
            ),
          ],
        ),
      ),
    );
    final note = noteCtrl.text.trim();
    if (ok != true || !mounted) return;
    await _apply({
      'progress': value,
      'note': note.isEmpty ? 'Progress $value%' : note,
    }, wT(en: 'SAVED', ms: 'DISIMPAN', zh: '\u5df2\u4fdd\u5b58'));
  }

  /// in_progress -> completed (completion note is mandatory on both sides).
  ///
  /// With [resubmit] the task stays completed and only the evidence is
  /// replaced: the backend keeps the newest photo, refreshes the submission
  /// timestamp and deletes the previous file.
  /// Completes the task. The site photo is mandatory: the camera runs BEFORE
  /// the API call and a cancelled or failed capture aborts the submission, so a
  /// task can never be marked done without evidence.
  Future<void> _completeTask({bool resubmit = false}) async {
    final noteCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
            resubmit
                ? wT(en: 'NEW PHOTO', ms: 'FOTO BARU', zh: '\u91cd\u65b0\u62cd\u7167')
                : wT(en: 'PHOTO DONE', ms: 'FOTO SIAP', zh: '\u62cd\u7167\u5b8c\u6210'),
            style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w900)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(wT(en: 'What did you do?', ms: 'Apa sudah siap?', zh: '\u5b8c\u6210\u4e86\u4ec0\u4e48\uff1f'),
              style: GoogleFonts.inter(
                  fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
          const SizedBox(height: 10),
          TextField(
            controller: noteCtrl,
            maxLines: 2,
            autofocus: true,
            style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              labelText: wT(en: 'Note (needed)', ms: 'Nota (wajib)', zh: '\u5907\u6ce8\uff08\u5fc5\u586b\uff09'),
              border: OutlineInputBorder(borderRadius: AppRadius.rMd),
            ),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(wT(en: 'CANCEL', ms: 'BATAL', zh: '\u53d6\u6d88'),
                style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800)),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.photo_camera_rounded, size: 22),
            label: Text(wT(en: 'PHOTO', ms: 'FOTO', zh: '\u62cd\u7167'),
                style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w900)),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(140, 60),
              backgroundColor: AppColors.green,
              foregroundColor: AppColors.onAccent,
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final note = noteCtrl.text.trim();
    if (note.isEmpty) {
      toast(wT(en: 'NOTE NEEDED', ms: 'PERLU NOTA', zh: '\u9700\u8981\u5907\u6ce8'));
      return;
    }
    CapturedPhoto photo;
    try {
      photo = await PhotoCapture.takeEvidencePhoto();
    } on PhotoCaptureException catch (e) {
      toast(e.message);
      return;
    } catch (e) {
      toast('$e');
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await ApiService().completeTaskWithPhoto(
        widget.taskId,
        photoBase64: photo.base64,
        photoMimeType: photo.mimeType,
        completionNote: note,
      );
      toast(resubmit
          ? wT(en: 'PHOTO SAVED', ms: 'FOTO DISIMPAN', zh: '\u7167\u7247\u5df2\u66f4\u65b0')
          : wT(en: 'DONE', ms: 'SIAP', zh: '\u5df2\u5b8c\u6210'));
      widget.onChanged?.call();
      await _load();
    } catch (e) {
      toast('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgMain,
      appBar: AppBar(
        backgroundColor: AppColors.bgCard,
        elevation: 0,
        surfaceTintColor: AppColors.transparent,
        shape: Border(bottom: BorderSide(color: AppColors.border)),
        iconTheme: IconThemeData(color: AppColors.textPrimary),
        title: Text(
          wT(en: 'TASK', ms: 'TUGASAN', zh: '任务详情'),
          style: GoogleFonts.inter(
              fontSize: 17, fontWeight: FontWeight.w900, color: AppColors.textPrimary),
        ),
        actions: [
          IconButton(
            iconSize: 26,
            icon: Icon(Icons.refresh_rounded, color: AppColors.textSecondary),
            tooltip: wT(en: 'REFRESH', ms: 'MUAT SEMULA', zh: '刷新'),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  String _short(dynamic v) {
    final s = v?.toString() ?? '';
    return s.length > 16 ? s.substring(0, 16) : s;
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_task == null && _error != null) {
      return ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          WErrorHint(
            title: wT(en: 'NO SIGNAL', ms: 'TIADA ISYARAT', zh: '网络不通'),
            hint: wT(en: 'Check internet. Try again.', ms: 'Semak internet. Cuba lagi.', zh: '检查网络后再试'),
            onRetry: _load,
          ),
        ],
      );
    }

    final t = _task ?? const <String, dynamic>{};
    final color = wStatusColor(_status);
    final pct = _progress;
    final name = (t['task_name'] ?? t['name'] ?? '').toString();
    final desc = (t['description'] ?? '').toString().trim();
    final instructions = (t['instructions'] ?? '').toString().trim();

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: AppRadius.rLg,
            border: Border.all(color: AppColors.border),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14), shape: BoxShape.circle),
                child: Icon(wStatusIcon(_status), size: 30, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    wStatusLabel(_status),
                    style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: color,
                        letterSpacing: 0.6),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    name.isEmpty ? wT(en: 'TASK', ms: 'TUGASAN', zh: '任务') : name,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                        height: 1.2),
                  ),
                ]),
              ),
            ]),
            const SizedBox(height: 14),
            Text('$pct%',
                style: GoogleFonts.inter(
                    fontSize: 34, fontWeight: FontWeight.w900, color: color)),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: AppRadius.rSm,
              child: LinearProgressIndicator(
                value: (pct / 100).clamp(0.0, 1.0),
                minHeight: 12,
                backgroundColor: color.withValues(alpha: 0.15),
                color: color,
              ),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        _primaryActions(),
        if (desc.isNotEmpty) ...[
          const SizedBox(height: 14),
          _textCard(Icons.info_outline_rounded, desc),
        ],
        if (instructions.isNotEmpty) ...[
          const SizedBox(height: 10),
          _textCard(Icons.checklist_rounded, instructions),
        ],
        if (_logs.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text(wT(en: 'HISTORY', ms: 'SEJARAH', zh: '记录'),
              style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          ..._logs.take(5).map((raw) {
            final log = Map<String, dynamic>.from(raw as Map);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.circle, size: 12, color: AppColors.textMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    (log['note'] ?? log['progress'] ?? '').toString(),
                    style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                        height: 1.3),
                  ),
                ),
                const SizedBox(width: 8),
                Text(_short(log['created_at'] ?? log['timestamp']),
                    style: GoogleFonts.inter(
                        fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
              ]),
            );
          }),
        ],
      ],
    );
  }

  Widget _textCard(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: AppRadius.rMd,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 22, color: AppColors.textSecondary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text,
              style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                  height: 1.4)),
        ),
      ]),
    );
  }

  /// One dominant action per state; the photo button is the biggest target.
  Widget _primaryActions() {
    if (_status == 'completed') {
      return Column(children: [
        WBigAction(
          icon: Icons.check_rounded,
          label: wT(en: 'DONE', ms: 'SIAP', zh: '已完成'),
          color: AppColors.green,
          height: 96,
          onTap: null,
        ),
        const SizedBox(height: 10),
        WBigAction(
          icon: Icons.photo_camera_rounded,
          label: wT(en: 'NEW PHOTO', ms: 'FOTO BARU', zh: '重新拍照'),
          color: AppColors.blue,
          height: kWPrimaryTap,
          outlined: true,
          busy: _busy,
          onTap: () => _completeTask(resubmit: true),
        ),
      ]);
    }
    if (_status == 'in_progress') {
      return Column(children: [
        WBigAction(
          icon: Icons.photo_camera_rounded,
          label: wT(en: 'PHOTO DONE', ms: 'FOTO SIAP', zh: '拍照完成'),
          color: AppColors.green,
          height: 112,
          busy: _busy,
          onTap: () => _completeTask(),
        ),
        const SizedBox(height: 10),
        WBigAction(
          icon: Icons.trending_up_rounded,
          label: wT(en: 'PROGRESS', ms: 'KEMAJUAN', zh: '更新进度'),
          color: AppColors.blue,
          height: kWPrimaryTap,
          outlined: true,
          onTap: _busy ? null : _submitProgress,
        ),
      ]);
    }
    return WBigAction(
      icon: Icons.play_arrow_rounded,
      label: wT(en: 'START', ms: 'MULA', zh: '开始'),
      color: AppColors.green,
      height: 104,
      busy: _busy,
      onTap: _startTask,
    );
  }
}

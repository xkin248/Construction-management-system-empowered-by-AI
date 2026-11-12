import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/api_service.dart';
import '../services/photo_capture.dart';
import '../theme/app_theme.dart';
import '../widgets/app_button.dart';
import '../widgets/worker_live_badge.dart';
import '../widgets/worker_ui.dart';

/// Worker task detail rebuilt against the reference UI flow (Task Detail
/// screen): title block, information grid (project / assigned / due /
/// priority / required skill / supervisor / status), description, progress and
/// a sticky action bar.
///
/// Action set follows the reference: START TASK â†’ UPLOAD PROGRESS PHOTO â†’
/// MARK AS COMPLETED, with CANCEL always available. After the photo evidence is
/// accepted the screen shows "Pending Supervisor Review" â€” it must never show
/// "Completed" on the worker side, because completion is confirmed by the
/// supervisor, not by the worker who submitted it.
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
  DateTime? _lastUpdated;

  /// True once this session submitted the completion evidence. The backend has
  /// no separate "review" status, so the worker-facing copy is driven from the
  /// completed state plus this flag: the worker always reads "Pending Supervisor
  /// Review" and never "Completed".
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    _task = widget.initial;
    _loading = widget.initial == null;
    _load();
  }

  String get _status => wStatusKey(_task?['status']);
  bool get _isSubmittedState =>
      _submitted || _status == 'submitted' || _status == 'pending_review';
  bool get _isClosed => _status == 'completed' || _status == 'approved' || _status == 'verified';
  bool get _isRejected => _status == 'rejected';

  int get _progress {
    final raw = _task?['progress'];
    if (raw is num) return raw.round().clamp(0, 100);
    if (_isClosed) return 100;
    return 0;
  }

  Future<void> _load() async {
    try {
      final task = await ApiService().getTask(widget.taskId);
      if (!mounted) return;
      setState(() {
        _task = Map<String, dynamic>.from(task);
        _error = null;
        _loading = false;
        _lastUpdated = DateTime.now();
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
      setState(() => _logs = logs);
    } catch (_) {
      // timeline is best-effort: the page stays usable without it
    }
  }

  // â”€â”€ actions â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> _startTask() async {
    setState(() => _busy = true);
    try {
      await ApiService().updateTask(widget.taskId, {
        'status': 'in_progress',
        'note': 'Started by worker',
      });
      toast(wT(en: 'TASK STARTED', ms: 'TUGASAN DIMULA', zh: '任务已开始'));
      widget.onChanged?.call();
      await _load();
    } catch (e) {
      toast('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Progress update â€” same PUT endpoint, capped at 99% so that the only way to
  /// finish a task stays the photo-evidence flow.
  Future<void> _uploadProgress() async {
    var value = _progress.clamp(0, 99);
    CapturedPhoto? photoShot;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: AppRadius.rXl),
          title: Text(
            wT(en: 'PROGRESS PHOTO', ms: 'FOTO KEMAJUAN', zh: '进度照片'),
            style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('$value%',
                style: GoogleFonts.inter(
                    fontSize: 36,
                    fontWeight: FontWeight.w800,
                    color: AppColors.navy)),
            Slider(
              value: value.toDouble(),
              max: 99,
              divisions: 99,
              activeColor: AppColors.accentSolid,
              label: '$value%',
              onChanged: (v) => setLocal(() => value = v.round()),
            ),
            const SizedBox(height: 12),
            Row(children: [
                Icon(
                  photoShot == null
                      ? Icons.photo_camera_outlined
                      : Icons.check_circle_rounded,
                  size: 20,
                  color: photoShot == null ? AppColors.textMuted : AppColors.success,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    photoShot == null
                        ? wT(en: 'No photo yet', ms: 'Belum ada foto', zh: '尚未拍照')
                        : wT(en: 'Photo captured', ms: 'Foto diambil', zh: '已拍照'),
                    style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    try {
                      final shot = await PhotoCapture.takeEvidencePhoto();
                      setLocal(() => photoShot = shot);
                    } catch (e) {
                      toast('$e');
                    }
                  },
                  child: Text(wT(en: 'TAKE PHOTO', ms: 'AMBIL FOTO', zh: '拍照'),
                      style: GoogleFonts.inter(
                          fontSize: 13, fontWeight: FontWeight.w800)),
                ),
            ]),
          ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(wT(en: 'CANCEL', ms: 'BATAL', zh: '取消'),
                  style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
            ElevatedButton(
              onPressed: photoShot == null
                  ? null
                  : () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(110, 48),
                backgroundColor: AppColors.accentSolid,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: AppRadius.rMd),
              ),
              child: Text(wT(en: 'SAVE', ms: 'SIMPAN', zh: '保存'),
                  style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await ApiService().updateTask(widget.taskId, {
        'progress': value,
        if (photoShot != null) 'progress_photo_base64': photoShot!.base64,
      });
      toast(wT(en: 'PROGRESS SAVED', ms: 'KEMAJUAN DISIMPAN', zh: '进度已保存'));
      widget.onChanged?.call();
      await _load();
    } catch (e) {
      toast('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Camera first, preview second, submit last â€” a task can never close without
  /// on-site photo evidence.
  Future<void> _markCompleted() async {
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

    final confirmed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => _CompletionPreviewPage(photo: photo)),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await ApiService().completeTaskWithPhoto(
        widget.taskId,
        photoBase64: photo.base64,
        photoMimeType: photo.mimeType,
      );
      if (!mounted) return;
      setState(() => _submitted = true);
      toast(wT(
        en: 'SUBMITTED — PENDING SUPERVISOR REVIEW',
        ms: 'DIHANTAR — MENUNGGU SEMAKAN PENYELIA',
        zh: '已提交，等待监理审核',
      ));
      widget.onChanged?.call();
      await _load();
    } catch (e) {
      toast('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // â”€â”€ build â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgMain,
      appBar: AppBar(
        backgroundColor: AppColors.bgCard,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: Border(bottom: BorderSide(color: AppColors.border)),
        iconTheme: const IconThemeData(color: AppColors.navy),
        title: Text(
          wT(en: 'Task Details', ms: 'Butiran Tugasan', zh: '任务详情'),
          style: GoogleFonts.inter(
              fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
        ),
        actions: [
          IconButton(
            iconSize: 22,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: wT(en: 'Refresh', ms: 'Muat semula', zh: '刷新'),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _buildBody(),
      bottomNavigationBar: _loading ? null : SafeArea(child: _actionBar()),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_task == null && _error != null) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          WErrorHint(
            title: wT(en: 'NO SIGNAL', ms: 'TIADA ISYARAT', zh: '网络不通'),
            hint: wT(
                en: 'Check your connection and try again.',
                ms: 'Semak sambungan dan cuba lagi.',
                zh: '检查网络后重试'),
            onRetry: _load,
          ),
        ],
      );
    }

    final t = _task ?? const <String, dynamic>{};
    final project = t['project'] is Map ? t['project'] as Map : const {};
    final supervisor = project['supervisor'] is Map
        ? ((project['supervisor'] as Map)['full_name'] ?? '').toString()
        : ((t['assigned_worker'] is Map
                ? ((t['assigned_worker'] as Map)['full_name'] ?? '')
                : '')
            .toString());
    final name = (t['task_name'] ?? t['name'] ?? '').toString();
    final projectName = (t['project_name'] ?? project['project_name'] ?? '').toString();
    final due = _date(t['due_date']);
    final assigned = _date(t['started_at'] ?? t['created_at'] ?? t['assigned_date']);
    final desc = (t['description'] ?? '').toString().trim();
    final location = (project['location_address'] ?? t['work_location'] ?? '').toString().trim();
    final trade = (t['trade'] ?? t['required_skill'] ?? '').toString().trim();
    final photoUrl = (t['completion_photo_url'] ?? '').toString();
    final pct = _progress;
    final chipColor = _chipColor();

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
      children: [
        WorkerLiveBadge(
          loading: _loading || _busy,
          failed: false,
          lastUpdated: _lastUpdated,
          onRefresh: _load,
        ),
        const SizedBox(height: 12),

        // Title block: task name + project + status pill.
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.navy,
            borderRadius: AppRadius.rXl,
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(
                  name.isEmpty ? wT(en: 'Task', ms: 'Tugasan', zh: '任务') : name,
                  style: GoogleFonts.inter(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      height: 1.25),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: chipColor,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(_chipIcon(), size: 14, color: Colors.white),
                  const SizedBox(width: 5),
                  Text(_chipLabel(),
                      style: GoogleFonts.inter(
                          fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white)),
                ]),
              ),
            ]),
            if (projectName.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(projectName,
                  style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.78))),
            ],
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: (pct / 100).clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: Colors.white.withValues(alpha: 0.18),
                color: AppColors.accentSolid,
              ),
            ),
            const SizedBox(height: 6),
            Text('$pct% ${wT(en: 'progress', ms: 'kemajuan', zh: '进度')}',
                style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.75))),
          ]),
        ),
        const SizedBox(height: 14),

        if (_isSubmittedState && !_isClosed) _reviewBanner(),
        if (_isClosed) _reviewBanner(isClosed: true),
        if (_isRejected) _reviewBanner(isRejected: true),

        _card(
          title: wT(en: 'Details', ms: 'Butiran', zh: '任务信息'),
          child: Column(children: [
            _kv(Icons.business_center_outlined,
                wT(en: 'Project', ms: 'Projek', zh: '项目'), projectName),
            _kv(Icons.event_outlined,
                wT(en: 'Assigned date', ms: 'Tarikh ditugaskan', zh: '指派日期'), assigned),
            _kv(Icons.event_available_outlined,
                wT(en: 'Due date', ms: 'Tarikh akhir', zh: '截止日期'), due),
            _kv(Icons.flag_outlined,
                wT(en: 'Priority', ms: 'Keutamaan', zh: '优先级'), _priorityLabel(t['priority'])),
            _kv(Icons.workspace_premium_outlined,
                wT(en: 'Required skill', ms: 'Kemahiran', zh: '所需技能'), trade),
            _kv(Icons.person_outline_rounded,
                wT(en: 'Supervisor', ms: 'Penyelia', zh: '监理'), supervisor),
            _kv(Icons.place_outlined,
                wT(en: 'Work location', ms: 'Lokasi kerja', zh: '工作地点'), location,
                last: true),
          ]),
        ),
        const SizedBox(height: 12),

        _card(
          title: wT(en: 'Description', ms: 'Keterangan', zh: '说明'),
          child: Text(
            desc.isEmpty
                ? wT(en: 'No description provided.', ms: 'Tiada keterangan.', zh: '暂无说明')
                : desc,
            style: GoogleFonts.inter(
                fontSize: 14,
                height: 1.5,
                fontWeight: FontWeight.w500,
                color: desc.isEmpty ? AppColors.textMuted : AppColors.textPrimary),
          ),
        ),

        if (photoUrl.isNotEmpty) ...[
          const SizedBox(height: 12),
          _card(
            title: wT(en: 'Completion photo', ms: 'Foto penyiapan', zh: '完成照片'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ClipRRect(
                borderRadius: AppRadius.rMd,
                child: Image.network(
                  photoUrl,
                  height: 180,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    height: 80,
                    alignment: Alignment.center,
                    color: AppColors.bgMain,
                    child: Text(
                        wT(en: 'Photo not loaded', ms: 'Foto tidak dimuat', zh: '照片未加载'),
                        style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textMuted)),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                wT(
                    en: 'Kept separate from the attendance selfie.',
                    ms: 'Berasingan daripada selfie kehadiran.',
                    zh: '与考勤自拍分开保存。'),
                style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted),
              ),
            ]),
          ),
        ],

        if (_logs.isNotEmpty) ...[
          const SizedBox(height: 12),
          _card(
            title: wT(en: 'History', ms: 'Sejarah', zh: '记录'),
            child: Column(
              children: _logs.take(6).map((raw) {
                final log = Map<String, dynamic>.from(raw as Map);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Icon(Icons.circle, size: 7, color: AppColors.textMuted),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        (log['note'] ?? log['to_status'] ?? log['progress'] ?? '').toString(),
                        style: GoogleFonts.inter(
                            fontSize: 13,
                            height: 1.35,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textSecondary),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(_date(log['created_at']),
                        style: GoogleFonts.inter(
                            fontSize: 11, color: AppColors.textMuted)),
                  ]),
                );
              }).toList(),
            ),
          ),
        ],
      ],
    );
  }

  // â”€â”€ pieces â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _card({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: AppRadius.rLg,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppColors.textMuted,
                letterSpacing: 0.7)),
        const SizedBox(height: 10),
        child,
      ]),
    );
  }

  Widget _kv(IconData icon, String label, String value, {bool last = false}) {
    final v = value.trim();
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: AppColors.textMuted),
        const SizedBox(width: 10),
        SizedBox(
          width: 108,
          child: Text(label,
              style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary)),
        ),
        Expanded(
          child: Text(
            v.isEmpty ? '—' : v,
            style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                height: 1.35,
                color: v.isEmpty ? AppColors.textMuted : AppColors.textPrimary),
          ),
        ),
      ]),
    );
  }

  Widget _reviewBanner({bool isClosed = false, bool isRejected = false}) {
    final Color color;
    final IconData icon;
    final String title;
    final String body;
    if (isRejected) {
      color = AppColors.danger;
      icon = Icons.cancel_rounded;
      title = wT(en: 'Rejected by supervisor', ms: 'Ditolak penyelia', zh: '监理已拒绝');
      body = wT(
          en: 'Read the note, fix the work and submit again.',
          ms: 'Baca nota, baiki kerja dan hantar semula.',
          zh: '查看说明，整改后重新提交');
    } else if (isClosed) {
      color = AppColors.warning;
      icon = Icons.hourglass_top_rounded;
      title = wT(en: 'Pending Supervisor Review', ms: 'Menunggu semakan penyelia', zh: '等待监理审核');
      body = wT(
          en: 'Photo submitted. The supervisor confirms the task.',
          ms: 'Foto dihantar. Penyelia akan mengesahkan.',
          zh: '照片已提交，等待监理核实后生效');
    } else {
      color = AppColors.warning;
      icon = Icons.hourglass_top_rounded;
      title = wT(en: 'Pending Supervisor Review', ms: 'Menunggu semakan penyelia', zh: '等待监理审核');
      body = wT(
          en: 'Submitted. You can no longer edit this task.',
          ms: 'Dihantar. Tugasan tidak boleh diubah.',
          zh: '已提交，此任务不可再修改');
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: AppRadius.rLg,
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: GoogleFonts.inter(
                    fontSize: 14, fontWeight: FontWeight.w800, color: color)),
            const SizedBox(height: 3),
            Text(body,
                style: GoogleFonts.inter(
                    fontSize: 12.5, height: 1.35, color: AppColors.textSecondary)),
          ]),
        ),
      ]),
    );
  }

  Color _chipColor() {
    if (_isRejected) return AppColors.danger;
    if (_isClosed) return AppColors.warning;
    if (_status == 'in_progress') return AppColors.accentSolid;
    return AppColors.warning;
  }

  IconData _chipIcon() {
    if (_isRejected) return Icons.cancel_rounded;
    if (_isClosed || _isSubmittedState) return Icons.hourglass_top_rounded;
    if (_status == 'in_progress') return Icons.timelapse_rounded;
    return Icons.flag_rounded;
  }

  /// Worker-facing status wording: a submitted task reads "Pending Supervisor
  /// Review" â€” never "Completed".
  String _chipLabel() {
    if (_isRejected) return wT(en: 'REJECTED', ms: 'DITOLAK', zh: '已拒绝');
    if (_isClosed || _isSubmittedState) {
      return wT(en: 'PENDING REVIEW', ms: 'MENUNGGU SEMAKAN', zh: '待审核');
    }
    if (_status == 'in_progress') return wT(en: 'IN PROGRESS', ms: 'SEDANG KERJA', zh: '进行中');
    return wT(en: 'TO DO', ms: 'BELUM MULA', zh: '待办');
  }

  String _priorityLabel(dynamic raw) {
    final p = (raw ?? '').toString().toLowerCase();
    switch (p) {
      case 'high':
        return wT(en: 'High', ms: 'Tinggi', zh: '高');
      case 'low':
        return wT(en: 'Low', ms: 'Rendah', zh: '低');
      case 'medium':
        return wT(en: 'Medium', ms: 'Sederhana', zh: '中');
      default:
        return '—';
    }
  }

  String _date(dynamic raw) {
    final s = (raw ?? '').toString().trim();
    if (s.isEmpty) return '';
    try {
      final dt = DateTime.parse(s).toLocal();
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return s.length > 10 ? s.substring(0, 10) : s;
    }
  }

  /// Sticky action bar. The primary button only exists while the task is still
  /// open; once evidence is submitted the only action left is CANCEL (back).
  Widget _actionBar() {
    final open = !_isClosed && !_isSubmittedState && !_isRejected;
    final canStart = open && _status != 'in_progress';
    final canAct = open && _status == 'in_progress';

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (canStart)
          AppButton(
            label: wT(en: 'Start Task', ms: 'Mula Tugasan', zh: '开始任务'),
            icon: Icons.play_arrow_rounded,
            loading: _busy,
            loadingLabel: wT(en: 'Startingâ€¦', ms: 'Memulakanâ€¦', zh: '正在开始…'),
            onPressed: _busy ? null : _startTask,
            height: 52,
          ),
        if (canAct) ...[
          AppButton(
            label: wT(en: 'Upload Progress Photo', ms: 'Muat Naik Foto Kemajuan', zh: '上传进度照片'),
            icon: Icons.add_a_photo_outlined,
            tone: AppButtonTone.secondary,
            onPressed: _busy ? null : _uploadProgress,
            height: 50,
          ),
          const SizedBox(height: 10),
          AppButton(
            label: wT(en: 'Mark as Completed', ms: 'Tanda Selesai', zh: '标记完成'),
            icon: Icons.check_circle_outline_rounded,
            loading: _busy,
            loadingLabel: wT(en: 'Submittingâ€¦', ms: 'Menghantarâ€¦', zh: '正在提交…'),
            onPressed: _busy ? null : _markCompleted,
            height: 52,
          ),
        ],
        if (!canStart && !canAct) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
            decoration: BoxDecoration(
              color: AppColors.bgMain,
              borderRadius: AppRadius.rMd,
              border: Border.all(color: AppColors.border),
            ),
            child: Row(children: [
              Icon(_isRejected ? Icons.cancel_rounded : Icons.lock_outline_rounded,
                  size: 18,
                  color: _isRejected ? AppColors.danger : AppColors.textMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _isRejected
                      ? wT(en: 'Waiting for supervisor to reopen',
                          ms: 'Menunggu penyelia membuka semula',
                          zh: '等待监理重新打开')
                      : wT(en: 'No action available', ms: 'Tiada tindakan', zh: '暂无可用操作'),
                  style: GoogleFonts.inter(
                      fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                ),
              ),
            ]),
          ),
        ],
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).maybePop(),
            child: Text(
              wT(en: 'Cancel', ms: 'Batal', zh: '取消'),
              style: GoogleFonts.inter(
                  fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
            ),
          ),
        ),
      ]),
    );
  }
}

/// Full-screen preview of the just-taken completion photo plus the mandatory
/// note. Pops with the note string, or null when the worker backs out.
class _CompletionPreviewPage extends StatefulWidget {
  const _CompletionPreviewPage({required this.photo});

  final CapturedPhoto photo;

  @override
  State<_CompletionPreviewPage> createState() => _CompletionPreviewPageState();
}

class _CompletionPreviewPageState extends State<_CompletionPreviewPage> {
  @override
  Widget build(BuildContext context) {
    Uint8List? bytes;
    try {
      bytes = base64Decode(widget.photo.base64);
    } catch (_) {
      bytes = null;
    }
    return Scaffold(
      backgroundColor: AppColors.bgMain,
      appBar: AppBar(
        backgroundColor: AppColors.bgCard,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: Border(bottom: BorderSide(color: AppColors.border)),
        iconTheme: const IconThemeData(color: AppColors.navy),
        title: Text(
          wT(en: 'Check photo', ms: 'Semak foto', zh: '确认照片'),
          style: GoogleFonts.inter(
              fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
        children: [
          ClipRRect(
            borderRadius: AppRadius.rLg,
            child: bytes == null
                ? Container(
                    height: 220,
                    color: AppColors.bgCard,
                    alignment: Alignment.center,
                    child: Icon(Icons.broken_image_rounded,
                        size: 40, color: AppColors.textMuted),
                  )
                : Image.memory(bytes,
                    height: 320, width: double.infinity, fit: BoxFit.cover),
          ),
          const SizedBox(height: 8),
          Text(
            wT(
                en: 'Task photo — separate from the attendance selfie.',
                ms: 'Foto tugasan — berasingan daripada selfie kehadiran.',
                zh: '任务照片，与考勤自拍分开保存。'),
            style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted),
          ),
          const SizedBox(height: 20),
          AppButton(
            label: wT(en: 'Submit for Review', ms: 'Hantar untuk Semakan', zh: '提交审核'),
            icon: Icons.send_rounded,
            loading: false,
            onPressed: () => Navigator.of(context).pop(true),
            height: 52,
          ),
          const SizedBox(height: 10),
          AppButton(
            label: wT(en: 'Retake', ms: 'Ambil Semula', zh: '重拍'),
            icon: Icons.refresh_rounded,
            tone: AppButtonTone.secondary,
            onPressed: () => Navigator.of(context).pop(),
            height: 48,
          ),
        ],
      ),
    );
  }
}

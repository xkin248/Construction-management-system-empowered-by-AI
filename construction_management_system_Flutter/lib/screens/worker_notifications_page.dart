import 'package:flutter/material.dart';
import '../widgets/app_page_intro.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/api_service.dart';
import '../services/app_settings.dart';
import '../theme/app_theme.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/worker_live_badge.dart';
import '../widgets/worker_ui.dart';
import 'worker_attendance_page.dart';
import 'worker_tasks_page.dart';

/// Worker notifications (spec A8).
///
/// Reads the worker-only endpoint `/notifications/worker/{id}` (no backend
/// change). Each card carries a short title, a time slot and one next action.
class WorkerNotificationsPage extends StatefulWidget {
  const WorkerNotificationsPage({super.key});

  @override
  State<WorkerNotificationsPage> createState() => _WorkerNotificationsPageState();
}

class _WorkerNotificationsPageState extends State<WorkerNotificationsPage> {
  bool _loading = true;
  bool _failed = false;
  int? _workerId;
  List<Map<String, dynamic>> _items = [];
  DateTime? _lastUpdated;

  @override
  void initState() {
    super.initState();
    AppColors.darkMode.addListener(_rebuild);
    AppSettings.lang.addListener(_rebuild);
    _load();
  }

  @override
  void dispose() {
    AppColors.darkMode.removeListener(_rebuild);
    AppSettings.lang.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    setState(() {
      _loading = _items.isEmpty;
      _failed = false;
    });
    try {
      if (_workerId == null) {
        final me = await ApiService().me();
        final wid = me['worker_id'];
        _workerId = wid is num
            ? wid.toInt()
            : (me['id'] is num ? (me['id'] as num).toInt() : null);
      }
      if (_workerId == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final raw = await ApiService().getWorkerNotifications(_workerId!);
      final list = raw
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _items = list;
        _lastUpdated = DateTime.now();
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markAllRead() async {
    if (_workerId == null) return;
    try {
      await ApiService().workerMarkAllRead(_workerId!);
      toast(wT(en: 'ALL READ', ms: 'SEMUA DIBACA', zh: '已全部标记'));
      await _load();
    } catch (_) {
      toast(wT(en: 'FAILED', ms: 'GAGAL', zh: '操作失败'));
    }
  }

  /// The worker notification endpoint does not send a timestamp yet, so the
  /// slot is filled only when the field is actually present.
  String _timeOf(Map<String, dynamic> n) {
    final raw = n['created_at'] ?? n['sent_at'] ?? n['time'];
    if (raw == null) return '—';
    final d = DateTime.tryParse(raw.toString());
    if (d == null) return '—';
    final local = d.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.day}/${local.month} ${two(local.hour)}:${two(local.minute)}';
  }

  Widget _nextAction(Map<String, dynamic> n) {
    final type = (n['related_entity_type'] ?? '').toString().toLowerCase();
    if (type.contains('task')) {
      return _actionButton(
        label: wT(en: 'OPEN TASK', ms: 'BUKA TUGASAN', zh: '查看任务'),
        icon: Icons.checklist_rounded,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const WorkerTasksPage()),
        ),
      );
    }
    if (type.contains('attendance')) {
      return _actionButton(
        label: wT(en: 'CLOCK IN', ms: 'DAFTAR MASUK', zh: '去打卡'),
        icon: Icons.fingerprint_rounded,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const WorkerAttendancePage()),
        ),
      );
    }
    return _actionButton(
      label: wT(en: 'OK', ms: 'OK', zh: '知道了'),
      icon: Icons.done_rounded,
      onTap: _load,
    );
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 58,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: AppColors.accentSolid,
          borderRadius: AppRadius.rMd,
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 22, color: AppColors.onAccent),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                  fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.onAccent),
            ),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgMain,
      appBar: AppBar(
        title: Text(
          wT(en: 'NOTIFICATIONS', ms: 'PEMBERITAHUAN', zh: '通知'),
          style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            tooltip: wT(en: 'Mark all read', ms: 'Tanda semua dibaca', zh: '全部已读'),
            onPressed: _items.isEmpty ? null : _markAllRead,
            icon: const Icon(Icons.done_all_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          AppPageIntro(
            icon: Icons.notifications_active_rounded,
            enTitle: 'MY ALERTS',
            msTitle: 'MAKLUMAN SAYA',
            zhTitle: '我的通知',
            enSubtitle: 'Read important work updates',
            msSubtitle: 'Baca makluman kerja',
            zhSubtitle: '查看重要工作消息',
            worker: true,
          ),
          const SizedBox(height: 14),
                    WorkerLiveBadge(
            failed: _failed,
            loading: _loading,
            lastUpdated: _lastUpdated,
            onRefresh: _load,
          ),
          const SizedBox(height: 12),
          if (_loading)
            const SkeletonList()
          else if (_items.isEmpty)
            WEmpty(
              icon: Icons.notifications_none_rounded,
              title: wT(en: 'NO MESSAGES', ms: 'TIADA MESEJ', zh: '暂无通知'),
              actionLabel: wT(en: 'REFRESH', ms: 'MUAT SEMULA', zh: '刷新'),
              actionIcon: Icons.refresh_rounded,
              onAction: _load,
            )
          else
            for (final n in _items) ...[
              _notificationCard(n),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }

  Widget _notificationCard(Map<String, dynamic> n) {
    final title = (n['title'] ?? '').toString();
    final body = (n['content'] ?? n['body'] ?? n['message'] ?? '').toString();
    final unread = n['is_read'] == false;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: AppRadius.rLg,
        border: Border.all(
          color: unread ? AppColors.accentSolid : AppColors.border,
          width: unread ? 2 : 1,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(
            unread ? Icons.mark_email_unread_rounded : Icons.mark_email_read_rounded,
            size: 22,
            color: unread ? AppColors.accentSolid : AppColors.textMuted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title.isEmpty ? wT(en: 'Message', ms: 'Mesej', zh: '消息') : title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                  fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.textPrimary),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _timeOf(n),
            style: GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted),
          ),
        ]),
        if (body.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            body,
            style: GoogleFonts.inter(
                fontSize: 16, height: 1.35, color: AppColors.textSecondary),
          ),
        ],
        const SizedBox(height: 12),
        _nextAction(n),
      ]),
    );
  }
}

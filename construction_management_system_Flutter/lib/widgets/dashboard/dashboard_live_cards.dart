import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/app_settings.dart';
import '../../theme/app_theme.dart';
import '../supervisor/demo_badge.dart';

/// Live blocks of the supervisor dashboard (spec PART B3):
/// Live Project Status, Live Attendance, Today's Common Tasks and Alerts.
///
/// All four share the same shell so the dashboard reads as one grid on wide
/// screens and as a single column on phones.

String _t(String en, String zh, String ms) => AppSettings.t(en, zh, ms);

/// Shared card shell for the live blocks.
class LiveBlockCard extends StatelessWidget {
  const LiveBlockCard({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onViewAll,
    this.viewAllLabel,
    required this.children,
    this.footer,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onViewAll;
  final String? viewAllLabel;
  final List<Widget> children;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return sectionCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: AppColors.accentLight, borderRadius: AppRadius.rSm),
            child: Icon(icon, size: 16, color: AppColors.accentText),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                      fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              if (subtitle != null)
                Text(subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 11.5, color: AppColors.textMuted)),
            ]),
          ),
          if (onViewAll != null)
            TextButton(
              onPressed: onViewAll,
              style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
              child: Text(
                '${viewAllLabel ?? _t('View all', '查看全部', 'Lihat semua')} →',
                style: GoogleFonts.inter(
                    fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.accent),
              ),
            ),
        ]),
        const SizedBox(height: 12),
        ...children,
        if (footer != null) ...[
          const SizedBox(height: 12),
          Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 10),
          footer!,
        ],
      ]),
    );
  }
}

// ─────────────────────────── Live Project Status ───────────────────────────

/// Live Project Status: the top projects with completion, crew size and due
/// date. Tapping a row opens the project detail (spec PART B3 / B4).
class LiveProjectStatusCard extends StatelessWidget {
  const LiveProjectStatusCard({
    super.key,
    required this.projects,
    this.onOpen,
    this.onViewAll,
  });

  final List projects;
  final void Function(Map project)? onOpen;
  final VoidCallback? onViewAll;

  @override
  Widget build(BuildContext context) {
    final shown = projects.take(3).toList();
    return LiveBlockCard(
      icon: Icons.domain_rounded,
      title: _t('Live Project Status', '项目实时状态', 'Status Projek Langsung'),
      subtitle: _t('Progress and crew on site', '进度与在场工人', 'Kemajuan dan pekerja di tapak'),
      onViewAll: onViewAll,
      viewAllLabel: _t('Projects', '项目', 'Projek'),
      children: shown.isEmpty
          ? [
              _LiveEmpty(
                icon: Icons.folder_open_outlined,
                text: _t('No projects yet', '暂无项目', 'Tiada projek lagi'),
              ),
            ]
          : [
              for (var i = 0; i < shown.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                _ProjectLiveRow(project: shown[i] as Map, onTap: onOpen == null ? null : () => onOpen!(shown[i] as Map)),
              ],
            ],
    );
  }
}

class _ProjectLiveRow extends StatelessWidget {
  const _ProjectLiveRow({required this.project, this.onTap});

  final Map project;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final progress = (project['progress'] as num? ?? 0).toDouble().clamp(0, 100).toDouble();
    final status = (project['status'] ?? 'planning').toString();
    final workers = project['worker_count'] ?? project['tracked_workers'] ?? 0;
    final due = project['end_date'] ?? project['expected_end_date'];
    final pct = progress.round();

    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.rSm,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Row(children: [
                Flexible(
                  child: Text(
                    (project['project_name'] ?? '-').toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                        fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                  ),
                ),
                demoBadgeFor(project, ['project_name', 'location']),
              ]),
            ),
            const SizedBox(width: 8),
            statusPill(status),
          ]),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: AppRadius.rHair,
            child: LinearProgressIndicator(
              value: progress / 100,
              minHeight: 6,
              backgroundColor: AppColors.bgMain,
              valueColor: AlwaysStoppedAnimation(
                  progress >= 100 ? AppColors.green : AppColors.accent),
            ),
          ),
          const SizedBox(height: 5),
          Row(children: [
            Text('$pct%',
                style: GoogleFonts.inter(
                    fontSize: 11.5, fontWeight: FontWeight.w800, color: AppColors.textSecondary)),
            const SizedBox(width: 10),
            Icon(Icons.people_outline_rounded, size: 12, color: AppColors.textMuted),
            const SizedBox(width: 3),
            Text('$workers',
                style: GoogleFonts.inter(fontSize: 11.5, color: AppColors.textMuted)),
            const Spacer(),
            if (due != null)
              Text(
                _t('Due $due', '截止 $due', 'Tamat $due'),
                style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted),
              ),
          ]),
        ]),
      ),
    );
  }
}

// ───────────────────────────── Live Attendance ─────────────────────────────

/// Live Attendance: who is on site right now, with a per-worker button that
/// opens the on-site selfie full-screen (spec PART B3 + B8).
class LiveAttendancePanel extends StatelessWidget {
  const LiveAttendancePanel({
    super.key,
    required this.rows,
    this.onViewAll,
    this.onOpenPhoto,
    this.loadingWorkerId,
  });

  final List rows;
  final VoidCallback? onViewAll;

  /// Called with the attendance row; the page fetches the selfie detail and
  /// opens the viewer (the daily summary carries no photo URL).
  final void Function(Map row)? onOpenPhoto;
  final int? loadingWorkerId;

  @override
  Widget build(BuildContext context) {
    final present = rows
        .where((r) =>
            r is Map && ((r['status'] ?? r['today_status'] ?? 'absent').toString() != 'absent'))
        .toList();
    final shown = present.take(4).toList();

    return LiveBlockCard(
      icon: Icons.how_to_reg_rounded,
      title: _t('Live Attendance', '实时考勤', 'Kehadiran Langsung'),
      subtitle: _t('${present.length} on site today', '今日在场 ${present.length} 人',
          '${present.length} hadir hari ini'),
      onViewAll: onViewAll,
      viewAllLabel: _t('Monitor', '监控', 'Pantau'),
      children: shown.isEmpty
          ? [
              _LiveEmpty(
                icon: Icons.person_search_rounded,
                text: _t('Nobody has checked in yet', '还没有人打卡', 'Belum ada daftar masuk'),
              ),
            ]
          : [
              for (var i = 0; i < shown.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                _AttendanceLiveRow(
                  row: shown[i] as Map,
                  onPhoto: onOpenPhoto == null ? null : () => onOpenPhoto!(shown[i] as Map),
                  photoLoading: loadingWorkerId != null &&
                      loadingWorkerId == (shown[i] as Map)['id'],
                ),
              ],
            ],
    );
  }
}

class _AttendanceLiveRow extends StatelessWidget {
  const _AttendanceLiveRow({required this.row, this.onPhoto, this.photoLoading = false});

  final Map row;
  final VoidCallback? onPhoto;
  final bool photoLoading;

  @override
  Widget build(BuildContext context) {
    final name = (row['name'] ?? '?').toString();
    final status = (row['status'] ?? row['today_status'] ?? 'absent').toString();
    final project = row['project'] is Map ? row['project']['project_name'] : row['project_name'];

    String fmt(Object? raw) {
      if (raw == null) return '—';
      final parsed = DateTime.tryParse(raw.toString());
      if (parsed == null) return raw.toString();
      final local = parsed.toLocal();
      return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    }

    return Row(children: [
      initialsAvatar(name, radius: 16),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Flexible(
              child: Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                      fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            ),
            demoBadgeFor(row, ['name', 'email']),
          ]),
          Text(
            [
              if (project != null) project.toString(),
              '${_t('In', '上班', 'Masuk')} ${fmt(row['check_in_time'])}',
              '${_t('Out', '下班', 'Keluar')} ${fmt(row['check_out_time'])}',
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted),
          ),
        ]),
      ),
      const SizedBox(width: 8),
      statusPill(status),
      if (onPhoto != null) ...[
        const SizedBox(width: 4),
        Tooltip(
          message: _t('View check-in selfie', '查看打卡自拍', 'Lihat swafoto'),
          child: InkWell(
            onTap: photoLoading ? null : onPhoto,
            borderRadius: AppRadius.rSm,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.bgMain,
                borderRadius: AppRadius.rSm,
                border: Border.all(color: AppColors.border),
              ),
              child: photoLoading
                  ? const SizedBox(
                      width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(Icons.photo_camera_rounded, size: 14, color: AppColors.textSecondary),
            ),
          ),
        ),
      ],
    ]);
  }
}

// ────────────────────────── Today's Common Tasks ──────────────────────────

/// Today's Common Tasks: the three daily jobs with their status counters
/// (spec PART B3).
class CommonTasksTodayCard extends StatelessWidget {
  const CommonTasksTodayCard({
    super.key,
    required this.tasks,
    this.onViewAll,
    this.loading = false,
    this.error,
  });

  final List tasks;
  final VoidCallback? onViewAll;
  final bool loading;
  final Object? error;

  static String _kindLabel(String kind) {
    switch (kind) {
      case 'briefing':
        return _t('Morning briefing', '工地晨会', 'Taklimat pagi');
      case 'toolbox':
        return _t('Toolbox check', '工具箱检查', 'Semakan kotak alat');
      case 'housekeeping':
        return _t('Housekeeping', '场地清理', 'Kebersihan tapak');
      default:
        return kind.isEmpty ? _t('Daily job', '每日任务', 'Tugasan harian') : kind;
    }
  }

  static IconData _kindIcon(String kind) {
    switch (kind) {
      case 'briefing':
        return Icons.groups_rounded;
      case 'toolbox':
        return Icons.handyman_rounded;
      case 'housekeeping':
        return Icons.cleaning_services_rounded;
      default:
        return Icons.task_alt_rounded;
    }
  }

  static bool _done(Map t) {
    final s = (t['status'] ?? '').toString().toLowerCase();
    return s == 'done' || s == 'completed' || s == 'approved';
  }

  @override
  Widget build(BuildContext context) {
    final doneCount = tasks.where((t) => t is Map && _done(t)).length;
    final total = tasks.length;

    return LiveBlockCard(
      icon: Icons.checklist_rounded,
      title: _t("Today's Common Tasks", '今日通用任务', 'Tugasan Harian'),
      subtitle: loading
          ? _t('Loading…', '加载中…', 'Memuatkan…')
          : error != null
              ? _t('Could not load daily jobs', '无法加载每日任务', 'Gagal memuatkan')
              : _t('$doneCount of $total completed', '已完成 $doneCount/$total',
                  '$doneCount daripada $total selesai'),
      onViewAll: onViewAll,
      children: loading
          ? const [
              SizedBox(height: 90, child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
            ]
          : tasks.isEmpty
              ? [
                  _LiveEmpty(
                    icon: Icons.checklist_rounded,
                    text: error != null
                        ? _t('Daily jobs unavailable — retry later', '每日任务暂不可用，请稍后重试',
                            'Tugasan harian tidak tersedia')
                        : _t('No daily jobs for today', '今天没有每日任务', 'Tiada tugasan hari ini'),
                  ),
                ]
              : [
                  for (var i = 0; i < tasks.length; i++) ...[
                    if (i > 0) const SizedBox(height: 8),
                    _CommonTaskLiveRow(task: tasks[i] as Map),
                  ],
                ],
    );
  }
}

class _CommonTaskLiveRow extends StatelessWidget {
  const _CommonTaskLiveRow({required this.task});

  final Map task;

  @override
  Widget build(BuildContext context) {
    final kind = (task['task_kind'] ?? task['task_type'] ?? '').toString();
    final done = CommonTasksTodayCard._done(task);
    final status = (task['status'] ?? (done ? 'done' : 'pending')).toString();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: done ? AppColors.green.withValues(alpha: 0.08) : AppColors.bgMain,
        borderRadius: AppRadius.rSm,
        border: Border.all(
            color: done ? AppColors.green.withValues(alpha: 0.28) : AppColors.border),
      ),
      child: Row(children: [
        Icon(CommonTasksTodayCard._kindIcon(kind),
            size: 16, color: done ? AppColors.green : AppColors.textSecondary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            CommonTasksTodayCard._kindLabel(kind),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
                fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
          ),
        ),
        const SizedBox(width: 6),
        statusPill(status),
      ]),
    );
  }
}

// ──────────────────────────────── Alerts ────────────────────────────────

/// One row of the dashboard alert list.
class DashboardAlert {
  const DashboardAlert({
    required this.icon,
    required this.color,
    required this.title,
    this.detail,
    this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String? detail;
  final VoidCallback? onTap;
}

/// Alerts: overdue work, issues and attendance exceptions in one place.
class DashboardAlertsPanel extends StatelessWidget {
  const DashboardAlertsPanel({
    super.key,
    required this.alerts,
    this.onViewAll,
  });

  final List<DashboardAlert> alerts;
  final VoidCallback? onViewAll;

  @override
  Widget build(BuildContext context) {
    return LiveBlockCard(
      icon: Icons.notifications_active_rounded,
      title: _t('Alerts', '告警', 'Amaran'),
      subtitle: alerts.isEmpty
          ? _t('Nothing needs attention', '暂无需要处理的事项', 'Tiada perkara mendesak')
          : _t('${alerts.length} need attention', '${alerts.length} 项待处理',
              '${alerts.length} perlu tindakan'),
      onViewAll: onViewAll,
      viewAllLabel: _t('Inbox', '收件箱', 'Inbox'),
      children: alerts.isEmpty
          ? [
              _LiveEmpty(
                icon: Icons.verified_rounded,
                text: _t('All clear', '一切正常', 'Semua terkawal'),
              ),
            ]
          : [
              for (var i = 0; i < alerts.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                _AlertRow(alert: alerts[i]),
              ],
            ],
    );
  }
}

class _AlertRow extends StatelessWidget {
  const _AlertRow({required this.alert});

  final DashboardAlert alert;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: alert.onTap,
      borderRadius: AppRadius.rSm,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: alert.color.withValues(alpha: 0.08),
          borderRadius: AppRadius.rSm,
          border: Border.all(color: alert.color.withValues(alpha: 0.26)),
        ),
        child: Row(children: [
          Icon(alert.icon, size: 16, color: alert.color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(alert.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                      fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              if (alert.detail != null)
                Text(alert.detail!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 11, color: AppColors.textSecondary)),
            ]),
          ),
          if (alert.onTap != null)
            Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.textMuted),
        ]),
      ),
    );
  }
}

class _LiveEmpty extends StatelessWidget {
  const _LiveEmpty({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
      decoration: BoxDecoration(color: AppColors.bgMain, borderRadius: AppRadius.rSm),
      child: Column(children: [
        Icon(icon, size: 22, color: AppColors.textMuted),
        const SizedBox(height: 6),
        Text(text,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted)),
      ]),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../constants/trade_levels.dart';
import '../services/app_settings.dart';
import '../theme/app_theme.dart';
import 'a11y.dart';

/// One workforce row on the supervisor Workers list.
///
/// The card carries everything a supervisor needs before opening the profile:
/// who the worker is, the four-level trade band, the site they report to, how to
/// call them, and whether they are on site today (spec PART B6). It renders in
/// both a plain list (`inGrid: false`) and a wide-screen grid (`inGrid: true`),
/// so the parent only has to pick the sliver type.
class WorkerListCard extends StatelessWidget {
  const WorkerListCard({
    super.key,
    required this.worker,
    this.inGrid = false,
    this.onTap,
    this.onEdit,
  });

  final Map worker;
  final bool inGrid;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;

  String get _name => ((worker['name'] as String?) ?? '-').trim();

  String? get _phone {
    final p = ((worker['phone'] as String?) ?? '').trim();
    return p.isEmpty ? null : p;
  }

  String get _status =>
      ((worker['today_status'] as String?) ?? 'absent').toLowerCase();

  String get _levelLabel => TradeLevels.label(worker['trade'] as String?);

  String? get _projectName {
    final p = worker['project'];
    if (p is Map) {
      final n = (p['project_name'] as String?)?.trim();
      if (n != null && n.isNotEmpty) return n;
    }
    return null;
  }

  double? get _hoursToday {
    final h = worker['hours_today'];
    return h is num ? h.toDouble() : null;
  }

  String _statusLabel() {
    switch (_status) {
      case 'present':
        return AppSettings.t('On site', '在岗', 'Di tapak');
      case 'late':
        return AppSettings.t('Late', '迟到', 'Lewat');
      default:
        return AppSettings.t('Not on site', '不在岗', 'Tiada di tapak');
    }
  }

  /// 12-hour check-in / check-out stamp, or a dash when the worker has not
  /// clocked in yet. Comes from `/attendance/today`, so it is today-local.
  String _time(Map<String, dynamic>? src, String key) {
    final raw = src?[key];
    if (raw is! String || raw.trim().isEmpty) return '-';
    final d = DateTime.tryParse(raw);
    if (d == null) return '-';
    final local = d.toLocal();
    final h = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m ${local.hour < 12 ? 'AM' : 'PM'}';
  }

  @override
  Widget build(BuildContext context) {
    final hours = _hoursToday;
    final skill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.10),
        borderRadius: AppRadius.rPill,
      ),
      child: Text(
        _levelLabel,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.accentText,
          letterSpacing: 0.1,
        ),
      ),
    );

    return Material(
      color: AppColors.bgCard,
      borderRadius: AppRadius.rLg,
      child: InkWell(
        borderRadius: AppRadius.rLg,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
          decoration: BoxDecoration(
            borderRadius: AppRadius.rLg,
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              initialsAvatar(_name, radius: 21, seed: '${worker['worker_id']}'),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            _name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        semanticStatus(
                          statusPill(_status, label: _statusLabel()),
                          _status,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        skill,
                        if (hours != null) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.timer_outlined,
                              size: 12, color: AppColors.textMuted),
                          const SizedBox(width: 3),
                          Text(
                            '${hours.toStringAsFixed(hours == hours.roundToDouble() ? 0 : 1)}h',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                        if (_status == 'present' || _status == 'late') ...[
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              '${AppSettings.t('In', '上班', 'Masuk')} '
                              '${_time(worker.cast<String, dynamic>(), 'check_in_time')}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    _meta(
                      Icons.apartment_rounded,
                      _projectName ??
                          AppSettings.t(
                              'Unassigned', '未分配项目', 'Belum ditugaskan'),
                    ),
                    const SizedBox(height: 3),
                    _meta(
                      Icons.phone_outlined,
                      _phone ?? AppSettings.t('No phone', '无电话', 'Tiada telefon'),
                      strong: _phone != null,
                    ),
                  ],
                ),
              ),
              if (onEdit != null)
                semanticIconButton(
                  label: AppSettings.t('Edit worker', '编辑工人', 'Sunting pekerja'),
                  child: IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.edit_outlined,
                        size: 18, color: AppColors.textMuted),
                    onPressed: onEdit,
                    tooltip: AppSettings.t('Edit', '编辑', 'Sunting'),
                  ),
                )
              else if (onTap != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6, right: 4),
                  child: Icon(Icons.chevron_right_rounded,
                      size: 20, color: AppColors.textMuted),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _meta(IconData icon, String text, {bool strong = false}) => Row(
        children: [
          Icon(icon, size: 13, color: AppColors.textMuted),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 11.5,
                color: strong ? AppColors.textSecondary : AppColors.textMuted,
                fontWeight: strong ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        ],
      );
}

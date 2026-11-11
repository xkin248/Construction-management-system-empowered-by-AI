import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../constants/trade_levels.dart';
import '../../services/app_settings.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../a11y.dart';
import 'attendance_photo_viewer.dart';
import 'demo_badge.dart';

/// One row of the supervisor attendance monitor (spec PART B8).
///
/// Shows the worker, the check-in/check-out clock, the project, the GPS
/// distance against the geofence, the derived review state and an entry point
/// to the on-site selfie (tap the thumbnail, or the button, for the full-size
/// picture).
///
/// The day summary endpoint (`/attendance/today`) does not carry the selfie URL
/// nor the distances, so the card loads `/attendance/worker/{id}/today` once
/// for present workers. `Image`-based widgets cannot send the bearer header, so
/// [AttendancePhotoThumb] streams the bytes through the API client.
class AttendanceLogCard extends StatefulWidget {
  const AttendanceLogCard({
    super.key,
    required this.row,
    this.fenceRadiusM,
    this.showProject = true,
    this.inGrid = false,
    this.detail,
  });

  /// Row from `AttendanceSummary.rows` (worker + `today_status`).
  final Map row;

  /// Geofence radius of the worker's project, when known.
  final double? fenceRadiusM;
  final bool showProject;
  final bool inGrid;

  /// Pre-loaded `/attendance/worker/{id}/today` payload, if the parent already
  /// fetched it. When null the card fetches it itself.
  final Map? detail;

  @override
  State<AttendanceLogCard> createState() => _AttendanceLogCardState();
}

class _AttendanceLogCardState extends State<AttendanceLogCard> {
  Map? _detail;
  bool _loadingDetail = false;

  @override
  void initState() {
    super.initState();
    _detail = widget.detail;
    if (_detail == null && _hasLog) _fetchDetail();
  }

  bool get _hasLog => (widget.row['status'] ?? widget.row['today_status'] ?? 'absent') != 'absent';

  Future<void> _fetchDetail() async {
    final wid = widget.row['worker_id'];
    if (wid is! int) return;
    setState(() => _loadingDetail = true);
    try {
      final d = await ApiService().attendanceWorkerToday(wid);
      if (!mounted) return;
      setState(() {
        _detail = d;
        _loadingDetail = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingDetail = false);
    }
  }

  String _fmtTime(Object? raw) {
    if (raw == null) return '—';
    final s = raw.toString();
    try {
      final d = DateTime.parse(s).toLocal();
      return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return s.length >= 16 ? s.substring(11, 16) : s;
    }
  }

  String _fmtMeters(double? m) {
    if (m == null) return '—';
    return m >= 1000 ? '${(m / 1000).toStringAsFixed(2)} km' : '${m.round()} m';
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final status = (row['status'] ?? row['today_status'] ?? 'absent') as String;
    final name = (row['name'] ?? '?') as String;
    final trade = TradeLevels.label(row['trade'] as String?);
    final projectName = row['project'] is Map
        ? (row['project']['project_name'] as String? ?? '—')
        : (row['project_name'] as String? ?? '—');
    final hours = row['hours_today'];

    final inDist = _asDouble(_detail?['in_distance_m']);
    final outDist = _asDouble(_detail?['out_distance_m']);
    final outsideCount = (_detail?['out_of_fence_count'] ?? 0) as int;
    final radius = widget.fenceRadiusM;
    final worst = [inDist, outDist].whereType<double>().fold<double?>(null, (a, b) => a == null || b > a ? b : a);
    final bool? insideFence = (radius != null && worst != null) ? worst <= radius : null;
    final needsReview = (outsideCount > 0) || (insideFence == false);

    final inUrl = _detail?['in_photo_url'] as String?;
    final outUrl = _detail?['out_photo_url'] as String?;

    return sectionCard(
      margin: widget.inGrid ? EdgeInsets.zero : const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          initialsAvatar(name, radius: 19),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text(
                    name,
                    style: GoogleFonts.inter(
                        fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                demoBadgeFor(row, const ['name', 'email']),
              ]),
              Text(trade, style: GoogleFonts.inter(fontSize: 12.5, color: AppColors.textMuted)),
            ]),
          ),
          semanticStatus(statusPill(status), status),
        ]),
        if (widget.showProject) ...[
          const SizedBox(height: 8),
          Row(children: [
            Icon(Icons.place_outlined, size: 12, color: AppColors.textMuted),
            const SizedBox(width: 4),
            Expanded(
              child: Text(projectName,
                  style: GoogleFonts.inter(fontSize: 12.5, color: AppColors.textSecondary),
                  overflow: TextOverflow.ellipsis),
            ),
          ]),
        ],
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _timeChip(Icons.login_rounded,
                AppSettings.t('In', '上班', 'Masuk'), _fmtTime(row['check_in_time']), AppColors.green),
            _timeChip(Icons.logout_rounded,
                AppSettings.t('Out', '下班', 'Keluar'), _fmtTime(row['check_out_time']), AppColors.blue),
            if (hours != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: AppColors.accentLight, borderRadius: AppRadius.rSm),
                child: Text('${hours}h',
                    style: GoogleFonts.inter(
                        fontSize: 11.5, fontWeight: FontWeight.w800, color: AppColors.accentText)),
              ),
          ],
        ),
        const SizedBox(height: 10),
        // ── Geofence evidence ──
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Icon(Icons.gps_fixed_rounded,
              size: 14,
              color: insideFence == null
                  ? AppColors.textMuted
                  : (insideFence ? AppColors.green : AppColors.red)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _loadingDetail && _detail == null
                  ? AppSettings.t('Reading GPS evidence…', '正在读取定位证据…', 'Membaca bukti GPS…')
                  : _hasLog
                      ? AppSettings.t(
                          'GPS ${_fmtMeters(inDist)} in · ${_fmtMeters(outDist)} out'
                              '${radius != null ? ' · fence ${radius.round()} m' : ''}',
                          '定位 上班 ${_fmtMeters(inDist)} · 下班 ${_fmtMeters(outDist)}'
                              '${radius != null ? ' · 围栏 ${radius.round()} 米' : ''}',
                          'GPS masuk ${_fmtMeters(inDist)} · keluar ${_fmtMeters(outDist)}',
                        )
                      : AppSettings.t('No log today', '今日无打卡记录', 'Tiada rekod hari ini'),
              style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
          if (_hasLog)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: insideFence == false ? AppColors.redLight : AppColors.greenLight,
                borderRadius: AppRadius.rSm,
              ),
              child: Text(
                insideFence == null
                    ? AppSettings.t('Unverified', '待核验', 'Belum disahkan')
                    : insideFence
                        ? AppSettings.t('Inside fence', '围栏内', 'Dalam pagar')
                        : AppSettings.t('Outside fence', '围栏外', 'Luar pagar'),
                style: GoogleFonts.inter(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: insideFence == false ? AppColors.red : AppColors.green,
                ),
              ),
            ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Icon(needsReview ? Icons.fact_check_outlined : Icons.verified_outlined,
              size: 14, color: needsReview ? AppColors.yellow : AppColors.green),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              needsReview
                  ? AppSettings.t(
                      'Review needed${outsideCount > 0 ? ' · $outsideCount fence exit(s)' : ''}',
                      '需要审核${outsideCount > 0 ? ' · 越界 $outsideCount 次' : ''}',
                      'Perlu semakan${outsideCount > 0 ? ' · $outsideCount kali keluar pagar' : ''}',
                    )
                  : AppSettings.t('Fence check passed', '围栏校验通过', 'Semakan pagar lulus'),
              style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: needsReview ? AppColors.yellow : AppColors.green),
            ),
          ),
          if (_hasLog) ...[
            AttendancePhotoThumb(
              photoUrl: inUrl,
              label: AppSettings.t('In', '上班', 'Masuk'),
              size: 44,
            ),
            const SizedBox(width: 8),
            AttendancePhotoThumb(
              photoUrl: outUrl,
              label: AppSettings.t('Out', '下班', 'Keluar'),
              size: 44,
            ),
          ],
        ]),
      ]),
    );
  }

  double? _asDouble(Object? v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  Widget _timeChip(IconData icon, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: AppRadius.rSm,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text('$label $value',
            style: GoogleFonts.inter(
                fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
      ]),
    );
  }
}

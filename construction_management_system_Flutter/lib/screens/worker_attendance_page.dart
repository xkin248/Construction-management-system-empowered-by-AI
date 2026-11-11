import 'dart:async';
import '../widgets/app_page_intro.dart';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/api_service.dart';
import '../services/app_settings.dart';
import '../services/photo_capture.dart';
import '../theme/app_theme.dart';
import '../widgets/app_button.dart';
import '../widgets/worker_live_badge.dart';
import '../widgets/worker_ui.dart';

/// Attendance / clock-in, rebuilt to the current UI reference sheet.
///
/// Top-to-bottom order follows the reference: live clock + date, the assigned
/// site, a location panel (GPS accuracy + site map indicator), the geofence
/// verdict (Inside / Outside project area), the selfie step, then the single
/// orange Check In action.
///
/// Rules kept from BuildSmart_Button_Click_UI_Specification.md §5:
///  - the date and time are always device-local, refreshed every second,
///  - GPS permission + accuracy are shown explicitly, never hidden behind a
///    spinner,
///  - the selfie is live-camera only (gallery is not offered),
///  - Check In stays disabled until location is inside the fence, the selfie is
///    confirmed and the project is known; the button text says why it is off.
class WorkerAttendancePage extends StatefulWidget {
  const WorkerAttendancePage({super.key, this.embedded = false});

  /// When true the page is rendered inside the worker shell tab and therefore
  /// must not own a Scaffold / AppBar of its own.
  final bool embedded;

  @override
  State<WorkerAttendancePage> createState() => _WorkerAttendancePageState();
}

enum _Fault { none, gpsOff, permDenied, permForever, cameraDenied, network, outside, unknown }

class _WorkerAttendancePageState extends State<WorkerAttendancePage> {
  bool _booting = true;
  bool _locating = false;
  bool _submitting = false;

  int? _projectId;
  String _projectName = '';
  String _siteAddress = '';
  double? _centerLat;
  double? _centerLng;
  double _radius = 100;

  double? _lat;
  double? _lng;
  double? _accuracy;
  double? _distance;
  bool _inside = false;

  CapturedPhoto? _photo;
  _Fault _fault = _Fault.none;

  DateTime? _alreadyInAt;
  DateTime? _successAt;
  DateTime? _lastUpdated;
  DateTime _now = DateTime.now();
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    AppColors.darkMode.addListener(_rebuild);
    AppSettings.lang.addListener(_rebuild);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    _boot();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    AppColors.darkMode.removeListener(_rebuild);
    AppSettings.lang.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  String _two(int v) => v.toString().padLeft(2, '0');

  String _clock(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';

  static const List<String> _weekEn = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
  ];
  static const List<String> _weekMs = [
    'Isnin', 'Selasa', 'Rabu', 'Khamis', 'Jumaat', 'Sabtu', 'Ahad'
  ];
  static const List<String> _weekZh = [
    '星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'
  ];

  String get _todayLine {
    final i = _now.weekday - 1;
    final week = wT(en: _weekEn[i], ms: _weekMs[i], zh: _weekZh[i]);
    return '$week, ${_now.day} ${_monthName(_now.month)} ${_now.year}';
  }

  String _monthName(int m) {
    const en = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    const ms = ['Jan', 'Feb', 'Mac', 'Apr', 'Mei', 'Jun', 'Jul', 'Ogos', 'Sep', 'Okt', 'Nov', 'Dis'];
    const zh = ['1月', '2月', '3月', '4月', '5月', '6月', '7月', '8月', '9月', '10月', '11月', '12月'];
    return wT(en: en[m - 1], ms: ms[m - 1], zh: zh[m - 1]);
  }

  // ── data ─────────────────────────────────────────────────────────────────

  Future<void> _boot() async {
    setState(() {
      _booting = true;
      if (_fault != _Fault.outside) _fault = _Fault.none;
    });
    try {
      final me = await ApiService().me();
      final wid = me['worker_id'];
      final id = wid is num ? wid.toInt() : (me['id'] is num ? (me['id'] as num).toInt() : null);
      if (id != null) {
        try {
          final w = await ApiService().getWorker(id);
          final p = w['project'];
          if (p is Map) {
            _projectId = (p['project_id'] is num) ? (p['project_id'] as num).toInt() : null;
            _projectName = (p['project_name'] ?? '').toString();
            _siteAddress = (p['location_address'] ?? '').toString();
            final lat = p['center_lat'];
            final lng = p['center_lng'];
            final rad = p['fence_radius'];
            if (lat is num) _centerLat = lat.toDouble();
            if (lng is num) _centerLng = lng.toDouble();
            if (rad is num) _radius = rad.toDouble();
          }
        } catch (_) {
          // no worker row yet: the site card stays empty, clock-in stays blocked
        }
      }
      try {
        final today = await ApiService().workerTodayAttendance();
        if (today['checked_in'] == true) {
          final att = today['attendance'];
          final raw = att is Map ? (att['check_in_time'] ?? att['check_in']) : null;
          final parsed = raw == null ? null : DateTime.tryParse(raw.toString());
          _alreadyInAt = parsed?.toLocal() ?? DateTime.now();
        }
      } catch (_) {
        // attendance lookup is best-effort; the screen must still open
      }
      if (!mounted) return;
      setState(() => _lastUpdated = DateTime.now());
    } catch (_) {
      if (mounted) setState(() => _fault = _Fault.unknown);
    } finally {
      if (mounted) setState(() => _booting = false);
    }
  }

  Future<void> _locate() async {
    setState(() {
      _locating = true;
      if (_fault != _Fault.outside) _fault = _Fault.none;
    });
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        if (mounted) setState(() => _fault = _Fault.gpsOff);
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied) {
        if (mounted) setState(() => _fault = _Fault.permDenied);
        return;
      }
      if (perm == LocationPermission.deniedForever) {
        if (mounted) setState(() => _fault = _Fault.permForever);
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (!mounted) return;
      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
        _accuracy = pos.accuracy;
        if (_centerLat != null && _centerLng != null) {
          _distance = Geolocator.distanceBetween(
              pos.latitude, pos.longitude, _centerLat!, _centerLng!);
          _inside = _distance! <= _radius;
        }
        if (!_inside) _fault = _Fault.outside;
      });
    } catch (_) {
      if (mounted) setState(() => _fault = _Fault.unknown);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  /// Camera only — the gallery is never offered (spec §5: no upload of an old
  /// picture), and the shot must be confirmed before it counts.
  Future<void> _takeSelfie() async {
    setState(() => _fault = _Fault.none);
    CapturedPhoto shot;
    try {
      shot = await PhotoCapture.takeSelfie();
    } on PhotoCaptureException catch (e) {
      if (!mounted) return;
      final lower = e.message.toLowerCase();
      setState(() => _fault = (lower.contains('permission') || lower.contains('camera'))
          ? _Fault.cameraDenied
          : _Fault.unknown);
      return;
    } catch (_) {
      if (mounted) setState(() => _fault = _Fault.cameraDenied);
      return;
    }
    if (!mounted) return;

    final confirmed = await Navigator.of(context).push<CapturedPhoto>(
      MaterialPageRoute(builder: (_) => _SelfieReviewPage(photo: shot)),
    );
    if (confirmed == null || !mounted) return;
    setState(() => _photo = confirmed);
  }

  Future<void> _clockIn() async {
    if (_projectId == null || _lat == null || _lng == null || _photo == null) return;
    if (_submitting) return;
    setState(() {
      _submitting = true;
      if (_fault != _Fault.outside) _fault = _Fault.none;
    });
    try {
      final r = await ApiService().workerCheckIn(
        projectId: _projectId!,
        lat: _lat!,
        lng: _lng!,
        photoBase64: _photo!.base64,
        photoMimeType: _photo!.mimeType,
      );
      final att = r['attendance'];
      final raw = att is Map ? (att['check_in_time'] ?? att['check_in']) : null;
      final parsed = raw == null ? null : DateTime.tryParse(raw.toString());
      if (!mounted) return;
      // Success is only surfaced here — after the backend answered.
      setState(() => _successAt = parsed?.toLocal() ?? DateTime.now());
    } on DioException catch (e) {
      if (!mounted) return;
      final offline = e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.receiveTimeout;
      setState(() => _fault = offline ? _Fault.network : _Fault.unknown);
      if (!offline) toast(_serverMessage(e));
    } catch (_) {
      if (mounted) setState(() => _fault = _Fault.network);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _serverMessage(DioException e) {
    final data = e.response?.data;
    if (data is Map) {
      final d = data['detail'];
      if (d is String) return d;
      if (d is List && d.isNotEmpty) return d.first.toString();
    }
    return wT(en: 'NOT SUBMITTED', ms: 'TIDAK DIHANTAR', zh: '未提交');
  }

  // ── copy ─────────────────────────────────────────────────────────────────

  String _faultTitle(_Fault f) {
    switch (f) {
      case _Fault.gpsOff:
        return wT(en: 'GPS is off', ms: 'GPS dimatikan', zh: 'GPS 未开启');
      case _Fault.permDenied:
      case _Fault.permForever:
        return wT(en: 'Location blocked', ms: 'Lokasi disekat', zh: '定位权限被拒');
      case _Fault.cameraDenied:
        return wT(en: 'Camera blocked', ms: 'Kamera disekat', zh: '相机权限被拒');
      case _Fault.network:
        return wT(en: 'No internet', ms: 'Tiada internet', zh: '网络中断');
      case _Fault.outside:
        return wT(en: 'Outside project area', ms: 'Di luar kawasan projek', zh: '不在项目范围内');
      case _Fault.unknown:
        return wT(en: 'Something went wrong', ms: 'Ada masalah', zh: '出错了');
      case _Fault.none:
        return '';
    }
  }

  String _faultHint(_Fault f) {
    switch (f) {
      case _Fault.gpsOff:
        return wT(
            en: 'Turn on location, then press Get My Location.',
            ms: 'Hidupkan lokasi, tekan Dapatkan Lokasi.',
            zh: '请开启定位后重新获取位置。');
      case _Fault.permDenied:
        return wT(
            en: 'Allow location for this app, then try again.',
            ms: 'Benarkan lokasi untuk app ini, cuba lagi.',
            zh: '请允许本应用使用定位后重试。');
      case _Fault.permForever:
        return wT(
            en: 'Open system settings and allow location.',
            ms: 'Buka tetapan sistem dan benarkan lokasi.',
            zh: '请在系统设置中允许定位。');
      case _Fault.cameraDenied:
        return wT(
            en: 'Allow camera. A live selfie is required to clock in.',
            ms: 'Benarkan kamera. Selfie live diperlukan.',
            zh: '请允许相机，打卡需要现场自拍。');
      case _Fault.network:
        return wT(
            en: 'Your clock-in was NOT saved. Check internet and press Check In again.',
            ms: 'Daftar masuk TIDAK disimpan. Semak internet dan cuba lagi.',
            zh: '打卡未提交。请检查网络后重新打卡。');
      case _Fault.outside:
        return wT(
            en: 'Move closer to the site until the fence turns green.',
            ms: 'Dekatkan diri ke tapak sehingga pagar hijau.',
            zh: '请靠近工地，直至围栏状态变绿。');
      case _Fault.unknown:
        return wT(en: 'Please try again.', ms: 'Sila cuba lagi.', zh: '请重试。');
      case _Fault.none:
        return '';
    }
  }

  // ── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final body = RefreshIndicator(
      onRefresh: _boot,
      color: AppColors.accentSolid,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
        children: [
          AppPageIntro(
            icon: Icons.fingerprint_rounded,
            enTitle: 'CLOCK IN / OUT',
            msTitle: 'MASUK / KELUAR',
            zhTitle: '签到／签退',
            enSubtitle: 'GPS and live selfie are required',
            msSubtitle: 'GPS dan swafoto langsung diperlukan',
            zhSubtitle: '需要 GPS 定位和现场自拍',
            worker: true,
          ),
          const SizedBox(height: 14),
                    WorkerLiveBadge(
            failed: _fault == _Fault.unknown || _fault == _Fault.network,
            loading: _booting || _submitting,
            lastUpdated: _lastUpdated,
            onRefresh: _boot,
          ),
          const SizedBox(height: 12),
          _clockCard(),
          const SizedBox(height: 12),
          if (_successAt != null)
            _successCard()
          else ...[
            _siteCard(),
            const SizedBox(height: 12),
            _locationCard(),
            const SizedBox(height: 12),
            _fenceCard(),
            if (_fault != _Fault.none && _fault != _Fault.outside) ...[
              const SizedBox(height: 12),
              _faultCard(),
            ],
            const SizedBox(height: 12),
            _selfieCard(),
            const SizedBox(height: 16),
            _checkInArea(),
          ],
        ],
      ),
    );

    if (widget.embedded) return body;

    return Scaffold(
      backgroundColor: AppColors.bgMain,
      appBar: AppBar(
        backgroundColor: AppColors.bgCard,
        elevation: 0,
        surfaceTintColor: AppColors.transparent,
        shape: Border(bottom: BorderSide(color: AppColors.border)),
        iconTheme: IconThemeData(color: AppColors.textPrimary),
        title: Text(
          wT(en: 'ATTENDANCE', ms: 'KEDATANGAN', zh: '考勤'),
          style: GoogleFonts.inter(
              fontSize: 17, fontWeight: FontWeight.w900, color: AppColors.textPrimary),
        ),
      ),
      body: body,
    );
  }

  Widget _card({required Widget child, Color? border, EdgeInsets? padding}) {
    return Container(
      padding: padding ?? const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: AppRadius.rXl,
        border: Border.all(color: border ?? AppColors.border),
        boxShadow: AppShadows.sm,
      ),
      child: child,
    );
  }

  Widget _sectionLabel(String text) => Text(
        text.toUpperCase(),
        style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.9,
            color: AppColors.textMuted),
      );

  /// Live date + local time. The spec requires the *device* clock, so this is
  /// driven by a 1-second ticker rather than by the server.
  Widget _clockCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: AppRadius.rXl,
        boxShadow: AppShadows.accent(AppColors.navy, alpha: 0.22, blur: 16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.event_available_rounded, size: 16, color: AppColors.onAccentSoft),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _todayLine,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                  fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.onAccentSoft),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.onAccentFaint,
              borderRadius: AppRadius.rPill,
            ),
            child: Text(
              wT(en: 'LOCAL TIME', ms: 'MASA TEMPATAN', zh: '本地时间'),
              style: GoogleFonts.inter(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.6,
                  color: AppColors.onAccentSoft),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        Text(
          '${_two(_now.hour)}:${_two(_now.minute)}:${_two(_now.second)}',
          style: GoogleFonts.inter(
            fontSize: 42,
            fontWeight: FontWeight.w900,
            height: 1.05,
            letterSpacing: -1.2,
            color: AppColors.onAccent,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _alreadyInAt == null
              ? wT(en: 'Not clocked in yet', ms: 'Belum daftar masuk', zh: '尚未打卡')
              : wT(
                  en: 'Clocked in at ${_clock(_alreadyInAt!)}',
                  ms: 'Daftar masuk ${_clock(_alreadyInAt!)}',
                  zh: '已于 ${_clock(_alreadyInAt!)} 打卡'),
          style: GoogleFonts.inter(
              fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.onAccentMuted),
        ),
      ]),
    );
  }

  Widget _siteCard() {
    return _card(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.navy.withValues(alpha: 0.08),
            borderRadius: AppRadius.rMd,
          ),
          child: Icon(Icons.apartment_rounded, size: 21, color: AppColors.navy),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _sectionLabel(wT(en: 'Site', ms: 'Tapak', zh: '工地')),
            const SizedBox(height: 3),
            Text(
              _projectName.isEmpty
                  ? wT(en: 'No site assigned', ms: 'Tiada tapak', zh: '未分配项目')
                  : _projectName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                  fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.textPrimary),
            ),
            if (_siteAddress.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                _siteAddress,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                    fontSize: 12.5, height: 1.3, color: AppColors.textMuted),
              ),
            ],
            const SizedBox(height: 4),
            Text(
              '${wT(en: 'Allowed area', ms: 'Kawasan dibenar', zh: '允许范围')} · ${_radius.round()} m',
              style: GoogleFonts.inter(
                  fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
            ),
          ]),
        ),
      ]),
    );
  }

  /// Location panel: GPS accuracy + a schematic site map indicator.
  ///
  /// The map is drawn locally (no tile download) so it still means something
  /// when the worker has a weak signal — the dot and the ring are the point,
  /// not the street names.
  Widget _locationCard() {
    final hasFix = _lat != null;
    final tint = hasFix ? (_inside ? AppColors.success : AppColors.danger) : AppColors.textMuted;
    final accuracyLabel = _accuracy == null
        ? wT(en: 'Not measured', ms: 'Belum diukur', zh: '未获取')
        : '±${_accuracy!.toStringAsFixed(0)} m';
    final accuracyGood = _accuracy != null && _accuracy! <= 30;

    return _card(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _sectionLabel(wT(en: 'Location', ms: 'Lokasi', zh: '定位')),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.12),
              borderRadius: AppRadius.rPill,
              border: Border.all(color: tint.withValues(alpha: 0.35)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(hasFix ? Icons.gps_fixed_rounded : Icons.gps_off_rounded, size: 13, color: tint),
              const SizedBox(width: 4),
              Text(
                hasFix
                    ? wT(en: 'GPS FIX', ms: 'GPS OK', zh: '已定位')
                    : wT(en: 'NO FIX', ms: 'TIADA GPS', zh: '未定位'),
                style: GoogleFonts.inter(
                    fontSize: 10.5, fontWeight: FontWeight.w900, color: tint),
              ),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        SizedBox(
          height: 132,
          child: ClipRRect(
            borderRadius: AppRadius.rLg,
            child: CustomPaint(
              painter: _SiteMapPainter(
                inside: _inside,
                hasFix: hasFix,
                hasCenter: _centerLat != null && _centerLng != null,
                ratio: (_distance != null && _radius > 0)
                    ? (_distance! / (_radius * 2)).clamp(0.0, 1.35)
                    : null,
                background: AppColors.bgMain,
                grid: AppColors.border,
                fence: _centerLat == null ? AppColors.textMuted : AppColors.navy,
                marker: tint,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: _miniStat(
              wT(en: 'ACCURACY', ms: 'KETEPATAN', zh: '精度'),
              accuracyLabel,
              accuracyGood ? AppColors.success : AppColors.warning,
            ),
          ),
          Container(width: 1, height: 30, color: AppColors.border),
          Expanded(
            child: _miniStat(
              wT(en: 'FROM CENTRE', ms: 'DARI PUSAT', zh: '距中心'),
              _distance == null ? '—' : '${_distance!.round()} m',
              AppColors.textPrimary,
            ),
          ),
          Container(width: 1, height: 30, color: AppColors.border),
          Expanded(
            child: _miniStat(
              wT(en: 'COORDS', ms: 'KOORDINAT', zh: '坐标'),
              hasFix ? '${_lat!.toStringAsFixed(4)}, ${_lng!.toStringAsFixed(4)}' : '—',
              AppColors.textPrimary,
            ),
          ),
        ]),
        const SizedBox(height: 10),
        AppButton(
          label: hasFix
              ? wT(en: 'Refresh Location', ms: 'Muat Semula Lokasi', zh: '刷新定位')
              : wT(en: 'Get My Location', ms: 'Dapatkan Lokasi', zh: '获取我的位置'),
          tone: AppButtonTone.secondary,
          height: 44,
          icon: Icons.my_location_rounded,
          loading: _locating,
          loadingLabel: wT(en: 'Locating…', ms: 'Mencari…', zh: '定位中…'),
          onPressed: _locate,
        ),
      ]),
    );
  }

  Widget _miniStat(String label, String value, Color tint) {
    return Column(children: [
      Text(
        label,
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(
            fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.5,
            color: AppColors.textMuted),
      ),
      const SizedBox(height: 3),
      Text(
        value,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w900, color: tint),
      ),
    ]);
  }

  Widget _fenceCard() {
    if (_lat == null || _distance == null) {
      return _card(
        child: Row(children: [
          Icon(Icons.explore_off_rounded, size: 22, color: AppColors.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              wT(
                  en: 'Press Get My Location to check the site fence.',
                  ms: 'Tekan Dapatkan Lokasi untuk semak pagar tapak.',
                  zh: '请先获取位置以判断是否在项目范围内。'),
              style: GoogleFonts.inter(
                  fontSize: 13, height: 1.35, color: AppColors.textSecondary),
            ),
          ),
        ]),
      );
    }

    final tint = _inside ? AppColors.success : AppColors.danger;
    final title = _inside
        ? wT(en: 'Inside project area', ms: 'Dalam kawasan projek', zh: '在项目范围内')
        : wT(en: 'Outside project area', ms: 'Luar kawasan projek', zh: '在项目范围外');
    final sub = _inside
        ? wT(en: 'You can clock in now.', ms: 'Anda boleh daftar masuk.', zh: '现在可以打卡。')
        : wT(
            en: 'About ${(_distance! - _radius).clamp(0, 99999).round()} m from the fence. Move closer to clock in.',
            ms: 'Kira-kira ${(_distance! - _radius).clamp(0, 99999).round()} m dari pagar. Dekatkan diri.',
            zh: '距围栏约 ${(_distance! - _radius).clamp(0, 99999).round()} 米，请靠近后打卡。');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.08),
        borderRadius: AppRadius.rXl,
        border: Border.all(color: tint.withValues(alpha: 0.45)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(_inside ? Icons.verified_rounded : Icons.wrong_location_rounded,
              size: 24, color: tint),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.inter(
                  fontSize: 15, fontWeight: FontWeight.w900, color: tint, height: 1.25),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        Text(sub,
            style: GoogleFonts.inter(
                fontSize: 12.5, height: 1.35, color: AppColors.textSecondary)),
      ]),
    );
  }

  Widget _faultCard() {
    return AppErrorBanner(
      message: '${_faultTitle(_fault)} — ${_faultHint(_fault)}',
      onRetry: _boot,
    );
  }

  Widget _selfieCard() {
    Uint8List? bytes;
    if (_photo != null) {
      try {
        bytes = base64Decode(_photo!.base64);
      } catch (_) {
        bytes = null;
      }
    }
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _sectionLabel(wT(en: 'Selfie', ms: 'Selfie', zh: '自拍')),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.navy.withValues(alpha: 0.06),
              borderRadius: AppRadius.rPill,
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.no_photography_rounded, size: 12, color: AppColors.textMuted),
              const SizedBox(width: 4),
              Text(
                wT(en: 'CAMERA ONLY', ms: 'KAMERA SAHAJA', zh: '仅相机'),
                style: GoogleFonts.inter(
                    fontSize: 9.5, fontWeight: FontWeight.w900, color: AppColors.textMuted),
              ),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        if (bytes != null)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ClipRRect(
              borderRadius: AppRadius.rMd,
              child: Image.memory(bytes, width: 86, height: 86, fit: BoxFit.cover),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.check_circle_rounded, size: 16, color: AppColors.success),
                  const SizedBox(width: 5),
                  Text(
                    wT(en: 'Selfie confirmed', ms: 'Selfie disahkan', zh: '自拍已确认'),
                    style: GoogleFonts.inter(
                        fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.success),
                  ),
                ]),
                const SizedBox(height: 4),
                Text(
                  wT(
                      en: 'Taken just now with the live camera.',
                      ms: 'Diambil sebentar tadi dengan kamera live.',
                      zh: '刚刚使用相机现场拍摄。'),
                  style: GoogleFonts.inter(
                      fontSize: 11.5, height: 1.3, color: AppColors.textMuted),
                ),
                const SizedBox(height: 8),
                AppButton(
                  label: wT(en: 'Retake', ms: 'Ambil Semula', zh: '重拍'),
                  tone: AppButtonTone.secondary,
                  height: 38,
                  expand: false,
                  onPressed: _takeSelfie,
                ),
              ]),
            ),
          ])
        else
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
              wT(
                  en: 'A live selfie is required. Gallery photos are not accepted.',
                  ms: 'Selfie live diperlukan. Foto galeri tidak diterima.',
                  zh: '必须现场自拍，不接受相册照片。'),
              style: GoogleFonts.inter(
                  fontSize: 12.5, height: 1.35, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 10),
            AppButton(
              label: wT(en: 'Take Selfie', ms: 'Ambil Selfie', zh: '拍摄自拍'),
              tone: AppButtonTone.secondary,
              height: 46,
              icon: Icons.photo_camera_front_rounded,
              onPressed: _takeSelfie,
            ),
          ]),
      ]),
    );
  }

  Widget _checkInArea() {
    final hasProject = _projectId != null;
    final hasFence = _lat != null && _distance != null;
    final hasPhoto = _photo != null;
    final already = _alreadyInAt != null;
    final blocked = already || !hasProject || !hasFence || !_inside || !hasPhoto;

    final String reason;
    if (already) {
      reason = wT(en: 'You already clocked in today.', ms: 'Anda sudah daftar masuk hari ini.',
          zh: '今天已打过卡。');
    } else if (!hasProject) {
      reason = wT(en: 'No site assigned to your account.', ms: 'Tiada tapak untuk akaun anda.',
          zh: '账号未关联工地。');
    } else if (!hasFence) {
      reason = wT(en: 'Get your location first.', ms: 'Dapatkan lokasi dahulu.', zh: '请先获取位置。');
    } else if (!_inside) {
      reason = wT(en: 'You are outside the project area.', ms: 'Anda di luar kawasan projek.',
          zh: '您不在项目范围内。');
    } else if (!hasPhoto) {
      reason = wT(en: 'Take and confirm your selfie.', ms: 'Ambil dan sahkan selfie anda.',
          zh: '请拍摄并确认自拍。');
    } else {
      reason = '';
    }

    final String label;
    if (already) {
      label = wT(en: 'Already Clocked In', ms: 'Sudah Daftar Masuk', zh: '已打卡');
    } else {
      label = wT(en: 'Check In', ms: 'Daftar Masuk', zh: '打卡');
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppButton(
        label: label,
        loadingLabel: wT(en: 'Checking in…', ms: 'Sedang daftar…', zh: '打卡中…'),
        loading: _submitting,
        height: 56,
        icon: Icons.login_rounded,
        onPressed: blocked ? null : _clockIn,
      ),
      if (reason.isNotEmpty) ...[
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.lock_outline_rounded, size: 13, color: AppColors.textMuted),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              reason,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                  fontSize: 11.5, height: 1.3, color: AppColors.textMuted),
            ),
          ),
        ]),
      ],
    ]);
  }

  Widget _successCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.greenLight,
        borderRadius: AppRadius.rXl,
        border: Border.all(color: AppColors.success.withValues(alpha: 0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.check_circle_rounded, size: 34, color: AppColors.success),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              wT(en: 'Attendance recorded', ms: 'Kedatangan direkod', zh: '打卡成功'),
              style: GoogleFonts.inter(
                  fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.success),
            ),
          ),
        ]),
        const SizedBox(height: 14),
        _kv(wT(en: 'TIME', ms: 'MASA', zh: '时间'), _clock(_successAt!)),
        const SizedBox(height: 8),
        _kv(wT(en: 'DATE', ms: 'TARIKH', zh: '日期'), _todayLine),
        const SizedBox(height: 8),
        _kv(
            wT(en: 'SITE', ms: 'TAPAK', zh: '工地'),
            _projectName.isEmpty ? wT(en: 'Not set', ms: 'Tiada', zh: '未设置') : _projectName),
        const SizedBox(height: 14),
        AppButton(
          label: wT(en: 'Done', ms: 'Siap', zh: '完成'),
          tone: AppButtonTone.secondary,
          height: 48,
          onPressed: () {
            if (widget.embedded) {
              setState(() => _successAt = null);
            } else {
              Navigator.of(context).pop();
            }
          },
        ),
      ]),
    );
  }

  Widget _kv(String k, String v) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        width: 64,
        child: Text(k,
            style: GoogleFonts.inter(
                fontSize: 10.5,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.6,
                color: AppColors.textMuted)),
      ),
      Expanded(
        child: Text(v,
            style: GoogleFonts.inter(
                fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
      ),
    ]);
  }
}

/// Review step between the camera and the confirmed selfie: Retake or Confirm.
class _SelfieReviewPage extends StatelessWidget {
  const _SelfieReviewPage({required this.photo});

  final CapturedPhoto photo;

  @override
  Widget build(BuildContext context) {
    Uint8List? bytes;
    try {
      bytes = base64Decode(photo.base64);
    } catch (_) {
      bytes = null;
    }
    return Scaffold(
      backgroundColor: AppColors.bgMain,
      appBar: AppBar(
        backgroundColor: AppColors.bgCard,
        elevation: 0,
        surfaceTintColor: AppColors.transparent,
        shape: Border(bottom: BorderSide(color: AppColors.border)),
        iconTheme: IconThemeData(color: AppColors.textPrimary),
        title: Text(
          wT(en: 'CHECK SELFIE', ms: 'SEMAK SELFIE', zh: '确认自拍'),
          style: GoogleFonts.inter(
              fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.textPrimary),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
        children: [
          ClipRRect(
            borderRadius: AppRadius.rXl,
            child: bytes == null
                ? Container(
                    height: 260,
                    color: AppColors.bgCard,
                    alignment: Alignment.center,
                    child: Icon(Icons.broken_image_rounded,
                        size: 40, color: AppColors.textMuted),
                  )
                : Image.memory(bytes, width: double.infinity, fit: BoxFit.cover),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Icon(Icons.info_outline_rounded, size: 15, color: AppColors.textMuted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                wT(
                    en: 'Face must be clear. Retake if it is blurry or covered.',
                    ms: 'Muka mesti jelas. Ambil semula jika kabur.',
                    zh: '请确保面部清晰，模糊或被遮挡请重拍。'),
                style: GoogleFonts.inter(
                    fontSize: 12, height: 1.35, color: AppColors.textMuted),
              ),
            ),
          ]),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(
              child: AppButton(
                label: wT(en: 'Retake', ms: 'Ambil Semula', zh: '重拍'),
                tone: AppButtonTone.secondary,
                height: 52,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: AppButton(
                label: wT(en: 'Confirm Selfie', ms: 'Sahkan Selfie', zh: '确认自拍'),
                height: 52,
                icon: Icons.check_rounded,
                onPressed: () => Navigator.of(context).pop(photo),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

/// Schematic site map: the fence ring, the site centre and the worker's dot.
/// Drawn locally so it stays meaningful with a weak signal.
class _SiteMapPainter extends CustomPainter {
  _SiteMapPainter({
    required this.inside,
    required this.hasFix,
    required this.hasCenter,
    required this.ratio,
    required this.background,
    required this.grid,
    required this.fence,
    required this.marker,
  });

  final bool inside;
  final bool hasFix;
  final bool hasCenter;
  final double? ratio;
  final Color background;
  final Color grid;
  final Color fence;
  final Color marker;

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = background;
    canvas.drawRect(Offset.zero & size, bg);

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 22) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += 22) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final centre = Offset(size.width / 2, size.height / 2);
    final ringR = size.height * 0.34;

    final ring = Paint()
      ..color = (hasCenter ? fence : grid).withValues(alpha: 0.35)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(centre, ringR, ring);

    final ringEdge = Paint()
      ..color = (hasCenter ? fence : grid).withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    canvas.drawCircle(centre, ringR, ringEdge);

    // Centre pin.
    canvas.drawCircle(
        centre, 3.5, Paint()..color = (hasCenter ? fence : grid).withValues(alpha: 0.9));

    if (!hasFix) return;

    // Worker dot: inside → somewhere within the ring, outside → further out.
    final r = ratio ?? 0.5;
    final offset = Offset(
      centre.dx + ringR * r.clamp(0.0, 1.35) * 0.92,
      centre.dy - ringR * r.clamp(0.0, 1.35) * 0.45,
    );

    canvas.drawCircle(offset, 12, Paint()..color = marker.withValues(alpha: 0.22));
    canvas.drawCircle(offset, 6.5, Paint()..color = marker);
    canvas.drawCircle(offset, 2.2, Paint()..color = Colors.white);

    if (inside) {
      final link = Paint()
        ..color = marker.withValues(alpha: 0.55)
        ..strokeWidth = 1.4;
      canvas.drawLine(centre, offset, link);
    }
  }

  @override
  bool shouldRepaint(covariant _SiteMapPainter old) =>
      old.inside != inside ||
      old.hasFix != hasFix ||
      old.hasCenter != hasCenter ||
      old.ratio != ratio ||
      old.marker != marker ||
      old.background != background;
}

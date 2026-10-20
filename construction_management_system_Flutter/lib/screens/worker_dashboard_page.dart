import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';
import '../services/api_service.dart';
import '../services/app_settings.dart';
import '../services/project_cache.dart';
import '../l10n/app_strings.dart';
import '../services/gps_notification_service.dart';
import '../utils/date_helper.dart';
import 'attendance_geo_helper.dart';
import 'worker_task_detail_page.dart';

class WorkerDashboardPage extends StatefulWidget {
  const WorkerDashboardPage({super.key});
  @override
  State<WorkerDashboardPage> createState() => _WorkerDashboardPageState();
}

class _WorkerDashboardPageState extends State<WorkerDashboardPage> {
  bool _loadingAtt = true;
  bool _loadingTasks = true;
  bool _checkInLoading = false;
  bool _checkedIn = false;
  bool _checkedOut = false;
  int? _attendanceId;
  double _hoursToday = 0;
  String _checkInWindow = '08:00 - 10:30';
  String _checkOutWindow = '15:00 - 17:00';
  String _breakWindow = '12:00 - 13:00';
  String _workHours = '08:00 - 17:00';
  bool _windowEnforced = false;
  String _statusMsg = 'Tap the button below to check in with GPS geofencing';
  String _deviceType = 'web';
  String _deviceInfo = 'BuildSmart Web Client';
  String _deviceId = 'web-client';

  List _projects = [];
  int? _selectedProjectId;
  String? _workerName;

  Map? _taskBoard;
  String _lastUpdated = '';
  Timer? _syncTimer;
  bool _syncingNow = false;
  bool _checkInError = false; // true when last check-in was rejected (outside fence)

  @override
  void initState() {
    super.initState();
    AppColors.darkMode.addListener(_rebuild);
    AppSettings.lang.addListener(_rebuild);
    _initDevice();
    _loadAll();
    _startAutoSync();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    AppColors.darkMode.removeListener(_rebuild);
    AppSettings.lang.removeListener(_rebuild);
    _syncTimer?.cancel();
    super.dispose();
  }

  void _initDevice() {
    if (kIsWeb) {
      _deviceType = 'web';
      _deviceInfo = 'BuildSmart Web Client';
      _deviceId = 'web-client';
    } else {
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          _deviceType = 'android';
          _deviceInfo = 'BuildSmart Android App';
          _deviceId = 'android-device';
          break;
        case TargetPlatform.iOS:
          _deviceType = 'ios';
          _deviceInfo = 'BuildSmart iOS App';
          _deviceId = 'ios-device';
          break;
        case TargetPlatform.windows:
          _deviceType = 'windows';
          _deviceInfo = 'BuildSmart Windows App';
          _deviceId = 'windows-device';
          break;
        default:
          _deviceType = 'unknown';
          _deviceInfo = 'BuildSmart Client';
          _deviceId = 'unknown-device';
      }
    }
  }

  Future<void> _loadAll() async {
    await Future.wait([_loadAttendance(), _loadProjects(), _loadMe(), _loadTaskBoard()]);
  }

  Future<void> _loadMe() async {
    try {
      final me = await ApiService().me();
      _workerName = me['name']?.toString();
    } catch (_) {}
  }

  Future<void> _loadProjects() async {
    try {
      _projects = await ProjectCache.get(ApiService());
      if (_projects.isNotEmpty && _selectedProjectId == null) {
        final sp = await SharedPreferences.getInstance();
        final savedPid = sp.getInt('project_id');
        final exists = savedPid != null &&
            _projects.any((p) => p['project_id'] == savedPid);
        _selectedProjectId = exists ? savedPid : _projects.first['project_id'] as int;
      }
    } catch (_) {}
  }

  Future<void> _loadAttendance() async {
    setState(() => _loadingAtt = true);
    try {
      final r = await ApiService().workerTodayAttendance();
      if (mounted) {
        setState(() {
          _checkedIn = r['checked_in'] ?? false;
          _checkedOut = r['checked_out'] ?? false;
          _hoursToday = (r['hours_today'] as num?)?.toDouble() ?? 0;
          _checkInWindow = r['check_in_window']?.toString() ?? _checkInWindow;
          _checkOutWindow = r['check_out_window']?.toString() ?? _checkOutWindow;
          _breakWindow = r['break_window']?.toString() ?? _breakWindow;
          _windowEnforced = r['window_enforced'] == true;
          final inWin = _checkInWindow.split(' - ');
          final outWin = _checkOutWindow.split(' - ');
          if (inWin.isNotEmpty && outWin.length > 1) {
            _workHours = '${inWin.first} - ${outWin.last}';
          }
          final att = r['attendance'] as Map?;
          final rawStatus = (r['status'] ?? att?['status'] ?? '').toString().toLowerCase();
          if (rawStatus == 'rejected') {
            // The server refused the last attempt (geofence / window). Never
            // report "checked in" in that case — surface the reason instead.
            _checkInError = true;
            _checkedIn = false;
            _checkedOut = false;
            _attendanceId = null;
            final reason = r['rejection_reason']?.toString();
            _statusMsg = (reason != null && reason.isNotEmpty)
                ? '❌ Check-in rejected — $reason'
                : '❌ Check-in rejected — you are outside the site geofence. '
                    'Move closer to the site and try again.';
          } else if (att != null) {
            _checkInError = false;
            _attendanceId = att['attendance_id'] as int?;
            final ci = att['check_in_time'];
            final co = att['check_out_time'] ?? att['checked_out_time'];
            final t = _checkedOut ? (co ?? ci) : ci;
            if (t != null) {
              final tt = _fmtTime(t);
              _statusMsg = _checkedOut
                  ? '👋 Checked out — completed today at $tt'
                  : '✅ Currently checked in — arrived at $tt';
            }
          } else {
            _checkInError = false;
            _attendanceId = null;
          }
        });
      }
    } catch (e) {
      _statusMsg = 'Failed to load attendance';
    } finally {
      if (mounted) setState(() => _loadingAtt = false);
    }
  }

  Future<void> _loadTaskBoard() async {
    setState(() => _loadingTasks = true);
    try {
      final r = await ApiService().workerTaskBoard(refresh: true);
      if (mounted) {
        setState(() {
          _taskBoard = r;
          _lastUpdated = r['last_updated']?.toString() ?? '';
          _loadingTasks = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingTasks = false);
    }
  }

  /// Open the worker task detail page; refresh the board when it reports a
  /// status/progress change so the card and the record never diverge.
  Future<void> _openTask(Map<String, dynamic> task) async {
    final id = task['task_id'] ?? task['id'];
    final taskId = id is int ? id : int.tryParse(id?.toString() ?? '');
    if (taskId == null) {
      toast('Task id missing — cannot open details');
      return;
    }
    var changed = false;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => WorkerTaskDetailPage(
        taskId: taskId,
        initial: task,
        onChanged: () => changed = true,
      ),
    ));
    if (changed && mounted) {
      await _loadTaskBoard();
    }
  }

  void _startAutoSync() {
    _syncTimer = Timer.periodic(const Duration(seconds: 30), (_) => _runSync());
  }

  Future<void> _runSync() async {
    if (_syncingNow) return;
    _syncingNow = true;
    try {
      final r = await ApiService().workerTasksSync(sinceLastUpdated: _lastUpdated);
      if (r['changed'] == true) {
        final newBoard = r['board'] as Map?;
        if (newBoard != null && mounted) {
          setState(() {
            _taskBoard = newBoard;
            _lastUpdated = r['last_updated']?.toString() ?? '';
          });
          final alert = r['alert']?.toString();
          if (alert != null && alert.isNotEmpty) {
            toast('⚠ Task Update: $alert');
          }
        }
      }
    } catch (_) {
    } finally {
      _syncingNow = false;
    }
  }

  Future<void> _doCheckIn() async {
    if (_selectedProjectId == null) {
      toast('Please select a project first');
      return;
    }
    if (kIsWeb) {
      _simulateGpsCheckIn();
      return;
    }
    setState(() {
      _checkInLoading = true;
      _statusMsg = 'Getting your location...';
    });
    try {
      if (!await GeoHelper.isServiceEnabled()) {
        setState(() {
          _statusMsg = 'GPS is off. A notification has been sent to enable it.';
          _checkInLoading = false;
        });
        await GpsNotificationService.requestEnable();
        return;
      }
      final pos = await GeoHelper.getCurrentPosition();
      if (pos == null) {
        setState(() {
          _statusMsg = 'Location permission denied or GPS unavailable';
          _checkInLoading = false;
        });
        return;
      }
      final r = await ApiService().workerCheckIn(
        projectId: _selectedProjectId!,
        lat: pos['lat']!,
        lng: pos['lng']!,
        deviceInfo: _deviceInfo,
        deviceType: _deviceType,
        deviceId: _deviceId,
      );
      // The backend also answers 200 with status=rejected on some deployments,
      // so never trust the HTTP code alone — check what was really recorded.
      final inStatus = (r['status'] ?? '').toString().toLowerCase();
      if (inStatus != 'checked_in') {
        // "rejected" is the common case, but any unexpected status must not be
        // reported as success: the card has to mirror what the server stored.
        setState(() {
          _checkedIn = false;
          _checkedOut = false;
          _attendanceId = null;
          _checkInError = true;
          _statusMsg = inStatus == 'rejected'
              ? '❌ Check-in rejected — you are outside the site geofence. '
                  'Move closer to the site and try again.'
              : '❌ Check-in not recorded (server status: '
                  '${inStatus.isEmpty ? 'unknown' : inStatus}).';
          _checkInLoading = false;
        });
        toast(inStatus == 'rejected'
            ? 'Check-in rejected — you are outside the site geofence'
            : 'Check-in was not recorded by the server');
        await _loadAttendance();
        return;
      }
      setState(() {
        _checkedIn = true;
        _checkInError = false;
        _attendanceId = r['attendance_id'] as int?;
        _statusMsg = 'Checked in successfully at ${_fmtTime(r['check_in_time'])}';
        _checkInLoading = false;
      });
      toast('Checked in! Device: $_deviceType');
      // Re-sync with the server so the card can never drift from the record.
      await _loadAttendance();
    } on DioException catch (e) {
      setState(() {
        _checkedIn = false;
        _checkedOut = false;
        _attendanceId = null;
        _statusMsg = '❌ Check-in failed — ${_apiError(e)}';
        _checkInError = true;
        _checkInLoading = false;
      });
      toast('Check-in failed: ${_apiError(e)}');
      await _loadAttendance();
    } catch (e) {
      setState(() {
        _statusMsg = '❌ Error: $e';
        _checkInError = true;
        _checkInLoading = false;
      });
    }
  }

  /// Returns [lat, lng] of the currently selected project, falling back to
  /// the first project, then to the default site center.
  List<double> _projectCenter() {
    if (_projects.isEmpty) return [3.1390, 101.6869];
    var proj = _projects.first;
    if (_selectedProjectId != null) {
      final idx =
          _projects.indexWhere((p) => p['project_id'] == _selectedProjectId);
      if (idx >= 0) proj = _projects[idx];
    }
    return [
      (proj['center_lat'] as num? ?? 3.1390).toDouble(),
      (proj['center_lng'] as num? ?? 101.6869).toDouble(),
    ];
  }

  void _simulateGpsCheckIn() async {
    setState(() {
      _checkInLoading = true;
      _statusMsg = 'Using simulated location for web (demo mode)...';
    });
    await Future.delayed(const Duration(milliseconds: 500));
    try {
      final c = _projectCenter();
      final defaultLat = c[0];
      final defaultLng = c[1];
      final r = await ApiService().workerCheckIn(
        projectId: _selectedProjectId!,
        lat: defaultLat,
        lng: defaultLng,
        deviceInfo: _deviceInfo,
        deviceType: _deviceType,
        deviceId: _deviceId,
      );
      final webStatus = (r['status'] ?? '').toString().toLowerCase();
      if (webStatus != 'checked_in') {
        setState(() {
          _checkedIn = false;
          _checkedOut = false;
          _attendanceId = null;
          _checkInError = true;
          _statusMsg = '❌ Check-in rejected — outside the site geofence.';
          _checkInLoading = false;
        });
        toast('Check-in rejected — you are outside the site geofence');
        await _loadAttendance();
        return;
      }
      setState(() {
        _checkedIn = true;
        _checkInError = false;
        _attendanceId = r['attendance_id'] as int?;
        _statusMsg = '✅ Checked in (simulated GPS) at ${_fmtTime(r['check_in_time'])}';
        _checkInLoading = false;
      });
      toast('✅ Web demo: Checked in successfully!');
      await _loadAttendance();
    } on DioException catch (e) {
      setState(() {
        _checkedIn = false;
        _attendanceId = null;
        _checkInError = true;
        _statusMsg = '❌ Check-in failed — ${_apiError(e)}';
        _checkInLoading = false;
      });
      toast('Check-in failed: ${_apiError(e)}');
      await _loadAttendance();
    } catch (e) {
      setState(() {
        _statusMsg = '❌ Error: $e';
        _checkInLoading = false;
      });
    }
  }

  Future<void> _doCheckOut() async {
    if (_attendanceId == null) {
      toast('No active check-in found on the server. Refresh and try again.');
      await _loadAttendance();
      return;
    }
    setState(() {
      _checkInLoading = true;
      _statusMsg = 'Processing check-out...';
    });
    try {
      // Check-out must use the device's real position: sending the project
      // centre (as this used to) always passes the geofence and would mark a
      // worker as checked out while they are nowhere near the site.
      double outLat;
      double outLng;
      if (kIsWeb) {
        final c = _projectCenter();
        outLat = c[0];
        outLng = c[1];
      } else {
        final pos = await GeoHelper.getCurrentPosition();
        if (pos == null) {
          setState(() {
            _checkInError = true;
            _statusMsg = '❌ Check-out failed — location permission denied or GPS unavailable';
            _checkInLoading = false;
          });
          toast('Check-out failed: location unavailable');
          return;
        }
        outLat = pos['lat']!;
        outLng = pos['lng']!;
      }
      final r = await ApiService().workerCheckOut(
        lat: outLat,
        lng: outLng,
        deviceInfo: _deviceInfo,
        deviceType: _deviceType,
      );
      if ((r['status'] ?? '').toString().toLowerCase() == 'rejected') {
        setState(() {
          _checkInError = true;
          _statusMsg = '❌ Check-out rejected — outside the site geofence. '
              'Your session is still open on the server.';
          _checkInLoading = false;
        });
        toast('Check-out rejected — you are outside the site geofence');
        await _loadAttendance();
        return;
      }
      setState(() {
        _checkedIn = false;
        _checkedOut = true;
        _checkInError = false;
        _attendanceId = null;
        _statusMsg = '👋 Checked out at ${_fmtTime(r['check_out_time'])}. Thank you for today!';
        _checkInLoading = false;
      });
      toast('👋 Checked out successfully. See you tomorrow!');
      await _loadAttendance();
    } on DioException catch (e) {
      setState(() {
        _statusMsg = '❌ Check-out failed — ${_apiError(e)}';
        _checkInError = true;
        _checkInLoading = false;
      });
      toast('Check-out failed: ${_apiError(e)}');
      await _loadAttendance();
    } catch (e) {
      setState(() {
        _statusMsg = '❌ Error: $e';
        _checkInLoading = false;
      });
    }
  }

  String _fmtNow() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }

  /// Extract HH:mm from backend time strings without crashing on short /
  /// unexpected formats (ISO "2026-08-23T19:29:58+08:00" or "19:29:58").
  String _fmtTime(Object? v) {
    if (v == null) return '—';
    final s = v.toString();
    if (s.length >= 16) return s.substring(11, 16);
    if (s.length >= 5) return s.substring(0, 5);
    return s;
  }

  /// Prefer the backend `detail` text over Dio's generic status-code message so
  /// the worker reads the real reason (geofence distance, "already checked in").
  String _apiError(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['detail'] != null) return data['detail'].toString();
    if (data is String && data.isNotEmpty) return data;
    return e.message ?? 'unknown error';
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, constraints) {
      final isWide = constraints.maxWidth >= AppBreakpoints.phone;
      return Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppBreakpoints.maxContentWidth),
          child: SizedBox(
            width: double.infinity,
            child: RefreshIndicator(
              onRefresh: _loadAll,
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  const SizedBox(height: AppSpacing.xs),
                  if (isWide)
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(child: _buildWelcomeCard()),
                      const SizedBox(width: AppSpacing.lg),
                      Expanded(child: _buildCheckInCard()),
                    ])
                  else ...[
                    _buildWelcomeCard(),
                    const SizedBox(height: AppSpacing.lg),
                    _buildCheckInCard(),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  _buildTaskBoard(isWide: isWide),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }

  Widget _buildWelcomeCard() {
    final name = _workerName ?? 'Worker';
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? AppStrings.t('common.goodMorning')
        : hour < 18
            ? AppStrings.t('common.goodAfternoon')
            : AppStrings.t('common.goodEvening');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.green, AppColors.green.withValues(alpha: 0.75)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: AppRadius.rMd,
        boxShadow: [BoxShadow(color: AppColors.green.withValues(alpha: 0.18), blurRadius: 18, offset: Offset(0, 6))],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: AppColors.onAccentVeryFaint,
            child: initialsAvatar(name, radius: 24, seed: 'worker-$name'),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$greeting, ${name.split(' ').first}!',
                  style: GoogleFonts.inter(color: AppColors.onAccent, fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(AppStrings.t('worker.portal'),
                  style: GoogleFonts.inter(color: AppColors.onAccentSoft, fontSize: 14)),
              const SizedBox(height: 12),
              Wrap(spacing: 6, runSpacing: 4, children: [
                _welcomeChip(Icons.badge_rounded, AppStrings.t('worker.portal')),
                if (_checkedIn) _welcomeChip(Icons.gps_fixed, AppStrings.t('dash.onSite'), bg: AppColors.onAccentStrong, fg: AppColors.green),
              ]),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(_fmtNow(),
                style: GoogleFonts.inter(color: AppColors.onAccent, fontSize: 24, fontWeight: FontWeight.w800)),
            Text(DateHelper.formatShort(DateTime.now()),
                style: GoogleFonts.inter(color: AppColors.onAccentSoft, fontSize: 13)),
          ]),
        ],
      ),
    );
  }

  Widget _welcomeChip(IconData icon, String label, {Color? bg, Color? fg}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bg ?? AppColors.onAccentWash, borderRadius: AppRadius.rMd),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: fg ?? AppColors.onAccent),
        const SizedBox(width: 4),
        Text(label, style: GoogleFonts.inter(color: fg ?? AppColors.onAccent, fontSize: 14, fontWeight: FontWeight.w700)),
      ]),
    );
  }

  Widget _buildCheckInCard() {
    final showCheckOut = _checkedIn && !_checkedOut;
    return sectionCard(
      padding: const EdgeInsets.all(24),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('📍 Daily Attendance Check-In',
              style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          if (!_loadingAtt)
            statusPill(_checkedOut ? 'checked_out' : _checkedIn ? 'checked_in' : 'absent',
                label: _checkedOut ? 'DONE' : _checkedIn ? 'ON SITE' : 'NOT IN'),
        ]),
        const SizedBox(height: 16),

        if (_projects.isNotEmpty)
          DropdownButtonFormField<int>(
            initialValue: _selectedProjectId,
            decoration: InputDecoration(
              labelText: 'Select Your Project',
              prefixIcon: const Icon(Icons.apartment_rounded, size: 18),
            ),
            items: _projects.map<DropdownMenuItem<int>>((p) => DropdownMenuItem(
                  value: p['project_id'] as int,
                  child: Text(
                    p['project_name']?.toString() ?? 'Project ${p['project_id']}',
                    overflow: TextOverflow.ellipsis,
                  ),
                )).toList(),
            onChanged: _checkInLoading || _checkedIn
                ? null
                : (v) => setState(() => _selectedProjectId = v),
          ),
        if (_projects.isNotEmpty) ...[  
          const SizedBox(height: 16),
          // Show fence radius for selected project
          if (_selectedProjectId != null) Builder(builder: (ctx) {
            final sel = _projects.firstWhere(
              (p) => p['project_id'] == _selectedProjectId,
              orElse: () => {},
            );
            final r = (sel['fence_radius'] as num?)?.toInt() ?? 0;
            if (r == 0) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(children: [
                Icon(Icons.radar_rounded, size: 13, color: AppColors.green),
                const SizedBox(width: 4),
                Text(
                  'You must be within ${r}m of the site to check in',
                  style: GoogleFonts.inter(fontSize: 13, color: AppColors.green, fontWeight: FontWeight.w600),
                ),
              ]),
            );
          }),
        ],

        // Big circle status
        Center(
          child: Column(children: [
            Container(
              width: 110, height: 110,
              decoration: BoxDecoration(
                color: _checkedOut ? AppColors.blueLight : _checkedIn ? AppColors.greenLight : AppColors.accentLight,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: (_checkedOut ? AppColors.blue : _checkedIn ? AppColors.green : AppColors.accent).withValues(alpha: 0.18),
                    blurRadius: 24,
                  ),
                ],
              ),
              child: Icon(
                _checkedOut
                    ? Icons.logout_rounded
                    : _checkedIn
                        ? Icons.check_circle_rounded
                        : Icons.fingerprint_rounded,
                size: 54,
                color: _checkedOut ? AppColors.blue : _checkedIn ? AppColors.green : AppColors.accent,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: 260,
              child: Text(
                _statusMsg,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: _checkInError ? AppColors.red : AppColors.textSecondary,
                  fontWeight: _checkInError ? FontWeight.w600 : FontWeight.normal,
                  height: 1.4,
                ),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 8),
        if (_hoursToday > 0)
          Text('${AppStrings.t('worker.hoursToday')}: ${_hoursToday.toStringAsFixed(1)}h',
              style: GoogleFonts.inter(fontSize: 14, color: AppColors.accent, fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),

        Row(children: [
          const SizedBox(width: 4),
          Text(_windowEnforced ? 'Check-in: $_checkInWindow' : 'Check-in: Anytime',
              style: GoogleFonts.inter(fontSize: 13, color: AppColors.green, fontWeight: FontWeight.w700)),
          const Spacer(),
          Text(_windowEnforced ? 'Check-out: $_checkOutWindow' : 'Check-out: Anytime',
              style: GoogleFonts.inter(fontSize: 13, color: AppColors.blue, fontWeight: FontWeight.w700)),
          const SizedBox(width: 4),
        ]),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: AppRadius.rMd,
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Column(children: [
                Text(AppStrings.t('worker.workHours'),
                    style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(_windowEnforced ? _workHours : AppStrings.t('worker.anytime'),
                    style: GoogleFonts.inter(fontSize: 14, color: AppColors.textPrimary, fontWeight: FontWeight.w800)),
              ]),
              Container(width: 1, height: 30, color: AppColors.border),
              Column(children: [
                Text(AppStrings.t('worker.breakNoCheckin'),
                    style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(_breakWindow,
                    style: GoogleFonts.inter(fontSize: 14, color: AppColors.yellow, fontWeight: FontWeight.w800)),
              ]),
            ],
          ),
        ),
        const SizedBox(height: 16),

        SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton.icon(
            onPressed: _checkInLoading
                ? null
                : (_checkedOut
                    ? null
                    : (showCheckOut ? _doCheckOut : _doCheckIn)),
            icon: _checkInLoading
                ? const SizedBox(width: 24, height: 20, child: CircularProgressIndicator(color: AppColors.accentInk, strokeWidth: 2))
                : Icon(showCheckOut ? Icons.logout_rounded : Icons.fingerprint_rounded, size: 22),
            label: Text(
              _checkedOut
                  ? 'Attendance Completed Today'
                  : showCheckOut
                      ? 'Tap to Check Out'
                      : '🎯 Tap to Check In (GPS)',
              style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w800),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _checkedOut
                  ? AppColors.textMuted
                  : showCheckOut
                      ? AppColors.red
                      : AppColors.green,
              shape: RoundedRectangleBorder(borderRadius: AppRadius.rMd),
              elevation: 0,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Device: $_deviceType • $_deviceInfo',
          style: GoogleFonts.inter(fontSize: 14, color: AppColors.textMuted),
        ),
      ]),
    );
  }

  Widget _buildTaskBoard({bool isWide = false}) {
    if (_loadingTasks) {
      return sectionCard(
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          SizedBox(height: 16),
          Center(child: CircularProgressIndicator()),
          SizedBox(height: 12),
          Center(child: Text(AppStrings.t('worker.loadingTaskBoard'), style: TextStyle(color: AppColors.textMuted, fontSize: 14))),
          SizedBox(height: 16),
        ]),
      );
    }
    final tasks = (_taskBoard?['tasks'] as List?) ?? [];
    return sectionCard(
      padding: const EdgeInsets.all(4),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Row(children: [
            Text('🎯 My Assigned Work Sections',
                style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            const Spacer(),
            if (_lastUpdated.isNotEmpty)
              Text(_lastUpdated.substring(11, 16),
                  style: GoogleFonts.inter(fontSize: 14, color: AppColors.textMuted, fontWeight: FontWeight.w700)),
            IconButton(
              icon: Icon(Icons.refresh_rounded, size: 17, color: AppColors.accent),
              tooltip: 'Refresh tasks',
              onPressed: _loadTaskBoard,
            ),
          ]),
        ),
        if (tasks.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(color: AppColors.accentLight, borderRadius: AppRadius.rMd),
                child: Icon(Icons.assignment_outlined, size: 26, color: AppColors.accent),
              ),
              const SizedBox(height: 12),
              Text(AppStrings.t('worker.noTasks'),
                  style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              const SizedBox(height: 4),
              Text(AppStrings.t('worker.noTasksHint'),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(fontSize: 14, color: AppColors.textMuted)),
            ]),
          )
        else
          LayoutBuilder(builder: (ctx, c) {
            final tiles = tasks.asMap().entries.map((e) {
              final task = Map<String, dynamic>.from(e.value as Map);
              return _TaskTile(
                idx: e.key,
                task: task,
                inGrid: isWide,
                onTap: () => _openTask(task),
              );
            }).toList();
            if (!isWide) return Column(children: tiles);
            final w = c.maxWidth;
            return Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.sm,
              children: tiles
                  .map((t) => SizedBox(width: (w - AppSpacing.md) / 2, child: t))
                  .toList(),
            );
          }),
      ]),
    );
  }
}

class _TaskTile extends StatelessWidget {
  final int idx;
  final Map<String, dynamic> task;
  final bool inGrid;
  final VoidCallback? onTap;
  const _TaskTile({required this.idx, required this.task, this.inGrid = false, this.onTap});

  Color _priorityColor(String? p) {
    switch (p?.toLowerCase()) {
      case 'high':
        return AppColors.red;
      case 'medium':
        return AppColors.yellow;
      case 'low':
        return AppColors.blue;
      default:
        return AppColors.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = task['status']?.toString() ?? 'Pending';
    final priority = task['priority']?.toString() ?? 'Medium';
    final part = task['part_section']?.toString() ?? 'General Section';
    final instructions = task['work_instructions']?.toString() ?? '';
    final projectName = task['project_name']?.toString() ?? '';
    final rawPct = task['progress'];
    final pct = rawPct is num
        ? rawPct.round().clamp(0, 100)
        : (status.toLowerCase().replaceAll(' ', '_') == 'completed'
            ? 100
            : (status.toLowerCase().replaceAll(' ', '_') == 'in_progress' ? 50 : 0));
    final sKey = status.toLowerCase().replaceAll(' ', '_');
    final barColor = sKey == 'completed'
        ? AppColors.green
        : sKey == 'in_progress'
            ? AppColors.blue
            : AppColors.yellow;

    return Padding(
      padding: inGrid ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Material(
        color: AppColors.bgCard,
        borderRadius: AppRadius.rMd,
        child: InkWell(
          borderRadius: AppRadius.rMd,
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: AppRadius.rMd,
              border: Border.all(color: AppColors.border),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: AppColors.accentLight, borderRadius: AppRadius.rMd),
                child: Row(children: [
                  Icon(Icons.layers_rounded, size: 11, color: AppColors.accent),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(part,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(color: AppColors.accent, fontSize: 14, fontWeight: FontWeight.w800)),
                  ),
                ]),
              ),
            ),
            const SizedBox(width: 8),
            statusPill(status),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _priorityColor(priority).withValues(alpha: 0.18),
                borderRadius: AppRadius.rMd,
              ),
              child: Text(priority.toUpperCase(),
                  style: GoogleFonts.inter(
                    color: _priorityColor(priority),
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  )),
            ),
          ]),
          const SizedBox(height: 8),
          Text(task['task_name']?.toString() ?? 'Unnamed Task',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          if (task['description']?.toString().isNotEmpty ?? false) ...[
            const SizedBox(height: 4),
            Text(task['description'].toString(),
                style: GoogleFonts.inter(fontSize: 14, color: AppColors.textSecondary, height: 1.4)),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              if (projectName.isNotEmpty)
                _miniTag(Icons.apartment_rounded, projectName, AppColors.blue),
              if (task['due_date'] != null)
                _miniTag(Icons.event_rounded, 'Due: ${DateHelper.tryFormatShort(task['due_date'], fallback: task['due_date'].toString().substring(0, 10))}', AppColors.textSecondary),
            ],
          ),
          if (instructions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
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
                      style: GoogleFonts.inter(fontSize: 13, color: AppColors.blue, height: 1.4, fontWeight: FontWeight.w600)),
                ),
              ]),
            ),
          ],
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: AppRadius.rSm,
                      child: LinearProgressIndicator(
                        value: pct / 100,
                        minHeight: 6,
                        backgroundColor: AppColors.border,
                        valueColor: AlwaysStoppedAnimation<Color>(barColor),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text('$pct%',
                      style: GoogleFonts.inter(
                          fontSize: 13, fontWeight: FontWeight.w800, color: barColor)),
                  const SizedBox(width: 2),
                  Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.accent),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _miniTag(IconData icon, String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: AppRadius.rMd),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 10.5, color: color),
          const SizedBox(width: 3.5),
          Text(label,
              style: GoogleFonts.inter(color: color, fontSize: 14, fontWeight: FontWeight.w700)),
        ]),
      );
}

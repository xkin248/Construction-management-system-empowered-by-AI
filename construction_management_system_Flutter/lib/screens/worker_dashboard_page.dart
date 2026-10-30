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
import '../widgets/guided_empty_state.dart';
import '../widgets/worker_task_tile.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/failure_state.dart';
import '../widgets/app_scrollbar.dart';
import 'attendance_geo_helper.dart';
import 'notifications_page.dart';
import 'worker_task_detail_page.dart';
import 'worker_tasks_page.dart';
import '../widgets/a11y.dart';

class WorkerDashboardPage extends StatefulWidget {
  /// Lets the shell switch tabs from the dashboard shortcuts (0=Home,
  /// 1=Tasks, 2=Attendance, 3=Alerts). When null the dashboard pushes the
  /// standalone page instead, so the widget stays usable on its own.
  final void Function(int index, int subTab)? onNavigate;

  const WorkerDashboardPage({super.key, this.onNavigate});
  @override
  State<WorkerDashboardPage> createState() => _WorkerDashboardPageState();
}

class _WorkerDashboardPageState extends State<WorkerDashboardPage> {
  /// Drives the always-available scrollbar of the dashboard scroll view.
  final ScrollController _scrollCtrl = ScrollController();

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
  Object? _taskBoardError;
  String _lastUpdated = '';
  Timer? _syncTimer;
  bool _syncingNow = false;
  bool _checkInError = false; // true when last check-in was rejected (outside fence)

  /// Collapse state for the secondary blocks (attendance detail, task list).
  final Map<String, bool> _expandedSections = {};

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
    _scrollCtrl.dispose();
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
          _taskBoardError = null;
          _lastUpdated = r['last_updated']?.toString() ?? '';
          _loadingTasks = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _taskBoardError = e;
          _loadingTasks = false;
        });
      }
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
              child: AppScrollbar(
                controller: _scrollCtrl,
                child: ListView(
                controller: _scrollCtrl,
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  const SizedBox(height: AppSpacing.xs),
                  _buildWelcomeCard(),
                  const SizedBox(height: AppSpacing.lg),
                  // First screen mirrors the supervisor dashboard density:
                  // welcome → three headline numbers → the three daily steps.
                  _buildKpiRow(isWide),
                  const SizedBox(height: AppSpacing.lg),
                  _buildTodayThreeThings(),
                  const SizedBox(height: AppSpacing.lg),
                  _collapsibleSection(
                    icon: Icons.fact_check_outlined,
                    title: AppStrings.t('worker.attDetails'),
                    subtitle: AppStrings.t('worker.attDetailsSub'),
                    children: [_buildAttendanceDetailsCard()],
                  ),
                  _collapsibleSection(
                    icon: Icons.assignment_outlined,
                    title: AppStrings.t('worker.tasks'),
                    subtitle: AppStrings.t('worker.tasksSectionSub'),
                    children: [_buildTaskBoardBody(isWide: isWide)],
                  ),
                ],
              ),
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
        borderRadius: AppRadius.rLg,
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

  // ───────────────────────── Beginner-friendly first screen ─────────────────

  /// Section header — same rhythm as the supervisor dashboard.
  Widget _sectionHeader(String title, {String? sub}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: GoogleFonts.inter(
                  fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          if (sub != null) ...[
            const SizedBox(height: 2),
            Text(sub, style: GoogleFonts.inter(fontSize: 11.5, color: AppColors.textMuted)),
          ],
        ],
      );

  String get _statusLabel => _checkedOut
      ? AppStrings.t('worker.statusDone')
      : _checkedIn
          ? AppStrings.t('worker.statusOnSite')
          : AppStrings.t('worker.statusNotIn');

  /// Three headline numbers, mirroring the supervisor dashboard KPI row.
  Widget _buildKpiRow(bool isWide) {
    final tasks = (_taskBoard?['tasks'] as List?) ?? [];
    final pending = tasks.where((t) {
      final s = ((t as Map)['status'] ?? '').toString().toLowerCase().replaceAll(' ', '_');
      return s != 'completed';
    }).length;
    final hours = _hoursToday.toStringAsFixed(1);
    final cards = <Widget>[
      _kpiCard(AppStrings.t('worker.kpiPending'),
          _loadingTasks ? '—' : '$pending', Icons.playlist_add_check_rounded, AppColors.yellow),
      _kpiCard(AppStrings.t('worker.kpiHours'), '${hours}h', Icons.schedule_rounded,
          AppColors.accent),
      _kpiCard(
          AppStrings.t('worker.kpiStatus'),
          _statusLabel,
          _checkedOut
              ? Icons.logout_rounded
              : _checkedIn
                  ? Icons.gps_fixed_rounded
                  : Icons.fingerprint_rounded,
          _checkedOut
              ? AppColors.blue
              : _checkedIn
                  ? AppColors.green
                  : AppColors.textMuted),
    ];
    return Row(
      children: [
        for (var i = 0; i < cards.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: cards[i]),
        ],
      ],
    );
  }

  Widget _kpiCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: AppRadius.rLg,
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.sm,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(height: 8),
        Text(value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
                fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        const SizedBox(height: 2),
        Text(label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
                fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
      ]),
    );
  }

  /// "Today's three things": tasks → clock in → report a problem.
  Widget _buildTodayThreeThings() {
    final tasks = (_taskBoard?['tasks'] as List?) ?? [];
    final Map<String, dynamic>? nextTask =
        tasks.isEmpty ? null : Map<String, dynamic>.from(tasks.first as Map);
    final nextLabel = nextTask == null
        ? AppStrings.t('worker.noTaskToday')
        : '${AppStrings.t('worker.nextUp')}: '
            '${(nextTask['part_section'] ?? nextTask['task_name'] ?? '').toString()}';

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionHeader(AppStrings.t('worker.todayThree'),
          sub: AppStrings.t('worker.todayThreeSub')),
      const SizedBox(height: 10),
      _thingCard(
        icon: Icons.assignment_rounded,
        color: AppColors.accent,
        title: AppStrings.t('worker.thingTasks'),
        subtitle: nextLabel,
        trailing: _thingAction(AppStrings.t('worker.viewAll'), _openTasksTab),
        onTap: _openTasksTab,
        step: 1,
      ),
      const SizedBox(height: 10),
      _thingCard(
        icon: _checkedOut
            ? Icons.logout_rounded
            : _checkedIn
                ? Icons.check_circle_rounded
                : Icons.fingerprint_rounded,
        color: _checkedOut
            ? AppColors.blue
            : _checkedIn
                ? AppColors.green
                : AppColors.yellow,
        title: AppStrings.t('worker.thingCheckIn'),
        subtitle: _statusMsg,
        subtitleIsError: _checkInError,
        trailing: _checkInButton(),
        step: 2,
      ),
      const SizedBox(height: 10),
      _thingCard(
        icon: Icons.report_problem_rounded,
        color: AppColors.red,
        title: AppStrings.t('worker.thingIssue'),
        subtitle: AppStrings.t('worker.thingIssueSub'),
        trailing: _thingAction(AppStrings.t('worker.reportNow'), _openIssuesTab),
        onTap: _openIssuesTab,
        step: 3,
      ),
    ]);
  }

  Widget _thingCard({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required int step,
    Widget? trailing,
    VoidCallback? onTap,
    bool subtitleIsError = false,
  }) {
    return semanticTapTarget(
      label: title,
      hint: subtitle,
      child: Material(
      color: AppColors.bgCard,
      borderRadius: AppRadius.rLg,
      child: InkWell(
        borderRadius: AppRadius.rLg,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: AppRadius.rLg,
            border: Border.all(color: AppColors.border),
            boxShadow: AppShadows.sm,
          ),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14), shape: BoxShape.circle),
              child: Icon(icon, size: 20, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.16), borderRadius: AppRadius.rSm),
                    child: Text('$step',
                        style: GoogleFonts.inter(
                            fontSize: 10.5, fontWeight: FontWeight.w800, color: color)),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary)),
                  ),
                ]),
                const SizedBox(height: 3),
                Text(subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                        fontSize: 11.5,
                        height: 1.35,
                        color: subtitleIsError ? AppColors.red : AppColors.textSecondary,
                        fontWeight: subtitleIsError ? FontWeight.w600 : FontWeight.normal)),
              ]),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing],
          ]),
        ),
      ),
    ));
  }

  Widget _thingAction(String label, VoidCallback onTap) {
    return Material(
      color: AppColors.accentLight,
      borderRadius: AppRadius.rSm,
      child: semanticTapTarget(
        label: label,
        child: InkWell(
        borderRadius: AppRadius.rSm,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(label,
                style: GoogleFonts.inter(
                    fontSize: 11.5, fontWeight: FontWeight.w800, color: AppColors.accent)),
            const SizedBox(width: 2),
            Icon(Icons.chevron_right_rounded, size: 15, color: AppColors.accent),
          ]),
        ),
      )),
    );
  }

  /// Compact clock in / out button that lives inside the second step card.
  Widget _checkInButton() {
    final showCheckOut = _checkedIn && !_checkedOut;
    if (_checkInLoading) {
      return const SizedBox(
          width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4));
    }
    if (_checkedOut) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
            color: AppColors.bgMain, borderRadius: AppRadius.rSm),
        child: Text(AppStrings.t('worker.statusDone'),
            style: GoogleFonts.inter(
                fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
      );
    }
    return ElevatedButton(
      onPressed: showCheckOut ? _doCheckOut : _doCheckIn,
      style: ElevatedButton.styleFrom(
        backgroundColor: showCheckOut ? AppColors.red : AppColors.green,
        foregroundColor: AppColors.onAccent,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.rSm),
      ),
      child: Text(
          showCheckOut ? AppStrings.t('att.checkOut') : AppStrings.t('att.checkIn'),
          style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w800)),
    );
  }

  void _openTasksTab() {
    if (widget.onNavigate != null) {
      widget.onNavigate!(1, 0);
      return;
    }
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const WorkerTasksPage()));
  }

  void _openIssuesTab() {
    if (widget.onNavigate != null) {
      widget.onNavigate!(3, 1);
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => const NotificationsPage(initialTab: 1)));
  }

  /// Collapsible block, same interaction as the supervisor dashboard.
  Widget _collapsibleSection({
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) {
    final expanded = _expandedSections[title] ?? false;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: AppRadius.rLg,
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.sm,
      ),
      child: Column(children: [
        semanticTapTarget(
          label: title,
          hint: expanded ? 'Expanded' : 'Collapsed',
          child: InkWell(
          borderRadius: AppRadius.rLg,
          onTap: () => setState(() => _expandedSections[title] = !expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(children: [
              Icon(icon, size: 16, color: AppColors.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title,
                      style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 1),
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted)),
                ]),
              ),
              AnimatedRotation(
                turns: expanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 180),
                child: Icon(Icons.expand_more_rounded,
                    size: 20, color: AppColors.textMuted),
              ),
            ]),
          ),
        )),
        AnimatedCrossFade(
          firstChild: const SizedBox(width: double.infinity),
          secondChild: Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: Column(children: children),
          ),
          crossFadeState:
              expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 180),
        ),
      ]),
    );
  }

  /// Attendance detail block — project, fence, hours, device. The clock in/out
  /// button now lives in the "three things" card, so this stays a read-only
  /// detail area that is collapsed by default.
  Widget _buildAttendanceDetailsCard() {
    return sectionCard(
      padding: const EdgeInsets.all(16),
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
            color: AppColors.bgMain,
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

        const SizedBox(height: 14),
        Text(
          'Device: $_deviceType • $_deviceInfo',
          style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted),
        ),
      ]),
    );
  }

  /// Task board contents (used inside the collapsed "My tasks" section).
  Widget _buildTaskBoardBody({bool isWide = false}) {
    if (_loadingTasks) {
      return sectionCard(
        padding: const EdgeInsets.all(12),
        child: const SkeletonSection(lines: 4),
      );
    }
    if (_taskBoardError != null && _taskBoard == null) {
      return sectionCard(
        padding: EdgeInsets.zero,
        child: FailureInline(
          error: _taskBoardError,
          onRetry: _loadTaskBoard,
        ),
      );
    }
    final tasks = (_taskBoard?['tasks'] as List?) ?? [];
    return sectionCard(
      padding: const EdgeInsets.all(4),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Row(children: [
            Expanded(
              child: Text(AppStrings.t('worker.tasks'),
                  style: GoogleFonts.inter(
                      fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            ),
            if (_lastUpdated.length >= 16)
              Text(_lastUpdated.substring(11, 16),
                  style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
            IconButton(
              icon: Icon(Icons.refresh_rounded, size: 17, color: AppColors.accent),
              tooltip: AppStrings.t('worker.emptyTasksAction'),
              onPressed: _loadTaskBoard,
            ),
          ]),
        ),
        if (tasks.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
            child: GuidedEmptyState(
              icon: Icons.assignment_outlined,
              title: AppStrings.t('worker.emptyTasksTitle'),
              description: AppStrings.t('worker.emptyTasksDesc'),
              primaryLabel: AppStrings.t('worker.viewAll'),
              primaryIcon: Icons.arrow_forward_rounded,
              onPrimary: _openTasksTab,
              secondaryHint: AppStrings.t('worker.noTasksHint'),
            ),
          )
        else
          LayoutBuilder(builder: (ctx, c) {
            final tiles = tasks.map((e) {
              final task = Map<String, dynamic>.from(e as Map);
              return WorkerTaskTile(
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

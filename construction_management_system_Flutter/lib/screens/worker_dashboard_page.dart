import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../widgets/worker_ui.dart';
import '../theme/responsive.dart';
import '../services/api_service.dart';
import '../services/app_settings.dart';
import '../services/project_cache.dart';
import '../services/gps_notification_service.dart';
import '../services/photo_capture.dart';
import '../widgets/app_scrollbar.dart';
import '../widgets/worker_common_task_card.dart';
import 'attendance_geo_helper.dart';
import 'worker_common_task_page.dart';
import 'worker_task_detail_page.dart';
import 'worker_toolbox_page.dart';

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
  String? _inAt;
  String? _outAt;
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

  /// The three daily jobs (briefing / toolbox / housekeeping) for today.
  List<Map<String, dynamic>> _commonTasks = [];
  bool _loadingCommonTasks = true;
  Object? _commonTasksError;

  /// Collapse state for the secondary blocks (attendance detail, task list).

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
    await Future.wait([
      _loadAttendance(),
      _loadProjects(),
      _loadMe(),
      _loadTaskBoard(),
      _loadCommonTasks(),
    ]);
  }

  /// Today's three jobs. Opening this endpoint is also what creates the rows on
  /// the server, so the checklist exists even on a fresh install.
  Future<void> _loadCommonTasks() async {
    if (mounted) setState(() => _loadingCommonTasks = true);
    try {
      final r = await ApiService().commonTasksToday();
      final raw = r['tasks'];
      final list = <Map<String, dynamic>>[];
      if (raw is List) {
        for (final e in raw) {
          if (e is Map) list.add(Map<String, dynamic>.from(e));
        }
      }
      if (!mounted) return;
      setState(() {
        _commonTasks = list;
        _commonTasksError = null;
        _loadingCommonTasks = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _commonTasksError = e;
        _loadingCommonTasks = false;
      });
    }
  }

  bool _isCommonDone(Map<String, dynamic> t) {
    final s = (t['status'] ?? '').toString().toLowerCase();
    return s == 'done' || s == 'completed';
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
            _inAt = ci == null ? null : _fmtTime(ci);
            _outAt = co == null ? null : _fmtTime(co);
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
    // No web fallback on purpose: the browser build used to fake the GPS
    // position with the project centre, which defeated the geofence entirely.
    // Both conditions (inside the fence + a live selfie) are enforced now.
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
          _statusMsg = kIsWeb
              ? 'Location is unavailable in this browser. Use the BuildSmart app on your phone to check in.'
              : 'Location permission denied or GPS unavailable';
          _checkInLoading = false;
        });
        return;
      }
      // Photo comes after a usable position: there is no point making the
      // worker take a selfie for a check-in that cannot be submitted.
      final photo = await _captureCheckInPhoto();
      if (photo == null) {
        setState(() => _checkInLoading = false);
        return;
      }
      final r = await ApiService().workerCheckIn(
        projectId: _selectedProjectId!,
        lat: pos['lat']!,
        lng: pos['lng']!,
        deviceInfo: _deviceInfo,
        deviceType: _deviceType,
        deviceId: _deviceId,
        photoBase64: photo.base64,
        photoMimeType: photo.mimeType,
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
        _inAt = _fmtTime(r['check_in_time']);
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

  /// Opens the camera for the mandatory check-in selfie.
  ///
  /// Returns null when the worker cancels or the camera is unavailable, after
  /// showing the reason — the caller then aborts the check-in.
  Future<CapturedPhoto?> _captureCheckInPhoto() async {
    setState(() => _statusMsg = 'Opening camera — take a photo of yourself on site...');
    try {
      final photo = await PhotoCapture.takeSelfie();
      setState(() => _statusMsg = 'Photo captured, submitting check-in...');
      return photo;
    } on PhotoCaptureException catch (e) {
      if (!e.cancelled) toast(e.message);
      setState(() {
        _statusMsg = e.cancelled
            ? '❌ A photo of yourself is required to check in.'
            : '❌ ${e.message}';
      });
      return null;
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
      {
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
        _outAt = _fmtTime(r['check_out_time']);
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

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppBreakpoints.maxContentWidth),
        child: SizedBox(
          width: double.infinity,
          child: RefreshIndicator(onRefresh: _loadAll, child: _content()),
        ),
      ),
    );
  }

  Widget _content() {
    return AppScrollbar(
      controller: _scrollCtrl,
      child: ListView(
        controller: _scrollCtrl,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
        children: [
          _greeting(),
          _checkCard(),
          const SizedBox(height: 14),
          _commonTasksSection(),
          const SizedBox(height: 14),
          _numbersRow(),
          const SizedBox(height: 16),
          _tasksSection(),
        ],
      ),
    );
  }

  // ──────────────── greeting (one short line) ────────────────
  Widget _greeting() {
    final name = (_workerName ?? '').trim();
    if (name.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 8),
      child: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.inter(
            fontSize: 19, fontWeight: FontWeight.w900, color: AppColors.textPrimary),
      ),
    );
  }

  // ──────────────── 0. today's three jobs (big icon cards) ────────────────
  Widget _commonTasksSection() {
    final doneCount = _commonTasks.where(_isCommonDone).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 8),
          child: Row(children: [
            Expanded(
              child: Text(
                wT(en: 'TODAY', ms: 'HARI INI', zh: '今日任务'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary),
              ),
            ),
            if (_commonTasks.isNotEmpty)
              Text(
                '$doneCount/${_commonTasks.length}',
                style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: doneCount == _commonTasks.length
                        ? AppColors.green
                        : AppColors.textSecondary),
              ),
            IconButton(
              iconSize: 24,
              color: AppColors.textSecondary,
              tooltip: wT(en: 'REFRESH', ms: 'MUAT SEMULA', zh: '刷新'),
              onPressed: _loadingCommonTasks ? null : _loadCommonTasks,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ]),
        ),
        if (_loadingCommonTasks && _commonTasks.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_commonTasks.isEmpty)
          WErrorHint(
            title: wT(en: 'NO JOBS', ms: 'TIADA KERJA', zh: '暂无任务'),
            hint: _commonTasksError != null
                ? wT(
                    en: 'Could not load. Check network.',
                    ms: 'Gagal muat. Semak rangkaian.',
                    zh: '加载失败，请检查网络',
                  )
                : wT(
                    en: 'Tap to load today again.',
                    ms: 'Tekan untuk muat semula.',
                    zh: '点击重新加载今日任务',
                  ),
            onRetry: _loadCommonTasks,
          )
        else
          for (final t in _commonTasks) ...[
            WCommonTaskCard(
              kind: (t['task_kind'] ?? '').toString(),
              done: _isCommonDone(t),
              onTap: () => _openCommonTask(t),
            ),
            const SizedBox(height: 10),
          ],
      ],
    );
  }

  /// Tapping a card opens its own page. The toolbox job goes to the toolbox hub
  /// (take / return), the other two go straight to the one-photo page.
  Future<void> _openCommonTask(Map<String, dynamic> t) async {
    final id = (t['instance_id'] as num?)?.toInt();
    if (id == null) return;
    final kind = (t['task_kind'] ?? '').toString();
    final done = _isCommonDone(t);

    if (kind == 'toolbox') {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => WorkerToolboxPage(dailyInstanceId: id, dailyDone: done),
      ));
    } else {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => WorkerCommonTaskPage(
          instanceId: id,
          kind: kind,
          initialStatus: (t['status'] ?? 'pending').toString(),
        ),
      ));
    }
    if (!mounted) return;
    await Future.wait([_loadCommonTasks(), _loadTaskBoard()]);
  }

  // ──────────────── 1. one big check-in / check-out action ────────────────
  Widget _checkCard() {
    final working = _checkedIn && !_checkedOut;
    final done = _checkedOut;
    final color = done
        ? AppColors.green
        : working
            ? AppColors.accent
            : AppColors.green;
    final icon = done
        ? Icons.check_rounded
        : working
            ? Icons.logout_rounded
            : Icons.login_rounded;
    final label = done
        ? wT(en: 'DONE', ms: 'SIAP', zh: '已完成')
        : working
            ? wT(en: 'CHECK OUT', ms: 'KELUAR', zh: '下班打卡')
            : wT(en: 'CHECK IN', ms: 'MASUK', zh: '上班打卡');
    final VoidCallback? onTap = done ? null : (working ? _doCheckOut : _doCheckIn);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: AppRadius.rLg,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(children: [
        WBigAction(
          icon: icon,
          label: label,
          color: color,
          height: 112,
          busy: _checkInLoading || _loadingAtt,
          onTap: onTap,
        ),
        const SizedBox(height: 12),
        Tooltip(
          message: _statusMsg,
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              WChip(
                icon: Icons.schedule_rounded,
                label: (_outAt ?? _inAt ?? _fmtNow()),
                color: AppColors.blue,
              ),
              WChip(
                icon: Icons.timelapse_rounded,
                label: '${_hoursToday.toStringAsFixed(1)}h',
                color: AppColors.accent,
              ),
              if (working)
                WChip(
                  icon: Icons.gps_fixed_rounded,
                  label: 'GPS',
                  color: AppColors.green,
                ),
              if (_windowEnforced && _workHours.isNotEmpty)
                WChip(
                  icon: Icons.access_time_rounded,
                  label: _workHours,
                  color: AppColors.textSecondary,
                ),
            ],
          ),
        ),
        if (_checkInError) ...[
          const SizedBox(height: 12),
          WErrorHint(
            title: wT(en: 'OUTSIDE SITE', ms: 'LUAR TAPAK', zh: '不在工地范围'),
            hint: wT(
                en: 'Move to the site. Tap again.',
                ms: 'Pergi ke tapak. Tekan lagi.',
                zh: '走到工地范围内再按一次'),
            onRetry: _checkInLoading ? null : onTap,
          ),
        ],
        const SizedBox(height: 12),
        _siteRow(),
      ]),
    );
  }

  String? get _selectedProjectName {
    if (_selectedProjectId == null) return null;
    for (final p in _projects) {
      final m = Map<String, dynamic>.from(p as Map);
      if (m['project_id'] == _selectedProjectId) {
        return m['project_name']?.toString();
      }
    }
    return null;
  }

  Widget _siteRow() {
    final name = _selectedProjectName ??
        wT(en: 'SELECT SITE', ms: 'PILIH TAPAK', zh: '选择工地');
    return Material(
      color: AppColors.bgMain,
      borderRadius: AppRadius.rMd,
      child: InkWell(
        borderRadius: AppRadius.rMd,
        onTap: _pickSite,
        child: Container(
          height: kWRowTap,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            Icon(Icons.apartment_rounded, size: 26, color: AppColors.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                    fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
              ),
            ),
            Icon(Icons.swap_horiz_rounded, size: 24, color: AppColors.textMuted),
          ]),
        ),
      ),
    );
  }

  /// A dropdown is a literacy test; a list of big names is not.
  Future<void> _pickSite() async {
    if (_projects.isEmpty) {
      toast(wT(en: 'NO SITE', ms: 'TIADA TAPAK', zh: '暂无工地'));
      return;
    }
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppColors.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Text(wT(en: 'MY SITE', ms: 'TAPAK SAYA', zh: '我的工地'),
                style: GoogleFonts.inter(
                    fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.textPrimary)),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: _projects.map((p) {
                final m = Map<String, dynamic>.from(p as Map);
                final id = m['project_id'] as int;
                final selected = id == _selectedProjectId;
                return InkWell(
                  onTap: () => Navigator.pop(ctx, id),
                  child: Container(
                    height: kWRowTap,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(children: [
                      Icon(Icons.apartment_rounded,
                          size: 26,
                          color: selected ? AppColors.accent : AppColors.textMuted),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          m['project_name']?.toString() ?? 'Project $id',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                              fontSize: 17,
                              fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                              color: AppColors.textPrimary),
                        ),
                      ),
                      if (selected)
                        Icon(Icons.check_circle_rounded, size: 24, color: AppColors.green),
                    ]),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _selectedProjectId = picked);
    final sp = await SharedPreferences.getInstance();
    await sp.setInt('project_id', picked);
  }

  // ──────────────── 2. two big numbers ────────────────
  int get _tasksLeft {
    final board = _taskBoard;
    if (board == null) return 0;
    final tasks = (board['tasks'] as List?) ?? [];
    return tasks
        .where((e) => wStatusKey((e as Map)['status']) != 'completed')
        .length;
  }

  Widget _numbersRow() {
    return Row(children: [
      Expanded(
        child: WNumberTile(
          icon: Icons.checklist_rounded,
          value: '$_tasksLeft',
          label: wT(en: 'LEFT', ms: 'BAKI', zh: '剩余'),
          color: AppColors.accent,
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: WNumberTile(
          icon: Icons.schedule_rounded,
          value: '${_hoursToday.toStringAsFixed(1)}h',
          label: wT(en: 'HOURS', ms: 'JAM', zh: '工时'),
          color: AppColors.blue,
        ),
      ),
    ]);
  }

  // ──────────────── 3. three task rows + one big "all tasks" ────────────────
  Widget _tasksSection() {
    if (_loadingTasks && _taskBoard == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_taskBoardError != null && _taskBoard == null) {
      return WErrorHint(
        title: wT(en: 'NO SIGNAL', ms: 'TIADA ISYARAT', zh: '网络不通'),
        hint: wT(en: 'Check internet. Try again.', ms: 'Semak internet. Cuba lagi.', zh: '检查网络后再试'),
        onRetry: _loadTaskBoard,
      );
    }
    final tasks = ((_taskBoard?['tasks'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    if (tasks.isEmpty) {
      return Container(
        padding: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: AppRadius.rLg,
          border: Border.all(color: AppColors.border),
        ),
        child: WEmpty(
          icon: Icons.check_circle_outline_rounded,
          title: wT(en: 'NO TASKS', ms: 'TIADA TUGASAN', zh: '暂无任务'),
          actionLabel: wT(en: 'REFRESH', ms: 'MUAT SEMULA', zh: '刷新'),
          onAction: _loadTaskBoard,
        ),
      );
    }
    final preview = tasks.take(3).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ...preview.map((t) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: WTaskRow(task: t, onTap: () => _openTask(t)),
          )),
      WBigAction(
        icon: Icons.list_alt_rounded,
        label: wT(en: 'ALL TASKS', ms: 'SEMUA', zh: '全部任务'),
        color: AppColors.blue,
        height: kWPrimaryTap,
        onTap: _openTasksTab,
      ),
    ]);
  }

  void _openTasksTab() {
    widget.onNavigate?.call(1, 0);
  }
}

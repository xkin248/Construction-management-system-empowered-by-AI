import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import 'attendance_geo_helper.dart';

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
  String _checkInWindow = '05:00 - 10:30';
  String _checkOutWindow = '15:00 - 21:00';
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
    _initDevice();
    _loadAll();
    _startAutoSync();
  }

  @override
  void dispose() {
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
      _projects = await ApiService().getProjects();
      if (_projects.isNotEmpty && _selectedProjectId == null) {
        final sp = await SharedPreferences.getInstance();
        final savedPid = sp.getInt('project_id');
        if (savedPid != null) {
          _selectedProjectId = savedPid;
        } else {
          _selectedProjectId = _projects.first['project_id'] as int;
        }
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
          final att = r['attendance'] as Map?;
          if (att != null) {
            _attendanceId = att['attendance_id'] as int?;
            final ci = att['check_in_time'];
            if (ci != null) {
              final t = ci.toString().substring(11, 16);
              _statusMsg = _checkedOut
                  ? '👋 Checked out — completed today at $t'
                  : '✅ Currently checked in — arrived at $t';
            }
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
      setState(() {
        _checkedIn = true;
        _checkInError = false;
        _attendanceId = r['attendance_id'] as int?;
        final t = r['check_in_time']?.toString().substring(11, 16) ?? _fmtNow();
        _statusMsg = 'Checked in successfully at $t';
        _checkInLoading = false;
      });
      toast('Checked in! Device: $_deviceType');
    } on DioException catch (e) {
      setState(() {
        _statusMsg = e.message ?? 'Check-in failed';
        _checkInError = true;
        _checkInLoading = false;
      });
    } catch (e) {
      setState(() {
        _statusMsg = 'Error: $e';
        _checkInError = true;
        _checkInLoading = false;
      });
    }
  }

  void _simulateGpsCheckIn() async {
    setState(() {
      _checkInLoading = true;
      _statusMsg = 'Using simulated location for web (demo mode)...';
    });
    await Future.delayed(const Duration(milliseconds: 500));
    try {
      final defaultLat = _projects.isNotEmpty
          ? (_projects.first['center_lat'] as num? ?? 3.1390).toDouble()
          : 3.1390;
      final defaultLng = _projects.isNotEmpty
          ? (_projects.first['center_lng'] as num? ?? 101.6869).toDouble()
          : 101.6869;
      final r = await ApiService().workerCheckIn(
        projectId: _selectedProjectId!,
        lat: defaultLat,
        lng: defaultLng,
        deviceInfo: _deviceInfo,
        deviceType: _deviceType,
        deviceId: _deviceId,
      );
      setState(() {
        _checkedIn = true;
        _attendanceId = r['attendance_id'] as int?;
        final t = r['check_in_time']?.toString().substring(11, 16) ?? _fmtNow();
        _statusMsg = '✅ Checked in (simulated GPS) at $t';
        _checkInLoading = false;
      });
      toast('✅ Web demo: Checked in successfully!');
    } on DioException catch (e) {
      setState(() {
        _statusMsg = e.message ?? 'Check-in failed';
        _checkInLoading = false;
      });
    } catch (e) {
      setState(() {
        _statusMsg = 'Error: $e';
        _checkInLoading = false;
      });
    }
  }

  Future<void> _doCheckOut() async {
    if (_attendanceId == null) return;
    setState(() {
      _checkInLoading = true;
      _statusMsg = 'Processing check-out...';
    });
    try {
      final defaultLat = _projects.isNotEmpty
          ? (_projects.first['center_lat'] as num? ?? 3.1390).toDouble()
          : 3.1390;
      final defaultLng = _projects.isNotEmpty
          ? (_projects.first['center_lng'] as num? ?? 101.6869).toDouble()
          : 101.6869;
      final r = await ApiService().workerCheckOut(
        lat: defaultLat,
        lng: defaultLng,
        deviceInfo: _deviceInfo,
        deviceType: _deviceType,
      );
      setState(() {
        _checkedIn = false;
        _checkedOut = true;
        _attendanceId = null;
        final t = r['check_out_time']?.toString().substring(11, 16) ?? _fmtNow();
        _statusMsg = '👋 Checked out at $t. Thank you for today!';
        _checkInLoading = false;
      });
      toast('👋 Checked out successfully. See you tomorrow!');
    } on DioException catch (e) {
      setState(() {
        _statusMsg = e.message ?? 'Check-out failed';
        _checkInLoading = false;
      });
    } catch (e) {
      setState(() {
        _statusMsg = 'Error: $e';
        _checkInLoading = false;
      });
    }
  }

  String _fmtNow() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildWelcomeCard(),
          const SizedBox(height: 16),
          _buildCheckInCard(),
          const SizedBox(height: 16),
          _buildAIBanner(),
          const SizedBox(height: 12),
          _buildTaskBoard(),
        ],
      ),
    );
  }

  Widget _buildWelcomeCard() {
    final name = _workerName ?? 'Worker';
    final hour = DateTime.now().hour;
    final greeting = hour < 12 ? 'Good Morning' : hour < 18 ? 'Good Afternoon' : 'Good Evening';
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.green, AppColors.green.withValues(alpha: 0.75)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: AppColors.green.withValues(alpha: 0.18), blurRadius: 18, offset: const Offset(0, 6))],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: Colors.white.withValues(alpha: 0.25),
            child: initialsAvatar(name, radius: 24, seed: 'worker-$name'),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$greeting, ${name.split(' ').first}!',
                  style: GoogleFonts.outfit(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('BuildSmart Worker Portal',
                  style: GoogleFonts.outfit(color: Colors.white.withValues(alpha: 0.85), fontSize: 14)),
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 4, children: [
                _welcomeChip(Icons.badge_rounded, 'Worker Portal'),
                _welcomeChip(Icons.auto_awesome_rounded, 'AI Assisted'),
                if (_checkedIn) _welcomeChip(Icons.gps_fixed, 'On Site', bg: Colors.white.withValues(alpha: 0.9), fg: AppColors.green),
              ]),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(_fmtNow(),
                style: GoogleFonts.outfit(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
            Text(DateTime.now().toString().substring(0, 10),
                style: GoogleFonts.outfit(color: Colors.white.withValues(alpha: 0.85), fontSize: 13)),
          ]),
        ],
      ),
    );
  }

  Widget _welcomeChip(IconData icon, String label, {Color? bg, Color? fg}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: bg ?? Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(10)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: fg ?? Colors.white),
        const SizedBox(width: 4),
        Text(label, style: GoogleFonts.outfit(color: fg ?? Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
      ]),
    );
  }

  Widget _buildCheckInCard() {
    final showCheckOut = _checkedIn && !_checkedOut;
    return sectionCard(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('📍 Daily Attendance Check-In',
              style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
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
          const SizedBox(height: 14),
          // Show fence radius for selected project
          if (_selectedProjectId != null) Builder(builder: (ctx) {
            final sel = _projects.firstWhere(
              (p) => p['project_id'] == _selectedProjectId,
              orElse: () => {},
            );
            final r = (sel['fence_radius'] as num?)?.toInt() ?? 0;
            if (r == 0) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(children: [
                const Icon(Icons.radar_rounded, size: 13, color: AppColors.green),
                const SizedBox(width: 5),
                Text(
                  'You must be within ${r}m of the site to check in',
                  style: GoogleFonts.outfit(fontSize: 13, color: AppColors.green, fontWeight: FontWeight.w600),
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
            const SizedBox(height: 14),
            SizedBox(
              width: 260,
              child: Text(
                _statusMsg,
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  color: _checkInError ? AppColors.red : AppColors.textSecondary,
                  fontWeight: _checkInError ? FontWeight.w600 : FontWeight.normal,
                  height: 1.4,
                ),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 6),
        if (_hoursToday > 0)
          Text('Hours worked today: ${_hoursToday.toStringAsFixed(1)}h',
              style: GoogleFonts.outfit(fontSize: 14, color: AppColors.accent, fontWeight: FontWeight.w700)),
        const SizedBox(height: 18),

        Row(children: [
          const SizedBox(width: 4),
          Text('Check-in: $_checkInWindow',
              style: GoogleFonts.outfit(fontSize: 13, color: AppColors.green, fontWeight: FontWeight.w700)),
          const Spacer(),
          Text('Check-out: $_checkOutWindow',
              style: GoogleFonts.outfit(fontSize: 13, color: AppColors.blue, fontWeight: FontWeight.w700)),
          const SizedBox(width: 4),
        ]),
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
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Icon(showCheckOut ? Icons.logout_rounded : Icons.fingerprint_rounded, size: 22),
            label: Text(
              _checkedOut
                  ? 'Attendance Completed Today'
                  : showCheckOut
                      ? 'Tap to Check Out'
                      : '🎯 Tap to Check In (GPS)',
              style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w800),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _checkedOut
                  ? AppColors.textMuted
                  : showCheckOut
                      ? AppColors.red
                      : AppColors.green,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Device: $_deviceType • $_deviceInfo',
          style: GoogleFonts.outfit(fontSize: 14, color: AppColors.textMuted),
        ),
      ]),
    );
  }

  Widget _buildAIBanner() {
    final alert = _taskBoard?['alert']?.toString();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: alert != null && alert.isNotEmpty ? AppColors.yellowLight : AppColors.purpleLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: alert != null && alert.isNotEmpty ? AppColors.yellow.withValues(alpha: 0.4) : AppColors.purple.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        Icon(
          alert != null && alert.isNotEmpty ? Icons.warning_amber_rounded : Icons.auto_awesome_rounded,
          size: 20,
          color: alert != null && alert.isNotEmpty ? AppColors.yellow : AppColors.purple,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            alert != null && alert.isNotEmpty ? '⚠ Alert: $alert' : (_taskBoard?['summary']?.toString() ?? '🤖 AI analyzing your tasks...'),
            style: GoogleFonts.outfit(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: alert != null && alert.isNotEmpty ? const Color(0xFF92400E) : const Color(0xFF5B21B6),
              height: 1.35,
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildTaskBoard() {
    if (_loadingTasks) {
      return sectionCard(
        padding: const EdgeInsets.all(24),
        child: const Column(children: [
          SizedBox(height: 18),
          Center(child: CircularProgressIndicator()),
          SizedBox(height: 12),
          Center(child: Text('Loading AI task board...', style: TextStyle(color: AppColors.textMuted, fontSize: 14))),
          SizedBox(height: 18),
        ]),
      );
    }
    final tasks = (_taskBoard?['tasks'] as List?) ?? [];
    return sectionCard(
      padding: const EdgeInsets.all(4),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Row(children: [
            Text('🎯 My Assigned Work Sections',
                style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            const Spacer(),
            if (_lastUpdated.isNotEmpty)
              Text(_lastUpdated.substring(11, 16),
                  style: GoogleFonts.outfit(fontSize: 14, color: AppColors.textMuted, fontWeight: FontWeight.w700)),
            IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 17, color: AppColors.accent),
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
                decoration: BoxDecoration(color: AppColors.accentLight, borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.assignment_outlined, size: 26, color: AppColors.accent),
              ),
              const SizedBox(height: 12),
              Text('No tasks assigned yet',
                  style: GoogleFonts.outfit(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              const SizedBox(height: 4),
              Text('Your supervisor or AI will assign tasks to your account.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(fontSize: 14, color: AppColors.textMuted)),
            ]),
          )
        else
          ...tasks.asMap().entries.map((e) => _TaskTile(
                idx: e.key,
                task: Map<String, dynamic>.from(e.value as Map),
              )),
      ]),
    );
  }
}

class _TaskTile extends StatelessWidget {
  final int idx;
  final Map<String, dynamic> task;
  const _TaskTile({required this.idx, required this.task});

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
    final conf = (task['ai_confidence'] as num?)?.toDouble() ?? 0;
    final part = task['part_section']?.toString() ?? 'General Section';
    final instructions = task['work_instructions']?.toString() ?? '';
    final projectName = task['project_name']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: idx.isEven ? AppColors.bgMain.withValues(alpha: 0.4) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: AppColors.accentLight, borderRadius: BorderRadius.circular(8)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.layers_rounded, size: 11, color: AppColors.accent),
                const SizedBox(width: 4),
                Text(part,
                    style: GoogleFonts.outfit(color: AppColors.accent, fontSize: 14, fontWeight: FontWeight.w800)),
              ]),
            ),
            const SizedBox(width: 8),
            statusPill(status),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: _priorityColor(priority).withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(priority.toUpperCase(),
                  style: GoogleFonts.outfit(
                    color: _priorityColor(priority),
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  )),
            ),
          ]),
          const SizedBox(height: 8),
          Text(task['task_name']?.toString() ?? 'Unnamed Task',
              style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          if (task['description']?.toString().isNotEmpty ?? false) ...[
            const SizedBox(height: 4),
            Text(task['description'].toString(),
                style: GoogleFonts.outfit(fontSize: 14, color: AppColors.textSecondary, height: 1.4)),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              if (projectName.isNotEmpty)
                _miniTag(Icons.apartment_rounded, projectName, AppColors.blue),
              if (task['due_date'] != null)
                _miniTag(Icons.event_rounded, 'Due: ${task['due_date'].toString().substring(0, 10)}', AppColors.textSecondary),
              if (conf > 0)
                _miniTag(
                    Icons.auto_awesome_rounded,
                    'AI ${(conf * 100).toInt()}% confidence',
                    conf >= 0.7 ? AppColors.green : conf >= 0.4 ? AppColors.yellow : AppColors.red),
            ],
          ),
          if (instructions.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.blueLight,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.blue.withValues(alpha: 0.3)),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.lightbulb_circle_rounded, size: 16, color: AppColors.blue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(instructions,
                      style: GoogleFonts.outfit(fontSize: 13, color: Color(0xFF1E40AF), height: 1.4, fontWeight: FontWeight.w600)),
                ),
              ]),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _miniTag(IconData icon, String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 10.5, color: color),
          const SizedBox(width: 3.5),
          Text(label,
              style: GoogleFonts.outfit(color: color, fontSize: 14, fontWeight: FontWeight.w700)),
        ]),
      );
}

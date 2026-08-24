import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../services/app_settings.dart';
import '../services/gps_notification_service.dart';
import '../l10n/app_strings.dart';
import '../widgets/charts.dart';
import '../widgets/app_settings_actions.dart';
import 'attendance_geo_helper.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  bool ld = true;
  Map kpi = {};
  Map attSummary = {};
  List projects = [];
  List<Map> _weeklyAtt = [];
  Timer? _autoRefreshTimer;

  // Supervisor quick check-in from the dashboard.
  bool _isSupervisor = false;
  bool _supLoading = false;
  bool _supCheckedIn = false;
  String _supMsg = AppStrings.t('dash.checkinHint');

  // One-tap AI auto-assign (global — no project selection required).
  bool _autoAssigning = false;
  String _autoAssignMsg = 'One-tap AI auto-assign for all open tasks';

  @override
  void initState() {
    super.initState();
    AppColors.darkMode.addListener(_rebuild);
    AppSettings.lang.addListener(_rebuild);
    _load();
    _loadSupervisorAttendance();
    _startAutoRefresh();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  Future<void> _loadSupervisorAttendance() async {
    try {
      final me = await ApiService().me();
      final t = (me['user_type'] ?? '').toString().toLowerCase();
      final r = (me['role'] ?? '').toString().toLowerCase();
      final isSup = t.contains('supervisor') || r.contains('supervisor');
      if (!mounted || !isSup) return;
      setState(() => _isSupervisor = true);
      final today = await ApiService().supervisorTodayAttendance();
      final rec = today['attendance'];
      if (rec is Map && rec['status'] != null) {
        final status = rec['status'].toString();
        if (status == 'checked_in') {
          final ci = rec['check_in_time']?.toString() ?? '';
          setState(() {
            _supCheckedIn = true;
            _supMsg = ci.length >= 16
                ? 'Checked in at ${ci.substring(11, 16)}'
                : AppStrings.t('dash.checkedInToday');
          });
        }
      }
    } catch (_) {
      // Role/status fetch failure is non-blocking — hide the quick check-in card.
      if (mounted) setState(() => _isSupervisor = false);
    }
  }

  Future<void> _quickCheckIn() async {
    if (kIsWeb) {
      toast('GPS check-in is not supported in web browsers — use the mobile app.');
      return;
    }
    setState(() { _supLoading = true; _supMsg = 'Getting your location...'; });
    try {
      if (!await GeoHelper.isServiceEnabled()) {
        await GpsNotificationService.requestEnable();
        setState(() {
          _supMsg = 'Please enable GPS from the notification, then try again.';
          _supLoading = false;
        });
        return;
      }
      final pos = await GeoHelper.getCurrentPosition();
      if (pos == null) {
        setState(() { _supMsg = 'Location permission denied'; _supLoading = false; });
        return;
      }
      int? pid;
      if (projects.isNotEmpty) {
        pid = projects.first['project_id'] as int;
      }
      if (!mounted) return;
      if (projects.length > 1) {
        pid = await showDialog<int>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: Text(AppStrings.t('tasks.selectProject')),
            children: projects.map<Widget>((p) {
              final pj = p['project_id'] as int;
              return SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, pj),
                child: Text(p['project_name']?.toString() ?? 'Project $pj'),
              );
            }).toList(),
          ),
        );
        if (pid == null) {
          setState(() { _supMsg = 'Check-in cancelled'; _supLoading = false; });
          return;
        }
      }
      await ApiService().supervisorCheckIn(
        projectId: pid ?? 1,
        lat: pos['lat']!,
        lng: pos['lng']!,
      );
      setState(() {
        _supCheckedIn = true;
        _supMsg = 'Checked in at ${_fmtHm()}';
        _supLoading = false;
      });
      toast('Checked in successfully');
    } on DioException catch (e) {
      setState(() {
        _supMsg = e.message ?? 'Check-in failed';
        _supLoading = false;
      });
      toast(e.message ?? 'Check-in failed');
    } catch (e) {
      setState(() { _supMsg = 'Error: $e'; _supLoading = false; });
    }
  }

  Future<void> _quickCheckOut() async {
    if (kIsWeb) {
      toast('GPS check-out is not supported in web browsers — use the mobile app.');
      return;
    }
    setState(() { _supLoading = true; _supMsg = 'Getting your location...'; });
    try {
      final pos = await GeoHelper.getCurrentPosition();
      if (pos == null) {
        setState(() { _supMsg = 'Location permission denied'; _supLoading = false; });
        return;
      }
      await ApiService().supervisorCheckOut(lat: pos['lat']!, lng: pos['lng']!);
      setState(() {
        _supCheckedIn = false;
        _supMsg = 'Checked out at ${_fmtHm()}';
        _supLoading = false;
      });
      toast('Checked out successfully');
    } on DioException catch (e) {
      setState(() { _supMsg = e.message ?? 'Check-out failed'; _supLoading = false; });
      toast(e.message ?? 'Check-out failed');
    } catch (e) {
      setState(() { _supMsg = 'Error: $e'; _supLoading = false; });
    }
  }

  Future<void> _autoAssignAll() async {
    if (_autoAssigning) return;
    setState(() {
      _autoAssigning = true;
      _autoAssignMsg = 'Analyzing all open tasks...';
    });
    try {
      final res = await ApiService().aiAutoAssign(null, dryRun: false);
      final assigns = (res['assignments'] as List? ?? []);
      int assigned = 0;
      for (final a in assigns) {
        if (a is Map && a['assigned_worker_id'] != null) assigned++;
      }
      final total = assigns.length;
      if (!mounted) return;
      final msg = total == 0
          ? 'No open tasks to assign'
          : 'Auto-assigned $assigned of $total open task(s)';
      setState(() {
        _autoAssigning = false;
        _autoAssignMsg = msg;
      });
      toast(msg);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _autoAssigning = false;
        _autoAssignMsg = 'Auto-assign failed — check server connection';
      });
      toast('Auto-assign failed: $e');
    }
  }

  String _fmtHm() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }

  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer =
        Timer.periodic(const Duration(seconds: 60), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    AppColors.darkMode.removeListener(_rebuild);
    AppSettings.lang.removeListener(_rebuild);
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false, bool forceRefresh = false}) async {
    if (!silent) setState(() => ld = true);
    try {
      final results = await Future.wait([
        ApiService().kpi(),
        ApiService().attendanceToday(),
        ApiService().getProjects(),
        ApiService().getWeeklyAttendanceStats(),
      ]);
      kpi = results[0] as Map;
      attSummary = results[1] as Map;
      projects = results[2] as List;
      final weekly = results[3] as Map;
      if (mounted) {
        setState(() {
          _weeklyAtt = List<Map>.from(weekly['days'] ?? []);
        });
      }
    } catch (e) {
      if (!silent) toast('Failed to load dashboard: $e');
    } finally {
      if (mounted) setState(() => ld = false);
    }
  }

  @override
  Widget build(BuildContext c) {
    if (ld) {
      return const Center(child: CircularProgressIndicator());
    }

    final onSite = kpi['today_attendance'] ?? 0;
    final totalWorkers = kpi['total_workers'] ?? 0;
    final activeTasks = kpi['pending_tasks'] ?? 0;
    final productivity = kpi['productivity'] ?? 76;
    final alerts = kpi['open_issues'] ?? 0;
    final present = (attSummary['present'] ?? 0) as int;
    final late = (attSummary['late'] ?? 0) as int;
    final absent = (attSummary['absent'] ?? 0) as int;
    final totalAtt = (attSummary['total'] ?? totalWorkers) as int;
    final todayRate = totalAtt > 0 ? ((present + late) / totalAtt * 100).round() : 0;

    // Weekly attendance data from backend (Mon-Sun, daily attendance count of the current week)
    final weeklyData = _weeklyAtt
        .map((d) => ((d['present_workers'] ?? d['check_in_count'] ?? 0) as num).toDouble())
        .toList();
    final weekLabels = _weeklyAtt.map((d) {
      final wd = ((d['weekday'] as num?) ?? 0).toInt();
      const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return names[wd.clamp(0, 6).toInt()];
    }).toList();

    // Task distribution from KPI
    final completed = (kpi['completed_tasks'] ?? 0) as int;
    final inProgress = (kpi['in_progress_tasks'] ?? 0) as int;
    final pending = (kpi['pending_tasks'] ?? 0) as int;
    final totalTasks = completed + inProgress + pending;
    final completedPct = totalTasks > 0 ? (completed / totalTasks * 100).toInt() : 42;
    final inProgressPct = totalTasks > 0 ? (inProgress / totalTasks * 100).toInt() : 33;
    final pendingPct = totalTasks > 0 ? (pending / totalTasks * 100).toInt() : 25;
    final upcoming = _upcomingProjects();

    return LayoutBuilder(
      builder: (context, constraints) {
        final isPhone = constraints.maxWidth < 600;
        final hPad = isPhone ? 14.0 : 20.0;
        final vPad = isPhone ? 14.0 : 20.0;
        return RefreshIndicator(
      onRefresh: () => _load(forceRefresh: true),
      child: ListView(
        padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
        children: [
          // ── Language / Theme switcher ──
          Align(
            alignment: Alignment.centerRight,
            child: AppSettingsActions(),
          ),
          const SizedBox(height: 4),
          // ── Supervisor Quick Check-in ──
          if (_isSupervisor) ...[
            _buildQuickCheckInCard(),
            const SizedBox(height: 12),
            _buildAutoAssignCard(),
            const SizedBox(height: 20),
          ],

          // ── KPI Cards Row ──
          _buildKpiRow(onSite, totalWorkers, activeTasks, productivity, alerts, todayRate, present, late, absent),
          const SizedBox(height: 20),

          // ── Charts Row ──
          LayoutBuilder(builder: (ctx, cs) {
            final isWide = cs.maxWidth > 600;
            if (isWide) {
              return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(flex: 3, child: _weeklyAttCard(weeklyData, weekLabels)),
                const SizedBox(width: 16),
                SizedBox(width: 240, child: _taskDistCard(completedPct, inProgressPct, pendingPct)),
              ]);
            }
            return Column(children: [
              _weeklyAttCard(weeklyData, weekLabels),
              const SizedBox(height: 16),
              _taskDistCard(completedPct, inProgressPct, pendingPct),
            ]);
          }),
          const SizedBox(height: 20),

          // ── Productivity by Project ──
          _sectionHeader('Productivity Trend by Project', sub: 'Weekly task completion rate (%)'),
          const SizedBox(height: 12),
          if (projects.isEmpty)
            Padding(padding: EdgeInsets.all(20), child: Center(child: Text(AppStrings.t('proj.noProjects'), style: TextStyle(color: AppColors.textMuted))))
          else
            ...projects.take(4).map((p) => _projectProductivityRow(p)),
          const SizedBox(height: 24),

          // ── Upcoming Due Projects ──
          _sectionHeader('Upcoming Due Projects', sub: 'Projects due within 30 days or overdue'),
          const SizedBox(height: 12),
          if (upcoming.isEmpty)
            Padding(padding: EdgeInsets.all(20), child: Center(child: Text(AppStrings.t('dash.noDueProjects'), style: TextStyle(color: AppColors.textMuted))))
          else
            ...upcoming.map((p) => _upcomingProjectCard(p)),
          const SizedBox(height: 24),

          // ── Recent activity / status kept minimal — AI prediction blocks removed ──
          const SizedBox(height: 24),
        ],
      ),
    );
      },
    );
  }

  // ── Supervisor quick check-in card ──
  Widget _buildQuickCheckInCard() {
    final accent = _supCheckedIn ? AppColors.green : AppColors.accent;
    final bg = _supCheckedIn ? AppColors.greenLight : AppColors.accentLight;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
          child: Icon(
            _supCheckedIn ? Icons.check_circle_rounded : Icons.location_on_rounded,
            color: accent,
            size: 24,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_supCheckedIn ? AppStrings.t('dash.onSite') : AppStrings.t('dash.quickCheckin'),
                style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            const SizedBox(height: 2),
            Text(_supMsg,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(fontSize: 12.5, color: AppColors.textSecondary)),
          ]),
        ),
        const SizedBox(width: 10),
        _supLoading
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5))
            : ElevatedButton.icon(
                onPressed: _supCheckedIn ? _quickCheckOut : _quickCheckIn,
                icon: Icon(_supCheckedIn ? Icons.logout_rounded : Icons.login_rounded, size: 16),
                label: Text(_supCheckedIn ? AppStrings.t('att.checkOut') : AppStrings.t('att.checkIn')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
              ),
      ]),
    );
  }

  // ── One-tap AI Auto-Assign card (global, no project selection) ──
  Widget _buildAutoAssignCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: AppColors.purple.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.auto_awesome_rounded, color: AppColors.purple, size: 24),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(AppStrings.t('dash.autoAssignTasks'),
                style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            const SizedBox(height: 2),
            Text(_autoAssignMsg,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(fontSize: 12.5, color: AppColors.textSecondary)),
          ]),
        ),
        const SizedBox(width: 10),
        _autoAssigning
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5))
            : ElevatedButton.icon(
                onPressed: _autoAssignAll,
                icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                label: Text(AppStrings.t('dash.autoAssign')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.purple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
              ),
      ]),
    );
  }

  // ── KPI row builder ──
  Widget _buildKpiRow(onSite, totalWorkers, activeTasks, productivity, alerts, todayRate, present, late, absent) {
    return LayoutBuilder(builder: (ctx, cs) {
      final isWide = cs.maxWidth > 600;
      final cards = [
        _kpiCard(
          label: AppStrings.t('dash.todayAttendanceRate'),
          value: '$todayRate%',
          sub: '$onSite/$totalWorkers on site · $late late · $absent absent',
          icon: Icons.fact_check_rounded,
          iconColor: AppColors.accent,
        ),
        _kpiCard(
          label: 'Active Tasks',
          value: '$activeTasks',
          sub: '2 completed today',
          icon: Icons.assignment_rounded,
          iconColor: AppColors.blue,
        ),
        _kpiCard(
          label: 'Overall Productivity',
          value: '$productivity%',
          sub: '+4% from last week',
          icon: Icons.trending_up_rounded,
          iconColor: AppColors.green,
          valueColor: AppColors.green,
        ),
        _kpiCard(
          label: 'Alerts',
          value: '$alerts',
          sub: '2 attendance • 1 safety',
          icon: Icons.warning_amber_rounded,
          iconColor: AppColors.red,
        ),
      ];

      if (isWide) {
        return Row(children: cards.expand((c) => [Expanded(child: c), const SizedBox(width: 14)]).toList()..removeLast());
      }
      return Column(children: [
        Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Expanded(child: cards[0]), const SizedBox(width: 12), Expanded(child: cards[1])]),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Expanded(child: cards[2]), const SizedBox(width: 12), Expanded(child: cards[3])]),
      ]);
    });
  }

  Widget _kpiCard({required String label, required String value, String? sub, required IconData icon, required Color iconColor, Color? valueColor}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Text(label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 15, color: iconColor),
          ),
        ]),
        const SizedBox(height: 8),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value,
              style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w800, color: valueColor ?? AppColors.textPrimary)),
        ),
        if (sub != null) ...[
          const SizedBox(height: 3),
          Text(sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textMuted)),
        ],
      ]),
    );
  }

  // ── Weekly Attendance Chart Card ──
  Widget _weeklyAttCard(List<double> data, List<String> labels) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Flexible(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(AppStrings.t('dash.weeklyAttendance'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              Text(AppStrings.t('dash.allProjectsCombined'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textMuted)),
            ]),
          ),
          TextButton(
            onPressed: () {},
            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
            child: Text('${AppStrings.t('dash.viewAll')} →',
                style: GoogleFonts.outfit(fontSize: 13, color: AppColors.accent, fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 14),
        LabeledBarChart(values: data, labels: labels, height: 140, color: AppColors.blue.withValues(alpha: 0.25), highlightColor: AppColors.blue),
      ]),
    );
  }

  // ── Task Distribution Donut Card ──
  Widget _taskDistCard(int completedPct, int inProgressPct, int pendingPct) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(AppStrings.t('dash.taskDistribution'),
            style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        Text(AppStrings.t('dash.allActiveProjects'),
            style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textMuted)),
        const SizedBox(height: 16),
        Center(
          child: SimpleDonutChart(
            size: 110,
            slices: [
              DonutSlice(completedPct.toDouble(), AppColors.green, 'Completed'),
              DonutSlice(inProgressPct.toDouble(), AppColors.accent, 'In Progress'),
              DonutSlice(pendingPct.toDouble(), AppColors.border, 'Pending'),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _legendRow('Completed', '$completedPct%', AppColors.green),
        const SizedBox(height: 6),
        _legendRow('In Progress', '$inProgressPct%', AppColors.accent),
        const SizedBox(height: 6),
        _legendRow('Pending', '$pendingPct%', AppColors.textMuted),
      ]),
    );
  }

  Widget _legendRow(String label, String pct, Color color) => Row(children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: GoogleFonts.outfit(fontSize: 14, color: AppColors.textSecondary))),
        Text(pct, style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
      ]);

  Widget _sectionHeader(String title, {String? sub}) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        if (sub != null)
          Text(sub,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textMuted)),
      ]);

  Widget _projectProductivityRow(Map p) {
    final progress = (p['progress'] as num? ?? 0).toDouble();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Expanded(
            child: Text(p['project_name'] ?? '-',
                style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700),
                overflow: TextOverflow.ellipsis),
          ),
          Text('${progress.toStringAsFixed(0)}%',
              style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.accent)),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: progress / 100,
            minHeight: 6,
            backgroundColor: AppColors.border,
            valueColor: AlwaysStoppedAnimation(AppColors.accent),
          ),
        ),
      ]),
    );
  }

  // ── Upcoming Due Projects ──
  List _upcomingProjects() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due = projects.where((p) {
      final status = (p['status'] as String? ?? '').toLowerCase();
      if (status == 'completed' || status == 'done') return false;
      final end = DateTime.tryParse((p['end_date'] as String?) ?? '');
      if (end == null) return false;
      final endDay = DateTime(end.year, end.month, end.day);
      return endDay.difference(today).inDays <= 30;
    }).toList();
    due.sort((a, b) {
      final da = DateTime.tryParse((a['end_date'] as String?) ?? '') ?? DateTime(9999);
      final db = DateTime.tryParse((b['end_date'] as String?) ?? '') ?? DateTime(9999);
      return da.compareTo(db);
    });
    return due;
  }

  Widget _upcomingProjectCard(Map p) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final end = DateTime.tryParse((p['end_date'] as String?) ?? '');
    int daysLeft = 0;
    if (end != null) {
      final endDay = DateTime(end.year, end.month, end.day);
      daysLeft = endDay.difference(today).inDays;
    }
    final overdue = daysLeft < 0;
    final dueToday = daysLeft == 0;
    final label = overdue ? '${-daysLeft} day(s) overdue' : (dueToday ? 'Due today' : '$daysLeft day(s) left');
    final color = overdue ? AppColors.red : (dueToday ? AppColors.yellow : AppColors.green);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
          child: Icon(overdue ? Icons.event_busy_rounded : (dueToday ? Icons.event_available_rounded : Icons.event_rounded), size: 18, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p['project_name'] ?? '-', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text('Due: ${_fmtDate((p['end_date'] as String?) ?? '')}', style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textMuted)),
          ]),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
          child: Text(label, style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
        ),
      ]),
    );
  }


  String _fmtDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
    } catch (_) {
      return iso;
    }
  }
}

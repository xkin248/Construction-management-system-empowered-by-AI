import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../services/app_settings.dart';
import '../services/project_cache.dart';
import '../services/gps_notification_service.dart';
import '../l10n/app_strings.dart';
import '../utils/date_helper.dart';
import '../widgets/charts.dart';
import 'attendance_geo_helper.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  bool ld = true;
  String? _loadError;
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

  // AI Progress Prediction — manual trigger only (never on refresh, to save tokens).
  int? _predProjectId;
  bool _predLoading = false;
  Map? _prediction;
  int? _predictionPid; // project id that _prediction belongs to (avoid stale display)

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
    final errs = <String>[];

    Future<void> safe(String tag, Future<dynamic> f, void Function(dynamic) assign) async {
      try {
        assign(await f);
      } catch (e) {
        errs.add('$tag: $e');
      }
    }

    // Load each section independently so a single failed endpoint (500/timeout)
    // never blanks out the whole dashboard on mobile.
    await Future.wait([
      safe('kpi', ApiService().kpi(), (v) => kpi = v as Map),
      safe('attendance', ApiService().attendanceToday(), (v) => attSummary = v as Map),
      safe('projects', ProjectCache.get(ApiService()), (v) => projects = v as List),
      safe('weekly', ApiService().getWeeklyAttendanceStats(), (v) {
        final weekly = v as Map;
        _weeklyAtt = List<Map>.from(weekly['days'] ?? []);
      }),
    ]);

    if (mounted) {
      setState(() {
        ld = false;
        _loadError = errs.isEmpty ? null : errs.join('\n');
      });
      if (errs.isNotEmpty && !silent) toast('Some dashboard data failed to load: ${errs.first}');
    }
  }

  @override
  Widget build(BuildContext c) {
    if (ld) {
      return Container(
        color: AppColors.bgMain,
        child: Center(
          child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2.5),
        ),
      );
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
    final completedPct = totalTasks > 0 ? (completed / totalTasks * 100).toInt() : 0;
    final inProgressPct = totalTasks > 0 ? (inProgress / totalTasks * 100).toInt() : 0;
    final pendingPct = totalTasks > 0 ? (pending / totalTasks * 100).toInt() : 0;
    final upcoming = _upcomingProjects();

    return LayoutBuilder(
      builder: (context, constraints) {
        final isPhone = constraints.maxWidth < 600;
        final hPad = isPhone ? 14.0 : 20.0;
        final vPad = isPhone ? 14.0 : 20.0;
        return RefreshIndicator(
      onRefresh: () => _load(forceRefresh: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        // Experiment: force all dashboard sections to stay laid out & painted
        // up front so scrolling does not rebuild/recycle viewport tiles (which
        // renders blank on some devices). Revisit once root cause is confirmed.
        cacheExtent: 100000,
        padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
        children: [
          // ── Load error banner with retry ──
          if (_loadError != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.redLight,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.red.withValues(alpha: 0.35)),
              ),
              child: Row(children: [
                Icon(Icons.error_outline_rounded, size: 18, color: AppColors.red),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _loadError!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(fontSize: 12.5, color: AppColors.red),
                  ),
                ),
                TextButton(
                  onPressed: () => _load(forceRefresh: true),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.red,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  ),
                  child: const Text('Retry'),
                ),
              ]),
            ),
            const SizedBox(height: 14),
          ],
          // ── Supervisor Quick Check-in ──
          if (_isSupervisor) ...[
            _buildQuickCheckInCard(),
            const SizedBox(height: 20),
          ],

          // ── KPI Cards Row ──
          _buildKpiRow(onSite, totalWorkers, activeTasks, productivity, alerts, todayRate, present, late, absent, completed, inProgress, totalTasks, completedPct),
          const SizedBox(height: 20),

          // ── Charts Row ──
          LayoutBuilder(builder: (ctx, cs) {
            final isWide = cs.maxWidth > 600;
            if (isWide) {
              return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(flex: 3, child: _weeklyAttCard(weeklyData, weekLabels)),
                const SizedBox(width: 16),
                SizedBox(width: 240, child: _taskDistCard(completedPct, inProgressPct, pendingPct, hasTasks: totalTasks > 0)),
              ]);
            }
            return Column(children: [
              _weeklyAttCard(weeklyData, weekLabels),
              const SizedBox(height: 16),
              _taskDistCard(completedPct, inProgressPct, pendingPct, hasTasks: totalTasks > 0),
            ]);
          }),
          const SizedBox(height: 20),

          // ── AI Progress Prediction (manual trigger, mobile friendly) ──
          _buildPredictionSection(),
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

  // ── KPI row builder ──
  Widget _buildKpiRow(onSite, totalWorkers, activeTasks, productivity, alerts, todayRate, present, late, absent, completed, inProgress, totalTasks, completedPct) {
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
          // Show real completed + in-progress counts from the KPI response.
          sub: completed > 0 || inProgress > 0
              ? '$completed done · $inProgress in progress'
              : '$activeTasks pending',
          icon: Icons.assignment_rounded,
          iconColor: AppColors.blue,
        ),
        _kpiCard(
          label: 'Overall Productivity',
          value: '$productivity%',
          // No reliable week-over-week delta from the API — omit rather than
          // show fake '+4%' that misleads users.
          sub: totalTasks > 0
              ? '$completedPct% tasks completed'
              : null,
          icon: Icons.trending_up_rounded,
          iconColor: AppColors.green,
          valueColor: AppColors.green,
        ),
        _kpiCard(
          label: 'Alerts',
          value: '$alerts',
          // Use real count — avoids '2 attendance • 1 safety' static hardcoding.
          sub: alerts == 0
              ? 'No open issues'
              : alerts == 1 ? '1 open issue' : '$alerts open issues',
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
        if (data.isNotEmpty)
          // Always render the bar chart when the weekly payload exists, even if
          // all values are 0 (LabeledBarChart handles all-zero with 4px stubs).
          // Previously `data.any((v) => v > 0)` showed a "no data" placeholder
          // on phones, making the bar chart invisible whenever the week had no
          // attendance yet.
          LabeledBarChart(values: data, labels: labels, height: 140, color: AppColors.blue.withValues(alpha: 0.25), highlightColor: AppColors.blue)
        else
          Container(
            height: 140,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.bgCard,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(AppStrings.t('dash.noAttendanceData'),
                style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textMuted)),
          ),
      ]),
    );
  }

  // ── Task Distribution Donut Card ──
  Widget _taskDistCard(int completedPct, int inProgressPct, int pendingPct, {bool hasTasks = true}) {
    final slices = hasTasks
        ? [
            DonutSlice(completedPct.toDouble(), AppColors.green, 'Completed'),
            DonutSlice(inProgressPct.toDouble(), AppColors.accent, 'In Progress'),
            DonutSlice(pendingPct.toDouble(), AppColors.border, 'Pending'),
          ]
        : [DonutSlice(1, AppColors.border, 'Empty')];
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
            slices: slices,
          ),
        ),
        const SizedBox(height: 14),
        if (hasTasks) ...[
          _legendRow('Completed', '$completedPct%', AppColors.green),
          const SizedBox(height: 6),
          _legendRow('In Progress', '$inProgressPct%', AppColors.accent),
          const SizedBox(height: 6),
          _legendRow('Pending', '$pendingPct%', AppColors.textMuted),
        ] else
          Center(
            child: Text(AppStrings.t('dash.noTaskData'),
                style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textMuted)),
          ),
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
    final dt = DateTime.tryParse(iso);
    return dt == null ? iso : DateHelper.formatShort(dt);
  }

  // ── AI Progress Prediction (manual trigger only — never auto-refreshed) ──
  Future<void> _runPrediction() async {
    final pid = _predProjectId;
    if (pid == null) {
      toast('Select a project first');
      return;
    }
    if (_predLoading) return;
    setState(() => _predLoading = true);
    try {
      final res = await ApiService().progressPrediction(pid);
      if (!mounted) return;
      setState(() {
        _prediction = res;
        _predictionPid = pid;
      });
    } on DioException catch (e) {
      toast('Prediction failed: ${e.message ?? e}');
    } catch (e) {
      toast('Prediction failed: $e');
    } finally {
      if (mounted) setState(() => _predLoading = false);
    }
  }

  double? _predNum(Map m, String key) {
    final v = m[key];
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  Color _trendColor(String trend) {
    switch (trend.toLowerCase()) {
      case 'ahead':
        return AppColors.green;
      case 'on_track':
        return AppColors.blue;
      case 'behind':
        return AppColors.yellow;
      case 'critical':
        return AppColors.red;
      default:
        return AppColors.blue;
    }
  }

  IconData _trendIcon(String trend) {
    switch (trend.toLowerCase()) {
      case 'ahead':
        return Icons.trending_up_rounded;
      case 'on_track':
        return Icons.trending_flat_rounded;
      case 'behind':
        return Icons.trending_down_rounded;
      case 'critical':
        return Icons.warning_amber_rounded;
      default:
        return Icons.trending_flat_rounded;
    }
  }

  Widget _buildPredictionSection() {
    final showResult = !_predLoading &&
        _predProjectId != null &&
        _prediction != null &&
        _predictionPid == _predProjectId;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.purpleLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.auto_awesome_rounded,
                size: 18, color: AppColors.purple),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('AI Progress Prediction',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
              Text('Manual — calls the AI only when you tap Update (auto-refresh disabled, saves tokens)',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(fontSize: 11.5, color: AppColors.textMuted)),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        // ── Project picker + Update button (single-col on <480px) ──
        LayoutBuilder(builder: (ctx, cs) {
          final wide = cs.maxWidth >= 480;
          final picker = DropdownButtonFormField<int?>(
            initialValue: _predProjectId,
            isExpanded: true,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Select project',
              hintStyle:
                  GoogleFonts.outfit(fontSize: 13, color: AppColors.textMuted),
              filled: true,
              fillColor: AppColors.bgMain,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppColors.border)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppColors.border)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppColors.accent)),
            ),
            items: [
              for (final p in projects)
                if (p['project_id'] != null)
                  DropdownMenuItem<int?>(
                    value: (p['project_id'] as num).toInt(),
                    child: Text(
                      p['project_name']?.toString() ?? 'Project',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(fontSize: 13),
                    ),
                  ),
            ],
            onChanged: _predLoading ? null : (v) => setState(() => _predProjectId = v),
          );
          // Button: spinner is INSIDE the icon slot; no separate loading block below
          final updateBtn = SizedBox(
            width: wide ? null : double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              onPressed: _predLoading ? null : _runPrediction,
              icon: _predLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.auto_awesome_rounded, size: 18),
              label: Text(
                _predLoading ? 'Predicting…' : 'Update',
                style:
                    GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _predLoading ? AppColors.accent.withValues(alpha: 0.6) : AppColors.accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 18),
              ),
            ),
          );
          if (wide) {
            return Row(children: [
              Expanded(child: picker),
              const SizedBox(width: 12),
              updateBtn,
            ]);
          }
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            picker,
            const SizedBox(height: 10),
            updateBtn,
          ]);
        }),
        const SizedBox(height: 14),
        if (showResult)
          _predictionResultBlock(_prediction!)
        else
          Text(
            'Select a project and tap Update to see AI completion estimates.',
            style: GoogleFonts.outfit(fontSize: 11.5, color: AppColors.textMuted),
          ),
      ]),
    );
  }

  Widget _predictionResultBlock(Map pred) {
    final current = _predNum(pred, 'current_progress') ?? 0;
    final scheduled = _predNum(pred, 'scheduled_progress');
    final gap = _predNum(pred, 'progress_gap');
    final trend = (pred['trend'] as String? ?? 'on_track').toLowerCase();
    final tc = _trendColor(trend);
    final confRaw = pred['confidence'] ?? pred['ai_confidence'];
    final confidence = confRaw is num
        ? confRaw.toDouble()
        : double.tryParse(confRaw?.toString() ?? '');
    final aiUsed = pred['ai_used'] == true;
    final daysLeft = (pred['estimated_days_remaining'] as num?)?.toInt();
    final velocity = pred['velocity'];
    final weeksLeft = velocity is Map
        ? _predNum(velocity, 'estimated_weeks_remaining')
        : null;
    final risk = pred['risk_factors'] is List
        ? (pred['risk_factors'] as List).take(3).toList()
        : <dynamic>[];
    final recs = pred['recommendations'] is List
        ? (pred['recommendations'] as List).take(3).toList()
        : <dynamic>[];
    final milestones = pred['milestones'] is List
        ? (pred['milestones'] as List).take(3).toList()
        : <dynamic>[];
    final insights = pred['ai_insights']?.toString();
    final completionDate = pred['predicted_completion_date']?.toString();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // ── AI narrative insight ──
      if (insights != null && insights.trim().isNotEmpty) ...[
        Text(insights.trim(),
            style: GoogleFonts.outfit(fontSize: 12.5, color: AppColors.textSecondary)),
        const SizedBox(height: 12),
      ],

      // ── Current vs Scheduled progress bars ──
      _predBarRow('Current Progress', current, AppColors.accent),
      if (scheduled != null) ...[
        const SizedBox(height: 6),
        _predBarRow('Scheduled Progress', scheduled.clamp(0, 100).toDouble(), AppColors.blue.withValues(alpha: 0.6)),
      ],

      // ── Gap indicator ──
      if (gap != null) ...[
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: (gap >= 0 ? AppColors.green : AppColors.yellow).withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: (gap >= 0 ? AppColors.green : AppColors.yellow).withValues(alpha: 0.30),
            ),
          ),
          child: Row(children: [
            Icon(
              gap >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded,
              size: 16,
              color: gap >= 0 ? AppColors.green : AppColors.yellow,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                gap >= 0
                    ? '+${gap.toStringAsFixed(1)}% ahead of schedule'
                    : '${gap.toStringAsFixed(1)}% behind schedule',
                style: GoogleFonts.outfit(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: gap >= 0 ? AppColors.green : AppColors.yellow),
              ),
            ),
          ]),
        ),
      ],

      const SizedBox(height: 10),

      // ── Trend badge + predicted completion date ──
      Wrap(spacing: 8, runSpacing: 8, children: [
        // Trend badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: tc.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(_trendIcon(trend), size: 13, color: tc),
            const SizedBox(width: 5),
            Text(trend.replaceAll('_', ' ').toUpperCase(),
                style: GoogleFonts.outfit(
                    fontSize: 11, fontWeight: FontWeight.w800, color: tc)),
          ]),
        ),
        // Predicted completion date
        if (completionDate != null)
          _predChip(
            '📅 Est. finish: ${_fmtDate(completionDate)}',
            AppColors.accentLight,
            AppColors.accentDark,
          ),
        // Days remaining
        if (daysLeft != null)
          _predChip('~$daysLeft day(s) left', AppColors.blueLight, AppColors.blue),
        // Weeks estimate
        if (weeksLeft != null && weeksLeft < 900)
          _predChip('~${weeksLeft.toStringAsFixed(0)} wks est.', AppColors.purpleLight, AppColors.purple),
        // Confidence
        if (confidence != null)
          _predChip(
            'Confidence ${confidence.toStringAsFixed(0)}%',
            confidence >= 70 ? AppColors.greenLight : AppColors.yellowLight,
            confidence >= 70 ? AppColors.green : AppColors.yellow,
          ),
      ]),

      // ── Rule-based notice ──
      if (!aiUsed) ...[
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.yellowLight,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(children: [
            Icon(Icons.info_outline_rounded, size: 14, color: AppColors.yellow),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Rule-based estimate — Gemini AI not enabled for this project.',
                style: GoogleFonts.outfit(fontSize: 11.5, color: AppColors.yellow),
              ),
            ),
          ]),
        ),
      ],

      // ── Milestones mini progress bars ──
      if (milestones.isNotEmpty) ...[
        const SizedBox(height: 14),
        Text('Milestones',
            style: GoogleFonts.outfit(
                fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        const SizedBox(height: 6),
        for (final ms in milestones)
          if (ms is Map)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _predBarRow(
                ms['label']?.toString() ?? ms['name']?.toString() ?? '',
                (_predNum(ms, 'predicted_progress') ?? _predNum(ms, 'progress') ?? 0)
                    .clamp(0, 100)
                    .toDouble(),
                AppColors.purple,
                compact: true,
              ),
            ),
      ],

      // ── Risk factors (top 3) ──
      if (risk.isNotEmpty) ...[
        const SizedBox(height: 10),
        Row(children: [
          Icon(Icons.warning_amber_rounded, size: 14, color: AppColors.red),
          const SizedBox(width: 6),
          Text('Risk Factors',
              style: GoogleFonts.outfit(
                  fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.red)),
        ]),
        const SizedBox(height: 4),
        _predDotList(risk, AppColors.red),
      ],

      // ── Recommendations (top 3) ──
      if (recs.isNotEmpty) ...[
        const SizedBox(height: 8),
        Row(children: [
          Icon(Icons.lightbulb_outline_rounded, size: 14, color: AppColors.green),
          const SizedBox(width: 6),
          Text('Recommendations',
              style: GoogleFonts.outfit(
                  fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.green)),
        ]),
        const SizedBox(height: 4),
        _predDotList(recs, AppColors.green),
      ],
    ]);
  }

  Widget _predChip(String text, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
        child: Text(text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w700, color: fg)),
      );

  Widget _predBarRow(String label, double v, Color color, {bool compact = false}) {
    final value = v.clamp(0, 100).toDouble();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(
                    fontSize: compact ? 11.5 : 12.5,
                    color: AppColors.textSecondary))),
        const SizedBox(width: 8),
        Text('${value.toStringAsFixed(0)}%',
            style: GoogleFonts.outfit(
                fontSize: compact ? 11.5 : 12.5,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary)),
      ]),
      const SizedBox(height: 4),
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LinearProgressIndicator(
          value: value / 100,
          minHeight: compact ? 4 : 7,
          backgroundColor: AppColors.border,
          valueColor: AlwaysStoppedAnimation(color),
        ),
      ),
    ]);
  }

  Widget _predDotList(List items, Color color) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration:
                        BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(item?.toString() ?? '',
                      style: GoogleFonts.outfit(
                          fontSize: 12, color: AppColors.textSecondary)),
                ),
              ]),
            ),
        ],
      );
}

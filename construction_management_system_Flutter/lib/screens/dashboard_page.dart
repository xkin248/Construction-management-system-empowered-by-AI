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
import '../services/photo_capture.dart';
import '../l10n/app_strings.dart';
import '../utils/date_helper.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/failure_state.dart';
import '../widgets/add_worker_sheet.dart';
import '../widgets/task_form.dart';
import 'attendance_geo_helper.dart';
import 'notifications_page.dart';
import '../widgets/dashboard/dashboard_ai_engine_card.dart';
import '../widgets/dashboard/dashboard_chart_cards.dart';
import '../widgets/dashboard/dashboard_checkin_card.dart';
import '../widgets/dashboard/dashboard_connection_badge.dart';
import '../widgets/dashboard/dashboard_kpi_cards.dart';
import '../widgets/dashboard/dashboard_live_cards.dart';
import '../widgets/supervisor/attendance_photo_viewer.dart';
import 'attendance_page.dart';
import 'projects_page.dart';
import 'tasks_page.dart';
import '../widgets/dashboard/dashboard_project_cards.dart';
import '../widgets/dashboard/dashboard_quick_actions.dart';
import '../widgets/dashboard/dashboard_section_parts.dart';
import '../widgets/dashboard/dashboard_welcome_card.dart';

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

  // Connection health of the live feed (spec E2). "Live" is only ever
  // shown after a refresh actually succeeded, so a cold start cannot lie.
  DateTime? _lastOkAt;
  int _connFailures = 0;
  bool _everLoaded = false;

  // Supervisor quick check-in from the dashboard.
  bool _isSupervisor = false;
  bool _supLoading = false;
  bool _supCheckedIn = false;
  String _supMsg = AppStrings.t('dash.checkinHint');

  // Signed-in user profile (only used for the personalised welcome line).
  Map _me = {};

  // ── Live blocks (spec PART B3) ───────────────────────────────────────────
  /// Today's three daily jobs (briefing / toolbox / housekeeping).
  List<Map> _commonTasks = [];
  bool _commonLoading = false;
  Object? _commonError;

  /// Project scope of the live blocks; null = every project.
  int? _dashPid;

  /// Worker whose check-in selfie is being fetched (button spinner state).
  int? _photoWorkerId;

  // AI Progress Prediction — manual trigger only (never on refresh, to save tokens).
  int? _predProjectId;
  bool _predLoading = false;
  Map? _prediction;
  int?
      _predictionPid; // project id that _prediction belongs to (avoid stale display)

  // Keep the supervisor landing page focused on live operational numbers.
  // Deeper reporting remains available from its dedicated navigation pages.
  // Keep the full operational view visible: the compact feed was useful for
  // early validation, but it hid charts, safety alerts and crew activity from
  // the supervisor's landing screen.
  bool get _showRealtimeOnly => false;

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
      if (mounted) setState(() => _me = me);
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
      toast(
          'GPS check-in is not supported in web browsers — use the mobile app.');
      return;
    }
    setState(() {
      _supLoading = true;
      _supMsg = 'Getting your location...';
    });
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
        setState(() {
          _supMsg = 'Location permission denied';
          _supLoading = false;
        });
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
          setState(() {
            _supMsg = 'Check-in cancelled';
            _supLoading = false;
          });
          return;
        }
      }
      final photo = await _captureCheckInPhoto();
      if (photo == null) {
        setState(() {
          _supLoading = false;
        });
        return;
      }
      await ApiService().supervisorCheckIn(
        projectId: pid ?? 1,
        lat: pos['lat']!,
        lng: pos['lng']!,
        photoBase64: photo.base64,
        photoMimeType: photo.mimeType,
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
      setState(() {
        _supMsg = 'Error: $e';
        _supLoading = false;
      });
    }
  }

  Future<void> _quickCheckOut() async {
    if (kIsWeb) {
      toast(
          'GPS check-out is not supported in web browsers — use the mobile app.');
      return;
    }
    setState(() {
      _supLoading = true;
      _supMsg = 'Getting your location...';
    });
    try {
      final pos = await GeoHelper.getCurrentPosition();
      if (pos == null) {
        setState(() {
          _supMsg = 'Location permission denied';
          _supLoading = false;
        });
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
      setState(() {
        _supMsg = e.message ?? 'Check-out failed';
        _supLoading = false;
      });
      toast(e.message ?? 'Check-out failed');
    } catch (e) {
      setState(() {
        _supMsg = 'Error: $e';
        _supLoading = false;
      });
    }
  }

  /// Opens the camera for the mandatory supervisor check-in selfie.
  ///
  /// Returns null when the photo is cancelled or unavailable; the caller then
  /// aborts the check-in instead of falling back to a photo-less request.
  Future<CapturedPhoto?> _captureCheckInPhoto() async {
    setState(() {
      _supMsg = 'Opening camera — take a photo of yourself on site...';
    });
    try {
      final photo = await PhotoCapture.takeSelfie();
      setState(() {
        _supMsg = 'Photo captured, submitting check-in...';
      });
      return photo;
    } on PhotoCaptureException catch (e) {
      if (!e.cancelled) toast(e.message);
      setState(() {
        _supMsg = e.cancelled
            ? 'A photo of yourself is required to check in.'
            : e.message;
      });
      return null;
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

    Future<void> safe(
        String tag, Future<dynamic> f, void Function(dynamic) assign) async {
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
      safe('attendance', ApiService().attendanceToday(),
          (v) => attSummary = v as Map),
      safe('projects', ProjectCache.get(ApiService()),
          (v) => projects = v as List),
      safe('weekly', ApiService().getWeeklyAttendanceStats(), (v) {
        final weekly = v as Map;
        _weeklyAtt = List<Map>.from(weekly['days'] ?? []);
      }),
      safe('common', _loadCommonTasks(), (_) {}),
    ]);

    if (mounted) {
      setState(() {
        ld = false;
        _loadError = errs.isEmpty ? null : errs.join('\n');
        // Connection health (spec E2): only a refresh where every core
        // endpoint answered may keep the badge on "Live".
        if (errs.isEmpty) {
          _lastOkAt = DateTime.now();
          _connFailures = 0;
          _everLoaded = true;
        } else {
          _connFailures += 1;
        }
      });
      if (errs.isNotEmpty && !silent) {
        toast('Some dashboard data failed to load: ${errs.first}');
      }
    }
  }

  /// Never reports "live" before the first successful refresh (spec E2).
  DashboardConnState get _connState {
    if (_connFailures >= 2) return DashboardConnState.offline;
    if (!_everLoaded || _connFailures > 0) {
      return DashboardConnState.reconnecting;
    }
    final last = _lastOkAt;
    if (last == null) return DashboardConnState.reconnecting;
    // The feed polls every 60s, so two missed cycles mean it is no longer live.
    if (DateTime.now().difference(last) > const Duration(seconds: 150)) {
      return DashboardConnState.reconnecting;
    }
    return DashboardConnState.live;
  }

  @override
  Widget build(BuildContext c) {
    if (ld) {
      return Container(
        color: AppColors.bgMain,
        child: LayoutBuilder(
          builder: (context, constraints) => SkeletonDashboard(
            padding: EdgeInsets.all(constraints.maxWidth < 600 ? 16 : 24),
          ),
        ),
      );
    }

    // First paint failed for every endpoint: one actionable failure state
    // (icon + reason + retry) instead of an empty dashboard full of zeros.
    if (_loadError != null && kpi.isEmpty && projects.isEmpty) {
      return Container(
        color: AppColors.bgMain,
        child: FailureState(error: _loadError, onRetry: () => _load()),
      );
    }

    final onSite = kpi['today_attendance'] ?? 0;
    final totalWorkers = kpi['total_workers'] ?? 0;
    // open_issues is surfaced in the insights section rather than the hero KPI.
    final openIssues = kpi['open_issues'] ?? 0;
    // Total projects for the KPI grid: backend value when present, otherwise the
    // locally loaded project list (never null, so the card cannot crash).
    final int totalProjects = (kpi['total_projects'] is num)
        ? (kpi['total_projects'] as num).toInt()
        : projects.length;
    final present = (attSummary['present'] ?? 0) as int;
    final late = (attSummary['late'] ?? 0) as int;
    final absent = (attSummary['absent'] ?? 0) as int;
    final totalAtt = (attSummary['total'] ?? totalWorkers) as int;
    final todayRate =
        totalAtt > 0 ? ((present + late) / totalAtt * 100).round() : 0;

    if (_showRealtimeOnly) {
      return _realtimeDashboardView(
        attendanceRate: todayRate,
        siteProgress: _averageSiteProgress(),
        totalProjects: totalProjects,
        tasksInProgress: (kpi['in_progress_tasks'] as num?)?.toInt() ?? 0,
      );
    }

    // Weekly attendance data from backend (Mon-Sun, daily attendance count of the current week)
    final weeklyData = _weeklyAtt
        .map((d) => ((d['present_workers'] ?? d['check_in_count'] ?? 0) as num)
            .toDouble())
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
    final completedPct =
        totalTasks > 0 ? (completed / totalTasks * 100).toInt() : 0;
    final inProgressPct =
        totalTasks > 0 ? (inProgress / totalTasks * 100).toInt() : 0;
    final pendingPct =
        totalTasks > 0 ? (pending / totalTasks * 100).toInt() : 0;
    final upcoming = _upcomingProjects();

    return LayoutBuilder(
      builder: (context, constraints) {
        final isPhone = constraints.maxWidth < 600;
        final hPad = isPhone ? 16.0 : 24.0;
        final vPad = isPhone ? 16.0 : 24.0;
        return RefreshIndicator(
          onRefresh: () => _load(forceRefresh: true),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
            children: [
              // ── Load error banner with retry ──
              if (_loadError != null) ...[
                DashboardErrorBanner(
                  message:
                      AppStrings.t(failureKindOf(_loadError).descriptionKey),
                  onRetry: () => _load(forceRefresh: true),
                ),
                const SizedBox(height: 16),
              ],
              // ── 0. Greeting / date / project scope / notification bell ──
              RepaintBoundary(child: _dashTopBar(isPhone)),
              const SizedBox(height: 12),

              // ── 1. Welcome greeting (who you are + what this page does) ──
              WelcomeCard(me: _me),
              const SizedBox(height: 12),

              // ── 1a. Connection health + Last Updated (spec E2) ──
              // Sits above the KPIs on purpose: a supervisor must know whether the
              // numbers below are live before reading them.
              RepaintBoundary(
                child: DashboardConnectionBadge(
                  state: _connState,
                  lastUpdated: _lastOkAt,
                  onRefresh: () => _load(forceRefresh: true),
                ),
              ),
              const SizedBox(height: 16),

              // ── 1b. KPI grid — four cards, 2 columns on phone / 4 on desktop ──
              RepaintBoundary(
                child: _kpiGrid(
                  isPhone: isPhone,
                  totalProjects: totalProjects,
                  inProgress: inProgress,
                  pending: pending,
                  totalWorkers: totalWorkers is int ? totalWorkers : 0,
                  onSite: onSite is int ? onSite : 0,
                  todayRate: todayRate,
                  present: present,
                  totalAtt: totalAtt,
                ),
              ),
              const SizedBox(height: 16),

              // ── 3b. Live blocks (spec PART B3): project status / attendance /
              //        daily jobs / alerts. Two columns from 900px up. ──
              RepaintBoundary(
                child: _liveBlocks(
                  isPhone: constraints.maxWidth < 900,
                  absent: absent,
                  openIssues: (openIssues is num) ? openIssues.toInt() : 0,
                ),
              ),
              const SizedBox(height: 20),

              // ── 3. Quick actions — the 3 things a new user does most ──
              QuickActionsCard(
                  onNewTask: _quickNewTask,
                  onAddWorker: _quickAddWorker,
                  onNotifications: _quickNotifications),
              const SizedBox(height: 12),
              const RepaintBoundary(child: DashboardAiEngineCard()),
              const SizedBox(height: 20),

              // ── Supervisor quick check-in (a one-tap action, stays on top) ──
              if (_isSupervisor) ...[
                RepaintBoundary(
                    child: SupervisorCheckInCard(
                        checkedIn: _supCheckedIn,
                        loading: _supLoading,
                        message: _supMsg,
                        onCheckIn: _quickCheckIn,
                        onCheckOut: _quickCheckOut)),
                const SizedBox(height: 16),
              ],

              // ── 4. Charts / trends — collapsed, opened on demand ──
              CollapsibleSection(
                icon: Icons.insights_rounded,
                title: AppStrings.t('dash.insightsTitle'),
                subtitle: AppStrings.t('dash.insightsSub'),
                children: [
                  // Secondary number moved out of the hero KPI row.
                  Row(children: [
                    Icon(Icons.warning_amber_rounded,
                        size: 15, color: AppColors.red),
                    const SizedBox(width: 8),
                    Text(
                      '${AppStrings.t('dash.openIssues')}: $openIssues',
                      style: GoogleFonts.inter(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary),
                    ),
                  ]),
                  const SizedBox(height: 16),
                  LayoutBuilder(builder: (ctx, cs) {
                    final isWide = cs.maxWidth > 600;
                    if (isWide) {
                      return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                                flex: 3,
                                child: RepaintBoundary(
                                    child: WeeklyAttendanceCard(
                                        data: weeklyData, labels: weekLabels))),
                            const SizedBox(width: 16),
                            SizedBox(
                                width: 240,
                                child: RepaintBoundary(
                                    child: TaskDistributionCard(
                                        completedPct: completedPct,
                                        inProgressPct: inProgressPct,
                                        pendingPct: pendingPct,
                                        hasTasks: totalTasks > 0))),
                          ]);
                    }
                    return Column(children: [
                      RepaintBoundary(
                          child: WeeklyAttendanceCard(
                              data: weeklyData, labels: weekLabels)),
                      const SizedBox(height: 16),
                      RepaintBoundary(
                          child: TaskDistributionCard(
                              completedPct: completedPct,
                              inProgressPct: inProgressPct,
                              pendingPct: pendingPct,
                              hasTasks: totalTasks > 0)),
                    ]);
                  }),
                  const SizedBox(height: 20),
                  SectionHeader('Productivity Trend by Project',
                      sub: 'Weekly task completion rate (%)'),
                  const SizedBox(height: 12),
                  if (projects.isEmpty)
                    DashboardEmptyBox(AppStrings.t('proj.noProjects'),
                        icon: Icons.folder_open_outlined)
                  else
                    ...projects
                        .take(4)
                        .map((p) => ProjectProductivityRow(project: p)),
                  const SizedBox(height: 20),
                  SectionHeader('Upcoming Due Projects',
                      sub: 'Projects due within 30 days or overdue'),
                  const SizedBox(height: 12),
                  if (upcoming.isEmpty)
                    DashboardEmptyBox(AppStrings.t('dash.noDueProjects'),
                        icon: Icons.event_note_outlined)
                  else
                    ...upcoming.map((p) => UpcomingProjectCard(project: p)),
                ],
              ),

              // ── 5. AI prediction — collapsed by default, manual trigger ──
              CollapsibleSection(
                icon: Icons.auto_awesome_rounded,
                title: AppStrings.t('dash.aiPredictionTitle'),
                subtitle: AppStrings.t('dash.aiPredictionSub'),
                children: [RepaintBoundary(child: _predictionBody())],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _quickNewTask() async {
    if (projects.isEmpty) {
      toast('Create a project first');
      return;
    }
    final firstId = projects.first['project_id'];
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => TaskForm(
        initialProjectId: firstId is int ? firstId : int.tryParse('$firstId'),
      ),
    );
    if (created == true) _load(forceRefresh: true);
  }

  void _quickAddWorker() {
    showAddWorkerSheet(context, onAdded: () => _load(forceRefresh: true));
  }

  void _quickNotifications() {
    Navigator.push(
        context, MaterialPageRoute(builder: (_) => const NotificationsPage()));
  }

  // ─────────────── Live blocks (spec PART B3–B4) ───────────────

  String _t(String en, String zh, String ms) => AppSettings.t(en, zh, ms);

  String get _scopeName {
    if (_dashPid == null) return _t('All projects', '全部项目', 'Semua projek');
    for (final p in projects) {
      if ('${p['project_id']}' == '$_dashPid') {
        return (p['project_name'] ?? '-').toString();
      }
    }
    return _t('All projects', '全部项目', 'Semua projek');
  }

  /// Greeting strip: today's date, the project scope selector and the
  /// notification bell (spec PART B3 hero).
  Widget _dashTopBar(bool isPhone) {
    final now = DateTime.now();
    final dateStr = '${now.day.toString().padLeft(2, '0')}/'
        '${now.month.toString().padLeft(2, '0')}/${now.year}';
    const weekdays = [
      ['Monday', '星期一', 'Isnin'],
      ['Tuesday', '星期二', 'Selasa'],
      ['Wednesday', '星期三', 'Rabu'],
      ['Thursday', '星期四', 'Khamis'],
      ['Friday', '星期五', 'Jumaat'],
      ['Saturday', '星期六', 'Sabtu'],
      ['Sunday', '星期日', 'Ahad'],
    ];
    final w = weekdays[(now.weekday - 1).clamp(0, 6)];
    final unread = (kpi['unread_notifications'] as num?)?.toInt() ?? 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: AppRadius.rMd,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(children: [
        Icon(Icons.calendar_today_rounded,
            size: 14, color: AppColors.textMuted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '${_t(w[0], w[1], w[2])}, $dateStr',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary),
          ),
        ),
        if (projects.isNotEmpty) _projectScopeSelector(isPhone),
        const SizedBox(width: 4),
        InkWell(
          onTap: _quickNotifications,
          borderRadius: AppRadius.rSm,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Stack(clipBehavior: Clip.none, children: [
              Icon(Icons.notifications_none_rounded,
                  size: 20, color: AppColors.textSecondary),
              if (unread > 0)
                Positioned(
                  right: -3,
                  top: -3,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                        color: AppColors.red,
                        borderRadius: BorderRadius.circular(8)),
                    child: Text('$unread',
                        style: GoogleFonts.inter(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: Colors.white)),
                  ),
                ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _projectScopeSelector(bool isPhone) {
    return PopupMenuButton<int?>(
      tooltip: _t('Filter by project', '按项目筛选', 'Tapis ikut projek'),
      onSelected: (v) {
        setState(() => _dashPid = v);
        _loadCommonTasks();
      },
      itemBuilder: (_) => [
        PopupMenuItem<int?>(
          value: null,
          child: Text(_t('All projects', '全部项目', 'Semua projek')),
        ),
        for (final p in projects)
          PopupMenuItem<int?>(
            value: (p['project_id'] as num?)?.toInt(),
            child: Text((p['project_name'] ?? '-').toString(),
                overflow: TextOverflow.ellipsis),
          ),
      ],
      child: Container(
        constraints: BoxConstraints(maxWidth: isPhone ? 132 : 220),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.bgMain,
          borderRadius: AppRadius.rSm,
          border: Border.all(color: AppColors.border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(
            child: Text(
              _scopeName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary),
            ),
          ),
          Icon(Icons.arrow_drop_down_rounded,
              size: 16, color: AppColors.textMuted),
        ]),
      ),
    );
  }

  /// Loads today's three daily jobs for the selected project scope.
  Future<void> _loadCommonTasks() async {
    if (mounted) setState(() => _commonLoading = true);
    try {
      final res = await ApiService().commonTasksToday(projectId: _dashPid);
      final list = List<Map>.from((res['tasks'] as List?) ?? const []);
      if (!mounted) return;
      setState(() {
        _commonTasks = list;
        _commonError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _commonTasks = const [];
        _commonError = e;
      });
    } finally {
      if (mounted) setState(() => _commonLoading = false);
    }
  }

  /// The daily summary row carries no photo path, so the selfie URL is fetched
  /// from the per-worker detail endpoint and then opened full-screen (spec B8).
  Future<void> _openAttendancePhoto(Map row) async {
    final wid = (row['worker_id'] ?? row['id']) as num?;
    if (wid == null) return;
    final id = wid.toInt();
    setState(() => _photoWorkerId = id);
    try {
      final Map d = (await ApiService().attendanceWorkerToday(id)) ?? const {};
      final url = (d['in_photo_url'] ?? d['out_photo_url'])?.toString();
      if (!mounted) return;
      if (url == null || url.isEmpty) {
        toast(_t('No selfie on file for this check-in', '该打卡没有自拍记录',
            'Tiada swafoto'));
        return;
      }
      await showAttendancePhoto(context, url,
          title: (row['name'] ?? '').toString());
    } catch (e) {
      if (mounted) {
        toast(_t('Could not load the photo, please retry', '照片加载失败，请重试',
            'Gagal memuatkan foto'));
      }
    } finally {
      if (mounted) setState(() => _photoWorkerId = null);
    }
  }

  /// Dashboard alert list: overdue projects, open issues and today's absences.
  List<DashboardAlert> _alerts(int absent, int openIssues) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final overdue = projects.where((p) {
      final status = (p['status'] as String? ?? '').toLowerCase();
      if (status == 'completed' || status == 'done') return false;
      final end = DateTime.tryParse((p['end_date'] as String?) ?? '');
      if (end == null) return false;
      return DateTime(end.year, end.month, end.day).isBefore(today);
    }).toList();

    return [
      if (overdue.isNotEmpty)
        DashboardAlert(
          icon: Icons.schedule_rounded,
          color: AppColors.red,
          title: _t('${overdue.length} overdue projects',
              '${overdue.length} 个项目已逾期', '${overdue.length} projek lewat'),
          detail: overdue
              .take(2)
              .map((p) => (p['project_name'] ?? '-').toString())
              .join(', '),
          onTap: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const ProjectsPage())),
        ),
      if (absent > 0)
        DashboardAlert(
          icon: Icons.person_off_rounded,
          color: AppColors.accentSolid,
          title: _t('$absent absent today', '今日 $absent 人缺勤',
              '$absent tidak hadir hari ini'),
          detail: _t('Check the attendance exceptions', '查看考勤异常记录',
              'Semak rekod kehadiran'),
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const AttendancePage())),
        ),
      if (openIssues > 0)
        DashboardAlert(
          icon: Icons.report_problem_rounded,
          color: AppColors.accentSolid,
          title: _t('$openIssues open issues', '$openIssues 个未处理问题',
              '$openIssues isu terbuka'),
          detail: _t('Resolve site issues before they block work', '及时处理现场问题',
              'Selesaikan isu tapak'),
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const NotificationsPage())),
        ),
    ];
  }

  /// KPI grid: four headline numbers (total projects / active tasks /
  /// workers / attendance rate). Two columns on phone, four on desktop.
  /// Every value is pre-sanitised by the caller, so an empty dashboard renders
  /// four zero-value cards instead of an empty region or a crash.
  int _averageSiteProgress() {
    final values = <double>[];
    for (final item in projects) {
      if (item is Map && item['progress'] is num) {
        values.add((item['progress'] as num).toDouble().clamp(0, 100));
      }
    }
    if (values.isEmpty) return 0;
    return (values.reduce((a, b) => a + b) / values.length).round();
  }

  Widget _realtimeDashboardView({
    required int attendanceRate,
    required int siteProgress,
    required int totalProjects,
    required int tasksInProgress,
  }) {
    return LayoutBuilder(builder: (context, constraints) {
      final phone = constraints.maxWidth < 600;
      final cards = <Widget>[
        KpiCard(
          label: _t('Attendance Rate', '出勤率', 'Kadar Kehadiran'),
          value: '$attendanceRate%',
          sub: _t('Today', '今天', 'Hari ini'),
          icon: Icons.fact_check_rounded,
          iconColor: AppColors.purple,
          valueColor: attendanceRate >= 80 ? AppColors.green : AppColors.red,
        ),
        KpiCard(
          label: _t('Site Progress', '项目进度', 'Kemajuan Tapak'),
          value: '$siteProgress%',
          sub: _t('All projects', '全部项目', 'Semua projek'),
          icon: Icons.trending_up_rounded,
          iconColor: AppColors.green,
          valueColor: AppColors.green,
        ),
        KpiCard(
          label: _t('Total Projects', '总项目', 'Jumlah Projek'),
          value: '$totalProjects',
          sub: _t('Workspace total', '工作区总数', 'Jumlah ruang kerja'),
          icon: Icons.apartment_rounded,
          iconColor: AppColors.blue,
        ),
        KpiCard(
          label: _t('Tasks in Progress', '进行中任务', 'Tugasan Sedang Jalan'),
          value: '$tasksInProgress',
          sub: _t('Live now', '实时', 'Masa nyata'),
          icon: Icons.assignment_rounded,
          iconColor: AppColors.accentSolid,
        ),
      ];
      return RefreshIndicator(
        onRefresh: () => _load(forceRefresh: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.all(phone ? 16 : 24),
          children: [
            if (_loadError != null) ...[
              DashboardErrorBanner(
                message: AppStrings.t(failureKindOf(_loadError).descriptionKey),
                onRetry: () => _load(forceRefresh: true),
              ),
              const SizedBox(height: 12),
            ],
            _dashTopBar(phone),
            const SizedBox(height: 12),
            DashboardConnectionBadge(
              state: _connState,
              lastUpdated: _lastOkAt,
              onRefresh: () => _load(forceRefresh: true),
            ),
            const SizedBox(height: 16),
            Text(
              _t('REAL-TIME DASHBOARD', '实时仪表板', 'PAPAN PEMUKA MASA NYATA'),
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            if (phone) ...[
              Row(children: [
                Expanded(child: cards[0]),
                const SizedBox(width: 12),
                Expanded(child: cards[1])
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: cards[2]),
                const SizedBox(width: 12),
                Expanded(child: cards[3])
              ]),
            ] else
              Row(children: [
                Expanded(child: cards[0]),
                const SizedBox(width: 12),
                Expanded(child: cards[1]),
                const SizedBox(width: 12),
                Expanded(child: cards[2]),
                const SizedBox(width: 12),
                Expanded(child: cards[3]),
              ]),
            if (_isSupervisor) ...[
              const SizedBox(height: 16),
              SupervisorCheckInCard(
                checkedIn: _supCheckedIn,
                loading: _supLoading,
                message: _supMsg,
                onCheckIn: _quickCheckIn,
                onCheckOut: _quickCheckOut,
              ),
            ],
          ],
        ),
      );
    });
  }

  Widget _kpiGrid({
    required bool isPhone,
    required int totalProjects,
    required int inProgress,
    required int pending,
    required int totalWorkers,
    required int onSite,
    required int todayRate,
    required int present,
    required int totalAtt,
  }) {
    final cards = <Widget>[
      KpiCard(
        label: _t('Total Projects', '总项目', 'Jumlah Projek'),
        value: '$totalProjects',
        sub: totalProjects > 0
            ? _t('$totalProjects in workspace', '工作区内全部项目',
                '$totalProjects dalam ruang kerja')
            : _t('No projects yet', '暂无项目', 'Tiada projek'),
        icon: Icons.apartment_rounded,
        iconColor: AppColors.blue,
      ),
      KpiCard(
        label: _t('Active Tasks', '进行中任务', 'Tugasan Aktif'),
        value: '$inProgress',
        sub: pending > 0
            ? _t('$pending pending', '$pending 项待办', '$pending tertunda')
            : _t('Nothing pending', '无待办事项', 'Tiada tertunda'),
        icon: Icons.assignment_rounded,
        iconColor: AppColors.accentSolid,
      ),
      KpiCard(
        label: _t('Total Workers', '工人总数', 'Jumlah Pekerja'),
        value: '$totalWorkers',
        sub: _t('$onSite on site today', '今日在岗 $onSite 人',
            '$onSite di tapak hari ini'),
        icon: Icons.groups_rounded,
        iconColor: AppColors.green,
      ),
      KpiCard(
        label: _t('Attendance Rate', '出勤率', 'Kadar Kehadiran'),
        value: '$todayRate%',
        sub: '$present/$totalAtt ${_t('present', '已出勤', 'hadir')}',
        icon: Icons.fact_check_rounded,
        iconColor: AppColors.purple,
        valueColor: todayRate >= 80
            ? AppColors.green
            : (todayRate >= 50 ? AppColors.textPrimary : AppColors.red),
      ),
    ];

    if (!isPhone) {
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < cards.length; i++) ...[
              if (i > 0) const SizedBox(width: 12),
              Expanded(child: cards[i]),
            ],
          ],
        ),
      );
    }
    return Column(
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: cards[0]),
              const SizedBox(width: 12),
              Expanded(child: cards[1]),
            ],
          ),
        ),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: cards[2]),
              const SizedBox(width: 12),
              Expanded(child: cards[3]),
            ],
          ),
        ),
      ],
    );
  }

  /// Two columns on desktop, one column on phone (spec PART C).
  Widget _liveBlocks({
    required bool isPhone,
    required int absent,
    required int openIssues,
  }) {
    final scopedProjects = _dashPid == null
        ? projects
        : projects.where((p) => '${p['project_id']}' == '$_dashPid').toList();
    final attRows = List<Map>.from((attSummary['workers'] as List?) ?? const [])
        .whereType<Map>()
        .toList();

    final projectCard = LiveProjectStatusCard(
      projects: scopedProjects,
      onOpen: (project) {
        final id = (project['project_id'] as num?)?.toInt();
        if (id == null) return;
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ProjectDetailPage(projectId: id)),
        );
      },
      onViewAll: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => const ProjectsPage())),
    );
    final attendanceCard = LiveAttendancePanel(
      rows: attRows,
      loadingWorkerId: _photoWorkerId,
      onOpenPhoto: _openAttendancePhoto,
      onViewAll: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => const AttendancePage())),
    );
    final commonCard = CommonTasksTodayCard(
      tasks: _commonTasks,
      loading: _commonLoading,
      error: _commonError,
      onViewAll: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => const TasksPage())),
    );
    final alertsCard = DashboardAlertsPanel(
      alerts: _alerts(absent, openIssues),
      onViewAll: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => const NotificationsPage())),
    );

    if (isPhone) {
      return Column(children: [
        attendanceCard,
        const SizedBox(height: 12),
        projectCard,
        const SizedBox(height: 12),
        commonCard,
        const SizedBox(height: 12),
        alertsCard,
      ]);
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(
        child: Column(children: [
          projectCard,
          const SizedBox(height: 12),
          commonCard,
        ]),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(children: [
          attendanceCard,
          const SizedBox(height: 12),
          alertsCard,
        ]),
      ),
    ]);
  }

  /// Collapsible card: keeps secondary content one tap away instead of

  // ── KPI row builder ──
  /// Three headline numbers only — a first-time user should grasp the site

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
      final da =
          DateTime.tryParse((a['end_date'] as String?) ?? '') ?? DateTime(9999);
      final db =
          DateTime.tryParse((b['end_date'] as String?) ?? '') ?? DateTime(9999);
      return da.compareTo(db);
    });
    return due;
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

  /// Body of the AI prediction card. The card chrome / title lives in the
  /// collapsible section so the dashboard first screen stays short.
  Widget _predictionBody() {
    final showResult = !_predLoading &&
        _predProjectId != null &&
        _prediction != null &&
        _predictionPid == _predProjectId;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
                GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted),
            filled: true,
            fillColor: AppColors.bgMain,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            border: OutlineInputBorder(
                borderRadius: AppRadius.rSm,
                borderSide: BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(
                borderRadius: AppRadius.rSm,
                borderSide: BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(
                borderRadius: AppRadius.rSm,
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
                    style: GoogleFonts.inter(fontSize: 13),
                  ),
                ),
          ],
          onChanged:
              _predLoading ? null : (v) => setState(() => _predProjectId = v),
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
                        strokeWidth: 2, color: AppColors.accentInk))
                : const Icon(Icons.auto_awesome_rounded, size: 18),
            label: Text(
              _predLoading ? 'Predicting…' : 'Update',
              style:
                  GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _predLoading
                  ? AppColors.accent.withValues(alpha: 0.6)
                  : AppColors.accent,
              foregroundColor: AppColors.accentInk,
              shape: RoundedRectangleBorder(borderRadius: AppRadius.rSm),
              padding: const EdgeInsets.symmetric(horizontal: 16),
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
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              picker,
              const SizedBox(height: 12),
              updateBtn,
            ]);
      }),
      const SizedBox(height: 16),
      if (showResult)
        _predictionResultBlock(_prediction!)
      else
        Text(
          'Select a project and tap Update to see AI completion estimates.',
          style: GoogleFonts.inter(fontSize: 11.5, color: AppColors.textMuted),
        ),
    ]);
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
            style: GoogleFonts.inter(
                fontSize: 12.5, color: AppColors.textSecondary)),
        const SizedBox(height: 12),
      ],

      // ── Current vs Scheduled progress bars ──
      _predBarRow('Current Progress', current, AppColors.accent),
      if (scheduled != null) ...[
        const SizedBox(height: 8),
        _predBarRow('Scheduled Progress', scheduled.clamp(0, 100).toDouble(),
            AppColors.blue.withValues(alpha: 0.6)),
      ],

      // ── Gap indicator ──
      if (gap != null) ...[
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: (gap >= 0 ? AppColors.green : AppColors.yellow)
                .withValues(alpha: 0.10),
            borderRadius: AppRadius.rSm,
            border: Border.all(
              color: (gap >= 0 ? AppColors.green : AppColors.yellow)
                  .withValues(alpha: 0.30),
            ),
          ),
          child: Row(children: [
            Icon(
              gap >= 0
                  ? Icons.trending_up_rounded
                  : Icons.trending_down_rounded,
              size: 16,
              color: gap >= 0 ? AppColors.green : AppColors.yellow,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                gap >= 0
                    ? '+${gap.toStringAsFixed(1)}% ahead of schedule'
                    : '${gap.toStringAsFixed(1)}% behind schedule',
                style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: gap >= 0 ? AppColors.green : AppColors.yellow),
              ),
            ),
          ]),
        ),
      ],

      const SizedBox(height: 12),

      // ── Trend badge + predicted completion date ──
      Wrap(spacing: 8, runSpacing: 8, children: [
        // Trend badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: tc.withValues(alpha: 0.12),
            borderRadius: AppRadius.rLg,
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(_trendIcon(trend), size: 13, color: tc),
            const SizedBox(width: 4),
            Text(trend.replaceAll('_', ' ').toUpperCase(),
                style: GoogleFonts.inter(
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
          _predChip(
              '~$daysLeft day(s) left', AppColors.blueLight, AppColors.blue),
        // Weeks estimate
        if (weeksLeft != null && weeksLeft < 900)
          _predChip('~${weeksLeft.toStringAsFixed(0)} wks est.',
              AppColors.purpleLight, AppColors.purple),
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.yellowLight,
            borderRadius: AppRadius.rXs,
          ),
          child: Row(children: [
            Icon(Icons.info_outline_rounded, size: 14, color: AppColors.yellow),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Rule-based estimate — Gemini AI not enabled for this project.',
                style:
                    GoogleFonts.inter(fontSize: 11.5, color: AppColors.yellow),
              ),
            ),
          ]),
        ),
      ],

      // ── Milestones mini progress bars ──
      if (milestones.isNotEmpty) ...[
        const SizedBox(height: 16),
        Text('Milestones',
            style: GoogleFonts.inter(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
        const SizedBox(height: 8),
        for (final ms in milestones)
          if (ms is Map)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _predBarRow(
                ms['label']?.toString() ?? ms['name']?.toString() ?? '',
                (_predNum(ms, 'predicted_progress') ??
                        _predNum(ms, 'progress') ??
                        0)
                    .clamp(0, 100)
                    .toDouble(),
                AppColors.purple,
                compact: true,
              ),
            ),
      ],

      // ── Risk factors (top 3) ──
      if (risk.isNotEmpty) ...[
        const SizedBox(height: 12),
        Row(children: [
          Icon(Icons.warning_amber_rounded, size: 14, color: AppColors.red),
          const SizedBox(width: 8),
          Text('Risk Factors',
              style: GoogleFonts.inter(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.red)),
        ]),
        const SizedBox(height: 4),
        _predDotList(risk, AppColors.red),
      ],

      // ── Recommendations (top 3) ──
      if (recs.isNotEmpty) ...[
        const SizedBox(height: 8),
        Row(children: [
          Icon(Icons.lightbulb_outline_rounded,
              size: 14, color: AppColors.green),
          const SizedBox(width: 8),
          Text('Recommendations',
              style: GoogleFonts.inter(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.green)),
        ]),
        const SizedBox(height: 4),
        _predDotList(recs, AppColors.green),
      ],
    ]);
  }

  Widget _predChip(String text, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: bg, borderRadius: AppRadius.rMd),
        child: Text(text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
                fontSize: 12, fontWeight: FontWeight.w700, color: fg)),
      );

  Widget _predBarRow(String label, double v, Color color,
      {bool compact = false}) {
    final value = v.clamp(0, 100).toDouble();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                    fontSize: compact ? 11.5 : 12.5,
                    color: AppColors.textSecondary))),
        const SizedBox(width: 8),
        Text('${value.toStringAsFixed(0)}%',
            style: GoogleFonts.inter(
                fontSize: compact ? 11.5 : 12.5,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary)),
      ]),
      const SizedBox(height: 4),
      ClipRRect(
        borderRadius: AppRadius.rXs,
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
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                  padding: const EdgeInsets.only(top: 4),
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
                      style: GoogleFonts.inter(
                          fontSize: 12, color: AppColors.textSecondary)),
                ),
              ]),
            ),
        ],
      );
}

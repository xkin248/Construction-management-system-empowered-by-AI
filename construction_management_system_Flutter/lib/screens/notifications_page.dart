import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';
import '../services/api_service.dart';
import '../services/app_settings.dart';
import '../services/project_cache.dart';
import '../l10n/app_strings.dart';
import '../utils/date_helper.dart';
import '../models/notification.dart';
import '../widgets/guided_empty_state.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/failure_state.dart';
import 'projects_page.dart';
import 'tasks_page.dart';
import 'workers_page.dart';
import 'attendance_page.dart';

const _weathers = ['Sunny', 'Cloudy', 'Rain', 'Thunderstorm'];
const _severities = ['low', 'medium', 'high'];
const _categories = ['safety', 'delay', 'equipment', 'quality', 'other'];

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key, this.embedded = false, this.initialTab = 0});

  /// When true the page is rendered inside a shell that already owns the
  /// AppBar and the bottom navigation (worker shell tab), so this page only
  /// contributes its tab strip + content and never pushes a full-screen
  /// second-level route.
  final bool embedded;

  /// Tab to open on first build: 0 = notifications, 1 = daily reports work
  /// (supervisor) / issues (worker), 2 = issues (supervisor). Lets a dashboard
  /// shortcut deep-link straight into the issue report form.
  final int initialTab;

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage>
    with WidgetsBindingObserver {
  bool _loading = true;
  Object? _loadError;
  Object? _repError;
  Object? _issError;
  int _unreadCount = 0;
  List<NotificationItem> _items = [];
  NotificationSettings? _settings;
  Timer? _pollTimer;
  TabController? _tabController;

  bool _repLoading = false;
  bool _issLoading = false;
  // Tracks whether reports/issues have been loaded at least once
  bool _repLoaded = false;
  bool _issLoaded = false;
  List projects = [];
  List reports = [];
  List issues = [];
  int? _repPid;
  int? _issPid;
  final _workProgress = TextEditingController();
  final _materials = TextEditingController();
  final _issuesEnc = TextEditingController();
  final _manpower = TextEditingController();
  final _issTitle = TextEditingController();
  final _issDesc = TextEditingController();
  String _weather = 'Sunny';
  String _severity = 'low';
  String _category = 'safety';
  bool _isWorker = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppColors.darkMode.addListener(_rebuild);
    AppSettings.lang.addListener(_rebuild);
    _loadRole();
    _load(); // load notifications eagerly (lightweight)
    // Reports & Issues are loaded lazily on first tab visit (avoids 500 toast
    // when the reports API is unavailable, and saves unnecessary requests).
    _startPoll();
  }

  void _startPoll() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) => _refreshCount());
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  /// Worker accounts do not use daily reports — hide that tab entirely.
  Future<void> _loadRole() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final t = (sp.getString('user_type') ?? '').toLowerCase();
      final r = (sp.getString('user_role') ?? '').toLowerCase();
      if (mounted && (t == 'worker' || r == 'worker')) {
        setState(() => _isWorker = true);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AppColors.darkMode.removeListener(_rebuild);
    AppSettings.lang.removeListener(_rebuild);
    _pollTimer?.cancel();
    _tabController?.removeListener(_onTabChanged);
    _tabController?.dispose();
    _workProgress.dispose();
    _materials.dispose();
    _issuesEnc.dispose();
    _manpower.dispose();
    _issTitle.dispose();
    _issDesc.dispose();
    super.dispose();
  }

  /// Pause polling when app is backgrounded, resume when foregrounded.
  /// This prevents unnecessary network requests (and battery drain) when
  /// the user is not actively using the app.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startPoll();
      _refreshCount(); // immediate refresh after returning to foreground
    } else if (state == AppLifecycleState.paused ||
               state == AppLifecycleState.detached) {
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  }

  void _onTabChanged() {
    if (_tabController == null || !_tabController!.indexIsChanging) return;
    final i = _tabController!.index;
    if (!_isWorker) {
      // tab 1 = Daily Reports, tab 2 = Issues
      if (i == 1 && !_repLoaded) _loadReports();
      if (i == 2 && !_issLoaded) _loadIssues();
    } else {
      // worker: tab 1 = Issues
      if (i == 1 && !_issLoaded) _loadIssues();
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ApiService().getNotifications(),
        ApiService().getUnreadCount(),
      ]);
      _items = (results[0] as List)
          .map((e) => NotificationItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      _unreadCount = results[1] as int;
    } catch (e) {
      _loadError = e;
      toast('Failed to load notifications: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refreshCount() async {
    try {
      final c = await ApiService().getUnreadCount();
      if (mounted) setState(() => _unreadCount = c);
    } catch (_) {}
  }

  Future<void> _markRead(NotificationItem item) async {
    if (item.isRead) return;
    try {
      await ApiService().markNotificationRead(item.notificationId);
      if (mounted) {
        setState(() {
          _items = _items.map((e) {
            if (e.notificationId == item.notificationId) {
              return NotificationItem(
                notificationId: e.notificationId,
                supervisorId: e.supervisorId,
                notificationType: e.notificationType,
                title: e.title,
                content: e.content,
                relatedEntityType: e.relatedEntityType,
                relatedEntityId: e.relatedEntityId,
                isRead: true,
                createdAt: e.createdAt,
                readAt: DateTime.now(),
              );
            }
            return e;
          }).toList();
          _unreadCount = (_unreadCount - 1).clamp(0, 9999);
        });
      }
    } catch (e) {
      toast('Failed: $e');
    }
  }

  Future<void> _markAllRead() async {
    try {
      await ApiService().markAllNotificationsRead();
      if (mounted) {
        setState(() {
          _items = _items.map((e) => NotificationItem(
            notificationId: e.notificationId,
            supervisorId: e.supervisorId,
            notificationType: e.notificationType,
            title: e.title,
            content: e.content,
            relatedEntityType: e.relatedEntityType,
            relatedEntityId: e.relatedEntityId,
            isRead: true,
            createdAt: e.createdAt,
            readAt: DateTime.now(),
          )).toList();
          _unreadCount = 0;
        });
      }
    } catch (e) {
      toast('Failed: $e');
    }
  }

  Future<void> _openSettings() async {
    NotificationSettings settings;
    String? loadError;
    try {
      final raw = await ApiService().getNotificationSettings();
      settings = NotificationSettings.fromJson(Map<String, dynamic>.from(raw));
    } catch (e) {
      // Fall back to the last known / default values but tell the user the
      // dialog is not showing what the server currently has.
      settings = _settings ?? NotificationSettings();
      loadError = '$e';
    }
    _settings = settings;
    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) {
        var saving = false;
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: Text(AppStrings.t('notif.settingsTitle'),
                style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 17)),
            shape: RoundedRectangleBorder(borderRadius: AppRadius.rMd),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (loadError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      AppStrings.t('notif.settingsLoadFallback'),
                      style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted),
                    ),
                  ),
                _switch(AppStrings.t('notif.settingsAttendance'), settings.notifAttendance,
                    (v) => setDialogState(() => settings.notifAttendance = v)),
                _switch(AppStrings.t('notif.settingsTaskOverdue'), settings.notifTaskOverdue,
                    (v) => setDialogState(() => settings.notifTaskOverdue = v)),
                _switch(AppStrings.t('notif.settingsTaskAssigned'), settings.notifTaskAssigned,
                    (v) => setDialogState(() => settings.notifTaskAssigned = v)),
                _switch(AppStrings.t('notif.settingsIssues'), settings.notifIssue,
                    (v) => setDialogState(() => settings.notifIssue = v)),
                _switch(AppStrings.t('notif.settingsSafety'), settings.notifSafety,
                    (v) => setDialogState(() => settings.notifSafety = v)),
                _switch(AppStrings.t('notif.settingsDailyReport'), settings.notifDailyReport,
                    (v) => setDialogState(() => settings.notifDailyReport = v)),
                const Divider(height: 20),
                _switch(AppStrings.t('notif.settingsEmail'), settings.notifEmail,
                    (v) => setDialogState(() => settings.notifEmail = v)),
                _switch(AppStrings.t('notif.settingsPush'), settings.notifPush,
                    (v) => setDialogState(() => settings.notifPush = v)),
              ]),
            ),
            actions: [
              TextButton(
                  onPressed: saving ? null : () => Navigator.pop(ctx),
                  child: Text(AppStrings.t('common.cancel'))),
              ElevatedButton(
                onPressed: saving
                    ? null
                    : () async {
                        setDialogState(() => saving = true);
                        try {
                          await ApiService().updateNotificationSettings(settings.toJson());
                          _settings = settings;
                          if (ctx.mounted) Navigator.pop(ctx);
                          toast(AppStrings.t('notif.settingsSaved'));
                        } catch (e) {
                          if (ctx.mounted) setDialogState(() => saving = false);
                          toast('${AppStrings.t('notif.settingsSaveFailed')}: ${_settingsError(e)}');
                        }
                      },
                child: saving
                    ? const SizedBox(
                        width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(AppStrings.t('common.save')),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Keep server errors readable in a toast instead of dumping a Dio stack.
  String _settingsError(Object e) {
    final s = e.toString();
    if (s.contains('SocketException') || s.contains('Connection')) {
      return 'cannot reach the server';
    }
    if (s.contains('timeout')) return 'request timed out';
    return s.length > 120 ? '${s.substring(0, 120)}…' : s;
  }

  Widget _switch(String label, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label,
          style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
      value: value,
      activeThumbColor: AppColors.accent,
      onChanged: onChanged,
    );
  }

  void _navigateToRelated(NotificationItem item) {
    final type = item.relatedEntityType?.toLowerCase() ?? '';
    Widget Function()? builder;
    if (type == 'project') builder = () => const ProjectsPage();
    if (type == 'task') builder = () => const TasksPage();
    if (type == 'worker') builder = () => const WorkersPage();
    if (type == 'attendance') builder = () => const AttendancePage();
    if (builder != null) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => builder!()));
    }
  }

  /// Unread counter chip shown next to the page title.
  Widget _unreadBadge() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.red,
          borderRadius: AppRadius.rMd,
        ),
        child: Text('$_unreadCount',
            style: GoogleFonts.inter(
                color: AppColors.onAccent, fontSize: 13, fontWeight: FontWeight.w800)),
      );

  Widget _titleRow() => Row(mainAxisSize: MainAxisSize.min, children: [
        Text(AppStrings.t('notif.title'),
            style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 17)),
        if (_unreadCount > 0) ...[
          const SizedBox(width: 8),
          _unreadBadge(),
        ],
      ]);

  List<Widget> _headerActions() => [
        // Icon-only actions keep the header safe for long translated labels
        // (e.g. "Tandakan semua dibaca") on narrow phones.
        if (_items.any((e) => !e.isRead))
          IconButton(
            onPressed: _markAllRead,
            icon: const Icon(Icons.done_all_rounded, size: 20),
            color: AppColors.accent,
            tooltip: AppStrings.t('notif.markAllRead'),
          ),
        IconButton(
          icon: Icon(Icons.settings_outlined, color: AppColors.textSecondary),
          tooltip: AppStrings.t('notif.settingsTooltip'),
          onPressed: _openSettings,
        ),
      ];

  TabBar _tabBar(List<Widget> tabs) => TabBar(
        indicatorColor: AppColors.accent,
        labelColor: AppColors.accent,
        unselectedLabelColor: AppColors.textSecondary,
        labelStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700),
        tabs: tabs,
      );

  @override
  Widget build(BuildContext context) {
    // Build tab list once so DefaultTabController length never mismatches.
    final tabs = [
      Tab(text: AppStrings.t('notif.title')),
      if (!_isWorker) Tab(text: AppStrings.t('notif.dailyReports')),
      Tab(text: AppStrings.t('notif.issues')),
    ];
    final tabViews = [
      _buildNotificationsTab(),
      if (!_isWorker) _buildReportsTab(),
      _buildIssuesTab(),
    ];
    final content = Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppBreakpoints.maxContentWidth),
        child: SizedBox(
          width: double.infinity,
          child: TabBarView(children: tabViews),
        ),
      ),
    );
    return DefaultTabController(
      length: tabs.length,
      initialIndex: widget.initialTab.clamp(0, tabs.length - 1),
      child: Builder(builder: (ctx) {
        // Attach listener once after the DefaultTabController is created.
        final controller = DefaultTabController.of(ctx);
        if (_tabController != controller) {
          _tabController?.removeListener(_onTabChanged);
          _tabController = controller;
          _tabController!.addListener(_onTabChanged);
        }
        // Embedded mode: rendered as a tab inside a shell that already owns
        // the AppBar and bottom navigation (so no second-level full-screen
        // page and no accidental taps where the nav bar used to be).
        if (widget.embedded) {
          return ColoredBox(
            color: AppColors.bgMain,
            child: Column(children: [
              Material(
                color: AppColors.bgCard,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(
                    height: 48,
                    child: Row(children: [
                      if (_unreadCount > 0) ...[
                        const SizedBox(width: 16),
                        _unreadBadge(),
                      ],
                      const Spacer(),
                      ..._headerActions(),
                    ]),
                  ),
                  _tabBar(tabs),
                ]),
              ),
              Expanded(child: content),
            ]),
          );
        }
        return Scaffold(
          backgroundColor: AppColors.bgMain,
          appBar: AppBar(
            backgroundColor: AppColors.bgCard,
            elevation: 0,
            scrolledUnderElevation: 0.5,
            surfaceTintColor: AppColors.transparent,
            shape: Border(bottom: BorderSide(color: AppColors.border)),
            centerTitle: false,
            title: _titleRow(),
            actions: _headerActions(),
            bottom: _tabBar(tabs),
          ),
          body: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(maxWidth: AppBreakpoints.maxContentWidth),
              child: content,
            ),
          ),
        );
      }),
    );
  }

  Widget _buildNotificationsTab() {
    if (_loading) return const SkeletonList(rows: 6);
    if (_items.isEmpty) {
      if (_loadError != null) return FailureState(error: _loadError, onRetry: _load);
      return _emptyState();
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _items.length,
        itemBuilder: (ctx, i) => _notificationTile(_items[i]),
      ),
    );
  }

  Widget _buildReportsTab() {
    if (_repLoading) return const SkeletonList(rows: 5);
    return RefreshIndicator(
      onRefresh: _loadReports,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_repError != null)
            FailureInline(error: _repError, onRetry: _loadReports),
          _sectionCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(AppStrings.t('notif.submitDailyReport'),
                  style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.textPrimary)),
              const SizedBox(height: 16),
              if (projects.length > 1) ...[
                DropdownButtonFormField<int>(
                  initialValue: _repPid,
                  decoration: const InputDecoration(labelText: 'Project'),
                  items: projects.map<DropdownMenuItem<int>>((p) =>
                      DropdownMenuItem(value: p['project_id'] as int, child: Text(p['project_name'] as String? ?? ''))).toList(),
                  onChanged: (v) async {
                    setState(() => _repPid = v);
                    if (v != null) {
                      setState(() => _repLoading = true);
                      reports = await ApiService().getReports(v);
                      if (mounted) setState(() => _repLoading = false);
                    }
                  },
                ),
                const SizedBox(height: 12),
              ],
              DropdownButtonFormField<String>(
                initialValue: _weather,
                decoration: const InputDecoration(labelText: 'Weather'),
                items: _weathers.map((w) => DropdownMenuItem(value: w, child: Text(w))).toList(),
                onChanged: (v) => setState(() => _weather = v!),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _manpower,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: AppStrings.t('notif.workersPresent'), hintText: AppStrings.t('notif.workersPresentHint')),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _workProgress,
                maxLines: 3,
                decoration: const InputDecoration(labelText: "Today's Progress *", hintText: "Describe today's progress..."),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _materials,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Materials Used'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _issuesEnc,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Safety Notes / Issues Encountered'),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _submitReport,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(borderRadius: AppRadius.rMd),
                ),
                child: Text(AppStrings.t('notif.submitReport')),
              ),
            ]),
          ),
          const SizedBox(height: 24),
          Text(AppStrings.t('notif.recentReports'),
              style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.textPrimary)),
          const SizedBox(height: 12),
          if (reports.isEmpty)
            Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text(AppStrings.t('notif.noReports'),
                  style: TextStyle(color: AppColors.textMuted))),
            )
          else
            ...reports.map((r) => _sectionCard(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.accentLight,
                        borderRadius: AppRadius.rMd,
                      ),
                      child: Icon(Icons.description_outlined, color: AppColors.accent, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${DateHelper.tryFormatShort(r['report_date'])} · ${r['weather'] ?? ''}',
                            style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary)),
                        const SizedBox(height: 4),
                        Text(r['work_progress']?.toString() ?? 'No content',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(fontSize: 14, color: AppColors.textMuted)),
                      ]),
                    ),
                    Text('${r['manpower_count'] ?? 0}\nworkers',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(fontSize: 14, color: AppColors.textMuted)),
                  ]),
                )),
        ],
      ),
    );
  }

  Widget _buildIssuesTab() {
    if (_issLoading) return const SkeletonList(rows: 5);
    final activeIssues =
        issues.where((i) => !_isResolvedIssue(i as Map)).toList();
    final resolvedIssues =
        issues.where((i) => _isResolvedIssue(i as Map)).toList();
    return RefreshIndicator(
      onRefresh: _loadIssues,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_issError != null)
            FailureInline(error: _issError, onRetry: _loadIssues),
          _sectionCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(AppStrings.t('notif.reportIssue'),
                  style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.textPrimary)),
              const SizedBox(height: 16),
              if (projects.length > 1) ...[
                DropdownButtonFormField<int>(
                  initialValue: _issPid,
                  decoration: const InputDecoration(labelText: 'Project'),
                  items: projects.map<DropdownMenuItem<int>>((p) =>
                      DropdownMenuItem(value: p['project_id'] as int, child: Text(p['project_name'] as String? ?? ''))).toList(),
                  onChanged: (v) => setState(() => _issPid = v),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _issTitle,
                decoration: InputDecoration(labelText: AppStrings.t('notif.issueTitle'), hintText: AppStrings.t('notif.issueTitleHint')),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _severity,
                    decoration: const InputDecoration(labelText: 'Severity'),
                    items: _severities.map((s) => DropdownMenuItem(
                        value: s, child: Text(s[0].toUpperCase() + s.substring(1)))).toList(),
                    onChanged: (v) => setState(() => _severity = v!),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _category,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: _categories.map((c) => DropdownMenuItem(
                        value: c, child: Text(c[0].toUpperCase() + c.substring(1)))).toList(),
                    onChanged: (v) => setState(() => _category = v!),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              TextField(
                controller: _issDesc,
                maxLines: 3,
                decoration: InputDecoration(labelText: AppStrings.t('notif.issueDetail'), hintText: AppStrings.t('notif.issueDetailHint')),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _submitIssue,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.red,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(borderRadius: AppRadius.rMd),
                ),
                child: Text(AppStrings.t('notif.reportIssueSubmit')),
              ),
            ]),
          ),
          const SizedBox(height: 24),
          Text(AppStrings.t('notif.activeIssues'),
              style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.textPrimary)),
          const SizedBox(height: 12),
          if (activeIssues.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(child: Text(AppStrings.t('notif.noActiveIssues'),
                  style: TextStyle(color: AppColors.textMuted))),
            )
          else
            ...activeIssues.map((iss) => _issueCard(iss as Map)),
          if (resolvedIssues.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(AppStrings.t('notif.resolvedIssues'),
                style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.textPrimary)),
            const SizedBox(height: 12),
            ...resolvedIssues.map((iss) => _issueCard(iss as Map)),
          ],
        ],
      ),
    );
  }

  /// An issue counts as resolved only when the backend says so (``resolved``
  /// or ``closed``); anything else stays in the active list.
  bool _isResolvedIssue(Map iss) {
    final s = (iss['status']?.toString() ?? 'open').toLowerCase();
    return s == 'resolved' || s == 'closed';
  }

  Widget _issueCard(Map iss) {
    final resolved = _isResolvedIssue(iss);
    return _sectionCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(iss['title']?.toString() ?? '-',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                    color: resolved ? AppColors.textSecondary : AppColors.textPrimary)),
          ),
          _statusPill(iss['priority']?.toString() ?? 'low'),
        ]),
        const SizedBox(height: 4),
        Text(iss['description']?.toString() ?? '',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(fontSize: 14, color: AppColors.textMuted)),
        const SizedBox(height: 8),
        Row(children: [
          _statusPill(iss['incident_type']?.toString() ?? 'general'),
          const Spacer(),
          if (!resolved)
            TextButton(
              onPressed: () => _resolveIssue(iss['issue_id'] as int),
              child: Text(AppStrings.t('notif.markResolved')),
            ),
          _issueStatusPill(iss['status']?.toString() ?? 'open'),
        ]),
      ]),
    );
  }

  Widget _sectionCard({required Widget child, EdgeInsetsGeometry margin = EdgeInsets.zero}) {
    return sectionCard(margin: margin, padding: const EdgeInsets.all(16), child: child);
  }

  Widget _statusPill(String text) {
    final color = text == 'high' ? AppColors.red : (text == 'medium' ? AppColors.yellow : AppColors.green);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: AppRadius.rMd),
      child: Text(text[0].toUpperCase() + text.substring(1),
          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: color, letterSpacing: 0.2)),
    );
  }

  Widget _issueStatusPill(String status) {
    final s = status.toLowerCase();
    final resolved = s == 'resolved' || s == 'closed';
    final color = resolved ? AppColors.green : AppColors.red;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: AppRadius.rMd),
      child: Text(resolved ? 'Resolved' : 'Open',
          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: color, letterSpacing: 0.2)),
    );
  }

  Future<void> _loadReports() async {
    setState(() => _repLoading = true);
    try {
      if (projects.isEmpty) {
        projects = await ProjectCache.get(ApiService());
      }
      if (projects.isNotEmpty) {
        _repPid ??= projects.first['project_id'] as int;
        reports = await ApiService().getReports(_repPid!);
      }
      _repLoaded = true;
    } catch (e) {
      _repError = e;
      // Only show toast when the user is actually looking at this tab
      if (mounted && (_tabController?.index == (_isWorker ? -1 : 1))) {
        toast('Failed to load reports: $e');
      }
    } finally {
      if (mounted) setState(() => _repLoading = false);
    }
  }

  Future<void> _submitReport() async {
    if (_repPid == null) { toast('Please select a project'); return; }
    if (_workProgress.text.trim().isEmpty) { toast("Please describe today's progress"); return; }
    try {
      await ApiService().submitReport({
        'project_id': _repPid,
        'report_date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
        'weather': _weather,
        'work_progress': _workProgress.text,
        'materials_used': _materials.text,
        'issues_encountered': _issuesEnc.text,
        'manpower_count': int.tryParse(_manpower.text) ?? 0,
      });
      _workProgress.clear();
      _materials.clear();
      _issuesEnc.clear();
      _manpower.clear();
      toast('Daily report submitted');
      _loadReports();
    } on DioException catch (e) {
      toast(e.message ?? 'Submission failed');
    }
  }

  Future<void> _loadIssues() async {
    setState(() => _issLoading = true);
    try {
      if (projects.isEmpty) {
        projects = await ProjectCache.get(ApiService());
      }
      _issPid ??= projects.isNotEmpty ? projects.first['project_id'] as int : null;
      // Load issues in every status so the history stays visible/traceable.
      issues = await ApiService().getIssues();
      _issLoaded = true;
    } catch (e) {
      _issError = e;
      toast('Failed to load issues: $e');
    } finally {
      if (mounted) setState(() => _issLoading = false);
    }
  }

  Future<void> _submitIssue() async {
    if (_issPid == null && projects.isNotEmpty) _issPid = projects.first['project_id'] as int;
    if (_issPid == null) { toast('Create a project first'); return; }
    if (_issTitle.text.trim().isEmpty) { toast('Please enter a short issue title'); return; }
    try {
      await ApiService().createIssue({
        'title': _issTitle.text.trim(),
        'description': _issDesc.text.trim().isEmpty ? _issTitle.text.trim() : _issDesc.text.trim(),
        'project_id': _issPid,
        'priority': _severity,
        'incident_type': _category,
        'is_safety_incident': _category == 'safety',
      });
      _issTitle.clear();
      _issDesc.clear();
      toast('Issue reported');
      _loadIssues();
    } on DioException catch (e) {
      toast(e.message ?? 'Failed to report issue');
    }
  }

  Future<void> _resolveIssue(int id) async {
    try {
      await ApiService().resolveIssue(id);
      toast('Marked as resolved');
      _loadIssues();
    } on DioException catch (e) {
      toast(e.message ?? 'Failed to update issue');
    }
  }

  Widget _emptyState() => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
        child: GuidedEmptyState(
          icon: Icons.notifications_none_rounded,
          title: AppStrings.t('notif.noNotifications'),
          description: AppStrings.t('notif.allCaughtUp'),
          primaryLabel: AppStrings.t('common.retry'),
          primaryIcon: Icons.refresh_rounded,
          onPrimary: _load,
        ),
      );

  Widget _notificationTile(NotificationItem item) {
    final unread = !item.isRead;
    return GestureDetector(
      onTap: () {
        _markRead(item);
        if (item.relatedEntityType != null && item.relatedEntityType!.isNotEmpty) {
          _navigateToRelated(item);
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: unread ? AppColors.bgCard : AppColors.bgMain,
          borderRadius: AppRadius.rMd,
          border: Border.all(
              color: unread ? AppColors.border : AppColors.transparent),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Unread indicator bar
              if (unread)
                Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(AppRadius.md),
                        bottomLeft: Radius.circular(AppRadius.md)),
                  ),
                ),
              // Content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Type icon
                      Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          color: _iconColor(item.notificationType)
                              .withValues(alpha: 0.12),
                          borderRadius: AppRadius.rMd,
                        ),
                        child: Icon(
                          _typeIcon(item.notificationType),
                          size: 20,
                          color: _iconColor(item.notificationType),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Text
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                    fontSize: 13.5,
                                    fontWeight:
                                        unread ? FontWeight.w700 : FontWeight.w600,
                                    color: unread
                                        ? AppColors.textPrimary
                                        : AppColors.textSecondary)),
                            const SizedBox(height: 4),
                            Text(item.content,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                    fontSize: 14,
                                    color: AppColors.textMuted,
                                    height: 1.35)),
                            const SizedBox(height: 8),
                            Text(item.relativeTime,
                                style: GoogleFonts.inter(
                                    fontSize: 14,
                                    color: AppColors.textMuted)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _typeIcon(String type) {
    switch (type.toLowerCase()) {
      case 'attendance':
        return Icons.calendar_month_rounded;
      case 'task_overdue':
      case 'task_assigned':
        return Icons.check_circle_outline_rounded;
      case 'issue':
        return Icons.warning_amber_rounded;
      case 'safety':
        return Icons.health_and_safety_rounded;
      case 'daily_report':
        return Icons.description_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  Color _iconColor(String type) {
    switch (type.toLowerCase()) {
      case 'attendance':
        return AppColors.green;
      case 'task_overdue':
        return AppColors.red;
      case 'task_assigned':
        return AppColors.blue;
      case 'issue':
        return AppColors.yellow;
      case 'safety':
        return AppColors.red;
      case 'daily_report':
        return AppColors.purple;
      default:
        return AppColors.accent;
    }
  }
}

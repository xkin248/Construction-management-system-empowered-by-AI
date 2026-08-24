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
import '../widgets/app_settings_actions.dart';
import '../l10n/app_strings.dart';
import '../models/notification.dart';
import 'projects_page.dart';
import 'tasks_page.dart';
import 'workers_page.dart';
import 'attendance_page.dart';

const _weathers = ['Sunny', 'Cloudy', 'Rain', 'Thunderstorm'];
const _severities = ['low', 'medium', 'high'];
const _categories = ['safety', 'delay', 'equipment', 'quality', 'other'];

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});
  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  bool _loading = true;
  int _unreadCount = 0;
  List<NotificationItem> _items = [];
  NotificationSettings? _settings;
  Timer? _pollTimer;

  bool _repLoading = false;
  bool _issLoading = false;
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
    AppColors.darkMode.addListener(_rebuild);
    AppSettings.lang.addListener(_rebuild);
    _loadRole();
    _load();
    _loadReports();
    _loadIssues();
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
    AppColors.darkMode.removeListener(_rebuild);
    AppSettings.lang.removeListener(_rebuild);
    _pollTimer?.cancel();
    _workProgress.dispose();
    _materials.dispose();
    _issuesEnc.dispose();
    _manpower.dispose();
    _issTitle.dispose();
    _issDesc.dispose();
    super.dispose();
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
    try {
      final raw = await ApiService().getNotificationSettings();
      _settings = NotificationSettings.fromJson(Map<String, dynamic>.from(raw));
    } catch (_) {
      _settings ??= NotificationSettings();
    }
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(AppStrings.t('notif.settingsTitle'),
              style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 17)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _switch('Attendance', _settings?.notifAttendance ?? true,
                  (v) => setDialogState(() => _settings?.notifAttendance = v)),
              _switch('Task Overdue', _settings?.notifTaskOverdue ?? true,
                  (v) => setDialogState(() => _settings?.notifTaskOverdue = v)),
              _switch('Task Assigned', _settings?.notifTaskAssigned ?? true,
                  (v) => setDialogState(() => _settings?.notifTaskAssigned = v)),
              _switch('Issues', _settings?.notifIssue ?? true,
                  (v) => setDialogState(() => _settings?.notifIssue = v)),
              _switch('Safety Alerts', _settings?.notifSafety ?? true,
                  (v) => setDialogState(() => _settings?.notifSafety = v)),
              _switch('Daily Reports', _settings?.notifDailyReport ?? true,
                  (v) => setDialogState(() => _settings?.notifDailyReport = v)),
              const Divider(height: 20),
              _switch('Email', _settings?.notifEmail ?? false,
                  (v) => setDialogState(() => _settings?.notifEmail = v)),
              _switch('Push', _settings?.notifPush ?? true,
                  (v) => setDialogState(() => _settings?.notifPush = v)),
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(AppStrings.t('common.cancel'))),
            ElevatedButton(
              onPressed: () async {
                try {
                  await ApiService().updateNotificationSettings(_settings!.toJson());
                  if (ctx.mounted) Navigator.pop(ctx);
                  toast(AppStrings.t('common.success'));
                } catch (e) {
                  toast('${AppStrings.t('common.failed')}: $e');
                }
              },
              child: Text(AppStrings.t('common.save'))),
          ],
        ),
      ),
    );
  }

  Widget _switch(String label, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label,
          style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
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

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppColors.bgMain,
        appBar: AppBar(
          title: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(AppStrings.t('notif.title'),
                style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 17)),
            if (_unreadCount > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.red,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('$_unreadCount',
                    style: GoogleFonts.outfit(
                        color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)),
              ),
            ],
          ]),
          actions: [
            const AppSettingsActions(),
            if (_items.any((e) => !e.isRead))
              TextButton.icon(
                onPressed: _markAllRead,
                icon: const Icon(Icons.done_all_rounded, size: 18),
                label: Text(AppStrings.t('notif.markAllRead')),
                style: TextButton.styleFrom(foregroundColor: AppColors.accent),
              ),
            IconButton(
              icon: Icon(Icons.settings_outlined, color: AppColors.textSecondary),
              tooltip: 'Notification settings',
              onPressed: _openSettings,
            ),
          ],
          bottom: TabBar(
            indicatorColor: AppColors.accent,
            labelColor: AppColors.accent,
            unselectedLabelColor: AppColors.textSecondary,
            labelStyle: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700),
            tabs: [
              Tab(text: AppStrings.t('notif.title')),
              if (!_isWorker) Tab(text: AppStrings.t('notif.dailyReports')),
              Tab(text: AppStrings.t('notif.issues')),
            ],
          ),
        ),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppBreakpoints.maxContentWidth),
            child: SizedBox(
              width: double.infinity,
              child: TabBarView(
                children: [
                  _buildNotificationsTab(),
                  if (!_isWorker) _buildReportsTab(),
                  _buildIssuesTab(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationsTab() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_items.isEmpty) return _emptyState();
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
    if (_repLoading) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _loadReports,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(AppStrings.t('notif.submitDailyReport'),
                  style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.textPrimary)),
              const SizedBox(height: 14),
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(AppStrings.t('notif.submitReport')),
              ),
            ]),
          ),
          const SizedBox(height: 20),
          Text(AppStrings.t('notif.recentReports'),
              style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.textPrimary)),
          const SizedBox(height: 10),
          if (reports.isEmpty)
            Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: Text(AppStrings.t('notif.noReports'),
                  style: TextStyle(color: AppColors.textMuted))),
            )
          else
            ...reports.map((r) => _sectionCard(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: AppColors.accentLight,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.description_outlined, color: AppColors.accent, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${r['report_date'] ?? ''} · ${r['weather'] ?? ''}',
                            style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary)),
                        const SizedBox(height: 2),
                        Text(r['work_progress']?.toString() ?? 'No content',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.outfit(fontSize: 14, color: AppColors.textMuted)),
                      ]),
                    ),
                    Text('${r['manpower_count'] ?? 0}\nworkers',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(fontSize: 14, color: AppColors.textMuted)),
                  ]),
                )),
        ],
      ),
    );
  }

  Widget _buildIssuesTab() {
    if (_issLoading) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _loadIssues,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(AppStrings.t('notif.reportIssue'),
                  style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.textPrimary)),
              const SizedBox(height: 14),
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
                const SizedBox(width: 10),
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(AppStrings.t('notif.reportIssueSubmit')),
              ),
            ]),
          ),
          const SizedBox(height: 20),
          Text(AppStrings.t('notif.activeIssues'),
              style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.textPrimary)),
          const SizedBox(height: 10),
          if (issues.isEmpty)
            Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: Text(AppStrings.t('notif.noIssues'),
                  style: TextStyle(color: AppColors.textMuted))),
            )
          else
            ...issues.map((iss) => _sectionCard(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(
                        child: Text(iss['title']?.toString() ?? '-',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 13.5, color: AppColors.textPrimary)),
                      ),
                      _statusPill(iss['priority']?.toString() ?? 'low'),
                    ]),
                    const SizedBox(height: 4),
                    Text(iss['description']?.toString() ?? '',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(fontSize: 14, color: AppColors.textMuted)),
                    const SizedBox(height: 8),
                    Row(children: [
                      _statusPill(iss['incident_type']?.toString() ?? 'general'),
                      const Spacer(),
                      TextButton(
                        onPressed: () => _resolveIssue(iss['issue_id'] as int),
                        child: Text(AppStrings.t('notif.markResolved')),
                      ),
                    ]),
                  ]),
                )),
        ],
      ),
    );
  }

  Widget _sectionCard({required Widget child, EdgeInsetsGeometry margin = EdgeInsets.zero}) {
    return Container(
      margin: margin,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }

  Widget _statusPill(String text) {
    final color = text == 'high' ? AppColors.red : (text == 'medium' ? AppColors.yellow : AppColors.green);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(8)),
      child: Text(text[0].toUpperCase() + text.substring(1),
          style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700, color: color)),
    );
  }

  Future<void> _loadReports() async {
    setState(() => _repLoading = true);
    try {
      projects = await ApiService().getProjects();
      if (projects.isNotEmpty) {
        _repPid ??= projects.first['project_id'] as int;
        reports = await ApiService().getReports(_repPid!);
      }
    } catch (e) {
      toast('Failed to load reports: $e');
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
        'submitted_by': 1,
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
      projects = await ApiService().getProjects();
      _issPid ??= projects.isNotEmpty ? projects.first['project_id'] as int : null;
      issues = await ApiService().getIssues(status: 'open');
    } catch (e) {
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

  Widget _emptyState() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              color: AppColors.accentLight,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(Icons.notifications_none_rounded,
                size: 36, color: AppColors.accent),
          ),
          const SizedBox(height: 16),
          Text(AppStrings.t('notif.noNotifications'),
              style: GoogleFonts.outfit(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 6),
          Text(AppStrings.t('notif.allCaughtUp'),
              style: GoogleFonts.outfit(
                  fontSize: 13, color: AppColors.textMuted)),
        ]),
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
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: unread ? AppColors.bgCard : AppColors.bgMain,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: unread ? AppColors.border : Colors.transparent),
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
                        topLeft: Radius.circular(12),
                        bottomLeft: Radius.circular(12)),
                  ),
                ),
              // Content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Type icon
                      Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          color: _iconColor(item.notificationType)
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
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
                                style: GoogleFonts.outfit(
                                    fontSize: 13.5,
                                    fontWeight:
                                        unread ? FontWeight.w700 : FontWeight.w600,
                                    color: unread
                                        ? AppColors.textPrimary
                                        : AppColors.textSecondary)),
                            const SizedBox(height: 3),
                            Text(item.content,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.outfit(
                                    fontSize: 14,
                                    color: AppColors.textMuted,
                                    height: 1.35)),
                            const SizedBox(height: 6),
                            Text(item.relativeTime,
                                style: GoogleFonts.outfit(
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

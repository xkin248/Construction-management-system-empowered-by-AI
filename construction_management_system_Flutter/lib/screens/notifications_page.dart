import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../models/notification.dart';
import 'projects_page.dart';
import 'tasks_page.dart';
import 'workers_page.dart';
import 'attendance_page.dart';

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

  @override
  void initState() {
    super.initState();
    _load();
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) => _refreshCount());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
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
          title: Text('Notification Settings',
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
              child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                try {
                  await ApiService().updateNotificationSettings(_settings!.toJson());
                  if (ctx.mounted) Navigator.pop(ctx);
                  toast('Settings saved');
                } catch (e) {
                  toast('Failed: $e');
                }
              },
              child: const Text('Save')),
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
    return Scaffold(
      backgroundColor: AppColors.bgMain,
      appBar: AppBar(
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('Notifications',
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
          if (_items.any((e) => !e.isRead))
            TextButton.icon(
              onPressed: _markAllRead,
              icon: const Icon(Icons.done_all_rounded, size: 18),
              label: const Text('All Read'),
              style: TextButton.styleFrom(foregroundColor: AppColors.accent),
            ),
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: AppColors.textSecondary),
            tooltip: 'Notification settings',
            onPressed: _openSettings,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? _emptyState()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _items.length,
                    itemBuilder: (ctx, i) => _notificationTile(_items[i]),
                  ),
                ),
    );
  }

  Widget _emptyState() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              color: AppColors.accentLight,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.notifications_none_rounded,
                size: 36, color: AppColors.accent),
          ),
          const SizedBox(height: 16),
          Text('No notifications',
              style: GoogleFonts.outfit(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 6),
          Text('You\'re all caught up!',
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
                  decoration: const BoxDecoration(
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

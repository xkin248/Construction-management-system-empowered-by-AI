class NotificationItem {
  final int notificationId;
  final int supervisorId;
  final String notificationType;
  final String title;
  final String content;
  final String? relatedEntityType;
  final int? relatedEntityId;
  final bool isRead;
  final DateTime createdAt;
  final DateTime? readAt;

  NotificationItem({
    required this.notificationId,
    required this.supervisorId,
    required this.notificationType,
    required this.title,
    required this.content,
    this.relatedEntityType,
    this.relatedEntityId,
    this.isRead = false,
    required this.createdAt,
    this.readAt,
  });

  factory NotificationItem.fromJson(Map<String, dynamic> json) =>
      NotificationItem(
        notificationId: json['notification_id'] ?? 0,
        supervisorId: json['supervisor_id'] ?? 0,
        notificationType: json['notification_type'] ?? '',
        title: json['title'] ?? '',
        content: json['content'] ?? '',
        relatedEntityType: json['related_entity_type'],
        relatedEntityId: json['related_entity_id'],
        isRead: json['is_read'] == true || json['is_read'] == 1,
        createdAt:
            DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
        readAt: DateTime.tryParse(json['read_at'] ?? ''),
      );

  String get relativeTime {
    final now = DateTime.now();
    final diff = now.difference(createdAt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${createdAt.month.toString().padLeft(2, '0')}-${createdAt.day.toString().padLeft(2, '0')}';
  }
}

class NotificationSettings {
  final int settingId;
  bool notifAttendance;
  bool notifTaskOverdue;
  bool notifTaskAssigned;
  bool notifIssue;
  bool notifSafety;
  bool notifDailyReport;
  bool notifEmail;
  bool notifPush;

  NotificationSettings({
    this.settingId = 0,
    this.notifAttendance = true,
    this.notifTaskOverdue = true,
    this.notifTaskAssigned = true,
    this.notifIssue = true,
    this.notifSafety = true,
    this.notifDailyReport = true,
    this.notifEmail = false,
    this.notifPush = true,
  });

  factory NotificationSettings.fromJson(Map<String, dynamic> json) =>
      NotificationSettings(
        settingId: json['setting_id'] ?? 0,
        notifAttendance: json['notif_attendance'] == true,
        notifTaskOverdue: json['notif_task_overdue'] == true,
        notifTaskAssigned: json['notif_task_assigned'] == true,
        notifIssue: json['notif_issue'] == true,
        notifSafety: json['notif_safety'] == true,
        notifDailyReport: json['notif_daily_report'] == true,
        notifEmail: json['notif_email'] == true,
        notifPush: json['notif_push'] == true,
      );

  Map<String, dynamic> toJson() => {
        'notif_attendance': notifAttendance,
        'notif_task_overdue': notifTaskOverdue,
        'notif_task_assigned': notifTaskAssigned,
        'notif_issue': notifIssue,
        'notif_safety': notifSafety,
        'notif_daily_report': notifDailyReport,
        'notif_email': notifEmail,
        'notif_push': notifPush,
      };
}

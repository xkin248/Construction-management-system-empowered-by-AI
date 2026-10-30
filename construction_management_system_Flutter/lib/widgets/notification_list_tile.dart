import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/notification.dart';
import '../theme/app_theme.dart';
import 'a11y.dart';

/// One row of the notification feed.
///
/// Extracted from `notifications_page.dart` into a standalone widget so the
/// lazy [ListView.builder] can rebuild a single tile (e.g. when it flips from
/// unread to read) without rebuilding the whole page.
class NotificationListTile extends StatelessWidget {
  const NotificationListTile({
    super.key,
    required this.item,
    this.onTap,
  });

  final NotificationItem item;
  final VoidCallback? onTap;

  static IconData typeIcon(String type) {
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

  static Color iconColor(String type) {
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

  @override
  Widget build(BuildContext context) {
    final unread = !item.isRead;
    final tint = iconColor(item.notificationType);
    return semanticTapTarget(
      label: item.title,
      hint: unread ? 'Unread' : null,
      child: GestureDetector(
      onTap: onTap,
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
                          color: tint.withValues(alpha: 0.12),
                          borderRadius: AppRadius.rMd,
                        ),
                        child: Icon(
                          typeIcon(item.notificationType),
                          size: 20,
                          color: tint,
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
    ));
  }
}

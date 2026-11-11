import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/api_service.dart';
import '../../services/app_settings.dart';
import '../../theme/app_theme.dart';
import '../../widgets/a11y.dart';

/// Thumbnail + full-screen viewer for the on-site selfie attached to a
/// check-in / check-out record (spec PART B8: a supervisor must be able to
/// review the picture inside the app).
///
/// The backend only hands out a relative path (`/attendance/photos/...`) that
/// needs the bearer token, so the bytes are fetched through [ApiService] and
/// rendered with `Image.memory` — this also works on Web, where an image
/// request cannot carry an Authorization header.
class AttendancePhotoThumb extends StatefulWidget {
  const AttendancePhotoThumb({
    super.key,
    required this.photoUrl,
    this.label,
    this.size = 52,
  });

  /// Relative URL returned by the attendance API (`in_photo_url` /
  /// `out_photo_url`). When null the widget renders a muted placeholder so the
  /// row keeps its shape.
  final String? photoUrl;
  final String? label;
  final double size;

  @override
  State<AttendancePhotoThumb> createState() => _AttendancePhotoThumbState();
}

class _AttendancePhotoThumbState extends State<AttendancePhotoThumb> {
  Future<Uint8List>? _bytes;

  @override
  void initState() {
    super.initState();
    if (widget.photoUrl != null && widget.photoUrl!.isNotEmpty) {
      _bytes = ApiService().fetchAttendancePhoto(widget.photoUrl!);
    }
  }

  @override
  void didUpdateWidget(covariant AttendancePhotoThumb old) {
    super.didUpdateWidget(old);
    if (old.photoUrl != widget.photoUrl) {
      _bytes = (widget.photoUrl != null && widget.photoUrl!.isNotEmpty)
          ? ApiService().fetchAttendancePhoto(widget.photoUrl!)
          : null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasPhoto = widget.photoUrl != null && widget.photoUrl!.isNotEmpty;
    final placeholder = Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: AppColors.bgMain,
        borderRadius: AppRadius.rMd,
        border: Border.all(color: AppColors.border),
      ),
      child: Icon(
        Icons.no_photography_outlined,
        size: widget.size * 0.4,
        color: AppColors.textMuted,
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        semanticTapTarget(
          label: widget.label ??
              AppSettings.t('View check-in selfie', '查看打卡自拍', 'Lihat swafoto'),
          child: GestureDetector(
            onTap: hasPhoto ? () => showAttendancePhoto(context, widget.photoUrl!) : null,
            child: ClipRRect(
              borderRadius: AppRadius.rMd,
              child: !hasPhoto
                  ? placeholder
                  : FutureBuilder<Uint8List>(
                      future: _bytes,
                      builder: (ctx, snap) {
                        if (snap.hasError) {
                          return Container(
                            width: widget.size,
                            height: widget.size,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: AppColors.bgMain,
                              borderRadius: AppRadius.rMd,
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Icon(Icons.broken_image_outlined,
                                size: widget.size * 0.4, color: AppColors.textMuted),
                          );
                        }
                        final data = snap.data;
                        if (data == null) {
                          return Container(
                            width: widget.size,
                            height: widget.size,
                            alignment: Alignment.center,
                            color: AppColors.bgMain,
                            child: const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          );
                        }
                        return Image.memory(
                          data,
                          width: widget.size,
                          height: widget.size,
                          fit: BoxFit.cover,
                          cacheWidth: (widget.size * 2).toInt(),
                          gaplessPlayback: true,
                        );
                      },
                    ),
            ),
          ),
        ),
        if (widget.label != null) ...[
          const SizedBox(height: 4),
          Text(
            widget.label!,
            style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted),
          ),
        ],
      ],
    );
  }
}

/// Opens the selfie full-screen so the supervisor can inspect the face and the
/// site behind it. Pinch-to-zoom is enabled for evidence review.
Future<void> showAttendancePhoto(
  BuildContext context,
  String photoUrl, {
  String? title,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: AppColors.scrim,
    builder: (ctx) => Dialog(
      backgroundColor: AppColors.bgCard,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: AppRadius.rLg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Icon(Icons.photo_camera_rounded, size: 18, color: AppColors.green),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title ??
                          AppSettings.t('Attendance selfie', '考勤自拍', 'Swafoto kehadiran'),
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close_rounded, size: 20),
                    tooltip: AppSettings.t('Close', '关闭', 'Tutup'),
                  ),
                ],
              ),
            ),
            Flexible(
              child: FutureBuilder<Uint8List>(
                future: ApiService().fetchAttendancePhoto(photoUrl),
                builder: (c, snap) {
                  if (snap.hasError) {
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        AppSettings.t(
                          'Could not load the selfie. It may have been removed.',
                          '自拍加载失败，可能已被清理。',
                          'Gagal memuatkan swafoto.',
                        ),
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted),
                      ),
                    );
                  }
                  final data = snap.data;
                  if (data == null) {
                    return const Padding(
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    );
                  }
                  return InteractiveViewer(
                    minScale: 1,
                    maxScale: 4,
                    child: Image.memory(data, fit: BoxFit.contain),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    ),
  );
}

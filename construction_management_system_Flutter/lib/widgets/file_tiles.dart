import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/file.dart';
import '../theme/app_theme.dart';
import 'signed_file_image.dart';

/// Shared visual helpers for file tiles (icon / category tint / info chip).
///
/// Lives next to the tile widgets so both the grid card and the list row stay
/// pixel-identical to the previous inline implementations in `files_page.dart`.
IconData fileTypeIcon(FileItem file) {
  if (file.isImage) return Icons.image_rounded;
  if (file.isPDF) return Icons.picture_as_pdf_rounded;
  switch (file.fileCategory) {
    case 'drawings':
      return Icons.architecture_rounded;
    case 'reports':
      return Icons.assessment_rounded;
    default:
      return Icons.description_rounded;
  }
}

Color fileTypeColor(FileItem file) {
  if (file.isImage) return AppColors.purple;
  if (file.isPDF) return AppColors.red;
  switch (file.fileCategory) {
    case 'drawings':
      return AppColors.blue;
    case 'reports':
      return AppColors.green;
    default:
      return AppColors.accent;
  }
}

Color fileCategoryBg(String cat) {
  switch (cat) {
    case 'drawings':
      return AppColors.blueLight;
    case 'photos':
      return AppColors.purpleLight;
    case 'reports':
      return AppColors.greenLight;
    default:
      return AppColors.accentLight;
  }
}

class FileInfoChip extends StatelessWidget {
  const FileInfoChip({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.bgMain,
        borderRadius: AppRadius.rMd,
      ),
      child: Text(label,
          style: GoogleFonts.inter(
              fontSize: 14, fontWeight: FontWeight.w600,
              color: AppColors.textSecondary)),
    );
  }
}

/// Grid cell of the files gallery.
///
/// Extracted from `files_page.dart` so the lazy [GridView.builder] rebuilds one
/// cell at a time instead of re-running the page's builder closure, and so the
/// decoded thumbnail can be size-bounded by the caller.
class FileGridCard extends StatelessWidget {
  const FileGridCard({
    super.key,
    required this.file,
    this.onTap,
    this.onLongPress,
    this.cacheSize,
  });

  final FileItem file;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Max decoded edge in physical pixels for the thumbnail.
  final int? cacheSize;

  @override
  Widget build(BuildContext context) {
    final icon = Icon(fileTypeIcon(file), size: 32, color: fileTypeColor(file));
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: sectionCard(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: fileCategoryBg(file.fileCategory),
                  borderRadius: AppRadius.rMd,
                ),
                child: Center(
                  child: file.isImage && file.thumbnailPath != null
                      ? ClipRRect(
                          borderRadius: AppRadius.rMd,
                          child: SignedFileImage(
                            fileId: file.fileId,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            cacheWidth: cacheSize,
                            cacheHeight: cacheSize,
                            errorWidget: icon,
                          ),
                        )
                      : icon,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              file.originalName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                  fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 4),
            Text(
              '${file.sizeFormatted}  ${file.dateFormatted}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                  fontSize: 14, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

/// One row of the files list view.
class FileListTile extends StatelessWidget {
  const FileListTile({
    super.key,
    required this.file,
    this.onTap,
    this.onLongPress,
  });

  final FileItem file;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: sectionCard(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: fileCategoryBg(file.fileCategory),
              borderRadius: AppRadius.rMd,
            ),
            child: Center(
              child: Icon(fileTypeIcon(file), size: 24, color: fileTypeColor(file)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(file.originalName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 4),
                Row(children: [
                  FileInfoChip(label: file.categoryLabel),
                  const SizedBox(width: 8),
                  Text(file.sizeFormatted,
                      style: GoogleFonts.inter(
                          fontSize: 13,
                          color: AppColors.textMuted)),
                  const SizedBox(width: 8),
                  Text(file.dateFormatted,
                      style: GoogleFonts.inter(
                          fontSize: 13,
                          color: AppColors.textMuted)),
                ]),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.chevron_right_rounded,
              color: AppColors.textMuted, size: 20),
        ]),
      ),
    );
  }
}

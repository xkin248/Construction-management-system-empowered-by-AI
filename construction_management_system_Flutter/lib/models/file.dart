import '../utils/date_helper.dart';

class FileItem {
  final int fileId;
  final String originalName;
  final String storedName;
  final int fileSize;
  final String mimeType;
  final String fileCategory;
  final String? thumbnailPath;
  final int projectId;
  final int uploadedBy;
  final String? uploadedByName;
  final DateTime createdAt;
  final DateTime updatedAt;

  FileItem({
    required this.fileId,
    required this.originalName,
    required this.storedName,
    required this.fileSize,
    required this.mimeType,
    required this.fileCategory,
    this.thumbnailPath,
    required this.projectId,
    this.uploadedBy = 0,
    this.uploadedByName,
    required this.createdAt,
    required this.updatedAt,
  });

  factory FileItem.fromJson(Map<String, dynamic> json) => FileItem(
        fileId: json['file_id'] ?? 0,
        originalName: json['original_name'] ?? '',
        storedName: json['stored_name'] ?? '',
        fileSize: json['file_size'] ?? 0,
        mimeType: json['mime_type'] ?? '',
        fileCategory: json['file_category'] ?? 'documents',
        thumbnailPath: json['thumbnail_path'],
        projectId: json['project_id'] ?? 0,
        uploadedBy: json['uploaded_by'] ?? 0,
        uploadedByName: json['uploaded_by_name'],
        createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(json['updated_at'] ?? '') ?? DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'file_id': fileId,
        'original_name': originalName,
        'stored_name': storedName,
        'file_size': fileSize,
        'mime_type': mimeType,
        'file_category': fileCategory,
        'thumbnail_path': thumbnailPath,
        'project_id': projectId,
        'uploaded_by': uploadedBy,
        'uploaded_by_name': uploadedByName,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  String get sizeFormatted {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1048576) return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    return '${(fileSize / 1048576).toStringAsFixed(1)} MB';
  }

  String get dateFormatted => DateHelper.formatShort(createdAt.toLocal());

  String get categoryLabel {
    const map = {
      'drawings': 'Drawing',
      'documents': 'Document',
      'photos': 'Photo',
      'reports': 'Report',
    };
    return map[fileCategory] ?? fileCategory;
  }

  String get fileExtension {
    final dot = originalName.lastIndexOf('.');
    return dot == -1 ? '' : originalName.substring(dot + 1).toUpperCase();
  }

  bool get isImage {
    const imageTypes = ['image/jpeg', 'image/png', 'image/gif', 'image/webp', 'image/bmp'];
    return imageTypes.contains(mimeType);
  }

  bool get isPDF => mimeType == 'application/pdf';
}

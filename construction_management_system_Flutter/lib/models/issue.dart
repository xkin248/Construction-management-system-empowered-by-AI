class Issue {
  final int id;
  final int projectId;
  final String projectName;
  final String title;
  final String description;
  final String severity; // Low / Medium / High / Critical
  final String category; // Safety / Quality / Delay / Material / Equipment
  final String status; // Open / In Progress / Resolved
  final int? reportedBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Issue({
    required this.id,
    required this.projectId,
    this.projectName = '',
    required this.title,
    this.description = '',
    this.severity = 'Low',
    this.category = 'Safety',
    this.status = 'Open',
    this.reportedBy,
    this.createdAt,
    this.updatedAt,
  });

  factory Issue.fromJson(Map<String, dynamic> json) => Issue(
        id: json['id'] ?? 0,
        projectId: json['project_id'] ?? 0,
        projectName: json['project_name'] ?? '',
        title: json['title'] ?? '',
        description: json['description'] ?? '',
        severity: json['severity'] ?? 'Low',
        category: json['category'] ?? 'Safety',
        status: json['status'] ?? 'Open',
        reportedBy: json['reported_by'],
        createdAt: json['created_at'] != null
            ? DateTime.tryParse(json['created_at'])
            : null,
        updatedAt: json['updated_at'] != null
            ? DateTime.tryParse(json['updated_at'])
            : null,
      );
}
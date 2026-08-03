class DailyReport {
  final int id;
  final int projectId;
  final String projectName;
  final DateTime reportDate;
  final String weather;
  final String workProgress;
  final String materialsUsed;
  final String issuesEncountered;
  final int manpowerCount;
  final int submittedBy;
  final String? submittedByName;
  final DateTime? createdAt;

  DailyReport({
    required this.id,
    required this.projectId,
    this.projectName = '',
    required this.reportDate,
    required this.weather,
    this.workProgress = '',
    this.materialsUsed = '',
    this.issuesEncountered = '',
    this.manpowerCount = 0,
    required this.submittedBy,
    this.submittedByName,
    this.createdAt,
  });

  factory DailyReport.fromJson(Map<String, dynamic> json) => DailyReport(
        id: json['id'] ?? 0,
        projectId: json['project_id'] ?? 0,
        projectName: json['project_name'] ?? '',
        reportDate: DateTime.tryParse(json['report_date']) ?? DateTime.now(),
        weather: json['weather'] ?? 'Sunny',
        workProgress: json['work_progress'] ?? '',
        materialsUsed: json['materials_used'] ?? '',
        issuesEncountered: json['issues_encountered'] ?? '',
        manpowerCount: json['manpower_count'] ?? 0,
        submittedBy: json['submitted_by'] ?? 0,
        submittedByName: json['submitted_by_name'],
        createdAt: json['created_at'] != null
            ? DateTime.tryParse(json['created_at'])
            : null,
      );

  Map<String, dynamic> toJson() => {
        'project_id': projectId,
        'report_date': reportDate.toIso8601String().split('T')[0],
        'weather': weather,
        'work_progress': workProgress,
        'materials_used': materialsUsed,
        'issues_encountered': issuesEncountered,
        'manpower_count': manpowerCount,
        'submitted_by': submittedBy,
      };
}
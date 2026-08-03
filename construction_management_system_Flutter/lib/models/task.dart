class Task {
  final int id;
  final String title;
  final int projectId;
  final String projectName;
  final String priority; // High / Medium / Low
  final String status; // In Progress / Completed / Pending
  final double progress;
  final DateTime? dueDate;
  final int estimatedHours;
  final int loggedHours;
  final String assigneeName;
  final String assigneeRole;
  final List<String> requiredSkills;
  final double aiMatchScore;

  Task({
    required this.id,
    required this.title,
    required this.projectId,
    required this.projectName,
    this.priority = 'Medium',
    this.status = 'Pending',
    this.progress = 0,
    this.dueDate,
    this.estimatedHours = 0,
    this.loggedHours = 0,
    required this.assigneeName,
    this.assigneeRole = '',
    this.requiredSkills = const [],
    this.aiMatchScore = 0,
  });

  factory Task.fromJson(Map<String, dynamic> json) => Task(
        id: json['id'] ?? 0,
        title: json['title'] ?? '',
        projectId: json['project_id'] ?? 0,
        projectName: json['project_name'] ?? '',
        priority: json['priority'] ?? 'Medium',
        status: json['status'] ?? 'Pending',
        progress: (json['progress'] ?? 0).toDouble(),
        dueDate: json['due_date'] != null
            ? DateTime.tryParse(json['due_date'])
            : null,
        estimatedHours: json['estimated_hours'] ?? 0,
        loggedHours: json['logged_hours'] ?? 0,
        assigneeName: json['assignee_name'] ?? '',
        assigneeRole: json['assignee_role'] ?? '',
        requiredSkills:
            List<String>.from(json['required_skills'] ?? []),
        aiMatchScore: (json['ai_match_score'] ?? 0).toDouble(),
      );
}
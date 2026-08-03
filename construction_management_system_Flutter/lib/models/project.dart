class Project {
  final int id;
  final String name;
  final String location;
  final DateTime? startDate;
  final DateTime? dueDate;
  final double budget;
  final double spent;
  final double progress;
  final int workersCount;
  final String status; // active / completed / paused

  Project({
    required this.id,
    required this.name,
    required this.location,
    this.startDate,
    this.dueDate,
    required this.budget,
    this.spent = 0,
    this.progress = 0,
    this.workersCount = 0,
    this.status = 'active',
  });

  factory Project.fromJson(Map<String, dynamic> json) => Project(
        id: json['id'] ?? 0,
        name: json['name'] ?? '',
        location: json['location'] ?? '',
        startDate: json['start_date'] != null
            ? DateTime.tryParse(json['start_date'])
            : null,
        dueDate: json['due_date'] != null
            ? DateTime.tryParse(json['due_date'])
            : null,
        budget: (json['budget'] ?? 0).toDouble(),
        spent: (json['spent'] ?? 0).toDouble(),
        progress: (json['progress'] ?? 0).toDouble(),
        workersCount: json['workers_count'] ?? 0,
        status: json['status'] ?? 'active',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'location': location,
        'start_date': startDate?.toIso8601String(),
        'due_date': dueDate?.toIso8601String(),
        'budget': budget,
        'spent': spent,
        'progress': progress,
        'workers_count': workersCount,
        'status': status,
      };
}
class Attendance {
  final int id;
  final int workerId;
  final int projectId;
  final String status;
  final DateTime? checkIn;
  final DateTime? checkOut;
  final double? inDistanceM;
  final int outOfFenceCount;
  final double? hoursWorked;
  final double? latIn;
  final double? lngIn;

  Attendance({
    required this.id,
    required this.workerId,
    required this.projectId,
    required this.status,
    this.checkIn,
    this.checkOut,
    this.inDistanceM,
    this.outOfFenceCount = 0,
    this.hoursWorked,
    this.latIn,
    this.lngIn,
  });

  factory Attendance.fromJson(Map<String, dynamic> json) => Attendance(
        id: json['attendance_id'] ?? json['id'] ?? 0,
        workerId: json['worker_id'] ?? 0,
        projectId: json['project_id'] ?? 0,
        status: json['status'] ?? 'absent',
        checkIn: json['check_in_time'] != null
            ? DateTime.tryParse(json['check_in_time'])
            : null,
        checkOut: json['check_out_time'] != null
            ? DateTime.tryParse(json['check_out_time'])
            : null,
        inDistanceM: (json['in_distance_m'] ?? 0).toDouble(),
        outOfFenceCount: json['out_of_fence_count'] ?? 0,
        hoursWorked: (json['hours_worked'] ?? 0).toDouble(),
        latIn: json['lat_in']?.toDouble(),
        lngIn: json['lng_in']?.toDouble(),
      );
}
class Worker {
  final int id;
  final String name;
  final String trade;
  final String? phone;
  final String? icNumber;
  final String? todayStatus;
  final String? checkInTime;
  final String? checkOutTime;
  final double? hoursToday;
  final Map<String, dynamic>? project;

  Worker({
    required this.id,
    required this.name,
    required this.trade,
    this.phone,
    this.icNumber,
    this.todayStatus,
    this.checkInTime,
    this.checkOutTime,
    this.hoursToday,
    this.project,
  });

  factory Worker.fromJson(Map<String, dynamic> json) => Worker(
        id: json['worker_id'] ?? json['id'] ?? 0,
        name: json['name'] ?? '',
        trade: json['trade'] ?? '',
        phone: json['phone'],
        icNumber: json['ic_number'],
        todayStatus: json['today_status'],
        checkInTime: json['check_in_time'],
        checkOutTime: json['check_out_time'],
        hoursToday: json['hours_today'] != null
            ? (json['hours_today'] as num).toDouble()
            : null,
        project: json['project'] as Map<String, dynamic>?,
      );
}
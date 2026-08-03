import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../config/env.dart';

class ApiService {
  static final ApiService _i = ApiService._internal();
  factory ApiService() => _i;
  ApiService._internal();

  Dio? _d;
  String? _t;
  VoidCallback? _out;
  static const p = '/api', fast = true, port = 8000;

  Dio get dio {
    if (_d == null) throw Exception('Please call ApiService().init() first');
    return _d!;
  }

  String get baseUrl => Env.baseUrl;

  String get htmlRoot => '$baseUrl/html';

  void init({String? token, VoidCallback? onUnauthorized}) {
    _t = token;
    _out = onUnauthorized;
    if (_d != null) {
      // Already initialised — just refresh the token reference
      return;
    }
    _d = Dio(BaseOptions(
      baseUrl: baseUrl + p,
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 15),
      contentType: Headers.jsonContentType,
      responseType: ResponseType.json,
      headers: {'Accept': 'application/json'},
    ));
    _d!.interceptors.add(LogInterceptor(
      requestBody: true,
      responseBody: true,
      logPrint: (o) => debugPrint('[API] $o'),
    ));
    _d!.interceptors.add(InterceptorsWrapper(
      onRequest: (o, h) {
        if (_t?.isNotEmpty == true) {
          o.headers['Authorization'] = 'Bearer $_t';
        }
        return h.next(o);
      },
      onResponse: (r, h) {
        if (r.data is Map && (r.data as Map).containsKey('data')) {
          r.data = (r.data as Map)['data'];
        }
        return h.next(r);
      },
      onError: (e, h) {
        String m = 'Request failed';
        switch (e.type) {
          case DioExceptionType.connectionTimeout:
          case DioExceptionType.sendTimeout:
          case DioExceptionType.receiveTimeout:
            m = 'Network timeout';
            break;
          case DioExceptionType.badResponse:
            final c = e.response?.statusCode;
            final d = e.response?.data;
            if (c == 401) {
              m = 'Login session expired';
              _t = null;
              _out?.call();
            } else if (c == 410) {
              m = d is Map ? d['detail'] ?? 'Check-in was auto-cancelled' : 'Check-in cancelled';
            } else {
              m = d is Map && d['detail'] != null
                  ? d['detail'].toString()
                  : 'Request failed ($c)';
            }
            break;
          case DioExceptionType.unknown:
            m = 'Cannot reach the backend, please confirm it is running';
            break;
          default:
            break;
        }
        return h.next(e.copyWith(message: m));
      },
    ));
  }

  void ut(String nt) => _t = nt;
  void ct() => _t = null;

  Future<Map> login({required String a, required String p}) async {
    final d = fast
        ? FormData.fromMap({'username': a.trim(), 'password': p})
        : {'email': a.trim(), 'password': p};
    final r = await dio.post('/auth/login', data: d);
    final m = Map.from(r.data);
    if (m['access_token'] != null) ut(m['access_token']);
    return {
      'access_token': m['access_token'] ?? '',
      'user_type': m['user_type'] ?? 'supervisor',
      'user': Map.from(m['user'] ?? {}),
    };
  }

  Future<Map> registerWorker({
    required String name,
    required String email,
    required String password,
    String? phone,
    String? icNumber,
    String? trade,
    int? projectId,
  }) async {
    final r = await dio.post('/auth/register/worker', data: {
      'name': name.trim(),
      'email': email.trim().toLowerCase(),
      'password': password,
      if (phone != null) 'phone': phone,
      if (icNumber != null) 'ic_number': icNumber,
      if (trade != null) 'trade': trade,
      if (projectId != null) 'project_id': projectId,
      'role': 'worker',
    });
    return Map.from(r.data);
  }

  Future<Map> me() async => Map.from((await dio.get('/auth/me')).data);

  // ───────── Worker Authenticated Attendance ─────────
  Future<Map> workerCheckIn({
    required int projectId,
    required double lat,
    required double lng,
    String? deviceInfo,
    String? deviceType,
    String? deviceId,
  }) async =>
      Map.from((await dio.post('/attendance/worker/check-in', data: {
        'project_id': projectId,
        'lat': lat,
        'lng': lng,
        if (deviceInfo != null) 'device_info': deviceInfo,
        if (deviceType != null) 'device_type': deviceType,
        if (deviceId != null) 'device_id': deviceId,
      })).data);

  Future<Map> workerCheckOut({
    required double lat,
    required double lng,
    String? deviceInfo,
    String? deviceType,
  }) async =>
      Map.from((await dio.post('/attendance/worker/check-out', data: {
        'lat': lat,
        'lng': lng,
        if (deviceInfo != null) 'device_info': deviceInfo,
        if (deviceType != null) 'device_type': deviceType,
      })).data);

  Future<Map> workerTodayAttendance() async =>
      Map.from((await dio.get('/attendance/worker/today')).data);

  Future<Map> workerHeartbeat({
    required int attendanceId,
    required double lat,
    required double lng,
  }) async =>
      Map.from((await dio.post('/attendance/worker/heartbeat', data: {
        'attendance_id': attendanceId,
        'lat': lat,
        'lng': lng,
      })).data);

  // ───────── Worker AI Task Board ─────────
  Future<Map> workerTaskBoard({bool refresh = false}) async =>
      Map.from((await dio.get('/worker/task-board', queryParameters: {
        'refresh': refresh ? 'true' : 'false',
      })).data);

  Future<Map> workerTasksSync({String? sinceLastUpdated}) async =>
      Map.from((await dio.get('/worker/tasks/sync', queryParameters: {
        if (sinceLastUpdated != null) 'since_last_updated': sinceLastUpdated,
      })).data);

  Future<List> getProjects() async => (await dio.get('/projects')).data as List;
  Future<Map> createProject(Map d) async =>
      Map.from((await dio.post('/projects', data: d)).data);
  Future<Map> updateProject(int pid, Map d) async =>
      Map.from((await dio.put('/projects/$pid', data: d)).data);
  Future<Map> kpi() async => Map.from((await dio.get('/dashboard/kpi')).data);

  Future<Map> checkIn({
    required int wid,
    required int pid,
    required double lat,
    required double lng,
  }) async =>
      Map.from((await dio.post('/attendance/check-in', data: {
        'worker_id': wid,
        'project_id': pid,
        'lat': lat,
        'lng': lng,
      })).data);

  Future<Map> heartbeat({
    required int aid,
    required double lat,
    required double lng,
  }) async =>
      Map.from((await dio.post('/attendance/heartbeat', data: {
        'attendance_id': aid,
        'lat': lat,
        'lng': lng,
      })).data);

  Future<Map> checkOut({
    required int aid,
    required double lat,
    required double lng,
  }) async =>
      Map.from((await dio.post('/attendance/check-out', data: {
        'attendance_id': aid,
        'lat': lat,
        'lng': lng,
      })).data);

  Future<Map?> workerToday(int wid) async {
    try {
      return Map.from((await dio.get('/attendance/worker/$wid/today')).data);
    } catch (_) {
      return null;
    }
  }

  Future<List> aiMatch(String trade, int pid) async =>
      (await dio.post('/ai/tasks/match', queryParameters: {
        'required_trade': trade,
        'project_id': pid,
      })).data as List;

  Future<List> getTasks(int pid) async =>
      (await dio.get('/projects/$pid/tasks')).data as List;
  Future<Map> createTask(Map d) async =>
      Map.from((await dio.post('/tasks', data: d)).data);

  Future<List> getWorkers({int? pid}) async =>
      (await dio.get('/workers',
              queryParameters: pid != null ? {'project_id': pid} : null))
          .data as List;
  Future<Map> createWorker(Map d) async =>
      Map.from((await dio.post('/workers', data: d)).data);

  Future<Map> attendanceToday({int? pid}) async =>
      Map.from((await dio.get('/attendance/today',
              queryParameters: pid != null ? {'project_id': pid} : null))
          .data);

  Future<List> getIssues({int? pid, String? status}) async =>
      (await dio.get('/issues', queryParameters: {
        if (pid != null) 'project_id': pid,
        if (status != null) 'status': status,
      })).data as List;
  Future<Map> createIssue(Map d) async =>
      Map.from((await dio.post('/issues', data: d)).data);
  Future<Map> resolveIssue(int id) async =>
      Map.from((await dio.put('/issues/$id/resolve')).data);

  Future<Map> getSettings() async => Map.from((await dio.get('/settings')).data);
  Future<Map> updateSettings(Map d) async =>
      Map.from((await dio.put('/settings', data: d)).data);

  Future<List> getUsers() async => (await dio.get('/users')).data as List;
  Future<Map> inviteUser(Map d) async =>
      Map.from((await dio.post('/users', data: d)).data);
  Future<Map> updateUserRole(int id, String role) async =>
      Map.from((await dio.put('/users/$id/role', data: {'role': role})).data);

  Future<List> getReports(int pid) async =>
      (await dio.get('/projects/$pid/reports')).data as List;
  Future<Map> submitReport(Map d) async =>
      Map.from((await dio.post('/daily-reports', data: d)).data);

  Future<Map> reportSafety({
    required String t,
    required int w,
    required int p,
    required double lat,
    required double lng,
  }) async =>
      Map.from((await dio.post('/safety/report', queryParameters: {
        'incident_type': t,
        'worker_id': w,
        'project_id': p,
        'gps_lat': lat,
        'gps_lng': lng,
      })).data);
}
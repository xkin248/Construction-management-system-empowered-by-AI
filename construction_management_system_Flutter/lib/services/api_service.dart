import 'dart:io';
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

  /// Bearer header for requests that bypass Dio (e.g. Image.network loading the
  /// authenticated task completion photo). Empty when no token is set.
  Map<String, String> get authHeaders =>
      (_t?.isNotEmpty == true) ? {'Authorization': 'Bearer $_t'} : const {};

  /// Absolute URL of the task completion photo endpoint. The endpoint requires
  /// the Bearer token, so callers must pass [authHeaders] alongside.
  String taskCompletionPhotoUrl(int taskId) =>
      '$baseUrl$p/tasks/$taskId/completion-photo';

  void init({String? token, VoidCallback? onUnauthorized}) {
    _t = token;
    _out = onUnauthorized;
    if (_d != null) {
      // Already initialised — just refresh the token reference
      return;
    }
    _d = Dio(BaseOptions(
      baseUrl: baseUrl + p,
      // Use the central environment values.  The previous hard-coded 6/10 s
      // values ignored Env and timed out before a sleeping Render service had
      // a chance to wake up, which appeared in the UI as a network failure.
      connectTimeout: Duration(milliseconds: Env.connectTimeout),
      receiveTimeout: Duration(milliseconds: Env.receiveTimeout),
      contentType: Headers.jsonContentType,
      responseType: ResponseType.json,
      headers: {'Accept': 'application/json'},
    ));
    _d!.interceptors.add(LogInterceptor(
      requestBody: true,
      responseBody: true,
      // Request/response logs only in debug builds — release builds must not
      // spray payloads (which may carry tokens) into logcat.
      logPrint: (o) {
        if (kDebugMode) debugPrint('[API] $o');
      },
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
              // A rejected sign-in is an expected form validation result, not
              // an expired authenticated session. Treating it as a global
              // logout rebuilds LoginPage before it can show its inline error
              // and makes both fields appear to have been cleared.
              final isLoginRequest =
                  e.requestOptions.path.endsWith('/auth/login');
              m = isLoginRequest
                  ? 'Invalid credentials'
                  : 'Login session expired';

              // Only a protected request made with a saved token can expire a
              // real session. Login itself must stay on the current form so
              // the caller can retain the entered values and show feedback.
              if (!isLoginRequest && _t?.isNotEmpty == true) {
                _t = null;
                _out?.call();
              }
            } else if (c == 410) {
              m = d is Map
                  ? d['detail'] ?? 'Check-in was auto-cancelled'
                  : 'Check-in cancelled';
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
    List<String>? specialties,
    int? projectId,
  }) async {
    final r = await dio.post('/auth/register/worker', data: {
      'name': name.trim(),
      'email': email.trim().toLowerCase(),
      'password': password,
      if (phone != null) 'phone': phone,
      if (icNumber != null) 'ic_number': icNumber,
      if (trade != null) 'trade': trade,
      if (specialties != null) 'specialties': specialties,
      if (projectId != null) 'project_id': projectId,
      'role': 'worker',
    });
    return Map.from(r.data);
  }

  Future<Map> me() async => Map.from((await dio.get('/auth/me')).data);

  // ───────── FCM device token registration ─────────
  Future<bool> registerFcmToken({
    required int userId,
    required String userType,
    required String token,
  }) async {
    try {
      final r = await dio.post('/notifications/register-token', data: {
        'user_id': userId,
        'user_type': userType,
        'token': token,
      });
      final m = Map.from(r.data);
      return m['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  // ───────── Worker in-app notifications ─────────
  Future<List> getWorkerNotifications(int workerId,
      {bool unreadOnly = false}) async {
    final r =
        await dio.get('/notifications/worker/$workerId', queryParameters: {
      if (unreadOnly) 'unread_only': 'true',
    });
    return (r.data as List).toList();
  }

  Future<Map> workerUnreadCount(int workerId) async => Map.from(
      (await dio.get('/notifications/worker/$workerId/unread-count')).data);

  Future<Map> workerMarkAllRead(int workerId) async => Map.from(
      (await dio.put('/notifications/worker/$workerId/read-all')).data);

  // ───────── Worker Authenticated Attendance ─────────
  Future<Map> workerCheckIn({
    required int projectId,
    required double lat,
    required double lng,
    String? deviceInfo,
    String? deviceType,
    String? deviceId,
    String? photoBase64,
    String? photoMimeType,
  }) async =>
      Map.from((await dio.post('/attendance/worker/check-in', data: {
        'project_id': projectId,
        'lat': lat,
        'lng': lng,
        if (deviceInfo != null) 'device_info': deviceInfo,
        if (deviceType != null) 'device_type': deviceType,
        if (deviceId != null) 'device_id': deviceId,
        if (photoBase64 != null) 'photo_base64': photoBase64,
        if (photoMimeType != null) 'photo_mime_type': photoMimeType,
      }))
          .data);

  Future<Map> workerCheckOut({
    required double lat,
    required double lng,
    String? deviceInfo,
    String? deviceType,
    String? photoBase64,
    String? photoMimeType,
  }) async =>
      Map.from((await dio.post('/attendance/worker/check-out', data: {
        'lat': lat,
        'lng': lng,
        if (deviceInfo != null) 'device_info': deviceInfo,
        if (deviceType != null) 'device_type': deviceType,
        if (photoBase64 != null) 'photo_base64': photoBase64,
        if (photoMimeType != null) 'photo_mime_type': photoMimeType,
      }))
          .data);

  Future<Map> workerTodayAttendance() async =>
      Map.from((await dio.get('/attendance/worker/today')).data);

  // ───────── Supervisor Authenticated Attendance ─────────
  Future<Map> supervisorCheckIn({
    required int projectId,
    required double lat,
    required double lng,
    String? deviceInfo,
    String? deviceType,
    String? deviceId,
    String? photoBase64,
    String? photoMimeType,
  }) async =>
      Map.from((await dio.post('/attendance/supervisor/check-in', data: {
        'project_id': projectId,
        'lat': lat,
        'lng': lng,
        if (deviceInfo != null) 'device_info': deviceInfo,
        if (deviceType != null) 'device_type': deviceType,
        if (deviceId != null) 'device_id': deviceId,
        if (photoBase64 != null) 'photo_base64': photoBase64,
        if (photoMimeType != null) 'photo_mime_type': photoMimeType,
      }))
          .data);

  Future<Map> supervisorCheckOut({
    required double lat,
    required double lng,
    String? deviceInfo,
    String? deviceType,
    String? photoBase64,
    String? photoMimeType,
  }) async =>
      Map.from((await dio.post('/attendance/supervisor/check-out', data: {
        'lat': lat,
        'lng': lng,
        if (deviceInfo != null) 'device_info': deviceInfo,
        if (deviceType != null) 'device_type': deviceType,
        if (photoBase64 != null) 'photo_base64': photoBase64,
        if (photoMimeType != null) 'photo_mime_type': photoMimeType,
      }))
          .data);

  Future<Map> supervisorTodayAttendance() async =>
      Map.from((await dio.get('/attendance/supervisor/today')).data);

  Future<Map> workerHeartbeat({
    required int attendanceId,
    required double lat,
    required double lng,
  }) async =>
      Map.from((await dio.post('/attendance/worker/heartbeat', data: {
        'attendance_id': attendanceId,
        'lat': lat,
        'lng': lng,
      }))
          .data);

  // ───────── Worker AI Task Board ─────────
  Future<Map> workerTaskBoard({bool refresh = false}) async =>
      Map.from((await dio.get('/worker/task-board', queryParameters: {
        'refresh': refresh ? 'true' : 'false',
      }))
          .data);

  Future<Map> workerTasksSync({String? sinceLastUpdated}) async =>
      Map.from((await dio.get('/worker/tasks/sync', queryParameters: {
        if (sinceLastUpdated != null) 'since_last_updated': sinceLastUpdated,
      }))
          .data);

  // ───────── Daily common tasks (briefing / toolbox / housekeeping) ─────────

  /// The three jobs every site repeats daily. Reading this endpoint is also
  /// what creates today's rows on the server (lazy generation, no scheduler),
  /// so the worker always sees exactly three cards.
  Future<Map> commonTasksToday({int? projectId, String? workDate}) async =>
      Map.from((await dio.get('/common-tasks/today', queryParameters: {
        if (projectId != null) 'project_id': projectId,
        if (workDate != null) 'work_date': workDate,
      }))
          .data);

  /// Daily-record history of the three common tasks, newest date first.
  ///
  /// Read-only helper for the supervisor project detail tab: the same endpoint
  /// the worker app uses, only widened to a number of days.
  Future<List> commonTaskHistory({int? projectId, int days = 7}) async =>
      (await dio.get('/common-tasks', queryParameters: {
        if (projectId != null) 'project_id': projectId,
        'days': days,
      }))
          .data as List;

  /// Close one daily job with the mandatory site photo.
  ///
  /// The backend refuses the call without `photo_base64`, so the photo is a
  /// required argument here too — callers cannot forget the evidence.
  Future<Map> completeCommonTask(
    int instanceId, {
    required String photoBase64,
    String photoMimeType = 'image/jpeg',
  }) async =>
      Map.from((await dio.post('/common-tasks/$instanceId/complete', data: {
        'photo_base64': photoBase64,
        'photo_mime_type': photoMimeType,
      }))
          .data);

  /// Authenticated URL of a daily-job photo. The endpoint needs the Bearer
  /// token, so pair it with [authHeaders] (or use the Dio client instead).
  String commonTaskPhotoUrl(int instanceId) =>
      '$baseUrl$p/common-tasks/$instanceId/photo';

  // ───────── Toolbox: tools out / tools back ─────────

  /// Sign out one or more tools under a single shared photo of the tray.
  Future<Map> toolboxTake({
    required List<Map<String, dynamic>> items,
    required String photoBase64,
    String photoMimeType = 'image/jpeg',
    int? projectId,
  }) async =>
      Map.from((await dio.post('/toolbox/take', data: {
        'items': items,
        'photo_base64': photoBase64,
        'photo_mime_type': photoMimeType,
        if (projectId != null) 'project_id': projectId,
      }))
          .data);

  /// Bring one or more tools back under a single shared photo.
  Future<Map> toolboxReturn({
    required List<int> issueIds,
    required String photoBase64,
    String photoMimeType = 'image/jpeg',
  }) async =>
      Map.from((await dio.post('/toolbox/return', data: {
        'issue_ids': issueIds,
        'photo_base64': photoBase64,
        'photo_mime_type': photoMimeType,
      }))
          .data);

  /// Everything this worker has not brought back yet — the digital replacement
  /// for the paper toolbox register.
  Future<List> toolboxOutstanding() async =>
      (await dio.get('/toolbox/outstanding')).data as List;

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
      }))
          .data);

  Future<Map> heartbeat({
    required int aid,
    required double lat,
    required double lng,
  }) async =>
      Map.from((await dio.post('/attendance/heartbeat', data: {
        'attendance_id': aid,
        'lat': lat,
        'lng': lng,
      }))
          .data);

  Future<Map> checkOut({
    required int aid,
    required double lat,
    required double lng,
  }) async =>
      Map.from((await dio.post('/attendance/check-out', data: {
        'attendance_id': aid,
        'lat': lat,
        'lng': lng,
      }))
          .data);

  Future<Map?> workerToday(int wid) async {
    try {
      return Map.from((await dio.get('/attendance/worker/$wid/today')).data);
    } catch (_) {
      return null;
    }
  }

  Future<List> getTasks(int pid) async =>
      (await dio.get('/projects/$pid/tasks')).data as List;
  Future<List> getSupervisorTasks({int? pid}) async => (await dio.get('/tasks',
          queryParameters: pid == null ? null : {'project_id': pid}))
      .data as List;
  Future<Map> getTask(int taskId) async =>
      Map.from((await dio.get('/tasks/$taskId')).data);
  Future<Map> createTask(Map d) async =>
      Map.from((await dio.post('/tasks', data: d)).data);
  Future<Map> updateTask(int taskId, Map d) async =>
      Map.from((await dio.put('/tasks/$taskId', data: d)).data);

  /// Worker-only: close a task with the mandatory site photo.
  ///
  /// The backend rejects completion without photo evidence, so the photo is a
  /// required argument rather than an optional one — callers cannot forget it.
  /// [photoBase64] is the raw base64 body (no data URL prefix required).
  Future<Map> completeTaskWithPhoto(
    int taskId, {
    required String photoBase64,
    String? completionNote,
    String photoMimeType = 'image/jpeg',
  }) async =>
      Map.from((await dio.post('/tasks/$taskId/complete', data: {
        'photo_base64': photoBase64,
        'photo_mime_type': photoMimeType,
        if (completionNote != null && completionNote.trim().isNotEmpty)
          'completion_note': completionNote.trim(),
      }))
          .data);
  Future<Map> deleteTask(int taskId) async =>
      Map.from((await dio.delete('/tasks/$taskId')).data);
  Future<List> getTaskLogs(int taskId) async =>
      (await dio.get('/tasks/$taskId/logs')).data as List;

  /// Reopen a completed task (supervisor only).
  ///
  /// Deliberately not routed through [updateTask]: the backend rejects backward
  /// transitions on PUT, and a reopen is privileged and must carry a written
  /// reason so the audit trail can explain why a finished task went back on the
  /// board. [targetStatus] is 'in_progress' (default) or 'pending'.
  Future<Map> reopenTask(int taskId, String reason,
          {String targetStatus = 'in_progress'}) async =>
      Map.from((await dio.post('/tasks/$taskId/reopen',
              data: {'status': targetStatus, 'reason': reason}))
          .data);

  /// Supervisor-only evidence decision.  Completion is deliberately a second
  /// step: a worker submission is not counted as an approved task until this
  /// endpoint records the review.
  Future<Map> reviewTask(int taskId, String decision, {String? reason}) async =>
      Map.from((await dio.post('/tasks/$taskId/review', data: {
        'decision': decision,
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      }))
          .data);

  Future<Map> aiAutoAssign(int? projectId,
          {List<int>? taskIds,
          bool dryRun = false,
          bool sameProjectOnly = true}) async =>
      Map.from((await dio.post('/ai/tasks/auto-assign', data: {
        if (projectId != null) 'project_id': projectId,
        if (taskIds != null) 'task_ids': taskIds,
        'dry_run': dryRun,
        'same_project_only': sameProjectOnly,
        'top_k': 3,
      }))
          .data);

  /// Rank workers for a task's required skill level *before* the task exists
  /// (POST /ai/tasks/match).
  ///
  /// The backend registers this endpoint as POST only (`@router.post(
  /// "/ai/tasks/match")` in routers/ai_task.py); the previous GET produced a
  /// 4xx (405 locally, 404 on a backend build without the route) so the AI
  /// preview in the New Task sheet always failed. The parameters stay in the
  /// query string because the backend declares them as plain function
  /// arguments (required_trade, project_id), not as a request body.
  Future<List> aiTaskMatch(String requiredTrade, int projectId,
          {String? requiredSpecialty}) async =>
      (await dio.post('/ai/tasks/match', queryParameters: {
        'required_trade': requiredTrade,
        'project_id': projectId,
        if (requiredSpecialty != null) 'required_specialty': requiredSpecialty,
      }))
          .data as List;

  Future<Map> progressPrediction(int projectId) async => Map.from(
      (await dio.get('/ai/projects/$projectId/progress-prediction')).data);

  /// Which engine the AI layer is actually running on (model id, circuit
  /// state, last error). Surfaced on the dashboard so a degraded rule-only run
  /// is visible instead of being mistaken for a model verdict.
  Future<Map> aiStatus() async => Map.from((await dio.get('/ai/status')).data);

  Future<Map> getWorker(int wid) async =>
      Map.from((await dio.get('/workers/$wid')).data);

  Future<List> getWorkers({int? pid}) async => (await dio.get('/workers',
          queryParameters: pid != null ? {'project_id': pid} : null))
      .data as List;
  Future<Map> createWorker(Map d) async =>
      Map.from((await dio.post('/workers', data: d)).data);

  /// Updates an existing worker (name / trade level / phone / project).
  /// Backed by `PUT /workers/{worker_id}`; the registration e-mail and password
  /// are intentionally not editable here.
  Future<Map> updateWorker(int wid, Map d) async =>
      Map.from((await dio.put('/workers/$wid', data: d)).data);

  Future<Map> attendanceToday({int? pid}) async =>
      Map.from((await dio.get('/attendance/today',
              queryParameters: pid != null ? {'project_id': pid} : null))
          .data);

  /// Today's log of a single worker, including the selfie URLs and the GPS
  /// distance recorded at check-in / check-out.
  ///
  /// `/attendance/today` only reports a summary row, so the supervisor screens
  /// fetch this detail on demand to prove the on-site selfie and the fence
  /// distance (spec PART B8). Returns `null` when the worker has no log today.
  Future<Map?> attendanceWorkerToday(int workerId) async {
    final resp = await dio.get('/attendance/worker/$workerId/today');
    final data = resp.data;
    if (data is! Map) return null;
    return Map<String, dynamic>.from(data);
  }

  Future<List> getIssues({int? pid, String? status}) async =>
      (await dio.get('/issues', queryParameters: {
        if (pid != null) 'project_id': pid,
        if (status != null) 'status': status,
      }))
          .data as List;
  Future<Map> createIssue(Map d) async =>
      Map.from((await dio.post('/issues', data: d)).data);
  Future<Map> resolveIssue(int id) async =>
      Map.from((await dio.put('/issues/$id/resolve')).data);

  Future<Map> getSettings() async =>
      Map.from((await dio.get('/settings')).data);
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
      }))
          .data);

  // ───────── Weekly Attendance Stats (Dashboard) ─────────
  Future<Map> getWeeklyAttendanceStats() async =>
      Map.from((await dio.get('/attendance/weekly-stats')).data);

  // ───────── File Management ─────────
  Future<List> getFiles({int? pid, String? category}) async {
    final params = <String, dynamic>{};
    if (pid != null && pid > 0) params['project_id'] = pid;
    if (category != null && category != 'all') {
      params['file_category'] = category;
    }
    return (await dio.get('/files', queryParameters: params)).data as List;
  }

  /// Upload from in-memory bytes. Required on Flutter Web (and safe on mobile):
  /// file_picker's `path` is null on web and its cache file can be deleted on
  /// Android, so we always send bytes instead of re-reading the file.
  Future<Map> uploadFileBytes(Uint8List bytes, String fileName,
      {int? pid,
      String? category,
      void Function(int sent, int total)? onProgress}) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: fileName),
      if (pid != null && pid > 0) 'project_id': pid,
      if (category != null && category != 'all') 'file_category': category,
    });
    return Map.from((await dio.post('/files/upload',
            data: formData, onSendProgress: onProgress))
        .data);
  }

  Future<Map> uploadFile(File file, {int? pid, String? category}) async {
    final fileName = file.path.split(RegExp(r'[/\\]')).last;
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(file.path, filename: fileName),
      if (pid != null && pid > 0) 'project_id': pid,
      if (category != null && category != 'all') 'file_category': category,
    });
    return Map.from((await dio.post('/files/upload', data: formData)).data);
  }

  Future<void> deleteFile(int fileId) async {
    await dio.delete('/files/$fileId');
  }

  /// Authenticated download URL. Only usable by clients that can attach the
  /// `Authorization` header (Dio on mobile/desktop). Web navigation and
  /// `Image.network` must use [fetchDownloadLink] instead, the bare URL here
  /// is rejected with 401 by the backend.
  String downloadUrl(int fileId) => '$baseUrl/api/files/$fileId/download';

  /// Cache of signed links: a link is valid for `ttlSeconds`, we reuse it until
  /// 60s before expiry so a grid of previews triggers one request per file
  /// instead of one per rebuild.
  final Map<int, _CachedDownloadLink> _downloadLinkCache = {};

  /// Ask the backend for a short-lived, self-authenticating download URL.
  ///
  /// This is the fix for the download 401: the returned URL embeds a signed,
  /// file-scoped token, so a plain `GET` without headers succeeds — which is all
  /// Flutter Web navigation and `Image.network` can do. Minting the link itself
  /// still requires the normal Bearer token (sent by [dio]).
  Future<String> fetchDownloadLink(int fileId, {int ttlSeconds = 300}) async {
    final cached = _downloadLinkCache[fileId];
    if (cached != null && cached.isFresh) return cached.url;

    final resp = await dio.get('/files/$fileId/download-link',
        queryParameters: {'ttl': ttlSeconds});
    final data = Map<String, dynamic>.from(resp.data as Map);
    final url = (data['download_url'] ?? data['path'])?.toString();
    if (url == null || url.isEmpty) {
      throw StateError('Backend did not return a download link');
    }
    _downloadLinkCache[fileId] = _CachedDownloadLink(
      url,
      DateTime.now()
          .add(Duration(seconds: ttlSeconds > 90 ? ttlSeconds - 60 : 30)),
    );
    return url;
  }

  /// Drop a cached link, e.g. after the file was replaced or deleted.
  void invalidateDownloadLink(int fileId) => _downloadLinkCache.remove(fileId);

  // ───────── Notifications ─────────
  Future<List> getNotifications() async =>
      (await dio.get('/notifications')).data as List;

  Future<void> markNotificationRead(int id) async =>
      await dio.put('/notifications/$id/read');

  Future<void> markAllNotificationsRead() async =>
      await dio.put('/notifications/read-all');

  Future<int> getUnreadCount() async {
    final resp = await dio.get('/notifications/unread-count');
    return resp.data is int ? resp.data : (resp.data['count'] ?? 0) as int;
  }

  Future<Map> getNotificationSettings() async => Map<String, dynamic>.from(
      (await dio.get('/notifications/settings')).data as Map);

  Future<void> updateNotificationSettings(Map data) async =>
      await dio.put('/notifications/settings', data: data);

  // ───────── Attendance site photos (selfie evidence) ─────────
  /// Downloads an attendance selfie through the authenticated Dio client.
  ///
  /// The backend only exposes a relative URL (`/attendance/photos/...`) that
  /// demands the bearer header, so `Image.network` cannot load it directly.
  /// Fetching the bytes here also keeps the picture visible on Web, where
  /// custom headers on image requests are impossible.
  Future<Uint8List> fetchAttendancePhoto(String relativeUrl) async {
    final path =
        relativeUrl.startsWith('/') ? relativeUrl.substring(1) : relativeUrl;
    final resp = await dio.get(
      // Dio's base URL is `.../api` (without a trailing slash).  Supplying a
      // relative path would concatenate it as `.../apiattendance/...` on
      // Android, so keep the leading slash for a proper `/api/attendance/...`
      // request.
      '/$path',
      options: Options(responseType: ResponseType.bytes),
    );
    final data = resp.data;
    if (data is Uint8List) return data;
    return Uint8List.fromList(List<int>.from(data as List));
  }
}

/// A signed download URL plus the moment it stops being reusable.
class _CachedDownloadLink {
  _CachedDownloadLink(this.url, this.expiresAt);

  final String url;
  final DateTime expiresAt;

  bool get isFresh => expiresAt.isAfter(DateTime.now());
}

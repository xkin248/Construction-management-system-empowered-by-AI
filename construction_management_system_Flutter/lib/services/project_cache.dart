import 'api_service.dart';

/// In-memory cache for the project list with a configurable TTL.
///
/// All pages that need a project list (Tasks, Attendance, Files,
/// Notifications, Dashboard, TaskForm, WorkerDashboard, Projects)
/// should call [ProjectCache.get] instead of calling
/// `ApiService().getProjects()` directly.
///
/// Call [invalidate] whenever a project is created, updated, or deleted
/// so the next [get] fetches fresh data.
class ProjectCache {
  ProjectCache._();

  static List? _data;
  static DateTime? _fetchedAt;

  /// How long cached data is considered fresh.
  static const _ttl = Duration(minutes: 2);

  /// Returns the cached project list, re-fetching if the cache is stale or
  /// empty.
  ///
  /// Pass [forceRefresh] = true to bypass the TTL and always fetch fresh data.
  static Future<List> get(ApiService api, {bool forceRefresh = false}) async {
    final stale = _fetchedAt == null ||
        DateTime.now().difference(_fetchedAt!) > _ttl;
    if (!forceRefresh && !stale && _data != null) {
      return _data!;
    }
    _data = await api.getProjects();
    _fetchedAt = DateTime.now();
    return _data!;
  }

  /// Invalidates the cache so the next [get] call fetches fresh data.
  /// Call this after any create / update / delete project operation.
  static void invalidate() {
    _data = null;
    _fetchedAt = null;
  }
}

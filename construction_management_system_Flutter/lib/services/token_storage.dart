import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Wraps flutter_secure_storage for sensitive values (JWT token)
/// and keeps SharedPreferences for non-sensitive cached role data.
///
/// Use [TokenStorage] everywhere instead of reading/writing the token
/// directly via SharedPreferences.
class TokenStorage {
  TokenStorage._();

  static const _store = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  // ── Keys ──────────────────────────────────────────────────────────────────
  static const _kToken      = 'auth_token';
  static const _kUserType   = 'user_type';
  static const _kUserRole   = 'user_role';
  static const _kWorkerId   = 'worker_id';
  static const _kSupervisor = 'supervisor_id';
  static const _kProject    = 'project_id';

  // ── JWT token (secure) ────────────────────────────────────────────────────

  static Future<String?> getToken() => _store.read(key: _kToken);

  static Future<void> saveToken(String token) =>
      _store.write(key: _kToken, value: token);

  static Future<void> deleteToken() => _store.delete(key: _kToken);

  // ── Non-sensitive role data (SharedPreferences — fast sync read) ──────────

  static Future<SharedPreferences> get _sp => SharedPreferences.getInstance();

  static Future<String?> getUserType() async =>
      (await _sp).getString(_kUserType);

  static Future<String?> getUserRole() async =>
      (await _sp).getString(_kUserRole);

  static Future<int?> getWorkerId() async =>
      (await _sp).getInt(_kWorkerId);

  static Future<int?> getSupervisorId() async =>
      (await _sp).getInt(_kSupervisor);

  static Future<int?> getProjectId() async =>
      (await _sp).getInt(_kProject);

  /// Persists all user metadata received from the login response.
  static Future<void> saveUserMeta({
    required String userType,
    required String role,
    int? workerId,
    int? supervisorId,
    int? projectId,
  }) async {
    final sp = await _sp;
    await sp.setString(_kUserType, userType);
    await sp.setString(_kUserRole, role);
    if (workerId     != null) await sp.setInt(_kWorkerId,   workerId);
    if (supervisorId != null) await sp.setInt(_kSupervisor, supervisorId);
    if (projectId    != null) await sp.setInt(_kProject,    projectId);
  }

  /// Clears everything — call on logout or 401.
  static Future<void> clearAll() async {
    await _store.deleteAll();
    final sp = await _sp;
    await sp.clear();
  }
}

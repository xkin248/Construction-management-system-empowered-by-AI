import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Wraps flutter_secure_storage for sensitive values (JWT token)
/// and keeps SharedPreferences for non-sensitive cached role data.
///
/// On web there is no Keystore/Keychain, so the JWT falls back to
/// SharedPreferences (browser localStorage). Android / iOS / desktop keep the
/// encrypted [FlutterSecureStorage] implementation unchanged.
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

  // ── JWT token (secure on mobile/desktop, SharedPreferences on web) ─────────

  static Future<String?> getToken() async {
    if (kIsWeb) return (await _sp).getString(_kToken);
    return _store.read(key: _kToken);
  }

  static Future<void> saveToken(String token) async {
    if (kIsWeb) {
      await (await _sp).setString(_kToken, token);
      return;
    }
    await _store.write(key: _kToken, value: token);
  }

  static Future<void> deleteToken() async {
    if (kIsWeb) {
      await (await _sp).remove(_kToken);
      return;
    }
    await _store.delete(key: _kToken);
  }

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
    // Secure storage is not available on web (and may throw there), so only
    // touch it on platforms that actually back it with a Keystore/Keychain.
    if (!kIsWeb) {
      await _store.deleteAll();
    }
    final sp = await _sp;
    // Also removes the web fallback copy of the token.
    await sp.clear();
  }
}

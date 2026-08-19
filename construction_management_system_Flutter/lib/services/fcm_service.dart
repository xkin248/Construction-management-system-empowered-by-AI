import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import 'api_service.dart';

/// FCM push notification service (frontend).
///
/// Design choice (per task): keep the dependency set minimal — NO
/// flutter_local_notifications. Push payloads are plain FCM notification
/// messages:
///   * app in background/terminated → Android system tray handles display
///     automatically (FCM default behavior, no code needed);
///   * app in foreground → show a SnackBar via [scaffoldMessengerKey].
class FcmService {
  static bool _ready = false;

  /// Initialize Firebase + FCM for the current login session.
  ///
  /// Safe to call repeatedly; only acts once per process. Never throws:
  /// FCM absence must not block the app.
  static Future<void> setup() async {
    if (_ready) return;
    try {
      await Firebase.initializeApp();
      final fcm = FirebaseMessaging.instance;
      await fcm.requestPermission(alert: true, badge: true, sound: true);

      // Register the current token with the backend, then keep it fresh.
      await registerTokenToBackend();
      fcm.onTokenRefresh.listen((token) {
        unawaited(registerTokenToBackend());
      });

      // Foreground messages → in-app SnackBar (system tray handles background).
      FirebaseMessaging.onMessage.listen((msg) {
        final n = msg.notification;
        if (n == null) return;
        scaffoldMessengerKey.currentState?.showSnackBar(SnackBar(
          content: Text('${n.title ?? ''}\n${n.body ?? ''}'.trim()),
          backgroundColor: AppColors.sidebarBg,
          behavior: SnackBarBehavior.floating,
        ));
      });

      _ready = true;
      debugPrint('[FCM] setup complete');
    } catch (e) {
      debugPrint('[FCM] setup skipped: $e');
    }
  }

  /// Read the login identity from SharedPreferences and POST the token to
  /// `/api/notifications/register-token`. No-op when logged out or when FCM
  /// is unavailable.
  static Future<void> registerTokenToBackend() async {
    try {
      final fcm = FirebaseMessaging.instance;
      final token = await fcm.getToken();
      if (token == null || token.isEmpty) return;

      final sp = await SharedPreferences.getInstance();
      final authToken = sp.getString('token');
      if (authToken == null || authToken.isEmpty) return; // logged out

      final userType = (sp.getString('user_type') ?? '').toLowerCase();
      final int? userId = userType == 'worker'
          ? sp.getInt('worker_id')
          : sp.getInt('supervisor_id');
      if (userId == null) return;

      ApiService().ut(authToken);
      await ApiService().registerFcmToken(
        userId: userId,
        userType: userType == 'worker' ? 'worker' : 'supervisor',
        token: token,
      );
    } catch (e) {
      debugPrint('[FCM] registerToken skipped: $e');
    }
  }
}

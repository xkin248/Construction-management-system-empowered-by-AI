import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Sends a local notification asking the user to enable GPS,
/// instead of jumping straight to the system location settings page.
class GpsNotificationService {
  GpsNotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  /// Must be called once from main() before runApp.
  static Future<void> init() async {
    if (_initialized || kIsWeb) return;
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await _plugin.initialize(settings);
    _initialized = true;
  }

  /// Posts a "please enable GPS" notification. Does NOT open system settings.
  static Future<void> requestEnable() async {
    if (kIsWeb) return;
    if (!_initialized) await init();

    if (!kIsWeb) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final granted = await android?.requestNotificationsPermission() ?? true;
      if (granted == false) return;
    }

    const androidDetails = AndroidNotificationDetails(
      'gps_request',
      'GPS Request',
      channelDescription: 'Requests permission to enable GPS for attendance check-in',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.service,
      visibility: NotificationVisibility.public,
    );
    const details = NotificationDetails(android: androidDetails, iOS: DarwinNotificationDetails());

    await _plugin.show(
      1001,
      'Enable GPS Location',
      'Please turn on your GPS / location services to check in.',
      details,
      payload: 'gps_request',
    );
  }
}

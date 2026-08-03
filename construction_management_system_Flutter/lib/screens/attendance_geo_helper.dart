import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Platform-safe wrapper for GPS location.
/// Returns null on web or if permission is denied.
class GeoHelper {
  static Future<Map<String, double>?> getCurrentPosition() async {
    if (kIsWeb) return null;

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return null;
    }
    if (permission == LocationPermission.deniedForever) return null;

    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
    return {'lat': pos.latitude, 'lng': pos.longitude};
  }
}

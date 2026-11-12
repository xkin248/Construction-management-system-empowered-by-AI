class Env {
  // ✅ API Base URL — injected via --dart-define=BASE_URL=... at build time
  // For local Android emulator: http://10.0.2.2:8000
  // For real device on same WiFi: http://YOUR_PC_IP:8000
  // For production: https://your-backend.onrender.com
  static const String baseUrl = String.fromEnvironment(
    'BASE_URL',
    defaultValue: 'https://construction-management-system-empowered.onrender.com',
  );

  static const String apiVersion = '/api/v1';
  // Render's free instance can take tens of seconds to wake after it has been
  // idle.  Keep the web/mobile client connected long enough for that first
  // request instead of showing a false "no internet" error after six seconds.
  static const int connectTimeout = 30000;
  static const int receiveTimeout = 60000;

  // Locked theme colors — do not modify
  static const int primaryColor = 0xFF1976D2;
  static const int accentColor = 0xFFFF9800;
}
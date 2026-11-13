import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'theme/app_theme.dart';
import 'services/api_service.dart';
import 'services/token_storage.dart';
import 'screens/login_page.dart';
import 'screens/home_shell.dart';
import 'screens/worker_home_shell.dart';
import 'services/app_settings.dart';
import 'services/gps_notification_service.dart';
import 'theme/text_scale.dart';
import 'package:flutter/foundation.dart';

void main() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    FlutterError.onError = (FlutterErrorDetails details) {
      if (kDebugMode) {
        debugPrint('[FlutterError] ${details.exceptionAsString()}');
      }
      if (kDebugMode) {
        debugPrint('[FlutterError] ${details.stack}');
      }
      // Don't crash — log silently
    };
    runApp(const MyApp());
  }, (error, stack) {
    if (kDebugMode) {
      debugPrint('[ZoneError] $error');
    }
    if (kDebugMode) {
      debugPrint('[ZoneStack] $stack');
    }
    // Show error app so user can see what went wrong
    runApp(ErrorApp(error: error.toString()));
  });
}

/// Fallback app shown if something crashes before the main UI loads
class ErrorApp extends StatelessWidget {
  final String error;
  const ErrorApp({super.key, required this.error});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: AppColors.darkBg,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, color: AppColors.red, size: 56),
                const SizedBox(height: 16),
                const Text(
                  'BuildSmart — Startup Error',
                  style: TextStyle(
                      color: AppColors.onAccent,
                      fontSize: 18,
                      fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.darkSurface,
                    borderRadius: AppRadius.rMd,
                  ),
                  child: SelectableText(
                    error,
                    style: TextStyle(
                        color: AppColors.red,
                        fontSize: 12,
                        fontFamily: 'monospace'),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Please screenshot this and send to the developer.',
                  style:
                      TextStyle(color: AppColors.darkTextMuted, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                // Recovery exit: re-run the full app so SplashGate re-runs the
                // startup flow (login check, API init, FCM) from scratch.
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton(
                    onPressed: () => runApp(const MyApp()),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: AppColors.onAccent,
                      shape:
                          RoundedRectangleBorder(borderRadius: AppRadius.rMd),
                    ),
                    child: const Text(
                      'Try Again',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => runApp(const MyApp()),
                  style: TextButton.styleFrom(
                      foregroundColor: AppColors.darkTextMuted),
                  child: const Text('Retry',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Load persisted language/theme before the first frame.
    AppSettings.init().then((_) {
      if (mounted) setState(() {});
    });
    // Rebuild the MaterialApp when language / theme mode changes so the
    // locale + themeMode + dictionary all update instantly.
    AppSettings.lang.addListener(_onSettingsChanged);
    AppSettings.themeMode.addListener(_onSettingsChanged);
    // Local notifications (GPS request) setup. Never blocks startup.
    GpsNotificationService.init();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    AppSettings.lang.removeListener(_onSettingsChanged);
    AppSettings.themeMode.removeListener(_onSettingsChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    final dark = _systemIsDark();
    AppSettings.onSystemBrightnessChanged(dark);
    if (mounted) setState(() {});
  }

  bool _systemIsDark() =>
      WidgetsBinding.instance.platformDispatcher.platformBrightness ==
      Brightness.dark;

  @override
  Widget build(BuildContext context) {
    final dark = _systemIsDark();
    // Keep system-driven theme in sync with the platform brightness.
    if (AppSettings.themeMode.value == 'system') {
      AppColors.darkMode.value = dark;
    }
    return MaterialApp(
      title: 'BuildSmart Construction Management',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: scaffoldMessengerKey,
      // Keep Material/Cupertino widgets in sync with the app dictionary for
      // every language selectable in AppSettings.
      locale: Locale(AppSettings.lang.value),
      supportedLocales: const [Locale('en'), Locale('zh'), Locale('ms')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: buildAppTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: AppSettings.themeMode.value == 'dark'
          ? ThemeMode.dark
          : AppSettings.themeMode.value == 'light'
              ? ThemeMode.light
              : ThemeMode.system,
      // System font scaling is clamped for the whole app: dense site rows
      // must not clip their labels when the OS font size is pushed way up.
      builder: (context, child) =>
          AppTextScaler(child: child ?? const SizedBox.shrink()),
      // Root pages listen to AppColors.darkMode themselves and rebuild in
      // place, so the Navigator subtree must NOT be keyed here (that would
      // reset the route stack on every theme flip).
      home: const SplashGate(),
    );
  }
}

// ========== Checks login state at startup ==========
class SplashGate extends StatefulWidget {
  const SplashGate({super.key});
  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  bool _isRedirectingToLogin = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    // Restore the previous authenticated session if one was securely saved.
    // Theme, language, and notification preferences remain separate from
    // authentication and therefore survive both restart and sign-out.
    String? storedToken;
    String? cachedUserType;
    String? cachedRole;
    try {
      storedToken = await TokenStorage.getToken();
      cachedUserType = await TokenStorage.getUserType();
      cachedRole = await TokenStorage.getUserRole();
    } catch (e, st) {
      if (kDebugMode) debugPrint('[Boot] session restore failed: $e\n$st');
    }
    final token = storedToken?.trim();
    final hasStoredToken = token?.isNotEmpty == true;

    // ── 2. Initialise the API client — UNCONDITIONAL ────────────────────────
    // ApiService is a singleton used by every screen; it must be initialised
    // even when no token is available (null token = anonymous), otherwise
    // later calls run against an unconfigured client and crash.
    try {
      ApiService().init(
        token: hasStoredToken ? token : null,
        onUnauthorized: () => unawaited(_handleUnauthorized()),
      );
    } catch (e, st) {
      if (kDebugMode) debugPrint('[Boot] ApiService.init failed: $e\n$st');
    }

    // ── 3. FCM push setup ───────────────────────────────────────────────────
    // Do not initialise FCM during cold start.  On some site networks the
    // Google Play service call can stall Android's main thread and trigger an
    // ANR even though the login page has already rendered.  Notification
    // enrolment belongs to an explicit, authenticated opt-in flow; the core
    // attendance and task workflows must always be available first.

    if (!mounted) return;

    // Choose the login page only when there is no valid local session.
    if (!hasStoredToken) {
      _openLogin();
      return;
    }

    // A normal login always caches the account type. The JWT fallback also
    // supports a token created before that metadata was introduced; it only
    // selects the initial shell, while the backend still authorizes every API
    // request.
    final userType = (cachedUserType?.trim().isNotEmpty ?? false)
        ? cachedUserType!.trim()
        : _userTypeFromToken(token!);
    final role = cachedRole?.trim();
    if (userType == null && (role == null || role.isEmpty)) {
      // We cannot safely choose a shell for an unreadable legacy token.
      await _clearLocalSession();
      if (mounted) _openLogin();
      return;
    }

    final isWorker = userType?.toLowerCase() == 'worker' ||
        role?.toLowerCase() == 'worker';
    _openShell(isWorker: isWorker);

    // Verify the restored token without delaying the UI. A temporary outage
    // (or a waking free backend) leaves the cached session usable; a real 401
    // is handled by the global callback and returns to LoginPage.
    unawaited(_refreshCachedIdentity());
  }

  Future<void> _handleUnauthorized() async {
    if (_isRedirectingToLogin) return;
    _isRedirectingToLogin = true;
    try {
      await TokenStorage.clearAuth();
    } catch (e, st) {
      if (kDebugMode) debugPrint('[Auth] failed to clear session: $e\n$st');
    } finally {
      ApiService().ct();
      navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (_) => false,
      );
      _isRedirectingToLogin = false;
    }
  }

  Future<void> _clearLocalSession() async {
    try {
      await TokenStorage.clearAuth();
    } catch (e, st) {
      if (kDebugMode) debugPrint('[Boot] failed to clear session: $e\n$st');
    }
    ApiService().ct();
  }

  void _openLogin() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
  }

  void _openShell({required bool isWorker}) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => isWorker ? const WorkerHomeShell() : const HomeShell(),
      ),
    );
  }

  Future<void> _refreshCachedIdentity() async {
    try {
      final user = await ApiService().me();
      final userType = user['user_type']?.toString().trim();
      if (userType == null || userType.isEmpty) return;

      await TokenStorage.saveUserMeta(
        userType: userType,
        role: user['role']?.toString() ?? '',
        workerId: _asInt(user['worker_id']),
        supervisorId: _asInt(user['supervisor_id']),
        projectId: _asInt(user['project_id']),
      );
    } catch (_) {
      // Network failures are non-destructive. A 401 triggers
      // _handleUnauthorized through ApiService's interceptor.
    }
  }

  int? _asInt(Object? value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }

  String? _userTypeFromToken(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final payload = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      final decoded = jsonDecode(payload);
      if (decoded is! Map) return null;
      final userType = decoded['user_type']?.toString().trim();
      return userType == null || userType.isEmpty ? null : userType;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext c) => Container(
        color: AppColors.sidebarBg,
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                  color: AppColors.accent, borderRadius: AppRadius.rMd),
              child: const Center(
                  child: Text('B',
                      style: TextStyle(
                          color: AppColors.onAccent,
                          fontSize: 28,
                          fontWeight: FontWeight.w800))),
            ),
            const SizedBox(height: 16),
            const Text('BuildSmart',
                style: TextStyle(
                    color: AppColors.onAccent,
                    fontSize: 20,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            const Text('AI Construction System',
                style: TextStyle(
                    color: AppColors.darkTextMuted,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3)),
            const SizedBox(height: 24),
            SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2.4, color: AppColors.accent)),
          ]),
        ),
      );
}

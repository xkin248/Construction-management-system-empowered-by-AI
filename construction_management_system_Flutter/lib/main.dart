import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'theme/app_theme.dart';
import 'services/api_service.dart';
import 'services/fcm_service.dart';
import 'services/token_storage.dart';
import 'screens/login_page.dart';
import 'screens/home_shell.dart';
import 'screens/worker_home_shell.dart';
import 'services/app_settings.dart';
import 'services/gps_notification_service.dart';

void main() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    FlutterError.onError = (FlutterErrorDetails details) {
      debugPrint('[FlutterError] ${details.exceptionAsString()}');
      debugPrint('[FlutterError] ${details.stack}');
      // Don't crash — log silently
    };
    runApp(const MyApp());
  }, (error, stack) {
    debugPrint('[ZoneError] $error');
    debugPrint('[ZoneStack] $stack');
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
                  style: TextStyle(color: AppColors.onAccent, fontSize: 18, fontWeight: FontWeight.bold),
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
                    style: TextStyle(color: AppColors.red, fontSize: 12, fontFamily: 'monospace'),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Please screenshot this and send to the developer.',
                  style: TextStyle(color: AppColors.darkTextMuted, fontSize: 12),
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
                      shape: RoundedRectangleBorder(borderRadius: AppRadius.rMd),
                    ),
                    child: const Text(
                      'Try Again',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => runApp(const MyApp()),
                  style: TextButton.styleFrom(foregroundColor: AppColors.darkTextMuted),
                  child: const Text('Retry',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
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
      WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;

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
      // EN / BM localization support (Material widgets + app dictionary).
      locale: Locale(AppSettings.lang.value == 'ms' ? 'ms' : 'en'),
      supportedLocales: const [Locale('en'), Locale('ms')],
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
  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    // ── 1. Read persisted auth state ────────────────────────────────────────
    // Each read is guarded on its own: storage can be unavailable on some
    // platforms (e.g. web), and one failing read must never abort the startup
    // sequence nor leave a stale/partial value behind.
    String? token;
    String? userType;
    String? userRole;

    try {
      token = await TokenStorage.getToken();
    } catch (e, st) {
      debugPrint('[Boot] getToken failed: $e\n$st');
    }
    try {
      userType = await TokenStorage.getUserType();
    } catch (e, st) {
      debugPrint('[Boot] getUserType failed: $e\n$st');
    }
    try {
      userRole = await TokenStorage.getUserRole();
    } catch (e, st) {
      debugPrint('[Boot] getUserRole failed: $e\n$st');
    }

    // ── 2. Initialise the API client — UNCONDITIONAL ────────────────────────
    // ApiService is a singleton used by every screen; it must be initialised
    // even when the stored token could not be read (null token = anonymous),
    // otherwise later calls run against an unconfigured client and crash.
    try {
      ApiService().init(
        token: token,
        onUnauthorized: () async {
          await TokenStorage.clearAll();
          navigatorKey.currentState?.pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const LoginPage()), (_) => false);
        },
      );
    } catch (e, st) {
      debugPrint('[Boot] ApiService.init failed: $e\n$st');
    }

    // ── 3. FCM push setup ───────────────────────────────────────────────────
    // Firebase init + notification permission + token registration. Never
    // blocks startup (failures are swallowed inside, and re-guarded here).
    try {
      await FcmService.setup();
    } catch (e, st) {
      debugPrint('[Boot] FcmService.setup failed: $e\n$st');
    }

    if (!mounted) return;

    // ── 4. Route to the correct shell ───────────────────────────────────────
    final hasToken = token != null && token.isNotEmpty;
    final isWorker = userType == 'worker' || userRole == 'worker';
    final Widget home =
        hasToken ? (isWorker ? const WorkerHomeShell() : const HomeShell()) : const LoginPage();

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => home),
    );
  }

  @override
  Widget build(BuildContext c) => Container(
        color: AppColors.sidebarBg,
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(color: AppColors.accent, borderRadius: AppRadius.rMd),
              child: const Center(child: Text('B', style: TextStyle(color: AppColors.onAccent, fontSize: 28, fontWeight: FontWeight.w800))),
            ),
            const SizedBox(height: 16),
            const Text('BuildSmart', style: TextStyle(color: AppColors.onAccent, fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            const Text('AI Construction System',
                style: TextStyle(color: AppColors.darkTextMuted, fontSize: 12.5, fontWeight: FontWeight.w600, letterSpacing: 0.3)),
            const SizedBox(height: 24),
            SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.accent)),
          ]),
        ),
      );
}

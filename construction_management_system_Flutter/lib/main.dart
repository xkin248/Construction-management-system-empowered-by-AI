import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme/app_theme.dart';
import 'services/api_service.dart';
import 'services/fcm_service.dart';
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
        backgroundColor: const Color(0xFF10141C),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Color(0xFFEF4444), size: 56),
                const SizedBox(height: 16),
                const Text(
                  'BuildSmart — Startup Error',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1F2634),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    error,
                    style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12, fontFamily: 'monospace'),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Please screenshot this and send to the developer.',
                  style: TextStyle(color: Color(0xFF757E90), fontSize: 12),
                  textAlign: TextAlign.center,
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
    try {
      final sp = await SharedPreferences.getInstance();
      final token = sp.getString('token');
      final userType = sp.getString('user_type');
      final userRole = sp.getString('user_role');
      ApiService().init(
        token: token,
        onUnauthorized: () async {
          final sp2 = await SharedPreferences.getInstance();
          await sp2.clear();
          navigatorKey.currentState?.pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginPage()), (_) => false);
        },
      );
      // FCM push setup: Firebase init + notification permission + token
      // registration. Never blocks startup (failures are swallowed inside).
      await FcmService.setup();
      if (!mounted) return;

      Widget home;
      final hasToken = token != null && token.isNotEmpty;
      final isWorker = userType == 'worker' || userRole == 'worker';
      if (hasToken) {
        home = isWorker ? const WorkerHomeShell() : const HomeShell();
      } else {
        home = const LoginPage();
      }

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => home),
      );
    } catch (e, st) {
      debugPrint('[Boot Error] $e\n$st');
      // Always fallback to login — never crash
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginPage()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext c) => Container(
        color: AppColors.sidebarBg,
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(16)),
              child: const Center(child: Text('B', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800))),
            ),
            const SizedBox(height: 16),
            const Text('BuildSmart', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            const Text('AI Construction System',
                style: TextStyle(color: Color(0xFF757E90), fontSize: 11.5, fontWeight: FontWeight.w600, letterSpacing: 0.3)),
            const SizedBox(height: 22),
            SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.accent)),
          ]),
        ),
      );
}

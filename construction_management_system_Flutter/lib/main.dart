import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme/app_theme.dart';
import 'services/api_service.dart';
import 'screens/login_page.dart';
import 'screens/home_shell.dart';
import 'screens/worker_home_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BuildSmart Construction Management',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: scaffoldMessengerKey,
      theme: buildAppTheme(),
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
            const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.accent)),
          ]),
        ),
      );
}

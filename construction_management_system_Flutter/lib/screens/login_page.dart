import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import 'home_shell.dart';
import 'worker_home_shell.dart';
import 'worker_register_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with SingleTickerProviderStateMixin {
  final _email = TextEditingController(text: 'manager@buildsmart.my');
  final _pwd = TextEditingController();
  bool ld = false, obscure = true;
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
  late final Animation<double> _fade = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
  late final Animation<Offset> _slide = Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero)
      .animate(CurvedAnimation(parent: _anim, curve: Curves.easeOut));

  @override
  void initState() {
    super.initState();
    _anim.forward();
  }

  Future<void> _login() async {
    if (_email.text.trim().isEmpty || _pwd.text.isEmpty) {
      toast('Please enter your email and password');
      return;
    }
    setState(() => ld = true);
    try {
      final r = await ApiService().login(a: _email.text, p: _pwd.text);
      final sp = await SharedPreferences.getInstance();
      await sp.setString('token', r['access_token']);

      final userType = r['user_type'] ?? 'supervisor';
      final user = Map<String, dynamic>.from(r['user'] ?? {});
      final role = user['role']?.toString().toLowerCase() ?? '';

      await sp.setString('user_type', userType);
      await sp.setString('user_role', role);
      if (user['worker_id'] != null) {
        await sp.setInt('worker_id', user['worker_id'] as int);
      }
      if (user['supervisor_id'] != null) {
        await sp.setInt('supervisor_id', user['supervisor_id'] as int);
      }
      if (user['project_id'] != null) {
        await sp.setInt('project_id', user['project_id'] as int);
      }

      ApiService().ut(r['access_token']);

      if (!mounted) return;

      if (userType == 'worker' || role == 'worker') {
        Navigator.pushAndRemoveUntil(
            context, MaterialPageRoute(builder: (_) => const WorkerHomeShell()), (_) => false);
      } else {
        Navigator.pushAndRemoveUntil(
            context, MaterialPageRoute(builder: (_) => const HomeShell()), (_) => false);
      }
    } on DioException catch (e) {
      final msg = e.message ?? 'Login failed';
      if (e.response?.statusCode == 403) {
        toast('🔒 Access denied: $msg');
      } else {
        toast(msg);
      }
    } finally {
      if (mounted) setState(() => ld = false);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _pwd.dispose();
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5E6D3),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: FadeTransition(
              opacity: _fade,
              child: SlideTransition(
                position: _slide,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 40),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 32, offset: const Offset(0, 8)),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            width: 68, height: 68,
                            decoration: BoxDecoration(
                              color: AppColors.accent,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: const Center(
                                child: Icon(Icons.construction_rounded, color: Colors.white, size: 34)),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text('BuildSmart',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.outfit(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                        const SizedBox(height: 4),
                        Text('AI Construction System',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textSecondary, letterSpacing: 0.3)),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(color: AppColors.blueLight, borderRadius: BorderRadius.circular(10)),
                          child: Center(
                            child: Text('🔐 Worker & Site Supervisor login only',
                                style: GoogleFonts.outfit(fontSize: 10.5, color: AppColors.blue, fontWeight: FontWeight.w700)),
                          ),
                        ),
                        const SizedBox(height: 28),

                        Text('Email',
                            style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                        const SizedBox(height: 7),
                        TextField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          style: GoogleFonts.outfit(fontSize: 14),
                          decoration: const InputDecoration(hintText: 'you@buildsmart.my'),
                        ),
                        const SizedBox(height: 18),

                        Text('Password',
                            style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                        const SizedBox(height: 7),
                        TextField(
                          controller: _pwd,
                          obscureText: obscure,
                          onSubmitted: (_) => _login(),
                          style: GoogleFonts.outfit(fontSize: 14),
                          decoration: InputDecoration(
                            hintText: '••••••••',
                            suffixIcon: IconButton(
                              icon: Icon(
                                  obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                  size: 19,
                                  color: AppColors.textMuted),
                              onPressed: () => setState(() => obscure = !obscure),
                            ),
                          ),
                        ),
                        const SizedBox(height: 26),

                        SizedBox(
                          height: 52,
                          child: ElevatedButton(
                            onPressed: ld ? null : _login,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.accent,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              elevation: 0,
                            ),
                            child: ld
                                ? const SizedBox(
                                    height: 20, width: 20,
                                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.2))
                                : Text('Login',
                                    style: GoogleFonts.outfit(fontSize: 15.5, fontWeight: FontWeight.w700)),
                          ),
                        ),
                        const SizedBox(height: 18),

                        Center(
                          child: TextButton(
                            onPressed: () => Navigator.push(context,
                                MaterialPageRoute(builder: (_) => const WorkerRegisterPage())),
                            child: RichText(
                              textAlign: TextAlign.center,
                              text: TextSpan(
                                style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textMuted),
                                children: [
                                  const TextSpan(text: "Don't have a Worker account?  "),
                                  TextSpan(
                                    text: 'Register as Worker →',
                                    style: TextStyle(color: AppColors.green, fontWeight: FontWeight.w700),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const Divider(height: 8, color: AppColors.border),
                        const SizedBox(height: 14),

                        Center(
                          child: RichText(
                            textAlign: TextAlign.center,
                            text: TextSpan(
                              style: GoogleFonts.outfit(fontSize: 11, color: AppColors.textMuted),
                              children: const [
                                TextSpan(
                                  text: 'Powered by Google Gemini AI',
                                  style: TextStyle(color: Color(0xFF4285F4), fontWeight: FontWeight.w600),
                                ),
                                TextSpan(text: ' • '),
                                TextSpan(
                                  text: 'CIDB Construction 4.0',
                                  style: TextStyle(color: Color(0xFF4285F4), fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

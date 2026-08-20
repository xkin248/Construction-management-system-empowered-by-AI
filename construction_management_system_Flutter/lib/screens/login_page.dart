import 'dart:async';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../services/fcm_service.dart';
import 'home_shell.dart';
import 'worker_home_shell.dart';
import 'worker_register_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with SingleTickerProviderStateMixin {
  final _email = TextEditingController();
  final _pwd   = TextEditingController();
  bool ld = false, obscure = true;

  late final AnimationController _anim =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
  late final Animation<double> _fade  = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 0.12), end: Offset.zero,
  ).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOut));

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
      final user     = Map<String, dynamic>.from(r['user'] ?? {});
      final role     = user['role']?.toString().toLowerCase() ?? '';

      await sp.setString('user_type', userType);
      await sp.setString('user_role', role);
      if (user['worker_id']     != null) await sp.setInt('worker_id',     user['worker_id']     as int);
      if (user['supervisor_id'] != null) await sp.setInt('supervisor_id', user['supervisor_id'] as int);
      if (user['project_id']    != null) await sp.setInt('project_id',    user['project_id']    as int);

      ApiService().ut(r['access_token']);

      // FCM: register this device token for the freshly logged-in user.
      unawaited(FcmService.registerTokenToBackend());

      if (!mounted) return;

      final isWorker = userType.toLowerCase() == 'worker' || role == 'worker';
      if (isWorker) {
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
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.sidebarBg,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0D1117), Color(0xFF10141C), Color(0xFF1A2035)],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(builder: (ctx, constraints) {
            final isNarrow = constraints.maxWidth < 400;
            final hPad    = isNarrow ? 16.0 : 24.0;
            final cardPad = isNarrow ? 20.0 : 28.0;

            return SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 20),
              child: FadeTransition(
                opacity: _fade,
                child: SlideTransition(
                  position: _slide,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 400),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // ── Logo ──
                          Container(
                            width: 68, height: 68,
                            decoration: BoxDecoration(
                              color: AppColors.accent,
                              borderRadius: BorderRadius.circular(18),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.accent.withValues(alpha: 0.4),
                                  blurRadius: 24, offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: const Center(
                              child: Icon(Icons.construction_rounded, color: Colors.white, size: 34),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text('BuildSmart',
                              style: GoogleFonts.outfit(
                                  fontSize: 28, fontWeight: FontWeight.w800, color: Colors.white)),
                          const SizedBox(height: 4),
                          Text('AI Construction Management System',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.outfit(
                                  fontSize: 12, color: const Color(0xFF757E90), letterSpacing: 0.3)),
                          const SizedBox(height: 24),

                          // ── Login Card ──
                          Container(
                            padding: EdgeInsets.all(cardPad),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A1F2E),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: const Color(0xFF2A3045)),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.3),
                                  blurRadius: 32, offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Role badge
                                Center(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: AppColors.accent.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
                                    ),
                                    child: Text('🔐  Worker & Site Supervisor Login',
                                        style: GoogleFonts.outfit(
                                            fontSize: 13, color: AppColors.accent, fontWeight: FontWeight.w700)),
                                  ),
                                ),
                                const SizedBox(height: 22),

                                // Email field
                                Text('Email',
                                    style: GoogleFonts.outfit(
                                        fontSize: 13, fontWeight: FontWeight.w600,
                                        color: const Color(0xFFC8CDD8))),
                                const SizedBox(height: 8),
                                TextField(
                                  controller: _email,
                                  keyboardType: TextInputType.emailAddress,
                                  textInputAction: TextInputAction.next,
                                  style: GoogleFonts.outfit(fontSize: 14, color: Colors.white),
                                  decoration: _fieldDeco('you@buildsmart.my'),
                                ),
                                const SizedBox(height: 16),

                                // Password field
                                Text('Password',
                                    style: GoogleFonts.outfit(
                                        fontSize: 13, fontWeight: FontWeight.w600,
                                        color: const Color(0xFFC8CDD8))),
                                const SizedBox(height: 8),
                                TextField(
                                  controller: _pwd,
                                  obscureText: obscure,
                                  onSubmitted: (_) => _login(),
                                  textInputAction: TextInputAction.done,
                                  style: GoogleFonts.outfit(fontSize: 14, color: Colors.white),
                                  decoration: _fieldDeco('••••••••').copyWith(
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                        size: 19, color: const Color(0xFF4A5568),
                                      ),
                                      onPressed: () => setState(() => obscure = !obscure),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 24),

                                // Sign in button
                                SizedBox(
                                  height: 52,
                                  child: ElevatedButton(
                                    onPressed: ld ? null : _login,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.accent,
                                      foregroundColor: Colors.white,
                                      disabledBackgroundColor: AppColors.accent.withValues(alpha: 0.5),
                                      shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(14)),
                                      elevation: 0,
                                    ),
                                    child: ld
                                        ? const SizedBox(
                                            height: 20, width: 20,
                                            child: CircularProgressIndicator(
                                                color: Colors.white, strokeWidth: 2.2))
                                        : Text('Sign In',
                                            style: GoogleFonts.outfit(
                                                fontSize: 15.5, fontWeight: FontWeight.w700)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Register link
                          TextButton(
                            onPressed: () => Navigator.push(
                                context, MaterialPageRoute(builder: (_) => const WorkerRegisterPage())),
                            child: RichText(
                              textAlign: TextAlign.center,
                              text: TextSpan(
                                style: GoogleFonts.outfit(fontSize: 14, color: const Color(0xFF757E90)),
                                children: [
                                  const TextSpan(text: "Don't have a Worker account?  "),
                                  TextSpan(
                                    text: 'Register →',
                                    style: TextStyle(
                                        color: AppColors.accent, fontWeight: FontWeight.w700),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text('Powered by Google Gemini AI  •  CIDB Construction 4.0',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.outfit(
                                  fontSize: 11, color: const Color(0xFF3D4A5C))),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  InputDecoration _fieldDeco(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.outfit(fontSize: 14, color: const Color(0xFF4A5568)),
        filled: true,
        fillColor: const Color(0xFF0D1117),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF2A3045))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF2A3045))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.accent, width: 1.5)),
      );
}

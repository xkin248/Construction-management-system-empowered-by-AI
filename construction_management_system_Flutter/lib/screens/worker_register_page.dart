import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import 'login_page.dart';

class WorkerRegisterPage extends StatefulWidget {
  const WorkerRegisterPage({super.key});
  @override
  State<WorkerRegisterPage> createState() => _WorkerRegisterPageState();
}

class _WorkerRegisterPageState extends State<WorkerRegisterPage>
    with SingleTickerProviderStateMixin {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _pwd = TextEditingController();
  final _pwd2 = TextEditingController();
  final _phone = TextEditingController();
  final _ic = TextEditingController();
  String? _selectedSkill;
  bool ld = false, obscure = true, obscure2 = true;

  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
  late final Animation<double> _fade = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
  late final Animation<Offset> _slide = Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero)
      .animate(CurvedAnimation(parent: _anim, curve: Curves.easeOut));

  static const List<String> _skillOptions = [
    'General', 'Carpenter', 'Electrical', 'Plumbing', 'Masonry',
    'Steel', 'Painter', 'Welder', 'Tiler', 'Roofer'
  ];

  @override
  void initState() {
    super.initState();
    _anim.forward();
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _pwd.dispose();
    _pwd2.dispose();
    _phone.dispose();
    _ic.dispose();
    _anim.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (_name.text.trim().isEmpty) {
      toast('Please enter your full name');
      return;
    }
    if (_email.text.trim().isEmpty) {
      toast('Please enter your email');
      return;
    }
    if (_pwd.text.isEmpty || _pwd.text.length < 6) {
      toast('Password must be at least 6 characters');
      return;
    }
    if (_pwd.text != _pwd2.text) {
      toast('Passwords do not match');
      return;
    }

    setState(() => ld = true);
    try {
      await ApiService().registerWorker(
        name: _name.text.trim(),
        email: _email.text.trim(),
        password: _pwd.text,
        phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        icNumber: _ic.text.trim().isEmpty ? null : _ic.text.trim(),
        trade: _selectedSkill,
      );
      toast('✅ Worker account registered! You can now log in.');
      if (!mounted) return;
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => const LoginPage()));
    } on DioException catch (e) {
      toast(e.message ?? 'Registration failed');
    } finally {
      if (mounted) setState(() => ld = false);
    }
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
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
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
                        // Header
                        Center(
                          child: Container(
                            width: 64, height: 64,
                            decoration: BoxDecoration(
                              color: AppColors.green,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Center(child: Icon(Icons.badge_rounded, color: Colors.white, size: 32)),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text('Worker Registration',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                        const SizedBox(height: 4),
                        Text('Create your Worker account',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.outfit(fontSize: 15, color: AppColors.textSecondary, letterSpacing: 0.2)),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(color: AppColors.greenLight, borderRadius: BorderRadius.circular(10)),
                          child: Center(
                            child: Text('🔒 Only Worker role can register on this portal',
                                style: GoogleFonts.outfit(fontSize: 14, color: AppColors.green, fontWeight: FontWeight.w700)),
                          ),
                        ),
                        const SizedBox(height: 22),

                        _label('Full Name'),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _name,
                          style: GoogleFonts.outfit(fontSize: 15),
                          decoration: const InputDecoration(hintText: 'e.g. Ahmad Bin Osman'),
                        ),
                        const SizedBox(height: 14),

                        _label('Email'),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          style: GoogleFonts.outfit(fontSize: 15),
                          decoration: const InputDecoration(hintText: 'you@buildsmart.my'),
                        ),
                        const SizedBox(height: 14),

                        Row(children: [
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            _label('Password'),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _pwd,
                              obscureText: obscure,
                              style: GoogleFonts.outfit(fontSize: 15),
                              decoration: InputDecoration(
                                hintText: 'Min 6 characters',
                                suffixIcon: IconButton(
                                  icon: Icon(obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18, color: AppColors.textMuted),
                                  onPressed: () => setState(() => obscure = !obscure),
                                ),
                              ),
                            ),
                          ])),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            _label('Confirm'),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _pwd2,
                              obscureText: obscure2,
                              style: GoogleFonts.outfit(fontSize: 15),
                              decoration: InputDecoration(
                                hintText: 'Repeat password',
                                suffixIcon: IconButton(
                                  icon: Icon(obscure2 ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18, color: AppColors.textMuted),
                                  onPressed: () => setState(() => obscure2 = !obscure2),
                                ),
                              ),
                            ),
                          ])),
                        ]),
                        const SizedBox(height: 14),

                        Row(children: [
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            _label('Phone (optional)'),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _phone,
                              style: GoogleFonts.outfit(fontSize: 15),
                              decoration: const InputDecoration(hintText: '+60 1X-XXX XXXX'),
                            ),
                          ])),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            _label('IC Number (optional)'),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _ic,
                              style: GoogleFonts.outfit(fontSize: 15),
                              decoration: const InputDecoration(hintText: 'XXXXXX-XX-XXXX'),
                            ),
                          ])),
                        ]),
                        const SizedBox(height: 14),

                        Row(children: [
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            _label('Skill'),
                            const SizedBox(height: 6),
                            DropdownButtonFormField<String>(
                              initialValue: _selectedSkill,
                              isExpanded: true,
                              decoration: const InputDecoration(hintText: 'Select your skill'),
                              style: GoogleFonts.outfit(fontSize: 15, color: AppColors.textPrimary, fontWeight: FontWeight.w600),
                              items: _skillOptions
                                  .map((t) => DropdownMenuItem(value: t, child: Text(t, style: GoogleFonts.outfit(fontSize: 15))))
                                  .toList(),
                              onChanged: (v) => setState(() => _selectedSkill = v),
                            ),
                          ])),
                        ]),

                        const SizedBox(height: 24),
                        SizedBox(
                          height: 52,
                          child: ElevatedButton(
                            onPressed: ld ? null : _register,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.green,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              elevation: 0,
                            ),
                            child: ld
                                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.2))
                                : Text('Create Worker Account',
                                    style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w700)),
                          ),
                        ),
                        const SizedBox(height: 16),

                        Center(
                          child: TextButton(
                            onPressed: () => Navigator.pushReplacement(
                                context, MaterialPageRoute(builder: (_) => const LoginPage())),
                            child: RichText(
                              text: TextSpan(
                                style: GoogleFonts.outfit(fontSize: 15, color: AppColors.textSecondary),
                                children: [
                                  const TextSpan(text: 'Already have an account?  '),
                                  TextSpan(text: '← Back to Login', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700)),
                                ],
                              ),
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

  Widget _label(String s) => Text(s,
      style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary));
}

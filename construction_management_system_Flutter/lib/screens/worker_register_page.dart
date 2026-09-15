import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../l10n/app_strings.dart';
import 'login_page.dart';

class WorkerRegisterPage extends StatefulWidget {
  const WorkerRegisterPage({super.key});
  @override
  State<WorkerRegisterPage> createState() => _WorkerRegisterPageState();
}

class _WorkerRegisterPageState extends State<WorkerRegisterPage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _name  = TextEditingController();
  final _email = TextEditingController();
  final _pwd   = TextEditingController();
  final _pwd2  = TextEditingController();
  final _phone = TextEditingController();
  final _ic    = TextEditingController();

  // FocusNodes for keyboard "next" action chaining
  final _emailFocus = FocusNode();
  final _pwdFocus   = FocusNode();
  final _pwd2Focus  = FocusNode();
  final _phoneFocus = FocusNode();
  final _icFocus    = FocusNode();

  String? _selectedSkill;
  bool ld = false, obscure = true, obscure2 = true;

  // Nullable + lazy getter: never create a ticker from a deactivated element
  // (e.g. dispose() running before the controller was ever used).
  AnimationController? _animCtrl;
  AnimationController get _anim =>
      _animCtrl ??= AnimationController(vsync: this, duration: const Duration(milliseconds: 550));
  late final Animation<double> _fade  = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 0.10), end: Offset.zero,
  ).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));

  static const List<String> _skillOptions = [
    'General', 'Carpenter', 'Electrical', 'Plumbing', 'Masonry',
    'Steel', 'Painter', 'Welder', 'Tiler', 'Roofer',
  ];

  @override
  void initState() {
    super.initState();
    _anim.forward();
  }

  @override
  void dispose() {
    _name.dispose(); _email.dispose(); _pwd.dispose();
    _pwd2.dispose(); _phone.dispose(); _ic.dispose();
    _emailFocus.dispose(); _pwdFocus.dispose(); _pwd2Focus.dispose();
    _phoneFocus.dispose(); _icFocus.dispose();
    _animCtrl?.dispose();
    _animCtrl = null;
    super.dispose();
  }

  Future<void> _register() async {
    // All fields are required — no optional fields on this form.
    if (_name.text.trim().isEmpty) { toast('Please enter your full name'); return; }
    if (_email.text.trim().isEmpty) { toast('Please enter your email'); return; }
    if (_pwd.text.isEmpty || _pwd.text.length < 6) {
      toast('Password must be at least 6 characters'); return;
    }
    if (_pwd.text != _pwd2.text) { toast('Passwords do not match'); return; }
    if (_phone.text.trim().isEmpty) { toast('Please enter your phone number'); return; }
    if (_ic.text.trim().isEmpty) { toast('Please enter your IC number'); return; }
    if (_selectedSkill == null || _selectedSkill!.isEmpty) {
      toast('Please select your trade / skill'); return;
    }

    setState(() => ld = true);
    try {
      await ApiService().registerWorker(
        name:     _name.text.trim(),
        email:    _email.text.trim(),
        password: _pwd.text,
        phone:    _phone.text.trim(),
        icNumber: _ic.text.trim(),
        trade:    _selectedSkill,
      );
      toast('✅ Worker account registered! You can now log in.');
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginPage()));
    } on DioException catch (e) {
      toast(e.message ?? 'Registration failed');
    } finally {
      if (mounted) setState(() => ld = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.darkBg,
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.authBgTop, AppColors.authBgMid, AppColors.authBgBottom],
            ),
          ),
          child: SafeArea(
            child: Stack(
              children: [
                LayoutBuilder(builder: (ctx, constraints) {
              final isNarrow = constraints.maxWidth < 400;
              final hPad    = isNarrow ? 16.0 : 24.0;
              final cardPad = isNarrow ? 20.0 : 28.0;

              return SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 24),
                child: FadeTransition(
                  opacity: _fade,
                  child: SlideTransition(
                    position: _slide,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 480),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // ── Brand Header ──
                            Container(
                              width: 60, height: 60,
                              decoration: BoxDecoration(
                                color: AppColors.green,
                                borderRadius: AppRadius.rMd,
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.green.withValues(alpha: 0.35),
                                    blurRadius: 20, offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: const Center(
                                child: Icon(Icons.badge_rounded, color: AppColors.onAccent, size: 30),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(AppStrings.t('worker.register.title'),
                                style: GoogleFonts.inter(
                                    fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.onAccent)),
                            const SizedBox(height: 4),
                            Text(AppStrings.t('worker.register.subtitle'),
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(fontSize: 13, color: AppColors.darkTextMuted)),
                            const SizedBox(height: 24),

                            // ── Card ──
                            Container(
                              padding: EdgeInsets.all(cardPad),
                              decoration: BoxDecoration(
                                color: AppColors.darkSurface,
                                borderRadius: AppRadius.rMd,
                                border: Border.all(color: AppColors.darkBorder),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.scrim,
                                    blurRadius: 32, offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: Form(
                                key: _formKey,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    // Role badge
                                    Center(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: AppColors.green.withValues(alpha: 0.15),
                                          borderRadius: AppRadius.rMd,
                                          border: Border.all(color: AppColors.green.withValues(alpha: 0.3)),
                                        ),
                                        child: Text(AppStrings.t('worker.register.roleBadge'),
                                            style: GoogleFonts.inter(
                                                fontSize: 13, color: AppColors.green, fontWeight: FontWeight.w700)),
                                      ),
                                    ),
                                    const SizedBox(height: 24),

                                    // ── Full Name ──
                                    _label(AppStrings.t('worker.register.fullName')),
                                    const SizedBox(height: 8),
                                    _field(
                                      controller: _name,
                                      hint: 'e.g. Ahmad Bin Osman',
                                      textInputAction: TextInputAction.next,
                                      onSubmitted: (_) => FocusScope.of(context).requestFocus(_emailFocus),
                                    ),
                                    const SizedBox(height: 16),

                                    // ── Email ──
                                    _label(AppStrings.t('login.email')),
                                    const SizedBox(height: 8),
                                    _field(
                                      controller: _email,
                                      focusNode: _emailFocus,
                                      hint: 'you@buildsmart.my',
                                      keyboardType: TextInputType.emailAddress,
                                      textInputAction: TextInputAction.next,
                                      onSubmitted: (_) => FocusScope.of(context).requestFocus(_pwdFocus),
                                    ),
                                    const SizedBox(height: 16),

                                    // ── Password + Confirm (stacked on narrow, side-by-side on wide) ──
                                    isNarrow
                                        ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                            _label(AppStrings.t('login.password')),
                                            const SizedBox(height: 8),
                                            _pwdField(
                                              controller: _pwd,
                                              focusNode: _pwdFocus,
                                              hint: 'Min 6 characters',
                                              obscure: obscure,
                                              onToggle: () => setState(() => obscure = !obscure),
                                              nextFocus: _pwd2Focus,
                                            ),
                                            const SizedBox(height: 16),
                                            _label(AppStrings.t('worker.register.confirmPassword')),
                                            const SizedBox(height: 8),
                                            _pwdField(
                                              controller: _pwd2,
                                              focusNode: _pwd2Focus,
                                              hint: 'Repeat password',
                                              obscure: obscure2,
                                              onToggle: () => setState(() => obscure2 = !obscure2),
                                              nextFocus: _phoneFocus,
                                            ),
                                          ])
                                        : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                              _label(AppStrings.t('login.password')),
                                              const SizedBox(height: 8),
                                              _pwdField(
                                                controller: _pwd,
                                                focusNode: _pwdFocus,
                                                hint: 'Min 6 characters',
                                                obscure: obscure,
                                                onToggle: () => setState(() => obscure = !obscure),
                                                nextFocus: _pwd2Focus,
                                              ),
                                            ])),
                                            const SizedBox(width: 12),
                                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                              _label(AppStrings.t('worker.register.confirm')),
                                              const SizedBox(height: 8),
                                              _pwdField(
                                                controller: _pwd2,
                                                focusNode: _pwd2Focus,
                                                hint: 'Repeat password',
                                                obscure: obscure2,
                                                onToggle: () => setState(() => obscure2 = !obscure2),
                                                nextFocus: _phoneFocus,
                                              ),
                                            ])),
                                          ]),
                                    const SizedBox(height: 16),

                                    // ── Phone + IC (stacked on narrow) ──
                                    isNarrow
                                        ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                            _label(AppStrings.t('worker.register.phone')),
                                            const SizedBox(height: 8),
                                            _field(
                                              controller: _phone,
                                              focusNode: _phoneFocus,
                                              hint: '+60 1X-XXX XXXX',
                                              keyboardType: TextInputType.phone,
                                              textInputAction: TextInputAction.next,
                                              onSubmitted: (_) => FocusScope.of(context).requestFocus(_icFocus),
                                            ),
                                            const SizedBox(height: 16),
                                            _label(AppStrings.t('worker.register.ic')),
                                            const SizedBox(height: 8),
                                            _field(
                                              controller: _ic,
                                              focusNode: _icFocus,
                                              hint: 'XXXXXX-XX-XXXX',
                                              keyboardType: TextInputType.number,
                                              textInputAction: TextInputAction.done,
                                            ),
                                          ])
                                        : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                              _label(AppStrings.t('worker.register.phone')),
                                              const SizedBox(height: 8),
                                              _field(
                                                controller: _phone,
                                                focusNode: _phoneFocus,
                                                hint: '+60 1X-XXX XXXX',
                                                keyboardType: TextInputType.phone,
                                                textInputAction: TextInputAction.next,
                                                onSubmitted: (_) => FocusScope.of(context).requestFocus(_icFocus),
                                              ),
                                            ])),
                                            const SizedBox(width: 12),
                                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                              _label(AppStrings.t('worker.register.ic')),
                                              const SizedBox(height: 8),
                                              _field(
                                                controller: _ic,
                                                focusNode: _icFocus,
                                                hint: 'XXXXXX-XX-XXXX',
                                                keyboardType: TextInputType.number,
                                                textInputAction: TextInputAction.done,
                                              ),
                                            ])),
                                          ]),
                                    const SizedBox(height: 16),

                                    // ── Trade/Skill ──
                                    _label(AppStrings.t('worker.register.trade')),
                                    const SizedBox(height: 8),
                                    _dropdownField(),
                                    const SizedBox(height: 24),

                                    // ── Submit button ──
                                    SizedBox(
                                      height: 52,
                                      child: ElevatedButton(
                                        onPressed: ld ? null : _register,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppColors.green,
                                          foregroundColor: AppColors.onAccent,
                                          disabledBackgroundColor: AppColors.green.withValues(alpha: 0.5),
                                          shape: RoundedRectangleBorder(borderRadius: AppRadius.rMd),
                                          elevation: 0,
                                        ),
                                        child: ld
                                            ? const SizedBox(
                                                height: 20, width: 20,
                                                child: CircularProgressIndicator(color: AppColors.onAccent, strokeWidth: 2.2))
                                            : Text(AppStrings.t('worker.register.submit'),
                                                style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700)),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),

                            // ── Back to login ──
                            TextButton(
                              onPressed: () => Navigator.pushReplacement(
                                  context, MaterialPageRoute(builder: (_) => const LoginPage())),
                              child: RichText(
                                textAlign: TextAlign.center,
                                text: TextSpan(
                                  style: GoogleFonts.inter(fontSize: 14, color: AppColors.darkTextMuted),
                                  children: [
                                    TextSpan(text: AppStrings.t('worker.register.haveAccount')),
                                    TextSpan(
                                      text: '← ${AppStrings.t('worker.register.backToLogin')}',
                                      style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text('CIDB Construction 4.0',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(fontSize: 12, color: AppColors.darkTextMuted)),
                            const SizedBox(height: 8),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }), 
            ],
          ),
        ),
        ),
      ),
    );
  }

  // ── Shared dark-themed text field ──
  Widget _field({
    required TextEditingController controller,
    FocusNode? focusNode,
    required String hint,
    TextInputType keyboardType = TextInputType.text,
    TextInputAction textInputAction = TextInputAction.next,
    ValueChanged<String>? onSubmitted,
  }) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      style: GoogleFonts.inter(fontSize: 14, color: AppColors.onAccent),
      decoration: _inputDecoration(hint),
    );
  }

  // ── Password field with toggle ──
  Widget _pwdField({
    required TextEditingController controller,
    FocusNode? focusNode,
    required String hint,
    required bool obscure,
    required VoidCallback onToggle,
    FocusNode? nextFocus,
  }) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      obscureText: obscure,
      textInputAction: nextFocus != null ? TextInputAction.next : TextInputAction.done,
      onSubmitted: nextFocus != null
          ? (_) => FocusScope.of(context).requestFocus(nextFocus)
          : null,
      style: GoogleFonts.inter(fontSize: 14, color: AppColors.onAccent),
      decoration: _inputDecoration(hint).copyWith(
        suffixIcon: IconButton(
          icon: Icon(
            obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            size: 18,
            color: AppColors.darkTextMuted,
          ),
          onPressed: onToggle,
        ),
      ),
    );
  }

  // ── Dropdown ──
  Widget _dropdownField() {
    return DropdownButtonFormField<String>(
      initialValue: _selectedSkill,
      isExpanded: true,
      dropdownColor: AppColors.darkSurface,
      decoration: _inputDecoration('Select your trade'),
      style: GoogleFonts.inter(fontSize: 14, color: AppColors.onAccent, fontWeight: FontWeight.w600),
      icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.darkTextMuted),
      items: _skillOptions
          .map((t) => DropdownMenuItem(
                value: t,
                child: Text(t, style: GoogleFonts.inter(fontSize: 14, color: AppColors.onAccent)),
              ))
          .toList(),
      onChanged: (v) => setState(() => _selectedSkill = v),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.inter(fontSize: 14, color: AppColors.darkTextMuted),
      filled: true,
      fillColor: AppColors.darkBg,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border:        OutlineInputBorder(borderRadius: AppRadius.rMd, borderSide: const BorderSide(color: AppColors.darkBorder)),
      enabledBorder: OutlineInputBorder(borderRadius: AppRadius.rMd, borderSide: const BorderSide(color: AppColors.darkBorder)),
      focusedBorder: OutlineInputBorder(borderRadius: AppRadius.rMd, borderSide: BorderSide(color: AppColors.green, width: 1.5)),
    );
  }

  Widget _label(String s) => Text(s,
      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSidebar));
}

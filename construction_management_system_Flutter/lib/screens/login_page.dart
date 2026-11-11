import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/api_service.dart';
import '../services/app_settings.dart';
import '../services/fcm_service.dart';
import '../services/token_storage.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';
import '../widgets/app_button.dart';
import 'home_shell.dart';
import 'worker_home_shell.dart';
import 'worker_register_page.dart';

/// Sign-in screen, rebuilt to the current UI reference sheet.
///
/// Visual contract taken from the reference image: light canvas, orange brand
/// tile, one white card, a Worker / Supervisor switch, two fields with a
/// show/hide password toggle, one orange fill primary action, a quiet
/// "Forgot Password?" link and a bordered register action.
///
/// Behaviour contract taken from BuildSmart_Button_Click_UI_Specification.md §4:
///  - the Login button shows `Logging in…` while the request is in flight and
///    rejects a second tap (no duplicate submissions),
///  - success is announced only after the backend answers, then routes by the
///    role the backend returns,
///  - every failure has its own readable sentence: missing fields, wrong
///    credentials, disabled account, network down,
///  - a failed sign-in NEVER reveals whether the email / Worker ID exists.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

enum _LoginRole { worker, supervisor }

class _LoginPageState extends State<LoginPage> {
  final _email = TextEditingController();
  final _pwd = TextEditingController();
  final _pwdFocus = FocusNode();

  bool _busy = false;
  bool _obscure = true;
  _LoginRole _role = _LoginRole.worker;
  String? _formError;

  @override
  void initState() {
    super.initState();
    AppColors.darkMode.addListener(_onThemeChanged);
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    AppColors.darkMode.removeListener(_onThemeChanged);
    _email.dispose();
    _pwd.dispose();
    _pwdFocus.dispose();
    super.dispose();
  }

  // ── actions ──────────────────────────────────────────────────────────────

  Future<void> _login() async {
    if (_busy) return;
    final id = _email.text.trim();
    final pwd = _pwd.text;

    // Required-field check first: the spec wants one plain sentence, not three
    // field-level red labels.
    if (id.isEmpty || pwd.isEmpty) {
      setState(() => _formError = AppSettings.t(
            id.isEmpty && pwd.isEmpty
                ? 'Enter your email or Worker ID and your password.'
                : (id.isEmpty
                    ? 'Enter your email or Worker ID.'
                    : 'Enter your password.'),
            id.isEmpty && pwd.isEmpty
                ? '请输入邮箱/工号和密码。'
                : (id.isEmpty ? '请输入邮箱或工号。' : '请输入密码。'),
            id.isEmpty && pwd.isEmpty
                ? 'Masukkan e-mel atau ID pekerja dan kata laluan.'
                : (id.isEmpty
                    ? 'Masukkan e-mel atau ID pekerja.'
                    : 'Masukkan kata laluan.'),
          ));
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _formError = null;
    });

    try {
      final r = await ApiService().login(a: id, p: pwd);

      await TokenStorage.saveToken(r['access_token']);
      final userType = (r['user_type'] ?? 'supervisor').toString();
      final user = Map<String, dynamic>.from(r['user'] ?? {});
      final role = user['role']?.toString().toLowerCase() ?? '';
      await TokenStorage.saveUserMeta(
        userType: userType,
        role: role,
        workerId: user['worker_id'] as int?,
        supervisorId: user['supervisor_id'] as int?,
        projectId: user['project_id'] as int?,
      );
      ApiService().ut(r['access_token']);
      unawaited(FcmService.registerTokenToBackend());

      if (!mounted) return;

      // Route on what the backend says, not on the switch above — the switch is
      // a signpost only, the account decides the role.
      final isWorker = userType.toLowerCase() == 'worker' || role == 'worker';
      setState(() => _busy = false);
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => isWorker ? const WorkerHomeShell() : const HomeShell()),
        (_) => false,
      );
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        // 401 and 400 collapse into one message so the screen can't be used to
        // probe which emails exist.
        _formError = readableError(e);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _formError = readableError(e);
      });
    }
  }

  Future<void> _forgotPassword() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.rSheet),
        title: Text(
          AppSettings.t('Reset password', '重置密码', 'Set semula kata laluan'),
          style: GoogleFonts.inter(
              fontSize: 17, fontWeight: FontWeight.w900, color: AppColors.navy),
        ),
        content: Text(
          AppSettings.t(
            'Site accounts are issued and reset by your supervisor or project admin. '
            'Contact them to get a new password, then sign in again.',
            '工地账号由监理或项目管理员发放与重置。请联系他们获取新密码后重新登录。',
            'Akaun tapak dikeluarkan dan diset semula oleh penyelia atau pentadbir projek anda. '
            'Hubungi mereka untuk kata laluan baharu, kemudian log masuk semula.',
          ),
          style: GoogleFonts.inter(
              fontSize: 13.5, height: 1.45, color: AppColors.textSecondary),
        ),
        actions: [
          AppButton(
            label: AppSettings.t('Got it', '知道了', 'Faham'),
            expand: false,
            height: 44,
            onPressed: () => Navigator.of(ctx).pop(),
          ),
        ],
      ),
    );
  }

  // ── build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= AppBreakpoints.phone;

    return Scaffold(
      backgroundColor: AppColors.bgMain,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: wide ? 24 : 18, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _brandHeader(),
                  const SizedBox(height: 22),
                  _card(wide),
                  const SizedBox(height: 18),
                  _footer(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _brandHeader() {
    return Column(
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: AppColors.accentSolid,
            borderRadius: BorderRadius.circular(18),
            boxShadow: AppShadows.accent(AppColors.accentSolid, alpha: 0.32, blur: 18),
          ),
          child: Icon(Icons.apartment_rounded, size: 32, color: AppColors.accentInk),
        ),
        const SizedBox(height: 14),
        Text(
          'BuildSmart',
          style: GoogleFonts.inter(
            fontSize: 26,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.6,
            color: AppColors.navy,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          AppSettings.t(
            'Construction workforce & site management',
            '建筑工人与工地管理',
            'Pengurusan tenaga kerja & tapak bina',
          ),
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
              fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted),
        ),
      ],
    );
  }

  Widget _card(bool wide) {
    return Container(
      padding: EdgeInsets.all(wide ? 20 : 16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: AppRadius.rXl,
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            AppSettings.t('Sign in', '登录', 'Log masuk'),
            style: GoogleFonts.inter(
                fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 14),
          _roleSwitch(),
          const SizedBox(height: 16),
          _label(AppSettings.t('Email or Worker ID', '邮箱或工号', 'E-mel atau ID pekerja')),
          const SizedBox(height: 6),
          TextField(
            controller: _email,
            enabled: !_busy,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autocorrect: false,
            onSubmitted: (_) => _pwdFocus.requestFocus(),
            style: GoogleFonts.inter(
                fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
            decoration: _inputDeco(
              hint: _role == _LoginRole.worker ? 'e.g. 1001 or name@site.com' : 'name@site.com',
              icon: Icons.badge_outlined,
            ),
          ),
          const SizedBox(height: 14),
          _label(AppSettings.t('Password', '密码', 'Kata laluan')),
          const SizedBox(height: 6),
          TextField(
            controller: _pwd,
            focusNode: _pwdFocus,
            enabled: !_busy,
            obscureText: _obscure,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _login(),
            style: GoogleFonts.inter(
                fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
            decoration: _inputDeco(
              hint: '••••••••',
              icon: Icons.lock_outline_rounded,
              suffix: IconButton(
                onPressed: () => setState(() => _obscure = !_obscure),
                tooltip: _obscure
                    ? AppSettings.t('Show password', '显示密码', 'Tunjuk kata laluan')
                    : AppSettings.t('Hide password', '隐藏密码', 'Sembunyi kata laluan'),
                icon: Icon(
                  _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  size: 20,
                  color: AppColors.textMuted,
                ),
              ),
            ),
          ),
          if (_formError != null) ...[
            const SizedBox(height: 12),
            AppErrorBanner(message: _formError!),
          ],
          const SizedBox(height: 16),
          AppButton(
            label: AppSettings.t('Login', '登录', 'Log masuk'),
            loadingLabel: AppSettings.t('Logging in…', '登录中…', 'Sedang log masuk…'),
            loading: _busy,
            height: 54,
            icon: Icons.login_rounded,
            onPressed: _login,
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _busy ? null : _forgotPassword,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                AppSettings.t('Forgot Password?', '忘记密码？', 'Lupa kata laluan?'),
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.accentSolid,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: Divider(color: AppColors.border)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                AppSettings.t('New here?', '还没有账号？', 'Baru di sini?'),
                style: GoogleFonts.inter(
                    fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMuted),
              ),
            ),
            Expanded(child: Divider(color: AppColors.border)),
          ]),
          const SizedBox(height: 12),
          AppButton(
            label: AppSettings.t('Register as worker', '注册工人账号', 'Daftar sebagai pekerja'),
            tone: AppButtonTone.secondary,
            height: 50,
            icon: Icons.person_add_alt_1_outlined,
            onPressed: _busy
                ? null
                : () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const WorkerRegisterPage()),
                    ),
          ),
        ],
      ),
    );
  }

  Widget _roleSwitch() {
    Widget tab(_LoginRole r, String label, IconData icon) {
      final active = _role == r;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _busy ? null : () => setState(() => _role = r),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            height: 44,
            decoration: BoxDecoration(
              color: active ? AppColors.accentSolid : AppColors.transparent,
              borderRadius: AppRadius.rBtn,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon,
                    size: 17,
                    color: active ? AppColors.onAccent : AppColors.textSecondary),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: active ? AppColors.onAccent : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppColors.bgMain,
            borderRadius: AppRadius.rBtn,
            border: Border.all(color: AppColors.border),
          ),
          child: Row(children: [
            tab(_LoginRole.worker, AppSettings.t('Worker', '工人', 'Pekerja'),
                Icons.engineering_outlined),
            tab(_LoginRole.supervisor, AppSettings.t('Supervisor', '监理', 'Penyelia'),
                Icons.supervisor_account_outlined),
          ]),
        ),
        const SizedBox(height: 6),
        Text(
          AppSettings.t(
            'Your account decides the role — this switch only labels the form.',
            '实际角色由账号决定，此处仅用于标识登录身份。',
            'Akaun anda menentukan peranan — suis ini hanya melabel borang.',
          ),
          style: GoogleFonts.inter(
              fontSize: 11, height: 1.3, color: AppColors.textMuted),
        ),
      ],
    );
  }

  Widget _footer() {
    return Column(
      children: [
        Text(
          AppSettings.t(
            'Site data stays on your project. Sign out on shared devices.',
            '工地数据仅限本项目可见，共用设备请及时退出。',
            'Data tapak terhad kepada projek anda. Log keluar pada peranti kongsi.',
          ),
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(fontSize: 11.5, color: AppColors.textMuted, height: 1.3),
        ),
      ],
    );
  }

  Widget _label(String text) => Text(
        text,
        style: GoogleFonts.inter(
            fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.textSecondary),
      );

  InputDecoration _inputDeco({
    required String hint,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.inter(
          fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textMuted),
      prefixIcon: Icon(icon, size: 19, color: AppColors.textMuted),
      suffixIcon: suffix,
      filled: true,
      fillColor: AppColors.bgMain,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      border: OutlineInputBorder(
          borderRadius: AppRadius.bInput, borderSide: BorderSide(color: AppColors.border)),
      enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.bInput, borderSide: BorderSide(color: AppColors.border)),
      focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.bInput,
          borderSide: BorderSide(color: AppColors.accentSolid, width: 1.6)),
      disabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.bInput, borderSide: BorderSide(color: AppColors.border)),
    );
  }
}

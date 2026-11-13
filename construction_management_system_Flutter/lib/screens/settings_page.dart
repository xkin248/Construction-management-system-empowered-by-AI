import 'package:flutter/material.dart';
import '../widgets/app_page_intro.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';
import '../services/app_settings.dart';
import '../services/token_storage.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';
import 'login_page.dart';

/// Supervisor settings screen (reference flow: desktop sidebar "Settings").
///
/// Groups everything a site supervisor can change without touching the backend:
/// language, theme mode, notification preferences (stored locally) and logout.
/// The logout action is destructive-toned and always asks for confirmation.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  Map? _user;
  bool _loading = true;
  bool _busyLogout = false;

  /// Notification preference switches. Stored per category in SharedPreferences;
  /// the backend has no per-user preference endpoint yet, so the value only
  /// gates local display and is labelled accordingly.
  static const _notifCategories = <String, List<String>>{
    'attendance': ['Attendance', 'Kehadiran'],
    'task': ['Tasks', 'Tugasan'],
    'safety': ['Safety', 'Keselamatan'],
    'project': ['Projects', 'Projek'],
    'common': ['Common Tasks', 'Tugasan Harian'],
  };

  final Map<String, bool> _notifOn = {
    for (final k in _notifCategories.keys) k: true,
  };

  @override
  void initState() {
    super.initState();
    AppColors.darkMode.addListener(_rebuild);
    AppSettings.lang.addListener(_rebuild);
    _load();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    AppColors.darkMode.removeListener(_rebuild);
    AppSettings.lang.removeListener(_rebuild);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      _user = await ApiService().me();
    } catch (_) {
      // settings must stay usable offline; the account card simply stays empty
    }
    final sp = await SharedPreferences.getInstance();
    for (final k in _notifCategories.keys) {
      _notifOn[k] = sp.getBool('notif_pref_$k') ?? true;
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _setNotif(String key, bool value) async {
    setState(() => _notifOn[key] = value);
    final sp = await SharedPreferences.getInstance();
    await sp.setBool('notif_pref_$key', value);
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: AppRadius.rXl),
        title: Text(
          AppSettings.t('Log out?', '退出登录？', 'Log keluar?'),
          style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        content: Text(
          AppSettings.t(
            'You will need to sign in again to manage sites.',
            '退出后需要重新登录才能继续管理工地。',
            'Anda perlu log masuk semula untuk mengurus tapak.',
          ),
          style: GoogleFonts.inter(
              fontSize: 13.5, height: 1.4, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppSettings.t('Cancel', '取消', 'Batal'),
                style: GoogleFonts.inter(
                    fontSize: 14, fontWeight: FontWeight.w700)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
              minimumSize: const Size(96, 44),
              shape: RoundedRectangleBorder(borderRadius: AppRadius.rMd),
            ),
            child: Text(AppSettings.t('Log out', '退出登录', 'Log keluar'),
                style: GoogleFonts.inter(
                    fontSize: 14, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busyLogout = true);
    try {
      await TokenStorage.clearAuth();
      ApiService().ct();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(context,
          MaterialPageRoute(builder: (_) => const LoginPage()), (_) => false);
    } finally {
      if (mounted) setState(() => _busyLogout = false);
    }
  }

  /// Re-seeds the AppSettings notifier so every page picks the new language.
  void _setLang(String code) {
    if (AppSettings.lang.value == code) return;
    AppSettings.lang.value = code;
    setState(() {});
  }

  void _setTheme(String mode) {
    if (AppSettings.themeMode.value == mode) return;
    AppSettings.themeMode.value = mode;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgMain,
      appBar: AppBar(
        backgroundColor: AppColors.bgCard,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        surfaceTintColor: AppColors.transparent,
        shape: Border(bottom: BorderSide(color: AppColors.border)),
        centerTitle: false,
        iconTheme: const IconThemeData(color: AppColors.navy),
        title: Text(
          AppSettings.t('Settings', '设置', 'Tetapan'),
          style: GoogleFonts.inter(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                    maxWidth: AppBreakpoints.maxContentWidth),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  children: [
                    AppPageIntro(
                      icon: Icons.tune_rounded,
                      enTitle: 'YOUR PREFERENCES',
                      msTitle: 'TETAPAN ANDA',
                      zhTitle: '个人设置',
                      enSubtitle: 'Language, appearance and notifications',
                      msSubtitle: 'Bahasa, paparan dan notifikasi',
                      zhSubtitle: '语言、外观和通知设置',
                      worker: false,
                    ),
                    const SizedBox(height: 14),
                    _accountCard(),
                    const SizedBox(height: 16),
                    _section(
                      icon: Icons.translate_rounded,
                      title: AppSettings.t('Language', '语言', 'Bahasa'),
                      subtitle: AppSettings.t(
                          'Applies to every screen immediately.',
                          '切换后整个应用立即生效。',
                          'Berkuat kuasa serta-merta.'),
                      child: _choiceRow(
                        options: const [
                          ['en', 'English', 'English'],
                          ['ms', 'Bahasa Melayu', 'Bahasa Melayu'],
                          ['zh', '中文', '中文'],
                        ],
                        current: AppSettings.lang.value,
                        onPick: _setLang,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _section(
                      icon: Icons.brightness_6_outlined,
                      title: AppSettings.t('Theme', '主题', 'Tema'),
                      subtitle: AppSettings.t(
                          'Site work in daylight vs night shifts.',
                          '适合白天与夜间两种工地环境。',
                          'Sesuai untuk syif siang dan malam.'),
                      child: _choiceRow(
                        options: const [
                          ['light', 'Light', 'Cerah'],
                          ['dark', 'Dark', 'Gelap'],
                          ['system', 'System', 'Sistem'],
                        ],
                        current: AppSettings.themeMode.value,
                        onPick: _setTheme,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _section(
                      icon: Icons.notifications_active_outlined,
                      title: AppSettings.t('Notification preferences', '通知偏好',
                          'Keutamaan notifikasi'),
                      subtitle: AppSettings.t(
                          'Choose which alerts reach this device.',
                          '选择要接收的提醒类别。',
                          'Pilih makluman yang diterima.'),
                      child: Column(
                        children: [
                          for (final entry in _notifCategories.entries)
                            SwitchListTile.adaptive(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              value: _notifOn[entry.key] ?? true,
                              activeThumbColor: AppColors.accentSolid,
                              title: Text(
                                AppSettings.t(entry.value[0],
                                    _zhNotif(entry.key), entry.value[1]),
                                style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary),
                              ),
                              onChanged: (v) => _setNotif(entry.key, v),
                            ),
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(children: [
                              Icon(Icons.info_outline_rounded,
                                  size: 14, color: AppColors.textMuted),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  AppSettings.t(
                                    'Stored on this device. Server-side delivery rules are not editable yet.',
                                    '仅保存在本机，服务端推送规则暂不可编辑。',
                                    'Disimpan pada peranti ini sahaja.',
                                  ),
                                  style: GoogleFonts.inter(
                                      fontSize: 11.5,
                                      color: AppColors.textMuted),
                                ),
                              ),
                            ]),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _section(
                      icon: Icons.info_outline_rounded,
                      title: AppSettings.t('About', '关于', 'Perihal'),
                      subtitle: 'BuildSmart FYP build',
                      child: Column(children: [
                        _aboutRow(
                            AppSettings.t('Role', '角色', 'Peranan'),
                            (_user?['role'] ?? '—')
                                .toString()
                                .replaceAll('_', ' ')),
                        _aboutRow(
                            'API',
                            (AppSettings.t(
                              'Connected to the FastAPI backend',
                              '已连接 FastAPI 后端',
                              'Bersambung ke backend FastAPI',
                            ))),
                        _aboutRow(
                            AppSettings.t('Version', '版本', 'Versi'), '1.0.0'),
                      ]),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: _busyLogout ? null : _logout,
                        icon: _busyLogout
                            ? SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: AppColors.danger))
                            : Icon(Icons.logout_rounded,
                                size: 18, color: AppColors.danger),
                        label: Text(
                          _busyLogout
                              ? AppSettings.t(
                                  'Logging out…', '正在退出…', 'Sedang log keluar…')
                              : AppSettings.t('Log out', '退出登录', 'Log keluar'),
                          style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.danger),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: AppColors.danger),
                          shape: RoundedRectangleBorder(
                              borderRadius: AppRadius.rMd),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  String _zhNotif(String key) =>
      const {
        'attendance': '考勤',
        'task': '任务',
        'safety': '安全',
        'project': '项目',
        'common': '日常任务',
      }[key] ??
      key;

  Widget _accountCard() {
    final name =
        (_user?['full_name'] ?? AppSettings.t('Supervisor', '监理', 'Penyelia'))
            .toString();
    final email = (_user?['email'] ?? '').toString();
    final role =
        (_user?['role'] ?? 'site_supervisor').toString().replaceAll('_', ' ');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.navy,
        borderRadius: AppRadius.rXl,
      ),
      child: Row(children: [
        CircleAvatar(
          radius: 26,
          backgroundColor: AppColors.accentSolid,
          child: Text(
            name.isNotEmpty ? name.characters.first.toUpperCase() : '?',
            style: GoogleFonts.inter(
                fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name,
                style: GoogleFonts.inter(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Colors.white)),
            if (email.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(email,
                  style: GoogleFonts.inter(
                      fontSize: 12.5,
                      color: Colors.white.withValues(alpha: 0.75))),
            ],
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(role.toUpperCase(),
                  style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: Colors.white)),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _section({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: AppRadius.rLg,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 18, color: AppColors.navy),
          const SizedBox(width: 8),
          Expanded(
            child: Text(title,
                style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary)),
          ),
        ]),
        const SizedBox(height: 3),
        Text(subtitle,
            style: GoogleFonts.inter(
                fontSize: 12, height: 1.35, color: AppColors.textMuted)),
        const SizedBox(height: 12),
        child,
      ]),
    );
  }

  /// Row of pill choices — one selection, tap to apply immediately.
  Widget _choiceRow({
    required List<List<String>> options,
    required String current,
    required ValueChanged<String> onPick,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((opt) {
        final active = opt[0] == current;
        return InkWell(
          onTap: () => onPick(opt[0]),
          borderRadius: AppRadius.rMd,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: active ? AppColors.navy : AppColors.bgMain,
              borderRadius: AppRadius.rMd,
              border:
                  Border.all(color: active ? AppColors.navy : AppColors.border),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (active) ...[
                const Icon(Icons.check_rounded, size: 15, color: Colors.white),
                const SizedBox(width: 5),
              ],
              Text(opt[1],
                  style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                      color: active ? Colors.white : AppColors.textSecondary)),
            ]),
          ),
        );
      }).toList(),
    );
  }

  Widget _aboutRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Expanded(
          child: Text(label,
              style: GoogleFonts.inter(
                  fontSize: 13, color: AppColors.textSecondary)),
        ),
        Flexible(
          child: Text(value,
              textAlign: TextAlign.right,
              style: GoogleFonts.inter(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
        ),
      ]),
    );
  }
}

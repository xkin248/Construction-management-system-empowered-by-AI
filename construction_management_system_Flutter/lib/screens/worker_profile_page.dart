import 'package:flutter/material.dart';
import '../widgets/app_page_intro.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/api_service.dart';
import '../services/app_settings.dart';
import '../theme/app_theme.dart';
import '../widgets/worker_live_badge.dart';
import '../widgets/worker_ui.dart';
import 'login_page.dart';
import 'worker_notifications_page.dart';
import 'profile_page.dart';

/// Worker profile (spec A9).
///
/// Deliberately short: who am I, where do I work, what is my skill level, what
/// language do I read, my notifications, log out. Nothing else — a worker must
/// be able to find the one thing they came for in a single glance.
class WorkerProfilePage extends StatefulWidget {
  const WorkerProfilePage({super.key});

  @override
  State<WorkerProfilePage> createState() => _WorkerProfilePageState();
}

class _WorkerProfilePageState extends State<WorkerProfilePage> {
  bool _loading = true;
  bool _failed = false;

  String _name = '';
  String _phone = '';
  String _project = '';
  String _trade = '';
  int? _workerId;

  @override
  void initState() {
    super.initState();
    AppColors.darkMode.addListener(_rebuild);
    AppSettings.lang.addListener(_rebuild);
    _load();
  }

  @override
  void dispose() {
    AppColors.darkMode.removeListener(_rebuild);
    AppSettings.lang.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final me = await ApiService().me();
      final wid = me['worker_id'];
      _workerId = wid is num ? wid.toInt() : (me['id'] is num ? (me['id'] as num).toInt() : null);
      String project = '';
      String trade = '';
      if (_workerId != null) {
        try {
          final w = await ApiService().getWorker(_workerId!);
          trade = (w['trade'] ?? '').toString();
          final p = w['project'];
          if (p is Map) project = (p['project_name'] ?? '').toString();
        } catch (_) {
          // A missing worker row must not block the profile screen.
        }
      }
      if (!mounted) return;
      setState(() {
        _name = (me['full_name'] ?? me['name'] ?? '').toString();
        _phone = (me['phone'] ?? '').toString();
        _project = project;
        _trade = trade;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setLang(String code) async {
    AppSettings.lang.value = code;
    final sp = await SharedPreferences.getInstance();
    await sp.setString('app_lang', code);
    if (mounted) setState(() {});
  }

  Future<void> _logout() async {
    final sp = await SharedPreferences.getInstance();
    await sp.clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        AppPageIntro(
          icon: Icons.person_rounded,
          enTitle: 'MY DETAILS',
          msTitle: 'MAKLUMAT SAYA',
          zhTitle: '个人资料',
          enSubtitle: 'My site, skill and language',
          msSubtitle: 'Tapak, kemahiran dan bahasa',
          zhSubtitle: '我的工地、技能与语言',
          worker: true,
        ),
        const SizedBox(height: 14),
                WorkerLiveBadge(failed: _failed, loading: _loading, onRefresh: _load),
        const SizedBox(height: 14),
        _identityCard(),
        const SizedBox(height: 14),
        _rowsCard(),
        const SizedBox(height: 14),
        _lockedTradeCard(),
        const SizedBox(height: 14),
        _languageCard(),
        const SizedBox(height: 14),
        _actionsCard(),
      ],
    );
  }

  Widget _section({required String title, required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: AppRadius.rLg,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: GoogleFonts.inter(
                fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textMuted)),
        const SizedBox(height: 10),
        ...children,
      ]),
    );
  }

  Widget _identityCard() {
    final initials = _name.trim().isEmpty
        ? '?'
        : _name.trim().split(RegExp(r'\s+')).take(2).map((e) => e[0].toUpperCase()).join();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: AppRadius.rLg,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(children: [
        Container(
          width: 66,
          height: 66,
          decoration: BoxDecoration(color: AppColors.navy, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Text(initials,
              style: GoogleFonts.inter(
                  fontSize: 24, fontWeight: FontWeight.w900, color: AppColors.onAccent)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              _loading ? '…' : (_name.isEmpty ? '-' : _name),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                  fontSize: 21, fontWeight: FontWeight.w900, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 4),
            Text(
              _phone.isEmpty
                  ? wT(en: 'No phone', ms: 'Tiada telefon', zh: '未填电话')
                  : _phone,
              style: GoogleFonts.inter(fontSize: 16, color: AppColors.textSecondary),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _rowsCard() {
    return _section(title: wT(en: 'MY SITE', ms: 'TAPAK SAYA', zh: '我的项目'), children: [
      Row(children: [
        Icon(Icons.location_city_rounded, size: 26, color: AppColors.accentSolid),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            _project.isEmpty
                ? wT(en: 'Not assigned yet', ms: 'Belum ditugaskan', zh: '暂未分配')
                : _project,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
                fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
          ),
        ),
      ]),
    ]);
  }

  // ignore: unused_element
  Widget _tradeCard() {
    const levels = [
      ['general worker', 'General Worker', 'Pekerja Am', '普工'],
      ['semi skilled worker', 'Semi Skilled', 'Separa Mahir', '半熟练'],
      ['skilled worker', 'Skilled', 'Mahir', '熟练'],
      ['foreman', 'Foreman', 'Mandor', '工头'],
    ];
    final current = _trade.toLowerCase().trim();
    return _section(
      title: wT(en: 'MY SKILL LEVEL', ms: 'TAHAP KEMAHIRAN', zh: '我的工种等级'),
      children: [
        if (_trade.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              wT(en: 'Not set — ask your supervisor', ms: 'Belum ditetapkan', zh: '未设置，请联系监理'),
              style: GoogleFonts.inter(fontSize: 15, color: AppColors.textMuted),
            ),
          ),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final l in levels)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: current == l[0]
                    ? AppColors.accentSolid.withValues(alpha: 0.16)
                    : AppColors.bgMain,
                borderRadius: AppRadius.rPill,
                border: Border.all(
                  color: current == l[0] ? AppColors.accentSolid : AppColors.border,
                  width: current == l[0] ? 2 : 1,
                ),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(
                  current == l[0] ? Icons.verified_rounded : Icons.circle_outlined,
                  size: 18,
                  color: current == l[0] ? AppColors.accentSolid : AppColors.textMuted,
                ),
                const SizedBox(width: 6),
                Text(
                  wT(en: l[1], ms: l[2], zh: l[3]),
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: current == l[0] ? FontWeight.w900 : FontWeight.w600,
                    color: current == l[0] ? AppColors.accentSolid : AppColors.textSecondary,
                  ),
                ),
              ]),
            ),
        ]),
      ],
    );
  }

  /// A worker may see the skill level assigned by a supervisor, but cannot
  /// mistake the profile for a self-service level selector.
  Widget _lockedTradeCard() {
    return _section(
      title: wT(en: 'MY SKILL LEVEL', ms: 'TAHAP KEMAHIRAN', zh: '我的工种等级'),
      children: [
        Row(children: [
          Icon(Icons.lock_outline_rounded, size: 20, color: AppColors.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _trade.isEmpty
                  ? wT(en: 'Not set', ms: 'Belum ditetapkan', zh: '未设置')
                  : _trade,
              style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        Text(
          wT(
            en: 'Your supervisor assigns this level.',
            ms: 'Tahap ini ditetapkan oleh penyelia.',
            zh: '此等级由主管设定。',
          ),
          style: GoogleFonts.inter(fontSize: 12.5, color: AppColors.textMuted),
        ),
      ],
    );
  }

  Widget _languageCard() {
    const langs = [
      ['ms', 'BAHASA MELAYU'],
      ['en', 'ENGLISH'],
      ['zh', '中文'],
    ];
    final active = AppSettings.lang.value;
    return _section(
      title: wT(en: 'LANGUAGE', ms: 'BAHASA', zh: '语言'),
      children: [
        for (final l in langs)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _setLang(l[0]),
              child: Container(
                height: 60,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: active == l[0]
                      ? AppColors.accentSolid.withValues(alpha: 0.12)
                      : AppColors.bgMain,
                  borderRadius: AppRadius.rMd,
                  border: Border.all(
                    color: active == l[0] ? AppColors.accentSolid : AppColors.border,
                    width: active == l[0] ? 2 : 1,
                  ),
                ),
                child: Row(children: [
                  Icon(
                    active == l[0] ? Icons.radio_button_checked : Icons.radio_button_off,
                    size: 24,
                    color: active == l[0] ? AppColors.accentSolid : AppColors.textMuted,
                  ),
                  const SizedBox(width: 12),
                  Text('${l[1]}  ${l[0].toUpperCase()}',
                      style: GoogleFonts.inter(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary)),
                ]),
              ),
            ),
          ),
      ],
    );
  }

  Widget _actionsCard() {
    return Column(children: [
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const ProfilePage(),
        )),
        child: Container(
          height: kWPrimaryTap,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: AppRadius.rLg,
            border: Border.all(color: AppColors.border),
          ),
          child: Row(children: [
            Icon(Icons.person_outline_rounded, size: 28, color: AppColors.accentSolid),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                wT(en: 'MY PROFILE', ms: 'PROFIL SAYA', zh: '个人资料'),
                style: GoogleFonts.inter(
                    fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.textPrimary),
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 26, color: AppColors.textMuted),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const WorkerNotificationsPage(),
        )),
        child: Container(
          height: kWPrimaryTap,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: AppRadius.rLg,
            border: Border.all(color: AppColors.border),
          ),
          child: Row(children: [
            Icon(Icons.notifications_active_rounded, size: 28, color: AppColors.accentSolid),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                wT(en: 'NOTIFICATIONS', ms: 'PEMBERITAHUAN', zh: '通知'),
                style: GoogleFonts.inter(
                    fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.textPrimary),
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 26, color: AppColors.textMuted),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _logout,
        child: Container(
          height: kWPrimaryTap,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.red.withValues(alpha: 0.10),
            borderRadius: AppRadius.rLg,
            border: Border.all(color: AppColors.red, width: 2),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.logout_rounded, size: 26, color: AppColors.red),
            const SizedBox(width: 10),
            Text(
              wT(en: 'LOG OUT', ms: 'KELUAR', zh: '退出登录'),
              style: GoogleFonts.inter(
                  fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.red),
            ),
          ]),
        ),
      ),
    ]);
  }
}

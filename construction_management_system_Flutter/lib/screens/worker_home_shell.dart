import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import 'login_page.dart';
import 'worker_dashboard_page.dart';
import 'profile_page.dart';
import 'notifications_page.dart';
import '../services/app_settings.dart';
import '../widgets/app_settings_actions.dart';

// ──────────────── Nav model ────────────────
class _NavItem {
  final String label;
  final IconData icon;
  const _NavItem(this.label, this.icon);
}

/// Translate worker navigation labels (English / 中文 / Bahasa Melayu).
String _navT(String en) {
  const zh = {
    'My Dashboard': '我的仪表盘', 'My Attendance': '我的考勤', 'Notifications': '通知', 'Profile': '个人资料',
  };
  const ms = {
    'My Dashboard': 'Papan Pemuka Saya', 'My Attendance': 'Kehadiran Saya', 'Notifications': 'Notifikasi', 'Profile': 'Profil',
  };
  return AppSettings.t(en, zh[en], ms[en]);
}

const _workerMenu = [
  _NavItem('My Dashboard', Icons.grid_view_rounded),
  _NavItem('My Attendance', Icons.calendar_month_rounded),
  _NavItem('Notifications', Icons.notifications_outlined),
  _NavItem('Profile', Icons.person_outline_rounded),
];

final _workerPages = <Widget>[
  const WorkerDashboardPage(),
  const _WorkerAttendanceTab(),
  const NotificationsPage(),
  const ProfilePage(),
];

final _workerTitles = _workerMenu.map((e) => e.label).toList();

class WorkerHomeShell extends StatefulWidget {
  const WorkerHomeShell({super.key});
  @override
  State<WorkerHomeShell> createState() => _WorkerHomeShellState();
}

class _WorkerHomeShellState extends State<WorkerHomeShell> {
  int idx = 0;
  // Single IndexedStack instance keeps page state alive across navigation.
  final _pagesKey = GlobalKey();

  Future<void> _logout() async {
    final sp = await SharedPreferences.getInstance();
    await sp.clear();
    ApiService().ct();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
        context, MaterialPageRoute(builder: (_) => const LoginPage()), (_) => false);
  }

  void _go(int i) {
    setState(() => idx = i);
  }

  @override
  Widget build(BuildContext c) {
    return _NarrowLayout(
      pages: IndexedStack(key: _pagesKey, index: idx, children: _workerPages),
      idx: idx,
      onNav: _go,
      onLogout: _logout,
    );
  }
}

// ──────────────── Main (Bottom Nav) Layout ────────────────
class _NarrowLayout extends StatelessWidget {
  final Widget pages;
  final int idx;
  final ValueChanged<int> onNav;
  final VoidCallback onLogout;

  const _NarrowLayout({
    required this.pages,
    required this.idx,
    required this.onNav,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgMain,
      appBar: AppBar(
        backgroundColor: AppColors.bgCard,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(_navT(_workerTitles[idx]),
            style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
        actions: [
          const AppSettingsActions(),
          // Profile entry in the top-right corner (mobile-friendly replacement
          // for the removed sidebar / drawer profile entry).
          IconButton(
            icon: Icon(Icons.person_rounded, color: AppColors.textPrimary, size: 22),
            tooltip: _navT('Profile'),
            onPressed: () => onNav(3),
          ),
          IconButton(
            icon: Icon(Icons.power_settings_new_rounded, color: AppColors.red),
            tooltip: 'Log out',
            onPressed: onLogout,
          ),
        ],
      ),
      body: pages,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          border: Border(top: BorderSide(color: AppColors.border)),
          boxShadow: [BoxShadow(color: Color(0x0A000000), blurRadius: 12, offset: Offset(0, -2))],
        ),
        child: SafeArea(
          child: BottomNavigationBar(
            currentIndex: idx.clamp(0, _workerPages.length - 1),
            onTap: onNav,
            backgroundColor: AppColors.bgCard,
            selectedItemColor: AppColors.green,
            unselectedItemColor: AppColors.textMuted,
            type: BottomNavigationBarType.fixed,
            elevation: 0,
            items: _workerMenu
                .map((e) => BottomNavigationBarItem(
                      icon: Icon(e.icon),
                      label: _navT(e.label),
                      tooltip: _navT(e.label),
                    ))
                .toList(),
          ),
        ),
      ),
    );
  }
}

// ──────────────── Worker Attendance Tab (standalone page) ────────────────
class _WorkerAttendanceTab extends StatefulWidget {
  const _WorkerAttendanceTab();
  @override
  State<_WorkerAttendanceTab> createState() => _WorkerAttendanceTabState();
}

class _WorkerAttendanceTabState extends State<_WorkerAttendanceTab> {
  bool ld = true;
  Map? attendanceData;
  List history = [];

  @override
  void initState() {
    super.initState();
    AppColors.darkMode.addListener(_onDarkChanged);
    AppSettings.lang.addListener(_onLangChanged);
    _load();
  }

  void _onDarkChanged() {
    if (mounted) setState(() {});
  }

  void _onLangChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    AppColors.darkMode.removeListener(_onDarkChanged);
    AppSettings.lang.removeListener(_onLangChanged);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => ld = true);
    try {
      attendanceData = await ApiService().workerTodayAttendance();
    } catch (e) {
      toast('Failed to load attendance: $e');
    } finally {
      if (mounted) setState(() => ld = false);
    }
  }

  @override
  Widget build(BuildContext c) {
    if (ld) return const Center(child: CircularProgressIndicator());
    final att = attendanceData;
    final checkedIn = att?['checked_in'] ?? false;
    final checkedOut = att?['checked_out'] ?? false;
    final attRec = att?['attendance'] as Map?;
    final hours = att?['hours_today'] ?? 0;
    final windowEnabled = att?['window_enforced'] == true;
    final statusRaw = (attRec?['status'] ?? '').toString().toUpperCase();
    final statusNote = statusRaw == 'REJECTED'
        ? ' (Rejected: possibly outside the site GPS fence radius. Please move closer to the site and try again)'
        : '';

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(children: [
            Expanded(child: statCard(label: 'Today Status', value: checkedOut ? 'Checked Out' : checkedIn ? 'On Site' : 'Not Checked In',
                icon: checkedOut ? Icons.logout : checkedIn ? Icons.gps_fixed : Icons.punch_clock_outlined,
                iconColor: checkedOut ? AppColors.blue : checkedIn ? AppColors.green : AppColors.red)),
            const SizedBox(width: 12),
            Expanded(child: statCard(label: 'Hours Today', value: '${hours}h', icon: Icons.schedule_rounded, iconColor: AppColors.accent)),
          ]),
          const SizedBox(height: 16),
          sectionCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Today\'s Attendance Record',
                  style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              const SizedBox(height: 12),
              if (attRec == null)
                Text('No attendance record for today yet. Check in from the Dashboard.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 14))
              else ...[
                _row('Check In', _fmtTime(attRec['check_in_time']),
                    attRec['check_in_time'] != null ? AppColors.green : AppColors.textMuted),
                Divider(height: 16, color: AppColors.border),
                _row('Check Out', _fmtTime(attRec['check_out_time'] ?? attRec['checked_out_time']),
                    (attRec['check_out_time'] ?? attRec['checked_out_time']) != null ? AppColors.blue : AppColors.textMuted),
                Divider(height: 16, color: AppColors.border),
                _row('Status', statusRaw + statusNote,
                    checkedOut ? AppColors.blue : checkedIn ? AppColors.green : AppColors.red),
                if (attRec['device_info'] != null && attRec['device_info'].toString().isNotEmpty) ...[
                  Divider(height: 16, color: AppColors.border),
                  _row('Device', attRec['device_info'].toString().substring(0, attRec['device_info'].toString().length > 40 ? 40 : attRec['device_info'].toString().length),
                      AppColors.textSecondary),
                ],
                if (attRec['ip_address'] != null && attRec['ip_address'].toString().isNotEmpty) ...[
                  Divider(height: 16, color: AppColors.border),
                  _row('IP Address', attRec['ip_address'].toString(), AppColors.textSecondary),
                ],
              ]
            ]),
          ),
          const SizedBox(height: 16),
          sectionCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('⏰ Check-in Windows',
                  style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              const SizedBox(height: 8),
              if (!windowEnabled) ...[
                _row('Check In', 'Anytime', AppColors.green),
                const SizedBox(height: 6),
                _row('Check Out', 'Anytime', AppColors.blue),
                const SizedBox(height: 6),
                Text('Clock-in is allowed at any time (time window restrictions removed)',
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
              ] else ...[
                _row('Check In', att?['check_in_window'] ?? '08:00 - 10:30', AppColors.green),
                const SizedBox(height: 6),
                _row('Check Out', att?['check_out_window'] ?? '15:00 - 17:00', AppColors.blue),
              ],
            ]),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, Color color) => Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: TextStyle(fontSize: 14, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
        Text(value, style: TextStyle(fontSize: 14, color: color, fontWeight: FontWeight.w700)),
      ]);

  /// Extract HH:mm from backend time strings without crashing on short /
  /// unexpected formats (ISO "2026-08-23T19:29:58+08:00" or "19:29:58").
  String _fmtTime(Object? v) {
    if (v == null) return '—';
    final s = v.toString();
    if (s.length >= 16) return s.substring(11, 16);
    if (s.length >= 5) return s.substring(0, 5);
    return s;
  }
}

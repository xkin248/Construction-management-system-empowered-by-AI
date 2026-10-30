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
import '../l10n/app_strings.dart';
import '../widgets/app_settings_actions.dart';
import '../widgets/guided_empty_state.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/failure_state.dart';
import 'worker_tasks_page.dart';

// ──────────────── Nav model ────────────────
class _NavItem {
  final String labelKey; // key in app_strings (en / zh / ms)
  final IconData icon;
  final IconData activeIcon;
  const _NavItem(this.labelKey, this.icon, this.activeIcon);
}

/// Worker tabs — kept at five so every entry keeps a comfortable tap target
/// on a phone. "Tasks" is now a first-class entry (it used to be buried in the
/// dashboard), and Profile lives here instead of a second AppBar icon.
const _workerMenu = [
  _NavItem('wnav.dashboard', Icons.home_outlined, Icons.home_rounded),
  _NavItem('wnav.tasks', Icons.assignment_outlined, Icons.assignment_rounded),
  _NavItem('wnav.attendance', Icons.fact_check_outlined, Icons.fact_check_rounded),
  _NavItem('wnav.alerts', Icons.notifications_outlined, Icons.notifications_rounded),
  _NavItem('wnav.profile', Icons.person_outline_rounded, Icons.person_rounded),
];

/// Index of each tab, so dashboard shortcuts do not hard-code numbers.
const int kWorkerTabHome = 0;
const int kWorkerTabTasks = 1;
const int kWorkerTabAttendance = 2;
const int kWorkerTabAlerts = 3;
const int kWorkerTabProfile = 4;

class WorkerHomeShell extends StatefulWidget {
  const WorkerHomeShell({super.key});
  @override
  State<WorkerHomeShell> createState() => _WorkerHomeShellState();
}

class _WorkerHomeShellState extends State<WorkerHomeShell> {
  int idx = kWorkerTabHome;

  /// Sub-tab requested for the Alerts page (0 = notifications, 1 = issues).
  /// The dashboard "report a problem" shortcut jumps straight to the issue
  /// form; the key below is what forces the page to honour it.
  int _notifTab = 0;

  @override
  void initState() {
    super.initState();
    // The AppBar title and the bottom-navigation labels are resolved from the
    // active language inside build(), so the shell must rebuild whenever the
    // language (or theme) changes — otherwise they stay in the old language.
    AppSettings.lang.addListener(_onSettingsChanged);
    AppColors.darkMode.addListener(_onSettingsChanged);
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    AppSettings.lang.removeListener(_onSettingsChanged);
    AppColors.darkMode.removeListener(_onSettingsChanged);
    super.dispose();
  }

  Future<void> _logout() async {
    final sp = await SharedPreferences.getInstance();
    await sp.clear();
    ApiService().ct();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
        context, MaterialPageRoute(builder: (_) => const LoginPage()), (_) => false);
  }

  void _go(int i, [int subTab = 0]) {
    setState(() {
      idx = i;
      if (i == kWorkerTabAlerts) _notifTab = subTab;
    });
  }

  /// Pages are rebuilt on every build so the dashboard can drive navigation
  /// and the alerts tab can honour a requested sub-tab.
  List<Widget> _buildPages() => [
        WorkerDashboardPage(onNavigate: _go),
        const WorkerTasksPage(),
        _WorkerAttendanceTab(onGoHome: () => _go(kWorkerTabHome)),
        // Notifications lives inside this shell so the bottom navigation (and
        // its tap targets) stay in place — no full-screen second-level page
        // where a tap aimed at the nav bar would hit a list row instead.
        NotificationsPage(
          key: ValueKey('worker-notif-$_notifTab'),
          embedded: true,
          initialTab: _notifTab,
        ),
        const ProfilePage(),
      ];

  @override
  Widget build(BuildContext c) {
    return _NarrowLayout(
      pages: IndexedStack(index: idx, children: _buildPages()),
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
  final void Function(int index, [int subTab]) onNav;
  final VoidCallback onLogout;

  const _NarrowLayout({
    required this.pages,
    required this.idx,
    required this.onNav,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final title = AppStrings.t(_workerMenu[idx.clamp(0, _workerMenu.length - 1)].labelKey);
    return Scaffold(
      backgroundColor: AppColors.bgMain,
      appBar: AppBar(
        backgroundColor: AppColors.bgCard,
        elevation: 0,
        surfaceTintColor: AppColors.transparent,
        title: Text(title,
            style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
        actions: [
          const AppSettingsActions(),
          IconButton(
            icon: Icon(Icons.power_settings_new_rounded, color: AppColors.red),
            tooltip: AppStrings.t('profile.logout'),
            onPressed: onLogout,
          ),
        ],
      ),
      body: pages,
      // Floating rounded nav bar (Bento style). The bottom inset is owned by
      // SafeArea inside the bar, and the outer padding keeps a 10px gap from
      // the screen edge. Navigation behaviour itself is untouched.
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: AppRadius.rLg,
            border: Border.all(color: AppColors.border),
            boxShadow: AppShadows.md,
          ),
          child: ClipRRect(
            borderRadius: AppRadius.rLg,
            child: SafeArea(
              top: false,
              child: BottomNavigationBar(
                currentIndex: idx.clamp(0, _workerMenu.length - 1),
                onTap: (i) => onNav(i),
                backgroundColor: AppColors.transparent,
                selectedItemColor: AppColors.accent,
                unselectedItemColor: AppColors.textMuted,
                type: BottomNavigationBarType.fixed,
                elevation: 0,
                selectedFontSize: 11,
                unselectedFontSize: 11,
                items: _workerMenu
                    .map((e) => BottomNavigationBarItem(
                          icon: Icon(e.icon),
                          activeIcon: Icon(e.activeIcon),
                          label: AppStrings.t(e.labelKey),
                          tooltip: AppStrings.t(e.labelKey),
                        ))
                    .toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ──────────────── Worker Attendance Tab (standalone page) ────────────────
class _WorkerAttendanceTab extends StatefulWidget {
  /// Jump back to the dashboard (where the check-in button lives) when there
  /// is no record for today yet.
  final VoidCallback? onGoHome;
  const _WorkerAttendanceTab({this.onGoHome});
  @override
  State<_WorkerAttendanceTab> createState() => _WorkerAttendanceTabState();
}

class _WorkerAttendanceTabState extends State<_WorkerAttendanceTab> {
  bool ld = true;
  Object? _attError;
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
      _attError = null;
    } catch (e) {
      _attError = e;
      toast('Failed to load attendance: $e');
    } finally {
      if (mounted) setState(() => ld = false);
    }
  }

  @override
  Widget build(BuildContext c) {
    if (ld) return const SkeletonDetail();
    if (_attError != null && attendanceData == null) {
      return FailureState(error: _attError, onRetry: _load);
    }
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
                  style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              const SizedBox(height: 12),
              if (attRec == null)
                GuidedEmptyState(
                  compact: true,
                  icon: Icons.punch_clock_outlined,
                  title: AppStrings.t('worker.emptyAttTitle'),
                  description: AppStrings.t('worker.emptyAttDesc'),
                  primaryLabel: AppStrings.t('worker.emptyAttAction'),
                  primaryIcon: Icons.home_rounded,
                  onPrimary: () => widget.onGoHome?.call(),
                )
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
                  style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              const SizedBox(height: 8),
              if (!windowEnabled) ...[
                _row('Check In', 'Anytime', AppColors.green),
                const SizedBox(height: 8),
                _row('Check Out', 'Anytime', AppColors.blue),
                const SizedBox(height: 8),
                Text('Clock-in is allowed at any time (time window restrictions removed)',
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
              ] else ...[
                _row('Check In', att?['check_in_window'] ?? '08:00 - 10:30', AppColors.green),
                const SizedBox(height: 8),
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

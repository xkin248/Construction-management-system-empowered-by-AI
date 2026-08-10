import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import 'login_page.dart';
import 'worker_dashboard_page.dart';
import 'profile_page.dart';

// ──────────────── Nav model ────────────────
class _NavItem {
  final String label;
  final IconData icon;
  const _NavItem(this.label, this.icon);
}

const _workerMenu = [
  _NavItem('My Dashboard', Icons.grid_view_rounded),
  _NavItem('My Attendance', Icons.calendar_month_rounded),
  _NavItem('Profile', Icons.person_outline_rounded),
];

final _workerPages = <Widget>[
  const WorkerDashboardPage(),
  const _WorkerAttendanceTab(),
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
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  Future<void> _logout() async {
    final sp = await SharedPreferences.getInstance();
    await sp.clear();
    ApiService().ct();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
        context, MaterialPageRoute(builder: (_) => const LoginPage()), (_) => false);
  }

  void _go(int i, {bool fromDrawer = false}) {
    if (fromDrawer) Navigator.pop(context);
    setState(() => idx = i);
  }

  @override
  Widget build(BuildContext c) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final isWide = constraints.maxWidth >= 700;
        if (isWide) {
          return _WideLayout(
            idx: idx,
            onNav: (i) => _go(i),
            onLogout: _logout,
          );
        }
        return _NarrowLayout(
          scaffoldKey: _scaffoldKey,
          idx: idx,
          onNav: _go,
          onLogout: _logout,
        );
      },
    );
  }
}

// ──────────────── Wide (Sidebar) Layout ────────────────
class _WideLayout extends StatelessWidget {
  final int idx;
  final ValueChanged<int> onNav;
  final VoidCallback onLogout;

  const _WideLayout({
    required this.idx,
    required this.onNav,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          _WorkerSidebar(idx: idx, onNav: onNav, onLogout: onLogout),
          Expanded(
            child: Column(
              children: [
                _WorkerTopBar(title: _workerTitles[idx]),
                Expanded(child: IndexedStack(index: idx, children: _workerPages)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────── Narrow (Bottom Nav) Layout ────────────────
class _NarrowLayout extends StatelessWidget {
  final GlobalKey<ScaffoldState> scaffoldKey;
  final int idx;
  final ValueChanged<int> onNav;
  final VoidCallback onLogout;

  const _NarrowLayout({
    required this.scaffoldKey,
    required this.idx,
    required this.onNav,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: scaffoldKey,
      backgroundColor: AppColors.bgMain,
      appBar: AppBar(
        backgroundColor: AppColors.bgCard,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded, color: AppColors.textPrimary),
          onPressed: () => scaffoldKey.currentState?.openDrawer(),
        ),
        title: Text(_workerTitles[idx],
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.power_settings_new_rounded, color: AppColors.red),
            tooltip: 'Log out',
            onPressed: onLogout,
          ),
        ],
      ),
      drawer: Drawer(
        backgroundColor: AppColors.sidebarBg,
        width: AppColors.sidebarWidth,
        child: _WorkerSidebarContent(
          idx: idx,
          // Close the drawer then navigate
          onNav: (i) {
            scaffoldKey.currentState?.closeDrawer();
            onNav(i);
          },
          onLogout: onLogout,
        ),
      ),
      body: IndexedStack(index: idx, children: _workerPages),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
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
                .map((e) => BottomNavigationBarItem(icon: Icon(e.icon), label: e.label))
                .toList(),
          ),
        ),
      ),
    );
  }
}

// ──────────────── Sidebar (permanent) ────────────────
class _WorkerSidebar extends StatelessWidget {
  final int idx;
  final ValueChanged<int> onNav;
  final VoidCallback onLogout;

  const _WorkerSidebar({required this.idx, required this.onNav, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: AppColors.sidebarWidth,
      child: Material(
        color: AppColors.sidebarBg,
        child: _WorkerSidebarContent(idx: idx, onNav: onNav, onLogout: onLogout),
      ),
    );
  }
}

class _WorkerSidebarContent extends StatelessWidget {
  final int idx;
  final ValueChanged<int> onNav;
  final VoidCallback onLogout;

  const _WorkerSidebarContent({required this.idx, required this.onNav, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 12),
            child: Row(children: [
              Container(
                width: 38, height: 38,
                decoration: BoxDecoration(color: AppColors.green, borderRadius: BorderRadius.circular(10)),
                child: const Center(child: Icon(Icons.badge_rounded, color: Colors.white, size: 20)),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('BuildSmart',
                      style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                  Text('Worker Portal',
                      style: GoogleFonts.outfit(color: AppColors.textSidebarMuted, fontSize: 10.5)),
                ]),
              ),
            ]),
          ),
          Container(height: 1, color: AppColors.sidebarHover),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 14, 10, 4),
                  child: Text('WORKER MENU',
                      style: GoogleFonts.outfit(
                          color: AppColors.textSidebarMuted,
                          fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
                ),
                ..._workerMenu.asMap().entries.map((e) => _WorkerNavTile(
                      item: e.value,
                      selected: e.key == idx,
                      onTap: () => onNav(e.key),
                    )),
              ],
            ),
          ),
          Container(height: 1, color: AppColors.sidebarHover),
          Padding(
            padding: const EdgeInsets.all(14),
            child: FutureBuilder<Map>(
              future: ApiService().me(),
              builder: (ctx, snap) {
                final name = (snap.data?['name'] as String?) ?? '...';
                final role = (snap.data?['role'] as String?) ?? 'worker';
                return Row(children: [
                  initialsAvatar(name.isNotEmpty ? name : '?', radius: 16),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(name,
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.outfit(
                              color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12.5)),
                      Text(role.replaceAll('_', ' '),
                          style: GoogleFonts.outfit(
                              color: AppColors.textSidebarMuted, fontSize: 10.5)),
                    ]),
                  ),
                  IconButton(
                    icon: const Icon(Icons.power_settings_new_rounded, color: AppColors.red, size: 19),
                    tooltip: 'Log out',
                    onPressed: onLogout,
                  ),
                ]);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkerNavTile extends StatelessWidget {
  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;

  const _WorkerNavTile({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? AppColors.green : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          hoverColor: selected ? Colors.transparent : AppColors.sidebarHover,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(children: [
              Icon(item.icon, size: 18, color: selected ? Colors.white : AppColors.textSidebar),
              const SizedBox(width: 12),
              Expanded(
                child: Text(item.label,
                    style: GoogleFonts.outfit(
                        color: selected ? Colors.white : AppColors.textSidebar,
                        fontSize: 13.5, fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ──────────────── Top Bar ────────────────
class _WorkerTopBar extends StatelessWidget {
  final String title;
  const _WorkerTopBar({required this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: AppColors.bgCard,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(children: [
        Expanded(
          child: Text(title,
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        ),
        IconButton(
          icon: const Icon(Icons.info_outline, color: AppColors.textSecondary, size: 20),
          tooltip: 'About Worker Portal',
          onPressed: () {
            showDialog(context: context, builder: (_) => AlertDialog(
              title: const Text('Worker Portal'),
              content: const Text('This is the dedicated portal for construction workers. Use the Dashboard to check in and see your AI-assigned tasks.'),
              actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
            ));
          },
        ),
      ]),
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
    _load();
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
                const Text('No attendance record for today yet. Check in from the Dashboard.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12.5))
              else ...[
                _row('Check In', attRec['check_in_time']?.toString().substring(11, 16) ?? '—',
                    attRec['check_in_time'] != null ? AppColors.green : AppColors.textMuted),
                const Divider(height: 16, color: AppColors.border),
                _row('Check Out', attRec['check_out_time']?.toString().substring(11, 16) ?? '—',
                    attRec['check_out_time'] != null ? AppColors.blue : AppColors.textMuted),
                const Divider(height: 16, color: AppColors.border),
                _row('Status', (attRec['status'] ?? '—').toString().toUpperCase(),
                    checkedIn ? AppColors.green : checkedOut ? AppColors.blue : AppColors.red),
                if (attRec['device_info'] != null && attRec['device_info'].toString().isNotEmpty) ...[
                  const Divider(height: 16, color: AppColors.border),
                  _row('Device', attRec['device_info'].toString().substring(0, attRec['device_info'].toString().length > 40 ? 40 : attRec['device_info'].toString().length),
                      AppColors.textSecondary),
                ],
                if (attRec['ip_address'] != null && attRec['ip_address'].toString().isNotEmpty) ...[
                  const Divider(height: 16, color: AppColors.border),
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
              _row('Check In', att?['check_in_window'] ?? '05:00 - 10:30', AppColors.green),
              const SizedBox(height: 6),
              _row('Check Out', att?['check_out_window'] ?? '15:00 - 21:00', AppColors.blue),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, Color color) => Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
        Text(value, style: TextStyle(fontSize: 12.5, color: color, fontWeight: FontWeight.w700)),
      ]);
}

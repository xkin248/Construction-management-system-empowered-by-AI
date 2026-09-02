import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';
import '../services/api_service.dart';
import 'login_page.dart';
import 'dashboard_page.dart';
import 'projects_page.dart';
import 'tasks_page.dart';
import 'attendance_page.dart';
import 'workers_page.dart';
import 'files_page.dart';
import 'notifications_page.dart';
import 'profile_page.dart';
import '../services/app_settings.dart';
import '../widgets/app_settings_actions.dart';
import 'worker_home_shell.dart';

// ──────────────── Nav model ────────────────
class _NavItem {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  const _NavItem(this.label, this.icon, [IconData? active])
      : activeIcon = active ?? icon;
}

/// Translate navigation labels (English / 中文 / Bahasa Melayu).
String _navT(String en) {
  const zh = {
    'Dashboard': '仪表盘', 'Projects': '项目', 'Tasks': '任务', 'Attendance': '考勤',
    'Workers': '工人', 'Files': '文件', 'Notifications': '通知', 'More': '更多',
    'My Dashboard': '我的仪表盘', 'My Attendance': '我的考勤', 'Profile': '个人资料',
  };
  const ms = {
    'Dashboard': 'Papan Pemuka', 'Projects': 'Projek', 'Tasks': 'Tugas', 'Attendance': 'Kehadiran',
    'Workers': 'Pekerja', 'Files': 'Fail', 'Notifications': 'Notifikasi', 'More': 'Lagi',
    'My Dashboard': 'Papan Pemuka Saya', 'My Attendance': 'Kehadiran Saya', 'Profile': 'Profil',
  };
  return AppSettings.t(en, zh[en], ms[en]);
}

const _bottomNavItems = [
  _NavItem('Dashboard', Icons.grid_view_outlined, Icons.grid_view_rounded),
  _NavItem('Projects', Icons.apartment_outlined, Icons.apartment_rounded),
  _NavItem('Tasks', Icons.check_circle_outline_rounded, Icons.check_circle_rounded),
  _NavItem('Workers', Icons.badge_outlined, Icons.badge_rounded),
  _NavItem('Files', Icons.folder_outlined, Icons.folder_rounded),
];

const _mainMenu = [
  _NavItem('Dashboard', Icons.grid_view_rounded),
  _NavItem('Projects', Icons.apartment_rounded),
  _NavItem('Tasks', Icons.check_circle_outline_rounded),
  _NavItem('Attendance', Icons.calendar_month_rounded),
  _NavItem('Workers', Icons.badge_outlined),
  _NavItem('Files', Icons.folder_outlined, Icons.folder_rounded),
  _NavItem('Notifications', Icons.notifications_outlined, Icons.notifications_rounded),
];

final _pages = <Widget>[
  const DashboardPage(),   // 0 Dashboard
  const ProjectsPage(),    // 1 Projects
  const TasksPage(),       // 2 Tasks
  const AttendancePage(),  // 3 Attendance
  const WorkersPage(),     // 4 Workers
  const FilesPage(),       // 5 Files
  const NotificationsPage(), // 6 Notifications
];

final _titles = _mainMenu.map((e) => e.label).toList();

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int idx = 0;
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  // Shared across wide/narrow layouts so page states survive breakpoint
  // switches (rotation / resize / split-screen) instead of being recreated.
  final _pagesKey = GlobalKey();
  String _currentProject = '';
  Map<String, dynamic> _user = {};
  bool _userLoaded = false;

  @override
  void initState() {
    super.initState();
    AppColors.darkMode.addListener(_onDarkChanged);
    AppSettings.lang.addListener(_onLangChanged);
    _guardWorkerEntry();
    _loadUser();
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

  /// Role guard: worker accounts must never enter the supervisor HomeShell.
  /// Redirects immediately to WorkerHomeShell and fixes stale cached role.
  Future<void> _guardWorkerEntry() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final cachedType = sp.getString('user_type') ?? '';
      final cachedRole = sp.getString('user_role') ?? '';
      if (cachedType.toLowerCase() == 'worker' || cachedRole.toLowerCase() == 'worker') {
        if (mounted) {
          Navigator.pushAndRemoveUntil(
              context, MaterialPageRoute(builder: (_) => const WorkerHomeShell()), (_) => false);
        }
      }
    } catch (_) {}
  }

  Future<void> _loadUser() async {
    try {
      final data = await ApiService().me();
      final t = (data['user_type'] ?? '').toString().toLowerCase();
      final r = (data['role'] ?? '').toString().toLowerCase();
      if (t == 'worker' || r == 'worker') {
        final sp = await SharedPreferences.getInstance();
        await sp.setString('user_type', 'worker');
        await sp.setString('user_role', 'worker');
        if (mounted) {
          Navigator.pushAndRemoveUntil(
              context, MaterialPageRoute(builder: (_) => const WorkerHomeShell()), (_) => false);
        }
        return;
      }
      if (mounted) setState(() { _user = Map<String, dynamic>.from(data); _userLoaded = true; });
    } catch (_) {
      if (mounted) setState(() => _userLoaded = true);
    }
  }

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
        final isWide = constraints.maxWidth >= AppBreakpoints.navigation;
        // Single IndexedStack instance shared by both layouts: keeps page
        // state (filters, scroll positions, loaded data) across breakpoint
        // switches and avoids rebuilding + re-fetching on rotation/resize.
        final pages = IndexedStack(key: _pagesKey, index: idx, children: _pages);
        if (isWide) {
          return _WideLayout(
            pages: pages,
            idx: idx,
            currentProject: _currentProject,
            user: _user,
            onNav: (i) => _go(i),
            onLogout: _logout,
            onProjectChanged: (p) => setState(() => _currentProject = p),
          );
        }
        return _NarrowLayout(
          pages: pages,
          scaffoldKey: _scaffoldKey,
          idx: idx,
          currentProject: _currentProject,
          user: _user,
          userLoaded: _userLoaded,
          onNav: (i) => _go(i),
          onLogout: _logout,
          onProjectChanged: (p) => setState(() => _currentProject = p),
        );
      },
    );
  }
}

// ──────────────── Wide (Sidebar) Layout ────────────────
class _WideLayout extends StatelessWidget {
  final Widget pages;
  final int idx;
  final String currentProject;
  final Map<String, dynamic> user;
  final ValueChanged<int> onNav;
  final VoidCallback onLogout;
  final ValueChanged<String> onProjectChanged;

  const _WideLayout({
    required this.pages,
    required this.idx,
    required this.currentProject,
    required this.user,
    required this.onNav,
    required this.onLogout,
    required this.onProjectChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          _Sidebar(idx: idx, user: user, onNav: onNav, onLogout: onLogout),
          Expanded(
            child: Column(
              children: [
                _TopBar(
                  title: _titles[idx],
                  currentProject: currentProject,
                  user: user,
                  onProjectChanged: onProjectChanged,
                ),
                Expanded(child: pages),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────── Narrow (Bottom Nav) Layout ─────────
class _NarrowLayout extends StatelessWidget {
  final Widget pages;
  final GlobalKey<ScaffoldState> scaffoldKey;
  final int idx;
  final String currentProject;
  final Map<String, dynamic> user;
  final bool userLoaded;
  final ValueChanged<int> onNav;
  final VoidCallback onLogout;
  final ValueChanged<String> onProjectChanged;

  const _NarrowLayout({
    required this.pages,
    required this.scaffoldKey,
    required this.idx,
    required this.currentProject,
    required this.user,
    required this.userLoaded,
    required this.onNav,
    required this.onLogout,
    required this.onProjectChanged,
  });

  // Map bottom nav index → page index
  int _bottomToPageIdx(int bottomIdx) {
    const map = [0, 1, 2, 4, 5]; // Dashboard, Projects, Tasks, Workers, Files
    return map[bottomIdx];
  }

  int _pageToBottomIdx(int pageIdx) {
    if (pageIdx <= 2) return pageIdx; // Dashboard(0) / Projects(1) / Tasks(2)
    if (pageIdx == 4) return 3;       // Workers → bottom nav index 3
    if (pageIdx == 5) return 4;       // Files → bottom nav index 4
    return -1; // Attendance(3) / Notifications(6) are not in the bottom nav (kept in wide sidebar / More menu)
  }

  @override
  Widget build(BuildContext context) {
    final userName = (user['full_name'] as String?) ?? '';
    final initStr = userName.isNotEmpty ? initials(userName) : '?';

    return Scaffold(
      key: scaffoldKey,
      backgroundColor: AppColors.bgMain,
      appBar: AppBar(
        backgroundColor: AppColors.bgCard,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        title: Row(children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(7)),
            child: const Center(child: Icon(Icons.construction_rounded, color: Colors.white, size: 15)),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('BuildSmart',
                style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            Text(_navT(_titles[idx.clamp(0, _titles.length - 1)]),
                style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textMuted)),
          ]),
        ]),
        actions: [
          const AppSettingsActions(),
          Stack(children: [
            IconButton(
              icon: Icon(Icons.notifications_outlined, color: AppColors.textSecondary),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsPage())),
            ),
            Positioned(
              right: 8, top: 8,
              child: Container(width: 8, height: 8,
                  decoration: BoxDecoration(color: AppColors.red, shape: BoxShape.circle)),
            ),
          ]),
          GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfilePage())),
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: userLoaded
                  ? CircleAvatar(
                      radius: 16,
                      backgroundColor: avatarColor(userName.isNotEmpty ? userName : 'U'),
                      child: Text(initStr,
                          style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                    )
                  : CircleAvatar(
                      radius: 16,
                      backgroundColor: AppColors.sidebarHover,
                      child: SizedBox(width: 12, height: 12,
                          child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.accent)),
                    ),
            ),
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
          child: SizedBox(
            height: 68,
            child: Row(
              children: List.generate(_bottomNavItems.length, (i) {
                final item = _bottomNavItems[i];
                final isSelected = _pageToBottomIdx(idx) == i;
                return Expanded(
                  child: _BottomNavBtn(
                    item: item,
                    selected: isSelected,
                    onTap: () => onNav(_bottomToPageIdx(i)),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

// ──────────────── Bottom Nav Button ──────────────────
class _BottomNavBtn extends StatelessWidget {
  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;
  const _BottomNavBtn({required this.item, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: _navT(item.label),
      child: InkWell(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Icon(
              selected ? item.activeIcon : item.icon,
              key: ValueKey(selected),
              size: 22,
              color: selected ? AppColors.accent : AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              _navT(item.label),
              maxLines: 1,
              style: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? AppColors.accent : AppColors.textMuted,
              ),
            ),
          ),
        ]),
      ),
      ),
    );
  }
}

// ──────────────── Sidebar (permanent) ────────────────
class _Sidebar extends StatelessWidget {
  final int idx;
  final Map<String, dynamic> user;
  final ValueChanged<int> onNav;
  final VoidCallback onLogout;

  const _Sidebar({required this.idx, required this.user, required this.onNav, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: AppColors.sidebarWidth,
      child: Material(
        color: AppColors.sidebarBg,
        child: _SidebarContent(idx: idx, user: user, onNav: onNav, onLogout: onLogout),
      ),
    );
  }
}

class _SidebarContent extends StatelessWidget {
  final int idx;
  final Map<String, dynamic> user;
  final ValueChanged<int> onNav;
  final VoidCallback onLogout;

  const _SidebarContent({required this.idx, required this.user, required this.onNav, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    final userName = (user['full_name'] as String?) ?? '...';
    final role = (user['role'] as String?) ?? '';

    return SafeArea(
      child: Column(
        children: [
          // Logo
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 12),
            child: Row(children: [
              Container(
                width: 38, height: 38,
                decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(10)),
                child: const Center(child: Icon(Icons.construction_rounded, color: Colors.white, size: 20)),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('BuildSmart',
                      style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                  Text('AI Construction System',
                      style: GoogleFonts.outfit(color: AppColors.textSidebarMuted, fontSize: 14)),
                ]),
              ),
            ]),
          ),
          Container(height: 1, color: AppColors.sidebarHover),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              children: [
                _sectionLabel('MAIN MENU'),
                ..._mainMenu.asMap().entries.map((e) => _NavTile(
                      item: e.value,
                      selected: e.key == idx,
                      onTap: () => onNav(e.key),
                      showNotificationBadge: e.value.label == 'Notifications',
                    )),
              ],
            ),
          ),
          Container(height: 1, color: AppColors.sidebarHover),
          // User row
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              initialsAvatar(userName.isNotEmpty ? userName : '?', radius: 16),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(userName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                          color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                  Text(role.replaceAll('_', ' '),
                      style: GoogleFonts.outfit(
                          color: AppColors.textSidebarMuted, fontSize: 14)),
                ]),
              ),
              IconButton(
                icon: Icon(Icons.power_settings_new_rounded, color: AppColors.red, size: 19),
                tooltip: 'Log out',
                onPressed: onLogout,
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String s) => Padding(
        padding: const EdgeInsets.fromLTRB(10, 14, 10, 4),
        child: Text(s,
            style: GoogleFonts.outfit(
                color: AppColors.textSidebarMuted,
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8)),
      );
}

class _NavTile extends StatelessWidget {
  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;
  final bool showNotificationBadge;

  const _NavTile({
    required this.item,
    required this.selected,
    required this.onTap,
    this.showNotificationBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? AppColors.accent : Colors.transparent,
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
                child: Text(_navT(item.label),
                    style: GoogleFonts.outfit(
                        color: selected ? Colors.white : AppColors.textSidebar,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600)),
              ),
              if (showNotificationBadge)
                Container(
                  width: 8, height: 8,
                  margin: const EdgeInsets.only(left: 2),
                  decoration: BoxDecoration(color: AppColors.red, shape: BoxShape.circle),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ──────────────── Top Bar ────────────────
class _TopBar extends StatelessWidget {
  final String title;
  final String currentProject;
  final Map<String, dynamic> user;
  final ValueChanged<String> onProjectChanged;

  const _TopBar({
    required this.title,
    required this.currentProject,
    required this.user,
    required this.onProjectChanged,
  });

  @override
  Widget build(BuildContext context) {
    final userName = (user['full_name'] as String?) ?? '';
    final initStr = userName.isNotEmpty ? initials(userName) : '?';

    return Container(
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(children: [
        Expanded(
          child: Text(_navT(title),
              style: GoogleFonts.outfit(
                  fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        ),
        SizedBox(
          width: 220, height: 38,
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Search projects, workers...',
              hintStyle: GoogleFonts.outfit(fontSize: 14, color: AppColors.textMuted),
              prefixIcon: Icon(Icons.search_rounded, size: 18, color: AppColors.textMuted),
              filled: true,
              fillColor: AppColors.bgMain,
              contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 14),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppColors.border)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppColors.border)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppColors.accent, width: 1.4)),
            ),
          ),
        ),
        const SizedBox(width: 12),
        _ProjectChip(currentProject: currentProject, onChanged: onProjectChanged),
        const SizedBox(width: 12),
        const AppSettingsActions(),
        Stack(children: [
          IconButton(
            icon: Icon(Icons.notifications_outlined, color: AppColors.textSecondary, size: 22),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsPage())),
          ),
          Positioned(
            right: 8, top: 8,
            child: Container(width: 8, height: 8,
                decoration: BoxDecoration(color: AppColors.red, shape: BoxShape.circle)),
          ),
        ]),
        GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfilePage())),
          child: CircleAvatar(
            radius: 17,
            backgroundColor: userName.isNotEmpty ? avatarColor(userName) : AppColors.accent,
            child: Text(initStr,
                style: GoogleFonts.outfit(
                    color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
          ),
        ),
      ]),
    );
  }
}

class _ProjectChip extends StatefulWidget {
  final String currentProject;
  final ValueChanged<String> onChanged;
  const _ProjectChip({required this.currentProject, required this.onChanged});
  @override
  State<_ProjectChip> createState() => _ProjectChipState();
}

class _ProjectChipState extends State<_ProjectChip> {
  final _projects = ['KL Tower Block A', 'PJ Residential Complex', 'Penang Bridge', 'Iskandar Puteri Hub'];

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: widget.onChanged,
      itemBuilder: (_) => _projects.map((p) => PopupMenuItem(value: p, child: Text(p))).toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.location_on_rounded, size: 14, color: AppColors.accent),
          const SizedBox(width: 5),
          Text(widget.currentProject.isEmpty ? 'All Projects' : widget.currentProject,
              style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          const SizedBox(width: 4),
          Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: AppColors.textMuted),
        ]),
      ),
    );
  }
}

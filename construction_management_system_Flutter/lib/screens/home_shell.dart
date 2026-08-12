import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import 'login_page.dart';
import 'dashboard_page.dart';
import 'projects_page.dart';
import 'tasks_page.dart';
import 'attendance_page.dart';
import 'workers_page.dart';
import 'files_page.dart';
import 'ai_chat_page.dart';
import 'notifications_page.dart';
import 'settings_page.dart';
import 'profile_page.dart';

// ──────────────── Nav model ────────────────
class _NavItem {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  const _NavItem(this.label, this.icon, [IconData? active])
      : activeIcon = active ?? icon;
}

const _bottomNavItems = [
  _NavItem('Dashboard', Icons.grid_view_outlined, Icons.grid_view_rounded),
  _NavItem('Projects', Icons.apartment_outlined, Icons.apartment_rounded),
  _NavItem('Tasks', Icons.check_circle_outline_rounded, Icons.check_circle_rounded),
  _NavItem('Attendance', Icons.calendar_month_outlined, Icons.calendar_month_rounded),
  _NavItem('More', Icons.apps_outlined, Icons.apps_rounded),
];

const _mainMenu = [
  _NavItem('Dashboard', Icons.grid_view_rounded),
  _NavItem('Projects', Icons.apartment_rounded),
  _NavItem('Tasks', Icons.check_circle_outline_rounded),
  _NavItem('Attendance', Icons.calendar_month_rounded),
  _NavItem('Workers', Icons.badge_outlined),
  _NavItem('Files', Icons.folder_outlined, Icons.folder_rounded),
  _NavItem('Notifications', Icons.notifications_outlined, Icons.notifications_rounded),
  _NavItem('AI Assistant', Icons.smart_toy_outlined),
];
const _settingsMenu = [
  _NavItem('Settings', Icons.settings_outlined),
];

final _pages = <Widget>[
  const DashboardPage(),   // 0 Dashboard
  const ProjectsPage(),    // 1 Projects
  const TasksPage(),       // 2 Tasks
  const AttendancePage(),  // 3 Attendance
  const WorkersPage(),     // 4 Workers
  const FilesPage(),       // 5 Files
  const NotificationsPage(), // 6 Notifications
  const AiChatPage(),      // 7 AI Assistant
  const SettingsPage(),    // 8 Settings
];

final _titles = [
  ..._mainMenu.map((e) => e.label),
  ..._settingsMenu.map((e) => e.label),
];

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int idx = 0;
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  String _currentProject = '';
  Map<String, dynamic> _user = {};
  bool _userLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    try {
      final data = await ApiService().me();
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
        final isWide = constraints.maxWidth >= 900;
        if (isWide) {
          return _WideLayout(
            idx: idx,
            currentProject: _currentProject,
            user: _user,
            onNav: (i) => _go(i),
            onLogout: _logout,
            onProjectChanged: (p) => setState(() => _currentProject = p),
          );
        }
        return _NarrowLayout(
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
  final int idx;
  final String currentProject;
  final Map<String, dynamic> user;
  final ValueChanged<int> onNav;
  final VoidCallback onLogout;
  final ValueChanged<String> onProjectChanged;

  const _WideLayout({
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
                Expanded(child: IndexedStack(index: idx, children: _pages)),
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
  final GlobalKey<ScaffoldState> scaffoldKey;
  final int idx;
  final String currentProject;
  final Map<String, dynamic> user;
  final bool userLoaded;
  final ValueChanged<int> onNav;
  final VoidCallback onLogout;
  final ValueChanged<String> onProjectChanged;

  const _NarrowLayout({
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
    const map = [0, 1, 2, 3, 4]; // Dashboard, Projects, Tasks, Attendance, Workers
    return map[bottomIdx];
  }

  int _pageToBottomIdx(int pageIdx) {
    if (pageIdx <= 3) return pageIdx;
    return 4; // all others map to "More"
  }

  void _showMoreSheet(BuildContext ctx, ValueChanged<int> onNav) {
    showModalBottomSheet(
      context: ctx,
      backgroundColor: Colors.transparent,
      builder: (_) => _MoreSheet(currentIdx: idx, onNav: onNav, onLogout: onLogout, user: user),
    );
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
          Text('BuildSmart',
              style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        ]),
        actions: [
          Stack(children: [
            IconButton(
              icon: const Icon(Icons.notifications_outlined, color: AppColors.textSecondary),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsPage())),
            ),
            Positioned(
              right: 8, top: 8,
              child: Container(width: 8, height: 8,
                  decoration: const BoxDecoration(color: AppColors.red, shape: BoxShape.circle)),
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
                  : const CircleAvatar(
                      radius: 16,
                      backgroundColor: AppColors.sidebarHover,
                      child: SizedBox(width: 12, height: 12,
                          child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.accent)),
                    ),
            ),
          ),
        ],
      ),
      body: IndexedStack(index: idx, children: _pages),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.bgCard,
          border: Border(top: BorderSide(color: AppColors.border)),
          boxShadow: [BoxShadow(color: Color(0x0A000000), blurRadius: 12, offset: Offset(0, -2))],
        ),
        child: SafeArea(
          child: SizedBox(
            height: 64,
            child: Row(
              children: List.generate(_bottomNavItems.length, (i) {
                final item = _bottomNavItems[i];
                final isMore = i == 4;
                final isSelected = isMore
                    ? idx >= 4
                    : _pageToBottomIdx(idx) == i;
                return Expanded(
                  child: _BottomNavBtn(
                    item: item,
                    selected: isSelected,
                    onTap: () {
                      if (isMore) {
                        _showMoreSheet(context, onNav);
                      } else {
                        onNav(_bottomToPageIdx(i));
                      }
                    },
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
    return InkWell(
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
          Text(
            item.label,
            style: GoogleFonts.outfit(
              fontSize: 14,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? AppColors.accent : AppColors.textMuted,
            ),
          ),
        ]),
      ),
    );
  }
}

// ──────────────── More Bottom Sheet ──────────────────
class _MoreSheet extends StatelessWidget {
  final int currentIdx;
  final ValueChanged<int> onNav;
  final VoidCallback onLogout;
  final Map<String, dynamic> user;
  const _MoreSheet({required this.currentIdx, required this.onNav, required this.onLogout, required this.user});

  @override
  Widget build(BuildContext context) {
    final userName = (user['full_name'] as String?) ?? 'User';
    final role = (user['role'] as String?) ?? '';
    final moreItems = [
      {'label': 'Workers', 'icon': Icons.badge_outlined, 'idx': 4},
      {'label': 'Files', 'icon': Icons.folder_outlined, 'idx': 5},
      {'label': 'Notifications', 'icon': Icons.notifications_outlined, 'idx': 6},
      {'label': 'Daily Reports', 'icon': Icons.description_outlined, 'idx': -1},
      {'label': 'Issues', 'icon': Icons.warning_amber_outlined, 'idx': -1},
      {'label': 'AI Assistant', 'icon': Icons.smart_toy_outlined, 'idx': 7},
      {'label': 'Settings', 'icon': Icons.settings_outlined, 'idx': 8},
    ];

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Handle
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            width: 36, height: 4,
            decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
          ),
          // User info
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            child: Row(children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: avatarColor(userName),
                child: Text(initials(userName),
                    style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(userName,
                    style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.textPrimary)),
                Text(role.replaceAll('_', ' '),
                    style: GoogleFonts.outfit(fontSize: 14, color: AppColors.textSecondary)),
              ])),
            ]),
          ),
          const Divider(height: 1, color: AppColors.border),
          // Menu items
          ...moreItems.map((item) => ListTile(
            leading: Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: AppColors.bgMain,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(item['icon'] as IconData, size: 20, color: AppColors.textSecondary),
            ),
            title: Text(item['label'] as String,
                style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
            onTap: () {
              Navigator.pop(context);
              final targetIdx = item['idx'] as int;
              if (targetIdx >= 0) {
                onNav(targetIdx);
              } else {
                // Feature coming soon
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('${item['label']} — Coming soon!'),
                  backgroundColor: AppColors.bgCard,
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 2),
                ));
              }
            },
          )),
          const Divider(height: 1, color: AppColors.border),
          ListTile(
            leading: Container(
              width: 38, height: 38,
              decoration: BoxDecoration(color: AppColors.redLight, borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.logout_rounded, size: 20, color: AppColors.red),
            ),
            title: Text('Log Out',
                style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.red)),
            onTap: () {
              Navigator.pop(context);
              onLogout();
            },
          ),
          const SizedBox(height: 8),
        ]),
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
                      showAiBadge: e.value.label == 'AI Assistant',
                      showNotificationBadge: e.value.label == 'Notifications',
                    )),
                _sectionLabel('SETTINGS'),
                ..._settingsMenu.asMap().entries.map((e) => _NavTile(
                      item: e.value,
                      selected: (_mainMenu.length + e.key) == idx,
                      onTap: () => onNav(_mainMenu.length + e.key),
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
                icon: const Icon(Icons.power_settings_new_rounded, color: AppColors.red, size: 19),
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
  final bool showAiBadge;
  final bool showNotificationBadge;

  const _NavTile({
    required this.item,
    required this.selected,
    required this.onTap,
    this.showAiBadge = false,
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
                child: Text(item.label,
                    style: GoogleFonts.outfit(
                        color: selected ? Colors.white : AppColors.textSidebar,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600)),
              ),
              if (showAiBadge)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(8)),
                  child: Text('AI',
                      style: GoogleFonts.outfit(
                          color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)),
                ),
              if (showNotificationBadge)
                Container(
                  width: 8, height: 8,
                  margin: const EdgeInsets.only(left: 2),
                  decoration: const BoxDecoration(color: AppColors.red, shape: BoxShape.circle),
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
      decoration: const BoxDecoration(
        color: AppColors.bgCard,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(children: [
        Expanded(
          child: Text(title,
              style: GoogleFonts.outfit(
                  fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        ),
        SizedBox(
          width: 220, height: 38,
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Search projects, workers...',
              hintStyle: GoogleFonts.outfit(fontSize: 14, color: AppColors.textMuted),
              prefixIcon: const Icon(Icons.search_rounded, size: 18, color: AppColors.textMuted),
              filled: true,
              fillColor: AppColors.bgMain,
              contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 14),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.border)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.border)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.accent, width: 1.4)),
            ),
          ),
        ),
        const SizedBox(width: 12),
        _ProjectChip(currentProject: currentProject, onChanged: onProjectChanged),
        const SizedBox(width: 12),
        Stack(children: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined, color: AppColors.textSecondary, size: 22),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsPage())),
          ),
          Positioned(
            right: 8, top: 8,
            child: Container(width: 8, height: 8,
                decoration: const BoxDecoration(color: AppColors.red, shape: BoxShape.circle)),
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
          const Icon(Icons.location_on_rounded, size: 14, color: AppColors.accent),
          const SizedBox(width: 5),
          Text(widget.currentProject.isEmpty ? 'All Projects' : widget.currentProject,
              style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          const SizedBox(width: 4),
          const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: AppColors.textMuted),
        ]),
      ),
    );
  }
}

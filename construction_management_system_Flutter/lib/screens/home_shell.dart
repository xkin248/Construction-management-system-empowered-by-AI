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
import 'daily_report_page.dart';
import 'issues_page.dart';
import 'settings_page.dart';
import 'profile_page.dart';

// ──────────────── Nav model ────────────────
class _NavItem {
  final String label;
  final IconData icon;
  const _NavItem(this.label, this.icon);
}

const _mainMenu = [
  _NavItem('Dashboard', Icons.grid_view_rounded),
  _NavItem('Projects', Icons.apartment_rounded),
  _NavItem('Tasks', Icons.check_circle_outline_rounded),
  _NavItem('Attendance', Icons.calendar_month_rounded),
  _NavItem('Workers', Icons.badge_outlined),
  _NavItem('AI Assistant', Icons.smart_toy_outlined),
];
const _settingsMenu = [
  _NavItem('Settings', Icons.settings_outlined),
];

// ⚠️ IMPORTANT: _pages must match index order of _mainMenu + _settingsMenu
final _pages = <Widget>[
  const DashboardPage(),   // 0 Dashboard
  const ProjectsPage(),    // 1 Projects
  const TasksPage(),       // 2 Tasks
  const AttendancePage(),  // 3 Attendance
  const WorkersPage(),     // 4 Workers
  const _AiAssistantPlaceholder(), // 5 AI Assistant
  const SettingsPage(),    // 6 Settings
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
  String _currentProject = 'KL Tower Block A';

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
            onNav: (i) => _go(i),
            onLogout: _logout,
            onProjectChanged: (p) => setState(() => _currentProject = p),
          );
        }
        return _NarrowLayout(
          scaffoldKey: _scaffoldKey,
          idx: idx,
          currentProject: _currentProject,
          onNav: (i) => _go(i, fromDrawer: true),
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
  final ValueChanged<int> onNav;
  final VoidCallback onLogout;
  final ValueChanged<String> onProjectChanged;

  const _WideLayout({
    required this.idx,
    required this.currentProject,
    required this.onNav,
    required this.onLogout,
    required this.onProjectChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          _Sidebar(idx: idx, onNav: onNav, onLogout: onLogout),
          Expanded(
            child: Column(
              children: [
                _TopBar(
                  title: _titles[idx],
                  currentProject: currentProject,
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

// ──────────────── Narrow (Drawer) Layout ────────────────
class _NarrowLayout extends StatelessWidget {
  final GlobalKey<ScaffoldState> scaffoldKey;
  final int idx;
  final String currentProject;
  final ValueChanged<int> onNav;
  final VoidCallback onLogout;
  final ValueChanged<String> onProjectChanged;

  const _NarrowLayout({
    required this.scaffoldKey,
    required this.idx,
    required this.currentProject,
    required this.onNav,
    required this.onLogout,
    required this.onProjectChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: scaffoldKey,
      appBar: AppBar(
        backgroundColor: AppColors.bgCard,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded, color: AppColors.textPrimary),
          onPressed: () => scaffoldKey.currentState?.openDrawer(),
        ),
        title: Text(_titles[idx]),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined, color: AppColors.textSecondary),
            onPressed: () {},
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfilePage())),
              child: CircleAvatar(
                radius: 16,
                backgroundColor: AppColors.accent,
                child: Text('AR', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11)),
              ),
            ),
          ),
        ],
      ),
      drawer: Drawer(
        backgroundColor: AppColors.sidebarBg,
        width: AppColors.sidebarWidth,
        child: _SidebarContent(idx: idx, onNav: onNav, onLogout: onLogout),
      ),
      body: IndexedStack(index: idx, children: _pages),
    );
  }
}

// ──────────────── Sidebar (permanent) ────────────────
class _Sidebar extends StatelessWidget {
  final int idx;
  final ValueChanged<int> onNav;
  final VoidCallback onLogout;

  const _Sidebar({required this.idx, required this.onNav, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: AppColors.sidebarWidth,
      child: Material(
        color: AppColors.sidebarBg,
        child: _SidebarContent(idx: idx, onNav: onNav, onLogout: onLogout),
      ),
    );
  }
}

class _SidebarContent extends StatelessWidget {
  final int idx;
  final ValueChanged<int> onNav;
  final VoidCallback onLogout;

  const _SidebarContent({required this.idx, required this.onNav, required this.onLogout});

  @override
  Widget build(BuildContext context) {
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
                      style: GoogleFonts.outfit(color: AppColors.textSidebarMuted, fontSize: 10)),
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
            child: FutureBuilder<Map>(
              future: ApiService().me(),
              builder: (ctx, snap) {
                final name = (snap.data?['full_name'] as String?) ?? '...';
                final role = (snap.data?['role'] as String?) ?? '';
                return Row(children: [
                  initialsAvatar(name.isNotEmpty ? name : '?', radius: 16),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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

  Widget _sectionLabel(String s) => Padding(
        padding: const EdgeInsets.fromLTRB(10, 14, 10, 4),
        child: Text(s,
            style: GoogleFonts.outfit(
                color: AppColors.textSidebarMuted,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8)),
      );
}

class _NavTile extends StatelessWidget {
  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;
  final bool showAiBadge;

  const _NavTile({
    required this.item,
    required this.selected,
    required this.onTap,
    this.showAiBadge = false,
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
                          color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
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
  final ValueChanged<String> onProjectChanged;

  const _TopBar({
    required this.title,
    required this.currentProject,
    required this.onProjectChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: AppColors.bgCard,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(children: [
        // Page title
        Expanded(
          child: Text(title,
              style: GoogleFonts.outfit(
                  fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        ),
        // Search bar
        SizedBox(
          width: 220,
          height: 38,
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Search projects, workers...',
              hintStyle: GoogleFonts.outfit(fontSize: 12.5, color: AppColors.textMuted),
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
        // Project selector chip
        _ProjectChip(currentProject: currentProject, onChanged: onProjectChanged),
        const SizedBox(width: 12),
        // Notification bell
        Stack(
          children: [
            IconButton(
              icon: const Icon(Icons.notifications_outlined, color: AppColors.textSecondary, size: 22),
              onPressed: () {},
            ),
            Positioned(
              right: 8,
              top: 8,
              child: Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(color: AppColors.red, shape: BoxShape.circle),
              ),
            ),
          ],
        ),
        // Avatar
        GestureDetector(
          onTap: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const ProfilePage())),
          child: CircleAvatar(
            radius: 17,
            backgroundColor: AppColors.accent,
            child: Text('AR',
                style: GoogleFonts.outfit(
                    color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11)),
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
          Text(widget.currentProject,
              style: GoogleFonts.outfit(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          const SizedBox(width: 4),
          const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: AppColors.textMuted),
        ]),
      ),
    );
  }
}

// ──────────────── AI Assistant Placeholder ────────────────
class _AiAssistantPlaceholder extends StatelessWidget {
  const _AiAssistantPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.12), shape: BoxShape.circle),
          child: const Icon(Icons.smart_toy_outlined, size: 36, color: AppColors.accent),
        ),
        const SizedBox(height: 16),
        Text('AI Assistant',
            style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        const SizedBox(height: 6),
        Text('Coming soon — Gemini-powered construction intelligence',
            style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textMuted)),
      ]),
    );
  }
}

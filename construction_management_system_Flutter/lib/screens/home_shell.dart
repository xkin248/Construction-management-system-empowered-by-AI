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
import '../l10n/app_strings.dart';
import '../widgets/app_settings_actions.dart';
import 'worker_home_shell.dart';
import '../widgets/a11y.dart';

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€ Nav model â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _NavItem {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  const _NavItem(this.label, this.icon, [IconData? active])
      : activeIcon = active ?? icon;
}

/// Translate navigation labels (English / ä¸­æ–‡ / Bahasa Melayu).
String _navT(String en) {
  const zh = {
    'Dashboard': 'ä»ªè¡¨ç›˜', 'Projects': 'é¡¹ç›®', 'Tasks': 'ä»»åŠ¡', 'Attendance': 'è€ƒå‹¤',
    'Workers': 'å·¥äºº', 'Files': 'æ–‡ä»¶', 'Notifications': 'é€šçŸ¥', 'More': 'æ›´å¤š',
    'My Dashboard': 'æˆ‘çš„ä»ªè¡¨ç›˜', 'My Attendance': 'æˆ‘çš„è€ƒå‹¤', 'Profile': 'ä¸ªäººèµ„æ–™',
  };
  const ms = {
    'Dashboard': 'Papan Pemuka', 'Projects': 'Projek', 'Tasks': 'Tugas', 'Attendance': 'Kehadiran',
    'Workers': 'Pekerja', 'Files': 'Fail', 'Notifications': 'Notifikasi', 'More': 'Lagi',
    'My Dashboard': 'Papan Pemuka Saya', 'My Attendance': 'Kehadiran Saya', 'Profile': 'Profil',
  };
  return AppSettings.t(en, zh[en], ms[en]);
}

/// Bottom navigation is capped at 5 destinations for first-time users:
/// 4 core pages + a "More" sheet that groups every secondary entry
/// (Files / Attendance / Notifications / Profile). Nothing is unreachable.
const _bottomNavItems = [
  _NavItem('Dashboard', Icons.grid_view_outlined, Icons.grid_view_rounded),
  _NavItem('Projects', Icons.apartment_outlined, Icons.apartment_rounded),
  _NavItem('Tasks', Icons.check_circle_outline_rounded, Icons.check_circle_rounded),
  _NavItem('Workers', Icons.badge_outlined, Icons.badge_rounded),
  _NavItem('More', Icons.widgets_outlined, Icons.widgets_rounded),
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
  // Notifications(6) is opened as a full-screen page (push) from the shell,
  // so it keeps its own TabBar AppBar and never nests inside this Scaffold.
];

final _titles = _mainMenu.map((e) => e.label).toList();

/// Sidebar grouping: 4 core pages on top, everything else under "More tools".
/// Page indices in [_mainMenu] are unchanged so navigation stays wired.
const _coreMenuIdx = [0, 1, 2, 4]; // Dashboard / Projects / Tasks / Workers
const _extraMenuIdx = [5, 3, 6]; // Files / Attendance / Notifications

/// One-line explanation shown under each navigation label (new-user guidance).
String? _navHint(String label) {
  const keys = {
    'Dashboard': 'nav.hint.dashboard',
    'Projects': 'nav.hint.projects',
    'Tasks': 'nav.hint.tasks',
    'Workers': 'nav.hint.workers',
    'Attendance': 'nav.hint.attendance',
    'Files': 'nav.hint.files',
    'Notifications': 'nav.hint.notifications',
  };
  final k = keys[label];
  return k == null ? null : AppStrings.t(k);
}

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
    if (i == 6) {
      // Notifications has its own TabBar AppBar -> open as full screen page
      // instead of nesting inside this shell (avoids double app bar).
      Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsPage()));
      return;
    }
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

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€ Wide (Sidebar) Layout â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€ Narrow (Bottom Nav) Layout â”€â”€â”€â”€â”€â”€â”€â”€â”€
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

  /// Bottom nav index â†’ page index for the 4 core tabs.
  /// Index 4 is the "More" sheet and never maps to a page.
  static const _bottomPages = [0, 1, 2, 4];

  int _pageToBottomIdx(int pageIdx) {
    if (pageIdx <= 2) return pageIdx; // Dashboard(0) / Projects(1) / Tasks(2)
    if (pageIdx == 4) return 3;       // Workers â†’ bottom nav index 3
    // Files(5) / Attendance(3) are opened from "More", so that tab stays lit.
    return 4;
  }

  /// "More" sheet â€” groups every secondary entry so the bottom bar stays at 5.
  void _openMoreSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.transparent,
      builder: (sheetCtx) => Container(
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
          border: Border.all(color: AppColors.border),
        ),
        child: SafeArea(
          top: false,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(color: AppColors.border, borderRadius: AppRadius.rPill),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(AppStrings.t('nav.moreTitle'),
                        style: GoogleFonts.inter(
                            fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                    const SizedBox(height: 2),
                    Text(AppStrings.t('nav.moreSub'),
                        style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted)),
                  ]),
                ),
              ]),
            ),
            _MoreTile(
              icon: Icons.folder_outlined,
              label: _navT('Files'),
              hint: AppStrings.t('nav.hint.files'),
              onTap: () {
                Navigator.pop(sheetCtx);
                onNav(5);
              },
            ),
            _MoreTile(
              icon: Icons.calendar_month_rounded,
              label: _navT('Attendance'),
              hint: AppStrings.t('nav.hint.attendance'),
              onTap: () {
                Navigator.pop(sheetCtx);
                onNav(3);
              },
            ),
            _MoreTile(
              icon: Icons.notifications_outlined,
              label: _navT('Notifications'),
              hint: AppStrings.t('nav.hint.notifications'),
              showBadge: true,
              onTap: () {
                Navigator.pop(sheetCtx);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsPage()));
              },
            ),
            _MoreTile(
              icon: Icons.person_outline_rounded,
              label: _navT('Profile'),
              hint: AppStrings.t('nav.hint.profile'),
              onTap: () {
                Navigator.pop(sheetCtx);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfilePage()));
              },
            ),
            const SizedBox(height: 8),
          ]),
        ),
      ),
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
        scrolledUnderElevation: 0.5,
        surfaceTintColor: AppColors.transparent,
        shape: Border(bottom: BorderSide(color: AppColors.border)),
        centerTitle: false,
        title: Row(children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(color: AppColors.accent, borderRadius: AppRadius.rXs),
            child: const Center(child: Icon(Icons.construction_rounded, color: AppColors.accentInk, size: 15)),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('BuildSmart',
                style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            Text(_navT(_titles[idx.clamp(0, _titles.length - 1)]),
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textMuted)),
          ]),
        ]),
        actions: [
          const AppSettingsActions(),
          Stack(children: [
            IconButton(
              icon: Icon(Icons.notifications_outlined, color: AppColors.textSecondary),
              tooltip: _navT('Notifications'),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsPage())),
            ),
            Positioned(
              right: 8, top: 8,
              child: Container(width: 8, height: 8,
                  decoration: BoxDecoration(color: AppColors.red, shape: BoxShape.circle)),
            ),
          ]),
          semanticTapTarget(
            label: _navT('Profile'),
            child:           GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfilePage())),
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: userLoaded
                  ? CircleAvatar(
                      radius: 16,
                      backgroundColor: avatarColor(userName.isNotEmpty ? userName : 'U'),
                      child: Text(initStr,
                          style: GoogleFonts.inter(color: AppColors.onAccent, fontWeight: FontWeight.w800, fontSize: 13)),
                    )
                  : CircleAvatar(
                      radius: 16,
                      backgroundColor: AppColors.sidebarHover,
                      child: SizedBox(width: 12, height: 12,
                          child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.accent)),
                    ),
            ),
          )),
        ],
      ),
      body: pages,
      // Floating rounded nav bar (Bento style). Navigation indices and page
      // switching stay identical; only the surface styling changed.
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: AppRadius.rLg,
            border: Border.all(color: AppColors.border),
            boxShadow: AppShadows.md,
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 64,
              child: Row(
                children: List.generate(_bottomNavItems.length, (i) {
                  final item = _bottomNavItems[i];
                  final isSelected = _pageToBottomIdx(idx) == i;
                  return Expanded(
                    child: _BottomNavBtn(
                      item: item,
                      selected: isSelected,
                      onTap: () => i == _bottomPages.length
                          ? _openMoreSheet(context)
                          : onNav(_bottomPages[i]),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€ Bottom Nav Button â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _BottomNavBtn extends StatelessWidget {
  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;
  const _BottomNavBtn({required this.item, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return semanticTapTarget(
      label: _navT(item.label),
      selected: selected,
      child: Tooltip(
      message: _navT(item.label),
      child: InkWell(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppDuration.base,
        curve: AppDuration.ease,
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          // Selected item gets a pill highlight behind the icon.
          AnimatedContainer(
            duration: AppDuration.base,
            curve: AppDuration.ease,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: selected ? AppColors.accentLight : AppColors.transparent,
              borderRadius: AppRadius.rPill,
            ),
            child: AnimatedSwitcher(
              duration: AppDuration.base,
              child: Icon(
                selected ? item.activeIcon : item.icon,
                key: ValueKey(selected),
                size: 20,
                color: selected ? AppColors.accent : AppColors.textMuted,
              ),
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              _navT(item.label),
              maxLines: 1,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? AppColors.accent : AppColors.textMuted,
              ),
            ),
          ),
        ]),
      ),
      ),
    ));
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€ Sidebar (permanent) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
            child: Row(children: [
              Container(
                width: 38, height: 38,
                decoration: BoxDecoration(color: AppColors.accent, borderRadius: AppRadius.rMd),
                child: const Center(child: Icon(Icons.construction_rounded, color: AppColors.accentInk, size: 20)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('BuildSmart',
                      style: GoogleFonts.inter(color: AppColors.accentInk, fontWeight: FontWeight.w800, fontSize: 15)),
                  Text('AI Construction System',
                      style: GoogleFonts.inter(color: AppColors.textSidebarMuted, fontSize: 11.5)),
                ]),
              ),
            ]),
          ),
          Container(height: 1, color: AppColors.sidebarHover),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                _sectionLabel(AppStrings.t('nav.groupMain')),
                ..._coreMenuIdx.map((i) => _NavTile(
                      item: _mainMenu[i],
                      selected: i == idx,
                      hint: _navHint(_mainMenu[i].label),
                      onTap: () => onNav(i),
                    )),
                _sectionLabel(AppStrings.t('nav.groupMore')),
                ..._extraMenuIdx.map((i) => _NavTile(
                      item: _mainMenu[i],
                      selected: i == idx,
                      hint: _navHint(_mainMenu[i].label),
                      onTap: () => onNav(i),
                      showNotificationBadge: _mainMenu[i].label == 'Notifications',
                    )),
              ],
            ),
          ),
          Container(height: 1, color: AppColors.sidebarHover),
          // User row
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              initialsAvatar(userName.isNotEmpty ? userName : '?', radius: 16),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(userName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                          color: AppColors.onAccent, fontWeight: FontWeight.w700, fontSize: 14)),
                  Text(role.replaceAll('_', ' '),
                      style: GoogleFonts.inter(
                          color: AppColors.textSidebarMuted, fontSize: 12)),
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
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 4),
        child: Text(s,
            style: GoogleFonts.inter(
                color: AppColors.textSidebarMuted,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.0)),
      );
}

class _NavTile extends StatelessWidget {
  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;
  final bool showNotificationBadge;

  /// Optional one-line explanation for first-time users.
  final String? hint;

  const _NavTile({
    required this.item,
    required this.selected,
    required this.onTap,
    this.showNotificationBadge = false,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return semanticTapTarget(
      label: hint == null ? _navT(item.label) : '${_navT(item.label)}. $hint',
      selected: selected,
      child: Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected ? AppColors.accent : AppColors.transparent,
        borderRadius: AppRadius.rSm,
        child: InkWell(
          borderRadius: AppRadius.rSm,
          hoverColor: selected ? AppColors.transparent : AppColors.sidebarHover,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(children: [
              Icon(item.icon, size: 18, color: selected ? AppColors.onAccent : AppColors.textSidebar),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_navT(item.label),
                      style: GoogleFonts.inter(
                          color: selected ? AppColors.onAccent : AppColors.textSidebar,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600)),
                  if (hint != null)
                    Text(hint!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                            color: selected
                                ? AppColors.onAccent.withValues(alpha: 0.7)
                                : AppColors.textSidebarMuted,
                            fontSize: 11)),
                ]),
              ),
              if (showNotificationBadge)
                Container(
                  width: 8, height: 8,
                  margin: const EdgeInsets.only(left: 4),
                  decoration: BoxDecoration(color: AppColors.red, shape: BoxShape.circle),
                ),
            ]),
          ),
        ),
      ),
    ));
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€ Top Bar â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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
              style: GoogleFonts.inter(
                  fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        ),
        SizedBox(
          width: 220, height: 38,
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Search projects, workers...',
              hintStyle: GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted),
              prefixIcon: Icon(Icons.search_rounded, size: 18, color: AppColors.textMuted),
              filled: true,
              fillColor: AppColors.bgMain,
              contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
              border: OutlineInputBorder(
                  borderRadius: AppRadius.rSm,
                  borderSide: BorderSide(color: AppColors.border)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: AppRadius.rSm,
                  borderSide: BorderSide(color: AppColors.border)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: AppRadius.rSm,
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
            tooltip: _navT('Notifications'),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsPage())),
          ),
          Positioned(
            right: 8, top: 8,
            child: Container(width: 8, height: 8,
                decoration: BoxDecoration(color: AppColors.red, shape: BoxShape.circle)),
          ),
        ]),
        semanticTapTarget(
          label: _navT('Profile'),
          child:         GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfilePage())),
          child: CircleAvatar(
            radius: 17,
            backgroundColor: userName.isNotEmpty ? avatarColor(userName) : AppColors.accent,
            child: Text(initStr,
                style: GoogleFonts.inter(
                    color: AppColors.onAccent, fontWeight: FontWeight.w800, fontSize: 13)),
          ),
        )),
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
      tooltip: 'Select project',
      onSelected: widget.onChanged,
      itemBuilder: (_) => _projects.map((p) => PopupMenuItem(value: p, child: Text(p))).toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.bgMain,
          border: Border.all(color: AppColors.border),
          borderRadius: AppRadius.rSm,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.location_on_rounded, size: 14, color: AppColors.accent),
          const SizedBox(width: 4),
          Text(widget.currentProject.isEmpty ? 'All Projects' : widget.currentProject,
              style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          const SizedBox(width: 4),
          Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: AppColors.textMuted),
        ]),
      ),
    );
  }
}

// ──────────────── "More" sheet row ────────────────
class _MoreTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String hint;
  final VoidCallback onTap;
  final bool showBadge;

  const _MoreTile({
    required this.icon,
    required this.label,
    required this.hint,
    required this.onTap,
    this.showBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    return semanticTapTarget(
      label: '$label. $hint',
      child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Material(
        color: AppColors.transparent,
        borderRadius: AppRadius.rSm,
        child: InkWell(
          borderRadius: AppRadius.rSm,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            child: Row(children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.accentLight,
                  borderRadius: AppRadius.rSm,
                ),
                child: Icon(icon, size: 19, color: AppColors.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label,
                      style: GoogleFonts.inter(
                          fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text(hint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(fontSize: 11.5, color: AppColors.textMuted)),
                ]),
              ),
              if (showBadge)
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(color: AppColors.red, shape: BoxShape.circle),
                ),
              Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.textMuted),
            ]),
          ),
        ),
      ),
    ));
  }
}